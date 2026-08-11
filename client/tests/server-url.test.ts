import { describe, expect, it } from 'vitest';
import { normalizeServerUrl, ServerUrlError } from '../src/main/server-url';

describe('normalizeServerUrl', () => {
  it('keeps only the server origin', () => {
    expect(normalizeServerUrl('  HTTPS://Example.com:443/  ')).toBe(
      'https://example.com',
    );
  });

  it('rejects API paths, credentials, queries, and unsupported schemes', () => {
    for (const value of [
      'https://example.com/api/v1',
      'https://user:pass@example.com',
      'https://example.com?token=secret',
      'file:///tmp/nexusroom',
      'example.com:8080',
    ]) {
      expect(() => normalizeServerUrl(value)).toThrow(ServerUrlError);
    }
  });
});
