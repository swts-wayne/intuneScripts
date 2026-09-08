# Autopilot Registration Utility

This PowerShell script registers a Windows device with Microsoft Autopilot, assigns a Group Tag, waits for profile assignment, optionally upgrades Windows Home to Windows Pro for Pixel Forge devices, and then reboots into the Autopilot experience.

---

## Features

- Registers devices directly with Windows Autopilot
- Assigns Group Tags during registration
- Supports multiple deployment types:
  - Pixel Forge
  - Laptop
  - VM
- Polls Microsoft Graph until an Autopilot profile is assigned
- Automatically upgrades Windows Home to Windows Pro for Pixel Forge devices using the Microsoft generic Pro upgrade key
- Reboots into Autopilot OOBE once registration is complete

---

## Prerequisites

### PowerShell

The script should be run from an elevated PowerShell session.

### Azure AD Application

An Entra ID (Azure AD) application must exist with permissions allowing Autopilot device imports and queries.

The following values are required:

- Tenant ID
- Application (Client) ID
- Client Secret

### Internet Access

The device must be able to access:

- Microsoft Graph
- Microsoft Authentication endpoints
- PowerShell Gallery

---

## Configuration

Create a file named:

```text
secrets.json
```

in the same folder as the script.

Example:

```json
{
    "TenantID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "AppID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "AppSecret": "xxxxxxxxxxxxxxxxxxxxxxxx"
}
```

### Important

The `secrets.json` file contains credentials and should **never be committed to source control**.

Add the following to `.gitignore`:

```text
secrets.json
```

---

## Device Types

When launched, the script prompts for a deployment type:

| Option | Device Type | Group Tag |
|----------|----------|----------|
| 1 | Pixel Forge | forge |
| 2 | Laptop | laptop |
| 3 | VM | vm |

---

## Pixel Forge Behaviour

Pixel Forge devices are supplied with Windows Home.

Once an Autopilot profile has been successfully assigned, the script:

1. Detects the installed Windows edition.
2. If Windows Home (`Core`) is detected, applies the Microsoft generic Windows Pro upgrade key.
3. Reboots the device.

Generic upgrade key used:

```text
VK7JG-NPHTM-C97JM-9MPGT-3V66T
```

This key upgrades the edition from Home to Pro but does **not** activate Windows.

Windows activation should be handled separately through:

- OEM licensing
- MAK activation
- KMS
- Windows Enterprise Subscription Activation

---

## Workflow

```text
Start Script
      |
      v
Select Device Type
      |
      v
Install Autopilot Requirements
      |
      v
Register Device with Autopilot
      |
      v
Poll Microsoft Graph
      |
      v
Profile Assigned?
      |
      +---- No --> Continue polling
      |
      v
Upgrade Home -> Pro (Pixel Forge only)
      |
      v
Reboot
      |
      v
Autopilot OOBE
```

---

## Error Handling

The script stops and displays an error if:

- `secrets.json` is missing
- `secrets.json` is malformed
- Required configuration values are missing
- Autopilot registration fails
- Graph authentication fails
- Windows edition upgrade fails

If profile assignment is not detected within the configured timeout period, the script will notify the operator and reboot anyway.

---

## Logging and Troubleshooting

Useful checks if registration fails:

### Verify Device Appears in Autopilot

In Intune:

```text
Devices
  → Windows
    → Windows Enrollment
      → Devices
```

### Verify Group Tag

Confirm that the Group Tag displayed in Intune matches the selected deployment type.

### Verify Profile Assignment

Check that:

- A deployment profile exists
- The profile targets the correct Autopilot device group
- Dynamic group processing has completed

### Verify Windows Edition

Run:

```powershell
(Get-ComputerInfo).WindowsEditionId
```

Expected results:

```text
Core        = Windows Home
Professional = Windows Pro
```

---

## Notes

- The script installs `Get-WindowsAutopilotInfo` automatically if not already present.
- PowerShell Gallery is configured as a trusted repository during execution.
- Microsoft Graph beta endpoints are currently used to retrieve Autopilot assignment status.
- The script is intended for technician-driven device preparation prior to handing devices over to end users.

---

## Disclaimer

This script is provided as-is and should be tested in a non-production environment before being used at scale.