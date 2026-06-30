#Uninstall script for Steam via Winget
$ErrorActionPreference = "Stop"

# Ensure winget is available
$Winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $Winget) {
    Write-Error "Winget not found"
    exit 1
}

Write-Output "Uninstalling Steam via Winget..."

winget uninstall --id Valve.Steam --exact --silent

#This will indicate if the uninstall was successful or not and report back to intune
exit $LASTEXITCODE