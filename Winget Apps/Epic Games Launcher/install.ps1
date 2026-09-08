$ErrorActionPreference = "Stop"
# https://github.com/microsoft/winget-pkgs/tree/master/manifests/e/EpicGames/EpicGamesLauncher
$PackageName  = "EpicGames.EpicGamesLauncher"
$PackageArch  = "x64"
$PackageScope = "machine"

# Logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogPath "Winget-$($PackageName)-Install.log"

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Entry = "[$Timestamp] [$Level] $Message"

    Write-Output $Entry
    Add-Content -Path $LogFile -Value $Entry
}


Write-Log "===== Script Started ====="

try {
    # Ensure winget exists
    $Winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"

    if (-not $Winget) {
        Write-Log "ERROR: Winget not found" -Level ERROR
        exit 1
    }

    if ($Winget.count -gt 1) {
        $Winget = $Winget[-1].Path
    }

    Write-Log "Winget found: $($Winget)"

    #Structure our winget arguments so we can capture the outputs from winget
    $Arguments = @(
        "install"
        "--id", "$($PackageName)"
        "--exact"
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
        "--scope", "$($PackageScope)"
    )

    Write-Log "Running: winget $($Arguments -join ' ')"

    #This captures all the console prints from winget so we can log them
    $Output = & $Winget @Arguments 2>&1

    #Obviously this can only run after winget has "exited" 
    $Output | ForEach-Object {
        Write-Log $_
    }

    $ExitCode = $LASTEXITCODE

    Write-Log "Winget exit code: $ExitCode"
    Write-Log "===== Script Finished ====="

    exit $ExitCode
}
catch {
    Write-Log "Unhandled exception:" -Level ERROR
    Write-Log $_.Exception.Message -Level ERROR
    exit 1
}