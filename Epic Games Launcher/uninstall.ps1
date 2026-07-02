#Uninstall script for Epic Games Launcher via Winget
$ErrorActionPreference = "Stop"

# Ensure winget is available
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $winget) {
    Write-Error "Winget not found"
    exit 1
}

Write-Output "Uninstalling Epic Games Launcher via Winget..."

winget uninstall --id EpicGames.EpicGamesLauncher --exact --silent

#This will indicate if the uninstall was successful or not and report back to intune
exit $LASTEXITCODE