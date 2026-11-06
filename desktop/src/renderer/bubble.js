// The live camera in the chosen shape. Drag to move, scroll to resize, right-click for options.
import { cornerRadiusFraction, cssColor } from '../core/bubbleStyle.js';

const outer = document.getElementById('outer');
const inner = document.getElementById('inner');
const video = document.getElementById('video');
let style = await orbit.invoke('bubble:style');

function applyStyle() {
  const side = Math.min(window.innerWidth, window.innerHeight);
  const outline = side * style.outlineWidth;
  const innerSide = side - outline * 2;
  outer.style.borderRadius = `${side * cornerRadiusFraction(style.shape)}px`;
  outer.style.background = outline > 0 ? cssColor(style.outlineColor) : 'transparent';
  Object.assign(inner.style, {
    left: `${outline}px`,
    top: `${outline}px`,
    width: `${innerSide}px`,
    height: `${innerSide}px`,
    borderRadius: `${innerSide * cornerRadiusFraction(style.shape)}px`,
  });
  Object.assign(video.style, { left: `${-outline}px`, top: `${-outline}px`, width: `${side}px`, height: `${side}px` });
}

orbit.on('bubble:style', (next) => {
  style = next;
  applyStyle();
});
window.addEventListener('resize', applyStyle);
applyStyle();

outer.addEventListener('pointerdown', (e) => {
  if (e.button !== 0) return;
  outer.setPointerCapture(e.pointerId);
  orbit.send('bubble:drag-start');
});
outer.addEventListener('pointermove', (e) => {
  if (outer.hasPointerCapture(e.pointerId)) orbit.send('bubble:drag');
});
outer.addEventListener('pointerup', (e) => {
  if (outer.hasPointerCapture(e.pointerId)) outer.releasePointerCapture(e.pointerId);
  orbit.send('bubble:drag-end');
});
outer.addEventListener('wheel', (e) => {
  e.preventDefault();
  orbit.send('bubble:resize', -e.deltaY * (e.deltaMode === 1 ? 8 : 0.5));
}, { passive: false });
outer.addEventListener('contextmenu', (e) => {
  e.preventDefault();
  orbit.send('bubble:menu');
});

try {
  video.srcObject = await navigator.mediaDevices.getUserMedia({
    video: { width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } },
    audio: false,
  });
} catch (error) {
  orbit.send('bubble:error', error.name === 'NotAllowedError'
    ? 'Orbit isn’t allowed to use the camera. Check your privacy settings.'
    : error.name === 'NotFoundError' ? 'No camera was found.' : error.message);
}
