<#
.SYNOPSIS
    Installs or uninstalls Unreal Engine from Epic's offline installer (a .zip containing the MSI
    and its payload), pulling the zip from an internal server instead of shipping it through Intune.

.DESCRIPTION
    Intune only carries this script and secrets.json (a few KB). On the device it:
      1. Skips everything if the engine is already installed
      2. Waits a random delay so a fleet doesn't hit the file server at the same moment
      3. Checks free disk space
      4. Downloads the zip with BITS (resumable), falling back to curl.exe
      5. Verifies the zip's SHA256 against the value pinned below
      6. Extracts it (tar.exe, falling back to .NET) and deletes the zip to free space
      7. Finds the MSI in the extracted files and runs msiexec silently with verbose logging
      8. Deletes the extracted files on success

    Safe to re-run: Intune retries failed installs. A partial download resumes, and a completed
    extraction is reused if only the MSI step failed.

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

# Intune's agent is a 32-bit process, so powershell.exe starts as 32-bit by default and System32
# gets redirected to SysWOW64. Re-run in 64-bit PowerShell so tar/msiexec/curl behave normally.
if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') {
    $ps64 = Join-Path $env:windir 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $ps64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Action $Action
    exit $LASTEXITCODE
}

# ============================ CONFIG: edit per engine version ============================
$Config = @{
    EngineVersion   = '5.8.4'                                 # label used in logs, BITS job and staging folder names
    ZipUrl          = ''                                      # supplied by secrets.json (not committed to git)
    ZipFileName     = 'UnrealEngineInstaller5-8-4.zip'
    ZipSha256       = 'A0B28A67EF294E83687B7B7272BAAA3CABD019B3D8ACF5C2AEF8C6B45FD3213D'               # from Get-MsiInfo.ps1 -ZipPath
    MsiRelPath      = ''                                      # MSI path inside the zip, e.g. 'Installer\UnrealEngine.msi'. Blank = auto-detect (must be the only .msi)
    ProductCode     = '{222D5CFC-D556-4F66-922D-85F180F4C646}'   # needed for uninstall
    InstallLocation = 'C:\Program Files\Epic Games\UE_5.8.4'    # verify against a test install
    DetectRelPath   = 'Engine\Binaries\Win64\UnrealEditor.exe' # file that proves the install worked
    ExtraMsiArgs    = ''                                      # e.g. the symbols property, see Get-MsiInfo.ps1 -AllProperties
    MinFreeGB       = 150                                     # peak need is roughly zip + extracted files, or extracted + installed engine. Adjust to your sizes
    MaxJitterSec    = 700                                     # random start delay, 0..N seconds
}
# ==========================================================================================

$PackageName = "UnrealEngine-$($Config.EngineVersion)"
$WorkDir = Join-Path $env:ProgramData 'UEDeploy'   # zip and extracted files live here temporarily
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

# Logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogPath "$($PackageName)-$($Action).log"
$MsiLog  = Join-Path $LogPath "$($PackageName)-$($Action)-msi.log"

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

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
# function's return value. Functions that return a value (Test-ZipHash, Get-StagedMsi,
# Invoke-Msiexec) therefore must not call Write-Log; their callers log before and after instead.

function Set-DerivedPaths {
    # Everything computed from $Config; called at start-up and again after secrets.json is merged
    $script:ZipPath    = Join-Path $WorkDir $script:Config.ZipFileName
    $script:StageDir   = Join-Path $WorkDir "stage-$($script:Config.EngineVersion)"
    $script:StageDone  = Join-Path $WorkDir "stage-$($script:Config.EngineVersion).complete"
    $script:DetectFile = Join-Path $script:Config.InstallLocation $script:Config.DetectRelPath
}
Set-DerivedPaths

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

    Set-DerivedPaths

    if ([string]::IsNullOrWhiteSpace($script:Config.ZipUrl) -or $script:Config.ZipUrl -match 'example\.|PASTE') {
        throw 'ZipUrl is missing or still a placeholder in secrets.json'
    }
}

function Test-ZipHash {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    return ($actual -eq $Config.ZipSha256.Trim().ToUpper())
}

function Assert-FreeSpace {
    param([string]$Path, [int]$GB)
    $root = [System.IO.Path]::GetPathRoot($Path)
    $drive = Get-PSDrive -Name $root.Substring(0, 1)
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    Write-Log "Free space on ${root}: $freeGB GB (need $GB GB)"
    if ($freeGB -lt $GB) { throw "Not enough free space on $root ($freeGB GB free, $GB GB required)" }
}

function Remove-Tree {
    # rd /s /q is far faster than Remove-Item -Recurse on trees with tens of thousands of files
    param([string]$Path)
    if (Test-Path $Path) {
        & "$env:SystemRoot\System32\cmd.exe" /c rd /s /q $Path
    }
}

function Remove-Staging {
    Remove-Tree -Path $StageDir
    Remove-Item -Path $StageDone -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue
}

function Get-Zip {
    # Reuse a previously downloaded, verified copy
    if (Test-Path $ZipPath) {
        Write-Log "Found existing $ZipPath, verifying SHA256 (large file, takes a few minutes)"
        if (Test-ZipHash -Path $ZipPath) {
            Write-Log 'Existing zip verified, skipping download'
            return
        }
        Write-Log 'Existing zip failed hash check, deleting' 'WARNING'
        Remove-Item $ZipPath -Force
    }

    Write-Log "Downloading $($Config.ZipUrl)"
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
            $job = Start-BitsTransfer -Source $Config.ZipUrl -Destination $ZipPath `
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
            '--output', "`"$ZipPath`"", "`"$($Config.ZipUrl)`"")
        if ($p.ExitCode -ne 0) { throw "curl.exe failed with exit code $($p.ExitCode)" }
    }

    Write-Log 'Download finished, verifying SHA256 (large file, takes a few minutes)'
    if (-not (Test-ZipHash -Path $ZipPath)) {
        Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
        throw 'Downloaded zip failed SHA256 verification (deleted; the next retry will re-download)'
    }
    Write-Log 'Download complete and hash verified'
}

function Expand-Stage {
    # Extracts the zip into $StageDir. A marker file records a complete extraction so a retry can skip it.
    if (Test-Path $StageDone) {
        Write-Log 'Extracted files already present, skipping extraction'
        return
    }
    if (-not (Test-Path $ZipPath)) { throw "Zip not found at $ZipPath" }

    if (Test-Path $StageDir) {
        Write-Log 'Removing incomplete staging folder from a previous attempt' 'WARNING'
        Remove-Tree -Path $StageDir
    }
    New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

    $extracted = $false

    # Primary: tar.exe (bsdtar, Windows 10 1803+). Much faster than Expand-Archive and handles zip64.
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tar) {
        Write-Log 'Extracting with tar.exe (this can take a while)'
        $p = Start-Process -FilePath $tar -Wait -PassThru -NoNewWindow `
            -ArgumentList @('-xf', "`"$ZipPath`"", '-C', "`"$StageDir`"")
        if ($p.ExitCode -eq 0) {
            $extracted = $true
        }
        else {
            Write-Log "tar.exe failed with exit code $($p.ExitCode), falling back to .NET" 'WARNING'
            Remove-Tree -Path $StageDir
            New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
        }
    }

    # Fallback: .NET ZipFile (slower, but no external dependency)
    if (-not $extracted) {
        Write-Log 'Extracting with .NET ZipFile (this can take a while)'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $StageDir)
    }

    Set-Content -Path $StageDone -Value (Get-Date -Format 'o')
    Write-Log 'Extraction complete'
}

function Get-StagedMsi {
    if ($Config.MsiRelPath) {
        $path = Join-Path $StageDir $Config.MsiRelPath
        if (-not (Test-Path $path)) { throw "MsiRelPath not found in extracted files: $path" }
        return $path
    }
    $found = @(Get-ChildItem -Path $StageDir -Filter '*.msi' -Recurse -File)
    if ($found.Count -eq 1) { return $found[0].FullName }
    throw "Expected exactly one .msi in the extracted files but found $($found.Count): $(($found.FullName) -join '; '). Set MsiRelPath in the config."
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
                Remove-Staging
                exit 0
            }

            if (-not (Test-Path $StageDone)) {
                # Spread the load on the file server when many devices start at once
                $delay = Get-Random -Minimum 0 -Maximum ($Config.MaxJitterSec + 1)
                Write-Log "Jitter delay: $delay s"
                Start-Sleep -Seconds $delay

                Assert-FreeSpace -Path $WorkDir -GB $Config.MinFreeGB
                Get-Zip
                Expand-Stage
                # Free the space before the install needs it
                Remove-Item -Path $ZipPath -Force -ErrorAction SilentlyContinue
            }
            else {
                Write-Log 'Extracted files from a previous attempt found, skipping download and extraction'
            }

            try { $msi = Get-StagedMsi }
            catch {
                Write-Log 'Staged files are unusable, clearing them so the next attempt starts fresh' 'WARNING'
                Remove-Staging
                throw
            }
            Write-Log "Using MSI: $msi"

            $argString = "/i `"$msi`" /qn /norestart /l*v `"$MsiLog`" INSTALLLOCATION=`"$($Config.InstallLocation)`""
            if ($Config.ExtraMsiArgs) { $argString += " $($Config.ExtraMsiArgs)" }
            Write-Log "msiexec $argString"
            $code = Invoke-Msiexec -Arguments $argString

            if ($code -in 0, 3010) {
                if (-not (Test-Path $DetectFile)) {
                    throw "msiexec reported success ($code) but $DetectFile is missing. Check DetectRelPath/InstallLocation."
                }
                Write-Log "Install succeeded (exit $code), cleaning up staged files"
                Remove-Staging
                exit $code
            }
            Write-Log 'Keeping extracted files so a retry can skip the download' 'WARNING'
            throw "msiexec failed with exit code $code (see $MsiLog)"
        }

        'Uninstall' {
            $argString = "/x $($Config.ProductCode) /qn /norestart /l*v `"$MsiLog`""
            Write-Log "msiexec $argString"
            $code = Invoke-Msiexec -Arguments $argString
            # 1605 = product not installed; treat as success so Intune doesn't loop
            if ($code -in 0, 3010, 1605) {
                Write-Log "Uninstall finished (exit $code)"
                Remove-Staging
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
