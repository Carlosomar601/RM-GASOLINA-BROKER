import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';

import { config } from './config.js';

/**
 * Cifrado de secretos en reposo (contraseñas de RM, tokens de PTS2Link,
 * llaves del procesador). AES-256-GCM; la llave se deriva de MASTER_KEY.
 * Formato guardado: v1:<iv b64>:<tag b64>:<cipher b64>
 */

const key = createHash('sha256').update(config.masterKey).digest();

export function encryptSecret(plain: string | null | undefined): string | null {
  if (plain === null || plain === undefined || plain === '') return null;
  const iv = randomBytes(12);
  const c = createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
  return `v1:${iv.toString('base64')}:${c.getAuthTag().toString('base64')}:${enc.toString('base64')}`;
}

export function decryptSecret(stored: string | null | undefined): string | null {
  if (!stored) return null;
  const parts = stored.split(':');
  if (parts.length !== 4 || parts[0] !== 'v1') return null;
  try {
    const [, iv, tag, data] = parts as [string, string, string, string];
    const d = createDecipheriv('aes-256-gcm', key, Buffer.from(iv, 'base64'));
    d.setAuthTag(Buffer.from(tag, 'base64'));
    return Buffer.concat([d.update(Buffer.from(data, 'base64')), d.final()]).toString('utf8');
  } catch {
    return null;
  }
}

/** Para mostrar en la consola sin revelar el secreto. */
export function maskSecret(stored: string | null | undefined): string | null {
  const plain = decryptSecret(stored);
  if (!plain) return null;
  if (plain.length <= 4) return '••••';
  return `${'•'.repeat(Math.max(4, plain.length - 4))}${plain.slice(-4)}`;
}
