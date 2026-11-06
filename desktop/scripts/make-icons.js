// Draws Orbit's app and tray icons as PNGs (no image tools needed). Run with `npm run icons`.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'assets', 'icons');
fs.mkdirSync(out, { recursive: true });

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function png(size, pixel) {
  const raw = Buffer.alloc(size * (size * 4 + 1));
  const samples = 4; // 4×4 supersampling per pixel
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0;
    for (let x = 0; x < size; x++) {
      let r = 0, g = 0, b = 0, a = 0;
      for (let sy = 0; sy < samples; sy++) {
        for (let sx = 0; sx < samples; sx++) {
          const [pr, pg, pb, pa] = pixel((x + (sx + 0.5) / samples) / size, (y + (sy + 0.5) / samples) / size);
          r += pr * pa; g += pg * pa; b += pb * pa; a += pa;
        }
      }
      const n = samples * samples;
      const o = y * (size * 4 + 1) + 1 + x * 4;
      raw[o] = a ? Math.round(r / a) : 0;
      raw[o + 1] = a ? Math.round(g / a) : 0;
      raw[o + 2] = a ? Math.round(b / a) : 0;
      raw[o + 3] = Math.round((a / n) * 255);
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8; header[9] = 6; header[10] = 0; header[11] = 0; header[12] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

const red = [229, 72, 77];
const dist = (x, y) => Math.hypot(x - 0.5, y - 0.5);
function roundedSquare(x, y, inset, radius) {
  const qx = Math.max(Math.abs(x - 0.5) - (0.5 - inset - radius), 0);
  const qy = Math.max(Math.abs(y - 0.5) - (0.5 - inset - radius), 0);
  return Math.hypot(qx, qy) <= radius;
}

// App icon: a red dot inside a white ring, on a near-black rounded square.
const appIcon = (x, y) => {
  if (!roundedSquare(x, y, 0.06, 0.2)) return [0, 0, 0, 0];
  const d = dist(x, y);
  if (d <= 0.15) return [...red, 1];
  if (d >= 0.24 && d <= 0.3) return [255, 255, 255, 1];
  return [20, 20, 22, 1];
};

// Tray, idle: same mark, with a grey ring that reads on light and dark taskbars.
const trayIdle = (x, y) => {
  const d = dist(x, y);
  if (d <= 0.2) return [...red, 1];
  if (d >= 0.32 && d <= 0.45) return [140, 140, 146, 1];
  return [0, 0, 0, 0];
};

// Tray, recording: a red disc with a white stop square.
const trayRecording = (x, y) => {
  const d = dist(x, y);
  if (d > 0.46) return [0, 0, 0, 0];
  if (Math.abs(x - 0.5) <= 0.14 && Math.abs(y - 0.5) <= 0.14) return [255, 255, 255, 1];
  return [...red, 1];
};

const files = {
  'icon.png': [512, appIcon],
  'tray-idle.png': [32, trayIdle],
  'tray-idle@2x.png': [64, trayIdle],
  'tray-recording.png': [32, trayRecording],
  'tray-recording@2x.png': [64, trayRecording],
};
for (const [name, [size, draw]] of Object.entries(files)) {
  fs.writeFileSync(path.join(out, name), png(size, draw));
  console.log('wrote', name);
}
