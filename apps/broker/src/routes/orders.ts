import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { one, oneOrFail, query, tx } from '../db.js';
import { customerId, requireCustomer } from '../auth/jwt.js';
import { rmFor } from '../clients/rmApi.js';
import { captureHold, placeHold, releaseHold } from '../domain/payments.js';
import { currentPrice, litersFor } from '../domain/pricing.js';
import { logEvent, nextOrderCode, round2, totals, transition } from '../domain/orders.js';
import { publishStation } from '../realtime/hub.js';

export default async function orderRoutes(app: FastifyInstance) {
  /** Crea el borrador de orden: estación, grado, techo y artículos. */
  app.post('/v1/orders', { preHandler: requireCustomer }, async (req, reply) => {
    const cid = customerId(req);
    const body = z
      .object({
        stationId: z.string().uuid(),
        fuelCode: z.string().min(2),
        capAmount: z.number().min(5).max(500),
        vehicleId: z.string().uuid().optional(),
        items: z
          .array(z.object({ itemCode: z.string(), qty: z.number().positive().max(50) }))
          .default([]),
      })
      .parse(req.body);

    const fuel = await oneOrFail<{ id: string; display_name: string }>(
      'SELECT id, display_name FROM fuel_products WHERE station_id = $1 AND code = $2',
      [body.stationId, body.fuelCode],
      'Grado de combustible no configurado en esta estación',
    );
    const price = await currentPrice(fuel.id);
    if (price === null) return reply.code(409).send({ error: 'no_price', message: 'Sin precio vigente' });

    const vehicle =
      body.vehicleId ??
      (
        await one<{ id: string }>(
          'SELECT id FROM vehicles WHERE customer_id = $1 ORDER BY is_default DESC, created_at LIMIT 1',
          [cid],
        )
      )?.id ??
      null;

    const order = await tx(async (c) => {
      const code = await nextOrderCode();
      const o = await c.query(
        `INSERT INTO orders (code, station_id, customer_id, vehicle_id, fuel_product_id,
                             price_per_unit, cap_amount, status)
         VALUES ($1,$2,$3,$4,$5,$6,$7,'draft')
         RETURNING id, code, edge_transaction_uuid`,
        [code, body.stationId, cid, vehicle, fuel.id, price, round2(body.capAmount)],
      );
      const orderId = o.rows[0].id as string;

      let itemsAmount = 0;
      for (const line of body.items) {
        const p = await c.query(
          'SELECT id, item_code, name, price FROM products WHERE station_id = $1 AND item_code = $2 AND active',
          [body.stationId, line.itemCode],
        );
        const prod = p.rows[0];
        if (!prod) continue;
        const total = round2(Number(prod.price) * line.qty);
        itemsAmount += total;
        await c.query(
          `INSERT INTO order_items (order_id, product_id, item_code, name, qty, unit_price, line_total)
           VALUES ($1,$2,$3,$4,$5,$6,$7)`,
          [orderId, prod.id, prod.item_code, prod.name, line.qty, prod.price, total],
        );
      }
      const t = totals({ capAmount: body.capAmount, itemsAmount });
      await c.query('UPDATE orders SET items_amount = $2, authorized_amount = $3 WHERE id = $1', [
        orderId,
        t.itemsAmount,
        t.authorizedAmount,
      ]);
      return { id: orderId, code: o.rows[0].code as string, edge: o.rows[0].edge_transaction_uuid as string };
    });

    await logEvent(order.id, 'created', `customer:${cid}`, { capAmount: body.capAmount });
    return reply.code(201).send(await fetchOrder(order.id));
  });

  /** Autoriza la retención (techo + artículos). No cobra. */
  app.post('/v1/orders/:id/authorize', { preHandler: requireCustomer }, async (req, reply) => {
    const cid = customerId(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const body = z.object({ paymentMethodId: z.string().uuid().optional() }).parse(req.body ?? {});

    const o = await oneOrFail<any>(
      'SELECT * FROM orders WHERE id = $1 AND customer_id = $2',
      [id, cid],
      'Orden no encontrada',
    );
    if (o.status !== 'draft') return reply.code(409).send({ error: 'bad_state', status: o.status });

    const pm =
      body.paymentMethodId ??
      (
        await one<{ id: string }>(
          'SELECT id FROM payment_methods WHERE customer_id = $1 ORDER BY is_default DESC, created_at LIMIT 1',
          [cid],
        )
      )?.id ??
      null;

    const t = totals({ capAmount: o.cap_amount, itemsAmount: o.items_amount });
    const hold = await placeHold({
      orderId: id,
      amount: t.authorizedAmount,
      paymentMethodId: pm,
      reference: o.code,
    });

    await transition(id, 'authorized', {
      actor: `customer:${cid}`,
      event: 'hold_placed',
      patch: { authorized_amount: t.authorizedAmount, authorized_at: new Date() },
      payload: { amount: t.authorizedAmount, expiresAt: hold.expiresAt, processorRef: hold.processorRef },
    });

    return fetchOrder(id);
  });

  /**
   * «Estoy aquí»: el cliente identifica el surtidor (QR o número).
   * Aquí es donde el broker manda FuelPumpAuthorize a Retail Manager con
   * RequestId = edge_transaction_uuid (idempotente) y crea la tarea del
   * handheld.
   */
  app.post('/v1/orders/:id/arrive', { preHandler: requireCustomer }, async (req, reply) => {
    const cid = customerId(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const body = z
      .object({ pumpNumber: z.number().int().positive().optional(), qrToken: z.string().optional() })
      .refine((v) => v.pumpNumber !== undefined || v.qrToken !== undefined, {
        message: 'Indica pumpNumber o qrToken',
      })
      .parse(req.body);

    const o = await oneOrFail<any>('SELECT * FROM orders WHERE id = $1 AND customer_id = $2', [id, cid]);
    if (o.status !== 'authorized') return reply.code(409).send({ error: 'bad_state', status: o.status });

    const pump = await one<any>(
      body.qrToken
        ? 'SELECT * FROM pumps WHERE qr_token = $1 AND station_id = $2'
        : 'SELECT * FROM pumps WHERE number = $1 AND station_id = $2',
      [body.qrToken ?? body.pumpNumber, o.station_id],
    );
    if (!pump) return reply.code(404).send({ error: 'pump_not_found' });

    const hose = await one<any>(
      `SELECT h.* FROM hoses h WHERE h.pump_id = $1 AND h.fuel_product_id = $2 ORDER BY h.position LIMIT 1`,
      [pump.id, o.fuel_product_id],
    );
    if (!hose) return reply.code(409).send({ error: 'hose_not_mapped', message: 'Ese surtidor no ofrece ese grado' });

    // 1) Comando al POS/controlador — idempotente por RequestId
    const requestId = o.edge_transaction_uuid as string;
    await query(
      `INSERT INTO pts_commands (order_id, controller_id, request_id, command, params, status)
       VALUES ($1,$2,$3,'FuelPumpAuthorize',$4,'queued')
       ON CONFLICT (request_id) DO NOTHING`,
      [
        id,
        pump.controller_id,
        requestId,
        JSON.stringify({ pump: pump.pts_pump_number, hose: hose.pts_nozzle_number, amount: o.cap_amount }),
      ],
    );

    const rm = await rmFor(o.station_id);
    const res = await rm.fuelPumpAuthorize({
      pump: pump.pts_pump_number,
      hose: hose.pts_nozzle_number,
      amount: Number(o.cap_amount),
      requestId,
      paymentRef: o.code,
      controllerId: pump.controller_id ?? 1,
    });

    await query(
      `UPDATE pts_commands SET status = $2, response = $3, error = $4, acked_at = now() WHERE request_id = $1`,
      [requestId, res.ok ? 'acked' : 'failed', JSON.stringify(res.data ?? {}), res.ok ? null : res.raw.slice(0, 400)],
    );

    if (!res.ok) {
      await logEvent(id, 'pump_authorize_failed', 'rm', { status: res.status, raw: res.raw.slice(0, 300) });
      return reply.code(502).send({ error: 'pump_authorize_failed', detail: res.raw.slice(0, 300) });
    }

    // 2) Estado de la orden + tarea para el handheld
    await transition(id, 'arrived', {
      actor: `customer:${cid}`,
      event: 'arrived',
      patch: { pump_id: pump.id, arrived_at: new Date() },
      payload: { pumpNumber: pump.number, requestId },
    });

    const hasItems = await one<{ n: number }>('SELECT count(*)::int AS n FROM order_items WHERE order_id = $1', [id]);
    await query(
      `INSERT INTO tasks (order_id, station_id, status, priority)
       VALUES ($1,$2,$3,false)
       ON CONFLICT (order_id) DO UPDATE SET status = EXCLUDED.status`,
      [id, o.station_id, (hasItems?.n ?? 0) > 0 ? 'incoming' : 'waiting'],
    );
    publishStation(o.station_id, 'task_incoming', { orderId: id, pumpNumber: pump.number });

    return fetchOrder(id);
  });

  /** Cancela mientras no haya surtido; libera la retención. */
  app.post('/v1/orders/:id/cancel', { preHandler: requireCustomer }, async (req, reply) => {
    const cid = customerId(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const reason = z.object({ reason: z.string().max(200).optional() }).parse(req.body ?? {}).reason ?? 'cliente';

    const o = await oneOrFail<any>('SELECT * FROM orders WHERE id = $1 AND customer_id = $2', [id, cid]);
    if (!['draft', 'authorized', 'arrived'].includes(o.status)) {
      return reply.code(409).send({ error: 'bad_state', status: o.status });
    }
    await releaseHold(id, reason);
    await transition(id, 'cancelled', {
      actor: `customer:${cid}`,
      patch: { cancelled_reason: reason, completed_at: new Date() },
    });
    await query("UPDATE tasks SET status = 'closed', closed_at = now() WHERE order_id = $1", [id]);
    return fetchOrder(id);
  });

  /** Estado de la orden (poll de respaldo del WebSocket). */
  app.get('/v1/orders/:id', { preHandler: requireCustomer }, async (req, reply) => {
    const cid = customerId(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const o = await one('SELECT id FROM orders WHERE id = $1 AND customer_id = $2', [id, cid]);
    if (!o) return reply.code(404).send({ error: 'not_found' });
    return fetchOrder(id);
  });

  app.get('/v1/orders', { preHandler: requireCustomer }, async (req) => {
    const cid = customerId(req);
    const { limit } = z.object({ limit: z.coerce.number().min(1).max(50).default(10) }).parse(req.query ?? {});
    const rows = await query<{ id: string }>(
      'SELECT id FROM orders WHERE customer_id = $1 ORDER BY created_at DESC LIMIT $2',
      [cid, limit],
    );
    return Promise.all(rows.map((r) => fetchOrder(r.id)));
  });

  /** Recibo: cobro final, liberación y trazabilidad. */
  app.get('/v1/orders/:id/receipt', { preHandler: requireCustomer }, async (req, reply) => {
    const cid = customerId(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const o = await one<any>(
      `SELECT o.*, s.name AS station_name, p.number AS pump_number, fp.display_name AS fuel_name
         FROM orders o
         JOIN stations s ON s.id = o.station_id
         LEFT JOIN pumps p ON p.id = o.pump_id
         LEFT JOIN fuel_products fp ON fp.id = o.fuel_product_id
        WHERE o.id = $1 AND o.customer_id = $2`,
      [id, cid],
    );
    if (!o) return reply.code(404).send({ error: 'not_found' });
    if (!['dispensed', 'settled'].includes(o.status)) {
      return reply.code(409).send({ error: 'not_ready', status: o.status });
    }
    const items = await query('SELECT name, qty, unit_price, line_total FROM order_items WHERE order_id = $1', [id]);
    const hold = await one(
      'SELECT amount, captured_amount, status FROM payment_holds WHERE order_id = $1 ORDER BY id DESC LIMIT 1',
      [id],
    );
    return {
      code: o.code,
      station: o.station_name,
      pump: o.pump_number,
      fuel: o.fuel_name,
      pricePerLiter: o.price_per_unit,
      liters: o.dispensed_volume,
      fuelAmount: o.dispensed_amount,
      items,
      itemsAmount: o.items_amount,
      total: o.final_amount ?? round2(Number(o.dispensed_amount) + Number(o.items_amount)),
      released: o.released_amount,
      hold,
      edgeTransactionUuid: o.edge_transaction_uuid,
      rmInvoiceNumber: o.rm_invoice_number,
      settledAt: o.completed_at,
    };
  });
}

/** Vista canónica de la orden que consumen las apps. */
export async function fetchOrder(id: string) {
  const o = await oneOrFail<any>(
    `SELECT o.*, s.name AS station_name, s.code AS station_code,
            p.number AS pump_number, fp.code AS fuel_code, fp.display_name AS fuel_name,
            v.plate, v.make_model, v.color
       FROM orders o
       JOIN stations s ON s.id = o.station_id
       LEFT JOIN pumps p ON p.id = o.pump_id
       LEFT JOIN fuel_products fp ON fp.id = o.fuel_product_id
       LEFT JOIN vehicles v ON v.id = o.vehicle_id
      WHERE o.id = $1`,
    [id],
  );
  const items = await query(
    'SELECT id, item_code, name, qty, unit_price, line_total, picked_at, delivered_at, substituted FROM order_items WHERE order_id = $1',
    [id],
  );
  const t = totals({
    capAmount: Number(o.cap_amount),
    itemsAmount: Number(o.items_amount),
    dispensedAmount: Number(o.dispensed_amount),
  });
  return {
    id: o.id,
    code: o.code,
    status: o.status,
    edgeTransactionUuid: o.edge_transaction_uuid,
    station: { id: o.station_id, code: o.station_code, name: o.station_name },
    vehicle: o.plate ? { plate: o.plate, makeModel: o.make_model, color: o.color } : null,
    pumpNumber: o.pump_number,
    fuel: { code: o.fuel_code, name: o.fuel_name, pricePerLiter: o.price_per_unit },
    capAmount: t.capAmount,
    itemsAmount: t.itemsAmount,
    authorizedAmount: t.authorizedAmount,
    dispensedAmount: t.dispensedAmount,
    dispensedVolume: Number(o.dispensed_volume),
    estimatedLiters: litersFor(t.capAmount, Number(o.price_per_unit ?? 0)),
    finalAmount: o.final_amount ?? t.finalAmount,
    releasedAmount: o.released_amount ?? t.releasedAmount,
    items,
    timestamps: {
      createdAt: o.created_at,
      authorizedAt: o.authorized_at,
      arrivedAt: o.arrived_at,
      dispensingAt: o.dispensing_at,
      completedAt: o.completed_at,
    },
  };
}

export { captureHold };
