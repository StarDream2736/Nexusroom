import { nexusRoomIpcChannels } from '../shared/preload-api';
import type { WindowMode } from './window-state';

export interface WindowStateIpcInvokeEvent {
  readonly sender: {
    readonly id: number;
  };
}

export type WindowStateIpcHandler = (
  event: WindowStateIpcInvokeEvent,
  ...args: unknown[]
) => Promise<void>;

export interface WindowStateIpcMainLike {
  handle(channel: string, listener: WindowStateIpcHandler): void;
  removeHandler(channel: string): void;
}

export interface WindowStateIpcOptions {
  readonly getMainWindowId: () => number | null;
  readonly apply: (mode: WindowMode) => void;
}

function assertMainWindow(
  event: WindowStateIpcInvokeEvent,
  getMainWindowId: () => number | null,
): void {
  if (event.sender.id !== getMainWindowId()) {
    throw new Error('Window state IPC is only available to the current main window.');
  }
}

function requireAuthenticated(value: unknown): boolean {
  if (typeof value !== 'boolean') {
    throw new Error('Authenticated window state must be a boolean.');
  }
  return value;
}

export function createWindowStateIpcHandler(
  options: WindowStateIpcOptions,
): WindowStateIpcHandler {
  return async (event, value) => {
    assertMainWindow(event, options.getMainWindowId);
    options.apply(requireAuthenticated(value) ? 'authenticated' : 'unauthenticated');
  };
}

export function registerWindowStateIpc(
  ipcMain: WindowStateIpcMainLike,
  options: WindowStateIpcOptions,
): () => void {
  const channel = nexusRoomIpcChannels.setAuthenticatedWindowState;
  ipcMain.handle(channel, createWindowStateIpcHandler(options));
  return () => {
    ipcMain.removeHandler(channel);
  };
}
