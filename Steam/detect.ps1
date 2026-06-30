#check if the steam.exe exists
$steamExe = "$env:ProgramFiles(x86)\Steam\Steam.exe"

if (Test-Path $steamExe) {
    Write-Output "Installed"
    exit 0
} else {
    exit 1
}