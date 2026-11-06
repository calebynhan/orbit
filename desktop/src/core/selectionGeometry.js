// Math for the "Selected Portion" rectangle. A port of Sources/OrbitCore/SelectionGeometry.swift,
// but in Electron's screen space: global DIPs with a **top-left** origin (y grows downward).
// Rects are `{ x, y, width, height }`. Results snap to whole DIPs.

import { aspectUnits } from './captureFormat.js';

export const minimumSize = { width: 64, height: 64 };
export const handleTolerance = 8;
const defaultFraction = 0.6;

export const handles = ['topLeft', 'top', 'topRight', 'right', 'bottomRight', 'bottom', 'bottomLeft', 'left', 'body'];

const movesLeft = (h) => h === 'topLeft' || h === 'left' || h === 'bottomLeft';
const movesRight = (h) => h === 'topRight' || h === 'right' || h === 'bottomRight';
const movesTop = (h) => h === 'topLeft' || h === 'top' || h === 'topRight';
const movesBottom = (h) => h === 'bottomLeft' || h === 'bottom' || h === 'bottomRight';

const maxX = (r) => r.x + r.width;
const maxY = (r) => r.y + r.height;

export function rectFromPoints(start, end) {
  return {
    x: Math.min(start.x, end.x),
    y: Math.min(start.y, end.y),
    width: Math.abs(end.x - start.x),
    height: Math.abs(end.y - start.y),
  };
}

export function intersects(a, b) {
  return a.x < maxX(b) && b.x < maxX(a) && a.y < maxY(b) && b.y < maxY(a);
}

export function containsPoint(r, p) {
  return p.x >= r.x && p.x <= maxX(r) && p.y >= r.y && p.y <= maxY(r);
}

function snapped(r) {
  return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
}

export function defaultSelection(bounds) {
  const width = bounds.width * defaultFraction;
  const height = bounds.height * defaultFraction;
  return snapped({ x: bounds.x + (bounds.width - width) / 2, y: bounds.y + (bounds.height - height) / 2, width, height });
}

/** Fits `rect` inside `bounds` (shrinking if needed) and enforces the minimum size. */
export function clamped(rect, bounds) {
  const width = Math.min(Math.max(rect.width, minimumSize.width), bounds.width);
  const height = Math.min(Math.max(rect.height, minimumSize.height), bounds.height);
  return {
    x: Math.min(Math.max(rect.x, bounds.x), maxX(bounds) - width),
    y: Math.min(Math.max(rect.y, bounds.y), maxY(bounds) - height),
    width,
    height,
  };
}

/** The rect after dragging `handle` by `delta` ({ dx, dy }), kept inside `bounds`. */
export function resized(rect, handle, delta, bounds, aspect = 'freeform') {
  if (handle === 'body') {
    return constrained({ ...rect, x: rect.x + delta.dx, y: rect.y + delta.dy }, aspect, 'body', bounds);
  }
  let minX = rect.x;
  let right = maxX(rect);
  let top = rect.y;
  let bottom = maxY(rect);
  if (movesLeft(handle)) minX = Math.max(Math.min(minX + delta.dx, right - minimumSize.width), bounds.x);
  if (movesRight(handle)) right = Math.min(Math.max(right + delta.dx, minX + minimumSize.width), maxX(bounds));
  if (movesTop(handle)) top = Math.max(Math.min(top + delta.dy, bottom - minimumSize.height), bounds.y);
  if (movesBottom(handle)) bottom = Math.min(Math.max(bottom + delta.dy, top + minimumSize.height), maxY(bounds));
  return constrained({ x: minX, y: top, width: right - minX, height: bottom - top }, aspect, handle, bounds);
}

/**
 * Applies the aspect lock (keeping the edge/corner opposite `anchor` fixed), snaps to whole DIPs,
 * and keeps the rect inside `bounds`.
 */
export function constrained(rect, aspect, anchor, bounds) {
  const units = aspectUnits(aspect);
  if (!units) return clamped(snapped(rect), bounds);

  const heightDriven = anchor === 'top' || anchor === 'bottom';
  const requested = Math.floor(heightDriven ? rect.height / units.height : rect.width / units.width);
  const fewest = Math.ceil(Math.max(minimumSize.width / units.width, minimumSize.height / units.height));
  const most = Math.floor(Math.min(bounds.width / units.width, bounds.height / units.height));
  const count = Math.min(Math.max(requested, fewest), most);
  const width = count * units.width;
  const height = count * units.height;

  let x;
  if (movesLeft(anchor)) x = maxX(rect) - width;
  else if (movesRight(anchor)) x = rect.x;
  else x = rect.x + rect.width / 2 - width / 2;
  let y;
  if (movesTop(anchor)) y = maxY(rect) - height;
  else if (movesBottom(anchor)) y = rect.y;
  else y = rect.y + rect.height / 2 - height / 2;

  return {
    x: Math.min(Math.max(Math.round(x), bounds.x), maxX(bounds) - width),
    y: Math.min(Math.max(Math.round(y), bounds.y), maxY(bounds) - height),
    width,
    height,
  };
}

/** Which handle (if any) is under `point`. Corners win over edges; edges extend a few DIPs outside. */
export function handleAt(point, rect, tolerance = handleTolerance) {
  const outer = { x: rect.x - tolerance, y: rect.y - tolerance, width: rect.width + 2 * tolerance, height: rect.height + 2 * tolerance };
  if (!containsPoint(outer, point)) return null;
  const left = Math.abs(point.x - rect.x) <= tolerance;
  const right = Math.abs(point.x - maxX(rect)) <= tolerance;
  const top = Math.abs(point.y - rect.y) <= tolerance;
  const bottom = Math.abs(point.y - maxY(rect)) <= tolerance;
  if (left && top) return 'topLeft';
  if (right && top) return 'topRight';
  if (left && bottom) return 'bottomLeft';
  if (right && bottom) return 'bottomRight';
  if (left) return 'left';
  if (right) return 'right';
  if (top) return 'top';
  if (bottom) return 'bottom';
  return 'body';
}

export const handleCursor = {
  topLeft: 'nwse-resize',
  bottomRight: 'nwse-resize',
  topRight: 'nesw-resize',
  bottomLeft: 'nesw-resize',
  top: 'ns-resize',
  bottom: 'ns-resize',
  left: 'ew-resize',
  right: 'ew-resize',
  body: 'move',
};
