#Install Epic Games Launcher
$ErrorActionPreference = "Stop"

# Ensure winget is available
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $winget) {
    Write-Error "Winget not found"
    exit 1
}

Write-Output "Installing Epic Games Launcher via Winget..."

winget install --id EpicGames.EpicGamesLauncher --exact --silent --accept-package-agreements --accept-source-agreements

exit $LASTEXITCODE