$ErrorActionPreference = "Stop"
$PackageId = "BlenderFoundation.Blender"

$Winget = Get-ChildItem "C:\Program Files\WindowsApps" -Directory `
        -Filter "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.Name -split '_')[1] } -Descending |
    Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName "winget.exe" }

if (-not $Winget -or -not (Test-Path $Winget)) { exit 1 }

$ErrorActionPreference = "Continue"
& $Winget uninstall --id $PackageId --exact --silent --disable-interactivity --accept-source-agreements 2>&1 | Out-Null
$ExitCode = $LASTEXITCODE

# 0x8A150014 = no installed package found, which is fine for an uninstall
if ($ExitCode -eq -1978335212) { $ExitCode = 0 }
exit $ExitCode