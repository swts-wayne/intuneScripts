# Unreal Engine via Intune (zip hosted on an internal server)

Epic's offline installer is a large `.zip` containing a small MSI plus its payload. Intune ships only `Deploy-UnrealEngine.ps1` and `secrets.json` (a few KB). Each PC then:

1. downloads the zip from your internal server (BITS, resumable, `curl.exe` fallback)
2. verifies the zip's SHA256
3. extracts it with `tar.exe` (falls back to .NET), then deletes the zip
4. runs the MSI from the extracted files silently
5. deletes the extracted files

If the MSI step fails, the next Intune retry reuses the extracted files instead of downloading again.

## VC++ runtime

The offline installer doesn't install the Microsoft Visual C++ runtime, and the editor crashes at launch with a "wrong version of the VC++ redistributable" error if the PC's copy is too old. The script handles this first, before the big download:

- It reads the installed 2015-2022 x64 runtime version from the registry. If it's already at or above `VcRedistMinVersion`, it does nothing.
- Otherwise it downloads Microsoft's current `vc_redist.x64.exe` (`VcRedistUrl`), checks it has a valid Microsoft signature, and installs it silently. No hash is pinned because Microsoft's "latest" link changes; the signature check replaces it.
- It then re-checks the version and fails loudly if it's still below the minimum.
- Exit 3010 (reboot pending) from the redistributable is passed on to Intune as a soft reboot.
- Uninstalling the engine leaves the runtime alone, because other software uses it.

**Set `VcRedistMinVersion`** from a PC where the editor launches (for example after the winget install):

```powershell
$v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
"{0}.{1}.{2}.{3}" -f $v.Major, $v.Minor, $v.Bld, $v.Rbld
```

To serve the installer from your own server instead of Microsoft (offline PCs, or to pin a version), host `vc_redist.x64.exe` there and put its URL in `secrets.json` as `VcRedistUrl`. The signature check still applies.

Logs: `UnrealEngine-<ver>-vcredist.log` in the IME Logs folder, beside the others.

## 1. Gather details (once per engine version)

On any Windows machine:

```powershell
# the zip: size, SHA256, and where the MSI(s) sit inside it
.\Get-MsiInfo.ps1 -ZipPath D:\Installers\UnrealEngine-5.X.zip

# extract the zip somewhere, then read the MSI itself
.\Get-MsiInfo.ps1 -Path D:\Extracted\<path-to>\UnrealEngine.msi
.\Get-MsiInfo.ps1 -Path D:\Extracted\<path-to>\UnrealEngine.msi -AllProperties
```

Fill in the CONFIG block of `Deploy-UnrealEngine.ps1`:

| Config key | From |
|---|---|
| `ZipSha256` | SHA256 line from `-ZipPath` |
| `ZipFileName` | the zip's file name |
| `MsiRelPath` | the MSI path listed from `-ZipPath`. Leave blank only if the zip contains exactly one `.msi` |
| `ProductCode` | ProductCode from `-Path` (needed for uninstall) |
| `ExtraMsiArgs` | optional. Find Epic's debug-symbols property via `-AllProperties` (or Epic's offline installer docs) and add it, e.g. `SOMEPROPERTY=1` |
| `MinFreeGB` | see sizing below |

**Measured for 5.8.4:** zip about 31 GiB, extracted about 40 GB, installed about 75 GB. Extraction peaks at about 71 GB (zip plus extracted), the install stage at about 115 GB (extracted plus installed), and the final footprint is about 75 GB once the staged files are deleted. `MinFreeGB = 130` leaves margin over the install-stage peak.

**Sizing:** `-ZipPath` shows the zip size and total uncompressed size. Peak disk use is roughly the zip plus the extracted files (during extraction), or the extracted files plus the installed engine (during install). The zip is deleted right after extraction. Set `MinFreeGB` above whichever peak is larger, with margin, and check your PCs actually have that free.

## Secrets

The script reads `secrets.json` from its own folder and merges it over the CONFIG block, so any config key can be overridden there. Currently just the download URL:

```json
{ "ZipUrl": "https://files.example.com/ue/UnrealEngine-5.X.zip" }
```

- Commit `secrets-template.json`, never `secrets.json`. Add `secrets.json` and `*.intunewin` to `.gitignore` (the package contains your real `secrets.json`).
- `secrets.json` must sit next to the script when you run `IntuneWinAppUtil`, so it ends up inside the `.intunewin`.
- The script stops with a clear error if the file is missing or `ZipUrl` is still a placeholder.
- It's a plain file on the PC while the install runs, so a local admin can read it. That's fine for a LAN-only URL, but don't put a real credential or token in it.

## 2. File server setup

1. Put the zip somewhere your internal web server serves it (nginx container, Web Station, etc.).
2. Internal DNS + HTTPS (e.g. through your reverse proxy) so the PCs get a valid certificate, then put the full URL in `secrets.json` as `ZipUrl`.
3. Restrict access to your LAN/VLAN (reverse proxy access list and/or NAS firewall). Do not expose it to the internet. The offline installer is licensed to your organisation, so keep it internal.
4. If a reverse proxy is in front: disable compression and asset caching for that host, and add `proxy_buffering off;` and `proxy_max_temp_file_size 0;`. BITS needs `Content-Length` and range support.
5. Test from a client PC:
   ```
   curl.exe -I <ZipUrl>
   curl.exe -r 0-1023 -o NUL -w "%{http_code}\n" <ZipUrl>
   ```
   The first should return 200 with `Accept-Ranges: bytes` and `Content-Length`. The second should print 206.

The pinned SHA256 (delivered through Intune) is what guarantees the file is the right one, whatever the transport.

## 3. Test locally before packaging

Elevated PowerShell on a test PC with `secrets.json` next to the script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Deploy-UnrealEngine.ps1 -Action Install
```

Then confirm:
- The editor exists at `InstallLocation\DetectRelPath`. **Adjust both in the CONFIG block if Epic's folder naming differs from what I assumed.**
- `C:\ProgramData\UEDeploy` is empty afterwards (zip and extracted files cleaned up).
- Logs are in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`: `UnrealEngine-<ver>-Install.log` (script) and `UnrealEngine-<ver>-Install-msi.log` (verbose MSI). Intune's diagnostics collection picks these up. The script appends on each run, so retries are visible in one file.
- Uninstall works: `... -Action Uninstall`.

To test as SYSTEM (what Intune uses): `psexec -s -i powershell.exe`, then run the same command.

The script re-launches itself in 64-bit PowerShell if started as 32-bit, which is how Intune starts it by default.

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
| Max install time | 300 minutes (jitter delay + download + hash + extraction + install all count; adjust after your pilot) |
| Requirements | 64-bit OS, Windows 10 or later, **Disk space required: 130000 MB** (peak is the extracted files plus the installed engine, about 115 GB for 5.8.4; see sizing below) |
| Detection rule | File exists: path `InstallLocation`, file `Engine\Binaries\Win64\UnrealEditor.exe` |
| Return codes | Defaults (0 success, 3010 soft reboot, 1641 hard reboot, 1618 retry) |

One Intune app per engine version, so versions can coexist and be retired independently.

## 6. Rollout

- Assign as **Required** to a small pilot device group (3 to 5 PCs) first and check the logs. Use the pilot to measure how long download, hash, extraction and install each take, and set the max install time from that.
- Then widen to the full group. The random start delay (`MaxJitterSec`) staggers the downloads. If 30 PCs still saturate the server or its link, increase it.
- If the Launcher/Fab is needed, deploy `EpicGames.EpicGamesLauncher` as its own app and make it a dependency.

## Troubleshooting

- **Hash mismatch:** the file on the server changed or the transfer was corrupted. Re-run `Get-MsiInfo.ps1 -ZipPath` against the server's copy and compare to `ZipSha256`.
- **"Expected exactly one .msi":** the zip contains several MSIs. Set `MsiRelPath` to the right one (listed by `-ZipPath`).
- **Not enough free space:** the check uses `MinFreeGB`. Free up space on the PC or lower it if your own sizing shows it's too conservative.
- **Intune shows failed but the log says success:** the detection rule path doesn't match the real install path.
- **Download stalls:** check `Accept-Ranges` and `Content-Length` through the proxy, and `Get-BitsTransfer -AllUsers` on the PC.
- **Exit code 1603 from msiexec:** read `UnrealEngine-<ver>-Install-msi.log` in the IME Logs folder, searching for `Return value 3`. The extracted files stay in `C:\ProgramData\UEDeploy` for the retry.