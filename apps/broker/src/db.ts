import pg from 'pg';
import { config } from './config.js';

// numeric → number (los montos de esta app caben sin problema en double)
pg.types.setTypeParser(1700, (v: string) => (v === null ? null : Number(v)));
pg.types.setTypeParser(20, (v: string) => (v === null ? null : Number(v)));

export const pool = new pg.Pool({
  connectionString: config.db.url,
  max: 10,
  idleTimeoutMillis: 30_000,
});

export type Row = Record<string, any>;

export async function query<T extends Row = Row>(sql: string, params: unknown[] = []): Promise<T[]> {
  const res = await pool.query(sql, params as any[]);
  return res.rows as T[];
}

export async function one<T extends Row = Row>(sql: string, params: unknown[] = []): Promise<T | null> {
  const rows = await query<T>(sql, params);
  return rows[0] ?? null;
}

export async function oneOrFail<T extends Row = Row>(
  sql: string,
  params: unknown[] = [],
  message = 'No encontrado',
): Promise<T> {
  const row = await one<T>(sql, params);
  if (!row) {
    const err = new Error(message) as Error & { statusCode?: number };
    err.statusCode = 404;
    throw err;
  }
  return row;
}

/** Ejecuta fn dentro de una transacción; hace rollback ante cualquier error. */
export async function tx<T>(fn: (c: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const out = await fn(client);
    await client.query('COMMIT');
    return out;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}
