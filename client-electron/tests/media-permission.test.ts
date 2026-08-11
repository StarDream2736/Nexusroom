import { describe, expect, it } from 'vitest';
import {
  isAudioPermissionCheck,
  isAudioPermissionRequest,
  selectRendererPermissionTarget,
  isTrustedRendererRequest,
} from '../src/main/media-permission';

describe('renderer media permission policy', () => {
  it('requires the current main frame and the exact production file renderer', () => {
    const mainContents = {};
    const target = selectRendererPermissionTarget({
      isPackaged: true,
      fileUrl: 'file:///C:/NexusRoom/dist/renderer/index.html',
    });
    const details = {
      isMainFrame: true,
      requestingUrl: 'file:///C:/NexusRoom/dist/renderer/index.html',
      securityOrigin: 'file://',
    };

    expect(isTrustedRendererRequest(mainContents, mainContents, details, target)).toBe(true);
    expect(isTrustedRendererRequest(null, mainContents, details, target)).toBe(false);
    expect(isTrustedRendererRequest({}, mainContents, details, target)).toBe(false);
    expect(isTrustedRendererRequest(mainContents, mainContents, { ...details, isMainFrame: false }, target)).toBe(false);
    expect(isTrustedRendererRequest(
      mainContents,
      mainContents,
      { ...details, requestingUrl: 'file:///C:/NexusRoom/other.html' },
      target,
    )).toBe(false);
  });

  it('uses the file renderer when a development URL is not set', () => {
    const target = selectRendererPermissionTarget({
      isPackaged: false,
      fileUrl: 'file:///C:/NexusRoom/dist/renderer/index.html',
    });
    const mainContents = {};

    expect(target).toEqual({
      rendererKind: 'file',
      rendererUrl: 'file:///C:/NexusRoom/dist/renderer/index.html',
    });
    expect(isTrustedRendererRequest(
      mainContents,
      mainContents,
      {
        isMainFrame: true,
        requestingUrl: target.rendererUrl,
        securityOrigin: 'file://',
      },
      target,
    )).toBe(true);
  });

  it('allows only the configured development origin', () => {
    const mainContents = {};
    const target = selectRendererPermissionTarget({
      isPackaged: false,
      developmentUrl: 'http://127.0.0.1:5173',
      fileUrl: 'file:///C:/NexusRoom/dist/renderer/index.html',
    });
    const details = {
      isMainFrame: true,
      requestingUrl: 'http://127.0.0.1:5173/room/1',
      securityOrigin: 'http://127.0.0.1:5173',
    };

    expect(isTrustedRendererRequest(mainContents, mainContents, details, target)).toBe(true);
    expect(isTrustedRendererRequest(
      mainContents,
      mainContents,
      { ...details, requestingUrl: 'http://localhost:5173/room/1' },
      target,
    )).toBe(false);
    expect(isTrustedRendererRequest(
      mainContents,
      mainContents,
      { ...details, securityOrigin: 'http://127.0.0.1:5174' },
      target,
    )).toBe(false);
  });

  it('rejects unknown, video, and display capture permissions', () => {
    expect(isAudioPermissionCheck('media', 'audio')).toBe(true);
    expect(isAudioPermissionCheck('media', 'unknown')).toBe(false);
    expect(isAudioPermissionCheck('media', 'video')).toBe(false);
    expect(isAudioPermissionRequest('media', ['audio'])).toBe(true);
    expect(isAudioPermissionRequest('media', ['audio', 'video'])).toBe(false);
    expect(isAudioPermissionRequest('display-capture', ['audio'])).toBe(false);
  });
});
