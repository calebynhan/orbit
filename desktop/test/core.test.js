// Ports of Tests/OrbitCoreTests, so both apps agree on the timeline, geometry, and project file.
import test from 'node:test';
import assert from 'node:assert/strict';

import { BubbleTrackRecorder, bubbleState, makeTrack, trackState, alignTrack } from '../src/core/bubbleTrack.js';
import { computePlacement, cameraOffset } from '../src/core/cameraPlacement.js';
import { pixelSize } from '../src/core/captureFormat.js';
import * as sel from '../src/core/selectionGeometry.js';
import * as geo from '../src/core/overlayGeometry.js';
import { bubbleStyle, colorFromHex, hexColor, maxOutlineWidth, rgba } from '../src/core/bubbleStyle.js';
import { acceleratorFromEvent, displayString, validationProblem } from '../src/core/shortcut.js';

const near = (actual, expected, eps = 1e-9) => assert.ok(Math.abs(actual - expected) < eps, `${actual} ≉ ${expected}`);

// MARK: Bubble track

const a = bubbleState(0.1, 0.1, 0.2);
const b = bubbleState(0.5, 0.9, 0.4);

test('empty track has no state', () => assert.equal(trackState(makeTrack(), 1), null));

test('clamps before first and after last keyframe', () => {
  const track = makeTrack([{ time: 1, state: a }, { time: 2, state: b }]);
  assert.deepEqual(trackState(track, 0), a);
  assert.deepEqual(trackState(track, 5), b);
});

test('interpolates linearly between keyframes', () => {
  const mid = trackState(makeTrack([{ time: 0, state: a }, { time: 2, state: b }]), 1);
  near(mid.center.x, 0.3);
  near(mid.center.y, 0.5);
  near(mid.diameter, 0.3);
});

test('keyframes are sorted', () => {
  assert.deepEqual(makeTrack([{ time: 2, state: b }, { time: 0, state: a }]).keyframes.map((k) => k.time), [0, 2]);
});

test('many keyframes use the right segment', () => {
  const frames = Array.from({ length: 11 }, (_, i) => ({ time: i, state: bubbleState(i / 10, 0, 0.2) }));
  near(trackState(makeTrack(frames), 7.5).center.x, 0.75);
});

test('recorder: unchanged samples add nothing, a move after a hold inserts a hold keyframe', () => {
  const c = bubbleState(0.6, 0.6, 0.2);
  const recorder = new BubbleTrackRecorder().record(a, 0).record(a, 1).record(a, 5).record(c, 5.1);
  assert.deepEqual(recorder.keyframes.map((k) => k.time), [0, 5, 5.1]);
  assert.deepEqual(trackState(makeTrack(recorder.keyframes), 4), a);
});

test('recorder: finished appends the final hold', () => {
  const track = new BubbleTrackRecorder().record(a, 0).record(a, 3).finished();
  assert.deepEqual(track.keyframes.at(-1), { time: 3, state: a });
});

test('alignTrack re-bases times and collapses samples from before the video started', () => {
  const track = makeTrack([{ time: 100, state: a }, { time: 100.5, state: b }, { time: 102, state: a }]);
  const aligned = alignTrack(track, 100.8);
  assert.deepEqual(aligned.keyframes.map((k) => Math.round(k.time * 10) / 10), [0, 1.2]);
  assert.deepEqual(aligned.keyframes[0].state, b);
});

// MARK: Camera placement

test('camera placement', () => {
  assert.deepEqual(computePlacement(0.25, 10, 10), { sourceStart: 0, insertAt: 0.25, duration: 9.75 });
  assert.deepEqual(computePlacement(-0.5, 10, 20), { sourceStart: 0.5, insertAt: 0, duration: 9.5 });
  assert.deepEqual(computePlacement(2, 30, 10), { sourceStart: 0, insertAt: 2, duration: 8 });
  assert.equal(computePlacement(12, 5, 10), null);
  assert.equal(computePlacement(-6, 5, 10), null);
  near(cameraOffset(100.3, 100.1), 0.2);
});

// MARK: Capture format

test('pixel sizes', () => {
  assert.deepEqual(pixelSize('p1080', { width: 640, height: 360 }, 2), { width: 1920, height: 1080 });
  assert.deepEqual(pixelSize('p1080', { width: 1512, height: 982 }, 2), { width: 1662, height: 1080 });
  assert.deepEqual(pixelSize('p1080', { width: 360, height: 640 }, 2), { width: 1080, height: 1920 });
  assert.deepEqual(pixelSize('native', { width: 301, height: 200 }, 2), { width: 602, height: 400 });
  assert.deepEqual(pixelSize('native', { width: 1366, height: 768 }, 1.25), { width: 1708, height: 960 });
  assert.deepEqual(pixelSize('p720', { width: 1920, height: 1080 }, 1), { width: 1280, height: 720 });
  assert.deepEqual(pixelSize('p1080', { width: 0, height: 0 }, 2), { width: 2, height: 2 });
});

// MARK: Selection geometry (top-left origin)

const display = { x: 200, y: 100, width: 1000, height: 600 };

test('rect from two points is standardized', () => {
  assert.deepEqual(sel.rectFromPoints({ x: 50, y: 80 }, { x: 10, y: 20 }), { x: 10, y: 20, width: 40, height: 60 });
});

test('default selection is centered inside bounds', () => {
  const r = sel.defaultSelection(display);
  near(r.x + r.width / 2, 700, 1);
  near(r.y + r.height / 2, 400, 1);
});

test('clamp moves back inside, shrinks oversize, enforces minimum', () => {
  assert.deepEqual(sel.clamped({ x: 1100, y: 50, width: 300, height: 200 }, display), { x: 900, y: 100, width: 300, height: 200 });
  assert.deepEqual(sel.clamped({ x: 0, y: 0, width: 5000, height: 5000 }, display), display);
  const tiny = sel.clamped({ x: 500, y: 300, width: 2, height: 2 }, display);
  assert.deepEqual([tiny.width, tiny.height], [64, 64]);
});

test('moving the body translates and stays in bounds', () => {
  const start = { x: 300, y: 200, width: 200, height: 100 };
  assert.deepEqual(sel.resized(start, 'body', { dx: 50, dy: -20 }, display), { x: 350, y: 180, width: 200, height: 100 });
  assert.deepEqual(sel.resized(start, 'body', { dx: 5000, dy: 0 }, display), { x: 1000, y: 200, width: 200, height: 100 });
});

test('corner handles move only their edges (y grows downward)', () => {
  const start = { x: 300, y: 200, width: 200, height: 100 };
  assert.deepEqual(sel.resized(start, 'topRight', { dx: 40, dy: -30 }, display), { x: 300, y: 170, width: 240, height: 130 });
  assert.deepEqual(sel.resized(start, 'bottomLeft', { dx: -40, dy: 30 }, display), { x: 260, y: 200, width: 240, height: 130 });
});

test('edge handles change one dimension', () => {
  const start = { x: 300, y: 200, width: 200, height: 100 };
  assert.deepEqual(sel.resized(start, 'left', { dx: 20, dy: 999 }, display), { x: 320, y: 200, width: 180, height: 100 });
  assert.deepEqual(sel.resized(start, 'top', { dx: 999, dy: 10 }, display), { x: 300, y: 210, width: 200, height: 90 });
});

test('resize never goes below minimum or outside bounds', () => {
  const start = { x: 300, y: 200, width: 200, height: 100 };
  const collapsed = sel.resized(start, 'right', { dx: -1000, dy: 0 }, display);
  assert.equal(collapsed.x, 300);
  assert.equal(collapsed.width, 64);
  const grown = sel.resized(start, 'topLeft', { dx: -5000, dy: -5000 }, display);
  assert.deepEqual([grown.x, grown.y, grown.x + grown.width, grown.y + grown.height], [200, 100, 500, 300]);
});

test('16:9 lock snaps to exact whole-DIP sizes', () => {
  const r = sel.constrained({ x: 300, y: 200, width: 333, height: 150 }, 'widescreen', 'body', display);
  assert.equal(r.width * 9, r.height * 16);
  assert.ok([r.x, r.y, r.width, r.height].every(Number.isInteger));
});

test('16:9 lock keeps the opposite corner anchored', () => {
  const start = { x: 300, y: 200, width: 320, height: 180 };
  // Dragging the top-right corner keeps the bottom-left corner (300, 380) in place.
  assert.deepEqual(sel.resized(start, 'topRight', { dx: 160, dy: 0 }, display, 'widescreen'), { x: 300, y: 110, width: 480, height: 270 });
  const fromTop = sel.resized(start, 'top', { dx: 0, dy: -90 }, display, 'widescreen');
  assert.deepEqual([fromTop.width, fromTop.height, fromTop.y + fromTop.height], [480, 270, 380]);
});

test('16:9 lock fits small bounds; freeform only snaps', () => {
  const bounds = { x: 0, y: 0, width: 1000, height: 300 };
  const r = sel.constrained(bounds, 'widescreen', 'body', bounds);
  assert.ok(r.x >= 0 && r.y >= 0 && r.x + r.width <= 1000 && r.y + r.height <= 300);
  assert.equal(r.width * 9, r.height * 16);
  assert.deepEqual(sel.constrained({ x: 300.4, y: 200.6, width: 333.3, height: 150.2 }, 'freeform', 'body', display), { x: 300, y: 201, width: 333, height: 150 });
});

test('hit testing finds handles, body, and outside', () => {
  const r = { x: 100, y: 100, width: 200, height: 100 };
  assert.equal(sel.handleAt({ x: 102, y: 102 }, r), 'topLeft');
  assert.equal(sel.handleAt({ x: 300, y: 200 }, r), 'bottomRight');
  assert.equal(sel.handleAt({ x: 200, y: 100 }, r), 'top');
  assert.equal(sel.handleAt({ x: 99, y: 150 }, r), 'left');
  assert.equal(sel.handleAt({ x: 200, y: 150 }, r), 'body');
  assert.equal(sel.handleAt({ x: 10, y: 10 }, r), null);
});

// MARK: Overlay geometry

test('state from window bounds is normalized to the area, top-left origin', () => {
  const area = { x: 100, y: 50, width: 1000, height: 500 };
  const s = geo.stateFromWindow({ x: 250, y: 100, width: 100, height: 100 }, area);
  near(s.center.x, 0.2);
  near(s.center.y, 0.2);
  near(s.diameter, 0.2);
  const back = geo.rectForState(s, area);
  near(back.x, 250);
  near(back.y, 100);
  near(back.width, 100);
});

test('rect for state inside a video rect; center inverts it', () => {
  const video = { x: 10, y: 20, width: 400, height: 200 };
  assert.deepEqual(geo.rectForState(bubbleState(0.5, 0.5, 0.2), video), { x: 190, y: 100, width: 40, height: 40 });
  assert.deepEqual(geo.normalizedCenter({ x: 110, y: 70 }, video), { x: 0.25, y: 0.25 });
});

test('aspect fit and square crop', () => {
  assert.deepEqual(geo.aspectFitRect({ width: 1600, height: 900 }, { x: 0, y: 0, width: 800, height: 800 }), { x: 0, y: 175, width: 800, height: 450 });
  assert.deepEqual(geo.aspectFitRect({ width: 0, height: 0 }, { x: 0, y: 0, width: 800, height: 800 }), { x: 0, y: 0, width: 0, height: 0 });
  assert.deepEqual(geo.centeredSquareCrop({ width: 1920, height: 1080 }), { x: 420, y: 0, width: 1080, height: 1080 });
  assert.deepEqual(geo.centeredSquareCrop({ width: 1080, height: 1920 }), { x: 0, y: 420, width: 1080, height: 1080 });
});

test('clamp keeps the bubble inside and limits its size', () => {
  const c = geo.clampState(bubbleState(-1, 2, 0.2), 2);
  near(c.center.x, 0.05);
  near(c.center.y, 0.9);
  assert.equal(geo.clampState(bubbleState(0.5, 0.5, 0.001), 1).diameter, geo.minDiameter);
  assert.equal(geo.clampState(bubbleState(0.5, 0.5, 5), 1).diameter, geo.maxDiameter);
});

// MARK: Style

test('style clamps outline width and colour components', () => {
  assert.equal(bubbleStyle('square', 1, rgba(1, 1, 1)).outlineWidth, maxOutlineWidth);
  assert.equal(bubbleStyle('blob', 0.01).shape, 'circle');
  assert.deepEqual(rgba(2, -1, 0.5), { red: 1, green: 0, blue: 0.5, alpha: 1 });
  assert.equal(hexColor(colorFromHex('#ff8000')), '#ff8000');
});

// MARK: Shortcut

test('accelerators from key events', () => {
  assert.equal(acceleratorFromEvent({ code: 'Digit5', key: '%', ctrlKey: true, shiftKey: true }), 'CommandOrControl+Shift+5');
  assert.equal(acceleratorFromEvent({ code: 'KeyR', key: 'r', altKey: true }), 'Alt+R');
  assert.equal(acceleratorFromEvent({ code: 'ShiftLeft', key: 'Shift', shiftKey: true }), null);
  assert.equal(validationProblem('CommandOrControl+Shift+5'), null);
  assert.equal(validationProblem('F9'), null);
  assert.notEqual(validationProblem('Shift+R'), null);
  assert.notEqual(validationProblem('R'), null);
  assert.equal(displayString('CommandOrControl+Shift+5', 'win32'), 'Ctrl + Shift + 5');
  assert.equal(displayString('Super+Alt+R', 'linux'), 'Super + Alt + R');
});
