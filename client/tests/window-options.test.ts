import { describe, expect, it } from 'vitest';
import {
  configureApplicationMenu,
  createWindowOptions,
} from '../src/window-options';

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

  it.each(['win32', 'linux'])('removes the native menu on %s', (platform) => {
    const menus: unknown[] = [];

    configureApplicationMenu(platform, {
      setApplicationMenu: (menu) => menus.push(menu),
    });

    expect(menus).toEqual([null]);
  });

  it('keeps the platform menu behavior on macOS', () => {
    const menus: unknown[] = [];

    configureApplicationMenu('darwin', {
      setApplicationMenu: (menu) => menus.push(menu),
    });

    expect(menus).toEqual([]);
  });
});
