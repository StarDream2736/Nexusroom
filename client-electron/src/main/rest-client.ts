import { normalizeServerUrl } from './server-url';

export type RestErrorKind =
  | 'configuration'
  | 'api'
  | 'http'
  | 'invalid-response'
  | 'network'
  | 'timeout'
  | 'cancelled';

export interface RestErrorDetails {
  readonly kind: RestErrorKind;
  readonly status?: number;
  readonly code?: number;
  readonly data?: unknown;
  readonly cause?: unknown;
}

export class RestError extends Error {
  readonly kind: RestErrorKind;
  readonly status: number | undefined;
  readonly code: number | undefined;
  readonly data: unknown;
  readonly cause: unknown;

  constructor(message: string, details: RestErrorDetails) {
    super(message);
    this.name = 'RestError';
    this.kind = details.kind;
    this.status = details.status;
    this.code = details.code;
    this.data = details.data;
    this.cause = details.cause;
  }
}

export type FetchImplementation = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

export interface RestRequestOptions {
  readonly method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  readonly body?: unknown;
  readonly headers?: HeadersInit;
  readonly signal?: AbortSignal;
}

export interface RestClientOptions {
  readonly serverUrl?: string | null;
  readonly token?: string | null;
  readonly timeoutMs?: number;
  readonly fetchImpl?: FetchImplementation;
}

interface JsonEnvelope {
  readonly code: number;
  readonly message: string;
  readonly data?: unknown;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function readEnvelope(value: unknown): JsonEnvelope | null {
  if (!isRecord(value) || typeof value.code !== 'number') {
    return null;
  }

  return {
    code: value.code,
    message: typeof value.message === 'string' ? value.message : '',
    data: value.data,
  };
}

export class RestClient {
  private readonly fetchImpl: FetchImplementation;
  private readonly timeoutMs: number;
  private _serverUrl: string | null;
  private _token: string | null;

  constructor(options: RestClientOptions = {}) {
    this.fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
    this.timeoutMs = options.timeoutMs ?? 10_000;
    if (!Number.isFinite(this.timeoutMs) || this.timeoutMs <= 0) {
      throw new RestError('REST 超时必须是正数', { kind: 'configuration' });
    }
    this._serverUrl = options.serverUrl
      ? normalizeServerUrl(options.serverUrl)
      : null;
    this._token = options.token || null;
  }

  get serverUrl(): string | null {
    return this._serverUrl;
  }

  setServerUrl(serverUrl: string | null | undefined): void {
    this._serverUrl = serverUrl ? normalizeServerUrl(serverUrl) : null;
  }

  setToken(token: string | null | undefined): void {
    this._token = token || null;
  }

  get<T>(
    path: string,
    options: Omit<RestRequestOptions, 'method' | 'body'> = {},
  ): Promise<T> {
    return this.request<T>(path, { ...options, method: 'GET' });
  }

  post<T>(
    path: string,
    body: unknown = {},
    options: Omit<RestRequestOptions, 'method' | 'body'> = {},
  ): Promise<T> {
    return this.request<T>(path, { ...options, method: 'POST', body });
  }

  postForm<T>(
    path: string,
    body: FormData,
    options: Omit<RestRequestOptions, 'method' | 'body'> = {},
  ): Promise<T> {
    return this.request<T>(path, { ...options, method: 'POST', body });
  }

  patch<T>(
    path: string,
    body: unknown = {},
    options: Omit<RestRequestOptions, 'method' | 'body'> = {},
  ): Promise<T> {
    return this.request<T>(path, { ...options, method: 'PATCH', body });
  }

  delete<T>(
    path: string,
    options: Omit<RestRequestOptions, 'method' | 'body'> = {},
  ): Promise<T> {
    return this.request<T>(path, { ...options, method: 'DELETE' });
  }

  async request<T>(path: string, options: RestRequestOptions = {}): Promise<T> {
    const url = this.buildUrl(path);
    const controller = new AbortController();
    let timedOut = false;
    const callerSignal = options.signal;
    const abortFromCaller = (): void => controller.abort();

    if (callerSignal?.aborted) {
      throw new RestError('REST 请求已取消', { kind: 'cancelled' });
    }
    callerSignal?.addEventListener('abort', abortFromCaller, { once: true });

    const timeout = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, this.timeoutMs);

    const headers = new Headers(options.headers);
    headers.set('Accept', 'application/json');
    if (this._token) {
      headers.set('Authorization', `Bearer ${this._token}`);
    }

    let body: BodyInit | undefined;
    if (options.body !== undefined) {
      const isMultipart =
        typeof FormData !== 'undefined' && options.body instanceof FormData;
      if (isMultipart) {
        // Let fetch add the multipart boundary to Content-Type.
        headers.delete('Content-Type');
        body = options.body;
      } else {
        const json = JSON.stringify(options.body);
        if (json === undefined) {
          clearTimeout(timeout);
          callerSignal?.removeEventListener('abort', abortFromCaller);
          throw new RestError('REST 请求体不是有效 JSON', {
            kind: 'configuration',
          });
        }
        body = json;
      }
      if (!isMultipart) {
        headers.set('Content-Type', 'application/json');
      }
    }

    try {
      const response = await this.fetchImpl(url, {
        method: options.method ?? 'GET',
        headers,
        body,
        signal: controller.signal,
      });
      const text = await response.text();
      let parsed: unknown;
      if (text.length > 0) {
        try {
          parsed = JSON.parse(text) as unknown;
        } catch (error) {
          throw new RestError('服务器返回了无效 JSON', {
            kind: 'invalid-response',
            status: response.status,
            cause: error,
          });
        }
      }

      const envelope = readEnvelope(parsed);
      if (envelope === null) {
        throw new RestError(
          response.ok
            ? '服务器响应格式无效'
            : `请求失败（HTTP ${response.status}）`,
          {
            kind: response.ok ? 'invalid-response' : 'http',
            status: response.status,
          },
        );
      }
      if (!response.ok || envelope.code !== 20_000) {
        throw new RestError(
          envelope.message || `请求失败（HTTP ${response.status}）`,
          {
            kind: 'api',
            status: response.status,
            code: envelope.code,
            data: envelope.data,
          },
        );
      }

      return envelope.data as T;
    } catch (error) {
      if (error instanceof RestError) {
        throw error;
      }
      if (timedOut) {
        throw new RestError('REST 请求超时', { kind: 'timeout' });
      }
      if (callerSignal?.aborted) {
        throw new RestError('REST 请求已取消', { kind: 'cancelled' });
      }
      throw new RestError('REST 网络请求失败', { kind: 'network', cause: error });
    } finally {
      clearTimeout(timeout);
      callerSignal?.removeEventListener('abort', abortFromCaller);
    }
  }

  private buildUrl(path: string): URL {
    if (this._serverUrl === null) {
      throw new RestError('尚未配置服务器地址', { kind: 'configuration' });
    }
    if (!path.startsWith('/')) {
      throw new RestError('REST 路径必须以 / 开头', { kind: 'configuration' });
    }

    let url: URL;
    try {
      url = new URL(path, this._serverUrl);
    } catch {
      throw new RestError('REST 路径无效', { kind: 'configuration' });
    }
    if (url.origin !== this._serverUrl) {
      throw new RestError('REST 路径不能跨服务器', { kind: 'configuration' });
    }
    return url;
  }
}
