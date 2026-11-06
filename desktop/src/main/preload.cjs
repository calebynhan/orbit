// The only bridge between Orbit's pages and the main process.
const { contextBridge, ipcRenderer } = require('electron');

const allowedPrefixes = ['app:', 'toolbar:', 'area:', 'bubble:', 'recorder:', 'stop:', 'editor:', 'file:', 'welcome:'];
const allowed = (channel) => typeof channel === 'string' && allowedPrefixes.some((p) => channel.startsWith(p));

contextBridge.exposeInMainWorld('orbit', {
  platform: process.platform,
  invoke(channel, ...args) {
    if (!allowed(channel)) return Promise.reject(new Error(`Blocked channel ${channel}`));
    return ipcRenderer.invoke(channel, ...args);
  },
  send(channel, ...args) {
    if (allowed(channel)) ipcRenderer.send(channel, ...args);
  },
  on(channel, callback) {
    if (!allowed(channel)) return () => {};
    const listener = (_event, ...args) => callback(...args);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
  },
});
