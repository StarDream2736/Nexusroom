import { describe, expect, it } from 'vitest';
import { createWindowOptions } from '../src/window-options';

describe('Electron window options', () => {
  it('keeps the renderer behind the isolated, sandboxed boundary', () => {
    const options = createWindowOptions('C:/NexusRoom/preload.js');

    expect(options.webPreferences).toMatchObject({
      contextIsolation: true,
      nodeIntegration: false,
      nodeIntegrationInSubFrames: false,
      sandbox: true,
      webSecurity: true,
      allowRunningInsecureContent: false,
      webviewTag: false,
      preload: 'C:/NexusRoom/preload.js',
    });
  });
});
