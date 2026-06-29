$ErrorActionPreference = "Stop"

# Ensure winget is available
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $winget) {
    Write-Error "Winget not found"
    exit 1
}

Write-Output "Installing Steam via Winget..."

winget install --id Valve.Steam --exact --silent --accept-package-agreements --accept-source-agreements

exit 0