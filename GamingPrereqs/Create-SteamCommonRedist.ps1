## In order to bypass Steam's first-launch "install script", manually create the reg keys it's looking for. This will vary per game as different games have different pre-reqs

##### LIST OF TESTED GAMES #####
## Ultimate Chicken Horse
## BongoCat

$Base = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam\Apps\CommonRedist"

# Create folder structure
New-Item "$Base\DirectX\Jun2010" -Force | Out-Null
New-Item "$Base\vcredist\2010" -Force | Out-Null
New-Item "$Base\vcredist\2013" -Force | Out-Null

# DirectX
New-ItemProperty `
    -Path "$Base\DirectX\Jun2010" `
    -Name "dxsetup" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

# VC++ 2010
New-ItemProperty `
    -Path "$Base\vcredist\2010" `
    -Name "x86" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

New-ItemProperty `
    -Path "$Base\vcredist\2010" `
    -Name "x64" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

# VC++ 2013
New-ItemProperty `
    -Path "$Base\vcredist\2013" `
    -Name "x86" `
    -PropertyType String `
    -Value "12.0.30501" `
    -Force | Out-Null

New-ItemProperty `
    -Path "$Base\vcredist\2013" `
    -Name "x64" `
    -PropertyType String `
    -Value "12.0.30501" `
    -Force | Out-Null

Write-Host "Steam CommonRedist registry markers created."