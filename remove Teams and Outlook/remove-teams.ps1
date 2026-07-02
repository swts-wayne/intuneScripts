# Remove New Teams Machine-Wide Installer
Get-AppxPackage -AllUsers *MSTeams* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

Get-AppxProvisionedPackage -Online |
Where-Object {$_.DisplayName -like "*MSTeams*"} |
Remove-AppxProvisionedPackage -Online