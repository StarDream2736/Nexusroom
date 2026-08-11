export type RendererMediaType = 'audio' | 'video' | 'unknown';

export interface RendererPermissionDetails {
  readonly isMainFrame: boolean;
  readonly requestingUrl?: string;
  readonly securityOrigin?: string;
}

export interface RendererPermissionTarget {
  readonly rendererKind: 'file' | 'web';
  readonly rendererUrl: string;
}

export function selectRendererPermissionTarget(options: {
  readonly isPackaged: boolean;
  readonly developmentUrl?: string;
  readonly fileUrl: string;
}): RendererPermissionTarget {
  const developmentUrl = options.isPackaged ? undefined : options.developmentUrl;
  return developmentUrl
    ? { rendererKind: 'web', rendererUrl: developmentUrl }
    : { rendererKind: 'file', rendererUrl: options.fileUrl };
}

function parseUrl(value: string | undefined): URL | null {
  if (value === undefined || value.length === 0) return null;
  try {
    return new URL(value);
  } catch {
    return null;
  }
}

function isFileSecurityOrigin(value: string | undefined): boolean {
  return value === 'file://' || value === 'file:///';
}

export function isTrustedRendererRequest(
  webContents: object | null,
  mainWindowWebContents: object | null,
  details: RendererPermissionDetails,
  target: RendererPermissionTarget,
): boolean {
  if (
    webContents === null ||
    mainWindowWebContents === null ||
    webContents !== mainWindowWebContents ||
    details.isMainFrame !== true
  ) {
    return false;
  }

  const requestingUrl = parseUrl(details.requestingUrl);
  const rendererUrl = parseUrl(target.rendererUrl);
  if (requestingUrl === null || rendererUrl === null) return false;

  if (target.rendererKind === 'file') {
    return rendererUrl.protocol === 'file:' &&
      requestingUrl.protocol === 'file:' &&
      requestingUrl.href === rendererUrl.href &&
      isFileSecurityOrigin(details.securityOrigin);
  }

  if (rendererUrl.protocol !== 'http:' && rendererUrl.protocol !== 'https:') return false;
  const securityOrigin = parseUrl(details.securityOrigin);
  if (securityOrigin === null) return false;
  return requestingUrl.origin === rendererUrl.origin && securityOrigin.origin === rendererUrl.origin;
}

export function isAudioPermissionCheck(
  permission: string,
  mediaType: RendererMediaType | undefined,
): boolean {
  return permission === 'media' && mediaType === 'audio';
}

export function isAudioPermissionRequest(
  permission: string,
  mediaTypes: readonly ('audio' | 'video')[] | undefined,
): boolean {
  return permission === 'media' && mediaTypes?.length === 1 && mediaTypes[0] === 'audio';
}
