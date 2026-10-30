#Detection script for Makeblock.xToolStudio via Winget
#Requires a machine-wide (HKLM) install, all-users shortcuts and the staged RNDIS driver
$ErrorActionPreference = "Stop"

$PackageName  = "Makeblock.xToolStudio"
$ShortcutPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\xTool Studio.lnk"   # match the name the installer/remediation creates
$DriverInf    = "rndis.inf"
$DriverMin    = [version]'1.0.0.0'

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

# 4. RNDIS driver staged in the driver store (third-party packages only)
$driverFound = Get-WindowsDriver -Online |
    Where-Object {
        (Split-Path $_.OriginalFileName -Leaf).ToLower() -eq $DriverInf -and
        [version]$_.Version -ge $DriverMin
    }

if ($wingetFound -and $hklmFound -and $shortcutFound -and $driverFound) {
    Write-Host "found it!"
    exit 0
}

exit 1