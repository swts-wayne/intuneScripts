#Check if there are any reg keys for localsend
$App = Get-ItemProperty `
    HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
    HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -like "*LocalSend*"
    }

#if not, assume it's not installed
if ($App) {
    Write-Output "Installed"
    exit 0
}

exit 1