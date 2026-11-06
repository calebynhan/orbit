// Small JSON settings store in the user-data folder (the Mac app uses UserDefaults).
import { app } from 'electron';
import fs from 'node:fs';
import path from 'node:path';

import { defaultStyle, bubbleStyle } from '../core/bubbleStyle.js';
import { defaultAccelerator } from '../core/shortcut.js';
import { resolutions, aspects, frameRates } from '../core/captureFormat.js';

const defaults = {
  cameraOn: true,
  microphoneOn: true,
  microphoneId: null,
  systemAudioOn: false,
  captureMode: 'entireScreen',
  resolution: 'p1080',
  aspect: 'widescreen',
  framesPerSecond: 60,
  selection: null,
  bubbleStyle: defaultStyle,
  accelerator: defaultAccelerator,
  welcomeShown: false,
};

const validators = {
  captureMode: (v) => v === 'entireScreen' || v === 'selection',
  resolution: (v) => resolutions.includes(v),
  aspect: (v) => aspects.includes(v),
  framesPerSecond: (v) => frameRates.includes(v),
};

let values = null;
let file = null;

function load() {
  if (values) return values;
  file = path.join(app.getPath('userData'), 'settings.json');
  let stored = {};
  try {
    stored = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    // First run, or an unreadable file: start from defaults.
  }
  values = { ...defaults };
  for (const [key, value] of Object.entries(stored)) {
    if (!(key in defaults)) continue;
    if (validators[key] && !validators[key](value)) continue;
    values[key] = value;
  }
  values.bubbleStyle = bubbleStyle(values.bubbleStyle?.shape, values.bubbleStyle?.outlineWidth, values.bubbleStyle?.outlineColor);
  return values;
}

export function get(key) {
  return load()[key];
}

export function set(key, value) {
  load();
  if (!(key in defaults)) throw new Error(`Unknown setting ${key}`);
  if (validators[key] && !validators[key](value)) return false;
  values[key] = value;
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(`${file}.tmp`, JSON.stringify(values, null, 2));
    fs.renameSync(`${file}.tmp`, file);
  } catch (error) {
    console.error('Couldn’t save settings', error);
  }
  return true;
}

export function all() {
  return { ...load() };
}
