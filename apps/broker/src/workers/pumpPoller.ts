import { config } from '../config.js';
import { one, query } from '../db.js';
import { normalizePumpState, ptsLinkFor, type PtsPumpStatus } from '../clients/ptsLink.js';
import { rmForOrNull } from '../clients/rmApi.js';
import { activeStations } from '../tenancy.js';
import { logEvent, round2, round3, transition } from '../domain/orders.js';
import { publishOrder, publishStation } from '../realtime/hub.js';
import { settleOrder } from '../routes/tasks.js';

/**
 * Vigilante del surtido, estación por estación. Para cada estación activa:
 * pregunta a SU PTS2Link; si no responde, cae al FuelPumpStatus de SU
 * Retail Manager. Así una estación caída no afecta a las demás.
 *
 *   authorized/arrived + FILLING     → dispensing (progreso en vivo)
 *   dispensing + END_OF_TRANSACTION  → dispensed → settled (captura + factura)
 */

async function readPumps(stationId: string): Promise<{ readings: PtsPumpStatus[]; source: string }> {
  const link = await ptsLinkFor(stationId);
  if (link) {
    const viaLink = await link.pumps();
    if (viaLink && Array.isArray(viaLink)) return { readings: viaLink, source: 'pts2link' };
  }

  const rm = await rmForOrNull(stationId);
  if (!rm) return { readings: [], source: 'none' };

  const active = await query<{ pts_pump_number: number }>(
    `SELECT DISTINCT p.pts_pump_number
       FROM pumps p JOIN orders o ON o.pump_id = p.id
      WHERE p.station_id = $1 AND o.status IN ('arrived','dispensing')`,
    [stationId],
  );

  const out: PtsPumpStatus[] = [];
  for (const a of active) {
    const res = await rm.fuelPumpStatus(a.pts_pump_number);
    if (!res.ok || !res.data || typeof res.data !== 'object') continue;
    const d = res.data as Record<string, any>;
    out.push({
      pump: Number(d.Pump ?? a.pts_pump_number),
      state: String(d.State ?? d.Status ?? 'UNKNOWN'),
      nozzle: d.Nozzle !== undefined ? Number(d.Nozzle) : undefined,
      volume: d.Volume !== undefined ? Number(d.Volume) : undefined,
      amount: d.Amount !== undefined ? Number(d.Amount) : undefined,
      price: d.Price !== undefined ? Number(d.Price) : undefined,
      transaction: d.Transaction !== undefined ? Number(d.Transaction) : undefined,
    });
  }
  return { readings: out, source: 'rm_api' };
}

async function tickStation(stationId: string) {
  const { readings } = await readPumps(stationId);
  if (!readings.length) return;

  for (const r of readings) {
    const state = normalizePumpState(r.state);
    const pump = await one<{ id: string; status: string }>(
      'SELECT id, status FROM pumps WHERE station_id = $1 AND pts_pump_number = $2 LIMIT 1',
      [stationId, r.pump],
    );
    if (!pump) continue;

    if (pump.status !== state) {
      await query('UPDATE pumps SET status = $2, status_at = now() WHERE id = $1', [pump.id, state]);
      publishStation(stationId, 'pump_status', { pumpId: pump.id, number: r.pump, status: state });
    }

    const order = await one<any>(
      `SELECT * FROM orders
        WHERE pump_id = $1 AND status IN ('arrived','dispensing')
        ORDER BY arrived_at DESC LIMIT 1`,
      [pump.id],
    );
    if (!order) continue;

    const amount = round2(Number(r.amount ?? 0));
    const volume = round3(Number(r.volume ?? 0));

    if (state === 'filling') {
      if (order.status === 'arrived') {
        await transition(order.id, 'dispensing', {
          actor: 'pts',
          patch: { dispensing_at: new Date(), pts_transaction_id: r.transaction ?? null },
          payload: { pump: r.pump },
        });
        await query(
          "UPDATE tasks SET status = 'delivering' WHERE order_id = $1 AND status IN ('incoming','waiting','picking')",
          [order.id],
        );
      }
      if (amount > Number(order.dispensed_amount)) {
        await query('UPDATE orders SET dispensed_amount = $2, dispensed_volume = $3 WHERE id = $1', [
          order.id,
          Math.min(amount, Number(order.cap_amount)),
          volume,
        ]);
        publishOrder(order.id, 'dispensing_progress', { amount, volume, cap: Number(order.cap_amount) });
      }
      continue;
    }

    if (state === 'end_of_transaction' && order.status === 'dispensing') {
      const finalAmount = Math.min(amount || Number(order.dispensed_amount), Number(order.cap_amount));
      const finalVolume = volume || Number(order.dispensed_volume);
      await logEvent(order.id, 'pts_end_of_transaction', 'pts', {
        amount: finalAmount,
        volume: finalVolume,
        transaction: r.transaction ?? null,
      });
      await settleOrder(order.id, { dispensedAmount: finalAmount, dispensedVolume: finalVolume, actor: 'pts' });
      await query("UPDATE tasks SET status = 'closed', closed_at = now() WHERE order_id = $1", [order.id]);
      publishStation(stationId, 'order_settled', { orderId: order.id });
    }
  }
}

async function tanksTickStation(stationId: string) {
  const link = await ptsLinkFor(stationId);
  const readings = link ? await link.tanks() : null;
  if (!readings) return;
  for (const t of readings) {
    const tank = await one<{ id: string }>(
      'SELECT id FROM tanks WHERE station_id = $1 AND pts_tank_number = $2 LIMIT 1',
      [stationId, t.tank],
    );
    if (!tank) continue;
    await query('INSERT INTO tank_readings (tank_id, volume, height, temperature, water) VALUES ($1,$2,$3,$4,$5)', [
      tank.id,
      t.volume ?? null,
      t.height ?? null,
      t.temperature ?? null,
      t.water ?? null,
    ]);
  }
}

async function tick() {
  const stations = await activeStations();
  await Promise.allSettled(stations.map((s) => tickStation(s.id)));
}

async function tanksTick() {
  const stations = await activeStations();
  await Promise.allSettled(stations.map((s) => tanksTickStation(s.id)));
}

export function startPumpPoller() {
  const pumpTimer = setInterval(() => {
    tick().catch((e) => console.error('[pumps]', (e as Error).message));
  }, config.rules.pumpPollMs);

  const tankTimer = setInterval(() => {
    tanksTick().catch((e) => console.error('[tanks]', (e as Error).message));
  }, 30_000);

  return () => {
    clearInterval(pumpTimer);
    clearInterval(tankTimer);
  };
}
