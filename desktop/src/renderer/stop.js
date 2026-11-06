// Floating stop button with the elapsed time.
import { icon } from './icons.js';

const { startedAt } = await orbit.invoke('stop:info');
const stopButton = document.getElementById('stop');
stopButton.innerHTML = `${icon('stop', 'icon')}Stop`;
stopButton.onclick = () => orbit.send('stop:stop');

const time = document.getElementById('time');
const pad = (n) => String(n).padStart(2, '0');
function tick() {
  const total = Math.floor((Date.now() - (startedAt ?? Date.now())) / 1000);
  time.textContent = total >= 3600
    ? `${Math.floor(total / 3600)}:${pad(Math.floor(total / 60) % 60)}:${pad(total % 60)}`
    : `${Math.floor(total / 60)}:${pad(total % 60)}`;
}
tick();
setInterval(tick, 500);
