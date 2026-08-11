import { describe, expect, it } from 'vitest';
import { RestClient, RestError } from '../src/main/rest-client';

describe('RestClient', () => {
  it('adds the bearer token and unwraps the JSON envelope', async () => {
    let request: Request | undefined;
    const client = new RestClient({
      serverUrl: 'https://example.com/',
      token: 'token-value',
      fetchImpl: async (input, init) => {
        request = new Request(input, init);
        return new Response(
          JSON.stringify({ code: 20_000, message: 'ok', data: { id: 7 } }),
          { status: 200 },
        );
      },
    });

    await expect(client.get<{ id: number }>('/api/v1/users/me')).resolves.toEqual({
      id: 7,
    });
    expect(request?.url).toBe('https://example.com/api/v1/users/me');
    expect(request?.headers.get('Authorization')).toBe('Bearer token-value');
  });

  it('parses API errors without exposing the token', async () => {
    const client = new RestClient({
      serverUrl: 'https://example.com',
      token: 'do-not-log-this-token',
      fetchImpl: async () =>
        new Response(
          JSON.stringify({ code: 40_101, message: 'token expired', data: null }),
          { status: 401 },
        ),
    });

    const error = await client.get('/api/v1/users/me').catch((value: unknown) => value);
    expect(error).toBeInstanceOf(RestError);
    expect((error as RestError).status).toBe(401);
    expect((error as RestError).code).toBe(40_101);
    expect((error as RestError).message).toBe('token expired');
    expect(String(error)).not.toContain('do-not-log-this-token');
  });

  it('supports caller cancellation and timeout', async () => {
    const fetchImpl = async (
      _input: RequestInfo | URL,
      init?: RequestInit,
    ): Promise<Response> =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => {
          reject(new DOMException('aborted', 'AbortError'));
        });
      });
    const controller = new AbortController();
    const client = new RestClient({
      serverUrl: 'https://example.com',
      timeoutMs: 10,
      fetchImpl,
    });

    const cancelled = client.get('/ping', { signal: controller.signal });
    controller.abort();
    await expect(cancelled).rejects.toMatchObject({ kind: 'cancelled' });
    await expect(client.get('/ping')).rejects.toMatchObject({ kind: 'timeout' });
  });

  it('uploads FormData without overriding the multipart boundary', async () => {
    let request: Request | undefined;
    const client = new RestClient({
      serverUrl: 'https://example.com',
      token: 'upload-token',
      fetchImpl: async (input, init) => {
        request = new Request(input, init);
        return new Response(
          JSON.stringify({ code: 20_000, message: 'ok', data: { file_id: 'f1' } }),
          { status: 200 },
        );
      },
    });
    const form = new FormData();
    form.append('room_id', '7');
    form.append('file', new Blob(['image']), 'image.png');

    await expect(
      client.postForm('/api/v1/files/upload', form, {
        headers: { 'Content-Type': 'application/json' },
      }),
    ).resolves.toEqual({ file_id: 'f1' });
    expect(request?.headers.get('Authorization')).toBe('Bearer upload-token');
    expect(request?.headers.get('Content-Type')).toMatch(/^multipart\/form-data; boundary=/);
    if (request === undefined) {
      throw new Error('request was not captured');
    }
    const sent = await request.formData();
    expect(sent.get('room_id')).toBe('7');
    expect(sent.get('file')).toBeInstanceOf(Blob);
  });
});
