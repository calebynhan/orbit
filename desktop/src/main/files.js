// Lets renderers stream large files to disk (recordings, exports) without holding them in memory.
// A page gets a writer only for a path main approved: a name inside a project folder it was given a
// token for, or the destination the user picked in a save dialog.
import { ipcMain } from 'electron';
import fs from 'node:fs';

import { folderForToken, inside } from './protocol.js';

const writers = new Map();
let nextId = 1;

export async function openWriter(file, owner) {
  const handle = await fs.promises.open(file, 'w');
  const id = nextId++;
  writers.set(id, { handle, file, owner });
  return { id, file };
}

function writer(event, id) {
  const entry = writers.get(id);
  if (!entry || entry.owner !== event.sender.id) throw new Error('Unknown file');
  return entry;
}

export function registerFileHandlers() {
  ipcMain.handle('file:create', async (event, token, name) => {
    const folder = folderForToken(token);
    const file = folder && typeof name === 'string' && !/[\\/]/.test(name) ? inside(folder, name) : null;
    if (!file) throw new Error('Not allowed');
    return openWriter(file, event.sender.id);
  });

  ipcMain.handle('file:write', async (event, id, data, position) => {
    const { handle } = writer(event, id);
    let offset = 0;
    while (offset < data.byteLength) {
      const { bytesWritten } = await handle.write(data, offset, data.byteLength - offset, position + offset);
      offset += bytesWritten;
    }
  });

  ipcMain.handle('file:close', async (event, id) => {
    const entry = writer(event, id);
    writers.delete(id);
    await entry.handle.close();
  });

  ipcMain.handle('file:abort', async (event, id) => {
    const entry = writer(event, id);
    writers.delete(id);
    await entry.handle.close().catch(() => {});
    await fs.promises.rm(entry.file, { force: true });
  });
}

/** Closes anything a window left open (it crashed or was closed mid-write). */
export async function closeWritersFor(ownerId) {
  for (const [id, entry] of writers) {
    if (entry.owner !== ownerId) continue;
    writers.delete(id);
    await entry.handle.close().catch(() => {});
  }
}
