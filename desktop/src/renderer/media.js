// Helpers shared by the recorder and the editor: writing MP4s to disk through the main process,
// and picking codecs every player can open.
import {
  Output, Mp4OutputFormat, StreamTarget, getFirstEncodableVideoCodec, getFirstEncodableAudioCodec,
} from '../vendor/mediabunny.mjs';

/** H.264 + AAC where the platform can encode them (they open everywhere, including the Mac app). */
export async function videoCodecFor(width, height, frameRate) {
  const codec = await getFirstEncodableVideoCodec(['avc', 'vp9', 'av1', 'vp8'], { width, height, frameRate });
  if (!codec) throw new Error(`This computer can’t encode ${width}×${height} video. Try a lower resolution.`);
  return codec;
}

export async function audioCodec() {
  return (await getFirstEncodableAudioCodec(['aac', 'opus'], { numberOfChannels: 2, sampleRate: 48000 })) ?? null;
}

/** A WritableStream that writes mediabunny chunks at their byte offsets in a main-process file. */
function fileStream(writerId) {
  return new WritableStream({
    async write(chunk) {
      await orbit.invoke('file:write', writerId, chunk.data, chunk.position);
    },
  });
}

/** An MP4 output streaming to `writer` ({ id } from file:create / editor:choose-export). */
export function fileOutput(writer) {
  return new Output({
    format: new Mp4OutputFormat({ fastStart: false }),
    target: new StreamTarget(fileStream(writer.id), { chunked: true, chunkSize: 4 * 1024 * 1024 }),
  });
}

/**
 * When a live-capture output saw its first frame, in performance.now() seconds. Every track in the
 * file is timed from this moment ("synced-zero"), so it lines files from separate outputs up.
 */
export function firstMediaTime(output) {
  const value = output._firstMediaStreamTimestamp;
  return typeof value === 'number' ? value : null;
}

/** performance.now() seconds → wall-clock milliseconds, comparable with the main process. */
export const toEpochMs = (seconds) => performance.timeOrigin + seconds * 1000;

export const mediaUrl = (token, file) => `orbit://media/${token}/${encodeURIComponent(file)}`;

export function describeMediaError(error, what) {
  if (error?.name === 'NotAllowedError') return `Orbit isn’t allowed to use the ${what}. Check your privacy settings and try again.`;
  if (error?.name === 'NotFoundError') return `No ${what} was found.`;
  if (error?.name === 'NotReadableError') return `The ${what} is in use by another app or couldn’t be started.`;
  return error?.message || String(error);
}

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
