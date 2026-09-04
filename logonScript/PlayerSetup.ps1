Clear-Host

# Load common functions
. "$PSScriptRoot\Common\Logging.ps1"

function Invoke-Module {

    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    Write-Log "Starting module: $Name"

    try {

        & $ScriptPath

        Write-Log "Module completed successfully: $Name"

    }
    catch {

        Write-Log "Module failed: $Name - $_" "ERROR"

    }
}

Write-Log "SWTS Player Provisioning Tool started"

$username = $env:USERNAME

Write-Log "Logged-on user: $username"

Write-Host ""
Write-Host "==========================================="
Write-Host "      SWTS PLAYER PROVISIONING TOOL"
Write-Host "==========================================="
Write-Host ""
Write-Host "1. Configure Synology Drive"
Write-Host "2. Install Printers"
Write-Host "3. Run Everything"
Write-Host ""
Write-Host "Q. Quit"
Write-Host ""

$selection = Read-Host "Select an option"

switch ($selection.ToUpper()) {

    "1" {

        Invoke-Module `
            -Name "Synology Drive" `
            -ScriptPath "$PSScriptRoot\Synology\Deploy-SynologyDrive.ps1"

    }

    "2" {

        Invoke-Module `
            -Name "Printer Installation" `
            -ScriptPath "$PSScriptRoot\Printers\Install-Printers.ps1"

    }

    "3" {

        Invoke-Module `
            -Name "Synology Drive" `
            -ScriptPath "$PSScriptRoot\Synology\Deploy-SynologyDrive.ps1"

        Invoke-Module `
            -Name "Printer Installation" `
            -ScriptPath "$PSScriptRoot\Printers\Install-Printers.ps1"

    }

    "Q" {

        Write-Log "User exited provisioning tool"

    }

    default {

        Write-Log "Invalid selection '$selection'" "WARNING"

    }
}

Write-Log "Provisioning tool finished"
`