#Uninstall script for Synology Drive Client via Winget
$ErrorActionPreference = "Stop"

$PackageName = "Synology.DriveClient"

$Winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"

if ($Winget.Count -gt 1) {
    $Winget = $Winget[-1].Path
}

if (!$Winget) {
    Write-Error "winget not installed"
    exit 1
}

& $Winget uninstall --silent --exact --id $PackageName

exit $LASTEXITCODE