Write-Log "Starting Steam configuration"

try {

    $ConfigPath = Join-Path $PSScriptRoot "..\Config"

    $Secrets = Get-Content (
        Join-Path $ConfigPath "Secrets.json"
    ) -Raw | ConvertFrom-Json

    $PlayerNumber = ($env:USERNAME -replace '^p', '')
    $PlayerNumber = [int]$PlayerNumber

    $SteamUsername = "{0}{1:D2}" -f `
        $Secrets.Steam.UsernamePrefix, `
        $PlayerNumber

    $SteamPassword = $Secrets.Steam.PasswordFormat -f (
        "{0:D2}" -f $PlayerNumber
    )

    Write-Log "Steam account derived: $SteamUsername"

    # Put the password on the clipboard
    Set-Clipboard $SteamPassword

    Write-Log "Steam password copied to clipboard"

    # Launch Steam
    Start-Process "steam.exe"

    Write-Host ""
    Write-Host "Steam Username: $SteamUsername"
    Write-Host "Password has been copied to clipboard."
    Write-Host ""

    Write-Log "Steam launched successfully"

}
catch {

    Write-Log "Steam configuration failed: $_" "ERROR"
    throw

}