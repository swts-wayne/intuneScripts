# =====================================================================
# GamingPrereqs
#
# Purpose:
# Install Steam game prerequisites and create Steam CommonRedist
# registry markers required for Steam games on Shared Devices.
#
# Validated against:
# - Ultimate Chicken Horse (386940)
# - Steamworks Common Redistributables (228980)
#
# =====================================================================

# Logging
# I use this logging function wherever I can

$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogPath "GamingPrereqs-Install.log"

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

try {

    Write-Log "===== GamingPrereqs installation started ====="

    # ================================================================
    # Install VC++ 2013 x86
    # ================================================================

    $VC2013x86 = Join-Path $PSScriptRoot "VC2013\vcredist_x86.exe"

    Write-Log "Installing Visual C++ 2013 x86"

    $Process = Start-Process `
        -FilePath $VC2013x86 `
        -ArgumentList "/install /quiet /norestart" `
        -Wait `
        -PassThru

    Write-Log "Visual C++ 2013 x86 exited with code $($Process.ExitCode)"

    # ================================================================
    # Install VC++ 2013 x64
    # ================================================================

    $VC2013x64 = Join-Path $PSScriptRoot "VC2013\vcredist_x64.exe"

    Write-Log "Installing Visual C++ 2013 x64"

    $Process = Start-Process `
        -FilePath $VC2013x64 `
        -ArgumentList "/install /quiet /norestart" `
        -Wait `
        -PassThru

    Write-Log "Visual C++ 2013 x64 exited with code $($Process.ExitCode)"

    # ================================================================
    # Extract DirectX Runtime
    # ================================================================

    $DXRedist = Join-Path $PSScriptRoot "DirectX\directx_Jun2010_redist.exe"
    $DXTemp = Join-Path $env:TEMP "DXRedist"

    Write-Log "Preparing DirectX extraction directory: $DXTemp"

    New-Item `
        -Path $DXTemp `
        -ItemType Directory `
        -Force | Out-Null

    Write-Log "Extracting DirectX June 2010 Runtime"

    $Process = Start-Process `
        -FilePath $DXRedist `
        -ArgumentList "/Q /T:$DXTemp" `
        -Wait `
        -PassThru

    Write-Log "DirectX extraction exited with code $($Process.ExitCode)"

    # ================================================================
    # Install DirectX
    # ================================================================

    $DXSetup = Join-Path $DXTemp "DXSETUP.exe"

    Write-Log "Installing DirectX Runtime"

    $Process = Start-Process `
        -FilePath $DXSetup `
        -ArgumentList "/silent" `
        -Wait `
        -PassThru

    Write-Log "DirectX installer exited with code $($Process.ExitCode)"

    # ===================================================