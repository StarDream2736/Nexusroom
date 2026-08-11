import { contextBridge, ipcRenderer } from 'electron';
import {
  nexusRoomIpcChannels as channels,
  type AccountScope,
  type AccountSession,
  type CachedMessage,
  type MessageCacheEntry,
  type NexusRoomApi,
  type NexusRoomStorageApi,
  type NexusRoomWireGuardApi,
  type RuntimeInfo,
  type RuntimePlatform,
  type WireGuardTunnelConfig,
} from './shared/preload-api';

function normalizePlatform(platform: NodeJS.Platform): RuntimePlatform {
  if (platform === 'win32' || platform === 'darwin' || platform === 'linux') {
    return platform;
  }
  return 'other';
}

const getRuntimeInfo = (): RuntimeInfo => ({
  platform: normalizePlatform(process.platform),
  electron: process.versions.electron ?? 'unknown',
  chrome: process.versions.chrome ?? 'unknown',
});

const storage: NexusRoomStorageApi = {
  getSetting: (key) =>
    ipcRenderer.invoke(channels.getSetting, key) as Promise<string | null>,
  setSetting: (key, value) =>
    ipcRenderer.invoke(channels.setSetting, key, value) as Promise<void>,
  getSession: (scope: AccountScope) =>
    ipcRenderer.invoke(channels.getSession, scope) as Promise<AccountSession | null>,
  saveSession: (scope: AccountScope, accessToken: string) =>
    ipcRenderer.invoke(channels.saveSession, scope, accessToken) as Promise<void>,
  removeSession: (scope: AccountScope) =>
    ipcRenderer.invoke(channels.removeSession, scope) as Promise<void>,
  getMessages: (scope: AccountScope, roomId?: number) =>
    ipcRenderer.invoke(channels.getMessages, scope, roomId) as Promise<
      readonly CachedMessage[]
    >,
  saveMessages: (scope: AccountScope, messages: readonly MessageCacheEntry[]) =>
    ipcRenderer.invoke(channels.saveMessages, scope, messages) as Promise<void>,
  clearMessages: (scope: AccountScope, roomId?: number) =>
    ipcRenderer.invoke(channels.clearMessages, scope, roomId) as Promise<void>,
  clearData: () => ipcRenderer.invoke(channels.clearData) as Promise<void>,
};

const wireguard: NexusRoomWireGuardApi = {
  getAvailability: () =>
    ipcRenderer.invoke(channels.wireguardAvailability),
  generateKeyPair: () =>
    ipcRenderer.invoke(channels.wireguardGenerateKeyPair),
  startTunnel: (config: WireGuardTunnelConfig) =>
    ipcRenderer.invoke(channels.wireguardStartTunnel, config),
  stopTunnel: () =>
    ipcRenderer.invoke(channels.wireguardStopTunnel),
  getStatus: () =>
    ipcRenderer.invoke(channels.wireguardStatus),
};

const api: NexusRoomApi = { getRuntimeInfo, storage, wireguard };

contextBridge.exposeInMainWorld('nexusroom', api);
