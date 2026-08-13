import { getIntegration, type Integration } from '../tenancy.js';

/**
 * Cliente de la API v2 de Retail Manager (cse.api.v1) **por estación**.
 * Cada estación/POS trae su propio base_url, usuario, canal y prefijo de
 * ruta desde la tabla `integrations`, así un mismo broker atiende a varios
 * clientes con varios Retail Manager a la vez.
 *
 *   const rm = await rmFor(stationId);
 *   await rm.fuelPumpAuthorize({ ... });
 */

export type RmResult<T = unknown> = {
  ok: boolean;
  status: number;
  data: T | null;
  raw: string;
  endpoint: string;
};

export type RmInvoiceItem = {
  ProductCode: string;
  Description: string;
  Quantity: number;
  Price: number;
  Cost?: number;
};

export type RmInvoice = {
  Factura: string;
  OrdenNumero: string;
  Cliente: string;
  Fecha: string;
  Vendedor: string;
  Subtotal: number;
  Descuento: number;
  Total: number;
  CityTax: number;
  StateTax: number;
  PaidCash?: number;
  PaidCredit?: number;
  Items: RmInvoiceItem[];
};

export class RmClient {
  constructor(private readonly cfg: Integration) {}

  get label() {
    return this.cfg.label;
  }
  get baseUrl() {
    return this.cfg.baseUrl;
  }
  get userId(): string {
    return String(this.cfg.settings.userId ?? this.cfg.username ?? '2');
  }
  get channel(): number {
    return Number(this.cfg.settings.channel ?? 1);
  }
  get fuelMop(): string {
    return String(this.cfg.settings.fuelMop ?? 'CREDIT');
  }
  /** ProductCode que el POS espera para la línea de combustible. */
  get fuelProductCode(): string {
    return String(this.cfg.settings.fuelProductCode ?? 'FUEL');
  }

  private url(endpoint: string, params: Record<string, string | number | undefined> = {}): string {
    const prefix = String(this.cfg.settings.pathPrefix ?? 'cse.api.v1').replace(/^\/+|\/+$/g, '');
    const u = new URL(`${this.cfg.baseUrl}/${prefix}/${endpoint}`);
    for (const [k, v] of Object.entries(params)) {
      if (v !== undefined && v !== null && v !== '') u.searchParams.set(k, String(v));
    }
    // Algunos despliegues exigen credenciales en la query
    if (this.cfg.authType === 'query' && this.cfg.secret) {
      u.searchParams.set('UserID', this.userId);
      u.searchParams.set('UserPass', this.cfg.secret);
    }
    if (this.cfg.authType === 'apikey' && this.cfg.secret) {
      u.searchParams.set(String(this.cfg.settings.apiKeyParam ?? 'ApiKey'), this.cfg.secret);
    }
    return u.toString();
  }

  private headers(): Record<string, string> {
    const h: Record<string, string> = { accept: 'application/json' };
    if (this.cfg.authType === 'bearer' && this.cfg.secret) h.authorization = `Bearer ${this.cfg.secret}`;
    if (this.cfg.authType === 'basic' && this.cfg.username) {
      const raw = `${this.cfg.username}:${this.cfg.secret ?? ''}`;
      h.authorization = `Basic ${Buffer.from(raw).toString('base64')}`;
    }
    return h;
  }

  async call<T>(
    endpoint: string,
    params: Record<string, string | number | undefined> = {},
    method: 'GET' | 'POST' = 'GET',
  ): Promise<RmResult<T>> {
    const target = this.url(endpoint, params);
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), this.cfg.timeoutMs);
    try {
      const res = await fetch(target, { method, headers: this.headers(), signal: ac.signal });
      const raw = await res.text();
      let data: T | null = null;
      try {
        data = raw ? (JSON.parse(raw) as T) : null;
      } catch {
        data = null;
      }
      return { ok: res.ok, status: res.status, data, raw, endpoint };
    } catch (e) {
      return { ok: false, status: 0, data: null, raw: (e as Error).message, endpoint };
    } finally {
      clearTimeout(timer);
    }
  }

  // ── Diagnóstico ──────────────────────────────────────────────────
  serverTime = () => this.call<unknown>('ServerTime');
  validez = () => this.call<unknown>('Validez');
  validateUser = (userId: string | number, userPass: string) =>
    this.call<unknown>('ValidateUser', { UserID: userId, UserPass: userPass });

  // ── Catálogo ─────────────────────────────────────────────────────
  getAllProducts = (opts: { active?: boolean; web?: boolean; department?: string } = {}) =>
    this.call<unknown[]>('GetAllProducts', {
      Active: opts.active === false ? 'False' : 'True',
      Web: opts.web ? 'True' : 'False',
      Department: opts.department,
    });
  productInfo = (itemCode: string) => this.call<unknown>('ProductInfo', { ItemCode: itemCode });
  productByBarcode = (barcode: string) => this.call<unknown>('ProductInfo', { Barcode: barcode });

  // ── Combustible (requiere esquema FDLink nuevo) ──────────────────
  fuelPrices = (grade?: number) => this.call<unknown[]>('FuelPrices', { Grade: grade });
  fuelTanks = (tank?: number) => this.call<unknown[]>('FuelTanks', { Tank: tank });
  fuelPumpStatus = (pump?: number) => this.call<unknown>('FuelPumpStatus', { Pump: pump });
  fuelRequestStatus = (requestId: string) => this.call<unknown>('FuelRequestStatus', { RequestId: requestId });

  fuelPumpAuthorize = (args: {
    pump: number;
    hose: number;
    amount: number;
    requestId: string;
    paymentRef: string;
    controllerId: number;
    mop?: string;
  }) =>
    this.call<unknown>(
      'FuelPumpAuthorize',
      {
        Pump: args.pump,
        Hose: args.hose,
        Amount: args.amount.toFixed(2),
        MOP: args.mop ?? this.fuelMop,
        Channel: this.channel,
        RequestId: args.requestId,
        PaymentRef: args.paymentRef,
        ControllerId: args.controllerId,
      },
      'POST',
    );

  fuelSetPrice = (args: { grade: number; servLevel: number; tier1: number; tier2?: number; reload?: boolean }) =>
    this.call<unknown>(
      'FuelSetPrice',
      {
        Grade: args.grade,
        ServLevel: args.servLevel,
        Tier1: args.tier1.toFixed(2),
        Tier2: (args.tier2 ?? args.tier1).toFixed(2),
        Reload: args.reload ? 'YES' : 'NO',
        Channel: this.channel,
      },
      'POST',
    );

  importExternalInvoice = (invoice: RmInvoice) =>
    this.call<unknown>('ImportExternalInvoice', { InvoiceData: JSON.stringify(invoice) }, 'POST');
}

export class MissingIntegrationError extends Error {
  statusCode = 424;
  constructor(kind: string, stationId: string) {
    super(`La estación ${stationId} no tiene configurado el enlace "${kind}"`);
  }
}

export async function rmFor(stationId: string): Promise<RmClient> {
  const cfg = await getIntegration(stationId, 'rm_api');
  if (!cfg) throw new MissingIntegrationError('rm_api', stationId);
  return new RmClient(cfg);
}

export async function rmForOrNull(stationId: string): Promise<RmClient | null> {
  const cfg = await getIntegration(stationId, 'rm_api');
  return cfg ? new RmClient(cfg) : null;
}
