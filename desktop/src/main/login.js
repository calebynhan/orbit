// "Open at Login": the registry Run key on Windows, an XDG autostart entry on Linux.
import { app } from 'electron';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const hiddenFlag = '--hidden';
export const loginSupported = process.platform === 'win32' || process.platform === 'linux';

const autostartFile = () => path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'autostart', 'orbit.desktop');

/** The command that starts this copy of Orbit (the AppImage itself when running from one). */
const executable = () => process.env.APPIMAGE || process.execPath;

export function openAtLogin() {
  if (process.platform === 'win32') return app.getLoginItemSettings({ args: [hiddenFlag] }).openAtLogin;
  if (process.platform === 'linux') return fs.existsSync(autostartFile());
  return false;
}

export function setOpenAtLogin(enabled) {
  if (process.platform === 'win32') {
    app.setLoginItemSettings({ openAtLogin: enabled, args: [hiddenFlag] });
  } else if (process.platform === 'linux') {
    const file = autostartFile();
    if (enabled) {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      const quoted = `"${executable().replace(/(["\\`$])/g, '\\$1')}"`;
      fs.writeFileSync(file, [
        '[Desktop Entry]',
        'Type=Application',
        'Name=Orbit',
        'Comment=Screen recorder with a movable face cam',
        `Exec=${quoted} ${hiddenFlag}`,
        'X-GNOME-Autostart-enabled=true',
        '',
      ].join('\n'));
    } else {
      fs.rmSync(file, { force: true });
    }
  }
}
