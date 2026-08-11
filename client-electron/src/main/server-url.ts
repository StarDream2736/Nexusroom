export class ServerUrlError extends Error {
  constructor(message = '服务器地址必须是 HTTP(S) 根地址') {
    super(message);
    this.name = 'ServerUrlError';
  }
}

export function normalizeServerUrl(value: string): string {
  if (typeof value !== 'string') {
    throw new ServerUrlError();
  }

  const input = value.trim();
  if (input.length === 0 || /[?#]/u.test(input)) {
    throw new ServerUrlError();
  }

  let url: URL;
  try {
    url = new URL(input);
  } catch {
    throw new ServerUrlError();
  }

  if (
    (url.protocol !== 'http:' && url.protocol !== 'https:') ||
    url.hostname.length === 0 ||
    url.username.length > 0 ||
    url.password.length > 0 ||
    (url.pathname.length > 0 && url.pathname !== '/')
  ) {
    throw new ServerUrlError();
  }

  return url.origin;
}
