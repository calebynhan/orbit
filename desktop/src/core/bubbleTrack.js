// The path the bubble took while recording. Mirrors Sources/OrbitCore/BubbleTrack.swift.
//
// A BubbleState is `{ center: { x, y }, diameter }`: `center` is normalized to the recorded
// area with a top-left origin (0,0 = top-left, 1,1 = bottom-right); `diameter` is a fraction
// of the area's height.

export function bubbleState(x, y, diameter) {
  return { center: { x, y }, diameter };
}

export function stateEquals(a, b) {
  return a.center.x === b.center.x && a.center.y === b.center.y && a.diameter === b.diameter;
}

function interpolate(a, b, t) {
  return bubbleState(
    a.center.x + (b.center.x - a.center.x) * t,
    a.center.y + (b.center.y - a.center.y) * t,
    a.diameter + (b.diameter - a.diameter) * t,
  );
}

/** Keyframes `{ time, state }` sorted by time. */
export function makeTrack(keyframes = []) {
  return { keyframes: [...keyframes].sort((a, b) => a.time - b.time) };
}

/** Bubble state at `time`, linearly interpolated between keyframes and held at the ends. */
export function trackState(track, time) {
  const frames = track?.keyframes ?? [];
  if (frames.length === 0) return null;
  const first = frames[0];
  const last = frames[frames.length - 1];
  if (time <= first.time) return first.state;
  if (time >= last.time) return last.state;
  let low = 0;
  let high = frames.length - 1;
  while (low + 1 < high) {
    const mid = (low + high) >> 1;
    if (frames[mid].time <= time) low = mid; else high = mid;
  }
  const a = frames[low];
  const b = frames[high];
  const span = b.time - a.time;
  if (!(span > 0)) return b.state;
  return interpolate(a.state, b.state, (time - a.time) / span);
}

/**
 * Builds a compact track from periodic samples: only changes become keyframes, and a "hold"
 * keyframe is inserted before a move so interpolation doesn't drift across a pause.
 */
export class BubbleTrackRecorder {
  constructor() {
    this.keyframes = [];
    this.lastSample = null;
  }

  record(state, time) {
    const sample = { time, state };
    if (this.lastSample && stateEquals(this.lastSample.state, state)) {
      this.lastSample = sample;
      return this;
    }
    if (this.lastSample) this.#hold(this.lastSample);
    this.keyframes.push(sample);
    this.lastSample = sample;
    return this;
  }

  /** The final track, including a hold keyframe at the last sample time. */
  finished() {
    if (this.lastSample) this.#hold(this.lastSample);
    return makeTrack(this.keyframes);
  }

  #hold(last) {
    const lastTime = this.keyframes.length ? this.keyframes[this.keyframes.length - 1].time : -Infinity;
    if (last.time > lastTime) this.keyframes.push(last);
  }
}

/**
 * Re-bases a track sampled on another clock so `zero` becomes time 0 (the first video frame).
 * Samples from before the video started collapse into one keyframe at 0.
 */
export function alignTrack(track, zero) {
  const shifted = track.keyframes.map((k) => ({ time: k.time - zero, state: k.state }));
  const before = shifted.filter((k) => k.time <= 0);
  const after = shifted.filter((k) => k.time > 0);
  const start = before.length ? [{ time: 0, state: before[before.length - 1].state }] : [];
  return makeTrack([...start, ...after]);
}
