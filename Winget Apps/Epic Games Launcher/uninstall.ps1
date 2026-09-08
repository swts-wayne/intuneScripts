#Uninstall script for Epic Games Launcher via Winget
$ErrorActionPreference = "Stop"

$PackageName  = "EpicGames.EpicGamesLauncher"

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