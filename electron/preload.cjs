const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("focusCorner", {
  isDesktop: true,
  platform: process.platform,
  setLaunchAtLogin: (enabled) => ipcRenderer.invoke("launch-at-login", !!enabled),
  saveData: (data) => ipcRenderer.invoke("save-data", data),
  onToggleNotes: (cb) => {
    const handler = () => cb();
    ipcRenderer.on("toggle-notes", handler);
    return () => ipcRenderer.removeListener("toggle-notes", handler);
  },
});
