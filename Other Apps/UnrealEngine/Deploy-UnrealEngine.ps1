<#
.SYNOPSIS
    Installs or uninstalls Unreal Engine from the Epic offline-installer MSI,
    pulling the MSI from an internal NAS instead of shipping it through Intune.

.DESCRIPTION
    Intune only carries this script (a few KB). On the device it:
      1. Skips everything if the engine is already installed
      2. Waits a random delay so a fleet doesn't hit the NAS at the same moment
      3. Checks free disk space
      4. Downloads the MSI with BITS (resumable), falling back to curl.exe
      5. Verifies the SHA256 against the value pinned below
      6. Runs msiexec silently with verbose logging
      7. Deletes the downloaded MSI on success

    Safe to re-run: Intune retries failed installs, and a partial download resumes.

.PARAMETER Action
    Install or Uninstall.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Deploy-UnrealEngine.ps1 -Action Install
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action
)

$ErrorActionPreference = 'Stop'

# ============================ CONFIG: edit per engine version ============================
$Config = @{
    EngineVersion   = '5.8.4'                                   # label used in logs and BITS job name
    MsiUrl          = ''                                      # supplied by secrets.json (not committed to git)
    MsiFileName     = 'UnrealEngineInstaller'
    MsiSha256       = '9E5A45B5865C4F995FD2773586313FF90741B14FA343E71426EC707068146B11'
    ProductCode     = '{222D5CFC-D556-4F66-922D-85F180F4C646}'   # needed for uninstall
    InstallLocation = 'C:\Program Files\Epic Games\UE_5.X'    # verify against a test install
    DetectRelPath   = 'Engine\Binaries\Win64\UnrealEditor.exe' # file that proves the install worked
    ExtraMsiArgs    = ''                                      # e.g. the symbols property, see Get-MsiInfo.ps1 -AllProperties
    MinFreeGB       = 120                                     # headroom for MSI download + installed engine
    MaxJitterSec    = 900                                     # random start delay, 0..N seconds
}
# ==========================================================================================

$PackageName = "UnrealEngine-$($Config.EngineVersion)"
$WorkDir = Join-Path $env:ProgramData 'UEDeploy'   # downloaded MSI lives here (deleted after install)
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# Logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogPath "$($PackageName)-$($Action).log"
$MsiLog  = Join-Path $LogPath "$($PackageName)-$($Action)-msi.log"

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

$MsiPath = Join-Path $WorkDir $Config.MsiFileName
$DetectFile = Join-Path $Config.InstallLocation $Config.DetectRelPath
$BitsJobName = "UEDeploy-$($Config.EngineVersion)"

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

# NOTE: Write-Log uses Write-Output, so anything it logs inside a function ends up in that
# function's return value. Functions that return a value (Test-InstallerHash, Invoke-Msiexec)
# therefore must not call Write-Log; their callers log before and after instead.

function Import-Secrets {
    # Merges secrets.json (same folder as this script) over the CONFIG block.
    # secrets.json is git-ignored; secrets-template.json is the committed example.
    $secretsFile = Join-Path $PSScriptRoot 'secrets.json'
    if (-not (Test-Path $secretsFile)) {
        throw "secrets.json not found next to the script ($secretsFile). Copy secrets-template.json to secrets.json and fill it in before packaging."
    }

    $secrets = Get-Content -Path $secretsFile -Raw | ConvertFrom-Json
    foreach ($prop in $secrets.PSObject.Properties) {
        $script:Config[$prop.Name] = $prop.Value
        Write-Log "Loaded '$($prop.Name)' from secrets.json"
    }

    # Anything derived from the config has to be recalculated after the merge
    $script:DetectFile = Join-Path $script:Config.InstallLocation $script:Config.DetectRelPath

    if ([string]::IsNullOrWhiteSpace($script:Config.MsiUrl) -or $script:Config.MsiUrl -match 'example\.|PASTE') {
        throw 'MsiUrl is missing or still a placeholder in secrets.json'
    }
}

function Test-InstallerHash {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    return ($actual -eq $Config.MsiSha256.Trim().ToUpper())
}

function Assert-FreeSpace {
    param([string]$Path, [int]$GB)
    $root = [System.IO.Path]::GetPathRoot($Path)
    $drive = Get-PSDrive -Name $root.Substring(0, 1)
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    Write-Log "Free space on ${root}: $freeGB GB (need $GB GB)"
    if ($freeGB -lt $GB) { throw "Not enough free space on $root ($freeGB GB free, $GB GB required)" }
}

function Get-Installer {
    # Reuse a previously downloaded, verified copy
    if (Test-Path $MsiPath) {
        Write-Log "Found existing $MsiPath, verifying SHA256 (large file, takes a few minutes)"
        if (Test-InstallerHash -Path $MsiPath) {
            Write-Log 'Existing MSI verified, skipping download'
            return
        }
        Write-Log 'Existing MSI failed hash check, deleting' 'WARNING'
        Remove-Item $MsiPath -Force
    }

    Write-Log "Downloading $($Config.MsiUrl)"
    $downloaded = $false

    # Primary: BITS. Resumable, bandwidth-friendly, survives network blips.
    try {
        $job = Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $BitsJobName } | Select-Object -First 1
        if ($job) {
            Write-Log "Resuming existing BITS job $($job.JobId)"
            Resume-BitsTransfer -BitsJob $job -Asynchronous | Out-Null
        }
        else {
            $job = Start-BitsTransfer -Source $Config.MsiUrl -Destination $MsiPath `
                -DisplayName $BitsJobName -Asynchronous -Priority Normal `
                -RetryInterval 60 -RetryTimeout 7200
        }

        $lastLog = Get-Date
        while ($job.JobState -in 'Queued', 'Connecting', 'Transferring', 'TransientError') {
            Start-Sleep -Seconds 15
            if (((Get-Date) - $lastLog).TotalSeconds -ge 120) {
                $pct = if ($job.BytesTotal -gt 0) { [math]::Round(100 * $job.BytesTransferred / $job.BytesTotal, 1) } else { 0 }
                Write-Log "BITS state=$($job.JobState) progress=$pct%"
                $lastLog = Get-Date
            }
        }

        if ($job.JobState -eq 'Transferred') {
            Complete-BitsTransfer -BitsJob $job
            $downloaded = $true
        }
        else {
            Write-Log "BITS ended in state $($job.JobState): $($job.ErrorDescription)" 'WARNING'
            Remove-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "BITS failed: $($_.Exception.Message)" 'WARNING'
    }

    # Fallback: curl.exe ships with Windows 10 1803+. -C - resumes a partial file.
    if (-not $downloaded) {
        Write-Log 'Falling back to curl.exe'
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (-not (Test-Path $curl)) { throw 'BITS failed and curl.exe is not available' }
        $p = Start-Process -FilePath $curl -Wait -PassThru -NoNewWindow -ArgumentList @(
            '--fail', '--location', '--retry', '5', '--retry-delay', '30', '-C', '-',
            '--output', "`"$MsiPath`"", "`"$($Config.MsiUrl)`"")
        if ($p.ExitCode -ne 0) { throw "curl.exe failed with exit code $($p.ExitCode)" }
    }

    Write-Log 'Download finished, verifying SHA256 (large file, takes a few minutes)'
    if (-not (Test-InstallerHash -Path $MsiPath)) {
        Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue
        throw 'Downloaded MSI failed SHA256 verification (deleted; the next retry will re-download)'
    }
    Write-Log 'Download complete and hash verified'
}

function Invoke-Msiexec {
    param([string]$Arguments)
    $p = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    return $p.ExitCode
}

try {
    Write-Log "=== $Action Unreal Engine $($Config.EngineVersion) on $env:COMPUTERNAME ==="
    Import-Secrets

    switch ($Action) {
        'Install' {
            if (Test-Path $DetectFile) {
                Write-Log "Already installed ($DetectFile exists), nothing to do"
                exit 0
            }

            # Spread the load on the NAS when many devices start at once
            $delay = Get-Random -Minimum 0 -Maximum ($Config.MaxJitterSec + 1)
            Write-Log "Jitter delay: $delay s"
            Start-Sleep -Seconds $delay

            New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
            Assert-FreeSpace -Path $WorkDir -GB $Config.MinFreeGB
            Get-Installer

            $argString = "/i `"$MsiPath`" /qn /norestart /l*v `"$MsiLog`" INSTALLLOCATION=`"$($Config.InstallLocation)`""
            if ($Config.ExtraMsiArgs) { $argString += " $($Config.ExtraMsiArgs)" }
            Write-Log "msiexec $argString"
            $code = Invoke-Msiexec -Arguments $argString

            if ($code -in 0, 3010) {
                if (-not (Test-Path $DetectFile)) {
                    throw "msiexec reported success ($code) but $DetectFile is missing. Check DetectRelPath/InstallLocation."
                }
                Write-Log "Install succeeded (exit $code)"
                Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue
                exit $code
            }
            throw "msiexec failed with exit code $code (see $MsiLog)"
        }

        'Uninstall' {
            $argString = "/x $($Config.ProductCode) /qn /norestart /l*v `"$MsiLog`""
            Write-Log "msiexec $argString"
            $code = Invoke-Msiexec -Arguments $argString
            # 1605 = product not installed; treat as success so Intune doesn't loop
            if ($code -in 0, 3010, 1605) {
                Write-Log "Uninstall finished (exit $code)"
                exit $(if ($code -eq 1605) { 0 } else { $code })
            }
            throw "msiexec uninstall failed with exit code $code (see $MsiLog)"
        }
    }
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    exit 1
}
