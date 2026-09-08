Start-Transcript -Path "C:\Windows\Temp\autologon.txt" -Append
$Username = "swts-user"
$AdminUsername = "swts-admin"
$ComputerName = $env:COMPUTERNAME
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$RegPath2 = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"
$Password = ""
$AdminPassword = "junkpassword"

# ============================
# ALLOW BLANK PASSWORDS
# ============================

Write-Output "Configuring blank password policy..."

$inf = @"
[System Access]
LimitBlankPasswordUse = 0
"@

$infPath = "C:\Windows\Temp\secpol.inf"
$dbPath = "C:\Windows\security\local.sdb"

try {
    $inf | Out-File -FilePath $infPath -Encoding ASCII -Force
    secedit /configure /db $dbPath /cfg $infPath /areas SECURITYPOLICY | Out-Null
    Write-Output "Blank password policy updated"
}
catch {
    Write-Output "Failed to set blank password policy"
    Write-Output $_
}

Write-Output "Starting user setup..."

# ============================
# CREATE USER (RELIABLE METHOD)
# ============================

$userExists = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

if (-not $userExists) {
    Write-Output "Creating local user: $Username"

    try {
        # Use net.exe (more reliable in SYSTEM context)
        cmd.exe /c "net user $Username $Password /add"

        # Ensure account settings
        cmd.exe /c "wmic UserAccount where Name='$Username' set PasswordExpires=FALSE"

        Write-Output "User created successfully"
    }
    catch {
        Write-Output "FAILED to create user!"
        Write-Output $_
        exit 1
    }
} else {
    Write-Output "User already exists"
}

# ============================
# CREATE ADMIN USER
# ============================

$adminUserExists = Get-LocalUser -Name $AdminUsername -ErrorAction SilentlyContinue

if (-not $adminUserExists) {
    Write-Output "Creating local user: $AdminUsername"

    try {
        # Use net.exe (more reliable in SYSTEM context)
        cmd.exe /c "net user $AdminUsername $AdminPassword /add"
        Write-Output "running cmd net user"

        Write-Output "User created successfully"
    }
    catch {
        Write-Output "FAILED to create user!"
        Write-Output $_
        exit 1
    }
} else {
    Write-Output "User already exists"
}

# ============================
# GROUP MEMBERSHIP
# ============================

try {
    Write-Output "Adding users to appropriate groups"
    # Remove from admins
    Remove-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction SilentlyContinue

    # Add swts-user to Users group and ensure swts-admin is in Administrator group
    Add-LocalGroupMember -Group "Users" -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group "Administrators" -Member $AdminUsername -ErrorAction SilentlyContinue

    Write-Output "Group membership set"
}
catch {
    Write-Output "Group config error"
}

# ============================
# AUTO-LOGON CONFIG
# ============================

Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -Type String
Set-ItemProperty $RegPath "DefaultUsername" -Value $Username -Type String
Set-ItemProperty $RegPath "DefaultPassword" -Value $Password -Type String
Set-ItemProperty $RegPath "DefaultDomainName" -Value $ComputerName -Type String
Set-ItemProperty $RegPath2 "DevicePasswordLessBuildVersion" -Value 0 -Type DWord

Write-Output "Auto-logon configured for $Username"