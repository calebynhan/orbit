// The face cam's shape and outline. Mirrors Sources/OrbitCore/BubbleStyle.swift.

export const BubbleShape = Object.freeze({ circle: 'circle', rounded: 'rounded', square: 'square' });
export const bubbleShapes = [BubbleShape.circle, BubbleShape.rounded, BubbleShape.square];

export const shapeLabel = { circle: 'Circle', rounded: 'Rounded', square: 'Square' };

/** Corner radius as a fraction of the bubble's side. */
export function cornerRadiusFraction(shape) {
  switch (shape) {
    case BubbleShape.rounded: return 0.18;
    case BubbleShape.square: return 0;
    default: return 0.5;
  }
}

const clamp01 = (v) => Math.min(Math.max(Number(v) || 0, 0), 1);

/** A platform-independent colour, components 0...1. Same JSON shape as the Swift `RGBAColor`. */
export function rgba(red, green, blue, alpha = 1) {
  return { red: clamp01(red), green: clamp01(green), blue: clamp01(blue), alpha: clamp01(alpha) };
}

export const white = rgba(1, 1, 1);
export const black = rgba(0, 0, 0);

export function colorEquals(a, b) {
  return a.red === b.red && a.green === b.green && a.blue === b.blue && a.alpha === b.alpha;
}

export function cssColor(c) {
  const to255 = (v) => Math.round(v * 255);
  return `rgba(${to255(c.red)}, ${to255(c.green)}, ${to255(c.blue)}, ${c.alpha})`;
}

export function hexColor(c) {
  const hex = (v) => Math.round(v * 255).toString(16).padStart(2, '0');
  return `#${hex(c.red)}${hex(c.green)}${hex(c.blue)}`;
}

export function colorFromHex(value) {
  const match = /^#?([0-9a-f]{6})$/i.exec(value ?? '');
  if (!match) return white;
  const n = parseInt(match[1], 16);
  return rgba(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255);
}

export const maxOutlineWidth = 0.08;

export function bubbleStyle(shape, outlineWidth, outlineColor) {
  return {
    shape: bubbleShapes.includes(shape) ? shape : BubbleShape.circle,
    outlineWidth: Math.min(Math.max(Number(outlineWidth) || 0, 0), maxOutlineWidth),
    outlineColor: outlineColor ? rgba(outlineColor.red, outlineColor.green, outlineColor.blue, outlineColor.alpha ?? 1) : white,
  };
}

export const defaultStyle = bubbleStyle(BubbleShape.circle, 0.035, white);

/** Presets offered in the bubble's right-click menu (same as the Mac app). */
export const sizePresets = [['Small', 140], ['Medium', 200], ['Large', 300], ['Extra Large', 440]];
export const outlinePresets = [['None', 0], ['Thin', 0.015], ['Medium', 0.035], ['Thick', 0.06]];
export const colorPresets = [
  ['White', white],
  ['Black', black],
  ['Red', rgba(0.9, 0.28, 0.3)],
  ['Blue', rgba(0.31, 0.49, 1)],
  ['Green', rgba(0.33, 0.8, 0.5)],
  ['Yellow', rgba(1, 0.84, 0.3)],
];
