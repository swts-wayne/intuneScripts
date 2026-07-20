## The Gamebar is actually removed by the debloat script
## The point of this script is to create dummy handlers for the gamebar so that any game calling it thinks it has launched it, when it hasn't

$Protocols = @(
    "Registry::HKEY_CLASSES_ROOT\ms-gamebar",
    "Registry::HKEY_CLASSES_ROOT\ms-gamingoverlay"
)

foreach ($Protocol in $Protocols) {
    if (-not (Test-Path $Protocol)) {
        Write-Host "Missing: $Protocol"
        exit 1
    }
}

Write-Host "Protocols present"
exit 0