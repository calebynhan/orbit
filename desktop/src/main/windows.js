// Window factory with Orbit's security defaults.
import { BrowserWindow } from 'electron';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { appUrl } from './protocol.js';

const here = path.dirname(fileURLToPath(import.meta.url));
export const iconPath = path.resolve(here, '..', '..', 'assets', 'icons', 'icon.png');

/**
 * Creates a window showing `page` (a file in src/renderer).
 * `overlay: true` makes a frameless, transparent, always-on-top panel that never steals focus
 * unless `focusable` is set, and is hidden from screen capture where the OS supports it
 * (Windows 10 2004+; there's no equivalent on Linux).
 */
export function createWindow(page, { overlay = false, focusable = !overlay, query = '', webPreferences = {}, ...options } = {}) {
  const win = new BrowserWindow({
    show: false,
    icon: iconPath,
    backgroundColor: overlay ? '#00000000' : '#121212',
    ...(overlay
      ? {
          frame: false,
          transparent: true,
          resizable: false,
          movable: false,
          minimizable: false,
          maximizable: false,
          fullscreenable: false,
          skipTaskbar: true,
          hasShadow: false,
          alwaysOnTop: true,
          focusable,
        }
      : {}),
    ...options,
    webPreferences: {
      preload: path.join(here, 'preload.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      spellcheck: false,
      ...webPreferences,
    },
  });
  if (overlay) {
    win.setAlwaysOnTop(true, 'screen-saver');
    win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true, skipTransformProcessType: true });
    win.setContentProtection(true);
    win.setMenu(null);
  } else {
    win.setMenuBarVisibility(false);
  }
  win.loadURL(appUrl(page) + (query ? `?${query}` : ''));
  return win;
}

/** Resolves once the page has loaded. */
export function loaded(win) {
  return new Promise((resolve) => {
    if (!win.webContents.isLoading()) resolve();
    else win.webContents.once('did-finish-load', resolve);
  });
}
