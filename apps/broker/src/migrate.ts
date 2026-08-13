import { readdir, readFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { pool, query } from './db.js';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = resolve(here, '..', 'db', 'migrations');

const seedOnly = process.argv.includes('--seed');

async function ensureTable() {
  await query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name       text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);
}

async function run() {
  await ensureTable();
  const files = (await readdir(migrationsDir))
    .filter((f) => f.endsWith('.sql'))
    .filter((f) => (seedOnly ? f.includes('seed') : true))
    .sort();

  const applied = new Set((await query<{ name: string }>('SELECT name FROM schema_migrations')).map((r) => r.name));

  for (const file of files) {
    if (applied.has(file) && !file.includes('seed')) {
      console.log(`· ${file} ya aplicada`);
      continue;
    }
    const sql = await readFile(join(migrationsDir, file), 'utf8');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query(
        'INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT (name) DO UPDATE SET applied_at = now()',
        [file],
      );
      await client.query('COMMIT');
      console.log(`✓ ${file}`);
    } catch (e) {
      await client.query('ROLLBACK');
      console.error(`✗ ${file}:`, (e as Error).message);
      process.exitCode = 1;
      break;
    } finally {
      client.release();
    }
  }
  await pool.end();
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
