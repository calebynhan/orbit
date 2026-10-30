(() => {
  const demo = document.getElementById('demo');
  const stage = document.getElementById('stage');
  const face = document.getElementById('face');
  const toggle = document.getElementById('toggle');
  const pill = document.getElementById('pill-text');
  const hint = document.getElementById('hint');
  let recording = true, seconds = 7, timer = null, drag = null;

  const tick = () => { seconds += 1; pill.textContent = 'REC ' + Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0'); };
  const start = () => { timer = setInterval(tick, 1000); };
  start();

  toggle.addEventListener('click', () => {
    recording = !recording;
    demo.dataset.state = recording ? 'recording' : 'stopped';
    toggle.textContent = recording ? 'Stop' : 'Record again';
    toggle.setAttribute('aria-pressed', String(recording));
    if (recording) { seconds = 0; tick(); start(); hint.textContent = 'Drag the circle off the button. Then press Stop and drag it again.'; }
    else { clearInterval(timer); pill.textContent = 'STOPPED · still movable'; hint.textContent = 'Stopped. The circle still moves, because the camera was never burned in.'; }
  });

  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);
  const place = (x, y) => {
    const r = stage.getBoundingClientRect(), size = face.offsetWidth;
    face.style.left = clamp(x - r.left - drag.dx, 0, r.width - size) + 'px';
    face.style.top = clamp(y - r.top - drag.dy, 0, r.height - size) + 'px';
  };
  face.addEventListener('pointerdown', (e) => {
    const f = face.getBoundingClientRect();
    drag = { dx: e.clientX - f.left, dy: e.clientY - f.top };
    face.setPointerCapture(e.pointerId);
    e.preventDefault();
  });
  face.addEventListener('pointermove', (e) => { if (drag) place(e.clientX, e.clientY); });
  const end = () => { drag = null; };
  face.addEventListener('pointerup', end);
  face.addEventListener('pointercancel', end);

  // Keyboard: arrow keys move the circle when the stage is focused.
  stage.addEventListener('keydown', (e) => {
    const step = e.shiftKey ? 24 : 8, k = e.key;
    if (!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(k)) return;
    e.preventDefault();
    const f = face.getBoundingClientRect();
    drag = { dx: 0, dy: 0 };
    place(f.left + (k === 'ArrowRight' ? step : k === 'ArrowLeft' ? -step : 0), f.top + (k === 'ArrowDown' ? step : k === 'ArrowUp' ? -step : 0));
    drag = null;
  });
})();
