import { app, BrowserWindow, session } from 'electron';
import path from 'node:path';
import { createWindowOptions } from './window-options';

let mainWindow: BrowserWindow | null = null;

function loadRenderer(window: BrowserWindow): void {
  const rendererUrl = process.env.NEXUSROOM_RENDERER_URL;
  const loadResult = rendererUrl
    ? window.loadURL(rendererUrl)
    : window.loadFile(path.join(__dirname, '../dist/renderer/index.html'));

  loadResult.catch((error: unknown) => {
    console.error('Unable to load NexusRoom renderer.', error);
  });
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

app.whenReady().then(() => {
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => {
    callback(false);
  });
  createMainWindow();
  app.on('activate', focusMainWindow);
}).catch((error: unknown) => {
  console.error('Unable to start NexusRoom.', error);
  app.exit(1);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
