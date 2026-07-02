# Remove Outlook for Windows (Store app)
Get-AppxPackage -AllUsers *OutlookForWindows* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

Get-AppxProvisionedPackage -Online |
Where-Object {$_.DisplayName -like "*OutlookForWindows*"} |
Remove-AppxProvisionedPackage -Online