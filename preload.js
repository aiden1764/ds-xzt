const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('dshDesktop', {
  retry: () => ipcRenderer.invoke('app:retry'),
  // 环境依赖配置面板的订阅入口（见 loading.js）
  onStatus: callback => {
    if (typeof callback !== 'function') return
    ipcRenderer.on('startup:status', (_event, state) => callback(state))
  },
  onLog: callback => {
    if (typeof callback !== 'function') return
    ipcRenderer.on('startup:log', (_event, line) => callback(line))
  },
})
