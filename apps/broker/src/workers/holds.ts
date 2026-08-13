import { query } from '../db.js';
import { logEvent, transition } from '../domain/orders.js';
import { provider } from '../domain/payments.js';

/**
 * Retenciones vencidas: si el cliente autorizó y nunca llegó, se libera el
 * dinero y la orden se marca fallida. Corre cada minuto.
 */
async function tick() {
  const expired = await query<{ id: string; order_id: string; processor_ref: string; amount: number; status: string }>(
    `SELECT h.id, h.order_id, h.processor_ref, h.amount, o.status
       FROM payment_holds h
       JOIN orders o ON o.id = h.order_id
      WHERE h.status = 'held' AND h.expires_at < now()`,
  );

  for (const h of expired) {
    await provider.release({ ref: h.processor_ref, amount: Number(h.amount) });
    await query("UPDATE payment_holds SET status = 'expired', released_at = now() WHERE id = $1", [h.id]);
    await logEvent(h.order_id, 'hold_expired', 'system', { amount: h.amount });

    if (['authorized', 'arrived'].includes(h.status)) {
      await transition(h.order_id, 'failed', {
        actor: 'system',
        patch: { cancelled_reason: 'retención expirada', completed_at: new Date() },
      }).catch(() => undefined);
      await query("UPDATE tasks SET status = 'closed', closed_at = now() WHERE order_id = $1", [h.order_id]);
    }
  }
}

export function startHoldWatcher() {
  const timer = setInterval(() => {
    tick().catch((e) => console.error('[holds]', (e as Error).message));
  }, 60_000);
  void tick().catch(() => undefined);
  return () => clearInterval(timer);
}
