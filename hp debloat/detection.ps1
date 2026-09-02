# ================================
# HP OEM Debloat Detection Script
# ================================

$Manufacturer = (Get-CimInstance Win32_ComputerSystem).Manufacturer

# Ignore non-HP devices
if ($Manufacturer -notlike "*HP*") {
    Write-Output "Non-HP device"
    exit 0
}

$BloatwarePatterns = @(
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

$UninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$InstalledApps = Get-ItemProperty $UninstallKeys -ErrorAction SilentlyContinue

$DetectedApps = foreach ($Pattern in $BloatwarePatterns) {
    $InstalledApps | Where-Object {
        $_.DisplayName