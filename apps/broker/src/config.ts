import 'dotenv/config';

function str(key: string, fallback?: string): string {
  const v = process.env[key] ?? fallback;
  if (v === undefined) throw new Error(`Falta la variable de entorno ${key}`);
  return v;
}
function num(key: string, fallback: number): number {
  const v = process.env[key];
  return v === undefined || v === '' ? fallback : Number(v);
}
function bool(key: string, fallback = false): boolean {
  const v = process.env[key];
  if (v === undefined) return fallback;
  return ['1', 'true', 'yes', 'si', 'sí'].includes(v.toLowerCase());
}

export const config = {
  env: str('NODE_ENV', 'development'),
  port: num('PORT', 8090),
  logLevel: str('LOG_LEVEL', 'info'),
  /** Llave para cifrar secretos de integraciones en la base. */
  masterKey: str('MASTER_KEY', 'dev-master-key-cambiar'),
  /** Token de servicio para /v1/admin/* (vacío = abierto, solo en dev). */
  adminToken: process.env.ADMIN_TOKEN ?? '',
  jwt: {
    secret: str('JWT_SECRET', 'dev-secret-no-usar-en-produccion'),
    ttlHours: num('JWT_TTL_HOURS', 720),
  },
  db: { url: str('DATABASE_URL', 'postgres://octano:octano@localhost:5432/octano') },
  /**
   * Valores por omisión SOLO para el arranque y para sembrar la primera
   * estación. En operación cada estación trae sus propios endpoints en la
   * tabla `integrations` (multi-cliente / multi-POS).
   */
  defaults: {
    rmBase: str('RM_API_BASE', 'http://localhost:8180').replace(/\/+$/, ''),
    rmUserId: str('RM_API_USER_ID', '2'),
    rmChannel: num('RM_API_CHANNEL', 1),
    rmTimeoutMs: num('RM_API_TIMEOUT_MS', 8000),
    rmFuelMop: str('RM_FUEL_MOP', 'CREDIT'),
    ptsLinkBase: str('PTS2LINK_BASE', 'http://localhost:9080').replace(/\/+$/, ''),
    ptsDirectEnabled: bool('PTS_DIRECT_ENABLED', false),
  },
  rules: {
    holdTtlMinutes: num('HOLD_TTL_MINUTES', 60),
    maxAuthAmount: num('MAX_AUTH_AMOUNT', 200),
    pumpPollMs: num('PUMP_POLL_MS', 1500),
    outboxPollMs: num('OUTBOX_POLL_MS', 3000),
  },
} as const;

export type Config = typeof config;
