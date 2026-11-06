// One recording's editor: preview with a draggable bubble, face-cam options, re-record or import a
// face cam, delete, and export. Mirrors Sources/Orbit/Editor/EditorModel.swift and EditorView.swift.
import { MediaStreamVideoTrackSource, MediaStreamAudioTrackSource, QUALITY_HIGH } from '../vendor/mediabunny.mjs';
import { icon } from './icons.js';
import { exportVideo } from './exporter.js';
import { fileOutput, videoCodecFor, audioCodec, firstMediaTime, mediaUrl, describeMediaError, sleep } from './media.js';
import { decodeProject, encodeProject, overlayState, defaultDiameter, Placement } from '../core/project.js';
import { trackState } from '../core/bubbleTrack.js';
import { aspectFitRect, clampState, normalizedCenter, rectForState } from '../core/overlayGeometry.js';
import { cornerRadiusFraction, cssColor, hexColor, colorFromHex, bubbleStyle } from '../core/bubbleStyle.js';

const $ = (id) => document.getElementById(id);
const screenVideo = $('screen');
const cameraVideo = $('camera');

const loaded = await orbit.invoke('editor:load');
const { token } = loaded;
document.title = loaded.name;
let project = decodeProject(loaded.project);

const ui = {
  hasCamera: false,
  cameraDuration: 0,
  duration: 0,
  renderSize: { width: 0, height: 0 },
  videoRect: { x: 0, y: 0, width: 0, height: 0 },
  loading: true,
  error: null,
  scrubbing: false,
  dragging: null,
  exporting: null, // progress 0…1 while exporting
  take: null,
};

const overlay = () => project.overlay;
const hasRecordedPath = () => project.bubbleTrack.keyframes.length > 0;
const busy = () => ui.exporting !== null || ui.take !== null;

function currentDiameter() {
  return overlay().diameterOverride ?? trackState(project.bubbleTrack, screenVideo.currentTime)?.diameter ?? defaultDiameter;
}

function currentBubbleState() {
  if (!ui.hasCamera || !ui.renderSize.height) return null;
  const state = overlayState(overlay(), screenVideo.currentTime, project.bubbleTrack);
  return state ? clampState(state, ui.renderSize.width / ui.renderSize.height) : null;
}

// MARK: Loading

function waitForMetadata(video) {
  return new Promise((resolve, reject) => {
    if (video.readyState >= 1) return resolve();
    const done = () => { cleanup(); resolve(); };
    const fail = () => { cleanup(); reject(video.error ?? new Error('Couldn’t open the video.')); };
    const cleanup = () => { video.removeEventListener('loadedmetadata', done); video.removeEventListener('error', fail); };
    video.addEventListener('loadedmetadata', done);
    video.addEventListener('error', fail);
  });
}

async function load() {
  ui.loading = true;
  ui.error = null;
  render();
  const resumeAt = screenVideo.currentTime || 0;
  try {
    screenVideo.src = mediaUrl(token, project.screenFile);
    await waitForMetadata(screenVideo);
    if (!screenVideo.videoWidth) throw new Error('The screen recording has no video. It may not have finished saving.');
    ui.renderSize = { width: screenVideo.videoWidth, height: screenVideo.videoHeight };
    ui.duration = screenVideo.duration;
    screenVideo.currentTime = Math.min(resumeAt, ui.duration);
  } catch (error) {
    ui.error = `Couldn’t play “${project.screenFile}”. ${error.message ?? ''}`;
  }

  ui.hasCamera = false;
  cameraVideo.removeAttribute('src');
  if (project.camera && !ui.error) {
    try {
      cameraVideo.src = mediaUrl(token, project.camera.file);
      await waitForMetadata(cameraVideo);
      ui.cameraDuration = cameraVideo.duration;
      ui.hasCamera = cameraVideo.videoWidth > 0;
    } catch (error) {
      console.error('Camera clip failed to load', error);
    }
  }
  cameraVideo.muted = !project.camera?.includeAudio;
  ui.loading = false;
  render();
}

// MARK: Saving

async function save() {
  try {
    await orbit.invoke('editor:save', encodeProject(project));
  } catch (error) {
    orbit.invoke('editor:error', 'Couldn’t save', error.message);
  }
}

let saveTimer = null;
function apply(nextOverlay, { persist = true } = {}) {
  project = { ...project, overlay: nextOverlay };
  render();
  clearTimeout(saveTimer);
  if (persist) save();
}

// MARK: Preview

function layout() {
  const stage = $('stage').getBoundingClientRect();
  ui.videoRect = aspectFitRect(ui.renderSize, { x: 0, y: 0, width: stage.width, height: stage.height });
  Object.assign(screenVideo.style, {
    left: `${ui.videoRect.x}px`, top: `${ui.videoRect.y}px`, width: `${ui.videoRect.width}px`, height: `${ui.videoRect.height}px`,
  });
}

function cameraInRange() {
  if (!ui.hasCamera) return false;
  const t = screenVideo.currentTime - project.camera.offset;
  return t >= 0 && t < ui.cameraDuration;
}

function syncCamera() {
  if (!ui.hasCamera) return;
  const target = screenVideo.currentTime - project.camera.offset;
  if (!cameraInRange() || ui.take) {
    if (!cameraVideo.paused) cameraVideo.pause();
    return;
  }
  const drift = Math.abs(cameraVideo.currentTime - target);
  if (!screenVideo.paused) {
    if (cameraVideo.paused) {
      cameraVideo.currentTime = target;
      cameraVideo.play().catch(() => {});
    } else if (drift > 0.12) {
      cameraVideo.currentTime = target;
    }
  } else {
    if (!cameraVideo.paused) cameraVideo.pause();
    if (drift > 0.02 && !cameraVideo.seeking) cameraVideo.currentTime = target;
  }
}

function drawBubble() {
  const bubble = $('bubble');
  const handle = $('handle');
  const state = ui.take ? null : currentBubbleState();
  if (!state || ui.loading || ui.error) {
    bubble.hidden = true;
    handle.hidden = true;
    return;
  }
  const rect = rectForState(state, ui.videoRect);
  const style = overlay().style;
  const radius = (side) => `${side * cornerRadiusFraction(style.shape)}px`;
  handle.hidden = false;
  Object.assign(handle.style, { left: `${rect.x}px`, top: `${rect.y}px`, width: `${rect.width}px`, height: `${rect.height}px`, borderRadius: radius(rect.width) });

  bubble.hidden = !cameraInRange();
  if (bubble.hidden) return;
  const outline = rect.width * style.outlineWidth;
  const inner = rect.width - outline * 2;
  Object.assign(bubble.style, {
    left: `${rect.x}px`, top: `${rect.y}px`, width: `${rect.width}px`, height: `${rect.height}px`,
    borderRadius: radius(rect.width), background: outline > 0 ? cssColor(style.outlineColor) : 'transparent',
  });
  Object.assign($('bubbleInner').style, { left: `${outline}px`, top: `${outline}px`, width: `${inner}px`, height: `${inner}px`, borderRadius: radius(inner) });
  Object.assign(cameraVideo.style, {
    left: `${-outline}px`, top: `${-outline}px`, width: `${rect.width}px`, height: `${rect.height}px`,
    transform: overlay().mirrored ? 'scaleX(-1)' : 'none',
  });
}

const formatTime = (seconds) => {
  const total = Math.floor(Number.isFinite(seconds) ? seconds : 0);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
};

function frame() {
  layout();
  syncCamera();
  drawBubble();
  if (!ui.scrubbing) $('scrub').value = String(ui.duration ? screenVideo.currentTime / ui.duration : 0);
  $('time').textContent = `${formatTime(screenVideo.currentTime)} / ${formatTime(ui.duration)}`;
  $('play').innerHTML = icon(screenVideo.paused ? 'play' : 'pause');
  requestAnimationFrame(frame);
}

// MARK: Controls

const setSegmented = (id, value, disabled = false) => {
  for (const button of $(id).querySelectorAll('button')) {
    button.classList.toggle('on', button.dataset.value === value);
    button.disabled = disabled;
  }
};

function render() {
  const message = $('message');
  message.hidden = !ui.loading && !ui.error;
  message.innerHTML = ui.loading ? '<div class="spinner"></div>' : '';
  if (ui.error) message.textContent = ui.error;

  $('noCamera').hidden = ui.hasCamera;
  $('bubbleRow').hidden = !ui.hasCamera;
  $('styleRow').hidden = !ui.hasCamera;
  const o = overlay();
  $('visible').checked = o.visible;
  setSegmented('placement', o.placement, !hasRecordedPath());
  $('placement').title = hasRecordedPath() ? 'Replay where you dragged the bubble while recording, or pin it in one spot.' : 'Drag the bubble in the preview to place it.';
  if (!ui.dragging) $('size').value = String(currentDiameter());
  $('mirror').checked = o.mirrored;
  setSegmented('shape', o.style.shape);
  $('outline').value = String(o.style.outlineWidth);
  $('color').value = hexColor(o.style.outlineColor);
  $('linuxNote').hidden = !(orbit.platform === 'linux' && ui.hasCamera && hasRecordedPath() && o.placement === Placement.fixed && project.screenFile.endsWith('.mp4'));

  for (const id of ['bubbleRow', 'styleRow']) $(id).classList.toggle('disabled', busy());

  const take = $('take');
  if (ui.take) {
    take.innerHTML = `${icon('stop')}Stop Face Cam Recording`;
    take.classList.add('recording');
  } else {
    take.innerHTML = `${icon('record')}${ui.hasCamera ? 'Re-record Face Cam' : 'Record Face Cam'}`;
    take.classList.remove('recording');
  }
  take.title = 'Plays the recording (muted) and records your camera and mic alongside it.';
  take.disabled = ui.exporting !== null || ui.loading || Boolean(ui.error);
  $('import').innerHTML = `${icon('add')}Add Video…`;
  $('import').hidden = Boolean(ui.take);
  $('import').disabled = busy() || ui.loading;
  $('remove').hidden = !ui.hasCamera || Boolean(ui.take);
  $('remove').disabled = busy();
  $('delete').innerHTML = `${icon('trash')}Delete`;
  $('delete').disabled = busy();
  $('export').innerHTML = `${icon('export')}Export MP4…`;
  $('export').hidden = ui.exporting !== null;
  $('export').disabled = ui.loading || Boolean(ui.error) || busy();
  $('progress').hidden = ui.exporting === null;
  if (ui.exporting !== null) {
    $('progress').querySelector('progress').value = ui.exporting;
    $('progressLabel').textContent = `Exporting… ${Math.floor(ui.exporting * 100)}%`;
  }
  $('play').disabled = Boolean(ui.take);
  $('scrub').disabled = Boolean(ui.take);
}

function togglePlay() {
  if (ui.take) return;
  if (screenVideo.paused) {
    if (screenVideo.currentTime >= ui.duration - 0.05) screenVideo.currentTime = 0;
    screenVideo.play().catch(() => {});
  } else {
    screenVideo.pause();
  }
}

function setStyle(changes, persist = true) {
  const s = overlay().style;
  const style = bubbleStyle(changes.shape ?? s.shape, changes.outlineWidth ?? s.outlineWidth, changes.outlineColor ?? s.outlineColor);
  apply({ ...overlay(), style }, { persist });
  if (persist) orbit.invoke('editor:default-style', style); // the next recording starts with this look
}

function setPlacement(placement) {
  const center = currentBubbleState()?.center ?? overlay().fixedCenter;
  apply(placement === Placement.fixed ? { ...overlay(), placement, fixedCenter: center } : { ...overlay(), placement });
}

/** Dragging the bubble in the preview pins it to that spot. */
function moveBubble(center, persist) {
  apply({ ...overlay(), placement: Placement.fixed, fixedCenter: center, diameterOverride: overlay().diameterOverride ?? currentDiameter() }, { persist });
}

$('play').onclick = togglePlay;
$('scrub').addEventListener('input', (e) => {
  ui.scrubbing = true;
  screenVideo.currentTime = Number(e.target.value) * ui.duration;
});
$('scrub').addEventListener('change', () => { ui.scrubbing = false; });
$('visible').onchange = (e) => apply({ ...overlay(), visible: e.target.checked });
$('mirror').onchange = (e) => apply({ ...overlay(), mirrored: e.target.checked });
$('placement').onclick = (e) => { if (e.target.dataset.value) setPlacement(e.target.dataset.value); };
$('shape').onclick = (e) => { if (e.target.dataset.value) setStyle({ shape: e.target.dataset.value }); };
$('size').addEventListener('input', (e) => apply({ ...overlay(), diameterOverride: Number(e.target.value) }, { persist: false }));
$('size').addEventListener('change', (e) => apply({ ...overlay(), diameterOverride: Number(e.target.value) }));
$('outline').addEventListener('input', (e) => setStyle({ outlineWidth: Number(e.target.value) }, false));
$('outline').addEventListener('change', (e) => setStyle({ outlineWidth: Number(e.target.value) }));
$('color').addEventListener('input', (e) => setStyle({ outlineColor: colorFromHex(e.target.value) }, false));
$('color').addEventListener('change', (e) => setStyle({ outlineColor: colorFromHex(e.target.value) }));

// Drag the dashed handle to move the face cam.
const handle = $('handle');
handle.addEventListener('pointerdown', (e) => {
  if (e.button !== 0 || busy()) return;
  const rect = handle.getBoundingClientRect();
  const stage = $('stage').getBoundingClientRect();
  ui.dragging = { pointer: { x: e.clientX, y: e.clientY }, center: { x: rect.left - stage.left + rect.width / 2, y: rect.top - stage.top + rect.height / 2 } };
  handle.setPointerCapture(e.pointerId);
  handle.classList.add('dragging');
});
function draggedCenter(e) {
  const point = { x: ui.dragging.center.x + e.clientX - ui.dragging.pointer.x, y: ui.dragging.center.y + e.clientY - ui.dragging.pointer.y };
  const center = normalizedCenter(point, ui.videoRect);
  const aspect = ui.videoRect.height > 0 ? ui.videoRect.width / ui.videoRect.height : 1;
  return clampState({ center, diameter: currentDiameter() }, aspect).center;
}
handle.addEventListener('pointermove', (e) => { if (ui.dragging) moveBubble(draggedCenter(e), false); });
handle.addEventListener('pointerup', (e) => {
  if (!ui.dragging) return;
  moveBubble(draggedCenter(e), true);
  ui.dragging = null;
  handle.classList.remove('dragging');
});

// MARK: Face-cam sources

async function useCamera(source) {
  const placement = hasRecordedPath() ? overlay().placement : Placement.fixed;
  project = { ...project, camera: source, overlay: { ...overlay(), visible: true, placement } };
  await save();
  await load();
}

/** Records your camera and mic while the screen recording plays back (muted), then overlays it. */
async function startTake() {
  if (ui.take || busy()) return;
  let stream = null;
  let writer = null;
  try {
    stream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } },
      audio: { echoCancellation: true },
    });
  } catch (error) {
    orbit.invoke('editor:error', 'Couldn’t start the face cam', describeMediaError(error, 'camera and microphone'));
    return;
  }
  try {
    await orbit.invoke('editor:take-bubble', true);
    const name = await orbit.invoke('editor:take-name');
    writer = await orbit.invoke('file:create', token, name);
    const output = fileOutput(writer);
    const videoTrack = stream.getVideoTracks()[0];
    const settings = videoTrack.getSettings();
    const even = (n) => Math.max(2, Math.round(n / 2) * 2);
    output.addVideoTrack(new MediaStreamVideoTrackSource(videoTrack, {
      codec: await videoCodecFor(even(settings.width || 1280), even(settings.height || 720), 30), quality: QUALITY_HIGH, keyFrameInterval: 2, sizeChangeBehavior: 'fill',
    }, { frameRate: 30 }), { frameRate: 30 });
    const audioEncoding = await audioCodec();
    const audioTrack = stream.getAudioTracks()[0];
    if (audioEncoding && audioTrack) output.addAudioTrack(new MediaStreamAudioTrackSource(audioTrack, { codec: audioEncoding, quality: QUALITY_HIGH }));
    await output.start();
    for (let i = 0; i < 60 && firstMediaTime(output) === null; i++) await sleep(50);
    const cameraStart = firstMediaTime(output);
    if (cameraStart === null) throw new Error('The camera didn’t send any video.');

    const videoStart = screenVideo.currentTime >= ui.duration - 0.5 ? 0 : screenVideo.currentTime;
    screenVideo.currentTime = videoStart;
    await new Promise((resolve) => (screenVideo.seeking ? screenVideo.addEventListener('seeked', resolve, { once: true }) : resolve()));
    screenVideo.muted = true; // keep playback audio out of your mic
    await screenVideo.play();
    const playStart = performance.now() / 1000;
    ui.take = { stream, output, writer, name, offset: videoStart - (playStart - cameraStart) };
    render();
  } catch (error) {
    stream.getTracks().forEach((t) => t.stop());
    if (writer) await orbit.invoke('file:abort', writer.id).catch(() => {});
    await orbit.invoke('editor:take-bubble', false);
    screenVideo.muted = false;
    orbit.invoke('editor:error', 'Couldn’t record the face cam', error.message);
  }
}

async function stopTake() {
  const take = ui.take;
  if (!take) return;
  ui.take = null;
  screenVideo.pause();
  screenVideo.muted = false;
  render();
  try {
    await take.output.finalize();
    await orbit.invoke('file:close', take.writer.id);
    await useCamera({ file: take.name, offset: take.offset, includeAudio: true });
  } catch (error) {
    orbit.invoke('editor:error', 'Couldn’t save the face cam', error.message);
  } finally {
    take.stream.getTracks().forEach((t) => t.stop());
    await orbit.invoke('editor:take-bubble', false);
  }
}

$('take').onclick = () => (ui.take ? stopTake() : startTake());
screenVideo.addEventListener('ended', () => { if (ui.take) stopTake(); });

$('import').onclick = async () => {
  try {
    const name = await orbit.invoke('editor:import');
    if (name) await useCamera({ file: name, offset: 0, includeAudio: true });
  } catch (error) {
    orbit.invoke('editor:error', 'Couldn’t add the video', error.message);
  }
};

$('remove').onclick = async () => {
  project = { ...project, camera: null };
  await save();
  await load();
};

// MARK: Delete and export

$('delete').onclick = async () => {
  screenVideo.pause();
  await orbit.invoke('editor:delete');
};

orbit.on('editor:release', () => {
  for (const video of [screenVideo, cameraVideo]) {
    video.pause();
    video.removeAttribute('src');
    video.load();
  }
});

async function startExport() {
  if (busy() || ui.loading || ui.error) return;
  const writer = await orbit.invoke('editor:choose-export');
  if (!writer) return;
  screenVideo.pause();
  ui.exporting = 0;
  render();
  let lastRender = 0;
  try {
    await exportVideo({
      token,
      project,
      writer,
      onProgress: (value) => {
        ui.exporting = value;
        if (performance.now() - lastRender > 100) {
          lastRender = performance.now();
          render();
        }
      },
    });
    orbit.invoke('editor:reveal', writer.file);
  } catch (error) {
    console.error(error);
    orbit.invoke('editor:error', 'Export failed', error.message ?? String(error));
  } finally {
    ui.exporting = null;
    render();
  }
}
$('export').onclick = startExport;

window.addEventListener('keydown', (e) => {
  const typing = ['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement?.tagName) && document.activeElement.type !== 'range' && document.activeElement.type !== 'checkbox';
  if (e.key === ' ' && !typing) {
    e.preventDefault();
    togglePlay();
  } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'e') {
    e.preventDefault();
    startExport();
  } else if ((e.ctrlKey || e.metaKey) && (e.key === 'Delete' || e.key === 'Backspace') && !busy()) {
    e.preventDefault();
    $('delete').click();
  }
});

// Exposed for the automated smoke test (scripts/smoke.js).
window.orbitEditor = { startExport, state: () => ({ ...ui, project }) };

render();
requestAnimationFrame(frame);
await load();
