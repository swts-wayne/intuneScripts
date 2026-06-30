$ErrorActionPreference = "Stop"

# Ensure winget is available
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $winget) {
    Write-Error "Winget not found"
    exit 1
}

Write-Output "Uninstalling Epic Games Launcher via Winget..."

winget uninstall --id EpicGames.EpicGamesLauncher --exact --silent

exit $LASTEXITCODE