// Full-display overlay for "Selected Portion": dims everything outside a frame you can draw,
// move, and resize. Mirrors Sources/Orbit/UI/AreaSelection.swift. Works in global DIPs and
// draws in this window's local coordinates.
import * as geo from '../core/selectionGeometry.js';
import { pixelSize } from '../core/captureFormat.js';

const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');
let state = await orbit.invoke('area:state');
let selection = state.selection;
let drag = null;

const toGlobal = (e) => ({ x: e.clientX + state.display.x, y: e.clientY + state.display.y });

function draw() {
  const dpr = window.devicePixelRatio || 1;
  const w = window.innerWidth;
  const h = window.innerHeight;
  if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
  }
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);
  if (!selection) return;
  const r = { x: selection.x - state.display.x, y: selection.y - state.display.y, width: selection.width, height: selection.height };

  if (state.recording) {
    // Just outside the capture area so it never bleeds into the video edge.
    ctx.setLineDash([6, 4]);
    ctx.lineWidth = 2;
    ctx.strokeStyle = 'rgba(255, 59, 48, 0.85)';
    ctx.strokeRect(r.x - 2, r.y - 2, r.width + 4, r.height + 4);
    return;
  }

  ctx.fillStyle = 'rgba(0, 0, 0, 0.35)';
  ctx.beginPath();
  ctx.rect(0, 0, w, h);
  ctx.rect(r.x, r.y, r.width, r.height);
  ctx.fill('evenodd');

  ctx.setLineDash([5, 3]);
  ctx.lineWidth = 1;
  ctx.strokeStyle = '#fff';
  ctx.strokeRect(r.x + 0.5, r.y + 0.5, r.width - 1, r.height - 1);
  ctx.setLineDash([]);

  const xs = [r.x, r.x + r.width / 2, r.x + r.width];
  const ys = [r.y, r.y + r.height / 2, r.y + r.height];
  for (const x of xs) {
    for (const y of ys) {
      if (x === xs[1] && y === ys[1]) continue;
      ctx.beginPath();
      ctx.arc(x, y, 4.5, 0, Math.PI * 2);
      ctx.fillStyle = '#fff';
      ctx.fill();
      ctx.lineWidth = 0.5;
      ctx.strokeStyle = 'rgba(0, 0, 0, 0.4)';
      ctx.stroke();
    }
  }

  const px = pixelSize(state.resolution, selection, state.scaleFactor);
  const text = `${px.width} × ${px.height}`;
  ctx.font = '500 12px system-ui, "Segoe UI", Ubuntu, sans-serif';
  const tw = ctx.measureText(text).width;
  const box = { width: tw + 16, height: 22 };
  let by = r.y + r.height + 10;
  if (by + box.height > h - 4) by = r.y + r.height - box.height - 10; // no room below: inside
  const bx = Math.min(Math.max(r.x + r.width / 2 - box.width / 2, 4), w - box.width - 4);
  ctx.fillStyle = 'rgba(0, 0, 0, 0.6)';
  ctx.beginPath();
  ctx.roundRect(bx, by, box.width, box.height, 6);
  ctx.fill();
  ctx.fillStyle = '#fff';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, bx + 8, by + box.height / 2 + 0.5);
}

function commit(rect) {
  selection = rect;
  orbit.send('area:change', rect);
  draw();
}

canvas.addEventListener('pointerdown', (e) => {
  if (state.recording || e.button !== 0) return;
  canvas.setPointerCapture(e.pointerId);
  const p = toGlobal(e);
  const handle = selection ? geo.handleAt(p, selection) : null;
  drag = handle ? { handle, start: p, original: selection } : { handle: null, start: p };
});

canvas.addEventListener('pointermove', (e) => {
  const p = toGlobal(e);
  if (!drag) {
    const handle = selection && !state.recording ? geo.handleAt(p, selection) : null;
    canvas.style.cursor = handle ? geo.handleCursor[handle] : 'crosshair';
    return;
  }
  if (drag.handle) {
    commit(geo.resized(drag.original, drag.handle, { dx: p.x - drag.start.x, dy: p.y - drag.start.y }, state.display, state.aspect));
  } else {
    // Drawing a new frame: the corner being dragged is the anchor's opposite.
    const anchor = `${p.y < drag.start.y ? 'top' : 'bottom'}${p.x < drag.start.x ? 'Left' : 'Right'}`;
    commit(geo.constrained(geo.rectFromPoints(drag.start, p), state.aspect, anchor, state.display));
  }
});

canvas.addEventListener('pointerup', () => {
  if (drag) orbit.send('area:done');
  drag = null;
});

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') orbit.send('area:cancel');
  else if (e.key === 'Enter') orbit.send('area:record');
});

orbit.on('area:state', (next) => {
  state = next;
  selection = next.selection;
  draw();
});
window.addEventListener('resize', draw);
draw();
