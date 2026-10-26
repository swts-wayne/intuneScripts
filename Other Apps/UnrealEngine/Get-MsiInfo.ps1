<#
.SYNOPSIS
    Reads ProductCode, ProductVersion and the SHA256 from an MSI so you can fill in
    the CONFIG block in Deploy-UnrealEngine.ps1. Run on any Windows machine.

.PARAMETER Path
    Path to the Unreal Engine offline installer MSI.

.PARAMETER AllProperties
    Dump the whole MSI Property table. Use this to find Epic's custom public
    properties (INSTALLLOCATION, the debug symbols switch, etc.) and their defaults.

.EXAMPLE
    .\Get-MsiInfo.ps1 -Path D:\Installers\UnrealEngine-5.X.msi
    .\Get-MsiInfo.ps1 -Path D:\Installers\UnrealEngine-5.X.msi -AllProperties
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$AllProperties
)

$Path = (Resolve-Path $Path).Path
$installer = New-Object -ComObject WindowsInstaller.Installer
$db = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($Path, 0))

function Read-Rows {
    param($Database, [string]$Query, [int]$Columns)
    $view = $Database.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $Database, @($Query))
    $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null) | Out-Null
    while ($true) {
        $rec = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)
        if ($null -eq $rec) { break }
        $vals = 1..$Columns | ForEach-Object { $rec.GetType().InvokeMember('StringData', 'GetProperty', $null, $rec, $_) }
        , $vals
    }
    $view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null) | Out-Null
}

if ($AllProperties) {
    Read-Rows -Database $db -Query 'SELECT Property, Value FROM Property' -Columns 2 |
        ForEach-Object { [pscustomobject]@{ Property = $_[0]; Value = $_[1] } } |
        Sort-Object Property | Format-Table -AutoSize -Wrap
}
else {
    $wanted = 'ProductName', 'ProductVersion', 'ProductCode', 'Manufacturer'
    Read-Rows -Database $db -Query 'SELECT Property, Value FROM Property' -Columns 2 |
        Where-Object { $_[0] -in $wanted } |
        ForEach-Object { [pscustomobject]@{ Property = $_[0]; Value = $_[1] } } |
        Format-Table -AutoSize
}

Write-Host 'Computing SHA256 (large file, be patient)...'
$hash = Get-FileHash -Path $Path -Algorithm SHA256
Write-Host ("Size   : {0:N1} GB" -f ((Get-Item $Path).Length / 1GB))
Write-Host ("SHA256 : {0}" -f $hash.Hash)
