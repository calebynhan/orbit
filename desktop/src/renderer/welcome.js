// First-run guide: what Orbit is, the global shortcut, and how a recording works.
import { acceleratorFromEvent, displayString } from '../core/shortcut.js';

const $ = (id) => document.getElementById(id);
const state = await orbit.invoke('welcome:state');
let step = 0;
let listening = false;

function render() {
  for (const section of document.querySelectorAll('.step')) section.hidden = Number(section.dataset.step) !== step;
  document.querySelectorAll('.dots span').forEach((dot, i) => dot.classList.toggle('on', i === step));
  $('back').hidden = step === 0;
  $('later').hidden = step !== 2;
  $('next').textContent = ['Get Started', 'Continue', 'Start a Recording'][step];
  $('shortcut').textContent = listening ? 'Type a shortcut…' : state.shortcut;
  $('shortcut').classList.toggle('listening', listening);
  $('change').textContent = listening ? 'Cancel' : 'Change…';
  $('shortcut2').textContent = state.shortcut;
  $('waylandNote').hidden = !state.wayland;
  $('loginRow').hidden = !state.loginSupported;
  $('login').checked = state.openAtLogin;
  $('folder').textContent = state.recordingsFolder;
  $('platformNote').textContent = state.platform === 'linux'
    ? 'On Wayland, your desktop asks which screen to share each time you record.'
    : 'Orbit’s own windows, like the face cam and the stop button, are left out of the recording.';
}

async function stopListening() {
  listening = false;
  await orbit.invoke('welcome:set-shortcut', state.accelerator); // re-register the current one
  render();
}

$('change').onclick = async () => {
  if (listening) return stopListening();
  listening = true;
  $('shortcutError').textContent = '';
  await orbit.invoke('welcome:pause-shortcut'); // so pressing the current one doesn't open the bar
  render();
};

window.addEventListener('keydown', async (e) => {
  if (!listening) return;
  e.preventDefault();
  if (e.key === 'Escape' && !e.ctrlKey && !e.altKey && !e.metaKey) return stopListening();
  const accelerator = acceleratorFromEvent(e);
  if (!accelerator) {
    $('shortcut').textContent = displayString([e.ctrlKey && 'CommandOrControl', e.altKey && 'Alt', e.shiftKey && 'Shift', e.metaKey && 'Super'].filter(Boolean).join('+') || '…', state.platform);
    return;
  }
  const result = await orbit.invoke('welcome:set-shortcut', accelerator);
  if (result.ok) {
    state.accelerator = accelerator;
    state.shortcut = result.shortcut;
    listening = false;
    $('shortcutError').innerHTML = '<span class="ok">Saved.</span>';
  } else {
    $('shortcutError').textContent = result.error;
    $('shortcut').textContent = displayString(accelerator, state.platform);
  }
  render();
});

$('login').onchange = (e) => orbit.invoke('welcome:set-login', e.target.checked);
$('back').onclick = () => { step = Math.max(0, step - 1); render(); };
$('later').onclick = () => orbit.invoke('welcome:finish', false);
$('next').onclick = async () => {
  if (listening) await stopListening();
  if (step < 2) {
    step += 1;
    render();
  } else {
    orbit.invoke('welcome:finish', true);
  }
};

render();
