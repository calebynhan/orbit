// The recording project file, `project.json`. Mirrors Sources/OrbitCore/RecordingProject.swift and
// reads and writes exactly the JSON the Mac app does, so a recording folder opens in either app.
//
// Swift's encoder writes CGPoint as `[x, y]`, dates as ISO 8601 without fractional seconds, and
// leaves nil optionals out. Internally points are `{ x, y }`.

import { bubbleStyle, defaultStyle } from './bubbleStyle.js';
import { makeTrack, trackState } from './bubbleTrack.js';

export const fileName = 'project.json';
export const currentVersion = 1;
export const defaultDiameter = 0.24;

export const Placement = Object.freeze({ followRecording: 'followRecording', fixed: 'fixed' });

export const defaultOverlay = Object.freeze({
  visible: true,
  placement: Placement.followRecording,
  fixedCenter: { x: 0.1, y: 0.82 },
  diameterOverride: null,
  mirrored: true,
  style: defaultStyle,
});

/** Resolved bubble state at a point in the video, or null when hidden. */
export function overlayState(overlay, time, track) {
  if (!overlay.visible) return null;
  const recorded = trackState(track, time);
  const center = (overlay.placement === Placement.followRecording ? recorded?.center : null) ?? overlay.fixedCenter;
  const diameter = overlay.diameterOverride ?? recorded?.diameter ?? defaultDiameter;
  return { center, diameter };
}

export function makeProject({ createdAt = new Date(), screenFile, camera = null, overlay = defaultOverlay, bubbleTrack = makeTrack(), framesPerSecond = null }) {
  return { version: currentVersion, createdAt, screenFile, camera, overlay, bubbleTrack, framesPerSecond };
}

// MARK: Decoding

const point = (value, name) => {
  if (Array.isArray(value) && value.length === 2) return { x: Number(value[0]), y: Number(value[1]) };
  if (value && typeof value === 'object' && 'x' in value && 'y' in value) return { x: Number(value.x), y: Number(value.y) };
  throw new Error(`${name} isn’t a point`);
};

const required = (object, key) => {
  if (object == null || !(key in object)) throw new Error(`missing “${key}”`);
  return object[key];
};

function decodeState(raw) {
  return { center: point(required(raw, 'center'), 'center'), diameter: Number(required(raw, 'diameter')) };
}

function decodeOverlay(raw) {
  const placement = required(raw, 'placement');
  if (!Object.values(Placement).includes(placement)) throw new Error(`unknown placement “${placement}”`);
  const style = raw.style ? bubbleStyle(raw.style.shape, raw.style.outlineWidth, raw.style.outlineColor) : defaultStyle;
  return {
    visible: Boolean(required(raw, 'visible')),
    placement,
    fixedCenter: point(required(raw, 'fixedCenter'), 'fixedCenter'),
    diameterOverride: raw.diameterOverride ?? null,
    mirrored: Boolean(required(raw, 'mirrored')),
    style,
  };
}

/** Parses `project.json` text. Throws with a readable reason when it isn't a project. */
export function decodeProject(text) {
  const raw = JSON.parse(text);
  const camera = raw.camera
    ? { file: String(required(raw.camera, 'file')), offset: Number(required(raw.camera, 'offset')), includeAudio: Boolean(required(raw.camera, 'includeAudio')) }
    : null;
  const createdAt = new Date(required(raw, 'createdAt'));
  if (Number.isNaN(createdAt.getTime())) throw new Error('createdAt isn’t a date');
  return {
    version: Number(required(raw, 'version')),
    createdAt,
    screenFile: String(required(raw, 'screenFile')),
    camera,
    overlay: decodeOverlay(required(raw, 'overlay')),
    bubbleTrack: makeTrack(required(required(raw, 'bubbleTrack'), 'keyframes').map((k) => ({ time: Number(required(k, 'time')), state: decodeState(required(k, 'state')) }))),
    framesPerSecond: raw.framesPerSecond ?? null,
  };
}

// MARK: Encoding

const encodePoint = (p) => [p.x, p.y];

/** Swift's `.iso8601` strategy: whole seconds, UTC, `Z`. */
export function iso8601(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function sortedKeys(value) {
  if (Array.isArray(value)) return value.map(sortedKeys);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((k) => [k, sortedKeys(value[k])]));
  }
  return value;
}

function withoutNulls(object) {
  return Object.fromEntries(Object.entries(object).filter(([, v]) => v !== null && v !== undefined));
}

export function encodeProject(project) {
  const o = project.overlay;
  const json = withoutNulls({
    version: project.version ?? currentVersion,
    createdAt: iso8601(project.createdAt),
    screenFile: project.screenFile,
    camera: project.camera ? { file: project.camera.file, offset: project.camera.offset, includeAudio: project.camera.includeAudio } : null,
    overlay: withoutNulls({
      visible: o.visible,
      placement: o.placement,
      fixedCenter: encodePoint(o.fixedCenter),
      diameterOverride: o.diameterOverride,
      mirrored: o.mirrored,
      style: { shape: o.style.shape, outlineWidth: o.style.outlineWidth, outlineColor: o.style.outlineColor },
    }),
    bubbleTrack: {
      keyframes: project.bubbleTrack.keyframes.map((k) => ({
        time: k.time,
        state: { center: encodePoint(k.state.center), diameter: k.state.diameter },
      })),
    },
    framesPerSecond: project.framesPerSecond,
  });
  return JSON.stringify(sortedKeys(json), null, 2) + '\n';
}

/** "Recording 2026-11-06 at 14.03.27", in local time, like the Mac app. */
export function folderName(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `Recording ${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} at ${pad(date.getHours())}.${pad(date.getMinutes())}.${pad(date.getSeconds())}`;
}
