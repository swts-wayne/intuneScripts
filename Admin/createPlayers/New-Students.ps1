<#
.SYNOPSIS
    Bulk creates student accounts in Microsoft Entra ID.

.DESCRIPTION
    Creates student accounts using the naming convention:

        p001@swts.dev
        p002@swts.dev
        p003@swts.dev

    The script will:

    - Determine the highest existing student number.
    - Create the requested number of new accounts.
    - Set:
        Given Name      = Player
        Surname         = ### (student number)
        Usage Location  = AU
    - Generate a random password.
    - Disable password expiry.
    - Add each account to the UG_Students security group.
    - Log all activity to a log file.

.PARAMETER Count
    Number of student accounts to create.

.EXAMPLE
    .\New-Students.ps1 -Count 30

.NOTES
    Requires Microsoft Graph PowerShell SDK.
#>

param(
    [Parameter(Mandatory)]
    [ValidateRange(1,1000)]
    [int]$Count
)

#--------------------------------------------------
# Configuration
#--------------------------------------------------

$DomainName = "swts.dev"
$GroupName  = "UG_Students"

$LogFile = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "StudentProvisioning.log"

#--------------------------------------------------
# Logging Function
#--------------------------------------------------

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Entry = "[$Timestamp] $Message"

    Write-Host $Entry
    Add-Content -Path $LogFile -Value $Entry
}

#--------------------------------------------------
# Password Generation Function
#--------------------------------------------------

function New-RandomPassword {
    param(
        [int]$Length = 20
    )

    $CharacterSet =
        "ABCDEFGHJKLMNPQRSTUVWXYZ" +
        "abcdefghijkmnopqrstuvwxyz" +
        "23456789" +
        "!@#$%^&*"

    $Password = -join (
        1..$Length | ForEach-Object {
            $CharacterSet[(Get-Random -Maximum $CharacterSet.Length)]
        }
    )

    return $Password
}

#--------------------------------------------------
# Connect to Microsoft Graph
#--------------------------------------------------

try {
    Write-Log "Connecting to Microsoft Graph..."

    Connect-MgGraph `
        -Scopes `
        "User.ReadWrite.All",
        "Group.ReadWrite.All" `
        -NoWelcome

    Write-Log "Successfully connected to Microsoft Graph."
}
catch {
    Write-Log "ERROR: Failed to connect to Microsoft Graph."
    throw
}

#--------------------------------------------------
# Locate Student Group
#--------------------------------------------------

Write-Log "Looking up security group '$GroupName'..."

$Group = Get-MgGroup -Filter "displayName eq '$GroupName'"

if (-not $Group) {
    Write-Log "ERROR: Security group '$GroupName' not found."
    throw "Security group '$GroupName' not found."
}

Write-Log "Found group '$GroupName' ($($Group.Id))"

#--------------------------------------------------
# Determine Current Highest Student Number
#--------------------------------------------------

Write-Log "Searching for existing student accounts..."

$Users = Get-MgUser `
    -All `
    -Property UserPrincipalName `
    -Filter "startsWith(userPrincipalName,'p')"

$HighestNumber = 0

foreach ($User in $Users) {

    if ($User.UserPrincipalName -match '^p(\d+)@swts\.dev$') {

        $CurrentNumber = [int]$Matches[1]

        if ($CurrentNumber -gt $HighestNumber) {
            $HighestNumber = $CurrentNumber
        }
    }
}

Write-Log "Highest existing student number is $HighestNumber"

#--------------------------------------------------
# Create New Student Accounts
#--------------------------------------------------

$CreatedCount = 0

for ($i = 1; $i -le $Count; $i++) {

    $StudentNumber = $HighestNumber + $i

    $StudentSuffix = "{0:D3}" -f $StudentNumber

    $UPN = "p$StudentSuffix@$DomainName"

    $Password = New-RandomPassword

    try {

        Write-Log "Creating user $UPN"

        $User = New-MgUser `
            -AccountEnabled:$true `
            -DisplayName "Player $StudentSuffix" `
            -GivenName "Player" `
            -Surname $StudentSuffix `
            -MailNickname "p$StudentSuffix" `
            -UserPrincipalName $UPN `
            -UsageLocation "AU" `
            -PasswordPolicies "DisablePasswordExpiration" `
            -PasswordProfile @{
                Password = $Password
                ForceChangePasswordNextSignIn = $false
            }

        Write-Log "Successfully created $UPN"

        New-MgGroupMember `
            -GroupId $Group.Id `
            -DirectoryObjectId $User.Id

        Write-Log "Added $UPN to '$GroupName'"

        $CreatedCount++
    }
    catch {
        Write-Log "ERROR processing $UPN"
        Write-Log $_.Exception.Message
    }
}

#--------------------------------------------------
# Summary
#--------------------------------------------------

Write-Log "Provisioning complete."
Write-Log "$CreatedCount of $Count requested accounts were created."

Disconnect-MgGraph | Out-Null