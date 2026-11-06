// Draws one exported frame: the screen, then the camera cropped into the bubble shape with its
// outline. Mirrors Sources/Orbit/Editor/BubbleCompositor.swift — the photo is fitted to the
// whole bubble and the inner (inset) shape crops it, over a ring in the outline colour.
import { cornerRadiusFraction, cssColor } from '../core/bubbleStyle.js';
import { centeredSquareCrop } from '../core/overlayGeometry.js';

function shapePath(ctx, rect, shape) {
  ctx.beginPath();
  if (shape === 'circle') {
    ctx.arc(rect.x + rect.width / 2, rect.y + rect.height / 2, rect.width / 2, 0, Math.PI * 2);
  } else {
    ctx.roundRect(rect.x, rect.y, rect.width, rect.height, rect.width * cornerRadiusFraction(shape));
  }
}

/**
 * @param camera a canvas/image of the camera frame, or null
 * @param rect   the bubble's square in output pixels (already clamped inside the frame)
 */
export function drawBubble(ctx, camera, rect, style, mirrored) {
  const outline = rect.width * style.outlineWidth;
  const inner = { x: rect.x + outline, y: rect.y + outline, width: rect.width - outline * 2, height: rect.height - outline * 2 };
  if (outline > 0) {
    ctx.fillStyle = cssColor(style.outlineColor);
    shapePath(ctx, rect, style.shape);
    ctx.fill();
  }
  if (!camera || inner.width <= 0) return;
  const crop = centeredSquareCrop({ width: camera.width, height: camera.height });
  ctx.save();
  shapePath(ctx, inner, style.shape);
  ctx.clip();
  if (mirrored) {
    ctx.translate(rect.x * 2 + rect.width, 0);
    ctx.scale(-1, 1);
  }
  ctx.drawImage(camera, crop.x, crop.y, crop.width, crop.height, rect.x, rect.y, rect.width, rect.height);
  ctx.restore();
}
