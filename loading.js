// loading.js -- 环境依赖配置面板的渲染逻辑
// 数据来自主进程 main.js 的 reportStatus() / reportLog()，经 preload.js 暴露的两个订阅进入本页。
const STAGE_TEXT = {
  boot: '正在准备启动窗口…',
  resolve: '正在解析运行环境路径…',
  check: '正在校验环境依赖…',
  spawn: '正在启动 DSH 本地服务…',
  'server-ready': '本地服务已就绪，正在建立连接…',
  workspace: '正在准备工作区与会话…',
  ready: '环境就绪，正在进入 DSH…',
  error: '启动失败，详情见下方日志',
}

const DEPENDENCIES = ['node', 'runtime', 'entry', 'server', 'workspace']

const stageEl = document.getElementById('stage')
const logEl = document.getElementById('log')

function renderStage(stage) {
  if (stageEl) stageEl.textContent = STAGE_TEXT[stage] || '正在启动…'
}

function renderDependency(key, info) {
  const row = document.getElementById('row-' + key)
  if (!row) return
  const data = info || {}
  const pathEl = row.querySelector('.path')
  const badge = row.querySelector('.badge')
  if (pathEl && data.path) pathEl.textContent = data.path
  if (!badge) return
  if (data.ok === true) {
    badge.textContent = '就绪'
    badge.className = 'badge ok'
  } else if (data.ok === false) {
    badge.textContent = '缺失'
    badge.className = 'badge bad'
  } else {
    badge.textContent = '检测中'
    badge.className = 'badge'
  }
}

function render(state) {
  if (!state) return
  renderStage(state.stage)
  for (const key of DEPENDENCIES) renderDependency(key, state[key])
}

function appendLog(line) {
  if (!logEl || line === undefined || line === null) return
  logEl.textContent += String(line) + '\n'
  if (logEl.textContent.length > 24000) logEl.textContent = logEl.textContent.slice(-24000)
  logEl.scrollTop = logEl.scrollHeight
}

if (window.dshDesktop) {
  if (typeof window.dshDesktop.onStatus === 'function') window.dshDesktop.onStatus(render)
  if (typeof window.dshDesktop.onLog === 'function') window.dshDesktop.onLog(appendLog)
}

appendLog('[env] 窗口已就绪，等待主进程上报环境依赖信息')
