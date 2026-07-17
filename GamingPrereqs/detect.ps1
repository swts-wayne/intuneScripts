## This detection script isn't checking to see if the redists are installed, it's checking if Steam has validated that they're installed
## This is a deliberate choice, as we need to create the keys manually due to a conflict in how Steam handles launching games as a standard user

## See the README for the list of tested games

##All the relevant keys live here
$Base = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam\Apps\CommonRedist"

try {

    $DX = (Get-ItemProperty "$Base\DirectX\Jun2010").dxsetup
    $VC10x86 = (Get-ItemProperty "$Base\vcredist\2010").x86
    $VC10x64 = (Get-ItemProperty "$Base\vcredist\2010").x64
    $VC13x86 = (Get-ItemProperty "$Base\vcredist\2013").x86
    $VC13x64 = (Get-ItemProperty "$Base\vcredist\2013").x64

    if (
        $DX -eq 1 -and
        $VC10x86 -eq 1 -and
        $VC10x64 -eq 1 -and
        $VC13x86 -eq "12.0.30501" -and
        $VC13x64 -eq "12.0.30501"
       )
    {
        Write-Host "Installed"
        exit 0
    }

}
catch {}

exit 1