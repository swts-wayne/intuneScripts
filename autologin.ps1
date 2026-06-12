$Username = "swts-user"
$Password = "password123"
$ComputerName = $env:COMPUTERNAME
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

# ✅ 1. Create user if it doesn't exist
$userExists = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

if (-not $userExists) {
    Write-Output "Creating local user: $Username"
    New-LocalUser -Name $Username -Password (ConvertTo-SecureString $Password -AsPlainText -Force) -AccountNeverExpires
    net user $Username ""
}

# ✅ 2. Ensure user is NOT an admin
$isAdmin = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Where-Object {$_.Name -like "*$Username"}

if ($isAdmin) {
    Write-Output "Removing $Username from Administrators"
    Remove-LocalGroupMember -Group "Administrators" -Member $Username
}

# ✅ 3. Ensure user is in Users group (standard user)
$inUsersGroup = Get-LocalGroupMember -Group "Users" -ErrorAction SilentlyContinue | Where-Object {$_.Name -like "*$Username"}

if (-not $inUsersGroup) {
    Write-Output "Adding $Username to Users group"
    Add-LocalGroupMember -Group "Users" -Member $Username
}

# ✅ 4. Configure auto-logon
Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -Type String
Set-ItemProperty $RegPath "DefaultUsername" -Value $Username -Type String
Set-ItemProperty $RegPath "DefaultPassword" -Value $Password -Type String
Set-ItemProperty $RegPath "DefaultDomainName" -Value $ComputerName -Type String

Write-Output "Auto-logon configured for $Username"