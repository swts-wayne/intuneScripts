#Uninstall script for Local Send via Winget
$ErrorActionPreference = "Stop"

$PackageName  = "LocalSend.LocalSend"

# Resolve winget.exe
$Winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
if ($Winget.count -gt 1) {
    $Winget = $Winget[-1].Path
}

if (!$Winget) {
    Write-Error "winget not installed"
} else {
    # uninstall via winget
    & $Winget uninstall --silent --exact --id $PackageName
}

exit $LASTEXITCODE