// The capture bar, modeled on the Mac app's ⇧⌘5-style toolbar.
import { icon } from './icons.js';

const $ = (id) => document.getElementById(id);
let state = null;

const tool = (el, iconName, label) => {
  el.innerHTML = icon(iconName) + (label ? `<span>${label}</span>` : '');
};

function render() {
  if (!state) return;
  tool($('close'), 'close');
  tool($('entireScreen'), 'screen', 'Entire Screen');
  tool($('selection'), 'area', 'Selected Portion');
  tool($('camera'), state.cameraOn ? 'camera' : 'cameraOff', 'Face Cam');
  tool($('mic'), state.microphoneOn ? 'mic' : 'micOff', 'Mic');
  tool($('systemAudio'), state.systemAudioOn ? 'speaker' : 'speakerOff', 'System Audio');
  $('micMenu').innerHTML = icon('chevron');
  $('entireScreen').classList.toggle('on', state.captureMode === 'entireScreen');
  $('selection').classList.toggle('on', state.captureMode === 'selection');
  $('camera').classList.toggle('on', state.cameraOn);
  $('mic').classList.toggle('on', state.microphoneOn);
  $('systemAudio').classList.toggle('on', state.systemAudioOn);
  $('systemAudio').hidden = !state.systemAudioSupported;
  $('options').textContent = `${state.resolutionLabel} · ${state.framesPerSecond}fps`;
  $('record').disabled = state.phase !== 'choosing';

  const select = $('display');
  select.hidden = state.displays.length < 2;
  select.innerHTML = state.displays.map((d) => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
  select.value = String(state.displayId);
  fit();
}

function escapeHtml(text) {
  return text.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

function fit() {
  const bar = $('bar');
  orbit.send('toolbar:fit', bar.offsetWidth + 12, bar.offsetHeight + 12);
}

async function microphones() {
  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    const inputs = devices.filter((d) => d.kind === 'audioinput' && d.deviceId !== 'communications');
    // Put the system default first, like the Mac app.
    inputs.sort((a, b) => (b.deviceId === 'default') - (a.deviceId === 'default'));
    return inputs.map((d, i) => ({ id: d.deviceId, name: d.label || `Microphone ${i + 1}` }));
  } catch {
    return [];
  }
}

const set = (key, value) => orbit.send('toolbar:set', key, value);

$('close').onclick = () => orbit.send('toolbar:cancel');
$('entireScreen').onclick = () => set('captureMode', 'entireScreen');
$('selection').onclick = () => set('captureMode', 'selection');
$('display').onchange = (e) => set('displayId', Number(e.target.value));
$('camera').onclick = () => set('cameraOn', !state.cameraOn);
$('mic').onclick = () => set('microphoneOn', !state.microphoneOn);
$('micMenu').onclick = async () => orbit.send('toolbar:microphones', await microphones());
$('systemAudio').onclick = () => set('systemAudioOn', !state.systemAudioOn);
$('options').onclick = () => orbit.send('toolbar:options');
$('record').onclick = () => orbit.send('toolbar:record');

window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') orbit.send('toolbar:cancel');
  else if (e.key === 'Enter' && document.activeElement?.tagName !== 'SELECT') orbit.send('toolbar:record');
});

orbit.on('toolbar:state', (next) => {
  state = next;
  render();
});
state = await orbit.invoke('toolbar:state');
render();
