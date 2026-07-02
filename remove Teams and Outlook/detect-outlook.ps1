$Outlook = Get-AppxPackage -AllUsers -Name "Microsoft.OutlookForWindows" -ErrorAction SilentlyContinue

if ($Outlook) {
    Write-Host "New Outlook detected."
    exit 0
}
else {
    Write-Host "New Outlook not detected."
    exit 1
}