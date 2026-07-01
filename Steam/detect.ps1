#Check if there are any uninstall reg keys for Steam
$App = Get-ItemProperty `
    HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
    HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -like "*Steam*"
    }

#if not, assume it's not installed
if ($App) {
    Write-Output "Installed"
    exit 0
}

exit 1