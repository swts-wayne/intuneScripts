$DriverName  = 'Canon Generic Plus UFR II'
$PrinterName = 'Staff Printer - C3930i'
$PortName    = 'IP_10.20.160.42' 

$ok = (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) -and
      (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue) -and
      (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue)
if ($ok) { Write-Output 'Installed'; exit 0 } else { exit 1 }