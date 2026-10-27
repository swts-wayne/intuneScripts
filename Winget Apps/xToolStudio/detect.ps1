<#Detection script for Makeblock.xToolStudio via Winget
#Requires a machine-wide (HKLM) install with all-users shortcuts, so per-user installs under SYSTEM fail detection#>
$ErrorActionPreference = "Stop"

$PackageName  = "Makeblock.xToolStudio"
$ShortcutPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\xTool Studio.lnk"   # match the name the installer/remediation creates

# Resolve winget.exe
$Winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue
if ($Winget.count -gt 1) {
    $Winget = $Winget[-1].Path
}

if (!$Winget) {
    Write-Error "winget not installed"
    exit 1
}

# 1. winget sees the package
$wingetPrg_Existing = & $Winget list --id $PackageName --exact --accept-source-agreements
$wingetFound = ($wingetPrg_Existing -like "*$PackageName*")

# 2. uninstall entry is machine-wide (HKLM), not in SYSTEM's hive
$hklmFound = Get-ItemProperty `
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
    -ErrorAction SilentlyContinue |
    Where-Object DisplayName -like '*xTool*'

# 3. all-users Start menu shortcut exists
$shortcutFound = Test-Path $ShortcutPath

if ($wingetFound -and $hklmFound -and $shortcutFound) {
    Write-Host "found it!"
    exit 0
}

exit 1