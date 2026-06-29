$Username = "swts-user"
$AdminUsername = "swts-admin"
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

$userExists = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
$adminUserExists = Get-LocalUser -Name $AdminUsername -ErrorAction SilentlyContinue
$autoLogon = (Get-ItemProperty $RegPath -Name "AutoAdminLogon" -ErrorAction SilentlyContinue).AutoAdminLogon
$defaultUser = (Get-ItemProperty $RegPath -Name "DefaultUsername" -ErrorAction SilentlyContinue).DefaultUsername

if ($adminUserExists -and $userExists -and $autoLogon -eq "1" -and $defaultUser -eq $Username) {
    Write-Output "Compliant"
    exit 0
} else {
    Write-Output "Non-compliant"
    exit 1
}