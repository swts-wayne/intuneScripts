#Uninstall script for Local Send via Winget
$Winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $Winget) {
    exit 1
}

winget uninstall --id LocalSend.LocalSend --exact --silent

#This will indicate if the uninstall was successful or not and report back to intune
exit $LASTEXITCODE