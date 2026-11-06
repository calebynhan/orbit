// Renders a recording to MP4: screen + bubble frames at the capture frame rate, and the screen's
// audio mixed with the face-cam clip's own audio when it has some (post-recorded or imported takes).
// The Mac app does the same with AVFoundation (CompositionBuilder + BubbleCompositor + Exporter).
import {
  Input, UrlSource, ALL_FORMATS, CanvasSink, AudioBufferSink, CanvasSource, AudioBufferSource, QUALITY_HIGH,
} from '../vendor/mediabunny.mjs';
import { fileOutput, videoCodecFor, audioCodec, mediaUrl } from './media.js';
import { drawBubble } from './compositor.js';
import { overlayState } from '../core/project.js';
import { clampState, rectForState } from '../core/overlayGeometry.js';

const sampleRate = 48000;
const windowSeconds = 2;
const evenFloor = (n) => Math.max(2, Math.floor(n / 2) * 2);

async function openTrack(token, file) {
  const input = new Input({ source: new UrlSource(mediaUrl(token, file)), formats: ALL_FORMATS });
  return {
    input,
    video: await input.getPrimaryVideoTrack(),
    audio: await input.getPrimaryAudioTrack(),
  };
}

/** Mixes every buffer overlapping [from, to) of `sink` into `ctx`, placing source time `from` at 0. */
async function scheduleAudio(ctx, sink, from, to) {
  if (!sink) return;
  for await (const { buffer, timestamp } of sink.buffers(Math.max(0, from), to)) {
    const node = ctx.createBufferSource();
    node.buffer = buffer;
    node.connect(ctx.destination);
    const when = timestamp - from;
    if (when < 0) node.start(0, -when);
    else node.start(when);
  }
}

/**
 * @param writer { id, file } from editor:choose-export
 * @param onProgress called with 0…1
 */
export async function exportVideo({ token, project, writer, onProgress }) {
  const screen = await openTrack(token, project.screenFile);
  if (!screen.video) throw new Error('The screen recording has no video. It may not have finished saving.');

  const start = await screen.video.getFirstTimestamp();
  const end = await screen.video.computeDuration();
  const duration = Math.max(0, end - start);
  const width = evenFloor(await screen.video.getDisplayWidth());
  const height = evenFloor(await screen.video.getDisplayHeight());
  let fps = project.framesPerSecond;
  if (!fps) {
    const stats = await screen.video.computePacketStats(100);
    fps = stats.averagePacketRate >= 50 ? 60 : 30;
  }

  let camera = null;
  if (project.camera) {
    camera = await openTrack(token, project.camera.file);
    camera.start = camera.video ? await camera.video.getFirstTimestamp() : 0;
    camera.end = camera.video ? await camera.video.computeDuration() : 0;
  }
  const showBubble = Boolean(camera?.video) && project.overlay.visible;

  const canvas = new OffscreenCanvas(width, height);
  const ctx = canvas.getContext('2d', { alpha: false });
  ctx.imageSmoothingQuality = 'high';

  const output = fileOutput(writer);
  const videoSource = new CanvasSource(canvas, { codec: await videoCodecFor(width, height, fps), quality: QUALITY_HIGH, keyFrameInterval: 2 });
  output.addVideoTrack(videoSource, { frameRate: fps });

  const screenAudio = screen.audio && (await screen.audio.canDecode()) ? new AudioBufferSink(screen.audio) : null;
  const cameraAudio = project.camera?.includeAudio && camera?.audio && (await camera.audio.canDecode()) ? new AudioBufferSink(camera.audio) : null;
  const audioEncoding = screenAudio || cameraAudio ? await audioCodec() : null;
  const audioSource = audioEncoding ? new AudioBufferSource({ codec: audioEncoding, quality: QUALITY_HIGH }) : null;
  if (audioSource) output.addAudioTrack(audioSource);

  const totalFrames = Math.max(1, Math.round(duration * fps));
  const frameTime = (i) => start + i / fps;
  const cameraTime = (t) => t - project.camera.offset;
  const inCamera = (t) => showBubble && cameraTime(t) >= camera.start && cameraTime(t) < camera.end;

  const screenFrames = new CanvasSink(screen.video, { width, height, fit: 'fill', poolSize: 2 })
    .canvasesAtTimestamps((function* () { for (let i = 0; i < totalFrames; i++) yield frameTime(i); })());
  const cameraFrames = showBubble
    ? new CanvasSink(camera.video, { poolSize: 2 })
      .canvasesAtTimestamps((function* () {
        for (let i = 0; i < totalFrames; i++) if (inCamera(frameTime(i))) yield cameraTime(frameTime(i));
      })())
    : null;

  await output.start();
  try {
    let frame = 0;
    for (let w = 0; w < duration; w += windowSeconds) {
      const windowEnd = Math.min(w + windowSeconds, duration);
      if (audioSource) {
        const length = Math.max(1, Math.round((windowEnd - w) * sampleRate));
        const mix = new OfflineAudioContext(2, length, sampleRate);
        await scheduleAudio(mix, screenAudio, start + w, start + windowEnd);
        if (cameraAudio) await scheduleAudio(mix, cameraAudio, cameraTime(start + w), cameraTime(start + windowEnd));
        await audioSource.add(await mix.startRendering());
      }
      for (; frame < totalFrames && frame / fps < windowEnd; frame++) {
        const t = frameTime(frame);
        const screenFrame = (await screenFrames.next()).value;
        if (screenFrame) ctx.drawImage(screenFrame.canvas, 0, 0, width, height);
        if (inCamera(t)) {
          const cameraFrame = (await cameraFrames.next()).value;
          const state = overlayState(project.overlay, t, project.bubbleTrack);
          if (state && cameraFrame) {
            const rect = rectForState(clampState(state, width / height), { x: 0, y: 0, width, height });
            drawBubble(ctx, cameraFrame.canvas, rect, project.overlay.style, project.overlay.mirrored);
          }
        }
        await videoSource.add(frame / fps, 1 / fps);
        onProgress?.(frame / totalFrames);
      }
    }
    await output.finalize();
    await orbit.invoke('file:close', writer.id);
    onProgress?.(1);
  } catch (error) {
    await output.cancel().catch(() => {});
    await orbit.invoke('file:abort', writer.id).catch(() => {});
    throw error;
  } finally {
    screen.input.dispose?.();
    camera?.input.dispose?.();
  }
}
