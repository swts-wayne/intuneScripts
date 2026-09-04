#This function serves to keep logging consistent across the entire script

$Global:LogPath = "C:\ProgramData\SWTS\PlayerSetup\Logs"

if (-not (Test-Path $Global:LogPath)) {
    New-Item -Path $Global:LogPath -ItemType Directory -Force | Out-Null
}

$Global:LogFile = Join-Path $Global:LogPath (
    "PlayerSetup-{0}.log" -f (Get-Date -Format "yyyyMMdd")
)

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO","WARNING","ERROR")]
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Entry = "[$Timestamp] [$Level] $Message"

    Write-Host $Entry

    Add-Content -Path $Global:LogFile -Value $Entry
}