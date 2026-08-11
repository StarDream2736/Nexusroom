import { describe, expect, it, vi } from 'vitest';

const fakeElectron = vi.hoisted(() => ({
  app: {
    isPackaged: false,
    getPath: () => 'C:\\NexusRoom\\electron.exe',
    on: () => undefined,
    whenReady: () => new Promise<void>(() => undefined),
    quit: () => undefined,
    exit: () => undefined,
  },
  BrowserWindow: class BrowserWindow {},
  ipcMain: {
    handle: () => undefined,
    removeHandler: () => undefined,
  },
  session: {
    defaultSession: {
      setPermissionCheckHandler: () => undefined,
      setPermissionRequestHandler: () => undefined,
    },
  },
}));

vi.mock('electron', () => fakeElectron);
import {
  createWireGuardIpcHandlers,
  registerWireGuardIpc,
  type WireGuardIpcHandler,
  type WireGuardIpcMainLike,
} from '../src/main/wireguard-ipc';
import type {
  WireGuardControllerApi,
} from '../src/main/wireguard-controller';
import {
  nexusRoomIpcChannels,
  type WireGuardAvailability,
  type WireGuardKeyPair,
  type WireGuardStatus,
} from '../src/shared/preload-api';
import {
  createShutdownCoordinator,
  type MainShutdownTimer,
} from '../src/main';

class FakeTimer implements MainShutdownTimer {
  private callback: (() => void) | null = null;

  setTimeout(callback: () => void): number {
    this.callback = callback;
    return 1;
  }

  clearTimeout(): void {
    this.callback = null;
  }

  run(): void {
    const callback = this.callback;
    this.callback = null;
    callback?.();
  }
}

class FakeIpcMain implements WireGuardIpcMainLike {
  readonly handlers = new Map<string, WireGuardIpcHandler>();
  readonly removed: string[] = [];

  handle(channel: string, listener: WireGuardIpcHandler): void {
    this.handlers.set(channel, listener);
  }

  removeHandler(channel: string): void {
    this.removed.push(channel);
    this.handlers.delete(channel);
  }
}

function createController(): WireGuardControllerApi & {
  readonly calls: string[];
} {
  const calls: string[] = [];
  const availability: WireGuardAvailability = { available: true };
  const keyPair: WireGuardKeyPair = { public_key: 'public', private_key: 'private' };
  const status: WireGuardStatus = { available: true, state: 'idle' };
  return {
    calls,
    getAvailability: () => {
      calls.push('availability');
      return availability;
    },
    getStatus: () => {
      calls.push('status');
      return status;
    },
    generateKeyPair: async () => {
      calls.push('generate');
      return keyPair;
    },
    startTunnel: async () => {
      calls.push('start');
      return { ...status, state: 'running' };
    },
    stopTunnel: async () => {
      calls.push('stop');
    },
    dispose: async () => {
      calls.push('dispose');
    },
  };
}

describe('WireGuard IPC', () => {
  it('registers only the narrow API and rejects stale senders', async () => {
    const controller = createController();
    const ipcMain = new FakeIpcMain();
    let mainWindowId: number | null = 42;
    const dispose = registerWireGuardIpc(ipcMain, {
      controller,
      getMainWindowId: () => mainWindowId,
    });

    expect([...ipcMain.handlers.keys()]).toEqual([
      nexusRoomIpcChannels.wireguardAvailability,
      nexusRoomIpcChannels.wireguardGenerateKeyPair,
      nexusRoomIpcChannels.wireguardStartTunnel,
      nexusRoomIpcChannels.wireguardStopTunnel,
      nexusRoomIpcChannels.wireguardStatus,
    ]);
    const availability = ipcMain.handlers.get(nexusRoomIpcChannels.wireguardAvailability);
    if (availability === undefined) {
      throw new Error('Availability handler was not registered.');
    }

    await expect(availability({ sender: { id: 7 } })).rejects.toBeInstanceOf(Error);
    expect(controller.calls).toEqual([]);

    await expect(
      availability({ sender: { id: 42 } }),
    ).resolves.toEqual({ available: true });
    expect(controller.calls).toEqual(['availability']);

    mainWindowId = null;
    await expect(availability({ sender: { id: 42 } })).rejects.toBeInstanceOf(Error);
    expect(controller.calls).toEqual(['availability']);

    dispose();
    expect(ipcMain.handlers).toHaveLength(0);
    expect(ipcMain.removed).toHaveLength(5);
  });

  it('validates start arguments after checking the sender', async () => {
    const controller = createController();
    const handlers = createWireGuardIpcHandlers({
      controller,
      getMainWindowId: () => 42,
    });
    const start = handlers[nexusRoomIpcChannels.wireguardStartTunnel];

    await expect(start({ sender: { id: 7 } }, { address: '10.0.8.2/24' })).rejects.toBeInstanceOf(Error);
    expect(controller.calls).toEqual([]);
    await expect(start({ sender: { id: 42 } })).rejects.toBeInstanceOf(Error);
    await expect(start({ sender: { id: 42 } }, null)).rejects.toBeInstanceOf(Error);
    expect(controller.calls).toEqual([]);

    await expect(
      start(
        { sender: { id: 42 } },
        { address: '10.0.8.2/24', private_key: 'private', peers: [] },
      ),
    ).resolves.toMatchObject({ state: 'running' });
    expect(controller.calls).toEqual(['start']);
  });

  it('returns status after a bounded stop', async () => {
    const controller = createController();
    const handlers = createWireGuardIpcHandlers({
      controller,
      getMainWindowId: () => 42,
    });

    const result = await handlers[nexusRoomIpcChannels.wireguardStopTunnel](
      { sender: { id: 42 } },
    );

    expect(result).toEqual({ available: true, state: 'idle' });
    expect(controller.calls).toEqual(['stop', 'status']);
  });

  it('hides and disables interaction immediately, then exits at the hard cap', async () => {
    const timer = new FakeTimer();
    const exit = vi.fn();
    const disableInteraction = vi.fn();
    const hideWindow = vi.fn();
    const coordinator = createShutdownCoordinator({
      disableInteraction,
      hideWindow,
      stopWireGuard: () => new Promise<void>(() => undefined),
      closeDatabase: () => undefined,
      exit,
      timer,
      hardTimeoutMs: 2_000,
    });

    const firstRequest = coordinator.request();
    const secondRequest = coordinator.request();

    expect(secondRequest).toBe(firstRequest);
    expect(coordinator.started).toBe(true);
    expect(coordinator.finished).toBe(false);
    expect(disableInteraction).toHaveBeenCalledTimes(1);
    expect(hideWindow).toHaveBeenCalledTimes(1);
    expect(exit).not.toHaveBeenCalled();

    timer.run();
    await firstRequest;
    expect(coordinator.finished).toBe(true);
    expect(exit).toHaveBeenCalledTimes(1);
    expect(exit).toHaveBeenCalledWith(0);
    expect(await coordinator.request()).toBeUndefined();
    expect(exit).toHaveBeenCalledTimes(1);
  });

  it('exits once when both independent resources finish', async () => {
    const timer = new FakeTimer();
    const exit = vi.fn();
    let stopCalls = 0;
    let databaseCalls = 0;
    const coordinator = createShutdownCoordinator({
      disableInteraction: () => undefined,
      hideWindow: () => undefined,
      stopWireGuard: async () => {
        stopCalls += 1;
      },
      closeDatabase: async () => {
        databaseCalls += 1;
      },
      exit,
      timer,
    });

    const firstRequest = coordinator.request();
    const secondRequest = coordinator.request();
    await firstRequest;
    await secondRequest;

    expect(stopCalls).toBe(1);
    expect(databaseCalls).toBe(1);
    expect(exit).toHaveBeenCalledTimes(1);
  });
});
