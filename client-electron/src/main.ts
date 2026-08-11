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
import { createWindowOptions } from './window-options';

let mainWindow: BrowserWindow | null = null;
let clientDatabase: ClientDatabase | null = null;
let disposeStorageIpc: (() => void) | null = null;
let rendererTarget: RendererPermissionTarget | null = null;

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
  if (mainWindow === null || mainWindow.isDestroyed()) return null;
  return mainWindow.webContents;
}

function createMainWindow(): BrowserWindow {
  const window = new BrowserWindow(
    createWindowOptions(path.join(__dirname, 'preload.js')),
  );

  window.once('ready-to-show', () => window.show());
  window.on('closed', () => {
    mainWindow = null;
  });
  mainWindow = window;
  loadRenderer(window);
  return window;
}

function focusMainWindow(): void {
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

app.on('web-contents-created', (_event, contents) => {
  contents.setWindowOpenHandler(() => ({ action: 'deny' }));
});

app.on('will-quit', disposeLocalStorage);

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
  disposeStorageIpc = registerStorageIpc(ipcMain, {
    database,
    getMainWindowId: () => {
      if (mainWindow === null || mainWindow.isDestroyed()) {
        return null;
      }
      return mainWindow.webContents.id;
    },
  });
  createMainWindow();
  app.on('activate', focusMainWindow);
}).catch(() => {
  disposeLocalStorage();
  console.error('Unable to start NexusRoom.');
  app.exit(1);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
