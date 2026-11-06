// Recording resolution and selection shape. Mirrors Sources/OrbitCore/CaptureFormat.swift.

export const resolutions = ['native', 'p720', 'p1080', 'p1440'];

export const resolutionLabel = {
  native: 'Native (HiDPI)',
  p720: '720p',
  p1080: '1080p',
  p1440: '1440p',
};

const shortSide = { native: null, p720: 720, p1080: 1080, p1440: 1440 };

const even = (value) => Math.max(2, Math.round(value / 2) * 2);

/**
 * Output pixels for a capture area measured in DIPs. Named sizes set the *short* side, so a 16:9
 * selection at 1080p comes out at exactly 1920×1080. Always even, as video encoders require.
 */
export function pixelSize(resolution, size, scale) {
  if (!(size.width > 0 && size.height > 0)) return { width: 2, height: 2 };
  const side = shortSide[resolution] ?? null;
  const factor = side != null ? side / Math.min(size.width, size.height) : scale;
  return { width: even(size.width * factor), height: even(size.height * factor) };
}

export const aspects = ['freeform', 'widescreen'];

export const aspectLabel = { freeform: 'Freeform', widescreen: '16:9' };

/** Width units × height units; sizes snap to whole multiples so the ratio is exact. */
export function aspectUnits(aspect) {
  return aspect === 'widescreen' ? { width: 16, height: 9 } : null;
}

export const frameRates = [30, 60];
