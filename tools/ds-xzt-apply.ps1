# ds-xzt-apply.ps1  --  ASCII ONLY on purpose.
# Windows PowerShell 5.1 misreads BOM-less UTF-8, so this script contains no non-ASCII
# characters and discovers the Chinese-named exe/shortcut paths at runtime instead.
#
# Runs silently after the app exits and does:
#   1) replace resources\app.asar with the repacked app-new.asar
#      (startup animation -> environment dependency panel, plus the rename)
#   2) rename the main executable to ds-xzt.exe
#   3) update Start Menu / Desktop / taskbar-pinned shortcuts (name + target)
#   4) update the uninstall entry display name
#
# Revert: rename resources\app.asar.bak back to app.asar, and ds-xzt.exe back to the
# original exe name.

$root = 'D:\DSH\dsh-desktop-baiyun'
$res = Join-Path $root 'resources'
$ws = $PSScriptRoot
$log = Join-Path $ws 'ds-xzt-apply.log'

function Write-Line([string]$Message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Add-Content -LiteralPath $log -Encoding utf8
}

Write-Line 'apply script started; waiting for the app to exit'

# ---------- 1) replace app.asar ----------
$asar = Join-Path $res 'app.asar'
$bak = Join-Path $res 'app.asar.bak'
$new = Join-Path $ws 'app-new.asar'
for ($i = 0; $i -lt 3600; $i++) {
    try {
        if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force -ErrorAction Stop }
        Rename-Item -LiteralPath $asar -NewName 'app.asar.bak' -ErrorAction Stop
        break
    } catch {
        Start-Sleep -Seconds 3
    }
}
if (Test-Path -LiteralPath $bak) {
    Copy-Item -LiteralPath $new -Destination $asar -Force
    $h1 = (Get-FileHash -LiteralPath $new -Algorithm SHA256).Hash
    $h2 = (Get-FileHash -LiteralPath $asar -Algorithm SHA256).Hash
    Write-Line ("app.asar replaced; hash match = " + ($h1 -eq $h2))
} else {
    Write-Line 'ERROR: could not move app.asar aside (still locked?)'
}

# ---------- 2) rename the main executable ----------
$newExe = Join-Path $root 'ds-xzt.exe'
$renamed = $false
if (Test-Path -LiteralPath $newExe) {
    $renamed = $true
} else {
    $candidate = Get-ChildItem -LiteralPath $root -Filter '*.exe' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike 'Uninstall*' -and $_.Name -ne 'elevate.exe' -and $_.Length -gt 50MB } |
        Select-Object -First 1
    if ($candidate) {
        for ($i = 0; $i -lt 600; $i++) {
            try {
                Rename-Item -LiteralPath $candidate.FullName -NewName 'ds-xzt.exe' -ErrorAction Stop
                $renamed = $true
                Write-Line ("renamed exe: " + $candidate.Name + " -> ds-xzt.exe")
                break
            } catch {
                Start-Sleep -Seconds 3
            }
        }
    } else {
        Write-Line 'ERROR: main executable not found'
    }
}

# ---------- 3) shortcuts ----------
try {
    $shell = New-Object -ComObject WScript.Shell
    $dirs = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:PUBLIC 'Desktop'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    )
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
            $lnkPath = $_.FullName
            try {
                $lnk = $shell.CreateShortcut($lnkPath)
                if ($lnk.TargetPath -like '*dsh-desktop-baiyun*') {
                    if ($renamed) { $lnk.TargetPath = $newExe }
                    $lnk.Description = 'ds-xzt'
                    $lnk.Save()
                    Write-Line ("shortcut updated: " + $lnkPath)
                    if ($_.Name -ne 'ds-xzt.lnk') {
                        Rename-Item -LiteralPath $lnkPath -NewName 'ds-xzt.lnk' -ErrorAction Stop
                        Write-Line 'shortcut renamed to ds-xzt.lnk'
                    }
                    $parent = Split-Path $lnkPath -Parent
                    if ($parent -like '*Start Menu\Programs\*' -and (Split-Path $parent -Leaf) -ne 'ds-xzt' -and (Split-Path $parent -Leaf) -ne 'Programs') {
                        $grand = Split-Path $parent -Parent
                        try {
                            Rename-Item -LiteralPath $parent -NewName 'ds-xzt' -ErrorAction Stop
                            Write-Line ("start menu folder renamed -> " + (Join-Path $grand 'ds-xzt'))
                        } catch {
                            Write-Line ("start menu folder rename skipped: " + $_.Exception.Message)
                        }
                    }
                }
            } catch {
                Write-Line ("shortcut error: " + $lnkPath + " :: " + $_.Exception.Message)
            }
        }
    }
} catch {
    Write-Line ("shortcut pass failed: " + $_.Exception.Message)
}

# ---------- 4) uninstall entry ----------
$uninstallKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\a42ace24-22fa-52e3-a9cc-73a05f7bff17'
if (Test-Path $uninstallKey) {
    try {
        Set-ItemProperty -Path $uninstallKey -Name 'DisplayName' -Value 'ds-xzt' -ErrorAction Stop
        if ($renamed) { Set-ItemProperty -Path $uninstallKey -Name 'DisplayIcon' -Value ($newExe + ',0') -ErrorAction SilentlyContinue }
        Write-Line 'uninstall entry updated'
    } catch {
        Write-Line ("uninstall entry update failed: " + $_.Exception.Message)
    }
}

Write-Line 'apply script finished'
