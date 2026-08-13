/**
 * Native window sizing for the two renderer states.
 *
 * Keeping these values in one small module makes the transition easy to
 * reason about and allows it to be tested without starting Electron.
 */
export type WindowMode = 'unauthenticated' | 'authenticated';

export interface WindowState {
  readonly width: number;
  readonly height: number;
  readonly minWidth: number;
  readonly minHeight: number;
  readonly resizable: boolean;
  readonly maximizable: boolean;
}

export const unauthenticatedWindowState: WindowState = {
  width: 480,
  height: 620,
  minWidth: 400,
  minHeight: 500,
  resizable: false,
  maximizable: false,
};

export const authenticatedWindowState: WindowState = {
  width: 1280,
  height: 800,
  minWidth: 960,
  minHeight: 640,
  resizable: true,
  maximizable: true,
};

export function getWindowState(mode: WindowMode): WindowState {
  return mode === 'authenticated'
    ? authenticatedWindowState
    : unauthenticatedWindowState;
}

export interface WindowStateTarget {
  readonly setSize: (width: number, height: number, animate?: boolean) => void;
  readonly setMinimumSize: (width: number, height: number) => void;
  readonly setResizable: (resizable: boolean) => void;
  readonly setMaximizable: (maximizable: boolean) => void;
  readonly isMaximized?: () => boolean;
  readonly unmaximize?: () => void;
}

/** Apply a state transition to a BrowserWindow-like target. */
export function applyWindowState(target: WindowStateTarget, mode: WindowMode): void {
  const state = getWindowState(mode);
  // A maximized authenticated window must be restored before compact sizing;
  // otherwise Electron keeps the maximized bounds and ignores setSize.
  if (mode === 'unauthenticated' && target.isMaximized?.()) {
    target.unmaximize?.();
  }
  // Unlock the fixed compact window before changing its minimum bounds.
  // On Windows, applying a larger minimum while the window is not resizable
  // leaves the BrowserWindow at its compact size after authentication.
  target.setResizable(true);
  target.setMinimumSize(state.minWidth, state.minHeight);
  target.setMaximizable(state.maximizable);
  target.setSize(state.width, state.height);
  target.setResizable(state.resizable);
}
