<#
  build-portable.ps1 -- package an installed ds-xzt desktop app into a portable zip.

  The script is intentionally ASCII-only: Windows PowerShell 5.1 misreads BOM-less
  UTF-8 files, so every non-ASCII name in the app tree is matched by pattern instead
  of being written literally.

  Usage:
    powershell -ExecutionPolicy Bypass -File build-portable.ps1 `
      -SourceDir 'D:\DSH\dsh-desktop-baiyun' `
      -OutFile   '.\ds-xzt-portable-0.2.0.zip'

  What it does:
    * walks SourceDir recursively and stores every file under a single top-level
      folder inside the zip (default: ds-xzt/), so extraction yields a clean folder
    * skips the rollback copies of the app bundle (app.asar.bak / app.asar.orig)
    * renames the NSIS uninstaller entry to "Uninstall ds-xzt.exe" so the archived
      package carries no leftover upstream branding
    * prints the SHA-256 of the finished archive
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$OutFile,
  [string]$RootName = 'ds-xzt',
  [string]$UninstallerName = 'Uninstall ds-xzt.exe'
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

$skipFiles = @('app.asar.bak', 'app.asar.orig')

$srcFull = (Resolve-Path -LiteralPath $SourceDir).Path.TrimEnd('\')
$outFull = [System.IO.Path]::GetFullPath($OutFile)
$outDir = Split-Path -Parent $outFull
if (-not (Test-Path -LiteralPath $outDir)) {
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}
if (Test-Path -LiteralPath $outFull) {
  Remove-Item -LiteralPath $outFull -Force
}

$files = @(
  Get-ChildItem -LiteralPath $srcFull -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $skipFiles -notcontains $_.Name }
)
$total = $files.Count
Write-Host ("source : {0}" -f $srcFull)
Write-Host ("output : {0}" -f $outFull)
Write-Host ("files  : {0}" -f $total)

$zip = [System.IO.Compression.ZipFile]::Open($outFull, [System.IO.Compression.ZipArchiveMode]::Create)
$done = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($srcFull.Length).TrimStart('\')
    $entryName = ($RootName + '\' + $rel).Replace('\', '/')

    if ($f.DirectoryName -eq $srcFull -and $f.Name -like 'Uninstall*.exe') {
      $entryName = $RootName + '/' + $UninstallerName
    }

    $entry = $zip.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Optimal)
    try { $entry.LastWriteTime = $f.LastWriteTime } catch { }

    $in = [System.IO.File]::OpenRead($f.FullName)
    try {
      $out = $entry.Open()
      try { $in.CopyTo($out) } finally { $out.Dispose() }
    } finally { $in.Dispose() }

    $done++
    if ($done % 2000 -eq 0) {
      Write-Host ("  {0}/{1}  {2:N0}s" -f $done, $total, $sw.Elapsed.TotalSeconds)
    }
  }
} finally {
  $zip.Dispose()
}

$len = (Get-Item -LiteralPath $outFull).Length
$hash = (Get-FileHash -LiteralPath $outFull -Algorithm SHA256).Hash
Write-Host ("entries: {0}" -f $done)
Write-Host ("size   : {0:N1} MB" -f ($len / 1MB))
Write-Host ("sha256 : {0}" -f $hash)
Write-Host ("elapsed: {0:N0}s" -f $sw.Elapsed.TotalSeconds)
