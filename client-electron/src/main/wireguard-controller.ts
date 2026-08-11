import { existsSync } from 'node:fs';
import { spawn as nodeSpawn, type SpawnOptions } from 'node:child_process';
import { createServer as createNetServer } from 'node:net';
import { dirname, join, resolve } from 'node:path';
import type { WireGuardAvailability, WireGuardKeyPair, WireGuardStatus, WireGuardTunnelConfig, WireGuardTunnelState } from '../shared/preload-api';

export const WIREGUARD_HELPER_NAME = 'nexusroom-wg.exe';
export const WIREGUARD_LOOPBACK_HOST = '127.0.0.1';
export const WIREGUARD_MAX_LINE_BYTES = 64 * 1024;
export const WIREGUARD_TIMEOUTS_MS = {
  genkey: 5_000,
  listen: 2_000,
  uac: 8_000,
  connect: 5_000,
  up: 8_000,
  down: 1_500,
  close: 1_000,
} as const;

export type WireGuardErrorCode = 'helper-missing' | 'disposed' | 'invalid-config' | 'spawn-failed' | 'connection' | 'timeout' | 'protocol' | 'cancelled' | 'internal';

export class WireGuardError extends Error {
  constructor(readonly code: WireGuardErrorCode, message: string) {
    super(message);
    this.name = 'WireGuardError';
  }
}

export type WireGuardFileSystem = { existsSync(path: string): boolean };
export type WireGuardTimer = {
  setTimeout(callback: () => void, delayMs: number): unknown;
  clearTimeout(handle: unknown): void;
};
type Listener = (...args: never[]) => void;
type EventSource = {
  on(event: string, listener: Listener): EventSource;
  once(event: string, listener: Listener): EventSource;
  removeAllListeners(): EventSource;
};
export type WireGuardChildProcessLike = EventSource & {
  readonly stdout?: EventSource | null;
  kill(signal?: NodeJS.Signals): boolean;
};
export type WireGuardSpawn = (
  command: string,
  args: readonly string[],
  options: { readonly windowsHide: boolean; readonly stdio: 'ignore' | readonly ['ignore', 'pipe', 'ignore'] },
) => WireGuardChildProcessLike;
type WireGuardSocketLike = EventSource & { write(data: string): boolean | void; destroy(error?: Error): void };
export type WireGuardServerLike = EventSource & {
  listen(options: { readonly host: string; readonly port: number }, callback?: () => void): WireGuardServerLike;
  address(): { readonly port: number } | string | null;
  close(callback?: (error?: Error) => void): void;
};
export type WireGuardServerFactory = () => WireGuardServerLike;
export type WireGuardTimeoutOptions = Record<keyof typeof WIREGUARD_TIMEOUTS_MS, number>;
export type WireGuardControllerOptions = {
  readonly helperPath: string;
  readonly fileSystem?: WireGuardFileSystem;
  readonly spawn?: WireGuardSpawn;
  readonly serverFactory?: WireGuardServerFactory;
  readonly timer?: WireGuardTimer;
  readonly timeouts?: Partial<WireGuardTimeoutOptions>;
};
export type WireGuardControllerApi = { getAvailability(): WireGuardAvailability; getStatus(): WireGuardStatus; generateKeyPair(): Promise<WireGuardKeyPair>; startTunnel(config: WireGuardTunnelConfig): Promise<WireGuardStatus>; stopTunnel(): Promise<void>; dispose(): Promise<void> };
interface StartupResources { server: WireGuardServerLike | null; socket: WireGuardSocketLike | null; launcher: WireGuardChildProcessLike | null }
interface StartupCancellation { subscribe(listener: () => void): () => void; cancel(): void }

const defaultTimer: WireGuardTimer = { setTimeout: (callback, delayMs) => setTimeout(callback, delayMs), clearTimeout: (handle) => clearTimeout(handle as ReturnType<typeof setTimeout>) };
const defaultFileSystem: WireGuardFileSystem = { existsSync };
const defaultSpawn: WireGuardSpawn = (command, args, options) =>
  nodeSpawn(command, [...args], options as SpawnOptions) as unknown as WireGuardChildProcessLike;
const defaultServerFactory: WireGuardServerFactory = () =>
  createNetServer() as unknown as WireGuardServerLike;

export type WireGuardHelperPathOptions = { readonly isPackaged: boolean; readonly executablePath: string; readonly developmentHelperPath: string };

export function resolveWireGuardHelperPath(options: WireGuardHelperPathOptions): string {
  return options.isPackaged
    ? join(dirname(resolve(options.executablePath)), WIREGUARD_HELPER_NAME)
    : resolve(options.developmentHelperPath);
}

export function buildRunAsPowerShellCommand(helperPath: string, port: number): string {
  if (!Number.isSafeInteger(port) || port < 1 || port > 65_535) {
    throw new WireGuardError('internal', 'Invalid internal WireGuard IPC port.');
  }
  return ['Start-Process', '-FilePath', "'" + helperPath.replaceAll("'", "''") + "'", '-ArgumentList', "@('up','--port','" + port + "')", '-Verb', 'RunAs', '-WindowStyle', 'Hidden'].join(' ');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function requireString(value: unknown, field: string, allowEmpty = false): string {
  if (typeof value !== 'string' || (!allowEmpty && value.length === 0)) {
    throw new WireGuardError('invalid-config', 'Invalid WireGuard ' + field + '.');
  }
  if ([...value].some((character) => {
    const code = character.codePointAt(0) ?? 0;
    return code < 0x20 || code === 0x7f;
  })) {
    throw new WireGuardError('invalid-config', 'Invalid WireGuard ' + field + '.');
  }
  return value;
}

function optionalInteger(value: unknown, field: string, minimum: number): void {
  if (value === undefined || value === null) return;
  if (!Number.isSafeInteger(value) || (value as number) < minimum || (value as number) > 65_535) {
    throw new WireGuardError('invalid-config', 'Invalid WireGuard ' + field + '.');
  }
}

export function validateWireGuardConfig(value: unknown): WireGuardTunnelConfig {
  if (!isRecord(value)) {
    throw new WireGuardError('invalid-config', 'Invalid WireGuard tunnel config.');
  }
  requireString(value.interface_name ?? 'NexusRoom0', 'interface name');
  requireString(value.private_key, 'private key');
  requireString(value.address, 'address');
  if (value.dns !== undefined) requireString(value.dns, 'DNS', true);
  optionalInteger(value.listen_port, 'listen port', 1);
  if (!Array.isArray(value.peers)) {
    throw new WireGuardError('invalid-config', 'Invalid WireGuard peers.');
  }
  for (const peer of value.peers) {
    if (!isRecord(peer)) {
      throw new WireGuardError('invalid-config', 'Invalid WireGuard peer.');
    }
    requireString(peer.public_key, 'peer public key');
    requireString(peer.allowed_ips, 'peer allowed IPs');
    if (peer.endpoint !== undefined) requireString(peer.endpoint, 'peer endpoint', true);
    optionalInteger(peer.persistent_keepalive, 'peer keepalive', 0);
  }
  return value as unknown as WireGuardTunnelConfig;
}
function createCancellation(): StartupCancellation {
  let cancelled = false;
  const listeners = new Set<() => void>();
  return {
    subscribe(listener): () => void {
      if (cancelled) {
        listener();
        return () => undefined;
      }
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    cancel(): void {
      if (cancelled) return;
      cancelled = true;
      for (const listener of listeners) listener();
      listeners.clear();
    },
  };
}
function toWireGuardError(error: unknown): WireGuardError {
  return error instanceof WireGuardError
    ? error
    : new WireGuardError('internal', 'WireGuard operation failed.');
}
function bestEffort(action: () => void): void {
  try {
    action();
  } catch {
    // Cleanup continues even when a resource is already closed.
  }
}
function destroySocket(socket: WireGuardSocketLike | null): void {
  if (socket !== null) bestEffort(() => socket.destroy());
}
function killChild(child: WireGuardChildProcessLike | null): void {
  if (child !== null) bestEffort(() => child.kill());
}
function closeServerBounded(
  server: WireGuardServerLike | null,
  timer: WireGuardTimer,
  timeoutMs: number,
): Promise<void> {
  if (server === null) return Promise.resolve();
  return new Promise((resolvePromise) => {
    const timeoutHandle = timer.setTimeout(resolvePromise, timeoutMs);
    try {
      server.close(() => {
        timer.clearTimeout(timeoutHandle);
        resolvePromise();
      });
    } catch {
      timer.clearTimeout(timeoutHandle);
      resolvePromise();
    }
  });
}
function waitFor<T>(
  timer: WireGuardTimer,
  timeoutMs: number,
  timeoutError: WireGuardError,
  cancellation: StartupCancellation | undefined,
  setup: (
    succeed: (value?: T) => void,
    fail: (error: WireGuardError) => void,
  ) => () => void,
): Promise<T> {
  return new Promise((resolvePromise, rejectPromise) => {
    let settled = false;
    let timeoutHandle: unknown = undefined;
    let removeCancel = (): void => undefined;
    let dispose = (): void => undefined;
    const finish = (error?: WireGuardError, value?: T): void => {
      if (settled) return;
      settled = true;
      timer.clearTimeout(timeoutHandle);
      removeCancel();
      dispose();
      if (error === undefined) resolvePromise(value as T);
      else rejectPromise(error);
    };
    timeoutHandle = timer.setTimeout(() => finish(timeoutError), timeoutMs);
    if (!settled && cancellation !== undefined) {
      removeCancel = cancellation.subscribe(() =>
        finish(new WireGuardError('cancelled', 'WireGuard startup was cancelled.')));
    }
    if (settled) return;
    try {
      dispose = setup(
        (value) => finish(undefined, value),
        (error) => finish(error),
      );
      if (settled) dispose();
    } catch {
      finish(new WireGuardError('internal', 'WireGuard operation failed.'));
    }
  });
}
function listenServer(
  server: WireGuardServerLike,
  timer: WireGuardTimer,
  timeoutMs: number,
  cancellation: StartupCancellation,
): Promise<void> {
  return waitFor(timer, timeoutMs,
    new WireGuardError('timeout', 'WireGuard IPC server listen timed out.'),
    cancellation,
    (succeed, fail) => {
      const onError = (): void => fail(new WireGuardError('connection', 'Unable to bind WireGuard IPC server.'));
      server.once('error', onError);
      try {
        server.listen({ host: WIREGUARD_LOOPBACK_HOST, port: 0 }, () => succeed());
      } catch {
        onError();
      }
      return () => server.removeAllListeners();
    });
}
function waitForAction(
  socket: WireGuardSocketLike,
  line: string,
  action: 'up' | 'down',
  timer: WireGuardTimer,
  timeoutMs: number,
  cancellation?: StartupCancellation,
): Promise<void> {
  return waitFor(timer, timeoutMs,
    new WireGuardError('timeout', 'WireGuard ' + action + ' confirmation timed out.'),
    cancellation,
    (succeed, fail) => {
      let buffer = '';
      const onData = (chunk: string | Buffer): void => {
        buffer += typeof chunk === 'string' ? chunk : chunk.toString('utf8');
        if (Buffer.byteLength(buffer, 'utf8') > WIREGUARD_MAX_LINE_BYTES) {
          fail(new WireGuardError('protocol', 'WireGuard helper response was too large.'));
          return;
        }
        let newlineIndex = buffer.indexOf('\n');
        while (newlineIndex >= 0) {
          const lineValue = buffer.slice(0, newlineIndex).replace(/\r$/u, '');
          buffer = buffer.slice(newlineIndex + 1);
          if (lineValue.trim().length > 0) {
            try {
              const message = JSON.parse(lineValue) as unknown;
              if (isRecord(message) && typeof message.action === 'string') {
                if (message.action === 'error') fail(new WireGuardError('protocol', 'WireGuard helper reported an error.'));
                else if (message.action === action) succeed();
              }
            } catch {
              // Ignore unrelated stdout or protocol lines.
            }
          }
          if (buffer.length === 0 || newlineIndex < 0) break;
          newlineIndex = buffer.indexOf('\n');
        }
      };
      const onClosed = (): void => fail(new WireGuardError('connection', 'WireGuard helper disconnected.'));
      socket.on('data', onData);
      socket.on('error', onClosed);
      socket.on('end', onClosed);
      socket.on('close', onClosed);
      try {
        socket.write(line);
      } catch {
        onClosed();
      }
      return () => socket.removeAllListeners();
    });
}
function launchAndConnect(
  server: WireGuardServerLike,
  spawnLauncher: () => WireGuardChildProcessLike,
  timer: WireGuardTimer,
  timeouts: Pick<WireGuardTimeoutOptions, 'uac' | 'connect'>,
  cancellation: StartupCancellation,
): Promise<WireGuardSocketLike> {
  return new Promise((resolvePromise, rejectPromise) => {
    let settled = false;
    let connection: WireGuardSocketLike | null = null;
    let launcher: WireGuardChildProcessLike | null = null;
    let uacTimer: unknown = undefined;
    let connectTimer: unknown;
    let removeCancel = (): void => undefined;
    const cleanup = (): void => {
      timer.clearTimeout(uacTimer);
      timer.clearTimeout(connectTimer);
      removeCancel();
      server.removeAllListeners();
      launcher?.removeAllListeners();
    };
    const fail = (error: WireGuardError): void => {
      if (settled) return;
      settled = true;
      cleanup();
      destroySocket(connection);
      rejectPromise(error);
    };
    const onConnection = (socket: WireGuardSocketLike): void => {
      if (connection !== null || settled) {
        destroySocket(socket);
        return;
      }
      connection = socket;
      settled = true;
      cleanup();
      resolvePromise(socket);
    };
    const onServerError = (): void => {
      fail(new WireGuardError('connection', 'WireGuard IPC server failed.'));
    };
    const onLauncherError = (): void => {
      fail(new WireGuardError('spawn-failed', 'Unable to launch WireGuard helper.'));
    };
    const onLauncherClose = (code: number | null): void => {
      if (settled) return;
      if (code !== 0) {
        fail(new WireGuardError('spawn-failed', 'WireGuard UAC launch failed.'));
        return;
      }
      timer.clearTimeout(uacTimer);
      connectTimer = timer.setTimeout(
        () => fail(new WireGuardError('timeout', 'WireGuard helper connection timed out.')),
        timeouts.connect,
      );
    };
    uacTimer = timer.setTimeout(
      () => fail(new WireGuardError('timeout', 'WireGuard UAC launch timed out.')),
      timeouts.uac,
    );
    if (settled) return;
    server.on('connection', onConnection);
    server.on('error', onServerError);
    removeCancel = cancellation.subscribe(() => {
      fail(new WireGuardError('cancelled', 'WireGuard startup was cancelled.'));
    });
    if (settled) return;
    try {
      launcher = spawnLauncher();
      launcher.once('error', onLauncherError);
      launcher.once('close', onLauncherClose);
    } catch {
      fail(new WireGuardError('spawn-failed', 'Unable to launch WireGuard helper.'));
    }
  });
}
function parseKeyOutput(output: string): WireGuardKeyPair | null {
  for (const line of output.split(/\r?\n/u).reverse()) {
    if (line.trim().length === 0) continue;
    try {
      const message = JSON.parse(line) as unknown;
      if (!isRecord(message) || message.action !== 'genkey' || !isRecord(message.data)) continue;
      if (
        typeof message.data.public_key === 'string' &&
        message.data.public_key.length > 0 &&
        typeof message.data.private_key === 'string' &&
        message.data.private_key.length > 0
      ) {
        return {
          public_key: message.data.public_key,
          private_key: message.data.private_key,
        };
      }
    } catch {
      // Keep looking for the final protocol line.
    }
  }
  return null;
}
function runGenKey(
  helperPath: string,
  spawn: WireGuardSpawn,
  timer: WireGuardTimer,
  timeoutMs: number,
): Promise<WireGuardKeyPair> {
  return new Promise((resolvePromise, rejectPromise) => {
    let settled = false;
    let output = '';
    let child: WireGuardChildProcessLike | null = null;
    const cleanup = (): void => {
      timer.clearTimeout(timeoutHandle);
      child?.removeAllListeners();
      child?.stdout?.removeAllListeners();
    };
    const fail = (error: WireGuardError): void => {
      if (settled) return;
      settled = true;
      cleanup();
      rejectPromise(error);
    };
    const onData = (chunk: string | Buffer): void => {
      output += typeof chunk === 'string' ? chunk : chunk.toString('utf8');
      if (Buffer.byteLength(output, 'utf8') > WIREGUARD_MAX_LINE_BYTES) {
        killChild(child);
        fail(new WireGuardError('protocol', 'WireGuard key output was too large.'));
      }
    };
    const onError = (): void => {
      fail(new WireGuardError('spawn-failed', 'Unable to run WireGuard key generation.'));
    };
    const onClose = (code: number | null): void => {
      if (settled) return;
      if (code !== 0) {
        fail(new WireGuardError('protocol', 'WireGuard key generation failed.'));
        return;
      }
      const keyPair = parseKeyOutput(output);
      if (keyPair === null) {
        fail(new WireGuardError('protocol', 'WireGuard key output was invalid.'));
      } else {
        settled = true;
        cleanup();
        resolvePromise(keyPair);
      }
    };
    const timeoutHandle = timer.setTimeout(() => {
      killChild(child);
      fail(new WireGuardError('timeout', 'WireGuard key generation timed out.'));
    }, timeoutMs);
    try {
      child = spawn(helperPath, ['genkey'], {
        windowsHide: true,
        stdio: ['ignore', 'pipe', 'ignore'],
      });
      if (child.stdout === null || child.stdout === undefined) {
        fail(new WireGuardError('spawn-failed', 'WireGuard key output was unavailable.'));
        return;
      }
      child.stdout.on('data', onData);
      child.once('error', onError);
      child.once('close', onClose);
    } catch {
      fail(new WireGuardError('spawn-failed', 'Unable to run WireGuard key generation.'));
    }
  });
}

export class WireGuardController implements WireGuardControllerApi {
  private readonly fileSystem: WireGuardFileSystem;
  private readonly spawn: WireGuardSpawn;
  private readonly serverFactory: WireGuardServerFactory;
  private readonly timer: WireGuardTimer;
  private readonly timeouts: WireGuardTimeoutOptions;
  private lifecyclePromise: Promise<void> = Promise.resolve();
  private stopPromise: Promise<void> | null = null;
  private startGeneration = 0;
  private startupResources: StartupResources | null = null;
  private startupControl: { cancel: () => void; done: Promise<void> } | null = null;
  private activeSocket: WireGuardSocketLike | null = null;
  private tunnelAddress: string | null = null;
  private state: WireGuardTunnelState = 'idle';
  private disposed = false;

  constructor(private readonly options: WireGuardControllerOptions) {
    this.fileSystem = options.fileSystem ?? defaultFileSystem;
    this.spawn = options.spawn ?? defaultSpawn;
    this.serverFactory = options.serverFactory ?? defaultServerFactory;
    this.timer = options.timer ?? defaultTimer;
    this.timeouts = { ...WIREGUARD_TIMEOUTS_MS, ...options.timeouts };
  }

  getAvailability(): WireGuardAvailability {
    try {
      return this.fileSystem.existsSync(this.options.helperPath)
        ? { available: true }
        : { available: false, reason: 'missing' };
    } catch {
      return { available: false, reason: 'missing' };
    }
  }

  getStatus(): WireGuardStatus {
    const availability = this.getAvailability();
    const state = !availability.available && (this.state === 'idle' || this.state === 'unavailable')
      ? 'unavailable'
      : this.state;
    return {
      available: availability.available,
      state,
      ...(this.tunnelAddress === null ? {} : { address: this.tunnelAddress }),
    };
  }

  generateKeyPair(): Promise<WireGuardKeyPair> {
    if (this.disposed) return Promise.reject(new WireGuardError('disposed', 'WireGuard controller is disposed.'));
    if (!this.getAvailability().available) {
      return Promise.reject(new WireGuardError('helper-missing', 'WireGuard helper is not available.'));
    }
    return runGenKey(this.options.helperPath, this.spawn, this.timer, this.timeouts.genkey);
  }

  startTunnel(config: WireGuardTunnelConfig): Promise<WireGuardStatus> {
    if (this.disposed) return Promise.reject(new WireGuardError('disposed', 'WireGuard controller is disposed.'));
    const generation = this.startGeneration;
    return this.enqueue(async () => {
      if (this.disposed) throw new WireGuardError('disposed', 'WireGuard controller is disposed.');
      if (generation !== this.startGeneration) {
        throw new WireGuardError('cancelled', 'WireGuard startup was cancelled.');
      }
      await this.stopInternal();
      return this.startInternal(validateWireGuardConfig(config));
    });
  }

  stopTunnel(): Promise<void> {
    if (this.stopPromise !== null) return this.stopPromise;
    this.startGeneration += 1;
    const startup = this.startupControl;
    startup?.cancel();
    const queued = (startup?.done ?? Promise.resolve()).then(() =>
      this.enqueue(() => this.stopInternal()),
    );
    const result = queued.finally(() => {
      if (this.stopPromise === result) this.stopPromise = null;
    });
    this.stopPromise = result;
    return result;
  }

  dispose(): Promise<void> {
    this.disposed = true;
    return this.stopTunnel();
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.lifecyclePromise.then(operation, operation);
    this.lifecyclePromise = next.then(() => undefined, () => undefined);
    return next;
  }

  private async startInternal(config: WireGuardTunnelConfig): Promise<WireGuardStatus> {
    if (!this.getAvailability().available) {
      this.state = 'unavailable';
      throw new WireGuardError('helper-missing', 'WireGuard helper is not available.');
    }
    this.state = 'starting';
    const cancellation = createCancellation();
    let resolveDone: () => void = () => undefined;
    const done = new Promise<void>((resolvePromise) => {
      resolveDone = resolvePromise;
    });
    const control = { cancel: cancellation.cancel, done };
    const resources: StartupResources = { server: null, socket: null, launcher: null };
    this.startupControl = control;
    this.startupResources = resources;
    try {
      const server = this.serverFactory();
      resources.server = server;
      await listenServer(server, this.timer, this.timeouts.listen, cancellation);
      const address = server.address();
      if (address === null || typeof address === 'string' || !Number.isSafeInteger(address.port) || address.port < 1 || address.port > 65_535) {
        throw new WireGuardError('connection', 'WireGuard IPC server did not expose a valid port.');
      }
      const port = address.port;
      const socket = await launchAndConnect(
        server,
        () => {
          const launcher = this.spawn(
            'powershell.exe',
            [
              '-NoLogo',
              '-NoProfile',
              '-NonInteractive',
              '-WindowStyle',
              'Hidden',
              '-Command',
              buildRunAsPowerShellCommand(this.options.helperPath, port),
            ],
            { windowsHide: true, stdio: 'ignore' },
          );
          resources.launcher = launcher;
          return launcher;
        },
        this.timer,
        { uac: this.timeouts.uac, connect: this.timeouts.connect },
        cancellation,
      );
      resources.socket = socket;
      bestEffort(() => server.close(() => undefined));
      resources.server = null;
      await waitForAction(
        socket,
        JSON.stringify(config) + '\n',
        'up',
        this.timer,
        this.timeouts.up,
        cancellation,
      );
      this.startupResources = null;
      this.activeSocket = socket;
      this.tunnelAddress = config.address;
      this.state = 'running';
      return this.getStatus();
    } catch (error) {
      killChild(resources.launcher);
      try {
        await this.stopSocket(resources.socket, cancellation);
      } catch {
        // Preserve the startup failure while still closing every resource.
      }
      await closeServerBounded(resources.server, this.timer, this.timeouts.close);
      this.startupResources = null;
      this.activeSocket = null;
      this.tunnelAddress = null;
      this.state = this.getAvailability().available ? 'idle' : 'unavailable';
      throw toWireGuardError(error);
    } finally {
      if (this.startupControl === control) this.startupControl = null;
      resolveDone();
    }
  }

  private async stopInternal(): Promise<void> {
    const activeSocket = this.activeSocket;
    const startup = this.startupResources;
    this.activeSocket = null;
    this.startupResources = null;
    if (activeSocket === null && startup === null) {
      this.tunnelAddress = null;
      this.state = this.getAvailability().available ? 'idle' : 'unavailable';
      return;
    }
    this.state = 'stopping';
    let failure: WireGuardError | null = null;
    try {
      if (activeSocket !== null) {
        try {
          await this.stopSocket(activeSocket);
        } catch (error) {
          failure = toWireGuardError(error);
        }
      }
      if (startup !== null) {
        killChild(startup.launcher);
        try {
          await this.stopSocket(startup.socket);
        } catch (error) {
          failure ??= toWireGuardError(error);
        }
        await closeServerBounded(startup.server, this.timer, this.timeouts.close);
      }
    } finally {
      this.tunnelAddress = null;
      this.state = this.getAvailability().available ? 'idle' : 'unavailable';
    }
    if (failure !== null) throw failure;
  }

  private async stopSocket(
    socket: WireGuardSocketLike | null,
    cancellation?: StartupCancellation,
  ): Promise<void> {
    if (socket === null) return;
    try {
      await waitForAction(
        socket,
        '{"action":"down"}\n',
        'down',
        this.timer,
        this.timeouts.down,
        cancellation,
      );
    } finally {
      destroySocket(socket);
    }
  }
}

export function createWireGuardController(
  options: WireGuardControllerOptions,
): WireGuardController {
  return new WireGuardController(options);
}
