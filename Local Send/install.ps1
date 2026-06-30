$ErrorActionPreference = "Stop"

# Ensure Winget is available
$Winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $Winget) {
    Write-Error "Winget not found"
    exit 1
}

Write-Output "Installing Local Send via Winget..."

winget install --id LocalSend.LocalSend --exact --silent --accept-package-agreements --accept-source-agreements

exit $LASTEXITCODE