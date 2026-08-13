import cors from '@fastify/cors';
import websocket from '@fastify/websocket';
import Fastify from 'fastify';
import { ZodError } from 'zod';

import { config } from './config.js';
import { pool } from './db.js';
import { verifyToken } from './auth/jwt.js';
import { attach, subscribeOrder, subscribeStation } from './realtime/hub.js';
import adminRoutes from './routes/admin.js';
import authRoutes from './routes/auth.js';
import catalogRoutes from './routes/catalog.js';
import orderRoutes from './routes/orders.js';
import taskRoutes from './routes/tasks.js';
import tenantRoutes from './routes/tenants.js';
import { startHoldWatcher } from './workers/holds.js';
import { startOutboxWorker } from './workers/outbox.js';
import { startPumpPoller } from './workers/pumpPoller.js';

const app = Fastify({
  logger: { level: config.logLevel, transport: config.env === 'development' ? undefined : undefined },
});

await app.register(cors, { origin: true });
await app.register(websocket);

app.setErrorHandler((err, req, reply) => {
  if (err instanceof ZodError) {
    return reply.code(400).send({ error: 'validation_error', issues: err.issues });
  }
  const status = (err as { statusCode?: number }).statusCode ?? 500;
  if (status >= 500) req.log.error({ err }, 'error no manejado');
  return reply.code(status).send({ error: err.name || 'error', message: err.message });
});

await app.register(authRoutes);
await app.register(catalogRoutes);
await app.register(orderRoutes);
await app.register(taskRoutes);
// Guardia de /v1/admin/*: si ADMIN_TOKEN está puesto se exige.
app.addHook('onRequest', async (req, reply) => {
  if (!req.url.startsWith('/v1/admin')) return;
  if (!config.adminToken) return;
  const header = req.headers['x-admin-token'];
  const bearer = (req.headers.authorization ?? '').replace(/^Bearer /i, '');
  if (header !== config.adminToken && bearer !== config.adminToken) {
    return reply.code(401).send({ error: 'unauthorized', message: 'Falta x-admin-token' });
  }
});

await app.register(adminRoutes);
await app.register(tenantRoutes);

/**
 * WebSocket de tiempo real.
 *   ws://host/v1/stream?token=<jwt>
 *   → { "subscribe": "order", "id": "<uuid>" }
 *   → { "subscribe": "station", "id": "<uuid>" }
 */
app.get('/v1/stream', { websocket: true }, (socket, req) => {
  const token = (req.query as { token?: string })?.token ?? '';
  const principal = verifyToken(token);
  if (!principal) {
    socket.send(JSON.stringify({ error: 'unauthorized' }));
    socket.close();
    return;
  }
  const client = attach(socket);
  if (principal.kind === 'employee') subscribeStation(client, principal.stationId);
  socket.send(JSON.stringify({ hello: principal.kind, at: new Date().toISOString() }));

  socket.on('message', (buf: Buffer) => {
    try {
      const msg = JSON.parse(buf.toString()) as { subscribe?: string; id?: string };
      if (msg.subscribe === 'order' && msg.id) subscribeOrder(client, msg.id);
      if (msg.subscribe === 'station' && msg.id) subscribeStation(client, msg.id);
      socket.send(JSON.stringify({ subscribed: msg.subscribe, id: msg.id }));
    } catch {
      socket.send(JSON.stringify({ error: 'bad_message' }));
    }
  });
});

const stopPumps = startPumpPoller();
const stopOutbox = startOutboxWorker();
const stopHolds = startHoldWatcher();

for (const sig of ['SIGINT', 'SIGTERM'] as const) {
  process.on(sig, async () => {
    app.log.info('cerrando…');
    stopPumps();
    stopOutbox();
    stopHolds();
    await app.close();
    await pool.end();
    process.exit(0);
  });
}

await app.listen({ port: config.port, host: '0.0.0.0' });
app.log.info(
  `Broker Octano escuchando en :${config.port} · multi-tenant · endpoints por estación en la tabla integrations`,
);
