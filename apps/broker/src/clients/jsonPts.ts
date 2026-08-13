import { createHash, randomBytes } from 'node:crypto';
import https from 'node:https';
import type { TLSSocket } from 'node:tls';

import { getIntegration, type Integration } from '../tenancy.js';

/**
 * jsonPTS directo — SOLO diagnóstico o respaldo si PTS2Link está caído.
 * Digest + validación de huella SHA-256 del certificado autofirmado
 * (nunca desactiva TLS a ciegas). Se configura por estación como una
 * integración `pts_direct`, deshabilitada por defecto.
 *
 * Verificado contra 192.168.100.251 (firmware 2026.03.21) con consultas
 * de solo lectura: PumpGetStatus, ProbeGetMeasurements, GetConfiguration.
 */

type PtsPacket = { Id: number; Type: string; Data?: Record<string, unknown> };

const md5 = (s: string) => createHash('md5').update(s).digest('hex');

function digestHeader(challenge: string, method: string, uri: string, user: string, pass: string, nc = 1): string {
  const get = (k: string) => new RegExp(`${k}="?([^",]+)"?`).exec(challenge)?.[1] ?? '';
  const realm = get('realm');
  const nonce = get('nonce');
  const qop = get('qop') || 'auth';
  const opaque = get('opaque');
  const cnonce = randomBytes(8).toString('hex');
  const ncHex = nc.toString(16).padStart(8, '0');
  const ha1 = md5(`${user}:${realm}:${pass}`);
  const ha2 = md5(`${method}:${uri}`);
  const response = md5(`${ha1}:${nonce}:${ncHex}:${cnonce}:${qop}:${ha2}`);
  const bits = [
    `username="${user}"`,
    `realm="${realm}"`,
    `nonce="${nonce}"`,
    `uri="${uri}"`,
    `qop=${qop}`,
    `nc=${ncHex}`,
    `cnonce="${cnonce}"`,
    `response="${response}"`,
  ];
  if (opaque) bits.push(`opaque="${opaque}"`);
  return `Digest ${bits.join(', ')}`;
}

function post(
  cfg: Integration,
  path: string,
  body: string,
  authorization?: string,
): Promise<{ status: number; headers: Record<string, any>; body: string; fingerprint: string }> {
  const url = new URL(cfg.baseUrl);
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        host: url.hostname,
        port: Number(url.port || 443),
        path,
        method: 'POST',
        rejectUnauthorized: cfg.verifyTls,
        headers: {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(body),
          ...(authorization ? { authorization } : {}),
        },
        timeout: cfg.timeoutMs,
      },
      (res) => {
        const socket = res.socket as TLSSocket;
        const cert = socket.getPeerCertificate?.();
        const fingerprint = (cert?.fingerprint256 ?? '').replace(/:/g, '').toUpperCase();
        let out = '';
        res.on('data', (c) => (out += c));
        res.on('end', () => resolve({ status: res.statusCode ?? 0, headers: res.headers, body: out, fingerprint }));
      },
    );
    req.on('timeout', () => req.destroy(new Error('timeout hablando con el PTS-2')));
    req.on('error', reject);
    req.end(body);
  });
}

export class PtsDirectClient {
  constructor(private readonly cfg: Integration) {}

  private get path(): string {
    return String(this.cfg.settings.path ?? '/jsonPTS');
  }

  async send(packets: PtsPacket[]): Promise<unknown> {
    const body = JSON.stringify({ Protocol: 1, Packets: packets });
    let res = await post(this.cfg, this.path, body);

    if (this.cfg.tlsFingerprint && res.fingerprint && res.fingerprint !== this.cfg.tlsFingerprint.toUpperCase()) {
      throw new Error(
        `Huella TLS del PTS-2 no coincide (esperada ${this.cfg.tlsFingerprint}, recibida ${res.fingerprint})`,
      );
    }

    if (res.status === 401 && this.cfg.authType === 'digest') {
      const auth = digestHeader(
        String(res.headers['www-authenticate'] ?? ''),
        'POST',
        this.path,
        this.cfg.username ?? 'admin',
        this.cfg.secret ?? '',
      );
      res = await post(this.cfg, this.path, body, auth);
    }

    if (res.status !== 200) throw new Error(`PTS-2 respondió ${res.status}: ${res.body.slice(0, 200)}`);
    return JSON.parse(res.body);
  }

  pumpStatus = (pump: number) => this.send([{ Id: 1, Type: 'PumpGetStatus', Data: { Pump: pump } }]);
  probeMeasurements = (probe: number) =>
    this.send([{ Id: 1, Type: 'ProbeGetMeasurements', Data: { Probe: probe } }]);
  configuration = () => this.send([{ Id: 1, Type: 'GetConfiguration' }]);
  dateTime = () => this.send([{ Id: 1, Type: 'GetDateTime' }]);
}

export async function ptsDirectFor(stationId: string): Promise<PtsDirectClient | null> {
  const cfg = await getIntegration(stationId, 'pts_direct');
  return cfg && cfg.enabled ? new PtsDirectClient(cfg) : null;
}
