Write-Log "Starting Synology deployment"

$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$username = $username -replace '^.*\\', '' -replace '@.*$', ''

Write-Log "Normalised username: $username"

$templateFile = "$PSScriptRoot\config-template.json"
$configFile = "$env:TEMP\synology-config.json"

(Get-Content $templateFile -Raw) `
    -replace '__USERNAME__', $username `
    -replace '__SERVER__', $Settings.SynologyServer `
    -replace '__ADMINUSER__', $Secrets.Synology.AdminUser `
    -replace '__PASSWORD__', $Secrets.Synology.AdminPassword |
    Set-Content $configFile -Encoding UTF8

Write-Log "Generated Synology configuration file"

$SynologyClient = "C:\Program Files\Synology\Synology Drive Client\SynologyDrive.exe"

if (Test-Path $SynologyClient) {

    Write-Log "Launching Synology configuration import"

    Start-Process `
        -FilePath $SynologyClient `
        -ArgumentList "-customized_file `"$configFile`"" `
        -Wait

    Write-Log "Synology deployment completed"
}
else {
    Write-Log "Synology Drive client not found" "ERROR"
}