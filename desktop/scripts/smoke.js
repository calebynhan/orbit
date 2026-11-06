// End-to-end smoke test: records the screen (with a fake camera and mic), opens the editor, and
// exports an MP4. Linux, under Xvfb:
//   xvfb-run -a -s "-screen 0 1600x900x24" npm run smoke
// ORBIT_SMOKE_MODE=entireScreen records the whole screen instead of a selection.
// Prints what it checked; screenshots go to $ORBIT_SMOKE_OUT (default: a temp dir).
import { app, BrowserWindow, screen, webContents } from 'electron';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import '../src/main/main.js';

const out = process.env.ORBIT_SMOKE_OUT || fs.mkdtempSync(path.join(os.tmpdir(), 'orbit-smoke-'));
fs.mkdirSync(out, { recursive: true });
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'orbit-home-'));
app.setPath('userData', path.join(home, 'user-data'));
app.setPath('videos', path.join(home, 'Videos'));
fs.mkdirSync(app.getPath('userData'), { recursive: true });
const mode = process.env.ORBIT_SMOKE_MODE || 'selection';
fs.writeFileSync(path.join(app.getPath('userData'), 'settings.json'), JSON.stringify({
  welcomeShown: true, captureMode: mode, cameraOn: true, microphoneOn: true, resolution: 'p720', framesPerSecond: 30, aspect: 'widescreen',
}));
process.env.ORBIT_SMOKE_EXPORT = path.join(out, 'export.mp4');
app.commandLine.appendSwitch('use-fake-device-for-media-stream');
app.commandLine.appendSwitch('use-fake-ui-for-media-stream');

// Never hang CI.
setTimeout(() => {
  console.error('[smoke] timed out');
  app.exit(2);
}, 150000).unref();

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log('[smoke]', ...a);

async function shot(win, name) {
  if (!win || win.isDestroyed()) return;
  const image = await win.webContents.capturePage();
  fs.writeFileSync(path.join(out, `${name}.png`), image.toPNG());
}

// Electron doesn't emit "ready" until the entry module finishes evaluating, so no top-level await.
app.whenReady().then(run).catch((error) => {
  console.error('[smoke] failed', error);
  app.exit(1);
});

async function run() {
for (let i = 0; i < 50 && !globalThis.orbitApp; i++) await sleep(100);
const { coordinator } = globalThis.orbitApp;

// Something moving on the "desktop" so the recording has content.
const desk = new BrowserWindow({ x: 0, y: 0, width: 1600, height: 900, show: true, frame: false, backgroundColor: '#204060' });
desk.loadURL('data:text/html,' + encodeURIComponent(`<body style="margin:0;background:linear-gradient(90deg,#1d4e89,#00b2ca,#7dcfb6,#fbd1a2,#f79256)"><div id=b style="position:absolute;top:300px;left:0;width:120px;height:120px;background:#fff;border-radius:16px;font:bold 40px sans-serif;display:flex;align-items:center;justify-content:center">0</div><script>let t=0;setInterval(()=>{t++;b.style.left=(t*7%1500)+'px';b.textContent=t},33)</script></body>`));
await sleep(1500);

coordinator.showToolbar();
await sleep(2500);
await shot(coordinator.toolbar, 'toolbar');
await shot(coordinator.area?.win, 'area');
await shot(coordinator.bubble?.win, 'bubble');
coordinator.bubble.resizeTo(260);
await sleep(300);
const resized = coordinator.bubble.bounds.width === 260 && coordinator.bubble.bounds.height === 260;

const finished = new Promise((resolve) => coordinator.once('finished', resolve));
await coordinator.startRecording();
log('phase after start', coordinator.phase);
// Drag the bubble around while recording.
const area = coordinator.session?.area;
for (let i = 0; i < 30 && coordinator.bubble; i++) {
  const b = coordinator.bubble.bounds;
  coordinator.bubble.win.setBounds({ ...b, x: Math.round(area.x + (area.width - b.width) * (i / 30)), y: Math.round(area.y + 20) });
  await sleep(100);
}
await shot(coordinator.stopPill, 'stop');
await sleep(1000);
coordinator.stopRecording();
const folder = await finished;
log('folder', folder);
const project = JSON.parse(fs.readFileSync(path.join(folder, 'project.json'), 'utf8'));

await sleep(2500);
const editor = BrowserWindow.getAllWindows().find((w) => w.webContents.getURL().includes('editor.html'));
await shot(editor, 'editor');
const editorState = await editor.webContents.executeJavaScript('JSON.stringify((({exporting, hasCamera, duration, renderSize, error, cameraDuration}) => ({exporting, hasCamera, duration, renderSize, error, cameraDuration}))(orbitEditor.state()))');
log('editor', editorState);
await editor.webContents.executeJavaScript('orbitEditor.startExport()');
for (let i = 0; i < 600; i++) {
  const exporting = await editor.webContents.executeJavaScript('orbitEditor.state().exporting');
  if (exporting === null && fs.existsSync(process.env.ORBIT_SMOKE_EXPORT)) break;
  await sleep(250);
}
const exported = process.env.ORBIT_SMOKE_EXPORT;
const checks = {
  screenFile: fs.statSync(path.join(folder, project.screenFile)).size > 0,
  cameraFile: Boolean(project.camera) && fs.statSync(path.join(folder, project.camera.file)).size > 0,
  bubblePath: project.bubbleTrack.keyframes.length > 1,
  exported: fs.existsSync(exported) && fs.statSync(exported).size > 0,
  bubbleResized: resized,
};
console.log(JSON.stringify({ out, folder, files: fs.readdirSync(folder), checks, export: exported }, null, 2));
const ok = Object.values(checks).every(Boolean);
console.log(ok ? '[smoke] OK' : '[smoke] FAILED');
app.exit(ok ? 0 : 1);
}
