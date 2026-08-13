import type { WebSocket } from '@fastify/websocket';

/**
 * Bus de tiempo real. Las apps se suscriben a su orden (cliente) o a la
 * estación (handheld) y reciben cada transición del ciclo de vida.
 */

type Client = { socket: WebSocket; orders: Set<string>; stations: Set<string> };

const clients = new Set<Client>();

export function attach(socket: WebSocket): Client {
  const c: Client = { socket, orders: new Set(), stations: new Set() };
  clients.add(c);
  socket.on('close', () => clients.delete(c));
  return c;
}

export function subscribeOrder(c: Client, orderId: string) {
  c.orders.add(orderId);
}

export function subscribeStation(c: Client, stationId: string) {
  c.stations.add(stationId);
}

function send(c: Client, msg: unknown) {
  try {
    c.socket.send(JSON.stringify(msg));
  } catch {
    clients.delete(c);
  }
}

export function publishOrder(orderId: string, type: string, payload: unknown) {
  const msg = { scope: 'order', orderId, type, payload, at: new Date().toISOString() };
  for (const c of clients) if (c.orders.has(orderId)) send(c, msg);
}

export function publishStation(stationId: string, type: string, payload: unknown) {
  const msg = { scope: 'station', stationId, type, payload, at: new Date().toISOString() };
  for (const c of clients) if (c.stations.has(stationId)) send(c, msg);
}

export function connectionCount(): number {
  return clients.size;
}
