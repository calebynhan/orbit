// The floating, draggable camera bubble shown while choosing and recording (and during a
// face-cam take in the editor). Mirrors Sources/Orbit/UI/CameraBubble.swift.
import { ipcMain, Menu, screen } from 'electron';

import * as settings from './settings.js';
import { createWindow } from './windows.js';
import { bubbleShapes, shapeLabel, sizePresets, outlinePresets, colorPresets, colorEquals } from '../core/bubbleStyle.js';

export const defaultDiameter = 200;
export const minDiameter = 100;
export const maxDiameter = 520;

const bubbles = new Map(); // webContents id → CameraBubble

function cornerBounds(area, diameter) {
  const margin = Math.min(40, area.width * 0.05, area.height * 0.05);
  return {
    x: Math.round(area.x + margin),
    y: Math.round(area.y + area.height - margin - diameter),
    width: diameter,
    height: diameter,
  };
}

export class CameraBubble {
  /** @param area global DIP rect to start in (bottom-left corner), e.g. the screen or the selection. */
  constructor(area, diameter = defaultDiameter) {
    // Resizable so setBounds can change its size under every window manager; being frameless and
    // transparent, it still has no resize border of its own.
    this.win = createWindow('bubble.html', { overlay: true, resizable: true, ...cornerBounds(area, diameter) });
    this.id = this.win.webContents.id;
    this.drag = null;
    bubbles.set(this.id, this);
    this.win.once('ready-to-show', () => this.win.showInactive());
    this.win.on('closed', () => bubbles.delete(this.id));
  }

  get bounds() {
    return this.win.isDestroyed() ? null : this.win.getBounds();
  }

  /** Brings the bubble into `area` if its center is outside it (keeps your placement otherwise). */
  keepInside(area) {
    const b = this.bounds;
    if (!b) return;
    const cx = b.x + b.width / 2;
    const cy = b.y + b.height / 2;
    if (cx >= area.x && cx <= area.x + area.width && cy >= area.y && cy <= area.y + area.height) return;
    const diameter = Math.max(Math.min(b.width, area.width * 0.5, area.height * 0.5), minDiameter);
    this.win.setBounds(cornerBounds(area, Math.round(diameter)));
  }

  resizeTo(diameter) {
    const b = this.bounds;
    if (!b) return;
    const size = Math.round(Math.min(Math.max(diameter, minDiameter), maxDiameter));
    const cx = b.x + b.width / 2;
    const cy = b.y + b.height / 2;
    this.win.setBounds({ x: Math.round(cx - size / 2), y: Math.round(cy - size / 2), width: size, height: size });
  }

  close() {
    if (!this.win.isDestroyed()) this.win.close();
  }

  showMenu() {
    const style = settings.get('bubbleStyle');
    const setStyle = (changes) => {
      settings.set('bubbleStyle', { ...style, ...changes });
      broadcastStyle();
    };
    const menu = Menu.buildFromTemplate([
      {
        label: 'Size',
        submenu: sizePresets.map(([label, size]) => ({ label, click: () => this.resizeTo(size) })),
      },
      {
        label: 'Shape',
        submenu: bubbleShapes.map((shape) => ({ label: shapeLabel[shape], type: 'radio', checked: style.shape === shape, click: () => setStyle({ shape }) })),
      },
      {
        label: 'Outline',
        submenu: outlinePresets.map(([label, width]) => ({ label, type: 'radio', checked: Math.abs(style.outlineWidth - width) < 0.001, click: () => setStyle({ outlineWidth: width }) })),
      },
      {
        label: 'Outline Color',
        submenu: colorPresets.map(([label, color]) => ({ label, type: 'radio', checked: colorEquals(style.outlineColor, color), click: () => setStyle({ outlineColor: color }) })),
      },
    ]);
    menu.popup({ window: this.win });
  }
}

export function broadcastStyle() {
  const style = settings.get('bubbleStyle');
  for (const bubble of bubbles.values()) {
    if (!bubble.win.isDestroyed()) bubble.win.webContents.send('bubble:style', style);
  }
}

export function registerBubbleHandlers() {
  const from = (event) => bubbles.get(event.sender.id);

  ipcMain.handle('bubble:style', () => settings.get('bubbleStyle'));

  // Dragging is done here rather than with a CSS drag region so the window's bounds are current on
  // every move (the recorder samples them) and right-click and scroll still reach the page.
  ipcMain.on('bubble:drag-start', (event) => {
    const bubble = from(event);
    if (!bubble?.bounds) return;
    bubble.drag = { cursor: screen.getCursorScreenPoint(), bounds: bubble.bounds };
  });

  ipcMain.on('bubble:drag', (event) => {
    const bubble = from(event);
    if (!bubble?.drag || bubble.win.isDestroyed()) return;
    const cursor = screen.getCursorScreenPoint();
    const { bounds } = bubble.drag;
    bubble.win.setBounds({ ...bounds, x: bounds.x + cursor.x - bubble.drag.cursor.x, y: bounds.y + cursor.y - bubble.drag.cursor.y });
  });

  ipcMain.on('bubble:drag-end', (event) => {
    const bubble = from(event);
    if (bubble) bubble.drag = null;
  });

  ipcMain.on('bubble:resize', (event, delta) => {
    const bubble = from(event);
    if (bubble?.bounds && Number.isFinite(delta)) bubble.resizeTo(bubble.bounds.width + delta);
  });

  ipcMain.on('bubble:menu', (event) => from(event)?.showMenu());
}
