# xTool Studio (Makeblock.xToolStudio) - Intune Win32 package

Deploys xTool Studio to Windows workstations through Intune using winget and PowerShell. Installs for all users into a shared location, creates all-users shortcuts, and stages the RNDIS driver so standard users can connect xTool P2S laser cutters over USB without a UAC prompt.

## Package contents

```
Install.ps1        Installs xTool Studio, cleans up legacy installs, creates shortcuts, stages the RNDIS driver
Detect.ps1         Custom detection script (see "Detection")
Uninstall.ps1      Uninstalls via winget and removes shortcuts and leftover files
Drivers\RNDIS.inf  RNDIS driver (from xTool's DPInsts archive)
Drivers\RNDIS.cat  Catalog file for RNDIS.inf
README.md          This file
```

Winget package ID: `Makeblock.xToolStudio`
Install path: `C:\Program Files\xToolStudio`

## What the install script does

1. Locates `winget.exe` under `C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*` (App Installer must be present on the device).
2. Removes any legacy per-user install. Early deployments ran as SYSTEM and registered a per-user install in SYSTEM's own registry hive. If an xTool uninstall entry is found under `HKCU` (SYSTEM's hive), the script stops the app, runs the NSIS uninstaller in place (`/S _?=<dir>`), deletes the leftovers and removes the stale registry key.
3. Installs with winget using a machine-scope override so the installer registers for all users:
   `winget install --id Makeblock.xToolStudio --exact --silent --scope machine --override "/S /allusers /D=C:\Program Files\xToolStudio"`
   (`/D=` must be last and unquoted. `--location` is not used because `--override` replaces the installer arguments.)
4. Creates all-users Start menu and Public Desktop shortcuts if the installer did not.
5. Checks that the uninstall entry exists under `HKLM` and logs a warning if it does not.
6. Stages the RNDIS driver into the driver store with `pnputil /add-driver Drivers\RNDIS.inf /install`.

Log file: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Winget-Makeblock.xToolStudio-Install.log`

## Detection

`Detect.ps1` only reports installed when all four conditions are true:

| Check | Why |
|---|---|
| `winget list --id Makeblock.xToolStudio --exact` finds the package | Package is installed and visible to winget |
| Uninstall entry present under `HKLM` | Install is machine-wide, not in SYSTEM's hive |
| All-users Start menu shortcut exists | Confirms shortcuts were created in a visible location |
| `RNDIS.inf` is present in the driver store (version 1.0.0.0 or newer) | Driver is staged |

Machines that still have the old per-user install fail detection, which makes Intune rerun the install script and migrate them.

If any name in the scripts changes (shortcut name, exe name), update **Install.ps1 and Detect.ps1 together** (and Uninstall.ps1), otherwise detection never passes.

## Intune app settings

| Setting | Value |
|---|---|
| Install command | `powershell.exe -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `powershell.exe -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behaviour | System |
| Device restart behaviour | Determine behaviour based on return codes |
| Return codes | Defaults, with 3010 as soft reboot |
| Requirements | 64-bit Windows 10 or later |
| Detection rule | Custom script: `Detect.ps1` |
| Run script as 32-bit process on 64-bit clients | No |
| Enforce script signature check and run silently | No |

## Uninstall

`Uninstall.ps1` stops the app if it is running, runs `winget uninstall --exact --id Makeblock.xToolStudio`, treats "no installed package found" (`0x8A150014`) as success, then removes the all-users shortcuts and any leftover install folder. It does not touch user profile data (settings and project files under each user's AppData). The staged RNDIS driver is left in the driver store by default. It can be removed with `pnputil /delete-driver oemNN.inf /uninstall /force` (look up the published name with `pnputil /enum-drivers`).

## Drivers

xTool distributes its Windows USB drivers by model: CH340 for the D series, gs32 for the S1, and RNDIS for the F1, F1 Ultra, M1, M1 Ultra and P2 series. P2S devices use RNDIS, which appears as a USB Ethernet/RNDIS Gadget network adapter.

xTool Studio's built-in "Install driver" prompt needs UAC elevation and fails for standard users, so the driver is staged here instead. Staging into the driver store lets Windows bind it automatically when a device is plugged in, without elevation.

- `RNDIS.inf` (Acer provider, 2010, hardware IDs `USB\VID_0525&PID_A4A2` and `USB\VID_0502&PID_3210`) is packaged.
- `rndis11.inf` (Linux gadget INF, hardware IDs `USB\VID_0525&PID_a4a2` and `USB\VID_1d6b&PID_0104&MI_00`) is **not** packaged. It has no `CatalogFile=` entry, so `pnputil` is likely to reject it as unsigned. If a device turns up reporting `USB\VID_1d6b&PID_0104&MI_00`, revisit this.
- Neither INF carries its own driver binary. Both bind Windows' built-in RNDIS driver to specific USB IDs.

To check a device: with the P2S connected over USB, open Device Manager, find the USB Ethernet/RNDIS Gadget (Network adapters), and read Properties > Details > Hardware Ids. Wi-Fi connections do not use this driver.

## First run (manual, per player account)

Setup that cannot be done by the install script because it is per-user:

- xTool Studio's first run asks a few setup questions that need clicking through.
- A mandatory safety brief is shown on first run. Logging in to an xTool account skips it.
- Accounts are generic "player" accounts, normally configured on two laptops each.
- The login window is an embedded browser inside the app, so Google sign-in through an identity provider that only allows FIDO security keys will not work. Use a login method that does not depend on a hardware key.
- The in-app safety brief is a safety control for laser cutters. If it is skipped, make sure an equivalent induction or sign-off happens another way.

After first-run setup, check Developer mode > Install driver in xTool Studio. Installed drivers show greyed-out "Installed" buttons.

## Troubleshooting

| Symptom | What to check |
|---|---|
| Deployment reports failed but the app is installed | Open the install log. A previous bug caused `Cannot bind argument to parameter 'Message' because it is an empty string` right after the pnputil banner, because `Write-Log` rejected empty lines. Fixed with `[AllowEmptyString()]` on `$Message`. |
| Detection never passes | Run `Detect.ps1` as SYSTEM in 64-bit PowerShell (`psexec -s`) and print the four checks. Usual cause: shortcut name in Detect.ps1 does not match what the installer or the script creates. |
| No shortcuts for users | Confirm the shortcut paths exist under `C:\ProgramData\Microsoft\Windows\Start Menu\Programs` and `C:\Users\Public\Desktop`. |
| P2S not found over USB | Check Device Manager for the RNDIS adapter and its hardware IDs, and confirm the driver is staged: `Get-WindowsDriver -Online \| Where-Object OriginalFileName -like '*RNDIS.inf'` |
| Intune stuck on failed after fixing the package | After three failures the IME waits 24 hours (Global Re-evaluation Schedule) before retrying. Retries run detection first and skip the install if the app is detected. To force it, restart the `IntuneManagementExtension` service, or clear the app's Win32Apps reporting and GRS registry keys and restart the service. |
| winget not found | Confirm App Installer is installed and `winget.exe` exists under `C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*`. |

## History

- Initial package forced a shared install path. It installed per-user as SYSTEM and created no shortcuts, and winget could not track the install because the uninstall entry sat in SYSTEM's hive.
- Reworked to install with `/allusers`, clean up legacy installs, create all-users shortcuts and verify the HKLM uninstall entry.
- Detection changed from a winget-only check to the four-part check above so that bad installs are re-run.
- RNDIS driver staging added to the install script, with the driver store added to detection.
- Fixed the `Write-Log` empty-string error that made successful installs report as failed.