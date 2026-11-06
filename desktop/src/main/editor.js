// Editor windows: one per recording folder. Mirrors Sources/Orbit/Editor/EditorModel.swift's
// file-system side (load, save, delete, import, export destination).
import { dialog, ipcMain, screen, shell } from 'electron';
import fs from 'node:fs';
import path from 'node:path';

import { createWindow } from './windows.js';
import { folderToken } from './protocol.js';
import { openWriter, closeWritersFor } from './files.js';
import { showError } from './alerts.js';
import { CameraBubble, broadcastStyle } from './bubble.js';
import * as settings from './settings.js';
import { bubbleStyle } from '../core/bubbleStyle.js';
import { decodeProject, encodeProject, fileName } from '../core/project.js';
import { recordingsRoot } from './coordinator.js';

const editors = new Map(); // webContents id → { win, folder, takeBubble }

export async function openEditor(folder) {
  for (const editor of editors.values()) {
    if (editor.folder === folder && !editor.win.isDestroyed()) {
      editor.win.show();
      editor.win.focus();
      return;
    }
  }
  try {
    decodeProject(await fs.promises.readFile(path.join(folder, fileName), 'utf8'));
  } catch (error) {
    const reason = error.code === 'ENOENT' ? `“${path.basename(folder)}” isn’t an Orbit recording (no project.json).` : `Couldn’t read “${path.basename(folder)}”: ${error.message}`;
    showError(new Error(reason), 'Couldn’t open the recording');
    return;
  }
  const win = createWindow('editor.html', { width: 1040, height: 760, minWidth: 780, minHeight: 560, title: path.basename(folder) });
  const id = win.webContents.id;
  editors.set(id, { win, folder, takeBubble: null });
  win.once('ready-to-show', () => win.show());
  win.on('closed', () => {
    editors.get(id)?.takeBubble?.close();
    editors.delete(id);
    closeWritersFor(id);
  });
}

export async function chooseRecording() {
  const root = recordingsRoot();
  await fs.promises.mkdir(root, { recursive: true }).catch(() => {});
  const result = await dialog.showOpenDialog({ title: 'Open Recording', defaultPath: root, buttonLabel: 'Open Recording', properties: ['openDirectory'] });
  if (!result.canceled && result.filePaths[0]) openEditor(result.filePaths[0]);
}

const stamp = () => Math.floor(Date.now() / 1000);

export function registerEditorHandlers() {
  const editor = (event) => {
    const entry = editors.get(event.sender.id);
    if (!entry) throw new Error('Not an editor');
    return entry;
  };

  ipcMain.handle('editor:load', async (event) => {
    const { folder } = editor(event);
    const text = await fs.promises.readFile(path.join(folder, fileName), 'utf8');
    return { folder, name: path.basename(folder), token: folderToken(folder), project: text };
  });

  ipcMain.handle('editor:save', async (event, project) => {
    const { folder } = editor(event);
    const text = encodeProject(decodeProject(project)); // validate before writing
    const file = path.join(folder, fileName);
    await fs.promises.writeFile(`${file}.tmp`, text);
    await fs.promises.rename(`${file}.tmp`, file);
  });

  ipcMain.handle('editor:delete', async (event) => {
    const entry = editor(event);
    const { response } = await dialog.showMessageBox(entry.win, {
      type: 'warning',
      message: 'Delete this recording?',
      detail: `“${path.basename(entry.folder)}” will be moved to the ${process.platform === 'win32' ? 'Recycle Bin' : 'Trash'}.`,
      buttons: [process.platform === 'win32' ? 'Move to Recycle Bin' : 'Move to Trash', 'Cancel'],
      defaultId: 1,
      cancelId: 1,
    });
    if (response !== 0) return false;
    entry.takeBubble?.close();
    await closeWritersFor(entry.win.webContents.id);
    // Release the media files before moving them (Windows won't move open files).
    entry.win.webContents.send('editor:release');
    await new Promise((resolve) => setTimeout(resolve, 150));
    try {
      await shell.trashItem(entry.folder);
    } catch (error) {
      console.error('Trash failed, deleting instead', error);
      try {
        await fs.promises.rm(entry.folder, { recursive: true, force: true });
      } catch (removeError) {
        showError(removeError, 'Couldn’t delete the recording');
        return false;
      }
    }
    setImmediate(() => entry.win.destroy());
    return true;
  });

  ipcMain.handle('editor:import', async (event) => {
    const entry = editor(event);
    const result = await dialog.showOpenDialog(entry.win, {
      title: 'Add Face Cam',
      message: 'Choose a video of your face. It starts at the beginning of the recording.',
      buttonLabel: 'Add Face Cam',
      properties: ['openFile'],
      filters: [{ name: 'Videos', extensions: ['mp4', 'm4v', 'mov', 'webm', 'mkv'] }],
    });
    if (result.canceled || !result.filePaths[0]) return null;
    const source = result.filePaths[0];
    const ext = path.extname(source) || '.mp4';
    const name = `camera-imported-${stamp()}${ext.toLowerCase()}`;
    await fs.promises.copyFile(source, path.join(entry.folder, name));
    return name;
  });

  ipcMain.handle('editor:take-name', () => `camera-take-${stamp()}.mp4`);

  ipcMain.handle('editor:default-style', (event, style) => {
    editor(event);
    settings.set('bubbleStyle', bubbleStyle(style?.shape, style?.outlineWidth, style?.outlineColor));
    broadcastStyle();
  });

  ipcMain.handle('editor:choose-export', async (event) => {
    const entry = editor(event);
    // Automated smoke test (scripts/smoke.js) exports without a dialog.
    if (process.env.ORBIT_SMOKE_EXPORT) return openWriter(process.env.ORBIT_SMOKE_EXPORT, event.sender.id);
    const result = await dialog.showSaveDialog(entry.win, {
      title: 'Export MP4',
      defaultPath: path.join(path.dirname(entry.folder), `${path.basename(entry.folder)}.mp4`),
      filters: [{ name: 'MP4 Video', extensions: ['mp4'] }],
    });
    if (result.canceled || !result.filePath) return null;
    const file = path.extname(result.filePath) ? result.filePath : `${result.filePath}.mp4`;
    return openWriter(file, event.sender.id);
  });

  ipcMain.handle('editor:reveal', (event, file) => {
    editor(event);
    shell.showItemInFolder(file);
  });

  /** Shows (or hides) a live camera bubble while recording a face-cam take over the playback. */
  ipcMain.handle('editor:take-bubble', (event, show) => {
    const entry = editor(event);
    entry.takeBubble?.close();
    entry.takeBubble = null;
    if (show) {
      const display = screen.getDisplayMatching(entry.win.getBounds());
      entry.takeBubble = new CameraBubble(display.workArea);
    }
  });

  ipcMain.handle('editor:error', (event, title, message) => {
    editor(event);
    showError(new Error(message), title);
  });
}
