import { randomUUID } from 'node:crypto';

import { one, query } from '../db.js';
import { getRules, stationOfOrder } from '../tenancy.js';
import { round2 } from './orders.js';

/**
 * Retenciones (holds). El procesador real se conecta implementando esta misma
 * interfaz: place → capture → release. El adaptador `mock` deja la traza
 * completa en payment_holds para que el flujo se pueda probar sin banco.
 */

export type HoldProvider = {
  name: string;
  place(args: { token: string; amount: number; reference: string }): Promise<{ ref: string }>;
  capture(args: { ref: string; amount: number }): Promise<{ ok: boolean }>;
  release(args: { ref: string; amount: number }): Promise<{ ok: boolean }>;
};

const mockProvider: HoldProvider = {
  name: 'mock',
  async place({ reference }) {
    return { ref: `mock_${reference}_${randomUUID().slice(0, 8)}` };
  },
  async capture() {
    return { ok: true };
  },
  async release() {
    return { ok: true };
  },
};

export const provider: HoldProvider = mockProvider;

export async function placeHold(args: {
  orderId: string;
  amount: number;
  paymentMethodId: string | null;
  reference: string;
}) {
  // Techo y vida de la retención se leen de las reglas de ESA estación.
  const stationId = await stationOfOrder(args.orderId);
  const rules = await getRules(stationId ?? '');
  if (args.amount > rules.maxAuthAmount) {
    const e = new Error(`El techo excede el máximo autorizable ($${rules.maxAuthAmount})`) as Error & {
      statusCode?: number;
    };
    e.statusCode = 422;
    throw e;
  }

  const pm = args.paymentMethodId
    ? await one<{ token: string }>('SELECT token FROM payment_methods WHERE id = $1', [args.paymentMethodId])
    : null;

  const { ref } = await provider.place({
    token: pm?.token ?? 'tok_wallet',
    amount: args.amount,
    reference: args.reference,
  });

  const expiresAt = new Date(Date.now() + rules.holdTtlMinutes * 60_000);

  const row = await one<{ id: string }>(
    `INSERT INTO payment_holds
       (order_id, payment_method_id, amount, status, processor, processor_ref, authorized_at, expires_at)
     VALUES ($1,$2,$3,'held',$4,$5, now(), $6)
     RETURNING id`,
    [args.orderId, args.paymentMethodId, round2(args.amount), provider.name, ref, expiresAt],
  );
  return { holdId: row!.id, processorRef: ref, expiresAt };
}

export async function captureHold(orderId: string, finalAmount: number) {
  const hold = await one<{ id: string; processor_ref: string; amount: number }>(
    "SELECT id, processor_ref, amount FROM payment_holds WHERE order_id = $1 AND status = 'held' ORDER BY id DESC LIMIT 1",
    [orderId],
  );
  if (!hold) return null;

  const capture = round2(Math.min(finalAmount, hold.amount));
  await provider.capture({ ref: hold.processor_ref, amount: capture });

  const released = round2(hold.amount - capture);
  if (released > 0) await provider.release({ ref: hold.processor_ref, amount: released });

  await query(
    `UPDATE payment_holds
        SET status = 'captured', captured_amount = $2, captured_at = now(),
            released_at = CASE WHEN $3 > 0 THEN now() ELSE released_at END
      WHERE id = $1`,
    [hold.id, capture, released],
  );

  return { captured: capture, released };
}

export async function releaseHold(orderId: string, reason: string) {
  const hold = await one<{ id: string; processor_ref: string; amount: number }>(
    "SELECT id, processor_ref, amount FROM payment_holds WHERE order_id = $1 AND status = 'held' ORDER BY id DESC LIMIT 1",
    [orderId],
  );
  if (!hold) return null;
  await provider.release({ ref: hold.processor_ref, amount: hold.amount });
  await query(
    "UPDATE payment_holds SET status = 'released', released_at = now(), failure_reason = $2 WHERE id = $1",
    [hold.id, reason],
  );
  return { released: hold.amount };
}
