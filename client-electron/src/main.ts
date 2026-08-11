import { app, BrowserWindow, ipcMain, session } from 'electron';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { ClientDatabase } from './main/client-database';
import { resolveClientDatabasePath } from './main/database-path';
import {
  isAudioPermissionCheck,
  isAudioPermissionRequest,
  selectRendererPermissionTarget,
  isTrustedRendererRequest,
  type RendererPermissionTarget,
} from './main/media-permission';
import { registerStorageIpc } from './main/storage-ipc';
import {
  createWireGuardController,
  resolveWireGuardHelperPath,
  type WireGuardControllerApi,
} from './main/wireguard-controller';
import { registerWireGuardIpc } from './main/wireguard-ipc';
import { createWindowOptions } from './window-options';

let mainWindow: BrowserWindow | null = null;
let clientDatabase: ClientDatabase | null = null;
let disposeStorageIpc: (() => void) | null = null;
let disposeWireGuardIpc: (() => void) | null = null;
let wireguardController: WireGuardControllerApi | null = null;
let rendererTarget: RendererPermissionTarget | null = null;
let isShuttingDown = false;

export interface MainShutdownTimer {
  setTimeout(callback: () => void, delayMs: number): unknown;
  clearTimeout(handle: unknown): void;
}

export interface ShutdownCoordinatorOptions {
  readonly hideWindow: () => void;
  readonly disableInteraction: () => void;
  readonly stopWireGuard: () => Promise<void> | void;
  readonly closeDatabase: () => Promise<void> | void;
  readonly exit: (code: number) => void;
  readonly timer?: MainShutdownTimer;
  readonly hardTimeoutMs?: number;
}

export interface ShutdownCoordinator {
  readonly started: boolean;
  readonly finished: boolean;
  request(): Promise<void>;
}

const defaultShutdownTimer: MainShutdownTimer = {
  setTimeout: (callback, delayMs) => setTimeout(callback, delayMs),
  clearTimeout: (handle) => clearTimeout(handle as ReturnType<typeof setTimeout>),
};

export function createShutdownCoordinator(
  options: ShutdownCoordinatorOptions,
): ShutdownCoordinator {
  const timer = options.timer ?? defaultShutdownTimer;
  const hardTimeoutMs = options.hardTimeoutMs ?? 2_000;
  let hasStarted = false;
  let hasFinished = false;
  let requestPromise: Promise<void> | null = null;

  const request = (): Promise<void> => {
    if (requestPromise !== null) {
      return requestPromise;
    }
    hasStarted = true;
    try {
      options.disableInteraction();
    } catch {
      // Cleanup continues even if the UI has already been destroyed.
    }
    try {
      options.hideWindow();
    } catch {
      // Cleanup continues even if the UI has already been destroyed.
    }

    requestPromise = new Promise<void>((resolvePromise) => {
      let settled = false;
      const finish = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        hasFinished = true;
        timer.clearTimeout(timeoutHandle);
        try {
          options.exit(0);
        } finally {
          resolvePromise();
        }
      };

      const timeoutHandle = timer.setTimeout(finish, hardTimeoutMs);
      void Promise.allSettled([
        Promise.resolve().then(() => options.stopWireGuard()),
        Promise.resolve().then(() => options.closeDatabase()),
      ]).then(finish, finish);
    });
    return requestPromise;
  };

  return {
    get started(): boolean {
      return hasStarted;
    },
    get finished(): boolean {
      return hasFinished;
    },
    request,
  };
}

function disposeLocalStorage(): void {
  disposeStorageIpc?.();
  disposeStorageIpc = null;

  const database = clientDatabase;
  clientDatabase = null;
  if (database === null) {
    return;
  }
  try {
    database.close();
  } catch {
    console.error('Unable to close NexusRoom local database.');
  }
}

function disableMainWindowInteraction(): void {
  isShuttingDown = true;
  disposeStorageIpc?.();
  disposeStorageIpc = null;
  disposeWireGuardIpc?.();
  disposeWireGuardIpc = null;
}

function hideMainWindow(): void {
  if (mainWindow === null || mainWindow.isDestroyed()) {
    return;
  }
  mainWindow.hide();
}

function loadRenderer(window: BrowserWindow): void {
  const target = currentRendererTarget();
  const loadResult = target.rendererKind === 'web'
    ? window.loadURL(target.rendererUrl)
    : window.loadFile(rendererFilePath());

  loadResult.catch((error: unknown) => {
    console.error('Unable to load NexusRoom renderer.', error);
  });
}

function rendererFilePath(): string {
  return path.join(__dirname, '../dist/renderer/index.html');
}

function currentRendererTarget(): RendererPermissionTarget {
  if (rendererTarget === null) {
    rendererTarget = selectRendererPermissionTarget({
      isPackaged: app.isPackaged,
      developmentUrl: process.env.NEXUSROOM_RENDERER_URL,
      fileUrl: pathToFileURL(rendererFilePath()).toString(),
    });
  }
  return rendererTarget;
}

function currentMainWindowWebContents(): object | null {
  if (isShuttingDown || mainWindow === null || mainWindow.isDestroyed()) return null;
  return mainWindow.webContents;
}

function createMainWindow(): BrowserWindow {
  const window = new BrowserWindow(
    createWindowOptions(path.join(__dirname, 'preload.js')),
  );

  window.once('ready-to-show', () => {
    if (!isShuttingDown && !window.isDestroyed()) window.show();
  });
  if (process.platform !== 'darwin') {
    window.on('close', (event) => {
      if (shutdownCoordinator.finished) return;
      event.preventDefault();
      void shutdownCoordinator.request();
    });
  }
  window.on('closed', () => {
    mainWindow = null;
  });
  mainWindow = window;
  loadRenderer(window);
  return window;
}

function focusMainWindow(): void {
  if (isShuttingDown) {
    return;
  }
  if (mainWindow === null || mainWindow.isDestroyed()) {
    mainWindow = null;
    createMainWindow();
    return;
  }

  if (mainWindow.isMinimized()) {
    mainWindow.restore();
  }
  mainWindow.show();
  mainWindow.focus();
}

const shutdownCoordinator = createShutdownCoordinator({
  disableInteraction: disableMainWindowInteraction,
  hideWindow: hideMainWindow,
  stopWireGuard: () => wireguardController?.dispose(),
  closeDatabase: disposeLocalStorage,
  exit: (code) => app.exit(code),
});

app.on('web-contents-created', (_event, contents) => {
  contents.setWindowOpenHandler(() => ({ action: 'deny' }));
});

app.on('before-quit', (event) => {
  if (shutdownCoordinator.finished) return;
  event.preventDefault();
  void shutdownCoordinator.request();
});

app.whenReady().then(() => {
  const permissionTarget = currentRendererTarget();
  session.defaultSession.setPermissionCheckHandler((webContents, permission, _origin, details) => {
    return isTrustedRendererRequest(
      webContents,
      currentMainWindowWebContents(),
      details,
      permissionTarget,
    ) && isAudioPermissionCheck(permission, details.mediaType);
  });
  session.defaultSession.setPermissionRequestHandler((webContents, permission, callback, details) => {
    const mediaTypes = permission === 'media' && 'mediaTypes' in details
      ? details.mediaTypes
      : undefined;
    callback(
      isTrustedRendererRequest(
        webContents,
        currentMainWindowWebContents(),
        details,
        permissionTarget,
      ) && isAudioPermissionRequest(permission, mediaTypes),
    );
  });
  const database = new ClientDatabase(
    resolveClientDatabasePath({
      isPackaged: app.isPackaged,
      executablePath: app.getPath('exe'),
      developmentRoot: path.resolve(__dirname, '..'),
    }),
  );
  clientDatabase = database;
  wireguardController = createWireGuardController({
    helperPath: resolveWireGuardHelperPath({
      isPackaged: app.isPackaged,
      executablePath: app.getPath('exe'),
      developmentHelperPath: path.resolve(
        __dirname,
        '../../client/native/wg-helper/nexusroom-wg.exe',
      ),
    }),
  });
  disposeStorageIpc = registerStorageIpc(ipcMain, {
    database,
    getMainWindowId: () => {
      if (isShuttingDown || mainWindow === null || mainWindow.isDestroyed()) {
        return null;
      }
      return mainWindow.webContents.id;
    },
  });
  disposeWireGuardIpc = registerWireGuardIpc(ipcMain, {
    controller: wireguardController,
    getMainWindowId: () => {
      if (isShuttingDown || mainWindow === null || mainWindow.isDestroyed()) {
        return null;
      }
      return mainWindow.webContents.id;
    },
  });
  createMainWindow();
  app.on('activate', focusMainWindow);
}).catch(() => {
  disposeLocalStorage();
  void wireguardController?.dispose();
  console.error('Unable to start NexusRoom.');
  app.exit(1);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin' && !isShuttingDown) {
    app.quit();
  }
});
