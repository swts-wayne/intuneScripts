$PrinterName = "Epson ColorWorks C6010A"
$PortName    = "LPR_10.20.106.20"

Remove-Printer `
    -Name $PrinterName `
    -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2

Remove-PrinterPort `
    -Name $PortName `
    -ErrorAction SilentlyContinue

exit 0