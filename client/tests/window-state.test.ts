import { describe, expect, it } from 'vitest';
import { nexusRoomIpcChannels } from '../src/shared/preload-api';
import {
  applyWindowState,
  authenticatedWindowState,
  getWindowState,
  unauthenticatedWindowState,
  type WindowStateTarget,
} from '../src/main/window-state';
import {
  createWindowStateIpcHandler,
  registerWindowStateIpc,
  type WindowStateIpcHandler,
} from '../src/main/window-state-ipc';

class FakeWindow implements WindowStateTarget {
  readonly calls: string[] = [];
  maximized = false;

  setSize(width: number, height: number): void {
    this.calls.push(`size:${width}x${height}`);
  }

  setMinimumSize(width: number, height: number): void {
    this.calls.push(`minimum:${width}x${height}`);
  }

  setResizable(value: boolean): void {
    this.calls.push(`resizable:${value}`);
  }

  setMaximizable(value: boolean): void {
    this.calls.push(`maximizable:${value}`);
  }

  isMaximized(): boolean {
    return this.maximized;
  }

  unmaximize(): void {
    this.maximized = false;
    this.calls.push('unmaximize');
  }
}

class FakeIpcMain {
  readonly handlers = new Map<string, WindowStateIpcHandler>();
  readonly removed: string[] = [];

  handle(channel: string, listener: WindowStateIpcHandler): void {
    this.handlers.set(channel, listener);
  }

  removeHandler(channel: string): void {
    this.handlers.delete(channel);
    this.removed.push(channel);
  }
}

describe('native authentication window state', () => {
  it('defines compact unauthenticated and full authenticated bounds', () => {
    expect(getWindowState('unauthenticated')).toEqual(unauthenticatedWindowState);
    expect(unauthenticatedWindowState).toMatchObject({
      width: 480,
      height: 620,
      minWidth: 400,
      minHeight: 500,
      resizable: false,
      maximizable: false,
    });
    expect(getWindowState('authenticated')).toEqual(authenticatedWindowState);
    expect(authenticatedWindowState).toMatchObject({
      width: 1280,
      height: 800,
      minWidth: 960,
      minHeight: 640,
      resizable: true,
      maximizable: true,
    });
  });

  it('applies a compact state and restores a maximized window first', () => {
    const target = new FakeWindow();
    target.maximized = true;
    applyWindowState(target, 'unauthenticated');
    expect(target.calls).toEqual([
      'unmaximize',
      'resizable:true',
      'minimum:400x500',
      'maximizable:false',
      'size:480x620',
      'resizable:false',
    ]);
  });

  it('only accepts state changes from the current main window and disposes cleanly', async () => {
    const target = new FakeWindow();
    let currentWindowId: number | null = 42;
    const ipcMain = new FakeIpcMain();
    const dispose = registerWindowStateIpc(ipcMain, {
      getMainWindowId: () => currentWindowId,
      apply: (mode) => applyWindowState(target, mode),
    });
    const handler = ipcMain.handlers.get(nexusRoomIpcChannels.setAuthenticatedWindowState);
    expect(handler).toBeDefined();
    await expect(handler?.({ sender: { id: 7 } }, true)).rejects.toThrow('current main window');
    await handler?.({ sender: { id: 42 } }, true);
    expect(target.calls).toContain('resizable:true');
    expect(target.calls).toContain('size:1280x800');
    expect(target.calls).toContain('resizable:true');
    expect(target.calls).toContain('maximizable:true');
    currentWindowId = null;
    await expect(handler?.({ sender: { id: 42 } }, false)).rejects.toThrow();
    dispose();
    expect(ipcMain.removed).toEqual([nexusRoomIpcChannels.setAuthenticatedWindowState]);
    expect(ipcMain.handlers.size).toBe(0);
  });

  it('rejects malformed renderer state values', async () => {
    const handler = createWindowStateIpcHandler({
      getMainWindowId: () => 1,
      apply: () => undefined,
    });
    await expect(handler({ sender: { id: 1 } }, 'authenticated')).rejects.toThrow('boolean');
  });
});
