$Teams = Get-AppxPackage -AllUsers -Name "MSTeams" -ErrorAction SilentlyContinue

if ($Teams) {
    Write-Host "New Teams detected."
    exit 0
}
else {
    Write-Host "New Teams not detected."
    exit 1
}