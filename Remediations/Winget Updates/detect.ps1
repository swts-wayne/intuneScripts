# Packages this remediation is responsible for
$Packages = @("LocalSend.LocalSend", "EpicGames.EpicGamesLauncher", "GitHub.GitHubDesktop", "VoltKraft.ImmichFolderWatch", "Synology.DriveClient")

$Winget = Get-ChildItem "C:\Program Files\WindowsApps" -Directory `
        -Filter "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.Name -split '_')[1] } -Descending |
    Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName "winget.exe" }

# No winget means remediation couldn't act either, so report compliant
if (-not $Winget -or -not (Test-Path $Winget)) { Write-Output "winget not found"; exit 0 }

$ErrorActionPreference = "Continue"
$Pending = @()
foreach ($Id in $Packages) {
    $Out = & $Winget list --id $Id --exact --source winget --upgrade-available `
               --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $Out -match [regex]::Escape($Id)) { $Pending += $Id }
}

if ($Pending.Count -gt 0) { Write-Output "Upgrades pending: $($Pending -join ', ')"; exit 1 }
Write-Output "All up to date"
exit 0