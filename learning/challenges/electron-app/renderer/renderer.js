async function init() {
  const info = await window.electronAPI.getAppInfo()
  document.getElementById('app-info').textContent = `${info.name} v${info.version}`
}

init()
