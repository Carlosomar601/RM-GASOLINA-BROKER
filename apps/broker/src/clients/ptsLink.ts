import { getIntegration, type Integration } from '../tenancy.js';

/**
 * Cliente de PTS2Link **por estación**. PTS2Link es dueño del enlace con el
 * PTS-2 (jsonPTS, huella TLS, mapeos POSDPS); el broker sólo lo consulta.
 *
 * Las rutas son configurables por estación en integrations.settings.paths,
 * porque distintos despliegues exponen distintos paths:
 *   { "health": "/api/health", "pumps": "/api/pumps",
 *     "pumpStatus": "/api/pumps/{pump}/status", "tanks": "/api/tanks" }
 */

export type PtsPumpStatus = {
  pump: number;
  state: string;
  nozzle?: number;
  volume?: number;
  amount?: number;
  price?: number;
  transaction?: number;
};

export type PtsTankReading = {
  tank: number;
  probe?: number;
  volume?: number;
  height?: number;
  temperature?: number;
  water?: number;
};

const defaultPaths: Record<string, string> = {
  health: '/api/health',
  controllers: '/api/controllers',
  pumps: '/api/pumps',
  pumpStatus: '/api/pumps/{pump}/status',
  tanks: '/api/tanks',
  mappings: '/api/mappings',
};

export class PtsLinkClient {
  constructor(private readonly cfg: Integration) {}

  get label() {
    return this.cfg.label;
  }
  get baseUrl() {
    return this.cfg.baseUrl;
  }
  get wsUrl(): string | null {
    return (this.cfg.settings.wsUrl as string | undefined) ?? null;
  }

  private path(name: string, vars: Record<string, string | number> = {}): string {
    const paths = { ...defaultPaths, ...((this.cfg.settings.paths as Record<string, string>) ?? {}) };
    let p = paths[name] ?? defaultPaths[name] ?? `/${name}`;
    for (const [k, v] of Object.entries(vars)) p = p.replace(`{${k}}`, String(v));
    return p;
  }

  private headers(): Record<string, string> {
    const h: Record<string, string> = { 'content-type': 'application/json' };
    if (this.cfg.authType === 'bearer' && this.cfg.secret) h.authorization = `Bearer ${this.cfg.secret}`;
    if (this.cfg.authType === 'apikey' && this.cfg.secret) {
      h[String(this.cfg.settings.apiKeyHeader ?? 'x-api-key')] = this.cfg.secret;
    }
    if (this.cfg.authType === 'basic' && this.cfg.username) {
      h.authorization = `Basic ${Buffer.from(`${this.cfg.username}:${this.cfg.secret ?? ''}`).toString('base64')}`;
    }
    return h;
  }

  private async call<T>(name: string, vars: Record<string, string | number> = {}): Promise<T | null> {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), this.cfg.timeoutMs);
    try {
      const res = await fetch(`${this.cfg.baseUrl}${this.path(name, vars)}`, {
        headers: this.headers(),
        signal: ac.signal,
      });
      if (!res.ok) return null;
      const text = await res.text();
      return text ? (JSON.parse(text) as T) : null;
    } catch {
      return null;
    } finally {
      clearTimeout(timer);
    }
  }

  health = () => this.call<{ status?: string }>('health');
  controllers = () => this.call<unknown[]>('controllers');
  pumps = () => this.call<PtsPumpStatus[]>('pumps');
  pumpStatus = (pump: number) => this.call<PtsPumpStatus>('pumpStatus', { pump });
  tanks = () => this.call<PtsTankReading[]>('tanks');
  mappings = () => this.call<unknown>('mappings');
}

export async function ptsLinkFor(stationId: string): Promise<PtsLinkClient | null> {
  const cfg = await getIntegration(stationId, 'pts2link');
  return cfg ? new PtsLinkClient(cfg) : null;
}

/** Normaliza los estados del PTS-2 al vocabulario de la tabla pumps. */
export function normalizePumpState(state: string | undefined): string {
  switch ((state ?? '').toUpperCase()) {
    case 'IDLE':
    case 'READY':
      return 'idle';
    case 'AUTHORIZED':
      return 'authorized';
    case 'FILLING':
    case 'DISPENSING':
      return 'filling';
    case 'END_OF_TRANSACTION':
    case 'EOT':
      return 'end_of_transaction';
    case 'OFFLINE':
      return 'offline';
    case 'BLOCKED':
      return 'blocked';
    default:
      return 'unknown';
  }
}
