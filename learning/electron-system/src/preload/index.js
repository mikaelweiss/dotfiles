const { contextBridge, ipcRenderer } = require('electron')
const { IPC_CHANNELS } = require('../shared/ipc-contracts')

contextBridge.exposeInMainWorld('api', {
  getSystemInfo: () => ipcRenderer.invoke(IPC_CHANNELS.GET_SYSTEM_INFO)
})
