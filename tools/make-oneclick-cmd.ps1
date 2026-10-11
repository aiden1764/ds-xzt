<#
  make-oneclick-cmd.ps1 -- build the self-contained one-click .cmd from a .ps1 launcher.

  Usage:
    powershell -ExecutionPolicy Bypass -File make-oneclick-cmd.ps1 `
      -LaunchScript .\source\tools\ds-xzt-launch.ps1 `
      -OutFile      .\ds-xzt-oneclick-setup.cmd

  Why the launcher is embedded instead of base64-encoded:
    -EncodedCommand would put ~24 KB on the command line and Windows caps that at 32767
    characters, so the script would break as soon as it grew. Instead the .cmd appends the
    launcher verbatim after a "#:PAYLOAD" marker and a one-line PowerShell command copies
    everything after that marker into a temp .ps1 and runs it.

  Encoding rules that make this work:
    * the .cmd itself is UTF-8 WITHOUT BOM and its batch section is pure ASCII, because
      cmd.exe decodes the file with the OEM code page (936 on zh-CN) and would mangle
      Chinese there
    * cmd never parses the payload: the batch section ends with "exit /b" before the marker
      is reached, so no %VAR% expansion or command interpretation happens inside it
    * the payload is extracted with [Text.Encoding]::UTF8 (decodes BOM-less UTF-8 correctly)
      and written back WITH a BOM, because Windows PowerShell 5.1 needs the BOM to read
      non-ASCII script text correctly
    * all Chinese user-facing text lives in the payload, so it prints correctly
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$LaunchScript,
  [Parameter(Mandatory = $true)][string]$OutFile,
  [string]$Marker = '#:PAYLOAD'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $LaunchScript)) { throw ('launcher not found: ' + $LaunchScript) }
$srcFull = (Resolve-Path -LiteralPath $LaunchScript).Path

# --- payload: launcher source, normalised to CRLF -------------------------------
$payload = [System.IO.File]::ReadAllText($srcFull, [System.Text.Encoding]::UTF8)
$payload = $payload -replace "`r`n", "`n"
$payload = $payload -replace "`n", "`r`n"
$payload = $payload.TrimStart("`r", "`n")
$payload = $payload.TrimEnd() + "`r`n"

if ($payload.IndexOf($Marker) -ge 0) {
  throw ('launcher source must not contain the payload marker ' + $Marker)
}

# --- batch section: ASCII only, must never fall through into the payload ---------
$header = @'
@echo off
setlocal
title ds-xzt one-click setup
set "PS1=%TEMP%\ds-xzt-launch.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8);$i=$c.LastIndexOf(MARKER);if($i -lt 0){exit 2};$t=$c.Substring($c.IndexOf([char]10,$i)+1);[IO.File]::WriteAllText('%PS1%',$t,(New-Object System.Text.UTF8Encoding($true)))"
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

'@

# The search expression is written as a concatenation so the marker string itself never
# appears contiguously inside the batch section -- otherwise IndexOf/LastIndexOf could
# match the header's own literal instead of the real marker line.
$markerExpression = "'#' + '" + $Marker.Substring(1) + "'"
$header = $header.Replace('MARKER', $markerExpression)
$header = $header -replace "`r`n", "`n"
$header = $header -replace "`n", "`r`n"

$cmd = $header + $Marker + "`r`n" + $payload

# --- write UTF-8 without BOM ----------------------------------------------------
$outFull = [System.IO.Path]::GetFullPath($OutFile)
$outDir = Split-Path -Parent $outFull
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
if (Test-Path -LiteralPath $outFull) { Remove-Item -LiteralPath $outFull -Force }

[System.IO.File]::WriteAllText($outFull, $cmd, (New-Object System.Text.UTF8Encoding($false)))

# --- report ---------------------------------------------------------------------
$bytes = (Get-Item -LiteralPath $outFull).Length
$lines = ([System.IO.File]::ReadAllText($outFull, [System.Text.Encoding]::UTF8) -split "`n").Count
Write-Host ('built  : {0}' -f $outFull)
Write-Host ('size   : {0:N2} KB  ({1} bytes, {2} lines)' -f ($bytes / 1KB), $bytes, $lines)
Write-Host ('sha256 : {0}' -f (Get-FileHash -LiteralPath $outFull -Algorithm SHA256).Hash.ToLower())
