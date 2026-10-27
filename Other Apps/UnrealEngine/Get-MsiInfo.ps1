<#
.SYNOPSIS
    Helper for filling in the CONFIG block of Deploy-UnrealEngine.ps1. Run on any Windows machine.

.DESCRIPTION
    -ZipPath  : the offline installer zip. Prints its size and SHA256 (for ZipSha256) and lists
                the .msi files inside it with their paths (for MsiRelPath), without extracting.
    -Path     : an MSI (extract the zip first). Prints ProductCode, ProductVersion etc. (for ProductCode).
    -AllProperties : with -Path, dumps the whole MSI Property table so you can find Epic's custom
                public properties (INSTALLLOCATION, the debug symbols switch, etc.) and their defaults.

.EXAMPLE
    .\Get-MsiInfo.ps1 -ZipPath D:\Installers\UnrealEngine-5.X.zip
    .\Get-MsiInfo.ps1 -Path D:\Extracted\Installer\UnrealEngine.msi
    .\Get-MsiInfo.ps1 -Path D:\Extracted\Installer\UnrealEngine.msi -AllProperties
#>
[CmdletBinding()]
param(
    [string]$ZipPath,
    [string]$Path,
    [switch]$AllProperties
)

if (-not $ZipPath -and -not $Path) {
    throw 'Provide -ZipPath and/or -Path. See Get-Help .\Get-MsiInfo.ps1 -Full'
}

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

if ($ZipPath) {
    $ZipPath = (Resolve-Path $ZipPath).Path

    Write-Host "--- Zip: $ZipPath ---"
    Write-Host ("Size   : {0:N1} GB" -f ((Get-Item $ZipPath).Length / 1GB))
    Write-Host 'Computing SHA256 (large file, be patient)...'
    Write-Host ("SHA256 : {0}" -f (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash)

    Write-Host ''
    Write-Host 'MSI files inside the zip (use the path as MsiRelPath if there is more than one):'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $msis = @($zip.Entries | Where-Object { $_.FullName -like '*.msi' })
        if ($msis.Count -eq 0) { Write-Host '  (none found)' }
        foreach ($e in $msis) {
            Write-Host ("  {0}  ({1:N1} MB)" -f ($e.FullName -replace '/', '\'), ($e.Length / 1MB))
        }
        Write-Host ("Total entries in zip: {0}" -f $zip.Entries.Count)
        Write-Host ("Uncompressed size   : {0:N1} GB" -f (($zip.Entries | Measure-Object -Property Length -Sum).Sum / 1GB))
    }
    finally {
        $zip.Dispose()
    }
}

if ($Path) {
    $Path = (Resolve-Path $Path).Path
    Write-Host ''
    Write-Host "--- MSI: $Path ---"

    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($Path, 0))

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
}