import { one, query } from '../db.js';
import { rmForOrNull, type RmInvoice } from '../clients/rmApi.js';
import { getRules } from '../tenancy.js';
import { logEvent } from '../domain/orders.js';
import { config } from '../config.js';

/**
 * Outbox hacia Retail Manager. Toda escritura al POS pasa por aquí, y cada
 * entrada recuerda a qué estación pertenece: el worker resuelve el enlace
 * `rm_api` de esa estación al momento de enviar. Si un POS está caído sólo
 * se reintenta el de esa estación.
 */

const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

export async function queueInvoice(orderId: string) {
  const o = await one<any>(
    `SELECT o.*, e.rm_user_id, c.rm_client_number, fp.display_name AS fuel_name, fp.rm_product_id
       FROM orders o
       LEFT JOIN tasks t ON t.order_id = o.id
       LEFT JOIN employees e ON e.id = t.employee_id
       JOIN customers c ON c.id = o.customer_id
       LEFT JOIN fuel_products fp ON fp.id = o.fuel_product_id
      WHERE o.id = $1`,
    [orderId],
  );
  if (!o) return;

  const rules = await getRules(o.station_id);
  const rm = await rmForOrNull(o.station_id);
  const items = await query<any>(
    'SELECT item_code, name, qty, unit_price, line_total FROM order_items WHERE order_id = $1',
    [orderId],
  );

  const fuelAmount = round2(Number(o.dispensed_amount));
  const itemsAmount = round2(Number(o.items_amount));

  // IVU por estación: normalmente el combustible no lleva IVU y los
  // artículos sí (PR: 10.5% estatal + 1% municipal).
  const taxableBase = (rules.itemsTaxable ? itemsAmount : 0) + (rules.fuelTaxable ? fuelAmount : 0);
  const stateTax = round2(taxableBase * rules.stateTaxRate);
  const cityTax = round2(taxableBase * rules.cityTaxRate);
  const subtotal = round2(fuelAmount + itemsAmount);
  const total = round2(subtotal + stateTax + cityTax);

  const invoice: RmInvoice = {
    Factura: rules.invoiceSeries,
    OrdenNumero: o.code,
    Cliente: o.rm_client_number ?? rules.defaultRmClient,
    Fecha: new Date().toISOString().slice(0, 10),
    Vendedor: String(o.rm_user_id ?? rm?.userId ?? config.defaults.rmUserId),
    Subtotal: subtotal,
    Descuento: 0,
    Total: total,
    CityTax: cityTax,
    StateTax: stateTax,
    PaidCredit: total,
    Items: [
      ...(fuelAmount > 0
        ? [
            {
              ProductCode: o.rm_product_id ? String(o.rm_product_id) : (rm?.fuelProductCode ?? 'FUEL'),
              Description: `${o.fuel_name ?? 'Combustible'} · ${Number(o.dispensed_volume).toFixed(3)} L`,
              Quantity: Number(Number(o.dispensed_volume).toFixed(3)),
              Price: Number(o.price_per_unit ?? 0),
            },
          ]
        : []),
      ...items.map((i) => ({
        ProductCode: i.item_code,
        Description: i.name,
        Quantity: Number(i.qty),
        Price: Number(i.unit_price),
      })),
    ],
  };

  await query(
    `INSERT INTO rm_outbox (order_id, endpoint, payload, status, next_try_at)
     VALUES ($1,'ImportExternalInvoice',$2,'pending', now())`,
    [orderId, JSON.stringify(invoice)],
  );

  // El total facturado puede traer impuestos que la retención no cubría:
  // lo dejamos en la bitácora para conciliación.
  if (total > Number(o.final_amount ?? subtotal)) {
    await logEvent(orderId, 'invoice_tax_delta', 'system', {
      captured: o.final_amount,
      invoiced: total,
      stateTax,
      cityTax,
    });
  }
}

async function drain() {
  const rows = await query<any>(
    `SELECT b.id, b.order_id, b.endpoint, b.payload, b.attempts, o.station_id
       FROM rm_outbox b
       LEFT JOIN orders o ON o.id = b.order_id
      WHERE b.status = 'pending' AND b.next_try_at <= now()
      ORDER BY b.id LIMIT 10`,
  );

  for (const row of rows) {
    const rm = row.station_id ? await rmForOrNull(row.station_id) : null;
    let ok = false;
    let raw = '';
    let data: unknown = null;

    if (!rm) {
      raw = 'la estación no tiene enlace rm_api habilitado';
    } else if (row.endpoint === 'ImportExternalInvoice') {
      const res = await rm.importExternalInvoice(row.payload as RmInvoice);
      ok = res.ok;
      raw = res.raw;
      data = res.data;
    } else if (row.endpoint === 'FuelSetPrice') {
      const p = row.payload as { grade: number; servLevel: number; tier1: number; tier2?: number };
      const res = await rm.fuelSetPrice(p);
      ok = res.ok;
      raw = res.raw;
      data = res.data;
    } else {
      raw = `endpoint no soportado: ${row.endpoint}`;
    }

    if (ok) {
      await query("UPDATE rm_outbox SET status = 'sent', sent_at = now(), response = $2 WHERE id = $1", [
        row.id,
        JSON.stringify(data ?? {}),
      ]);
      const invoiceNumber = extractInvoiceNumber(data);
      if (row.order_id && invoiceNumber) {
        await query('UPDATE orders SET rm_invoice_number = $2 WHERE id = $1', [row.order_id, invoiceNumber]);
      }
      if (row.order_id) await logEvent(row.order_id, 'rm_invoice_sent', 'rm', { invoiceNumber });
    } else {
      const attempts = Number(row.attempts) + 1;
      const dead = attempts >= 12;
      const backoffSec = Math.min(600, 2 ** attempts);
      await query(
        `UPDATE rm_outbox
            SET status = $2, attempts = $3, last_error = $4,
                next_try_at = now() + ($5 || ' seconds')::interval
          WHERE id = $1`,
        [row.id, dead ? 'dead' : 'pending', attempts, raw.slice(0, 500), backoffSec],
      );
      if (row.order_id) await logEvent(row.order_id, 'rm_invoice_retry', 'rm', { attempts, error: raw.slice(0, 200) });
    }
  }
}

function extractInvoiceNumber(data: unknown): string | null {
  if (!data || typeof data !== 'object') return null;
  const o = data as Record<string, unknown>;
  for (const k of ['InvoiceNumber', 'Factura', 'Numero', 'invoiceNumber']) {
    const v = o[k];
    if (typeof v === 'string' && v.trim()) return v.trim();
    if (typeof v === 'number') return String(v);
  }
  return null;
}

export function startOutboxWorker() {
  const tick = async () => {
    try {
      await drain();
    } catch (e) {
      console.error('[outbox]', (e as Error).message);
    }
  };
  const timer = setInterval(tick, config.rules.outboxPollMs);
  void tick();
  return () => clearInterval(timer);
}
