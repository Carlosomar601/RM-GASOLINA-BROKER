import { query, one, tx } from '../db.js';
import { publishOrder, publishStation } from '../realtime/hub.js';

export type OrderStatus =
  | 'draft'
  | 'authorized'
  | 'arrived'
  | 'dispensing'
  | 'dispensed'
  | 'settled'
  | 'cancelled'
  | 'failed';

/** Transiciones permitidas. Cualquier otra combinación es un error 409. */
const allowed: Record<OrderStatus, OrderStatus[]> = {
  draft: ['authorized', 'cancelled'],
  authorized: ['arrived', 'cancelled', 'failed'],
  arrived: ['dispensing', 'cancelled', 'failed'],
  dispensing: ['dispensed', 'failed'],
  dispensed: ['settled', 'failed'],
  settled: [],
  cancelled: [],
  failed: [],
};

export function canTransition(from: OrderStatus, to: OrderStatus): boolean {
  return (allowed[from] ?? []).includes(to);
}

export class ConflictError extends Error {
  statusCode = 409;
}

export async function logEvent(orderId: string, type: string, actor = 'system', payload: unknown = {}) {
  await query('INSERT INTO order_events (order_id, type, actor, payload) VALUES ($1,$2,$3,$4)', [
    orderId,
    type,
    actor,
    JSON.stringify(payload ?? {}),
  ]);
  publishOrder(orderId, type, payload);
}

/**
 * Cambia el estado con validación y bitácora, en una sola transacción.
 * `patch` permite fijar columnas junto con la transición (montos, timestamps).
 */
export async function transition(
  orderId: string,
  to: OrderStatus,
  opts: { actor?: string; patch?: Record<string, unknown>; event?: string; payload?: unknown } = {},
) {
  const updated = await tx(async (c) => {
    const cur = await c.query('SELECT status, station_id FROM orders WHERE id = $1 FOR UPDATE', [orderId]);
    const row = cur.rows[0] as { status: OrderStatus; station_id: string } | undefined;
    if (!row) throw new ConflictError('Orden no encontrada');
    if (row.status === to) return row;
    if (!canTransition(row.status, to)) {
      throw new ConflictError(`Transición inválida: ${row.status} → ${to}`);
    }

    const patch = { status: to, ...(opts.patch ?? {}) };
    const keys = Object.keys(patch);
    const sets = keys.map((k, i) => `${k} = $${i + 2}`).join(', ');
    await c.query(`UPDATE orders SET ${sets} WHERE id = $1`, [orderId, ...keys.map((k) => (patch as any)[k])]);

    await c.query('INSERT INTO order_events (order_id, type, actor, payload) VALUES ($1,$2,$3,$4)', [
      orderId,
      opts.event ?? to,
      opts.actor ?? 'system',
      JSON.stringify(opts.payload ?? {}),
    ]);
    return row;
  });

  publishOrder(orderId, opts.event ?? to, opts.payload ?? { status: to });
  if (updated?.station_id) publishStation(updated.station_id, 'order_updated', { orderId, status: to });
  return to;
}

export async function nextOrderCode(): Promise<string> {
  const row = await one<{ n: number }>(
    "SELECT COALESCE(MAX(NULLIF(regexp_replace(code, '\\D', '', 'g'), '')::int), 2600) + 1 AS n FROM orders",
  );
  return `OC-${row?.n ?? 2601}`;
}

export type OrderTotals = {
  capAmount: number;
  itemsAmount: number;
  authorizedAmount: number;
  dispensedAmount: number;
  finalAmount: number;
  releasedAmount: number;
};

/** Regla central: la retención es techo + artículos; el cobro es lo dispensado. */
export function totals(args: {
  capAmount: number;
  itemsAmount: number;
  dispensedAmount?: number;
}): OrderTotals {
  const cap = round2(args.capAmount);
  const items = round2(args.itemsAmount);
  const authorized = round2(cap + items);
  const dispensed = round2(args.dispensedAmount ?? 0);
  const final = round2(dispensed + items);
  return {
    capAmount: cap,
    itemsAmount: items,
    authorizedAmount: authorized,
    dispensedAmount: dispensed,
    finalAmount: final,
    releasedAmount: round2(Math.max(0, authorized - final)),
  };
}

export const round2 = (n: number) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
export const round3 = (n: number) => Math.round((Number(n) + Number.EPSILON) * 1000) / 1000;
