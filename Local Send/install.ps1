Write-Host "Installing LocalSend..."

# Ensure winget exists
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is not available on this system."
    exit 1
}

# Optional: wait a bit for winget to initialise (OOBE can be flaky)
Start-Sleep -Seconds 5

try {
    winget install `
        --id LocalSend.LocalSend `
        --exact `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements `
        --force

    Write-Host "LocalSend installed successfully."
}
catch {
    Write-Error "Failed to install LocalSend: $_"
    exit 1
}
