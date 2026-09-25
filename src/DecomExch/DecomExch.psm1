Set-StrictMode -Version 2.0

$script:DxLogFile = $null
$script:DxLogBuffer = New-Object System.Collections.Generic.List[object]

# Remote verbinding (Connect-DxExchange -Server); inloggegevens alleen in het geheugen.
$script:DxSession = $null
$script:DxSessionModule = $null
$script:DxExchangeServer = $null
$script:DxAuthentication = 'Kerberos'
$script:DxCredential = $null

foreach ($folder in 'Private', 'Public') {
    $path = Join-Path -Path $PSScriptRoot -ChildPath $folder
    foreach ($file in Get-ChildItem -Path $path -Filter '*.ps1' -File) {
        . $file.FullName
    }
}
