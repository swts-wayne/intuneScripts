# Unreal Engine via Intune (MSI hosted on NAS)

Intune ships only `Deploy-UnrealEngine.ps1` (a few KB). Each PC downloads the MSI from the NAS, verifies its SHA256, and installs it silently.

## 1. Gather MSI details (once per engine version)

On any Windows machine:

```powershell
.\Get-MsiInfo.ps1 -Path D:\Installers\UnrealEngine-5.X.msi
.\Get-MsiInfo.ps1 -Path D:\Installers\UnrealEngine-5.X.msi -AllProperties
```

- Copy **ProductCode** and **SHA256** into the CONFIG block of `Deploy-UnrealEngine.ps1`.
- `-AllProperties` lists the MSI's public properties. Find the debug-symbols switch there (or in Epic's offline installer docs) and put it in `ExtraMsiArgs`, e.g. `SOMEPROPERTY=1`. Leave it empty to take Epic's default.
- Note the size shown; set `MinFreeGB` to roughly MSI size + installed size + margin.

## Secrets

The script reads `secrets.json` from its own folder and merges it over the CONFIG block, so any config key can be overridden there. Currently just the download URL:

```json
{ "MsiUrl": "https://files.example.com/ue/UnrealEngine-5.X.msi" }
```

- Commit `secrets-template.json`, never `secrets.json`. Add `secrets.json` to `.gitignore`.
- `secrets.json` must sit next to the script when you run `IntuneWinAppUtil`, so it ends up inside the `.intunewin`.
- The script stops with a clear error if the file is missing or `MsiUrl` is still a placeholder.
- It's a plain file on the PC while the install runs, so a local admin can read it. That's fine for a LAN-only URL, but don't put a real credential or token in it.

## 2. NAS setup (Synology)

1. Put the MSI in a folder, e.g. `/volume1/web/ue/`.
2. Serve it over HTTP(S) with **Web Station** (a static site or virtual host pointing at that folder). BITS needs the server to support HTTP Range requests; Web Station's nginx does by default.
3. Internal DNS: create a record for the hostname and put the full MSI URL in `secrets.json` as `MsiUrl` (see "Secrets" below).
4. Restrict access to your LAN/VLAN (Web Station / firewall allow-list). Do not expose this to the internet. The offline installer is licensed to your organisation, so keep the file internal.
5. HTTPS is nice but optional: the pinned SHA256 in the script (delivered through Intune) is what guarantees the file is the right one. If you do use HTTPS, the PCs must trust the NAS certificate.
6. Test from a client: `curl.exe -I <your MsiUrl>` should return 200 and `Accept-Ranges: bytes`.

## 3. Test locally before packaging

Elevated PowerShell on a test PC:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Deploy-UnrealEngine.ps1 -Action Install
```

Then confirm:
- The editor exists at `InstallLocation\DetectRelPath`. **Adjust both in the CONFIG block if Epic's folder naming differs from what I assumed.**
- Logs are in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`: `UnrealEngine-<ver>-Install.log` (script) and `UnrealEngine-<ver>-Install-msi.log` (verbose MSI). Intune's diagnostics collection picks these up. The script appends on each run, so retries are visible in one file.
- Uninstall works: `... -Action Uninstall`.

To test as SYSTEM (what Intune uses): `psexec -s -i powershell.exe`, then run the same command.

## 4. Package for Intune

Put **only** `Deploy-UnrealEngine.ps1` and your real `secrets.json` in their own folder (e.g. `src\`), then:

```
IntuneWinAppUtil.exe -c .\src -s Deploy-UnrealEngine.ps1 -o .\out
```

## 5. Intune app settings (Windows app, Win32)

| Setting | Value |
|---|---|
| Install command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Deploy-UnrealEngine.ps1 -Action Install` |
| Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Deploy-UnrealEngine.ps1 -Action Uninstall` |
| Install behavior | System |
| Device restart behavior | No specific action |
| Max install time | 240 minutes (jitter delay + download + install all count) |
| Requirements | 64-bit OS, Windows 10 or later |
| Detection rule | File exists: path `InstallLocation`, file `Engine\Binaries\Win64\UnrealEditor.exe` |
| Return codes | Defaults (0 success, 3010 soft reboot, 1641 hard reboot, 1618 retry) |

One Intune app per engine version, so versions can coexist and be retired independently.

## 6. Rollout

- Assign as **Required** to a small pilot device group (3 to 5 PCs) first and check the logs.
- Then widen to the full group. The random start delay (`MaxJitterSec`) staggers the downloads. If 30 PCs still saturate the NAS or its link, increase it.
- If the Launcher/Fab is needed, deploy `EpicGames.EpicGamesLauncher` as its own app and make it a dependency.

## Troubleshooting

- **Hash mismatch:** the file on the NAS changed or the transfer was corrupted. Re-run `Get-MsiInfo.ps1` against the NAS copy and compare.
- **Intune shows failed but the log says success:** the detection rule path doesn't match the real install path.
- **Download stalls:** check `Accept-Ranges` on the NAS, and `Get-BitsTransfer -AllUsers` on the PC.
- **Exit code 1603 from msiexec:** read `UnrealEngine-<ver>-Install-msi.log` in the IME Logs folder, searching for `Return value 3`.
