import {
  nexusRoomIpcChannels,
  type NexusRoomWireGuardIpcChannel,
  type WireGuardTunnelConfig,
} from '../shared/preload-api';
import {
  type WireGuardControllerApi,
  WireGuardError,
} from './wireguard-controller';

export interface WireGuardIpcInvokeEvent {
  readonly sender: {
    readonly id: number;
  };
}

export type WireGuardIpcHandler = (
  event: WireGuardIpcInvokeEvent,
  ...args: unknown[]
) => Promise<unknown>;

export interface WireGuardIpcMainLike {
  handle(channel: string, listener: WireGuardIpcHandler): void;
  removeHandler(channel: string): void;
}

export interface WireGuardIpcOptions {
  readonly controller: WireGuardControllerApi;
  readonly getMainWindowId: () => number | null;
}

const wireGuardChannels: readonly NexusRoomWireGuardIpcChannel[] = [
  nexusRoomIpcChannels.wireguardAvailability,
  nexusRoomIpcChannels.wireguardGenerateKeyPair,
  nexusRoomIpcChannels.wireguardStartTunnel,
  nexusRoomIpcChannels.wireguardStopTunnel,
  nexusRoomIpcChannels.wireguardStatus,
];

function assertMainWindow(
  event: WireGuardIpcInvokeEvent,
  getMainWindowId: () => number | null,
): void {
  if (event.sender.id !== getMainWindowId()) {
    throw new WireGuardError(
      'connection',
      'WireGuard IPC is only available to the current main window.',
    );
  }
}

function requireNoArguments(args: readonly unknown[]): void {
  if (args.length !== 0) {
    throw new WireGuardError('invalid-config', 'Unexpected WireGuard IPC arguments.');
  }
}

function requireTunnelConfig(args: readonly unknown[]): WireGuardTunnelConfig {
  if (args.length !== 1 || typeof args[0] !== 'object' || args[0] === null) {
    throw new WireGuardError('invalid-config', 'Invalid WireGuard tunnel config.');
  }
  return args[0] as WireGuardTunnelConfig;
}

export function createWireGuardIpcHandlers(
  options: WireGuardIpcOptions,
): Readonly<Record<NexusRoomWireGuardIpcChannel, WireGuardIpcHandler>> {
  const assertSource = (event: WireGuardIpcInvokeEvent): void => {
    assertMainWindow(event, options.getMainWindowId);
  };

  return {
    [nexusRoomIpcChannels.wireguardAvailability]: async (event, ...args) => {
      assertSource(event);
      requireNoArguments(args);
      return options.controller.getAvailability();
    },
    [nexusRoomIpcChannels.wireguardGenerateKeyPair]: async (event, ...args) => {
      assertSource(event);
      requireNoArguments(args);
      return options.controller.generateKeyPair();
    },
    [nexusRoomIpcChannels.wireguardStartTunnel]: async (event, ...args) => {
      assertSource(event);
      return options.controller.startTunnel(requireTunnelConfig(args));
    },
    [nexusRoomIpcChannels.wireguardStopTunnel]: async (event, ...args) => {
      assertSource(event);
      requireNoArguments(args);
      await options.controller.stopTunnel();
      return options.controller.getStatus();
    },
    [nexusRoomIpcChannels.wireguardStatus]: async (event, ...args) => {
      assertSource(event);
      requireNoArguments(args);
      return options.controller.getStatus();
    },
  };
}

export function registerWireGuardIpc(
  ipcMain: WireGuardIpcMainLike,
  options: WireGuardIpcOptions,
): () => void {
  const handlers = createWireGuardIpcHandlers(options);
  for (const channel of wireGuardChannels) {
    ipcMain.handle(channel, handlers[channel]);
  }
  return () => {
    for (const channel of wireGuardChannels) {
      ipcMain.removeHandler(channel);
    }
  };
}
