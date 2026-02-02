async function init() {
  const info = await window.api.getSystemInfo()

  document.getElementById('system-info').innerHTML = `
    <div>Platform: ${info.platform}</div>
    <div>Node: ${info.nodeVersion}</div>
    <div>Electron: ${info.electronVersion}</div>
  `
}

init()
