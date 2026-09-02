# ================================
# HP OEM Debloat Script
# ================================

# Logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$LogFile = Join-Path $LogPath "OEM-Debloat.log"

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

Write-Log "================================================"
Write-Log "Starting OEM Debloat Script"
Write-Log "================================================"

# Verify manufacturer

try {
    $Manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Write-Log "Detected manufacturer: $Manufacturer"

    if ($Manufacturer -notlike "*HP*") {
        Write-Log "Non-HP device detected. Exiting."
        exit 0
    }
}
catch {
    Write-Log "Unable to determine manufacturer. $_" -Level ERROR
    exit 1
}

# Applications to remove

$RemovePatterns = @(
    "McAfee",
    "Dropbox",
    "ExpressVPN",
    "Booking.com",
    "HP Wolf Security",
    "HP Wolf Security Application",
    "HP Wolf Security Console",
    "HP Sure Click",
    "HP Sure Sense",
    "HP Touchpoint Analytics",
    "HP JumpStarts",
    "HP QuickDrop",
    "HP Connection Optimizer",
    "HP Registration Service",
    "HP Documentation",
    "HP Notifications",
    "HP Privacy Settings"
)

Write-Log "Searching installed applications"

$UninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$InstalledApps = Get-ItemProperty $UninstallKeys -ErrorAction SilentlyContinue

# Registry-based uninstall

foreach ($Pattern in $RemovePatterns) {

    $Matches = $InstalledApps | Where-Object {
        $_.DisplayName -like "*$Pattern*"
    }

    foreach ($App in $Matches) {

        Write-Log "Found $($App.DisplayName)"

        try {

            if ([string]::IsNullOrWhiteSpace($App.UninstallString)) {

                Write-Log "No uninstall string found for $($App.DisplayName)" -Level WARNING
                continue
            }

            $Uninstall = $App.UninstallString

            Write-Log "Removing $($App.DisplayName)"

            if ($Uninstall -match "MsiExec.exe|msiexec.exe") {

                $Uninstall = $Uninstall -replace "/I","/X"

                Start-Process `
                    -FilePath "cmd.exe" `
                    -ArgumentList "/c $Uninstall /qn /norestart" `
                    -Wait `
                    -NoNewWindow

            }
            else {

                Start-Process `
                    -FilePath "cmd.exe" `
                    -ArgumentList "/c `"$Uninstall`" /quiet" `
                    -Wait `
                    -NoNewWindow

            }

            Write-Log "Successfully removed $($App.DisplayName)"
        }
        catch {
            Write-Log "Failed removing $($App.DisplayName): $_" -Level ERROR
        }
    }
}

# Remove AppX packages

Write-Log "Checking AppX packages"

Get-AppxPackage -AllUsers |
Where-Object {
    $_.Name -match 'HP|McAfee|Dropbox|ExpressVPN'
} |
ForEach-Object {

    try {

        Write-Log "Removing AppX package $($_.Name)"

        Remove-AppxPackage `
            -Package $_.PackageFullName `
            -AllUsers `
            -ErrorAction Stop

        Write-Log "Successfully removed AppX package $($_.Name)"
    }
    catch {
        Write-Log "Failed removing AppX package $($_.Name): $_" -Level ERROR
    }
}

# Remove Provisioned Packages

Write-Log "Checking provisioned packages"

Get-AppxProvisionedPackage -Online |
Where-Object {
    $_.DisplayName -match 'HP|McAfee|Dropbox|ExpressVPN'
} |
ForEach-Object {

    try {

        Write-Log "Removing provisioned package $($_.DisplayName)"

        Remove-AppxProvisionedPackage `
            -Online `
            -PackageName $_.PackageName `
            -ErrorAction Stop

        Write-Log "Successfully removed provisioned package $($_.DisplayName)"
    }
    catch {
        Write-Log "Failed removing provisioned package $($_.DisplayName): $_" -Level ERROR
    }
}

# Disable Windows Consumer Features

try {

    Write-Log "Disabling Windows Consumer Features"

    New-Item `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Force | Out-Null

    Set-ItemProperty `
        -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
        -Name "DisableWindowsConsumerFeatures" `
        -Type DWord `
        -Value 1

    Write-Log "Windows Consumer Features disabled"
}
catch {
    Write-Log "Failed configuring Windows Consumer Features: $_" -Level ERROR
}

Write-Log "================================================"
Write-Log "OEM Debloat Script Completed"
Write-Log "================================================"