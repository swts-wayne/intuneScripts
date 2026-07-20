# ============================
# CONFIG
# ============================
$secretsPath = Join-Path $PSScriptRoot "secrets.json"

if (-not (Test-Path $secretsPath)) {
    throw "Missing secrets.json file"
}

try {
    $secret = Get-Content $secretsPath -Raw | ConvertFrom-Json
}
catch {
    throw "Failed to parse secrets.json"
}

$TenantID = $secret.TenantID
$AppID    = $secret.AppID
$AppSecret = $secret.AppSecret
$UpgradeToPro = $false

# Basic validation
if (-not $TenantID -or -not $AppID -or -not $AppSecret) {
    throw "secret.json is missing required values"
}


# ============================
# SELECT DEPLOYMENT TYPE
# ============================

do {
    Write-Host ""
    Write-Host "Select device type:" -ForegroundColor Cyan
    Write-Host "1 - Pixel Forge" -ForegroundColor Yellow
    Write-Host "2 - Laptop" -ForegroundColor Yellow
    Write-Host "3 - VM" -ForegroundColor Yellow
    Write-Host ""

    $selection = Read-Host "Enter selection (1-3)"

    switch ($selection) {
        "1" {
            $GroupTag = "forge"
            $UpgradeToPro = $true
            $valid = $true
        }
        "2" {
            $GroupTag = "laptop"
            $UpgradeToPro = $false
            $valid = $true
        }
        "3" {
            $GroupTag = "vm"
            $UpgradeToPro = $false
            $valid = $true
        }
        default {
            Write-Host "Invalid selection, try again." -ForegroundColor Red
            $valid = $false
        }
    }
} until ($valid)

Write-Host ""
Write-Host "Selected GroupTag: $GroupTag" -ForegroundColor Green
Write-Host ""

# ============================
# PREP
# ============================
Write-Host "Installing required script..." -ForegroundColor Cyan

# Install NuGet silently
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

# Trust PSGallery
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted

# Ensure script is available
if (-not (Get-Command Get-WindowsAutopilotInfo -ErrorAction SilentlyContinue)) {
    Install-Script -Name Get-WindowsAutopilotInfo -Force -Confirm:$false
}

# ============================
# REGISTER DEVICE
# ============================
Write-Host "Registering device with Autopilot..." -ForegroundColor Cyan

try {
    Get-WindowsAutopilotInfo.ps1 -Online -TenantID $TenantID -AppID $AppID -AppSecret $AppSecret -GroupTag $GroupTag -ErrorAction Stop
}
catch {
    Write-Host "Autopilot registration failed!" -ForegroundColor Red
    Write-Host $_
    exit 1
}

# ============================
# WAIT FOR AUTOPILOT PROFILE ASSIGNMENT
# ============================

Write-Host "Waiting for Autopilot profile assignment..." -ForegroundColor Yellow

# Get serial number (used to find device in Autopilot)
$serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber

# Get access token
$body = @{
    grant_type    = "client_credentials"
    scope         = "https://graph.microsoft.com/.default"
    client_id     = $AppID
    client_secret = $AppSecret
}

$tokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token" `
    -Body $body

$headers = @{
    Authorization = "Bearer $($tokenResponse.access_token)"
}

# Poll loop
$assigned = $false
$maxAttempts = 30   # ~10 minutes (30 × 20 sec)
$attempt = 0

do {
    $attempt++
    Write-Host "Checking assignment status (attempt $attempt)..." -ForegroundColor Cyan

    $uri = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$serial')"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

        if ($response.value.Count -gt 0) {
            $device = $response.value[0]

            Write-Host "Status: $($device.deploymentProfileAssignmentStatus)" -ForegroundColor Gray

            if ($device.deploymentProfileAssignmentStatus -eq "assigned") {
                $assigned = $true
                break
            } elseif ($device.deploymentProfileAssignmentStatus -eq "assignedUnkownSyncState"){
                #note the type in "unknown" there, that's a M$ error
                $assigned = $true
                break
            }
        } else {
            Write-Host "Device not found yet..." -ForegroundColor DarkYellow
        }
    }
    catch {
        Write-Host "Error querying Graph, retrying..." -ForegroundColor Red
    }

    Start-Sleep -Seconds 20

} while ($attempt -lt $maxAttempts)

if ($assigned) {
    if ($UpgradeToPro) {
        $edition = (Get-ComputerInfo).WindowsEditionId

        if ($edition -eq "Core") {
            Write-Host "Windows Home detected. Upgrading to Pro..." -ForegroundColor Yellow

            try {
                ##This is the generic Windows Pro key used to upgrade the OEM version
                changepk.exe /ProductKey VK7JG-NPHTM-C97JM-9MPGT-3V66T

                Write-Host "Pro upgrade initiated." -ForegroundColor Green
                Write-Host "Rebooting to complete edition upgrade..." -ForegroundColor Green
            } catch {
                Write-Host "Failed to start Windows Pro upgrade!" -ForegroundColor Red
                Write-Host $_
                exit 1
            }
        } else {
            Write-Host "Windows edition is already $edition" -ForegroundColor Green
        }
    }

    Write-Host "✅ Profile assigned! Rebooting..." -ForegroundColor Green
    shutdown /r /t 0
} else {
    Write-Host "❌ Timed out waiting for profile. Rebooting anyway..." -ForegroundColor Red
    shutdown /r /t 0
}

# ============================
# REBOOT INTO AUTOPILOT
# ============================
Write-Host "Rebooting device into Autopilot OOBE..." -ForegroundColor Green
Start-Sleep -Seconds 5
shutdown /r /t 0