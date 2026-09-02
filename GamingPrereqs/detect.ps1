## This detection script isn't checking to see if the redists are installed, it's checking if Steam has validated that they're installed
## This is a deliberate choice, as we need to create the keys manually due to a conflict in how Steam handles launching games as a standard user

## See the README for the list of tested games

##All the relevant keys live here
$ErrorActionPreference = "Stop"

$Base = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam\Apps\CommonRedist"

try {

    $DX = (Get-ItemProperty "$Base\DirectX\Jun2010").dxsetup

    $VC10 = Get-ItemProperty "$Base\vcredist\2010"

    $VC13 = Get-ItemProperty "$Base\vcredist\2013"

    $DXFile = Test-Path "C:\Windows\System32\XInput1_3.dll"

    if (
        $DX -eq 1 -and
        $VC10.x86 -eq 1 -and
        $VC10.x64 -eq 1 -and
        $VC13.x86 -eq "12.0.30501" -and
        $VC13.x64 -eq "12.0.30501" -and
        $DXFile
    ) {
        Write-Host "Detected"
        exit 0
    }

}
catch {
    # Expected when prerequisites not installed
    exit 1
}