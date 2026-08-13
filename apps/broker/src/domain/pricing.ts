import { one, query } from '../db.js';
import { rmForOrNull } from '../clients/rmApi.js';
import { round2 } from './orders.js';

/**
 * Precios: el Retail Manager de CADA estación es la fuente autorizada. El
 * broker espeja el precio vigente en fuel_prices y congela el precio de la
 * orden al autorizar, para que el recibo cuadre con lo cobrado.
 */

export async function currentPrice(fuelProductId: string, priceLevel = 1): Promise<number | null> {
  const row = await one<{ price: number }>(
    `SELECT price FROM fuel_prices
      WHERE fuel_product_id = $1 AND price_level = $2
      ORDER BY effective_from DESC LIMIT 1`,
    [fuelProductId, priceLevel],
  );
  return row?.price ?? null;
}

/** Trae FuelPrices del RM de esa estación y guarda los cambios. */
export async function syncPricesFromRm(stationId: string): Promise<{ updated: number; skipped: number; source: string }> {
  const rm = await rmForOrNull(stationId);
  if (!rm) return { updated: 0, skipped: 0, source: 'sin enlace rm_api' };

  const products = await query<{ id: string; pts_grade_id: number }>(
    'SELECT id, pts_grade_id FROM fuel_products WHERE station_id = $1',
    [stationId],
  );

  let updated = 0;
  let skipped = 0;

  for (const p of products) {
    const res = await rm.fuelPrices(p.pts_grade_id);
    const price = extractPrice(res.data);
    if (!res.ok || price === null) {
      skipped++;
      continue;
    }
    const cur = await currentPrice(p.id, 1);
    if (cur !== null && round2(cur) === round2(price)) continue;
    await query(
      "INSERT INTO fuel_prices (fuel_product_id, price_level, price, source) VALUES ($1, 1, $2, 'rm_api')",
      [p.id, price],
    );
    updated++;
  }
  return { updated, skipped, source: rm.label };
}

/** La RM API varía en la forma de la respuesta; buscamos Tier1/Price/Precio. */
function extractPrice(data: unknown): number | null {
  const pick = (o: Record<string, unknown>): number | null => {
    for (const k of ['Tier1', 'Price', 'Precio', 'tier1', 'price']) {
      const v = o[k];
      if (typeof v === 'number') return v;
      if (typeof v === 'string' && v.trim() !== '' && !Number.isNaN(Number(v))) return Number(v);
    }
    return null;
  };
  if (!data) return null;
  if (Array.isArray(data)) {
    for (const item of data) {
      if (item && typeof item === 'object') {
        const v = pick(item as Record<string, unknown>);
        if (v !== null) return v;
      }
    }
    return null;
  }
  if (typeof data === 'object') return pick(data as Record<string, unknown>);
  return null;
}

export function litersFor(amount: number, price: number): number {
  if (!price) return 0;
  return Math.round((amount / price) * 1000) / 1000;
}
