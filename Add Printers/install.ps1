# ============================
# Epson ColorWorks C6010A
# Intune Install Script
# ============================

$PrinterName = "Epson ColorWorks C6010A"
$PrinterIP   = "10.20.106.20"

# Verify queue name from printer config
$LprQueueName = "lp"

$PortName   = "LPR_$PrinterIP"

# Exact name of driver
$DriverName = "EPSON CW-C6010A"

$DriverPath = Join-Path $PSScriptRoot "Drivers"

Write-Host "Installing Epson driver package..."

#Run pnputil to add the drivers
pnputil.exe /add-driver "$DriverPath\*.inf" /subdirs /install

#Now to monitor the status of the driver install before proceeding
$Timeout = 30
$Elapsed = 0

Write-Host "Standby while we wait for the driver to install..."

do {
    $Driver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue

    if ($Driver) {
        break
    }

    Start-Sleep -Seconds 2
    $Elapsed += 2

} while ($Elapsed -lt $Timeout)

if (-not $Driver) {
    Write-Error "Driver '$DriverName' not installed."
    exit 1
}

Write-Host "Driver located."

# Create LPR port if missing

if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue))
{
    Write-Host "Creating LPR port..."

    Add-PrinterPort `
        -Name $PortName `
        -PrinterHostAddress $PrinterIP `
        -LprHostAddress $PrinterIP `
        -LprQueueName $LprQueueName `
        -LprByteCounting:$true
}

# Create printer if missing

if (-not (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue))
{
    Write-Host "Creating printer..."

    Add-Printer `
        -Name $PrinterName `
        -DriverName $DriverName `
        -PortName $PortName
}

Write-Host "Printer installation complete."

exit 0