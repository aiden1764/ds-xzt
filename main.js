const { app, BrowserWindow, dialog, ipcMain, session, shell } = require('electron')
const { spawn, spawnSync } = require('node:child_process')
const { randomUUID } = require('node:crypto')
const fs = require('node:fs')
const path = require('node:path')

let mainWindow = null
let dshProcess = null
let shuttingDown = false
let serverUrl = ''
let restarting = false

const DEFAULT_SESSION_ID = 'community.dsh.baiyun.default-session'

// --- 环境依赖配置上报 ---------------------------------------------------------
// loading.html 现在是「环境依赖配置」面板：主进程把每个依赖项的解析结果
// （实际路径 + 是否存在）和启动阶段实时推给它，并把 DSH 子进程日志转发到界面。
const startupState = {
  stage: 'boot',
  error: '',
  node: { label: 'Node 运行时', path: '', ok: null },
  runtime: { label: 'DSH 运行时', path: '', ok: null },
  entry: { label: 'DSH 入口', path: '', ok: null },
  server: { label: '本地服务', path: '', ok: null },
  workspace: { label: '工作区 / 会话', path: '', ok: null },
}

function sendToLoading(channel, payload) {
  if (!mainWindow || mainWindow.isDestroyed()) return
  const contents = mainWindow.webContents
  if (!contents || contents.isDestroyed()) return
  contents.send(channel, payload)
}

function reportStatus(patch) {
  if (patch) {
    for (const [key, value] of Object.entries(patch)) {
      const current = startupState[key]
      startupState[key] = (value && typeof value === 'object' && current && typeof current === 'object')
        ? { ...current, ...value }
        : value
    }
  }
  sendToLoading('startup:status', startupState)
}

function reportLog(line) {
  if (line === undefined || line === null) return
  const text = String(line).replace(/\s+$/, '')
  if (!text) return
  sendToLoading('startup:log', text)
}

function resolveNodeExecutable() {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'runtime', 'node.exe')
  }
  return process.env.DSH_NODE_EXE || path.join(
    process.env.ProgramFiles || 'C:\\Program Files',
    'nodejs',
    'node.exe',
  )
}

function resolveRuntimeRoot() {
  if (!app.isPackaged && process.env.DSH_RUNTIME_ROOT) {
    return path.resolve(process.env.DSH_RUNTIME_ROOT)
  }
  return app.isPackaged
    ? path.join(process.resourcesPath, 'dsh')
    : path.resolve(__dirname, '..')
}

function terminateDshProcess() {
  if (!dshProcess || dshProcess.exitCode !== null) return

  terminateChildTree(dshProcess)
  dshProcess = null
}

function terminateChildTree(child) {
  if (!child || child.exitCode !== null) return

  const pid = child.pid
  try {
    child.kill()
  } catch {
    // The process may already have exited between the state check and kill.
  }

  if (process.platform === 'win32' && pid) {
    const taskkill = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'taskkill.exe')
    spawnSync(taskkill, ['/pid', String(pid), '/t', '/f'], {
      timeout: 5000,
      windowsHide: true,
      stdio: 'ignore',
    })
  }
}

function showErrorPage(message) {
  reportStatus({ stage: 'error', error: message })
  if (!mainWindow || mainWindow.isDestroyed()) {
    dialog.showErrorBox('ds-xzt启动失败', message)
    return
  }
  mainWindow.loadFile(path.join(__dirname, 'error.html'), {
    query: { message },
  })
}

function waitForServer(child, timeoutMs = 60000) {
  return new Promise((resolve, reject) => {
    let stdout = ''
    let stderr = ''
    let settled = false
    let detectedUrl = ''

    const finish = (error, result) => {
      if (settled) return
      settled = true
      clearTimeout(timeout)
      if (error) reject(error)
      else resolve(result)
    }

    const timeout = setTimeout(() => {
      const details = stderr.trim() || stdout.trim() || 'ds-xzt未能在超时前完成启动。'
      finish(new Error(details.slice(-2000)))
    }, timeoutMs)

    child.stdout.on('data', chunk => {
      stdout = (stdout + chunk.toString()).slice(-20000)
      const matches = [...stdout.matchAll(/http:\/\/127\.0\.0\.1:(\d+)/g)]
      const candidate = matches.at(-1)
      if (candidate && Number(candidate[1]) > 0) detectedUrl = candidate[0]
    })
    child.stderr.on('data', chunk => {
      stderr = (stderr + chunk.toString()).slice(-20000)
    })
    child.once('error', error => finish(error))
    child.once('exit', code => {
      const details = stderr.trim() || stdout.trim() || `DSH exited with code ${code}.`
      finish(new Error(details.slice(-2000)))
    })

    async function poll() {
      if (settled) return
      if (shuttingDown) {
        finish(new Error('ds-xzt已退出。'))
        return
      }
      if (!detectedUrl) {
        setTimeout(poll, 100)
        return
      }
      try {
        const response = await fetch(detectedUrl)
        if (response.ok) {
          finish(null, detectedUrl)
          return
        }
      } catch {
        // Startup is asynchronous; the next interval retries the local endpoint.
      }
      setTimeout(poll, 200)
    }

    poll()
  })
}

async function startDsh() {
  reportStatus({ stage: 'resolve' })
  const runtimeRoot = resolveRuntimeRoot()
  const nodeExecutable = resolveNodeExecutable()
  const officialDshBin = path.join(runtimeRoot, 'node_modules', '@deepseek-ai', 'dsh', 'lib', 'bin.js')
  const sourceDshBin = path.join(runtimeRoot, 'apps', 'cli', 'lib', 'bin.js')
  const dshBin = fs.existsSync(officialDshBin) ? officialDshBin : sourceDshBin

  const nodeOk = fs.existsSync(nodeExecutable)
  const runtimeOk = fs.existsSync(runtimeRoot)
  const entryOk = fs.existsSync(dshBin)
  reportStatus({
    stage: 'check',
    node: { path: nodeExecutable, ok: nodeOk },
    runtime: { path: runtimeRoot, ok: runtimeOk },
    entry: { path: dshBin, ok: entryOk },
  })
  reportLog(`Node 运行时  ${nodeOk ? '就绪' : '缺失'}  ${nodeExecutable}`)
  reportLog(`DSH 运行时  ${runtimeOk ? '就绪' : '缺失'}  ${runtimeRoot}`)
  reportLog(`DSH 入口    ${entryOk ? '就绪' : '缺失'}  ${dshBin}`)

  for (const file of [nodeExecutable, dshBin]) {
    if (!fs.existsSync(file)) {
      reportStatus({ stage: 'error', error: `缺少内置依赖文件：${file}` })
      throw new Error(`Bundled DSH file is missing: ${file}`)
    }
  }

  serverUrl = ''
  const dshHome = path.join(app.getPath('userData'), 'dsh')
  fs.mkdirSync(dshHome, { recursive: true })

  terminateDshProcess()
  dshProcess = null

  const child = spawn(nodeExecutable, [
    dshBin,
    'web',
    '--no-open',
    '--host', '127.0.0.1',
    '--port', '0',
  ], {
    cwd: dshHome,
    env: {
      ...process.env,
      DSH_HOME: dshHome,
      DSH_TELEMETRY_DISABLED: '1',
      NO_COLOR: '1',
    },
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  dshProcess = child
  watchDshExit(child)

  reportStatus({ stage: 'spawn', server: { path: '127.0.0.1（等待端口分配）', ok: null } })
  reportLog(`$ ${path.basename(nodeExecutable)} ${path.basename(dshBin)} web --no-open --host 127.0.0.1 --port 0`)
  child.stdout.on('data', chunk => {
    for (const line of chunk.toString().split(/\r?\n/)) reportLog(line)
  })
  child.stderr.on('data', chunk => {
    for (const line of chunk.toString().split(/\r?\n/)) reportLog(line)
  })

  try {
    const url = await waitForServer(child)
    serverUrl = url
    reportStatus({ stage: 'server-ready', server: { path: url, ok: true } })
    reportLog(`本地服务已就绪  ${url}`)
    return url
  } catch (error) {
    dshProcess = null
    terminateChildTree(child)
    throw error
  }
}

async function callDshRpc(serverUrl, method, payload = {}) {
  const response = await fetch(new URL(`/api/${method}`, serverUrl), {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    signal: AbortSignal.timeout(5000),
    body: JSON.stringify({
      type: 'client-request',
      rpcId: randomUUID(),
      method,
      payload,
    }),
  })
  if (!response.ok) {
    throw new Error(`DSH RPC transport failed for ${method}: HTTP ${response.status}`)
  }

  const message = await response.json()
  if (message?.type !== 'server-response' || message.result?.ok !== true) {
    const error = message?.result?.ok === false ? message.result.error : undefined
    throw new Error(`DSH RPC failed for ${method}: ${error?.code ?? 'invalid response'} ${error?.message ?? ''}`.trim())
  }
  return message.result.value
}

function selectRecentWorkspace(workspaces, sessions) {
  let selected
  let selectedTime = Number.NEGATIVE_INFINITY

  for (const workspace of workspaces) {
    let latest = Number.NEGATIVE_INFINITY
    for (const sessionId of workspace.sessionIds ?? []) {
      const session = sessions.find(item => item?.sessionId === sessionId)
      const updatedAt = Number(session?.updatedAt)
      if (Number.isFinite(updatedAt)) latest = Math.max(latest, updatedAt)
    }
    if (latest === Number.NEGATIVE_INFINITY) {
      const createdAt = Date.parse(workspace.createdAt)
      if (Number.isFinite(createdAt)) latest = createdAt
    }
    if (selected === undefined || latest > selectedTime) {
      selected = workspace
      selectedTime = latest
    }
  }

  return selected
}

async function ensureDefaultWorkspace(serverUrl) {
  const workspaceList = await callDshRpc(serverUrl, 'workspace.list')
  const workspaces = Array.isArray(workspaceList?.items) ? workspaceList.items : []

  let workspace
  if (workspaces.length === 0) {
    const workspacePath = process.env.DSH_DEFAULT_WORKSPACE
      ? path.resolve(process.env.DSH_DEFAULT_WORKSPACE)
      : path.join(app.getPath('userData'), 'workspace')
    fs.mkdirSync(workspacePath, { recursive: true })

    const created = await callDshRpc(serverUrl, 'workspace.create', { path: workspacePath })
    workspace = created?.workspace
  } else {
    const initialSessionList = await callDshRpc(serverUrl, 'session.list')
    const initialSessions = Array.isArray(initialSessionList?.items) ? initialSessionList.items : []
    workspace = selectRecentWorkspace(workspaces, initialSessions)
  }

  if (!workspace?.workspaceId || typeof workspace.path !== 'string') {
    throw new Error('DSH RPC workspace resolution returned an invalid workspace')
  }

  reportStatus({ stage: 'workspace', workspace: { path: workspace.path, ok: true } })

  const sessionList = await callDshRpc(serverUrl, 'session.list')
  const sessions = Array.isArray(sessionList?.items) ? sessionList.items : []
  const archivedSessionIds = new Set(
    Array.isArray(workspaceList?.archivedSessionIds) ? workspaceList.archivedSessionIds : [],
  )
  const blankSession = sessions.find(session => (
    session?.blank === true
    && session.cwd === workspace.path
    && workspace.sessionIds?.includes(session.sessionId)
    && !archivedSessionIds.has(session.sessionId)
  ))
  if (blankSession !== undefined) {
    return { initialized: false, workspaceId: workspace.workspaceId, sessionId: blankSession.sessionId, reused: true }
  }

  const fixedSession = sessions.find(session => session?.sessionId === DEFAULT_SESSION_ID)
  const fixedSessionMatches = fixedSession?.blank === true
    && fixedSession.cwd === workspace.path
    && !archivedSessionIds.has(fixedSession.sessionId)
  const sessionId = fixedSession === undefined || fixedSessionMatches
    ? DEFAULT_SESSION_ID
    : `${DEFAULT_SESSION_ID}-${randomUUID()}`
  const createdSession = await callDshRpc(serverUrl, 'session.create', {
    workspaceId: workspace.workspaceId,
    sessionId,
  })
  if (createdSession?.sessionId !== sessionId) {
    throw new Error('DSH RPC session.create returned an unexpected session id')
  }
  return { initialized: true, workspaceId: workspace.workspaceId, sessionId, reused: false }
}

function watchDshExit(child) {
  child.once('exit', (code, signal) => {
    if (shuttingDown || dshProcess !== child || !serverUrl) return
    dshProcess = null
    const reason = signal ? `signal ${signal}` : `code ${code}`
    showErrorPage(`ds-xzt 已意外停止（${reason}）。`)
  })
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1000,
    minHeight: 680,
    title: 'ds-xzt',
    icon: path.join(__dirname, 'assets', 'icon.png'),
    show: false,
    backgroundColor: '#f7f7f8',
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      preload: path.join(__dirname, 'preload.js'),
    },
  })

  session.defaultSession.setPermissionRequestHandler((_webContents, permission, callback) => {
    const allowed = new Set(['clipboard-read', 'clipboard-sanitized-write', 'fullscreen'])
    callback(allowed.has(permission))
  })
  mainWindow.setMenuBarVisibility(false)
  mainWindow.webContents.on('will-attach-webview', event => event.preventDefault())
  mainWindow.webContents.on('will-navigate', (event, targetUrl) => {
    let targetOrigin
    let serverOrigin = ''
    try {
      targetOrigin = new URL(targetUrl).origin
      if (serverUrl) serverOrigin = new URL(serverUrl).origin
    } catch {
      event.preventDefault()
      return
    }
    if (serverOrigin && targetOrigin === serverOrigin) return
    event.preventDefault()
    if (/^https?:\/\//.test(targetUrl)) shell.openExternal(targetUrl)
  })
  mainWindow.webContents.setWindowOpenHandler(({ url: targetUrl }) => {
    if (/^https?:\/\//.test(targetUrl)) shell.openExternal(targetUrl)
    return { action: 'deny' }
  })
  mainWindow.webContents.on('did-fail-load', (_event, code, description, validatedUrl, isMainFrame) => {
    if (!isMainFrame || shuttingDown || !mainWindow) return
    if (serverUrl && validatedUrl.startsWith(serverUrl)) {
      showErrorPage(`${code}: ${description}`)
    }
  })
  mainWindow.webContents.on('did-finish-load', () => reportStatus())
  mainWindow.once('ready-to-show', () => mainWindow.show())
  mainWindow.on('closed', () => {
    mainWindow = null
  })
  mainWindow.loadFile(path.join(__dirname, 'loading.html'))
}

async function startDshWithRetry() {
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    if (shuttingDown) throw new Error('ds-xzt已退出。')
    try {
      const url = await startDsh()
      try {
        await ensureDefaultWorkspace(url)
      } catch (error) {
        // Workspace bootstrap is a usability recovery path, not a startup gate.
        console.warn('DSH default workspace bootstrap skipped:', error)
        reportStatus({ workspace: { path: '已跳过（不影响启动）', ok: false } })
      }
      reportStatus({ stage: 'ready' })
      return url
    } catch (error) {
      if (attempt === 2 || shuttingDown) throw error
      await new Promise(resolve => setTimeout(resolve, 350))
    }
  }
  throw new Error('ds-xzt连续启动失败。')
}

function navigateToServer(url) {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.loadURL(url)
  }
}

function run() {
  createWindow()
  startDshWithRetry()
    .then(navigateToServer)
    .catch(error => showErrorPage(error instanceof Error ? error.message : String(error)))
}

ipcMain.handle('app:retry', async () => {
  if (restarting || !mainWindow || mainWindow.isDestroyed()) return false
  restarting = true
  mainWindow.loadFile(path.join(__dirname, 'loading.html'))
  try {
    const url = await startDshWithRetry()
    await mainWindow.loadURL(url)
    return true
  } catch (error) {
    showErrorPage(error instanceof Error ? error.message : String(error))
    return false
  } finally {
    restarting = false
  }
})

const hasSingleInstanceLock = app.requestSingleInstanceLock()
if (!hasSingleInstanceLock) {
  app.quit()
} else {
  app.on('second-instance', () => {
    if (!mainWindow) return
    if (mainWindow.isMinimized()) mainWindow.restore()
    mainWindow.show()
    mainWindow.focus()
  })

  app.whenReady().then(() => {
    app.setAppUserModelId('community.dsh.baiyun')
    run()
  })
}

app.on('before-quit', () => {
  shuttingDown = true
  terminateDshProcess()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
