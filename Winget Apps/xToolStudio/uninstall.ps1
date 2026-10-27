#Uninstall script for Makeblock.xToolStudio via Winget
$ErrorActionPreference = "Stop"

$PackageName  = "Makeblock.xToolStudio"
$InstallPath  = "C:\Program Files\xToolStudio"
$ShortcutName = "xTool Studio.lnk"      # must match the install and detection scripts

# Resolve winget.exe
$Winget = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue
if ($Winget.count -gt 1) {
    $Winget = $Winget[-1].Path
}

if (!$Winget) {
    Write-Error "winget not installed"
    exit 1
}

# Stop the app if it's running, otherwise the uninstaller can leave files behind
Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$InstallPath\*" } |
    Stop-Process -Force

# uninstall via winget
& $Winget uninstall --silent --exact --id $PackageName --accept-source-agreements
$ExitCode = $LASTEXITCODE

# 0x8A150014 = no installed package found, which means there's nothing to uninstall
if ($ExitCode -eq -1978335212) {
    $ExitCode = 0
}

if ($ExitCode -eq 0) {
    # Remove shortcuts, including any we created ourselves, which the uninstaller doesn't know about
    @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\$ShortcutName",
        "$env:PUBLIC\Desktop\$ShortcutName"
    ) | ForEach-Object {
        if (Test-Path $_) { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
    }

    # Remove leftover install folder if the uninstaller left it behind
    if (Test-Path $InstallPath) {
        Remove-Item $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $ExitCode