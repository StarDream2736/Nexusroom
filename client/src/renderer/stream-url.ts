import { normalizeServerUrl } from '../main/server-url';

export const STREAM_KEY_PATTERN = /^[A-Za-z0-9_-]{8,128}$/u;

export class StreamUrlError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StreamUrlError';
  }
}

export function isValidStreamKey(value: string): boolean {
  return STREAM_KEY_PATTERN.test(value);
}

export function assertValidStreamKey(value: string, label = 'stream key'): string {
  if (typeof value !== 'string' || !isValidStreamKey(value)) {
    throw new StreamUrlError(
      `${label} must contain 8-128 ASCII letters, numbers, hyphens, or underscores`,
    );
  }
  return value;
}

function formatHost(hostname: string): string {
  const host = hostname.replace(/^\[|\]$/gu, '');
  return host.includes(':') ? `[${host}]` : host;
}

export function buildRtcStreamUrl(serverUrl: string, streamKey: string): string {
  const normalized = normalizeServerUrl(serverUrl);
  const server = new URL(normalized);
  const key = assertValidStreamKey(streamKey);
  const port = server.port || (server.protocol === 'https:' ? '443' : '80');
  const schema = server.protocol === 'https:' ? 'https' : 'http';
  return `webrtc://${formatHost(server.hostname)}:${port}/live/${key}?play=/api/v1/web/rtc/play/&schema=${schema}`;
}

export function buildFlvStreamUrl(serverUrl: string, streamKey: string): string {
  const normalized = normalizeServerUrl(serverUrl);
  const key = assertValidStreamKey(streamKey);
  return new URL(`/api/v1/stream/${encodeURIComponent(key)}`, normalized).toString();
}
