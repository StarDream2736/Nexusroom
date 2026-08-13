export interface WindowOptions {
  readonly width: number;
  readonly height: number;
  readonly minWidth: number;
  readonly minHeight: number;
  readonly title: string;
  readonly show: boolean;
  readonly backgroundColor: string;
  readonly webPreferences: {
    readonly preload: string;
    readonly contextIsolation: true;
    readonly nodeIntegration: false;
    readonly nodeIntegrationInSubFrames: false;
    readonly sandbox: true;
    readonly webSecurity: true;
    readonly allowRunningInsecureContent: false;
    readonly webviewTag: false;
  };
}

export interface ApplicationMenuApi {
  readonly setApplicationMenu: (menu: null) => void;
}

/**
 * Electron creates a native application menu by default on Windows and Linux.
 * Keep the platform-conventional menu on macOS while removing it elsewhere.
 */
export function configureApplicationMenu(
  platform: string,
  menu: ApplicationMenuApi,
): void {
  if (platform !== 'darwin') {
    menu.setApplicationMenu(null);
  }
}

export function createWindowOptions(preloadPath: string): WindowOptions {
  return {
    width: 1280,
    height: 800,
    minWidth: 960,
    minHeight: 640,
    title: 'NexusRoom',
    show: false,
    backgroundColor: '#0b0b0c',
    webPreferences: {
      preload: preloadPath,
      contextIsolation: true,
      nodeIntegration: false,
      nodeIntegrationInSubFrames: false,
      sandbox: true,
      webSecurity: true,
      allowRunningInsecureContent: false,
      webviewTag: false,
    },
  };
}
