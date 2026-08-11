import { contextBridge } from 'electron';
import type {
  NexusRoomApi,
  RuntimeInfo,
  RuntimePlatform,
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

const api: NexusRoomApi = { getRuntimeInfo };

contextBridge.exposeInMainWorld('nexusroom', api);
