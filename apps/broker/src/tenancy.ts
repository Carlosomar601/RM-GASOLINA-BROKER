import { one, query } from './db.js';
import { decryptSecret } from './crypto.js';
import { config } from './config.js';

/**
 * Resolución de configuración por estación. Un broker sirve a muchos
 * clientes (tenants); cada estación apunta a su propio Retail Manager,
 * su propio PTS2Link y sus propias reglas de negocio.
 *
 * Orden de resolución para un `kind`:
 *   1. integrations con station_id = la estación (is_primary primero)
 *   2. integrations del tenant con station_id NULL (valor por omisión)
 *   3. valores del .env (solo desarrollo / primer arranque)
 */

export type IntegrationKind = 'rm_api' | 'pts2link' | 'pts_direct' | 'payments' | 'push';

export type Integration = {
  id: string;
  tenantId: string;
  stationId: string | null;
  kind: IntegrationKind;
  label: string;
  baseUrl: string;
  authType: 'none' | 'basic' | 'digest' | 'bearer' | 'apikey' | 'query';
  username: string | null;
  secret: string | null;
  extra: Record<string, unknown>;
  timeoutMs: number;
  verifyTls: boolean;
  tlsFingerprint: string | null;
  settings: Record<string, any>;
  enabled: boolean;
};

export type StationRules = {
  holdTtlMinutes: number;
  maxAuthAmount: number;
  minAuthAmount: number;
  cityTaxRate: number;
  stateTaxRate: number;
  fuelTaxable: boolean;
  itemsTaxable: boolean;
  invoiceSeries: string;
  defaultRmClient: string;
};

type CacheEntry = { value: Integration | null; at: number };
const cache = new Map<string, CacheEntry>();
const rulesCache = new Map<string, { value: StationRules; at: number }>();
const TTL_MS = 30_000;

export function invalidateStation(stationId?: string) {
  if (!stationId) {
    cache.clear();
    rulesCache.clear();
    return;
  }
  for (const k of [...cache.keys()]) if (k.startsWith(`${stationId}:`)) cache.delete(k);
  rulesCache.delete(stationId);
}

export async function getIntegration(
  stationId: string,
  kind: IntegrationKind,
): Promise<Integration | null> {
  const key = `${stationId}:${kind}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.value;

  const row = await one<any>(
    `SELECT i.*, s.tenant_id AS station_tenant
       FROM stations s
       JOIN integrations i
         ON i.enabled
        AND i.kind = $2
        AND (i.station_id = s.id OR (i.station_id IS NULL AND i.tenant_id = s.tenant_id))
      WHERE s.id = $1
      ORDER BY (i.station_id IS NOT NULL) DESC, i.is_primary DESC, i.created_at
      LIMIT 1`,
    [stationId, kind],
  );

  const value = row ? hydrate(row) : fallback(kind);
  cache.set(key, { value, at: Date.now() });
  return value;
}

function hydrate(row: any): Integration {
  let extra: Record<string, unknown> = {};
  const decoded = decryptSecret(row.extra_enc);
  if (decoded) {
    try {
      extra = JSON.parse(decoded) as Record<string, unknown>;
    } catch {
      extra = {};
    }
  }
  return {
    id: row.id,
    tenantId: row.tenant_id,
    stationId: row.station_id,
    kind: row.kind,
    label: row.label,
    baseUrl: String(row.base_url).replace(/\/+$/, ''),
    authType: row.auth_type,
    username: row.username,
    secret: decryptSecret(row.secret_enc),
    extra,
    timeoutMs: Number(row.timeout_ms ?? 8000),
    verifyTls: !!row.verify_tls,
    tlsFingerprint: row.tls_fingerprint,
    settings: row.settings ?? {},
    enabled: !!row.enabled,
  };
}

/** Solo para desarrollo: si no hay fila configurada, usa el .env. */
function fallback(kind: IntegrationKind): Integration | null {
  const base = {
    id: 'env',
    tenantId: 'env',
    stationId: null,
    label: '.env (fallback)',
    username: null,
    secret: process.env.RM_API_USER_PASS ?? null,
    extra: {},
    verifyTls: true,
    tlsFingerprint: null,
    enabled: true,
  };
  if (kind === 'rm_api') {
    return {
      ...base,
      kind,
      baseUrl: config.defaults.rmBase,
      authType: 'query',
      username: config.defaults.rmUserId,
      timeoutMs: config.defaults.rmTimeoutMs,
      settings: {
        userId: config.defaults.rmUserId,
        channel: config.defaults.rmChannel,
        fuelMop: config.defaults.rmFuelMop,
        pathPrefix: 'cse.api.v1',
        fuelProductCode: 'FUEL',
      },
    };
  }
  if (kind === 'pts2link') {
    return {
      ...base,
      kind,
      baseUrl: config.defaults.ptsLinkBase,
      authType: process.env.PTS2LINK_TOKEN ? 'bearer' : 'none',
      secret: process.env.PTS2LINK_TOKEN ?? null,
      timeoutMs: 6000,
      settings: {
        wsUrl: process.env.PTS2LINK_WS ?? '',
        paths: {
          health: '/api/health',
          controllers: '/api/controllers',
          pumps: '/api/pumps',
          pumpStatus: '/api/pumps/{pump}/status',
          tanks: '/api/tanks',
          mappings: '/api/mappings',
        },
      },
    };
  }
  return null;
}

export async function getRules(stationId: string): Promise<StationRules> {
  const hit = rulesCache.get(stationId);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.value;

  const r = await one<any>('SELECT * FROM station_rules WHERE station_id = $1', [stationId]);
  const value: StationRules = {
    holdTtlMinutes: Number(r?.hold_ttl_minutes ?? config.rules.holdTtlMinutes),
    maxAuthAmount: Number(r?.max_auth_amount ?? config.rules.maxAuthAmount),
    minAuthAmount: Number(r?.min_auth_amount ?? 5),
    cityTaxRate: Number(r?.city_tax_rate ?? 0),
    stateTaxRate: Number(r?.state_tax_rate ?? 0),
    fuelTaxable: !!r?.fuel_taxable,
    itemsTaxable: r?.items_taxable ?? true,
    invoiceSeries: r?.invoice_series ?? 'M',
    defaultRmClient: r?.default_rm_client ?? '0000',
  };
  rulesCache.set(stationId, { value, at: Date.now() });
  return value;
}

/** Estaciones que el poller debe vigilar (una por enlace PTS2Link activo). */
export async function activeStations(): Promise<{ id: string; code: string; tenant_id: string }[]> {
  return query(`SELECT id, code, tenant_id FROM stations WHERE status = 'active' ORDER BY code`);
}

export async function stationOfOrder(orderId: string): Promise<string | null> {
  const row = await one<{ station_id: string }>('SELECT station_id FROM orders WHERE id = $1', [orderId]);
  return row?.station_id ?? null;
}
