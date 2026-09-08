# Student Account Provisioning

This script provisions student accounts in Microsoft Entra ID using the following standard:

| Property | Value |
|-----------|-----------|
| UPN | p###@swts.dev |
| Given Name | Player |
| Surname | ### |
| Usage Location | AU |
| Group Membership | UG_Students |
| Password Expiry | Disabled |

Example accounts:

- p001@swts.dev
- p002@swts.dev
- p003@swts.dev

The script automatically discovers the highest existing numbered student account and continues the sequence.

---

## Requirements

Microsoft Graph PowerShell SDK

Install:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

---

## Required Permissions

The account running the script should have permissions capable of:

- Creating users
- Managing group membership

Typical Graph scopes requested:

```powershell
User.ReadWrite.All
Group.ReadWrite.All
```

---

## Usage

Create 30 student accounts:

```powershell
.\New-Students.ps1 -Count 30
```

Create 10 student accounts:

```powershell
.\New-Students.ps1 -Count 10
```

---

## Numbering Behaviour

The script searches for existing accounts matching:

```text
p###@swts.dev
```

Example:

Existing users:

```text
p001@swts.dev
p002@swts.dev
p003@swts.dev
```

Running:

```powershell
.\New-Students.ps1 -Count 3
```

Creates:

```text
p004@swts.dev
p005@swts.dev
p006@swts.dev
```

---

## Logging

All activity is logged to:

```text
StudentProvisioning.log
```

Example:

```text
[2026-08-21 08:00:01] Connecting to Microsoft Graph...
[2026-08-21 08:00:04] Highest existing student number is 142
[2026-08-21 08:00:05] Creating user p143@swts.dev
[2026-08-21 08:00:06] Successfully created p143@swts.dev
[2026-08-21 08:00:06] Added p143@swts.dev to 'UG_Students'
```

---

## Passwords

Passwords are:

- Randomly generated
- Strong
- Not recorded
- Not displayed
- Password expiry disabled

The passwords only exist long enough for Entra ID account creation.

---

## Notes

If numbering becomes inconsistent because a non-student account matches the naming pattern:

```text
p999@swts.dev
```

the script will use that value as the highest number and continue from there.

This is intentional and keeps the logic simple.