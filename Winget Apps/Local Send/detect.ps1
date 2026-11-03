$PackageId   = "LocalSend.LocalSend"
$InstallPath = "C:\Program Files\LocalSend\localsend_app.exe"

# Not installed = not detected
if (-not (Test-Path $InstallPath)) { exit 1 }

$Winget = Get-ChildItem "C:\Program Files\WindowsApps" -Directory `
        -Filter "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.Name -split '_')[1] } -Descending |
    Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName "winget.exe" }

# No winget means the install script couldn't upgrade anyway, so don't loop on it
if (-not $Winget -or -not (Test-Path $Winget)) {
    Write-Output "Installed, winget unavailable"
    exit 0
}

$ErrorActionPreference = "Continue"
$Output = & $Winget list --id $PackageId --exact --source winget --upgrade-available `
              --accept-source-agreements --disable-interactivity 2>&1
$Exit = $LASTEXITCODE

# Package listed as upgradable = not detected, so Intune runs the install
if ($Exit -eq 0 -and ($Output | Out-String) -match [regex]::Escape($PackageId)) { exit 1 }

Write-Output "$PackageId installed and up to date"
exit 0