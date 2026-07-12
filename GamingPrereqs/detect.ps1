
##Check for vcredisx86
$vcx86 = Get-ItemProperty `
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\12.0\VC\Runtimes\x86" `
    -ErrorAction SilentlyContinue

##Check for vcredisx64
$vcx64 = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\VisualStudio\12.0\VC\Runtimes\x64" `
    -ErrorAction SilentlyContinue

##Check for directx
$directx = Test-Path "C:\Windows\System32\XInput1_3.dll"

if (
    $vcx86.Installed -eq 1 `
    -and $vcx64.Installed -eq 1 `
    -and $directx
   )
{
    Write-Output "Installed"
    exit 0
}

exit 1