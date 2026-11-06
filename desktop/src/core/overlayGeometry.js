// Conversions between the spaces the bubble lives in. Mirrors Sources/OrbitCore/OverlayGeometry.swift.
// Everything here is top-left origin: Electron screen DIPs while recording, normalized
// BubbleState in the project, and canvas / CSS pixels in the editor and exporter.

import { bubbleState } from './bubbleTrack.js';

export const minDiameter = 0.06;
export const maxDiameter = 0.8;

/** Normalizes a bubble window's bounds against the recorded area. */
export function stateFromWindow(windowBounds, area) {
  if (!(area.width > 0 && area.height > 0)) return bubbleState(0.5, 0.5, 0.2);
  return bubbleState(
    (windowBounds.x + windowBounds.width / 2 - area.x) / area.width,
    (windowBounds.y + windowBounds.height / 2 - area.y) / area.height,
    windowBounds.height / area.height,
  );
}

/** The square a state occupies inside `frame` (`{ x, y, width, height }` in any top-left space). */
export function rectForState(state, frame) {
  const size = state.diameter * frame.height;
  const midX = frame.x + state.center.x * frame.width;
  const midY = frame.y + state.center.y * frame.height;
  return { x: midX - size / 2, y: midY - size / 2, width: size, height: size };
}

export function normalizedCenter(point, frame) {
  if (!(frame.width > 0 && frame.height > 0)) return { x: 0.5, y: 0.5 };
  return { x: (point.x - frame.x) / frame.width, y: (point.y - frame.y) / frame.height };
}

export function aspectFitRect(content, bounds) {
  if (!(content.width > 0 && content.height > 0 && bounds.width > 0 && bounds.height > 0)) {
    return { x: 0, y: 0, width: 0, height: 0 };
  }
  const scale = Math.min(bounds.width / content.width, bounds.height / content.height);
  const width = content.width * scale;
  const height = content.height * scale;
  return { x: bounds.x + (bounds.width - width) / 2, y: bounds.y + (bounds.height - height) / 2, width, height };
}

/** The largest centered square inside a frame — what an aspect-fill crop of the camera shows. */
export function centeredSquareCrop(size) {
  const side = Math.min(size.width, size.height);
  return { x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side };
}

/** Keeps the whole bubble inside the frame. `aspect` is width / height of the frame. */
export function clampState(state, aspect) {
  const diameter = Math.min(Math.max(state.diameter, minDiameter), maxDiameter);
  const radiusY = diameter / 2;
  const radiusX = aspect > 0 ? radiusY / aspect : radiusY;
  return bubbleState(
    Math.min(Math.max(state.center.x, radiusX), 1 - radiusX),
    Math.min(Math.max(state.center.y, radiusY), 1 - radiusY),
    diameter,
  );
}
