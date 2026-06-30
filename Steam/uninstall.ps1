#Uninstall script for Steam via Winget
$Winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $Winget) {
    exit 1
}

winget uninstall --id Valve.Steam --exact --silent