import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { one, oneOrFail, query } from '../db.js';
import { employee, requireEmployee } from '../auth/jwt.js';
import { logEvent, round2, totals, transition } from '../domain/orders.js';
import { captureHold } from '../domain/payments.js';
import { publishStation } from '../realtime/hub.js';
import { queueInvoice } from '../workers/outbox.js';

export default async function taskRoutes(app: FastifyInstance) {
  /** Cola del turno para el handheld. */
  app.get('/v1/tasks', { preHandler: requireEmployee }, async (req) => {
    const e = employee(req);
    return query(
      `SELECT t.id, t.status, t.priority, t.identity_ok, t.employee_id,
              o.id AS order_id, o.code, o.status AS order_status, o.cap_amount,
              o.items_amount, o.dispensed_amount, o.edge_transaction_uuid,
              o.arrived_at, o.created_at,
              p.number AS pump_number,
              fp.display_name AS fuel_name, fp.code AS fuel_code,
              c.full_name AS customer_name, c.photo_url,
              v.plate, v.make_model, v.color,
              (SELECT count(*)::int FROM order_items i WHERE i.order_id = o.id) AS item_count,
              (SELECT count(*)::int FROM order_items i WHERE i.order_id = o.id AND i.picked_at IS NOT NULL) AS picked_count
         FROM tasks t
         JOIN orders o ON o.id = t.order_id
         LEFT JOIN pumps p ON p.id = o.pump_id
         LEFT JOIN fuel_products fp ON fp.id = o.fuel_product_id
         JOIN customers c ON c.id = o.customer_id
         LEFT JOIN vehicles v ON v.id = o.vehicle_id
        WHERE t.station_id = $1 AND t.status <> 'closed'
        ORDER BY t.priority DESC, o.arrived_at NULLS LAST, o.created_at`,
      [e.stationId],
    );
  });

  /** Detalle con los artículos a preparar. */
  app.get('/v1/tasks/:id', { preHandler: requireEmployee }, async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const t = await oneOrFail<any>(
      `SELECT t.*, o.code, o.cap_amount, o.items_amount, o.dispensed_amount, o.status AS order_status,
              o.edge_transaction_uuid, p.number AS pump_number, fp.display_name AS fuel_name,
              c.full_name AS customer_name, c.photo_url, v.plate, v.make_model, v.color
         FROM tasks t
         JOIN orders o ON o.id = t.order_id
         LEFT JOIN pumps p ON p.id = o.pump_id
         LEFT JOIN fuel_products fp ON fp.id = o.fuel_product_id
         JOIN customers c ON c.id = o.customer_id
         LEFT JOIN vehicles v ON v.id = o.vehicle_id
        WHERE t.id = $1`,
      [id],
    );
    const items = await query(
      `SELECT i.id, i.item_code, i.name, i.qty, i.unit_price, i.line_total,
              i.picked_at, i.substituted, i.delivered_at, pr.aisle
         FROM order_items i
         LEFT JOIN products pr ON pr.id = i.product_id
        WHERE i.order_id = $1
        ORDER BY pr.aisle NULLS LAST, i.name`,
      [t.order_id],
    );
    return { ...t, items };
  });

  /** El empleado toma la tarea. */
  app.post('/v1/tasks/:id/accept', { preHandler: requireEmployee }, async (req) => {
    const e = employee(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const t = await oneOrFail<any>('SELECT * FROM tasks WHERE id = $1', [id]);
    const items = await one<{ n: number }>('SELECT count(*)::int AS n FROM order_items WHERE order_id = $1', [t.order_id]);
    const next = (items?.n ?? 0) > 0 ? 'picking' : 'waiting';
    await query("UPDATE tasks SET status = $2, employee_id = $3, accepted_at = now() WHERE id = $1", [id, next, e.id]);
    await logEvent(t.order_id, 'task_accepted', `employee:${e.id}`, { status: next });
    publishStation(t.station_id, 'task_updated', { taskId: id, status: next });
    return { id, status: next };
  });

  /** Marca / desmarca un artículo del picking. */
  app.post('/v1/tasks/:id/items/:itemId/pick', { preHandler: requireEmployee }, async (req) => {
    const e = employee(req);
    const p = z.object({ id: z.string().uuid(), itemId: z.string().uuid() }).parse(req.params);
    const body = z.object({ picked: z.boolean().default(true), substituted: z.boolean().default(false) }).parse(req.body ?? {});
    const t = await oneOrFail<any>('SELECT * FROM tasks WHERE id = $1', [p.id]);
    await query(
      'UPDATE order_items SET picked_at = $2, substituted = $3 WHERE id = $1 AND order_id = $4',
      [p.itemId, body.picked ? new Date() : null, body.substituted, t.order_id],
    );
    await logEvent(t.order_id, 'item_picked', `employee:${e.id}`, { itemId: p.itemId, ...body });
    return { ok: true };
  });

  /** Verificación de identidad por foto antes de entregar. */
  app.post('/v1/tasks/:id/identity', { preHandler: requireEmployee }, async (req) => {
    const e = employee(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const body = z.object({ matches: z.boolean(), note: z.string().max(300).optional() }).parse(req.body);
    const t = await oneOrFail<any>('SELECT * FROM tasks WHERE id = $1', [id]);
    await query('UPDATE tasks SET identity_ok = $2, status = $3, note = $4 WHERE id = $1', [
      id,
      body.matches,
      body.matches ? 'delivering' : 'escalated',
      body.note ?? null,
    ]);
    await logEvent(t.order_id, body.matches ? 'identity_ok' : 'identity_mismatch', `employee:${e.id}`, {
      note: body.note ?? null,
    });
    publishStation(t.station_id, 'task_updated', { taskId: id, status: body.matches ? 'delivering' : 'escalated' });
    return { ok: true, status: body.matches ? 'delivering' : 'escalated' };
  });

  /**
   * Cierre manual del surtido cuando el pulso del PTS-2 no llega
   * (respaldo del worker). Captura la retención y encola la factura a RM.
   */
  app.post('/v1/tasks/:id/close', { preHandler: requireEmployee }, async (req, reply) => {
    const e = employee(req);
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const body = z
      .object({ dispensedAmount: z.number().min(0), dispensedVolume: z.number().min(0).optional() })
      .parse(req.body);

    const t = await oneOrFail<any>('SELECT * FROM tasks WHERE id = $1', [id]);
    const o = await oneOrFail<any>('SELECT * FROM orders WHERE id = $1', [t.order_id]);
    if (!['arrived', 'dispensing'].includes(o.status)) {
      return reply.code(409).send({ error: 'bad_state', status: o.status });
    }
    if (Number(body.dispensedAmount) > Number(o.cap_amount) + 0.01) {
      return reply.code(422).send({ error: 'over_cap', cap: o.cap_amount });
    }

    const price = Number(o.price_per_unit ?? 0);
    const volume = body.dispensedVolume ?? (price > 0 ? round2(body.dispensedAmount / price) : 0);

    if (o.status === 'arrived') {
      await transition(t.order_id, 'dispensing', {
        actor: `employee:${e.id}`,
        patch: { dispensing_at: new Date() },
      });
    }
    await settleOrder(t.order_id, { dispensedAmount: body.dispensedAmount, dispensedVolume: volume, actor: `employee:${e.id}` });
    await query("UPDATE tasks SET status = 'closed', closed_at = now() WHERE id = $1", [id]);
    publishStation(t.station_id, 'task_updated', { taskId: id, status: 'closed' });

    return { ok: true };
  });
}

/**
 * Liquidación: fija montos, captura la retención, libera la diferencia y
 * encola la factura hacia Retail Manager. La usan el worker de bombas y el
 * cierre manual del handheld.
 */
export async function settleOrder(
  orderId: string,
  args: { dispensedAmount: number; dispensedVolume: number; actor?: string },
) {
  const o = await oneOrFail<any>('SELECT * FROM orders WHERE id = $1', [orderId]);
  const t = totals({
    capAmount: Number(o.cap_amount),
    itemsAmount: Number(o.items_amount),
    dispensedAmount: args.dispensedAmount,
  });

  await transition(orderId, 'dispensed', {
    actor: args.actor ?? 'system',
    event: 'dispensed',
    patch: {
      dispensed_amount: t.dispensedAmount,
      dispensed_volume: args.dispensedVolume,
      final_amount: t.finalAmount,
      released_amount: t.releasedAmount,
    },
    payload: { amount: t.dispensedAmount, volume: args.dispensedVolume },
  });

  const capture = await captureHold(orderId, t.finalAmount);
  await logEvent(orderId, 'hold_captured', 'system', capture ?? {});

  await queueInvoice(orderId);

  await transition(orderId, 'settled', {
    actor: 'system',
    patch: { completed_at: new Date() },
    payload: { total: t.finalAmount, released: t.releasedAmount },
  });

  await query('UPDATE order_items SET delivered_at = now() WHERE order_id = $1 AND delivered_at IS NULL', [orderId]);
  return t;
}
