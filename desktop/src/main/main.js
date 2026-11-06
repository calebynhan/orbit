// Orbit for Windows and Linux. Lives in the tray; a global shortcut opens the capture bar.
import { app, globalShortcut, ipcMain, Notification, session, shell } from 'electron';
import fs from 'node:fs';

import * as settings from './settings.js';
import { registerScheme, handleScheme } from './protocol.js';
import { registerFileHandlers } from './files.js';
import { registerBubbleHandlers } from './bubble.js';
import { RecordingCoordinator, recordingsRoot } from './coordinator.js';
import { openEditor, chooseRecording, registerEditorHandlers } from './editor.js';
import { OrbitTray } from './tray.js';
import { createWindow } from './windows.js';
import { showError } from './alerts.js';
import { hiddenFlag, loginSupported, openAtLogin, setOpenAtLogin } from './login.js';
import { displayString, validationProblem } from '../core/shortcut.js';

const toggleFlag = '--toggle';
const isLinux = process.platform === 'linux';
const isWayland = isLinux && (process.env.XDG_SESSION_TYPE === 'wayland' || Boolean(process.env.WAYLAND_DISPLAY));

if (isLinux) {
  // Screen capture through PipeWire and the desktop portal (needed on Wayland).
  app.commandLine.appendSwitch('enable-features', 'WebRTCPipeWireCapturer,GlobalShortcutsPortal');
  // The capture bar, bubble, and area overlay place themselves on screen, which Wayland doesn't
  // allow apps to do. Run through XWayland unless asked not to.
  if (isWayland && !process.argv.some((a) => a.startsWith('--ozone-platform')) && !process.env.ORBIT_NATIVE_WAYLAND) {
    const appImage = process.env.APPIMAGE;
    app.relaunch({ execPath: appImage || process.execPath, args: [...process.argv.slice(1), '--ozone-platform=x11'] });
    app.exit(0);
  }
}

registerScheme();

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  let coordinator = null;
  let tray = null;
  let welcome = null;

  app.on('second-instance', (_event, argv) => {
    if (!coordinator) return;
    // `orbit --toggle` is what to bind as a system shortcut where global shortcuts aren't allowed.
    if (argv.includes(toggleFlag)) coordinator.handleHotKey();
    else if (coordinator.phase === 'idle') coordinator.showToolbar();
  });

  // Keep running in the tray when every window is closed.
  app.on('window-all-closed', () => {});

  app.whenReady().then(async () => {
    handleScheme();
    // Camera, microphone, and screen capture for Orbit's own pages only.
    const allowedPermissions = ['media', 'display-capture', 'notifications'];
    const ownPage = (url) => typeof url === 'string' && url.startsWith('orbit://app/');
    session.defaultSession.setPermissionRequestHandler((webContents, permission, callback) => {
      callback(ownPage(webContents.getURL()) && allowedPermissions.includes(permission));
    });
    session.defaultSession.setPermissionCheckHandler((webContents, permission) => ownPage(webContents?.getURL()) && allowedPermissions.includes(permission));

    registerFileHandlers();
    registerBubbleHandlers();
    registerEditorHandlers();

    coordinator = new RecordingCoordinator();
    coordinator.on('finished', (folder) => openEditor(folder));
    globalThis.orbitApp = { coordinator }; // for scripts/smoke.js

    const registerShortcut = (accelerator) => {
      globalShortcut.unregisterAll();
      try {
        return globalShortcut.register(accelerator, () => coordinator.handleHotKey());
      } catch {
        return false;
      }
    };

    const showWelcome = () => {
      if (welcome && !welcome.isDestroyed()) {
        welcome.show();
        welcome.focus();
        return;
      }
      welcome = createWindow('welcome.html', { width: 560, height: 640, resizable: false, maximizable: false, title: 'Welcome to Orbit' });
      welcome.once('ready-to-show', () => welcome.show());
      welcome.on('closed', () => {
        welcome = null;
        registerShortcut(settings.get('accelerator'));
      });
    };

    const actions = {
      status: () => ({ accelerator: settings.get('accelerator'), openAtLogin: openAtLogin(), loginSupported }),
      openRecording: () => chooseRecording(),
      revealRecordings: async () => {
        await fs.promises.mkdir(recordingsRoot(), { recursive: true }).catch(() => {});
        shell.openPath(recordingsRoot());
      },
      showWelcome,
      setOpenAtLogin: (enabled) => {
        setOpenAtLogin(enabled);
        tray?.refresh();
      },
      quit: () => app.quit(),
    };
    tray = new OrbitTray({ coordinator, actions });

    ipcMain.handle('welcome:state', () => ({
      accelerator: settings.get('accelerator'),
      shortcut: displayString(settings.get('accelerator'), process.platform),
      platform: process.platform,
      wayland: isWayland,
      openAtLogin: openAtLogin(),
      loginSupported,
      recordingsFolder: recordingsRoot(),
    }));
    ipcMain.handle('welcome:pause-shortcut', () => globalShortcut.unregisterAll());
    ipcMain.handle('welcome:set-shortcut', (_e, accelerator) => {
      const problem = validationProblem(accelerator);
      if (problem) return { ok: false, error: problem };
      if (!registerShortcut(accelerator)) {
        registerShortcut(settings.get('accelerator'));
        return { ok: false, error: `${displayString(accelerator, process.platform)} is taken by another app. Try a different one.` };
      }
      settings.set('accelerator', accelerator);
      tray.refresh();
      return { ok: true, shortcut: displayString(accelerator, process.platform) };
    });
    ipcMain.handle('welcome:set-login', (_e, enabled) => actions.setOpenAtLogin(Boolean(enabled)));
    ipcMain.handle('welcome:finish', (_e, startRecording) => {
      settings.set('welcomeShown', true);
      welcome?.close();
      if (startRecording) setTimeout(() => coordinator.showToolbar(), 250);
    });
    ipcMain.handle('app:open-recordings', () => actions.revealRecordings());

    const accelerator = settings.get('accelerator');
    const registered = registerShortcut(accelerator);
    if (!settings.get('welcomeShown')) {
      showWelcome();
    } else if (!registered) {
      showError(new Error(`Couldn’t register ${displayString(accelerator, process.platform)}. Another app may be using it. Pick a different one in the welcome guide.`), 'Shortcut unavailable');
      showWelcome();
    } else if (process.argv.includes(toggleFlag)) {
      coordinator.handleHotKey();
    } else if (!process.argv.includes(hiddenFlag) && Notification.isSupported()) {
      new Notification({ title: 'Orbit is ready', body: `Press ${displayString(accelerator, process.platform)} to record your screen.`, silent: true }).show();
    }

    // Open a recording folder passed on the command line: `orbit "/path/to/Recording …"`.
    const folderArg = process.argv.slice(1).find((a) => !a.startsWith('-') && fs.existsSync(a) && fs.statSync(a).isDirectory() && a !== app.getAppPath() && a !== '.');
    if (folderArg) openEditor(folderArg);
  });

  app.on('will-quit', () => globalShortcut.unregisterAll());
}
