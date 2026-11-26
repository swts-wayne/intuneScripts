$ErrorActionPreference = 'Continue'   # keep going so one failure doesn't block the rest
$DriverName  = 'Canon Generic Plus UFR II'
$PrinterName = 'Staff Printer - C3930i'
$PortName    = 'IP_10.20.160.42'   

# 1. Remove the queue
if (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) {
    Remove-Printer -Name $PrinterName
}

# 2. Remove the port, but only if no other queue is using it
if ((Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue) -and
    -not (Get-Printer | Where-Object PortName -eq $PortName)) {
    Remove-PrinterPort -Name $PortName
}

# 3. Unregister the driver from the spooler, but only if no other queue uses it
if ((Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue) -and
    -not (Get-Printer | Where-Object DriverName -eq $DriverName)) {
    Remove-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
}

# 4. Remove the package from the driver store (match on the INF names we shipped)
$ourInfs = Get-ChildItem "$PSScriptRoot\Driver" -Filter *.inf -Recurse | Select-Object -ExpandProperty Name
Get-WindowsDriver -Online |
    Where-Object { $ourInfs -contains (Split-Path $_.OriginalFileName -Leaf) } |
    ForEach-Object { pnputil.exe /delete-driver $_.Driver /uninstall /force }

# 5. Remove the Canon signing cert from Trusted Publishers
$cat = Get-ChildItem "$PSScriptRoot\Driver" -Filter *.cat -Recurse | Select-Object -First 1
$cert = (Get-AuthenticodeSignature $cat.FullName).SignerCertificate
if ($cert) {
    Remove-Item "Cert:\LocalMachine\TrustedPublisher\$($cert.Thumbprint)" -ErrorAction SilentlyContinue
}
exit 0