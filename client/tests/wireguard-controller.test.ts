import { EventEmitter } from 'node:events';
import { describe, expect, it, vi } from 'vitest';
import {
  createWireGuardController,
  WIREGUARD_MAX_LINE_BYTES,
  type WireGuardChildProcessLike,
  type WireGuardFileSystem,
  type WireGuardServerLike,
  type WireGuardSpawn,
  type WireGuardTimer,
} from '../src/main/wireguard-controller';
import type { WireGuardTunnelConfig } from '../src/shared/preload-api';

class FakeTimer implements WireGuardTimer {
  private nextId = 1;
  private readonly callbacks = new Map<number, () => void>();

  setTimeout(callback: () => void): number {
    const id = this.nextId;
    this.nextId += 1;
    this.callbacks.set(id, callback);
    return id;
  }

  clearTimeout(handle: unknown): void {
    if (typeof handle === 'number') {
      this.callbacks.delete(handle);
    }
  }

  runNext(): void {
    const next = this.callbacks.entries().next();
    if (next.done) {
      throw new Error('No fake timer is pending.');
    }
    this.callbacks.delete(next.value[0]);
    next.value[1]();
  }

  runAll(): void {
    while (this.callbacks.size > 0) {
      this.runNext();
    }
  }
}

class FakeReadable extends EventEmitter {
  emitData(chunk: string): void {
    this.emit('data', chunk);
  }
}

class FakeChild extends EventEmitter {
  readonly stdout = new FakeReadable();
  killed = false;

  kill(): boolean {
    this.killed = true;
    return true;
  }
}

class FakeSocket extends EventEmitter {
  readonly writes: string[] = [];
  destroyed = false;
  onWrite: ((data: string) => void) | null = null;

  write(data: string): boolean {
    this.writes.push(data);
    this.onWrite?.(data);
    return true;
  }

  destroy(): void {
    this.destroyed = true;
  }
}

class FakeServer extends EventEmitter {
  readonly listenCalls: Array<{ host: string; port: number }> = [];
  closed = false;
  readonly port = 41_234;

  listen(options: { host: string; port: number }, callback?: () => void): this {
    this.listenCalls.push(options);
    this.emit('listening');
    callback?.();
    return this;
  }

  address(): { port: number } {
    return { port: this.port };
  }

  close(callback?: (error?: Error) => void): void {
    this.closed = true;
    callback?.();
  }
}

interface HarnessOptions {
  readonly connect?: boolean;
  readonly launchCloses?: boolean;
  readonly upResponse?: 'success' | 'error' | 'none' | 'long';
  readonly upResponses?: readonly ('success' | 'error' | 'none' | 'long')[];
  readonly genkeyOutput?: string;
  readonly genkeyCloses?: boolean;
  readonly helperPath?: string;
}

interface Harness {
  readonly controller: ReturnType<typeof createWireGuardController>;
  readonly timer: FakeTimer;
  readonly server: FakeServer;
  readonly socket: FakeSocket;
  readonly launcher: FakeChild;
  readonly spawn: ReturnType<typeof vi.fn>;
}

const helperPath = 'C:\\NexusRoom\\nexusroom-wg.exe';
const tunnelConfig: WireGuardTunnelConfig = {
  interface_name: 'NexusRoom0',
  private_key: 'private-key-in-memory',
  address: '10.0.8.2/24',
  peers: [
    {
      public_key: 'server-public-key',
      endpoint: 'example.test:51820',
      allowed_ips: '10.0.8.0/24',
    },
  ],
};

function createHarness(options: HarnessOptions = {}): Harness {
  const timer = new FakeTimer();
  const server = new FakeServer();
  const socket = new FakeSocket();
  const launcher = new FakeChild();
  const resolvedHelperPath = options.helperPath ?? helperPath;
  let upResponseIndex = 0;
  const fileSystem: WireGuardFileSystem = { existsSync: () => true };
  const spawn = vi.fn((command: string, args: readonly string[]) => {
    if (args[0] === 'genkey') {
      const child = new FakeChild();
      if (options.genkeyCloses !== false) {
        queueMicrotask(() => {
          if (options.genkeyOutput !== undefined) {
            child.stdout.emitData(options.genkeyOutput);
          }
          child.emit('close', 0, null);
        });
      }
      return child as unknown as WireGuardChildProcessLike;
    }

    if (command !== 'powershell.exe') {
      throw new Error(`Unexpected command: ${command}`);
    }
    if (options.launchCloses !== false) {
      queueMicrotask(() => launcher.emit('close', 0, null));
    }
    if (options.connect !== false) {
      queueMicrotask(() => server.emit('connection', socket));
    }
    return launcher as unknown as WireGuardChildProcessLike;
  });
  socket.onWrite = (data) => {
    if (data.includes('"action":"down"')) {
      queueMicrotask(() => socket.emit('data', '{"action":"down"}\n'));
      return;
    }
    const response = options.upResponses?.[upResponseIndex++] ?? options.upResponse ?? 'success';
    if (response === 'error') {
      queueMicrotask(() => socket.emit('data', '{"action":"error","error":"failed"}\n'));
    } else if (response === 'long') {
      queueMicrotask(() => socket.emit('data', 'x'.repeat(WIREGUARD_MAX_LINE_BYTES + 1)));
    } else if (response !== 'none') {
      queueMicrotask(() => socket.emit('data', '{"action":"up","data":{"status":"ok"}}\n'));
    }
  };

  const controller = createWireGuardController({
    helperPath: resolvedHelperPath,
    fileSystem,
    spawn: spawn as unknown as WireGuardSpawn,
    serverFactory: () => server as unknown as WireGuardServerLike,
    timer,
    timeouts: {
      genkey: 10,
      listen: 10,
      uac: 10,
      connect: 10,
      up: 10,
      down: 10,
      close: 10,
    },
  });
  return { controller, timer, server, socket, launcher, spawn };
}

async function flushMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

describe('WireGuard controller', () => {
  it('reports a missing helper and refuses operations', async () => {
    const harness = createHarness();
    const missingFileSystem: WireGuardFileSystem = { existsSync: () => false };
    const controller = createWireGuardController({
      helperPath,
      fileSystem: missingFileSystem,
      timer: harness.timer,
    });

    expect(controller.getAvailability()).toEqual({ available: false, reason: 'missing' });
    await expect(controller.generateKeyPair()).rejects.toMatchObject({ code: 'helper-missing' });
    await expect(controller.startTunnel(tunnelConfig)).rejects.toMatchObject({ code: 'helper-missing' });
  });

  it('parses a normal genkey response without logging or persisting it', async () => {
    const harness = createHarness({
      genkeyOutput: '{"action":"genkey","data":{"public_key":"public","private_key":"private"}}\n',
    });

    const keyPair = await harness.controller.generateKeyPair();

    expect(keyPair).toEqual({ public_key: 'public', private_key: 'private' });
    expect(harness.spawn).toHaveBeenCalledWith(
      helperPath,
      ['genkey'],
      { windowsHide: true, stdio: ['ignore', 'pipe', 'ignore'] },
    );
  });

  it('bounds genkey timeout and terminates the child', async () => {
    const harness = createHarness({ genkeyCloses: false });
    const pending = harness.controller.generateKeyPair();

    await flushMicrotasks();
    harness.timer.runNext();

    await expect(pending).rejects.toMatchObject({ code: 'timeout' });
    const child = harness.spawn.mock.results[0]?.value as FakeChild | undefined;
    expect(child?.killed).toBe(true);
  });

  it('rejects malformed genkey JSON', async () => {
    const harness = createHarness({ genkeyOutput: 'not-json\n' });

    await expect(harness.controller.generateKeyPair()).rejects.toMatchObject({ code: 'protocol' });
  });

  it('rejects an oversized helper line and cleans up the socket and server', async () => {
    const harness = createHarness({ upResponse: 'long' });

    await expect(harness.controller.startTunnel(tunnelConfig)).rejects.toMatchObject({ code: 'protocol' });

    expect(harness.socket.destroyed).toBe(true);
    expect(harness.server.closed).toBe(true);
    expect(harness.controller.getStatus().state).toBe('idle');
  });

  it('starts over loopback and sends config only over the socket', async () => {
    const harness = createHarness();

    const status = await harness.controller.startTunnel(tunnelConfig);

    expect(status).toMatchObject({ available: true, state: 'running', address: tunnelConfig.address });
    expect(harness.server.listenCalls).toEqual([{ host: '127.0.0.1', port: 0 }]);
    expect(harness.server.closed).toBe(true);
    const launchCall = harness.spawn.mock.calls.find((call) => call[0] === 'powershell.exe');
    expect(launchCall).toBeDefined();
    const launchArgs = (launchCall?.[1] as readonly string[]).join(' ');
    expect(launchArgs).toContain('-Verb RunAs');
    expect(launchArgs).toContain('up');
    expect(launchArgs).toContain('--port');
    expect(launchArgs).toContain('41234');
    expect(launchArgs).toContain(helperPath);
    expect(launchArgs).not.toContain(tunnelConfig.private_key ?? '');
    expect(launchArgs).not.toContain(tunnelConfig.address);
    expect(JSON.parse(harness.socket.writes[0] ?? '{}')).toMatchObject({
      private_key: tunnelConfig.private_key,
      address: tunnelConfig.address,
    });
  });

  it('escapes an apostrophe in the fixed helper path without putting config in PowerShell', async () => {
    const pathWithQuote = "C:\\Nexus'Room\\nexusroom-wg.exe";
    const harness = createHarness({ helperPath: pathWithQuote });

    await harness.controller.startTunnel(tunnelConfig);

    const launchCall = harness.spawn.mock.calls.find((call) => call[0] === 'powershell.exe');
    const launchArgs = (launchCall?.[1] as readonly string[]).join(' ');
    expect(launchArgs).toContain("Nexus''Room");
    expect(launchArgs).toContain('-Verb RunAs');
    expect(launchArgs).not.toContain(tunnelConfig.private_key);
    expect(launchArgs).not.toContain(tunnelConfig.address);
    expect(launchArgs).not.toContain('allowed_ips');
  });

  it('bounds UAC and helper connection timeouts', async () => {
    const uacHarness = createHarness({ launchCloses: false, connect: false });
    const uacPending = uacHarness.controller.startTunnel(tunnelConfig);
    await flushMicrotasks();
    uacHarness.timer.runNext();
    await expect(uacPending).rejects.toMatchObject({ code: 'timeout' });
    expect(uacHarness.server.closed).toBe(true);
    expect(uacHarness.launcher.killed).toBe(true);

    const connectHarness = createHarness({ connect: false });
    const connectPending = connectHarness.controller.startTunnel(tunnelConfig);
    await flushMicrotasks();
    connectHarness.timer.runNext();
    await expect(connectPending).rejects.toMatchObject({ code: 'timeout' });
    expect(connectHarness.server.closed).toBe(true);
  });

  it('cleans every resource after an up failure', async () => {
    const harness = createHarness({ upResponse: 'error' });

    await expect(harness.controller.startTunnel(tunnelConfig)).rejects.toMatchObject({ code: 'protocol' });
    await flushMicrotasks();

    expect(harness.socket.destroyed).toBe(true);
    expect(harness.server.closed).toBe(true);
    expect(harness.launcher.killed).toBe(true);
    expect(harness.controller.getStatus().state).toBe('idle');
  });

  it('keeps queued starts serial and recovers after the first failure', async () => {
    const harness = createHarness({ upResponses: ['error', 'success'] });

    const first = harness.controller.startTunnel(tunnelConfig);
    const second = harness.controller.startTunnel(tunnelConfig);

    await expect(first).rejects.toMatchObject({ code: 'protocol' });
    await expect(second).resolves.toMatchObject({ state: 'running' });
    expect(harness.spawn.mock.calls.filter((call) => call[0] === 'powershell.exe')).toHaveLength(2);
    expect(harness.controller.getStatus().state).toBe('running');
  });

  it('cancels a pending startup immediately when stop is requested', async () => {
    const harness = createHarness({ launchCloses: false, connect: false });
    const start = harness.controller.startTunnel(tunnelConfig);

    await flushMicrotasks();
    const stop = harness.controller.stopTunnel();

    await expect(start).rejects.toMatchObject({ code: 'cancelled' });
    await expect(stop).resolves.toBeUndefined();
    expect(harness.launcher.killed).toBe(true);
    expect(harness.server.closed).toBe(true);
    expect(harness.controller.getStatus().state).toBe('idle');
    expect(() => harness.timer.runNext()).toThrow('No fake timer is pending.');
  });

  it('cancels a queued start without launching a second helper', async () => {
    const harness = createHarness({ launchCloses: false, connect: false });
    const first = harness.controller.startTunnel(tunnelConfig);
    const second = harness.controller.startTunnel(tunnelConfig);

    await flushMicrotasks();
    expect(harness.spawn.mock.calls.filter((call) => call[0] === 'powershell.exe')).toHaveLength(1);

    const stop = harness.controller.stopTunnel();

    await expect(first).rejects.toMatchObject({ code: 'cancelled' });
    await expect(second).rejects.toMatchObject({ code: 'cancelled' });
    await expect(stop).resolves.toBeUndefined();
    expect(harness.spawn.mock.calls.filter((call) => call[0] === 'powershell.exe')).toHaveLength(1);
    expect(harness.server.listenCalls).toHaveLength(1);
    expect(harness.launcher.killed).toBe(true);
    expect(harness.server.closed).toBe(true);
    expect(harness.controller.getStatus().state).toBe('idle');
    expect(() => harness.timer.runNext()).toThrow('No fake timer is pending.');
  });

  it('makes concurrent stop calls share one promise and remain idempotent', async () => {
    const harness = createHarness();
    await harness.controller.startTunnel(tunnelConfig);

    const firstStop = harness.controller.stopTunnel();
    const secondStop = harness.controller.stopTunnel();
    expect(secondStop).toBe(firstStop);
    await flushMicrotasks();
    await firstStop;

    expect(harness.socket.writes.filter((line) => line.includes('"action":"down"'))).toHaveLength(1);
    await harness.controller.stopTunnel();
    expect(harness.socket.writes.filter((line) => line.includes('"action":"down"'))).toHaveLength(1);
  });
});
