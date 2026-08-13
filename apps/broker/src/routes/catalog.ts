import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { query } from '../db.js';
import { requireCustomer, customerId } from '../auth/jwt.js';
import { rmForOrNull } from '../clients/rmApi.js';

export default async function catalogRoutes(app: FastifyInstance) {
  /** Estaciones con precios vigentes por grado. */
  app.get('/v1/stations', { preHandler: requireCustomer }, async (req) => {
    // Sólo las estaciones del operador (tenant) al que pertenece el cliente.
    const stations = await query(
      `SELECT s.id, s.code, s.name, s.address, s.town, s.lat, s.lng,
              s.is_open, s.has_minimarket, s.volume_unit, s.currency,
              (SELECT count(*) FROM pumps p WHERE p.station_id = s.id) AS pumps
         FROM stations s
         JOIN customers c ON c.tenant_id = s.tenant_id
        WHERE c.id = $1 AND s.status = 'active'
        ORDER BY s.name`,
      [customerId(req)],
    );
    const prices = await query(
      `SELECT station_id, code, display_name, price FROM v_current_fuel_prices ORDER BY code`,
    );
    return stations.map((s) => ({
      ...s,
      fuels: prices
        .filter((p) => p.station_id === s.id)
        .map((p) => ({ code: p.code, name: p.display_name, pricePerLiter: p.price })),
    }));
  });

  /** Catálogo del minimarket de una estación (espejo del POS). */
  app.get('/v1/stations/:id/products', { preHandler: requireCustomer }, async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    return query(
      `SELECT id, item_code, name, detail, category, price, aisle,
              (on_hand IS NULL OR on_hand > 0) AS in_stock
         FROM products
        WHERE station_id = $1 AND active
        ORDER BY category, name`,
      [id],
    );
  });

  /** Estado de bombas visible al cliente (para escoger surtidor). */
  app.get('/v1/stations/:id/pumps', { preHandler: requireCustomer }, async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    return query(
      `SELECT p.id, p.number, p.status, p.status_at,
              EXISTS (SELECT 1 FROM orders o
                       WHERE o.pump_id = p.id
                         AND o.status IN ('arrived','dispensing')) AS busy
         FROM pumps p
        WHERE p.station_id = $1
        ORDER BY p.number`,
      [id],
    );
  });

  /** Perfil + cartera + vehículos del cliente autenticado. */
  app.get('/v1/me', { preHandler: requireCustomer }, async (req) => {
    const id = customerId(req);
    const rows = await query(
      `SELECT c.id, c.phone, c.full_name, c.email, c.photo_url, c.photo_verified_at,
              w.balance, w.currency
         FROM customers c
         LEFT JOIN wallets w ON w.customer_id = c.id
        WHERE c.id = $1`,
      [id],
    );
    const vehicles = await query('SELECT id, plate, make_model, color, tank_liters, is_default FROM vehicles WHERE customer_id = $1', [id]);
    const cards = await query('SELECT id, brand, last4, is_default FROM payment_methods WHERE customer_id = $1', [id]);
    return { ...(rows[0] ?? {}), vehicles, paymentMethods: cards };
  });

  /** Recarga de cartera (en producción la dispara el procesador). */
  app.post('/v1/me/wallet/topup', { preHandler: requireCustomer }, async (req) => {
    const id = customerId(req);
    const { amount } = z.object({ amount: z.number().positive().max(500) }).parse(req.body);
    const w = await query<{ id: string; balance: number }>(
      'UPDATE wallets SET balance = balance + $2, updated_at = now() WHERE customer_id = $1 RETURNING id, balance',
      [id, amount],
    );
    const wallet = w[0]!;
    await query(
      `INSERT INTO wallet_entries (wallet_id, kind, amount, balance_after, memo)
       VALUES ($1,'topup',$2,$3,'Recarga desde la app')`,
      [wallet.id, amount, wallet.balance],
    );
    return { balance: wallet.balance };
  });

  /**
   * Sincroniza el catálogo del minimarket desde Retail Manager
   * (GetAllProducts). Se usa al abrir estación o desde el panel admin.
   */
  app.post('/v1/stations/:id/sync-products', async (req, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const rm = await rmForOrNull(id);
    if (!rm) return reply.code(424).send({ error: 'no_rm_integration', message: 'La estación no tiene enlace rm_api configurado' });
    const res = await rm.getAllProducts({ active: true });
    if (!res.ok || !Array.isArray(res.data)) {
      return reply.code(502).send({ error: 'rm_unavailable', detail: res.raw.slice(0, 300) });
    }
    let upserts = 0;
    for (const raw of res.data as Record<string, unknown>[]) {
      const itemCode = String(raw.ItemCode ?? raw.Referencia ?? '').trim();
      const name = String(raw.Description ?? raw.Descripcion ?? raw.Name ?? '').trim();
      const price = Number(raw.Price ?? raw.Precio ?? 0);
      if (!itemCode || !name) continue;
      await query(
        `INSERT INTO products (station_id, item_code, barcode, name, department, category, price, on_hand, active, synced_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,true, now())
         ON CONFLICT (station_id, item_code) DO UPDATE
           SET name = EXCLUDED.name, price = EXCLUDED.price, barcode = EXCLUDED.barcode,
               department = EXCLUDED.department, category = EXCLUDED.category,
               on_hand = EXCLUDED.on_hand, active = true, synced_at = now()`,
        [
          id,
          itemCode,
          raw.Barcode ?? null,
          name,
          raw.Department ?? null,
          raw.Category ?? raw.Categoria ?? null,
          Number.isFinite(price) ? price : 0,
          raw.OnHand ?? null,
        ],
      );
      upserts++;
    }
    return { upserts };
  });
}
