$MinVersion = [version]"5.2.3"

$Found = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq "Blender" -and $_.Publisher -eq "Blender Foundation" } |
    ForEach-Object { try { [version]$_.DisplayVersion } catch { } } |
    Where-Object { $_ -ge $MinVersion } |
    Sort-Object -Descending |
    Select-Object -First 1

if ($Found) {
    Write-Output "Blender $Found detected"   # STDOUT + exit 0 = detected
    exit 0
}
exit 1