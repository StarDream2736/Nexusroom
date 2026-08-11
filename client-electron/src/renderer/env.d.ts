import type { NexusRoomApi } from '../shared/preload-api';

declare global {
  interface Window {
    readonly nexusroom: NexusRoomApi;
  }
}

export {};
