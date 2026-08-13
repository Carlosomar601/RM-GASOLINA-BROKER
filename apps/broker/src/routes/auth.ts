import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { one, query } from '../db.js';
import { hashSecret, issueToken, verifySecret } from '../auth/jwt.js';

export default async function authRoutes(app: FastifyInstance) {
  // ── Cliente ────────────────────────────────────────────────────────
  app.post('/v1/auth/customer/login', async (req, reply) => {
    const body = z.object({ phone: z.string().min(7), password: z.string().min(4) }).parse(req.body);
    const c = await one<{ id: string; password_hash: string | null; status: string }>(
      'SELECT id, password_hash, status FROM customers WHERE phone = $1',
      [normalizePhone(body.phone)],
    );
    if (!c || c.status !== 'active') return reply.code(401).send({ error: 'invalid_credentials' });
    // En desarrollo, un cliente sin password_hash acepta cualquier clave.
    if (c.password_hash && !verifySecret(body.password, c.password_hash)) {
      await audit('customer', 'LoginFailed', 'Session', c.id, 'fail', req.ip);
      return reply.code(401).send({ error: 'invalid_credentials' });
    }
    await audit(`customer:${c.id}`, 'LoginSucceeded', 'Session', c.id, 'ok', req.ip);
    return { ...issueToken({ kind: 'customer', id: c.id }), customerId: c.id };
  });

  app.post('/v1/auth/customer/register', async (req, reply) => {
    const body = z
      .object({
        phone: z.string().min(7),
        fullName: z.string().min(2),
        email: z.string().email().optional(),
        password: z.string().min(4),
        plate: z.string().min(3).optional(),
        vehicle: z.string().optional(),
        color: z.string().optional(),
        tankLiters: z.number().positive().optional(),
      })
      .parse(req.body);

    const phone = normalizePhone(body.phone);
    const exists = await one('SELECT id FROM customers WHERE phone = $1', [phone]);
    if (exists) return reply.code(409).send({ error: 'phone_taken' });

    const c = await one<{ id: string }>(
      `INSERT INTO customers (phone, full_name, email, password_hash)
       VALUES ($1,$2,$3,$4) RETURNING id`,
      [phone, body.fullName, body.email ?? null, hashSecret(body.password)],
    );
    const id = c!.id;
    await query('INSERT INTO wallets (customer_id, balance) VALUES ($1, 0)', [id]);
    if (body.plate) {
      await query(
        `INSERT INTO vehicles (customer_id, plate, make_model, color, tank_liters, is_default)
         VALUES ($1,$2,$3,$4,$5,true)`,
        [id, body.plate.toUpperCase(), body.vehicle ?? null, body.color ?? null, body.tankLiters ?? null],
      );
    }
    await audit(`customer:${id}`, 'CustomerCreated', 'Customer', id, 'ok', req.ip);
    return reply.code(201).send({ ...issueToken({ kind: 'customer', id }), customerId: id });
  });

  // ── Empleado (PIN + placa del handheld) ────────────────────────────
  app.post('/v1/auth/employee/login', async (req, reply) => {
    const body = z.object({ badge: z.string().min(3), pin: z.string().min(4) }).parse(req.body);
    const e = await one<{ id: string; station_id: string; role: string; pin_hash: string | null; active: boolean }>(
      'SELECT id, station_id, role, pin_hash, active FROM employees WHERE badge = $1',
      [body.badge.toUpperCase()],
    );
    if (!e || !e.active) return reply.code(401).send({ error: 'invalid_credentials' });
    if (e.pin_hash && !verifySecret(body.pin, e.pin_hash)) {
      await audit('employee', 'LoginFailed', 'Session', e.id, 'fail', req.ip);
      return reply.code(401).send({ error: 'invalid_credentials' });
    }
    await audit(`employee:${e.id}`, 'LoginSucceeded', 'Session', e.id, 'ok', req.ip);
    return {
      ...issueToken({ kind: 'employee', id: e.id, stationId: e.station_id, role: e.role }),
      employeeId: e.id,
      stationId: e.station_id,
      role: e.role,
    };
  });
}

export function normalizePhone(p: string): string {
  const digits = p.replace(/\D/g, '');
  if (digits.length === 10) return `+1${digits}`;
  if (digits.startsWith('1') && digits.length === 11) return `+${digits}`;
  return p.startsWith('+') ? p : `+${digits}`;
}

export async function audit(
  actor: string,
  action: string,
  entity: string,
  entityId: string | null,
  result: 'ok' | 'fail',
  ip?: string,
  detail: unknown = {},
) {
  await query(
    'INSERT INTO audit_log (actor, action, entity, entity_id, result, ip, detail) VALUES ($1,$2,$3,$4,$5,$6,$7)',
    [actor, action, entity, entityId, result, ip ?? null, JSON.stringify(detail ?? {})],
  );
}
