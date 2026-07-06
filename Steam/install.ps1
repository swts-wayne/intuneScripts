$ErrorActionPreference = "Stop"

# Ensure winget is available
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue

if (-not $winget) {
    Write-Error "Winget not found"
    exit 1
}

Write-Output "Installing Steam via Winget..."

winget install --id Valve.Steam --exact --silent --accept-package-agreements --accept-source-agreements

exit $LASTEXITCODE




$ErrorActionPreference = "Stop"

# Logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogPath "Winget-Valve.Steam-Install.log"

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
    $Winget = Get-Command winget.exe -ErrorAction SilentlyContinue

    if (-not $Winget) {
        Write-Log "ERROR: Winget not found" -Level ERROR
        exit 1
    }

    Write-Log "Winget found: $($Winget.Source)"

    $WingetVersion = winget --version
    Write-Log "Winget version: $WingetVersion"

    #Structure our winget arguments so we can capture the outputs from winget
    $Arguments = @(
        "install"
        "--id", "Valve.Steam"
        "--exact"
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
    )

    Write-Log "Running: winget $($Arguments -join ' ')"

    #This captures all the console prints from winget so we can log them
    $Output = & winget @Arguments 2>&1

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