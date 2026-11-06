// Tray icon: the Windows notification area / Linux status icon. Idle: a menu. Recording: stop.
// Mirrors Sources/Orbit/App/StatusMenu.swift.
import { Menu, nativeImage, Tray } from 'electron';
import path from 'node:path';

import { iconPath } from './windows.js';

const icon = (name) => nativeImage.createFromPath(path.join(path.dirname(iconPath), name));

export function formatElapsed(ms) {
  const total = Math.floor(ms / 1000);
  const pad = (n) => String(n).padStart(2, '0');
  return total >= 3600 ? `${Math.floor(total / 3600)}:${pad(Math.floor(total / 60) % 60)}:${pad(total % 60)}` : `${Math.floor(total / 60)}:${pad(total % 60)}`;
}

export class OrbitTray {
  constructor({ coordinator, actions }) {
    this.coordinator = coordinator;
    this.actions = actions;
    this.tray = new Tray(icon('tray-idle.png'));
    this.clock = null;
    this.tray.on('click', () => {
      // Windows: left click starts or stops, right click shows the menu. (Linux shows the menu.)
      if (this.coordinator.isRecording) this.coordinator.stopRecording();
      else if (this.coordinator.phase === 'idle') this.coordinator.showToolbar();
    });
    coordinator.on('phase', () => this.refresh());
    this.refresh();
  }

  refresh() {
    clearInterval(this.clock);
    this.clock = null;
    const { phase } = this.coordinator;
    if (phase === 'recording') {
      this.tray.setImage(icon('tray-recording.png'));
      const tick = () => this.tray.setToolTip(`Orbit — recording ${formatElapsed(Date.now() - (this.coordinator.startedAt ?? Date.now()))}. Click to stop.`);
      tick();
      this.clock = setInterval(tick, 1000);
      this.tray.setContextMenu(Menu.buildFromTemplate([
        { label: 'Stop Recording', click: () => this.coordinator.stopRecording() },
      ]));
      return;
    }
    this.tray.setImage(icon('tray-idle.png'));
    if (phase === 'finishing' || phase === 'starting') {
      this.tray.setToolTip(phase === 'finishing' ? 'Orbit — saving…' : 'Orbit — starting…');
      this.tray.setContextMenu(Menu.buildFromTemplate([{ label: phase === 'finishing' ? 'Saving…' : 'Starting…', enabled: false }]));
      return;
    }
    const { accelerator, openAtLogin, loginSupported } = this.actions.status();
    this.tray.setToolTip('Orbit');
    this.tray.setContextMenu(Menu.buildFromTemplate([
      { label: 'New Recording…', accelerator, registerAccelerator: false, click: () => this.coordinator.showToolbar() },
      { label: 'Open Recording…', click: () => this.actions.openRecording() },
      { label: 'Show Recordings Folder', click: () => this.actions.revealRecordings() },
      { type: 'separator' },
      { label: 'Welcome Guide & Shortcut…', click: () => this.actions.showWelcome() },
      ...(loginSupported ? [{ label: 'Open at Login', type: 'checkbox', checked: openAtLogin, click: (item) => this.actions.setOpenAtLogin(item.checked) }] : []),
      { type: 'separator' },
      { label: 'Quit Orbit', click: () => this.actions.quit() },
    ]));
  }
}
