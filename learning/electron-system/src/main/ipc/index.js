const { ipcMain } = require('electron')
const { IPC_CHANNELS } = require('../../shared/ipc-contracts')

function registerIpcHandlers() {
  ipcMain.handle(IPC_CHANNELS.GET_SYSTEM_INFO, async () => {
    return {
      platform: process.platform,
      nodeVersion: process.versions.node,
      electronVersion: process.versions.electron
    }
  })
}

module.exports = { registerIpcHandlers }
