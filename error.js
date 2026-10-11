const message = document.getElementById('message')
const retryButton = document.getElementById('reload')
const quitButton = document.getElementById('quit')
const query = new URLSearchParams(window.location.search)

message.textContent = query.get('message') || '未知启动错误'

retryButton.addEventListener('click', async () => {
  if (!window.dshDesktop?.retry) return
  retryButton.disabled = true
  retryButton.textContent = '正在启动...'
  try {
    await window.dshDesktop.retry()
  } finally {
    retryButton.disabled = false
    retryButton.textContent = '重试'
  }
})

quitButton.addEventListener('click', () => window.close())
