// `orbit://` serves the app's own pages (orbit://app/...) and recording files
// (orbit://media/<token>/<file>) with HTTP range support, so <video> can seek and
// mediabunny can read just the bytes it needs.
import { protocol } from 'electron';
import fs from 'node:fs';
import path from 'node:path';
import { Readable } from 'node:stream';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const srcRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const appRoot = path.resolve(srcRoot, '..');
const vendor = {
  'mediabunny.mjs': path.join(appRoot, 'node_modules', 'mediabunny', 'dist', 'bundles', 'mediabunny.mjs'),
};

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.json': 'application/json',
  '.mp4': 'video/mp4',
  '.m4v': 'video/mp4',
  '.mov': 'video/quicktime',
  '.webm': 'video/webm',
  '.mkv': 'video/x-matroska',
};

/** token → absolute folder. A page can only read media from folders main handed it. */
const folders = new Map();

export function registerScheme() {
  protocol.registerSchemesAsPrivileged([
    { scheme: 'orbit', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true, corsEnabled: true } },
  ]);
}

export function folderToken(folder) {
  for (const [token, existing] of folders) if (existing === folder) return token;
  const token = randomUUID();
  folders.set(token, folder);
  return token;
}

export function folderForToken(token) {
  return folders.get(token) ?? null;
}

export const appUrl = (page) => `orbit://app/renderer/${page}`;

/** Resolves `name` inside `folder`, refusing anything that escapes it. */
export function inside(folder, name) {
  const resolved = path.resolve(folder, name);
  return resolved.startsWith(path.resolve(folder) + path.sep) ? resolved : null;
}

function notFound() {
  return new Response('Not found', { status: 404 });
}

async function serveFile(file, request) {
  let stat;
  try {
    stat = await fs.promises.stat(file);
  } catch {
    return notFound();
  }
  if (!stat.isFile()) return notFound();
  const type = mimeTypes[path.extname(file).toLowerCase()] ?? 'application/octet-stream';
  const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get('range') ?? '');
  if (!range) {
    return new Response(Readable.toWeb(fs.createReadStream(file)), {
      status: 200,
      headers: { 'Content-Type': type, 'Content-Length': String(stat.size), 'Accept-Ranges': 'bytes' },
    });
  }
  let start = range[1] === '' ? null : Number(range[1]);
  let end = range[2] === '' ? null : Number(range[2]);
  if (start === null) {
    start = Math.max(0, stat.size - (end ?? 0));
    end = stat.size - 1;
  } else {
    end = end === null ? stat.size - 1 : Math.min(end, stat.size - 1);
  }
  if (start >= stat.size || start > end) {
    return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${stat.size}` } });
  }
  return new Response(Readable.toWeb(fs.createReadStream(file, { start, end })), {
    status: 206,
    headers: {
      'Content-Type': type,
      'Content-Length': String(end - start + 1),
      'Content-Range': `bytes ${start}-${end}/${stat.size}`,
      'Accept-Ranges': 'bytes',
    },
  });
}

export function handleScheme() {
  protocol.handle('orbit', (request) => {
    const url = new URL(request.url);
    const parts = decodeURIComponent(url.pathname).split('/').filter(Boolean);
    if (url.host === 'app') {
      if (parts[0] === 'vendor') return vendor[parts[1]] ? serveFile(vendor[parts[1]], request) : notFound();
      if (parts[0] !== 'renderer' && parts[0] !== 'core') return notFound();
      const file = inside(srcRoot, parts.join('/'));
      return file ? serveFile(file, request) : notFound();
    }
    if (url.host === 'media') {
      const folder = folderForToken(parts[0]);
      const file = folder && parts.length === 2 ? inside(folder, parts[1]) : null;
      return file ? serveFile(file, request) : notFound();
    }
    return notFound();
  });
}
