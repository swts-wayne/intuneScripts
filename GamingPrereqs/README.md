# GamingPrereqs for Steam Shared Devices

## Purpose

This package installs common Steam game prerequisites and creates Steam Common Redistributable completion markers to prevent first-launch elevation prompts on Intune-managed Shared Devices.

This package was developed after troubleshooting an issue where Steam games would fail to launch for standard users, displaying:

> "This app has been blocked. Contact your administrator"

Steam would then remain stuck on:

> Running Install Script

Investigation showed that Steam was attempting to execute:

```text
SteamService.exe /installscript
```

which required elevation during first launch. When elevation was unavailable, Steam never created its prerequisite-completion registry markers and would repeatedly attempt to run the install script.

This package pre-installs the required prerequisites and creates the registry markers Steam expects.

---
## Tested Games
 - BongoCat
 - Ultimate Chicken Horse
 - Cryptmaster

---
## Components Installed

### Microsoft Visual C++ 2013 Redistributable

- x86
- x64

### Microsoft DirectX End User Runtime (June 2010)

Installs legacy DirectX components commonly required by Steam games.

Future versions may also include:

- Visual C++ 2010 x86/x64
- Visual C++ 2015-2022 x86/x64
- .NET Desktop Runtime
- Other Steam dependencies as required

---

## Steam Registry Markers Created

The package creates the following registry structure:

```text
HKLM\SOFTWARE\WOW6432Node\Valve\Steam\Apps\CommonRedist
```

### DirectX

```text
DirectX\Jun2010
    dxsetup = 1 (DWORD)
```

### Visual C++ 2010

```text
vcredist\2010
    x86 = 1 (DWORD)
    x64 = 1 (DWORD)
```

### Visual C++ 2013

```text
vcredist\2013
    x86 = 12.0.30501 (REG_SZ)
    x64 = 12.0.30501 (REG_SZ)
```

These values were captured from a successfully-completed Steam prerequisite installation.

---

## Intune Deployment

### Install Context

```text
System
```

### Assignment

Recommended:

```text
Required
Device Group
```

### Recommended Dependency Chain

```text
GamingPrereqs
    ↓
Steam
    ↓
Steam Games
```

If Steam is deployed as a Line-of-Business MSI, deploy GamingPrereqs separately as a required application.

---

## Detection Logic

Detection verifies:

```text
HKLM\SOFTWARE\WOW6432Node\Valve\Steam\Apps\CommonRedist
```

contains:

```text
DirectX\Jun2010\dxsetup
vcredist\2010\x86
vcredist\2010\x64
vcredist\2013\x86
vcredist\2013\x64
```

with expected values.

---

## Root Cause Summary

### Symptoms

- Steam game launch failed for standard users.
- Steam displayed "Running Install Script".
- Windows displayed "This app has been blocked. Contact your administrator".
- Launching the game executable directly worked.

### Findings

Steam was attempting to launch:

```text
SteamService.exe /installscript
```

using Steam Common Redistributables.

Steam expected completion markers under:

```text
HKLM\SOFTWARE\WOW6432Node\Valve\Steam\Apps\CommonRedist
```

When these markers were missing, Steam continuously retried the prerequisite installation.

Because Shared Device users were unable to approve the elevated install workflow, Steam never created the required entries and became stuck in a loop.

### Workaround

Pre-create the Steam CommonRedist completion markers.

This allows Steam to skip the elevation workflow and launch affected games normally.

### Outstanding Investigation

Root cause remains partially unresolved.

Further investigation may be required to determine why Steam Client Service is unable to complete its prerequisite workflow automatically on Shared Device configurations despite running under a privileged service context.

---

## Tested Games

| Game | AppID | Result | Notes |
|--------|--------|--------|--------|
| Ultimate Chicken Horse | 386940 | ✅ Success | Original issue resolved |
| | | | |
| | | | |
| | | | |

---

## Testing Procedure

1. Deploy GamingPrereqs.
2. Sync Intune.
3. Reboot device.
4. Install target Steam game.
5. Launch game as standard user.
6. Confirm:
   - No UAC prompt
   - No "Running Install Script" hang
   - Game launches successfully

---

## Version History

### v1.0

Initial release.

Includes:

- VC++ 2013 x86/x64
- DirectX June 2010
- Steam CommonRedist registry markers
- Intune detection script

Created during troubleshooting of Ultimate Chicken Horse on Intune Shared Devices.