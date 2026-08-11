export type RuntimePlatform = 'win32' | 'darwin' | 'linux' | 'other' | 'browser';

export interface RuntimeInfo {
  readonly platform: RuntimePlatform;
  readonly electron: string;
  readonly chrome: string;
}

export interface NexusRoomApi {
  readonly getRuntimeInfo: () => RuntimeInfo;
}
