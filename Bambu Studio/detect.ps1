$exePath = "C:\Program Files\Bambu Studio\BambuStudio.exe"

if (Test-Path $exePath) {
    $installedVersion = (Get-Item $exePath).VersionInfo.FileVersion
} else {
    Write-Host "Not installed"
    exit 1
}

Write-Host "Installed version: $installedVersion"

try {
    $apiUrl = "https://api.github.com/repos/bambulab/BambuStudio/releases/latest"
    $headers = @{"User-Agent"="Intune-Bambu-Updater"}
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers

    $latestVersion = $release.tag_name.TrimStart("v")
    Write-Host "Latest version: $latestVersion"

    if ([version]$installedVersion -ge [version]$latestVersion) {
        exit 0
    } else {
        exit 1
    }
} catch {
    Write-Host "Failed version check"
    exit 0
}
