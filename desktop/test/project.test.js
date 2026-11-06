import test from 'node:test';
import assert from 'node:assert/strict';

import { decodeProject, encodeProject, makeProject, defaultOverlay, overlayState, folderName, iso8601 } from '../src/core/project.js';
import { makeTrack, bubbleState } from '../src/core/bubbleTrack.js';

// Written by the Mac app's JSONEncoder (.prettyPrinted, .sortedKeys, .iso8601).
const fromMac = `{
  "bubbleTrack" : {
    "keyframes" : [
      {
        "state" : {
          "center" : [
            0.25,
            0.75
          ],
          "diameter" : 0.2
        },
        "time" : 0
      },
      {
        "state" : {
          "center" : [
            0.5,
            0.5
          ],
          "diameter" : 0.3
        },
        "time" : 2.5
      }
    ]
  },
  "camera" : {
    "file" : "camera.mov",
    "includeAudio" : false,
    "offset" : 0.12
  },
  "createdAt" : "2026-10-30T14:00:00Z",
  "framesPerSecond" : 60,
  "overlay" : {
    "fixedCenter" : [
      0.1,
      0.82
    ],
    "mirrored" : true,
    "placement" : "followRecording",
    "style" : {
      "outlineColor" : {
        "alpha" : 1,
        "blue" : 1,
        "green" : 1,
        "red" : 1
      },
      "outlineWidth" : 0.035,
      "shape" : "rounded"
    },
    "visible" : true
  },
  "screenFile" : "screen.mov",
  "version" : 1
}`;

test('reads a project written by the Mac app', () => {
  const p = decodeProject(fromMac);
  assert.equal(p.screenFile, 'screen.mov');
  assert.deepEqual(p.camera, { file: 'camera.mov', offset: 0.12, includeAudio: false });
  assert.equal(p.createdAt.toISOString(), '2026-10-30T14:00:00.000Z');
  assert.equal(p.framesPerSecond, 60);
  assert.deepEqual(p.overlay.fixedCenter, { x: 0.1, y: 0.82 });
  assert.equal(p.overlay.diameterOverride, null);
  assert.equal(p.overlay.style.shape, 'rounded');
  assert.deepEqual(p.bubbleTrack.keyframes[1], { time: 2.5, state: bubbleState(0.5, 0.5, 0.3) });
});

test('writes JSON the Mac app reads: point arrays, whole-second dates, no nulls, sorted keys', () => {
  const p = decodeProject(fromMac);
  const json = JSON.parse(encodeProject(p));
  assert.deepEqual(json.overlay.fixedCenter, [0.1, 0.82]);
  assert.deepEqual(json.bubbleTrack.keyframes[0].state.center, [0.25, 0.75]);
  assert.equal(json.createdAt, '2026-10-30T14:00:00Z');
  assert.ok(!('diameterOverride' in json.overlay));
  assert.deepEqual(Object.keys(json), [...Object.keys(json)].sort());
  assert.deepEqual(decodeProject(encodeProject(p)), p);
});

test('round trip of a new project', () => {
  const p = makeProject({
    createdAt: new Date('2026-11-06T09:30:00.456Z'),
    screenFile: 'screen.mp4',
    camera: { file: 'camera.mp4', offset: -0.04, includeAudio: false },
    overlay: { ...defaultOverlay, diameterOverride: 0.3 },
    bubbleTrack: makeTrack([{ time: 0, state: bubbleState(0.5, 0.5, 0.2) }]),
    framesPerSecond: 30,
  });
  const back = decodeProject(encodeProject(p));
  assert.equal(iso8601(back.createdAt), '2026-11-06T09:30:00Z');
  assert.deepEqual({ ...back, createdAt: null }, { ...p, createdAt: null });
});

test('older projects without style or frame rate still load', () => {
  const legacy = `{"version":1,"createdAt":"2026-10-30T14:00:00Z","screenFile":"screen.mov",
    "overlay":{"visible":true,"placement":"fixed","fixedCenter":[0.1,0.8],"mirrored":true},
    "bubbleTrack":{"keyframes":[]}}`;
  const p = decodeProject(legacy);
  assert.equal(p.framesPerSecond, null);
  assert.equal(p.camera, null);
  assert.equal(p.overlay.style.shape, 'circle');
});

test('a file that isn’t a project fails with a reason', () => {
  assert.throws(() => decodeProject('{"hello":1}'), /missing/);
});

test('overlay state: hidden, follow, fixed, override', () => {
  const recorded = bubbleState(0.7, 0.3, 0.25);
  const track = makeTrack([{ time: 0, state: recorded }]);
  assert.equal(overlayState({ ...defaultOverlay, visible: false }, 0, track), null);
  assert.deepEqual(overlayState(defaultOverlay, 1, track), recorded);
  assert.deepEqual(overlayState(defaultOverlay, 1, makeTrack()).center, defaultOverlay.fixedCenter);
  const fixed = overlayState({ ...defaultOverlay, placement: 'fixed', fixedCenter: { x: 0.2, y: 0.8 } }, 0, track);
  assert.deepEqual(fixed, bubbleState(0.2, 0.8, 0.25));
  assert.equal(overlayState({ ...defaultOverlay, diameterOverride: 0.4 }, 0, track).diameter, 0.4);
});

test('folder name is filesystem safe', () => {
  const name = folderName(new Date(2026, 0, 2, 3, 4, 5));
  assert.equal(name, 'Recording 2026-01-02 at 03.04.05');
  assert.ok(!/[:\\/*?"<>|]/.test(name));
});
