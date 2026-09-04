## This is the wifi connect script we can use separately for troubleshooting
## Just run: powershell.exe -executionpolicy bypass -file .\wifi.ps1 in the console

# ============================
# CONFIG
# ============================
$secretsPath = Join-Path $PSScriptRoot "secrets.json"

if (-not (Test-Path $secretsPath)) {
    throw "Missing secrets.json file"
}

try {
    $secret = Get-Content $secretsPath -Raw | ConvertFrom-Json
}
catch {
    throw "Failed to parse secrets.json"
}

$WifiSSID = $secret.WifiSSID
$WifiPSK  = $secret.WifiPSK

# Basic validation
if (-not $WifiSSID -or -not $WifiPSK) {
    throw "secret.json is missing required values"
}

# Connect to the WiFi network
if ($WifiSSID -and $WifiPSK) {

    Write-Host "Configuring Wi-Fi profile..." -ForegroundColor Cyan

    $wifiProfile = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$WifiSSID</name>
    <SSIDConfig>
        <SSID>
            <name>$WifiSSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$WifiPSK</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

    $profilePath = Join-Path $env:TEMP "wifi-profile.xml"

    $wifiProfile | Out-File -FilePath $profilePath -Encoding UTF8

    netsh wlan add profile filename="$profilePath" | Out-Null
    netsh wlan connect name="$WifiSSID" | Out-Null

    Start-Sleep -Seconds 5

    Write-Host "Wi-Fi connection attempted." -ForegroundColor Green
}

# Do a quick test to ensure the network is working and we can get to a relevant endpoint
Write-Host "Testing internet connectivity..." -ForegroundColor Cyan

try {

    $client = [System.Net.Sockets.TcpClient]::new()
    $client.Connect("login.microsoftonline.com", 443)

    if ($client.Connected) {
        Write-Host "Internet connectivity verified." -ForegroundColor Green
    }

    $client.Dispose()

}
catch {

    Write-Host "Unable to reach Microsoft login services." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1

}
