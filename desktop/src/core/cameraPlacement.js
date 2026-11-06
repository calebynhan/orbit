// Where a face-cam clip lands on the screen recording's timeline.
// Mirrors Sources/OrbitCore/CameraPlacement.swift.

/**
 * @param offset screen-timeline time at which camera time 0 occurs (negative = camera started first).
 * @returns `{ sourceStart, insertAt, duration }`, or null when the clip doesn't overlap the screen recording.
 */
export function computePlacement(offset, cameraDuration, screenDuration) {
  const sourceStart = Math.max(0, -offset);
  const insertAt = Math.max(0, offset);
  const duration = Math.min(cameraDuration - sourceStart, screenDuration - insertAt);
  if (!(duration > 0)) return null;
  return { sourceStart, insertAt, duration };
}

/** Offset between two start times on the same clock, in seconds. */
export function cameraOffset(cameraStart, screenStart) {
  return cameraStart - screenStart;
}
