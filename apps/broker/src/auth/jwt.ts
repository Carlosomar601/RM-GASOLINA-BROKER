import { createHmac, timingSafeEqual, randomUUID, scryptSync, randomBytes } from 'node:crypto';
import type { FastifyReply, FastifyRequest } from 'fastify';

import { config } from '../config.js';

export type Principal =
  | { kind: 'customer'; id: string }
  | { kind: 'employee'; id: string; stationId: string; role: string };

type Payload = Principal & { iat: number; exp: number; jti: string };

const b64 = (b: Buffer | string) =>
  Buffer.from(b).toString('base64url');

function sign(data: string): string {
  return createHmac('sha256', config.jwt.secret).update(data).digest('base64url');
}

export function issueToken(p: Principal): { token: string; expiresAt: string } {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + config.jwt.ttlHours * 3600;
  const body: Payload = { ...p, iat: now, exp, jti: randomUUID() };
  const head = b64(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const payload = b64(JSON.stringify(body));
  const token = `${head}.${payload}.${sign(`${head}.${payload}`)}`;
  return { token, expiresAt: new Date(exp * 1000).toISOString() };
}

export function verifyToken(token: string): Payload | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [head, payload, sig] = parts as [string, string, string];
  const expected = sign(`${head}.${payload}`);
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
  try {
    const body = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as Payload;
    if (body.exp * 1000 < Date.now()) return null;
    return body;
  } catch {
    return null;
  }
}

/** Contraseñas / PIN: scrypt con sal aleatoria, formato scrypt$sal$hash. */
export function hashSecret(secret: string): string {
  const salt = randomBytes(16).toString('hex');
  const hash = scryptSync(secret, salt, 64).toString('hex');
  return `scrypt$${salt}$${hash}`;
}

export function verifySecret(secret: string, stored: string | null): boolean {
  if (!stored) return false;
  const [scheme, salt, hash] = stored.split('$');
  if (scheme !== 'scrypt' || !salt || !hash) return false;
  const calc = scryptSync(secret, salt, 64).toString('hex');
  const a = Buffer.from(calc);
  const b = Buffer.from(hash);
  return a.length === b.length && timingSafeEqual(a, b);
}

declare module 'fastify' {
  interface FastifyRequest {
    principal?: Principal;
  }
}

function bearer(req: FastifyRequest): string | null {
  const h = req.headers.authorization;
  if (!h || !h.toLowerCase().startsWith('bearer ')) return null;
  return h.slice(7).trim();
}

export async function requireCustomer(req: FastifyRequest, reply: FastifyReply) {
  const t = bearer(req);
  const p = t ? verifyToken(t) : null;
  if (!p || p.kind !== 'customer') {
    return reply.code(401).send({ error: 'unauthorized', message: 'Token de cliente inválido' });
  }
  req.principal = { kind: 'customer', id: p.id };
}

export async function requireEmployee(req: FastifyRequest, reply: FastifyReply) {
  const t = bearer(req);
  const p = t ? verifyToken(t) : null;
  if (!p || p.kind !== 'employee') {
    return reply.code(401).send({ error: 'unauthorized', message: 'Token de empleado inválido' });
  }
  req.principal = { kind: 'employee', id: p.id, stationId: p.stationId, role: p.role };
}

export function customerId(req: FastifyRequest): string {
  if (req.principal?.kind !== 'customer') throw new Error('Principal no es cliente');
  return req.principal.id;
}

export function employee(req: FastifyRequest): { id: string; stationId: string; role: string } {
  if (req.principal?.kind !== 'employee') throw new Error('Principal no es empleado');
  return req.principal;
}
