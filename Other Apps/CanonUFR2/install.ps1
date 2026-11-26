$ErrorActionPreference = 'Stop'
$DriverName  = 'Canon Generic Plus UFR II'   # must match the INF model name exactly
$PrinterName = 'Staff Printer - C3930i'
$PortName    = 'IP_10.20.160.42'                 # sub-line IP of the printer
$PortIP      = '10.20.160.42'

# 1. Trust Canon's driver-signing cert so pnputil doesn't need a prompt
$cat = Get-ChildItem "$PSScriptRoot\Driver" -Filter *.cat -Recurse | Select-Object -First 1
$cert = (Get-AuthenticodeSignature $cat.FullName).SignerCertificate
if (-not $cert) { throw "No signer certificate found on $($cat.Name)" }

$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher','LocalMachine')
$store.Open('ReadWrite')
$store.Add($cert)
$store.Close()

# 2. Stage the driver in the driver store
pnputil.exe /add-driver "$PSScriptRoot\Driver\*.inf" /subdirs /install
if ($LASTEXITCODE -notin 0,3010) { exit $LASTEXITCODE }

# 3. Register the driver with the print spooler
if (-not (Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue)) {
    Add-PrinterDriver -Name $DriverName
}

# 4. Port (Standard TCP/IP, RAW 9100)
if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
    Add-PrinterPort -Name $PortName -PrinterHostAddress $PortIP
}

# 5. Queue
if (-not (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue)) {
    Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName
}
exit 0