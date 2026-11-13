param([string[]]$Packages = @("LocalSend.LocalSend", "EpicGames.EpicGamesLauncher", "GitHub.GitHubDesktop", "VoltKraft.ImmichFolderWatch", "Synology.DriveClient"))

$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogPath "Winget-Upgrade.log"
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $Entry = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Output $Entry
    Add-Content -Path $LogFile -Value $Entry -Encoding UTF8
}

$Winget = Get-ChildItem "C:\Program Files\WindowsApps" -Directory `
        -Filter "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.Name -split '_')[1] } -Descending |
    Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName "winget.exe" }

if (-not $Winget -or -not (Test-Path $Winget)) { Write-Log "winget not found"; exit 1 }

# 0 = upgraded, -1978335189 (0x8A15002B) = no applicable upgrade
$OkCodes = @(0, -1978335189)
$Failed  = 0
$ErrorActionPreference = "Continue"

foreach ($Id in $Packages) {
    Write-Log "Upgrading $Id"
    $Out = & $Winget upgrade --id $Id --exact --source winget --silent --disable-interactivity `
               --accept-package-agreements --accept-source-agreements 2>&1
    $Code = $LASTEXITCODE
    $Out | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '^[-\\|/]$' } |
        ForEach-Object { Write-Log $_ }
    Write-Log "$Id exit code: $Code"
    if ($OkCodes -notcontains $Code) { $Failed++ }
}

if ($Failed -gt 0) { exit 1 }
exit 0