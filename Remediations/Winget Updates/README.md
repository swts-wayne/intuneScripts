# Winget app updates via Intune Remediations

Scripts for keeping winget-packaged apps up to date on Windows devices managed with Microsoft Intune.

Apps are first installed as normal Intune Win32 apps (a PowerShell script that calls `winget install`). This repo covers the **update** side: an Intune Remediation that checks a fixed list of packages for pending upgrades and runs `winget upgrade` for any that have one.

## How it works

| Piece | Job |
|---|---|
| Intune Win32 app | First-time install, plus a simple "is it installed" detection rule |
| Remediation detection script | Reports non-compliant (exit 1) if any listed package has an upgrade available |
| Remediation script | Runs `winget upgrade` for each listed package |

Keeping updates in a Remediation rather than in the Win32 app's detection rule means:

- Updates run on a schedule you choose, not whenever Intune re-evaluates the app.
- The Win32 app doesn't flip between "detected" and "not detected" every time a new version is released.
- The same scripts can be run by hand against any list of packages.

Both scripts locate `winget.exe` inside the App Installer folder, because winget is not on `PATH` for the SYSTEM account. They always pass `--source winget`, so Microsoft Store packages are never touched.

## Files

| File | Purpose |
|---|---|
| `detect.ps1` | Remediation detection script. Contains the `$Packages` list. |
| `update.ps1` | Remediation script. Contains the default `-Packages` list. |

Rename these to suit. Whatever you call them, keep the package list the same in both. If the lists drift apart, a package listed only in the detection script is flagged but never fixed, and a package listed only in the remediation script is never flagged.

## Included apps

| Package ID | Notes |
|---|---|
| `LocalSend.LocalSend` | Doesn't reliably update itself |
| `VoltKraft.ImmichFolderWatch` | |

To add an app, add its winget ID to the list in **both** scripts. Check the ID first with `winget search <name>` or `winget show <id>`.

## Excluded apps

Not every package on a device should be in the list.

| App | Why it's excluded |
|---|---|
| `Valve.Steam` | Updates itself when launched, so winget has nothing to add |
| `BlenderFoundation.Blender` | A specific version is required, and that version is enforced by its own detection script in the Intune app |
| Windows Terminal | Ships with Windows as a Store app and is updated through the Microsoft Store |
| Outlook | New Outlook is a Store app; classic Outlook is updated by the Microsoft 365 Apps channel |
| Visual C++ Redistributables | Installed by other software as dependencies, and multiple versions side by side is normal. Only add one if a specific app needs a newer version than the device has |

**Do not use `winget upgrade --all` here.** Winget lists anything it can match to a package, including OS components, Store apps and dependencies that it did not install. Under SYSTEM it also cannot see per-user installs. An explicit list avoids both problems.

## Remediation settings in Intune

- Run this script using the logged-on credentials: **No** (runs as SYSTEM)
- Enforce script signature check: **No**, unless you sign your scripts
- Run script in 64-bit PowerShell: **Yes**
- Schedule: daily or weekly, assigned to a pilot group first

Remediations have Windows licensing requirements, so check these against your own tenant.

## Testing before you deploy

Run the scripts as SYSTEM, since that is the context Intune uses. [PsExec](https://learn.microsoft.com/sysinternals/downloads/psexec) works well for this:

```powershell
winget install --id Microsoft.Sysinternals.PsTools --exact --source winget
psexec -accepteula -s powershell.exe
whoami   # should print: nt authority\system
```

Then, from that shell:

1. Install an older version of a listed package.
2. Run the detection script. It should exit `1` and name the package.
3. Run the remediation script. It should upgrade the package and exit `0`.
4. Run the detection script again. It should exit `0`.

Also run the detection script against a package with nothing pending, to confirm it exits `0`.

## Running it ad hoc

The remediation script accepts a `-Packages` parameter, so you can point it at any list without editing the file:

```powershell
.\Remediate-WingetUpgrades.ps1 -Packages "LocalSend.LocalSend","Some.OtherPackage"
```

For a single device in Intune, use **Run remediation** from the device's page.

## Logging

The remediation script writes to `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Winget-Upgrade.log`, alongside the other Intune Management Extension logs.

## Exit codes

| Script | Exit code | Meaning |
|---|---|---|
| Detection | 0 | All listed packages are up to date, or winget isn't available |
| Detection | 1 | At least one listed package has an upgrade pending |
| Remediation | 0 | Every package was upgraded, or had no applicable upgrade (`0x8A15002B`) |
| Remediation | 1 | winget wasn't found, or at least one upgrade failed |

## Known limitations

- Upgrades can fail or be deferred if the app is running at the time.
- Devices can only upgrade to whatever version the winget repository currently offers.
- Winget can truncate columns when it has no console width. If detection ever misses a package that has an upgrade pending, check the raw output of `winget list` as SYSTEM.
- Per-user installs aren't visible to winget when it runs as SYSTEM.

## Disclaimer

These scripts are provided as-is. Test on a pilot device before deploying broadly.
