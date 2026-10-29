<#
.SYNOPSIS
    Installs or uninstalls Unreal Engine from Epic's offline installer (a .zip containing the MSI
    and its payload), pulling the zip from an internal server instead of shipping it through Intune.

.DESCRIPTION
    Intune only carries this script and secrets.json (a few KB). On the device it:
      0. Installs or updates the VC++ 2015-2022 x64 runtime if it's below VcRedistMinVersion
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
    InstallLocation = 'C:\Program Files\Epic Games\UE_5.8'    # verify against a test install
    DetectRelPath   = 'Engine\Binaries\Win64\UnrealEditor.exe' # file that proves the install worked
    ExtraMsiArgs    = ''                                      # e.g. the symbols property, see Get-MsiInfo.ps1 -AllProperties
    MinFreeGB       = 250                                     # peak need is roughly zip + extracted files, or extracted + installed engine. Adjust to your sizes
    MaxJitterSec    = 900                                     # random start delay, 0..N seconds
    VcRedistMinVersion = '14.44.35211.0'                      # minimum VC++ 2015-2022 x64 runtime. Set this to the version on a PC where the editor launches (see README)
    VcRedistUrl     = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'   # Microsoft's "latest" link. Override in secrets.json to use an internal copy
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

$script:RebootNeeded = $false

function Get-VcRedistVersion {
    # Installed VC++ 2015-2022 x64 runtime version, or $null. No Write-Log here: this function returns a value.
    $v = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
    if ($v -and $v.Installed -eq 1) {
        return [version]::new([int]$v.Major, [int]$v.Minor, [int]$v.Bld, [int]$v.Rbld)
    }
    return $null
}

function Install-VcRedist {
    # The editor needs a recent VC++ runtime and the offline installer doesn't provide one.
    # Skipped when the installed version already meets VcRedistMinVersion.
    $minVersion = [version]$Config.VcRedistMinVersion
    $current = Get-VcRedistVersion
    if ($current -and $current -ge $minVersion) {
        Write-Log "VC++ runtime $current already meets the minimum ($minVersion), skipping"
        return
    }
    $have = if ($current) { "$current" } else { 'not installed' }
    Write-Log "VC++ runtime is $have, need at least $minVersion. Installing."

    $exe = Join-Path $WorkDir 'vc_redist.x64.exe'
    Remove-Item $exe -Force -ErrorAction SilentlyContinue

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'   # progress rendering makes Invoke-WebRequest very slow
    Write-Log "Downloading $($Config.VcRedistUrl)"
    Invoke-WebRequest -Uri $Config.VcRedistUrl -OutFile $exe -UseBasicParsing

    # No pinned hash because the "latest" link changes; check the Microsoft signature instead
    $sig = Get-AuthenticodeSignature -FilePath $exe
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        Remove-Item $exe -Force -ErrorAction SilentlyContinue
        throw "VC++ redistributable signature check failed (status: $($sig.Status), signer: $($sig.SignerCertificate.Subject))"
    }
    Write-Log "Signature OK ($($sig.SignerCertificate.Subject))"

    $vcLog = Join-Path $LogPath "$($PackageName)-vcredist.log"
    $p = Start-Process -FilePath $exe -ArgumentList "/install /quiet /norestart /log `"$vcLog`"" -Wait -PassThru -NoNewWindow
    Remove-Item $exe -Force -ErrorAction SilentlyContinue

    # 0 = ok, 3010 = ok but a reboot is pending, 1638 = a newer version is already installed
    if ($p.ExitCode -notin 0, 3010, 1638) {
        throw "VC++ redistributable installer failed with exit code $($p.ExitCode) (see $vcLog)"
    }
    if ($p.ExitCode -eq 3010) { $script:RebootNeeded = $true }

    $after = Get-VcRedistVersion
    if (-not $after -or $after -lt $minVersion) {
        throw "VC++ runtime is '$after' after install, still below the required $minVersion. Check VcRedistMinVersion and VcRedistUrl."
    }
    Write-Log "VC++ runtime is now $after"
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
            # Runtime first: it's small, and a failure here shouldn't come after a 31 GB download
            Install-VcRedist

            if (Test-Path $DetectFile) {
                Write-Log "Engine already installed ($DetectFile exists), nothing more to do"
                Remove-Staging
                exit $(if ($script:RebootNeeded) { 3010 } else { 0 })
            }

            if (-not (Test-Path $StageDone)) {
                # Clear any partial extraction from a failed attempt first, so its leftovers
                # don't count against the free-space check below
                if (Test-Path $StageDir) {
                    Write-Log 'Removing incomplete staging folder from a previous attempt' 'WARNING'
                    Remove-Tree -Path $StageDir
                }

                # Spread the load on the file server when many devices start at once
                $delay = Get-Random -Minimum 0 -Maximum ($Config.MaxJitterSec + 1)
                Write-Log "Jitter delay: $delay s"
                Start-Sleep -Seconds $delay

                # MinFreeGB is the peak need including the zip, so if the zip is already on disk
                # it has already been paid for
                $needGB = $Config.MinFreeGB
                if (Test-Path $ZipPath) {
                    $needGB = [math]::Max(0, $needGB - [int][math]::Ceiling((Get-Item $ZipPath).Length / 1GB))
                }
                Assert-FreeSpace -Path $WorkDir -GB $needGB
                Get-Zip
                try { Expand-Stage }
                catch {
                    # Release the space a half-finished extraction is holding; the zip is kept for the retry
                    Write-Log 'Extraction failed, removing partial staging folder to free space' 'WARNING'
                    Remove-Tree -Path $StageDir
                    throw
                }
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
                exit $(if ($code -eq 0 -and $script:RebootNeeded) { 3010 } else { $code })
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