$ErrorActionPreference = "Stop"
# https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/Makeblock/xToolStudio
$PackageName  = "Makeblock.xToolStudio"
$PackageArch  = "x64"
$PackageScope = "machine"
$InstallPath  = "C:\Program Files\xToolStudio"
$ExeName      = "xTool Studio.exe"      # confirm against a test install
$ShortcutName = "xTool Studio.lnk"      # must match the detection script
$DriverPath   = Join-Path $PSScriptRoot "Drivers"

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
    $Winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue

    if (-not $Winget) {
        Write-Log "ERROR: Winget not found" -Level ERROR
        exit 1
    }

    if ($Winget.count -gt 1) {
        $Winget = $Winget[-1].Path
    }

    Write-Log "Winget found: $($Winget)"

    # --- Legacy cleanup: per-user install registered in SYSTEM's hive (HKCU when running as SYSTEM) ---
    $OldEntry = Get-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object DisplayName -like '*xTool*' |
        Select-Object -First 1

    if ($OldEntry) {
        Write-Log "Found legacy per-user install: $($OldEntry.DisplayName) $($OldEntry.DisplayVersion)"

        Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -like "$InstallPath\*" } |
            Stop-Process -Force

        $UninstallExe = $OldEntry.UninstallString -replace '^"?([^"]+\.exe)"?.*', '$1'

        if (Test-Path $UninstallExe) {
            $UninstallDir = Split-Path $UninstallExe
            Write-Log "Running uninstaller: $UninstallExe"
            # _?= makes the NSIS uninstaller run in place and block until it finishes
            Start-Process -FilePath $UninstallExe -ArgumentList "/S", "_?=$UninstallDir" -Wait
            Remove-Item $UninstallExe -Force -ErrorAction SilentlyContinue
        } else {
            Write-Log "Uninstaller not found at $UninstallExe, skipping" -Level WARNING
        }

        # Remove leftover files and the stale registry key so winget doesn't see two installs
        if (Test-Path $InstallPath) {
            Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($OldEntry.PSPath) {
            Remove-Item $OldEntry.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Log "Legacy cleanup complete"
    }

    #Structure our winget arguments so we can capture the outputs from winget
    # --override replaces the installer's default switches, so /S is required.
    # /D must be last and unquoted. It replaces --location here.
    $Arguments = @(
        "install"
        "--id", "$($PackageName)"
        "--exact"
        "--silent"
        "--accept-package-agreements"
        "--accept-source-agreements"
        "--scope", "$($PackageScope)"
        "--override", "/S /allusers /D=$($InstallPath)"
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

    # 0x8A15002B = already installed, no applicable update. Fine for machines that only need the driver.
    if ($ExitCode -eq -1978335189) {
        Write-Log "xTool Studio already installed and up to date, continuing"
        $ExitCode = 0
    }

    if ($ExitCode -eq 0) {
        # --- Safety net: create all-users shortcuts if the installer didn't ---
        $Exe = Join-Path $InstallPath $ExeName
        if (Test-Path $Exe) {
            $ws = New-Object -ComObject WScript.Shell
            $Shortcuts = @(
                "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$ShortcutName",
                "$env:PUBLIC\Desktop\$ShortcutName"
            )
            foreach ($Path in $Shortcuts) {
                if (-not (Test-Path $Path)) {
                    $lnk = $ws.CreateShortcut($Path)
                    $lnk.TargetPath = $Exe
                    $lnk.WorkingDirectory = $InstallPath
                    $lnk.Save()
                    Write-Log "Created shortcut: $Path"
                }
            }
        } else {
            Write-Log "Exe not found at $Exe, shortcuts not created" -Level WARNING
        }

        # --- Verify the uninstall entry landed in HKLM ---
        $Hklm = Get-ItemProperty `
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' `
            -ErrorAction SilentlyContinue |
            Where-Object DisplayName -like '*xTool*'
        if (-not $Hklm) {
            Write-Log "No HKLM uninstall entry found after install, check /allusers handling" -Level WARNING
        }

        # --- Stage the RNDIS driver in the driver store so standard users can plug in a P2S ---
        $Pnp = "$env:SystemRoot\sysnative\pnputil.exe"
        if (-not (Test-Path $Pnp)) { $Pnp = "$env:SystemRoot\System32\pnputil.exe" }

        $Inf = Join-Path $DriverPath "RNDIS.inf"
        if (-not (Test-Path $Inf)) {
            Write-Log "Driver INF not found at $Inf" -Level ERROR
            exit 1
        }

        Write-Log "Running: pnputil /add-driver $Inf /install"
        $DriverOutput = & $Pnp /add-driver $Inf /install 2>&1
        $DriverExit = $LASTEXITCODE
        $DriverOutput | ForEach-Object { Write-Log $_ }
        Write-Log "pnputil exit code: $DriverExit"

        # 0 = success, 3010 = success but reboot required
        if ($DriverExit -ne 0 -and $DriverExit -ne 3010) {
            Write-Log "Failed to stage RNDIS driver" -Level ERROR
            exit $DriverExit
        }
        if ($DriverExit -eq 3010) { $ExitCode = 3010 }
    }

    Write-Log "===== Script Finished ====="

    exit $ExitCode
}
catch {
    Write-Log "Unhandled exception:" -Level ERROR
    Write-Log $_.Exception.Message -Level ERROR
    exit 1
}