$ErrorActionPreference = "Stop"
# https://github.com/microsoft/winget-pkgs/tree/master/manifests/v/Valve/Steam/
$PackageId    = "Valve.Steam"
$PackageScope = "machine"

$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogPath "Winget-$PackageId-Install.log"

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")][string]$Level = "INFO"
    )
    $Entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Output $Entry
    Add-Content -Path $LogFile -Value $Entry -Encoding UTF8
}

Write-Log "===== Script Started ====="

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # Pick the newest installed App Installer by version, not by string order
    $Winget = Get-ChildItem "C:\Program Files\WindowsApps" -Directory `
            -Filter "Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
        Sort-Object { [version]($_.Name -split '_')[1] } -Descending |
        Select-Object -First 1 |
        ForEach-Object { Join-Path $_.FullName "winget.exe" }

    if (-not $Winget -or -not (Test-Path $Winget)) {
        Write-Log "Winget not found" -Level ERROR
        exit 1
    }

    Write-Log "Winget found: $Winget"

    $Arguments = @(
        "install"
        "--id", $PackageId
        "--exact"
        "--source", "winget"
        "--silent"
        "--disable-interactivity"
        "--accept-package-agreements"
        "--accept-source-agreements"
        "--scope", $PackageScope
    )

    Write-Log "Running: winget $($Arguments -join ' ')"

    # Native stderr must not become a terminating error here
    $ErrorActionPreference = "Continue"
    $Output   = & $Winget @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"

    $Output |
        ForEach-Object { "$_".Trim() } |
        Where-Object { $_ -and $_ -notmatch '^[-\\|/]$' -and $_ -notmatch '^[█▒\s]+' } |
        ForEach-Object { Write-Log $_ }

    Write-Log "Winget exit code: $ExitCode"
    Write-Log "===== Script Finished ====="
    exit $ExitCode
}
catch {
    Write-Log "Unhandled exception: $($_.Exception.Message)" -Level ERROR
    exit 1
}