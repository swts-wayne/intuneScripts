function Get-PlayerNumber {

    return ($env:USERNAME -replace '^p', '')

}

function Get-SteamUsername {

    param([string]$Prefix)

    return "{0}{1:D2}" -f $Prefix, (Get-PlayerNumber)

}

function Get-SteamPassword {

    param([string]$Format)

    $PlayerNumber = "{0:D2}" -f (Get-PlayerNumber)

    return ($Format -f $PlayerNumber)

}