// Drives a live recording: toolbar → (optional) area + camera bubble → screen + camera files → editor.
// Mirrors Sources/Orbit/Capture/RecordingCoordinator.swift.
import { app, desktopCapturer, ipcMain, Menu, Notification, screen } from 'electron';
import { EventEmitter } from 'node:events';
import fs from 'node:fs';
import path from 'node:path';

import * as settings from './settings.js';
import { CameraBubble } from './bubble.js';
import { createWindow } from './windows.js';
import { folderToken } from './protocol.js';
import { closeWritersFor } from './files.js';
import { showError } from './alerts.js';
import { BubbleTrackRecorder, alignTrack } from '../core/bubbleTrack.js';
import { stateFromWindow } from '../core/overlayGeometry.js';
import { pixelSize, resolutionLabel, aspectLabel, resolutions, aspects, frameRates } from '../core/captureFormat.js';
import * as selection from '../core/selectionGeometry.js';
import { defaultOverlay, encodeProject, fileName, folderName, makeProject, Placement } from '../core/project.js';
import { displayString } from '../core/shortcut.js';

const sampleInterval = 1000 / 30;
const isWindows = process.platform === 'win32';
/** Only Windows can keep Orbit's own windows out of a screen capture. */
export const canHideOwnWindows = isWindows || process.platform === 'darwin';

export const recordingsRoot = () => path.join(app.getPath('videos'), 'Orbit');

/** Wall-clock seconds with sub-millisecond precision, comparable across Orbit's processes. */
const now = () => (performance.timeOrigin + performance.now()) / 1000;

function displayName(display, index) {
  if (display.label) return display.label;
  return `Display ${index + 1} (${display.size.width}×${display.size.height})`;
}

function withTimeout(promise, ms, message) {
  let timer;
  return Promise.race([
    promise.finally(() => clearTimeout(timer)),
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(message)), ms); }),
  ]);
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

export class RecordingCoordinator extends EventEmitter {
  constructor() {
    super();
    this.phase = 'idle'; // idle | choosing | starting | recording | finishing
    this.startedAt = null;
    this.displayId = screen.getPrimaryDisplay().id;
    this.toolbar = null;
    this.area = null;
    this.bubble = null;
    this.stopPill = null;
    this.recorder = null;
    this.session = null;
    this.registerHandlers();
  }

  get isRecording() {
    return this.phase === 'recording';
  }

  handleHotKey() {
    switch (this.phase) {
      case 'idle': this.showToolbar(); break;
      case 'choosing': this.cancel(); break;
      case 'recording': this.stopRecording(); break;
      default: break;
    }
  }

  setPhase(phase) {
    this.phase = phase;
    this.emit('phase', phase);
    this.pushToolbarState();
  }

  // MARK: Display and area

  get display() {
    const displays = screen.getAllDisplays();
    return displays.find((d) => d.id === this.displayId) ?? screen.getPrimaryDisplay();
  }

  get captureArea() {
    return settings.get('captureMode') === 'selection' && settings.get('selection') ? settings.get('selection') : this.display.bounds;
  }

  toolbarState() {
    const displays = screen.getAllDisplays();
    return {
      phase: this.phase,
      cameraOn: settings.get('cameraOn'),
      microphoneOn: settings.get('microphoneOn'),
      microphoneId: settings.get('microphoneId'),
      systemAudioOn: settings.get('systemAudioOn'),
      systemAudioSupported: isWindows,
      captureMode: settings.get('captureMode'),
      resolution: settings.get('resolution'),
      resolutionLabel: resolutionLabel[settings.get('resolution')],
      framesPerSecond: settings.get('framesPerSecond'),
      displays: displays.map((d, i) => ({ id: d.id, name: displayName(d, i) })),
      displayId: this.display.id,
      shortcut: displayString(settings.get('accelerator'), process.platform),
    };
  }

  pushToolbarState() {
    if (this.toolbar && !this.toolbar.isDestroyed()) this.toolbar.webContents.send('toolbar:state', this.toolbarState());
  }

  areaState() {
    const display = this.display;
    return {
      display: display.bounds,
      scaleFactor: display.scaleFactor,
      selection: settings.get('selection'),
      aspect: settings.get('aspect'),
      resolution: settings.get('resolution'),
      recording: this.phase === 'recording' || this.phase === 'starting',
    };
  }

  // MARK: Toolbar

  showToolbar() {
    if (this.phase !== 'idle') return;
    this.displayId = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).id;
    this.setPhase('choosing');
    this.refreshAreaOverlay();

    const work = this.display.workArea;
    const width = 760;
    const height = 76;
    this.toolbar = createWindow('toolbar.html', {
      overlay: true,
      focusable: true,
      movable: true,
      width,
      height,
      x: Math.round(work.x + (work.width - width) / 2),
      y: Math.round(work.y + work.height - height - 48),
    });
    this.toolbar.once('ready-to-show', () => {
      this.toolbar?.show();
      this.toolbar?.focus();
    });
    this.toolbar.on('closed', () => {
      this.toolbar = null;
      if (this.phase === 'choosing') this.cancel();
    });
    if (settings.get('cameraOn')) this.startCameraPreview();
  }

  /** The toolbar page reports its natural size. Resize around where it is now (it can be dragged). */
  fitToolbar(width, height) {
    if (!this.toolbar || this.toolbar.isDestroyed()) return;
    const current = this.toolbar.getBounds();
    const work = screen.getDisplayMatching(current).workArea;
    const w = Math.min(Math.ceil(width), work.width - 24);
    const h = Math.ceil(height);
    if (w === current.width && h === current.height) return;
    const centerX = current.x + current.width / 2;
    const x = Math.round(Math.min(Math.max(centerX - w / 2, work.x), work.x + work.width - w));
    this.toolbar.setBounds({ x, y: current.y + current.height - h, width: w, height: h });
  }

  closeToolbar() {
    const toolbar = this.toolbar;
    this.toolbar = null;
    if (toolbar && !toolbar.isDestroyed()) toolbar.close();
  }

  cancel() {
    if (this.phase !== 'choosing') return;
    this.closeToolbar();
    this.closeAreaOverlay();
    this.stopCameraPreview();
    this.setPhase('idle');
  }

  set(key, value) {
    if (this.phase !== 'choosing') return;
    if (key === 'displayId') {
      if (screen.getAllDisplays().some((d) => d.id === value) && value !== this.displayId) {
        this.displayId = value;
        this.refreshAreaOverlay(true);
        if (settings.get('captureMode') !== 'selection') this.bubble?.keepInside(this.display.workArea);
      }
    } else if (key === 'cameraOn') {
      settings.set('cameraOn', Boolean(value));
      if (value) this.startCameraPreview(); else this.stopCameraPreview();
    } else if (['microphoneOn', 'systemAudioOn'].includes(key)) {
      settings.set(key, Boolean(value));
    } else if (key === 'microphoneId') {
      settings.set('microphoneId', typeof value === 'string' ? value : null);
    } else if (key === 'captureMode') {
      settings.set('captureMode', value);
      this.refreshAreaOverlay();
    } else if (key === 'resolution' || key === 'framesPerSecond') {
      settings.set(key, value);
      this.pushAreaState();
    } else if (key === 'aspect') {
      settings.set('aspect', value);
      const current = settings.get('selection');
      if (current) this.storeSelection(selection.constrained(current, value, 'body', this.display.bounds));
      this.pushAreaState();
    }
    this.pushToolbarState();
  }

  showOptionsMenu() {
    const radio = (label, key, value, current) => ({ label, type: 'radio', checked: value === current, click: () => this.set(key, value) });
    const menu = Menu.buildFromTemplate([
      { label: 'Resolution', enabled: false },
      ...resolutions.map((r) => radio(resolutionLabel[r], 'resolution', r, settings.get('resolution'))),
      { type: 'separator' },
      { label: 'Selection Shape', enabled: false },
      ...aspects.map((a) => radio(aspectLabel[a], 'aspect', a, settings.get('aspect'))),
      { type: 'separator' },
      { label: 'Frame Rate', enabled: false },
      ...frameRates.map((f) => radio(`${f} fps`, 'framesPerSecond', f, settings.get('framesPerSecond'))),
    ]);
    menu.popup({ window: this.toolbar ?? undefined });
  }

  showMicrophoneMenu(devices) {
    const chosen = settings.get('microphoneId');
    const resolved = devices.some((d) => d.id === chosen) ? chosen : devices[0]?.id;
    const items = devices.length
      ? devices.map((d) => ({ label: d.name, type: 'radio', checked: d.id === resolved, click: () => this.set('microphoneId', d.id) }))
      : [{ label: 'No microphone found', enabled: false }];
    Menu.buildFromTemplate(items).popup({ window: this.toolbar ?? undefined });
  }

  // MARK: Area selection overlay

  refreshAreaOverlay(rebuild = false) {
    if (this.phase !== 'choosing') return;
    if (settings.get('captureMode') !== 'selection') {
      this.closeAreaOverlay();
      return;
    }
    const bounds = this.display.bounds;
    const aspect = settings.get('aspect');
    if (rebuild || (this.area && JSON.stringify(this.area.bounds) !== JSON.stringify(bounds))) this.closeAreaOverlay();
    const stored = settings.get('selection');
    const fitted = stored && stored.width > 0 && selection.intersects(stored, bounds)
      ? selection.constrained(stored, aspect, 'body', bounds)
      : selection.constrained(selection.defaultSelection(bounds), aspect, 'body', bounds);
    this.storeSelection(fitted);
    if (this.area) {
      this.pushAreaState();
    } else {
      const win = createWindow('area.html', { overlay: true, focusable: true, ...bounds });
      this.area = { win, bounds };
      win.once('ready-to-show', () => {
        win.showInactive();
        this.toolbar?.moveTop();
        this.bubble?.win.moveTop();
      });
      win.on('closed', () => { if (this.area?.win === win) this.area = null; });
    }
    this.bubble?.keepInside(fitted);
  }

  pushAreaState() {
    if (this.area && !this.area.win.isDestroyed()) this.area.win.webContents.send('area:state', this.areaState());
  }

  storeSelection(rect) {
    settings.set('selection', rect);
  }

  closeAreaOverlay() {
    const area = this.area;
    this.area = null;
    if (area && !area.win.isDestroyed()) area.win.close();
  }

  // MARK: Camera preview

  startCameraPreview() {
    if (this.bubble) return;
    const area = settings.get('captureMode') === 'selection' && settings.get('selection') ? settings.get('selection') : this.display.workArea;
    this.bubble = new CameraBubble(area);
    this.bubble.win.on('closed', () => { this.bubble = null; });
  }

  stopCameraPreview() {
    this.bubble?.close();
    this.bubble = null;
  }

  /** The bubble page couldn't open the camera. */
  cameraFailed(message) {
    this.stopCameraPreview();
    if (this.phase === 'choosing') {
      settings.set('cameraOn', false);
      this.pushToolbarState();
    }
    showError(new Error(message), 'Couldn’t open the camera');
  }

  // MARK: Recording

  async startRecording() {
    if (this.phase !== 'choosing') return;
    const display = this.display;
    const area = this.captureArea;
    const isSelection = settings.get('captureMode') === 'selection';

    let source;
    try {
      // On Wayland this shows the desktop portal's own screen picker.
      const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: 0, height: 0 } });
      source = sources.find((s) => s.display_id === String(display.id)) ?? sources[0];
      if (!source) throw new Error('No screen is available to record.');
    } catch (error) {
      showError(error, 'Couldn’t start recording');
      return;
    }
    if (this.phase !== 'choosing') return;

    const createdAt = new Date();
    const folder = path.join(recordingsRoot(), folderName(createdAt));
    try {
      await fs.promises.mkdir(folder, { recursive: true });
    } catch (error) {
      showError(error, 'Couldn’t start recording');
      return;
    }

    this.closeToolbar();
    this.setPhase('starting');
    if (this.area) {
      this.area.win.setIgnoreMouseEvents(true);
      this.area.win.setFocusable(false);
      this.pushAreaState();
      this.bubble?.win.moveTop(); // keep the bubble draggable above the click-through outline
    }

    const fps = settings.get('framesPerSecond');
    const job = {
      token: folderToken(folder),
      sourceId: source.id,
      display: { width: display.bounds.width, height: display.bounds.height, scaleFactor: display.scaleFactor },
      crop: isSelection ? { x: area.x - display.bounds.x, y: area.y - display.bounds.y, width: area.width, height: area.height } : null,
      outputSize: pixelSize(settings.get('resolution'), area, display.scaleFactor),
      framesPerSecond: fps,
      microphone: settings.get('microphoneOn') ? { deviceId: settings.get('microphoneId') } : null,
      systemAudio: isWindows && settings.get('systemAudioOn'),
      camera: Boolean(this.bubble),
    };

    const started = deferred();
    this.session = { folder, area, fps, job, started, finished: null, track: new BubbleTrackRecorder(), sampler: null };
    this.recorder = createWindow('recorder.html', { width: 320, height: 200, webPreferences: { backgroundThrottling: false } });
    const recorderId = this.recorder.webContents.id;
    this.recorder.on('closed', () => {
      closeWritersFor(recorderId);
      this.recorder = null;
    });
    this.recorder.webContents.on('render-process-gone', () => this.recorderFailed('The recorder stopped unexpectedly.'));

    try {
      await withTimeout(started.promise, 30000, 'The recorder didn’t start in time.');
    } catch (error) {
      this.recorder?.destroy();
      this.recorder = null;
      this.session = null;
      this.closeAreaOverlay();
      this.stopCameraPreview();
      await fs.promises.rm(folder, { recursive: true, force: true }).catch(() => {});
      this.setPhase('idle');
      showError(error, 'Couldn’t start recording');
      return;
    }

    this.sampleBubble();
    this.session.sampler = setInterval(() => this.sampleBubble(), sampleInterval);
    this.startedAt = Date.now();
    this.setPhase('recording');
    this.showStopControls();
  }

  sampleBubble() {
    const bounds = this.bubble?.bounds;
    if (!bounds || !this.session) return;
    this.session.track.record(stateFromWindow(bounds, this.session.area), now());
  }

  /** Stop controls beyond the tray icon, which Windows often tucks away and GNOME doesn't show. */
  showStopControls() {
    const work = this.display.workArea;
    const width = 156;
    const height = 44;
    const bounds = { x: Math.round(work.x + (work.width - width) / 2), y: work.y + 12, width, height };
    const captured = !canHideOwnWindows && selection.intersects(bounds, this.session.area);
    if (captured) {
      // It would end up in the video. Tell the user how to stop instead.
      if (Notification.isSupported()) {
        new Notification({ title: 'Orbit is recording', body: `Press ${displayString(settings.get('accelerator'), process.platform)} to stop.`, silent: true }).show();
      }
      return;
    }
    this.stopPill = createWindow('stop.html', { overlay: true, movable: true, ...bounds });
    this.stopPill.once('ready-to-show', () => this.stopPill?.showInactive());
    this.stopPill.on('closed', () => { this.stopPill = null; });
  }

  closeStopControls() {
    const pill = this.stopPill;
    this.stopPill = null;
    if (pill && !pill.isDestroyed()) pill.close();
  }

  stopRecording() {
    if (this.phase !== 'recording') return;
    this.closeStopControls();
    this.setPhase('finishing');
    this.finish();
  }

  recorderFailed(message) {
    const session = this.session;
    if (!session) return;
    if (this.phase === 'starting') {
      session.started.reject(new Error(message));
    } else if (session.finished) {
      session.finished.reject(new Error(message));
    } else if (this.phase === 'recording') {
      showError(new Error(message), 'Recording stopped');
      this.stopRecording();
    }
  }

  async finish() {
    const session = this.session;
    if (!session) return;
    this.sampleBubble();
    clearInterval(session.sampler);
    session.finished = deferred();
    this.recorder?.webContents.send('recorder:stop');

    let result = null;
    try {
      result = await withTimeout(session.finished.promise, 120000, 'Saving the recording took too long.');
    } catch (error) {
      showError(error, 'Couldn’t save the recording');
    }
    this.recorder?.close();
    this.stopCameraPreview();
    this.closeAreaOverlay();
    this.session = null;
    this.startedAt = null;

    if (!result) {
      this.setPhase('idle');
      return;
    }
    const camera = result.cameraFile
      ? { file: result.cameraFile, offset: (result.cameraStartMs - result.screenStartMs) / 1000, includeAudio: false }
      : null;
    const project = makeProject({
      createdAt: new Date(),
      screenFile: result.screenFile,
      camera,
      overlay: { ...defaultOverlay, placement: camera ? Placement.followRecording : Placement.fixed, style: settings.get('bubbleStyle') },
      bubbleTrack: alignTrack(session.track.finished(), result.screenStartMs / 1000),
      framesPerSecond: session.fps,
    });
    this.setPhase('idle');
    try {
      await fs.promises.writeFile(path.join(session.folder, fileName), encodeProject(project));
      this.emit('finished', session.folder);
    } catch (error) {
      showError(error, 'Couldn’t save the recording');
    }
  }

  // MARK: IPC

  registerHandlers() {
    ipcMain.handle('toolbar:state', () => this.toolbarState());
    ipcMain.on('toolbar:set', (_e, key, value) => this.set(key, value));
    ipcMain.on('toolbar:fit', (_e, width, height) => this.fitToolbar(width, height));
    ipcMain.on('toolbar:cancel', () => this.cancel());
    ipcMain.on('toolbar:record', () => this.startRecording());
    ipcMain.on('toolbar:options', () => this.showOptionsMenu());
    ipcMain.on('toolbar:microphones', (_e, devices) => this.showMicrophoneMenu(Array.isArray(devices) ? devices : []));

    ipcMain.handle('area:state', () => this.areaState());
    ipcMain.on('area:change', (_e, rect) => {
      if (this.phase !== 'choosing' || !rect) return;
      const fitted = selection.clamped(selection.constrained(rect, 'freeform', 'body', this.display.bounds), this.display.bounds);
      this.storeSelection(fitted);
    });
    ipcMain.on('area:done', () => this.bubble?.keepInside(settings.get('selection')));
    ipcMain.on('area:cancel', () => this.cancel());
    ipcMain.on('area:record', () => this.startRecording());

    ipcMain.on('bubble:error', (event, message) => {
      if (this.bubble && event.sender.id === this.bubble.id) this.cameraFailed(message);
    });

    ipcMain.handle('stop:info', () => ({ startedAt: this.startedAt }));
    ipcMain.on('stop:stop', () => this.stopRecording());

    const fromRecorder = (event) => this.recorder && event.sender.id === this.recorder.webContents.id;
    ipcMain.handle('recorder:job', (event) => (fromRecorder(event) ? this.session?.job : null));
    ipcMain.handle('recorder:started', (event) => {
      if (fromRecorder(event)) this.session?.started.resolve();
    });
    ipcMain.handle('recorder:failed', (event, message) => {
      if (fromRecorder(event)) this.recorderFailed(String(message));
    });
    ipcMain.handle('recorder:finished', (event, result) => {
      if (fromRecorder(event)) this.session?.finished?.resolve(result);
    });
  }
}
