## The Gamebar is actually removed by the debloat script
## The point of this script is to create dummy handlers for the gamebar so that any game calling it thinks it has launched it, when it hasn't

$Protocols = @(
    "ms-gamebar",
    "ms-gamingoverlay"
)

foreach ($Protocol in $Protocols) {

    $Base = "Registry::HKEY_CLASSES_ROOT\$Protocol"

    New-Item $Base -Force | Out-Null

    Set-ItemProperty `
        -Path $Base `
        -Name '(Default)' `
        -Value "URL:$Protocol" `
        -Force

    New-ItemProperty `
        -Path $Base `
        -Name "URL Protocol" `
        -Value "" `
        -PropertyType String `
        -Force | Out-Null

    New-Item "$Base\shell\open\command" -Force | Out-Null

    Set-ItemProperty `
        -Path "$Base\shell\open\command" `
        -Name '(Default)' `
        -Value 'cmd.exe /c exit' `
        -Force
}

Write-Host "Game Bar protocol handlers created."