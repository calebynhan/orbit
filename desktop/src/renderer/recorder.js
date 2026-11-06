// Hidden window that captures the screen (cropped and scaled to the chosen area and resolution),
// the microphone and system audio, and the camera, encoding each straight to MP4 on disk.
// Screen and camera are separate files, like the Mac app, so the editor composites them later.
import { MediaStreamVideoTrackSource, MediaStreamAudioTrackSource, QUALITY_HIGH } from '../vendor/mediabunny.mjs';
import { fileOutput, videoCodecFor, audioCodec, firstMediaTime, toEpochMs, describeMediaError, sleep } from './media.js';

const job = await orbit.invoke('recorder:job');
const streams = [];
const outputs = []; // { output, writer, name }
let audioContext = null;
let stopping = false;

const fail = (error) => {
  if (stopping) return;
  orbit.invoke('recorder:failed', typeof error === 'string' ? error : describeMediaError(error, 'screen'));
};

async function screenStream() {
  const width = Math.round(job.display.width * job.display.scaleFactor);
  const height = Math.round(job.display.height * job.display.scaleFactor);
  const desktop = { chromeMediaSource: 'desktop', chromeMediaSourceId: job.sourceId };
  const video = { mandatory: { ...desktop, maxWidth: width, maxHeight: height, maxFrameRate: job.framesPerSecond } };
  try {
    return await navigator.mediaDevices.getUserMedia({ video, audio: job.systemAudio ? { mandatory: { chromeMediaSource: 'desktop' } } : false });
  } catch (error) {
    if (!job.systemAudio) throw error;
    // Some setups can't loop back system audio; record without it rather than not at all.
    console.warn('System audio unavailable', error);
    return navigator.mediaDevices.getUserMedia({ video, audio: false });
  }
}

async function microphoneStream() {
  const constraints = (deviceId) => ({
    audio: {
      ...(deviceId ? { deviceId: { exact: deviceId } } : {}),
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      channelCount: { ideal: 2 },
    },
  });
  try {
    return await navigator.mediaDevices.getUserMedia(constraints(job.microphone.deviceId));
  } catch (error) {
    if (!job.microphone.deviceId || error.name === 'NotAllowedError') throw error;
    return navigator.mediaDevices.getUserMedia(constraints(null)); // the chosen mic was unplugged
  }
}

/** One audio track: mic and system audio mixed together when both are on. */
function mixedAudioTrack(tracks) {
  if (tracks.length === 0) return null;
  if (tracks.length === 1) return tracks[0];
  audioContext = new AudioContext({ sampleRate: 48000 });
  const destination = audioContext.createMediaStreamDestination();
  for (const track of tracks) audioContext.createMediaStreamSource(new MediaStream([track])).connect(destination);
  return destination.stream.getAudioTracks()[0];
}

const even = (n) => Math.max(2, Math.round(n / 2) * 2);

async function addOutput(name, videoTrack, videoConfig, sourceOptions, audioTrack) {
  const writer = await orbit.invoke('file:create', job.token, name);
  const output = fileOutput(writer);
  const video = new MediaStreamVideoTrackSource(videoTrack, videoConfig, sourceOptions);
  output.addVideoTrack(video, { frameRate: sourceOptions.frameRate });
  video.errorPromise.catch(fail);
  if (audioTrack) {
    const codec = await audioCodec();
    if (codec) {
      const audio = new MediaStreamAudioTrackSource(audioTrack, { codec, quality: QUALITY_HIGH });
      output.addAudioTrack(audio);
      audio.errorPromise.catch(fail);
    }
  }
  outputs.push({ output, writer, name });
  return output;
}

async function start() {
  const screen = await screenStream();
  streams.push(screen);
  const screenTrack = screen.getVideoTracks()[0];
  screenTrack.addEventListener('ended', () => fail('Screen capture ended.'));

  const audioTracks = [...screen.getAudioTracks()];
  if (job.microphone) {
    let mic;
    try {
      mic = await microphoneStream();
    } catch (error) {
      throw new Error(describeMediaError(error, 'microphone'));
    }
    streams.push(mic);
    audioTracks.unshift(mic.getAudioTracks()[0]);
  }

  let cameraTrack = null;
  if (job.camera) {
    try {
      const camera = await navigator.mediaDevices.getUserMedia({ video: { width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } }, audio: false });
      streams.push(camera);
      cameraTrack = camera.getVideoTracks()[0];
    } catch (error) {
      throw new Error(describeMediaError(error, 'camera'));
    }
  }

  // Crop in captured pixels: Chromium may deliver the display at a different size than asked.
  const settings = screenTrack.getSettings();
  const scale = (settings.width || job.display.width * job.display.scaleFactor) / job.display.width;
  const transform = { width: job.outputSize.width, height: job.outputSize.height };
  if (job.crop) {
    transform.crop = {
      left: Math.round(job.crop.x * scale),
      top: Math.round(job.crop.y * scale),
      width: even(job.crop.width * scale),
      height: even(job.crop.height * scale),
    };
  }
  const fps = job.framesPerSecond;
  const screenOutput = await addOutput(
    'screen.mp4',
    screenTrack,
    {
      codec: await videoCodecFor(transform.width, transform.height, fps),
      quality: QUALITY_HIGH,
      keyFrameInterval: 2,
      sizeChangeBehavior: 'fill', // a display that changes resolution mid-recording is stretched to fit
      transform,
    },
    { frameRate: fps },
    mixedAudioTrack(audioTracks),
  );

  let cameraOutput = null;
  if (cameraTrack) {
    const cam = cameraTrack.getSettings();
    cameraOutput = await addOutput(
      'camera.mp4',
      cameraTrack,
      { codec: await videoCodecFor(even(cam.width || 1280), even(cam.height || 720), 30), quality: QUALITY_HIGH, keyFrameInterval: 2, sizeChangeBehavior: 'fill' },
      { frameRate: 30 },
      null,
    );
  }

  await screenOutput.start();
  if (cameraOutput) await cameraOutput.start();
}

async function stop() {
  stopping = true;
  const [screen, camera] = outputs;
  const result = { screenFile: screen.name, cameraFile: null, screenStartMs: null, cameraStartMs: null };
  try {
    for (const { output, writer } of outputs) {
      await output.finalize();
      await orbit.invoke('file:close', writer.id);
    }
    const screenStart = firstMediaTime(screen.output);
    if (screenStart === null) throw new Error('No video was captured from the screen.');
    result.screenStartMs = toEpochMs(screenStart);
    const cameraStart = camera ? firstMediaTime(camera.output) : null;
    if (camera && cameraStart !== null) {
      result.cameraFile = camera.name;
      result.cameraStartMs = toEpochMs(cameraStart);
    }
  } finally {
    for (const stream of streams) stream.getTracks().forEach((t) => t.stop());
    audioContext?.close();
  }
  return result;
}

orbit.on('recorder:stop', async () => {
  try {
    await orbit.invoke('recorder:finished', await stop());
  } catch (error) {
    stopping = false;
    fail(error.message || String(error));
  }
});

try {
  await start();
  // Give the first frame a moment so "recording" starts when frames are actually flowing.
  for (let i = 0; i < 20 && firstMediaTime(outputs[0].output) === null; i++) await sleep(50);
  await orbit.invoke('recorder:started');
} catch (error) {
  for (const stream of streams) stream.getTracks().forEach((t) => t.stop());
  for (const { writer } of outputs) await orbit.invoke('file:abort', writer.id).catch(() => {});
  fail(error);
}
