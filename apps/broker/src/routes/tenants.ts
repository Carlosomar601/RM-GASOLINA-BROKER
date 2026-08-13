import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { one, query } from '../db.js';
import { encryptSecret, maskSecret } from '../crypto.js';
import { invalidateStation } from '../tenancy.js';
import { rmForOrNull, RmClient } from '../clients/rmApi.js';
import { ptsLinkFor, PtsLinkClient } from '../clients/ptsLink.js';
import { ptsDirectFor } from '../clients/jsonPts.js';
import { getIntegration } from '../tenancy.js';

/**
 * Administración multi-cliente: tenants → estaciones → enlaces.
 * Aquí es donde se añade un cliente nuevo con su propio Retail Manager y su
 * propio PTS2Link, sin tocar el .env ni redeployar.
 */

const kind = z.enum(['rm_api', 'pts2link', 'pts_direct', 'payments', 'push']);

export default async function tenantRoutes(app: FastifyInstance) {
  // ── Tenants ────────────────────────────────────────────────────────
  app.get('/v1/admin/tenants', async () =>
    query(`SELECT t.*, (SELECT count(*)::int FROM stations s WHERE s.tenant_id = t.id) AS stations
             FROM tenants t ORDER BY t.name`),
  );

  app.post('/v1/admin/tenants', async (req, reply) => {
    const b = z
      .object({
        code: z.string().min(2).max(24),
        name: z.string().min(2),
        contactName: z.string().optional(),
        contactEmail: z.string().email().optional(),
      })
      .parse(req.body);
    const row = await one(
      `INSERT INTO tenants (code, name, contact_name, contact_email)
       VALUES ($1,$2,$3,$4) RETURNING *`,
      [b.code.toUpperCase(), b.name, b.contactName ?? null, b.contactEmail ?? null],
    );
    return reply.code(201).send(row);
  });

  // ── Estaciones ─────────────────────────────────────────────────────
  app.get('/v1/admin/stations', async () =>
    query(`SELECT s.*, t.name AS tenant_name,
                  (SELECT count(*)::int FROM pumps p WHERE p.station_id = s.id) AS pumps,
                  (SELECT count(*)::int FROM integrations i WHERE i.station_id = s.id AND i.enabled) AS links
             FROM stations s JOIN tenants t ON t.id = s.tenant_id
            ORDER BY t.name, s.code`),
  );

  app.post('/v1/admin/stations', async (req, reply) => {
    const b = z
      .object({
        tenantId: z.string().uuid(),
        code: z.string().min(2),
        name: z.string().min(2),
        address: z.string().optional(),
        town: z.string().optional(),
        lat: z.number().optional(),
        lng: z.number().optional(),
        volumeUnit: z.enum(['L', 'GAL']).default('L'),
        hasMinimarket: z.boolean().default(true),
      })
      .parse(req.body);

    const s = await one<{ id: string }>(
      `INSERT INTO stations (tenant_id, code, name, address, town, lat, lng, volume_unit, has_minimarket, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'onboarding') RETURNING id`,
      [b.tenantId, b.code.toUpperCase(), b.name, b.address ?? null, b.town ?? null, b.lat ?? null, b.lng ?? null, b.volumeUnit, b.hasMinimarket],
    );
    await query('INSERT INTO station_rules (station_id) VALUES ($1) ON CONFLICT DO NOTHING', [s!.id]);
    return reply.code(201).send({ id: s!.id });
  });

  app.patch('/v1/admin/stations/:id', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const b = z
      .object({
        name: z.string().optional(),
        status: z.enum(['active', 'paused', 'onboarding', 'disabled']).optional(),
        isOpen: z.boolean().optional(),
        volumeUnit: z.enum(['L', 'GAL']).optional(),
      })
      .parse(req.body);
    const map: Record<string, unknown> = {};
    if (b.name !== undefined) map.name = b.name;
    if (b.status !== undefined) map.status = b.status;
    if (b.isOpen !== undefined) map.is_open = b.isOpen;
    if (b.volumeUnit !== undefined) map.volume_unit = b.volumeUnit;
    const keys = Object.keys(map);
    if (keys.length) {
      await query(
        `UPDATE stations SET ${keys.map((k, i) => `${k} = $${i + 2}`).join(', ')} WHERE id = $1`,
        [id, ...keys.map((k) => map[k])],
      );
    }
    invalidateStation(id);
    return one('SELECT * FROM stations WHERE id = $1', [id]);
  });

  // ── Reglas de negocio por estación (IVU, techos, factura) ──────────
  app.get('/v1/admin/stations/:id/rules', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    return one('SELECT * FROM station_rules WHERE station_id = $1', [id]);
  });

  app.put('/v1/admin/stations/:id/rules', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const b = z
      .object({
        holdTtlMinutes: z.number().int().min(5).max(1440).optional(),
        maxAuthAmount: z.number().min(5).max(1000).optional(),
        minAuthAmount: z.number().min(1).max(100).optional(),
        cityTaxRate: z.number().min(0).max(0.5).optional(),
        stateTaxRate: z.number().min(0).max(0.5).optional(),
        fuelTaxable: z.boolean().optional(),
        itemsTaxable: z.boolean().optional(),
        invoiceSeries: z.string().max(4).optional(),
        defaultRmClient: z.string().max(24).optional(),
      })
      .parse(req.body);

    const cols: Record<string, unknown> = {
      hold_ttl_minutes: b.holdTtlMinutes,
      max_auth_amount: b.maxAuthAmount,
      min_auth_amount: b.minAuthAmount,
      city_tax_rate: b.cityTaxRate,
      state_tax_rate: b.stateTaxRate,
      fuel_taxable: b.fuelTaxable,
      items_taxable: b.itemsTaxable,
      invoice_series: b.invoiceSeries,
      default_rm_client: b.defaultRmClient,
    };
    const keys = Object.keys(cols).filter((k) => cols[k] !== undefined);
    if (keys.length) {
      await query(
        `INSERT INTO station_rules (station_id) VALUES ($1)
         ON CONFLICT (station_id) DO UPDATE
           SET ${keys.map((k, i) => `${k} = $${i + 2}`).join(', ')}, updated_at = now()`,
        [id, ...keys.map((k) => cols[k])],
      );
    }
    invalidateStation(id);
    return one('SELECT * FROM station_rules WHERE station_id = $1', [id]);
  });

  // ── Enlaces (integrations) ─────────────────────────────────────────
  app.get('/v1/admin/integrations', async (req) => {
    const q = z.object({ stationId: z.string().uuid().optional(), tenantId: z.string().uuid().optional() }).parse(
      req.query ?? {},
    );
    const rows = await query<any>(
      `SELECT i.*, s.code AS station_code, t.name AS tenant_name
         FROM integrations i
         JOIN tenants t ON t.id = i.tenant_id
         LEFT JOIN stations s ON s.id = i.station_id
        WHERE ($1::uuid IS NULL OR i.station_id = $1)
          AND ($2::uuid IS NULL OR i.tenant_id = $2)
        ORDER BY t.name, s.code NULLS FIRST, i.kind`,
      [q.stationId ?? null, q.tenantId ?? null],
    );
    return rows.map(publicShape);
  });

  app.post('/v1/admin/integrations', async (req, reply) => {
    const b = z
      .object({
        tenantId: z.string().uuid(),
        stationId: z.string().uuid().nullable().optional(),
        kind,
        label: z.string().min(2),
        baseUrl: z.string().url(),
        authType: z.enum(['none', 'basic', 'digest', 'bearer', 'apikey', 'query']).default('none'),
        username: z.string().optional(),
        secret: z.string().optional(),
        extra: z.record(z.unknown()).optional(),
        timeoutMs: z.number().int().min(1000).max(60000).default(8000),
        verifyTls: z.boolean().default(true),
        tlsFingerprint: z.string().optional(),
        settings: z.record(z.unknown()).default({}),
        enabled: z.boolean().default(true),
        isPrimary: z.boolean().default(true),
      })
      .parse(req.body);

    const row = await one<any>(
      `INSERT INTO integrations
         (tenant_id, station_id, kind, label, base_url, auth_type, username, secret_enc, extra_enc,
          timeout_ms, verify_tls, tls_fingerprint, settings, enabled, is_primary)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
       RETURNING *`,
      [
        b.tenantId,
        b.stationId ?? null,
        b.kind,
        b.label,
        b.baseUrl.replace(/\/+$/, ''),
        b.authType,
        b.username ?? null,
        encryptSecret(b.secret),
        encryptSecret(b.extra ? JSON.stringify(b.extra) : null),
        b.timeoutMs,
        b.verifyTls,
        b.tlsFingerprint ?? null,
        JSON.stringify(b.settings),
        b.enabled,
        b.isPrimary,
      ],
    );
    await query(
      "INSERT INTO integration_events (integration_id, actor, action, detail) VALUES ($1,'console','created',$2)",
      [row.id, JSON.stringify({ kind: b.kind, baseUrl: b.baseUrl })],
    );
    invalidateStation(b.stationId ?? undefined);
    return reply.code(201).send(publicShape(row));
  });

  app.put('/v1/admin/integrations/:id', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const b = z
      .object({
        label: z.string().optional(),
        baseUrl: z.string().url().optional(),
        authType: z.enum(['none', 'basic', 'digest', 'bearer', 'apikey', 'query']).optional(),
        username: z.string().nullable().optional(),
        secret: z.string().nullable().optional(),
        extra: z.record(z.unknown()).nullable().optional(),
        timeoutMs: z.number().int().min(1000).max(60000).optional(),
        verifyTls: z.boolean().optional(),
        tlsFingerprint: z.string().nullable().optional(),
        settings: z.record(z.unknown()).optional(),
        enabled: z.boolean().optional(),
        isPrimary: z.boolean().optional(),
      })
      .parse(req.body);

    const cols: Record<string, unknown> = {
      label: b.label,
      base_url: b.baseUrl ? b.baseUrl.replace(/\/+$/, '') : undefined,
      auth_type: b.authType,
      username: b.username,
      secret_enc: b.secret === undefined ? undefined : encryptSecret(b.secret),
      extra_enc: b.extra === undefined ? undefined : encryptSecret(b.extra ? JSON.stringify(b.extra) : null),
      timeout_ms: b.timeoutMs,
      verify_tls: b.verifyTls,
      tls_fingerprint: b.tlsFingerprint,
      settings: b.settings === undefined ? undefined : JSON.stringify(b.settings),
      enabled: b.enabled,
      is_primary: b.isPrimary,
    };
    const keys = Object.keys(cols).filter((k) => cols[k] !== undefined);
    if (keys.length) {
      await query(
        `UPDATE integrations SET ${keys.map((k, i) => `${k} = $${i + 2}`).join(', ')}, updated_at = now() WHERE id = $1`,
        [id, ...keys.map((k) => cols[k])],
      );
    }
    const row = await one<any>('SELECT * FROM integrations WHERE id = $1', [id]);
    await query(
      "INSERT INTO integration_events (integration_id, actor, action, detail) VALUES ($1,'console','updated',$2)",
      [id, JSON.stringify({ fields: keys })],
    );
    invalidateStation(row?.station_id ?? undefined);
    return publicShape(row);
  });

  app.delete('/v1/admin/integrations/:id', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const row = await one<{ station_id: string | null }>('SELECT station_id FROM integrations WHERE id = $1', [id]);
    await query('DELETE FROM integrations WHERE id = $1', [id]);
    invalidateStation(row?.station_id ?? undefined);
    return { deleted: true };
  });

  /**
   * Prueba el enlace de verdad y guarda el resultado.
   * rm_api → ServerTime + Validez · pts2link → health + pumps
   * pts_direct → GetDateTime (solo lectura, valida huella TLS)
   */
  app.post('/v1/admin/integrations/:id/test', async (req, reply) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    const row = await one<any>('SELECT * FROM integrations WHERE id = $1', [id]);
    if (!row) return reply.code(404).send({ error: 'not_found' });

    const stationId: string | null = row.station_id;
    let ok = false;
    let note = '';
    let detail: unknown = null;

    try {
      if (row.kind === 'rm_api') {
        const client = stationId ? await rmForOrNull(stationId) : null;
        const rm = client ?? new RmClient(await requireCfg(stationId, 'rm_api'));
        const time = await rm.serverTime();
        const lic = await rm.validez();
        ok = time.ok;
        note = ok ? `ServerTime ${time.status}` : `ServerTime ${time.status}: ${time.raw.slice(0, 120)}`;
        detail = { serverTime: time.data ?? time.raw.slice(0, 200), validez: lic.data ?? lic.raw.slice(0, 200) };
      } else if (row.kind === 'pts2link') {
        const client = stationId ? await ptsLinkFor(stationId) : null;
        const link = client ?? new PtsLinkClient(await requireCfg(stationId, 'pts2link'));
        const health = await link.health();
        const pumps = await link.pumps();
        ok = !!health || !!pumps;
        note = ok ? `health ${JSON.stringify(health ?? {})}` : 'sin respuesta';
        detail = { health, pumps };
      } else if (row.kind === 'pts_direct') {
        const direct = stationId ? await ptsDirectFor(stationId) : null;
        if (!direct) {
          note = 'enlace deshabilitado (habilítalo para probarlo)';
        } else {
          detail = await direct.dateTime();
          ok = true;
          note = 'jsonPTS respondió y la huella TLS coincide';
        }
      } else {
        note = 'tipo sin prueba automática';
      }
    } catch (e) {
      ok = false;
      note = (e as Error).message;
    }

    await query('UPDATE integrations SET last_check_at = now(), last_check_ok = $2, last_check_note = $3 WHERE id = $1', [
      id,
      ok,
      note.slice(0, 400),
    ]);
    await query(
      "INSERT INTO integration_events (integration_id, actor, action, detail) VALUES ($1,'console','tested',$2)",
      [id, JSON.stringify({ ok, note: note.slice(0, 200) })],
    );
    return { ok, note, detail };
  });

  app.get('/v1/admin/integrations/:id/events', async (req) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(req.params);
    return query('SELECT * FROM integration_events WHERE integration_id = $1 ORDER BY id DESC LIMIT 50', [id]);
  });
}

async function requireCfg(stationId: string | null, k: 'rm_api' | 'pts2link') {
  const cfg = stationId ? await getIntegration(stationId, k) : null;
  if (!cfg) throw new Error('El enlace no está asociado a una estación activa');
  return cfg;
}

/** Nunca devolvemos secretos: sólo si están puestos y sus últimos 4. */
function publicShape(row: any) {
  if (!row) return null;
  const { secret_enc, extra_enc, ...rest } = row;
  return {
    ...rest,
    hasSecret: !!secret_enc,
    secretMasked: maskSecret(secret_enc),
    hasExtra: !!extra_enc,
  };
}
