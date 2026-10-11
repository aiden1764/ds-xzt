@echo off
setlocal
title ds-xzt one-click setup
set "PS1=%TEMP%\ds-xzt-launch.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8);$i=$c.LastIndexOf('#' + ':PAYLOAD');if($i -lt 0){exit 2};$t=$c.Substring($c.IndexOf([char]10,$i)+1);[IO.File]::WriteAllText('%PS1%',$t,(New-Object System.Text.UTF8Encoding($true)))"
if errorlevel 1 (
  echo.
  echo   Failed to prepare the launcher. Please re-download this file.
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"
del "%PS1%" >nul 2>&1

if not "%RC%"=="0" (
  echo.
  echo   Something went wrong. Press any key to close.
  echo.
  pause >nul
)

endlocal & exit /b %RC%
#:PAYLOAD
# ds-xzt 一键下载启动脚本
#
# 由 ds-xzt-oneclick-setup.cmd 调用（cmd 里内嵌的是本文件的 base64 编码副本），
# 也可以直接右键「使用 PowerShell 运行」。
#
# 做的事：下载便携包 -> 校验 SHA-256 -> 解压到用户目录 -> 建桌面快捷方式 -> 启动。
# 不需要管理员权限，不写注册表，删除安装目录即卸载。
#
# 可覆盖的环境变量（调试/重装用）：
#   DSXZT_DEST        安装目录，默认 %LOCALAPPDATA%\Programs\ds-xzt
#   DSXZT_ZIP         用本地已有的 zip，跳过下载
#   DSXZT_NO_LAUNCH   设为 1 时只安装不启动
#   DSXZT_NO_SHORTCUT 设为 1 时不创建桌面快捷方式

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 版本信息
$Repo   = 'aiden1764/ds-xzt'
$Tag    = 'v0.2.0'
$Asset  = 'ds-xzt-portable-0.2.0.zip'
$Sha256 = '0f11497dd1978bb0052ce898542fd63ed7222419e808a4f19f8235dd83400180'
$Url    = 'https://github.com/{0}/releases/download/{1}/{2}' -f $Repo, $Tag, $Asset

$Dest = if ($env:DSXZT_DEST) { $env:DSXZT_DEST } else { Join-Path $env:LOCALAPPDATA 'Programs\ds-xzt' }
$Work = Join-Path $env:LOCALAPPDATA 'ds-xzt-download'
$Zip  = if ($env:DSXZT_ZIP) { $env:DSXZT_ZIP } else { Join-Path $Work $Asset }

# CmdletBinding makes an accidental extra positional argument a loud error instead of a
# silently mis-bound colour (that bug cost one round of testing).
function Say {
  [CmdletBinding()]
  param(
    [Parameter(Position = 0)][string]$Text,
    [Parameter(Position = 1)][string]$Color = 'Gray'
  )
  Write-Host $Text -ForegroundColor $Color
}
function Fail([string]$Text) { Write-Host ''; Say ('[失败] ' + $Text) 'Red'; exit 1 }

function Format-Size([double]$Bytes) {
  if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
  return ('{0:N0} MB' -f ($Bytes / 1MB))
}

# ---------------------------------------------------------------- 环境检查
Write-Host ''
Say '============================================================' 'Cyan'
Say '  ds-xzt 一键下载启动' 'Cyan'
Say '============================================================' 'Cyan'
Write-Host ''

if (-not [Environment]::Is64BitOperatingSystem) {
  Fail 'ds-xzt 只有 64 位 Windows 版本。'
}
Say ('系统      ：64 位 Windows OK') 'Green'
Say ('安装目录  ：' + $Dest)

New-Item -ItemType Directory -Force -Path $Work | Out-Null

# ---------------------------------------------------------------- 下载
$NeedDownload = $true
if (Test-Path -LiteralPath $Zip) {
  $have = (Get-Item -LiteralPath $Zip).Length
  if ($env:DSXZT_ZIP) {
    Say ('使用本地文件：' + $Zip)
    $NeedDownload = $false
  } else {
    Say ('发现已下载的包（' + (Format-Size $have) + '），正在校验…')
  }
}

if ($NeedDownload -and (Test-Path -LiteralPath $Zip)) {
  $hash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLower()
  if ($hash -eq $Sha256) {
    Say '校验通过，跳过下载。' 'Green'
    $NeedDownload = $false
  } else {
    Say '本地包校验不一致，重新下载。' 'Yellow'
    Remove-Item -LiteralPath $Zip -Force
  }
}

if ($NeedDownload) {
  $free = (Get-PSDrive -Name ($Work.Substring(0, 1))).Free
  Say ('磁盘可用  ：' + (Format-Size $free))
  if ($free -lt 3GB) { Fail 'C 盘可用空间不足 3 GB，请先清理后再运行。' }

  Say ''
  Say '正在从 GitHub 下载（约 466 MB，视网速可能要几分钟）…' 'Cyan'
  Say $Url 'DarkGray'
  Write-Host ''

  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  } catch { }

  $wc = New-Object System.Net.WebClient
  $wc.Headers.Add('User-Agent', 'ds-xzt-oneclick')
  $part = $Zip + '.part'
  if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force }

  $task = $wc.DownloadFileTaskAsync($Url, $part)
  $spin = '|/-\'
  $i = 0
  while (-not $task.IsCompleted) {
    Start-Sleep -Milliseconds 400
    $cur = 0
    if (Test-Path -LiteralPath $part) { $cur = (Get-Item -LiteralPath $part).Length }
    Write-Host ("`r  " + $spin[$i % 4] + "  已下载 " + (Format-Size $cur)) -NoNewline
    $i++
  }
  Write-Host "`r                                                        " -NoNewline
  Write-Host "`r" -NoNewline

  try {
    $task.GetAwaiter().GetResult()
  } catch {
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    Fail ('下载失败：' + $_.Exception.Message + '。请检查网络，或手动从 Releases 页面下载 zip。')
  } finally {
    $wc.Dispose()
  }

  Move-Item -LiteralPath $part -Destination $Zip -Force
  Say ('下载完成  ：' + (Format-Size (Get-Item -LiteralPath $Zip).Length)) 'Green'
}

# ---------------------------------------------------------------- 校验
Say ''
Say '正在校验 SHA-256…'
$actual = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $Sha256) {
  if (-not $env:DSXZT_ZIP) {
    Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
    Fail ('包完整性校验失败，已删除损坏的文件，请重新运行。' + "`n        实际：" + $actual + "`n        期望：" + $Sha256)
  }
  Say ('注意：本地文件哈希与发布版本不同（实际 ' + $actual.Substring(0, 12) + '…），继续安装。') 'Yellow'
} else {
  Say ('校验通过  ：' + $Sha256) 'Green'
}

# ---------------------------------------------------------------- 解压
Say ''
Say '正在解压（约 37600 个文件，请稍候）…' 'Cyan'

$staging = Join-Path $Work 'staging'
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $staging | Out-Null

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
$extracted = $false

if (Test-Path -LiteralPath $tar) {
  # Windows 自带的 bsdtar 解 zip 很快
  & $tar -xf $Zip -C $staging 2>$null
  if ($LASTEXITCODE -eq 0) { $extracted = $true }
}

if (-not $extracted) {
  # 回退：.NET 逐条解压
  Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
  $archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
  try {
    $n = 0
    foreach ($entry in $archive.Entries) {
      $target = Join-Path $staging $entry.FullName
      if ($entry.FullName.EndsWith('/')) {
        New-Item -ItemType Directory -Force -Path $target | Out-Null
      } else {
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
      }
      $n++
      if ($n % 5000 -eq 0) { Write-Host ('  ' + $n + ' / ' + $archive.Entries.Count) }
    }
  } finally {
    $archive.Dispose()
  }
}

$inner = Join-Path $staging 'ds-xzt'
if (-not (Test-Path -LiteralPath (Join-Path $inner 'ds-xzt.exe'))) {
  Fail '解压结果不完整，没找到 ds-xzt.exe。'
}
Say ('解压完成  ：' + [math]::Round($sw.Elapsed.TotalSeconds) + ' 秒') 'Green'

# ---------------------------------------------------------------- 安装
Say ''
Say '正在安装到用户目录…'
if (Test-Path -LiteralPath $Dest) {
  Say '  发现旧版本，正在替换…' 'Yellow'
  try {
    Remove-Item -LiteralPath $Dest -Recurse -Force
  } catch {
    Fail ('无法替换旧版本（ds-xzt 可能正在运行，请先退出再重试）：' + $_.Exception.Message)
  }
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
Move-Item -LiteralPath $inner -Destination $Dest
Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue

$exe = Join-Path $Dest 'ds-xzt.exe'
Say ('已安装    ：' + $exe) 'Green'

# ---------------------------------------------------------------- 快捷方式
if ($env:DSXZT_NO_SHORTCUT -eq '1') {
  Say '已按要求跳过桌面快捷方式（DSXZT_NO_SHORTCUT=1）。' 'Cyan'
} else {
  try {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'ds-xzt.lnk'))
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = $Dest
    $lnk.Description = 'ds-xzt —— DeepSeek Harness 社区桌面版'
    $lnk.IconLocation = $exe + ',0'
    $lnk.Save()
    Say '桌面快捷方式已创建：ds-xzt' 'Green'
  } catch {
    Say ('桌面快捷方式创建失败（不影响使用）：' + $_.Exception.Message) 'Yellow'
  }
}

# ---------------------------------------------------------------- 启动
Say ''
if ($env:DSXZT_NO_LAUNCH -eq '1') {
  Say '已按要求跳过启动（DSXZT_NO_LAUNCH=1）。' 'Cyan'
} else {
  Say '正在启动 ds-xzt…' 'Cyan'
  Start-Process -FilePath $exe -WorkingDirectory $Dest
}

Write-Host ''
Say '============================================================' 'Cyan'
Say '  完成。以后从桌面 ds-xzt 图标启动即可。' 'Green'
Say '  首次启动会停在「环境依赖配置」面板，五项全就绪后自动进入 DSH。' 'Gray'
Say '============================================================' 'Cyan'
Write-Host ''
