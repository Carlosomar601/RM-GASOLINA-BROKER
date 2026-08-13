import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { one, query } from '../db.js';
import { config } from '../config.js';
import { rmForOrNull } from '../clients/rmApi.js';
import { ptsLinkFor } from '../clients/ptsLink.js';
import { ptsDirectFor } from '../clients/jsonPts.js';
import { syncPricesFromRm } from '../domain/pricing.js';
import { activeStations, getIntegration } from '../tenancy.js';
import { connectionCount } from '../realtime/hub.js';

/** Operación y diagnóstico. Multi-estación: casi todo recibe stationId. */
export default async function adminRoutes(app: FastifyInstance) {
  app.get('/health', async () => {
    const db = await one<{ ok: number }>('SELECT 1 AS ok').catch(() => null);
    const stations = db ? await activeStations() : [];
    return {
      status: db ? 'ok' : 'degraded',
      db: !!db,
      stations: stations.length,
      wsClients: connectionCount(),
      env: config.env,
      at: new Date().toISOString(),
    };
  });

  /** Semáforo de todos los enlaces de todas las estaciones. */
  app.get('/v1/admin/links', async () => {
    const rows = await query<any>(
      `SELECT s.id AS station_id, s.code AS station_code, s.name AS station_name, s.status,
              t.name AS tenant_name,
              i.id AS integration_id, i.kind, i.label, i.base_url, i.enabled,
              i.last_check_ok, i.last_check_at, i.last_check_note
         FROM stations s
         JOIN tenants t ON t.id = s.tenant_id
         LEFT JOIN integrations i
           ON (i.station_id = s.id OR (i.station_id IS NULL AND i.tenant_id = s.tenant_id))
        ORDER BY t.name, s.code, i.kind`,
    );
    return rows;
  });

  app.get('/v1/admin/overview', async (req) => {
    const q = z.object({ stationId: z.string().uuid().optional() }).parse(req.query ?? {});
    const st = q.stationId ?? null;

    const pumps = await query(
      `SELECT p.number, p.status, p.status_at, s.code AS station
         FROM pumps p JOIN stations s ON s.id = p.station_id
        WHERE ($1::uuid IS NULL OR p.station_id = $1)
        ORDER BY s.code, p.number`,
      [st],
    );
    const tanks = await query(
      `SELECT t.label, t.capacity_liters, s.code AS station, r.volume, r.read_at
         FROM tanks t
         JOIN stations s ON s.id = t.station_id
         LEFT JOIN LATERAL (
           SELECT volume, read_at FROM tank_readings WHERE tank_id = t.id ORDER BY read_at DESC LIMIT 1
         ) r ON true
        WHERE ($1::uuid IS NULL OR t.station_id = $1)
        ORDER BY s.code, t.label`,
      [st],
    );
    const today = await one(
      `SELECT count(*)::int AS orders,
              COALESCE(sum(dispensed_volume),0) AS liters,
              COALESCE(sum(final_amount),0) AS revenue,
              COALESCE(avg(EXTRACT(EPOCH FROM (completed_at - arrived_at))/60), 0) AS avg_minutes
         FROM orders
        WHERE status = 'settled' AND created_at::date = current_date
          AND ($1::uuid IS NULL OR station_id = $1)`,
      [st],
    );
    const funnel = await query(
      `SELECT status, count(*)::int AS n FROM orders
        WHERE created_at > now() - interval '24 hours'
          AND ($1::uuid IS NULL OR station_id = $1)
        GROUP BY status`,
      [st],
    );
    const outbox = await query(
      `SELECT b.status, count(*)::int AS n
         FROM rm_outbox b LEFT JOIN orders o ON o.id = b.order_id
        WHERE ($1::uuid IS NULL OR o.station_id = $1)
        GROUP BY b.status`,
      [st],
    );
    return { pumps, tanks, today, funnel, outbox };
  });

  app.get('/v1/admin/orders', async (req) => {
    const q = z
      .object({
        limit: z.coerce.number().min(1).max(200).default(50),
        status: z.string().optional(),
        stationId: z.string().uuid().optional(),
      })
      .parse(req.query ?? {});
    return query(
      `SELECT o.id, o.code, o.status, o.cap_amount, o.dispensed_amount, o.final_amount,
              o.released_amount, o.created_at, o.completed_at, o.edge_transaction_uuid,
              s.code AS station, p.number AS pump, c.full_name AS customer
         FROM orders o
         JOIN stations s ON s.id = o.station_id
         LEFT JOIN pumps p ON p.id = o.pump_id
         JOIN customers c ON c.id = o.customer_id
        WHERE ($1::text IS NULL OR o.status = $1)
          AND ($2::uuid IS NULL OR o.station_id = $2)
        ORDER BY o.created_at DESC LIMIT $3`,
      [q.status ?? null, q.stationId ?? null, q.limit],
    );
  });

  app.get('/v1/admin/orders/:id/events', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    return query('SELECT id, type, actor, payload, created_at FROM order_events WHERE order_id = $1 ORDER BY id', [id]);
  });

  app.get('/v1/admin/audit', async () => query('SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 100'));

  // ── Diagnóstico por estación ───────────────────────────────────────
  app.get('/v1/admin/stations/:id/rm/ping', async (req, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const rm = await rmForOrNull(id);
    if (!rm) return reply.code(424).send({ error: 'no_rm_integration' });
    const [time, validez] = await Promise.all([rm.serverTime(), rm.validez()]);
    return { link: rm.label, baseUrl: rm.baseUrl, serverTime: time, validez };
  });

  app.get('/v1/admin/stations/:id/pts/status', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const link = await ptsLinkFor(id);
    if (link) {
      const pumps = await link.pumps();
      if (pumps) return { source: 'pts2link', link: link.label, pumps };
    }
    const direct = await ptsDirectFor(id);
    if (direct) {
      const raw = await direct.pumpStatus(1).catch((e: Error) => ({ error: e.message }));
      return { source: 'jsonPTS', raw };
    }
    return { source: 'none', pumps: [] };
  });

  app.get('/v1/admin/stations/:id/mappings', async (req, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const link = await ptsLinkFor(id);
    if (!link) return reply.code(424).send({ error: 'no_pts2link_integration' });
    const remote = await link.mappings();
    const local = {
      pumps: await query('SELECT number, pts_pump_number, price_level, rm_pump_id FROM pumps WHERE station_id = $1 ORDER BY number', [id]),
      hoses: await query(
        `SELECT p.number AS pump, h.position, h.pts_nozzle_number, fp.code AS fuel
           FROM hoses h JOIN pumps p ON p.id = h.pump_id
           JOIN fuel_products fp ON fp.id = h.fuel_product_id
          WHERE p.station_id = $1 ORDER BY p.number, h.position`,
        [id],
      ),
      tanks: await query('SELECT label, pts_tank_number, pts_probe_number FROM tanks WHERE station_id = $1 ORDER BY label', [id]),
    };
    return { remote, local };
  });

  app.post('/v1/admin/stations/:id/sync-prices', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    return syncPricesFromRm(id);
  });

  /** Config efectiva que usará el broker para esa estación (sin secretos). */
  app.get('/v1/admin/stations/:id/effective-config', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const kinds = ['rm_api', 'pts2link', 'pts_direct', 'payments'] as const;
    const out: Record<string, unknown> = {};
    for (const k of kinds) {
      const cfg = await getIntegration(id, k);
      out[k] = cfg
        ? {
            id: cfg.id,
            label: cfg.label,
            baseUrl: cfg.baseUrl,
            authType: cfg.authType,
            hasSecret: !!cfg.secret,
            timeoutMs: cfg.timeoutMs,
            settings: cfg.settings,
            enabled: cfg.enabled,
          }
        : null;
    }
    return out;
  });

  app.post('/v1/admin/outbox/retry', async () => {
    const rows = await query<{ id: number }>(
      "UPDATE rm_outbox SET status = 'pending', next_try_at = now() WHERE status IN ('failed','dead') RETURNING id",
    );
    return { requeued: rows.length };
  });
}
