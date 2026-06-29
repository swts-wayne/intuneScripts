$temp = "$env:TEMP\Bambu_Studio.exe"

try {
    $apiUrl = "https://api.github.com/repos/bambulab/BambuStudio/releases/latest"
    $headers = @{"User-Agent"="Intune-Bambu-Updater"}
    $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers

    $asset = $release.assets | Where-Object { $_.name -match "Bambu_Studio_win.*\.exe" } | Select-Object -First 1

    if (-not $asset) {
        Write-Error "Installer not found"
        exit 1
    }

    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $temp

    Start-Process $temp -ArgumentList "/S" -Wait -NoNewWindow

    Start-Sleep -Seconds 5

    if (Test-Path "C:\Program Files\Bambu Studio\BambuStudio.exe") {
        exit 0
    } else {
        exit 1
    }
} catch {
    Write-Error "Remediation failed"
    exit 1
}
