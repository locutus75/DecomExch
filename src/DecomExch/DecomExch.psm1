Set-StrictMode -Version 2.0

$script:DxLogFile = $null

foreach ($folder in 'Private', 'Public') {
    $path = Join-Path -Path $PSScriptRoot -ChildPath $folder
    foreach ($file in Get-ChildItem -Path $path -Filter '*.ps1' -File) {
        . $file.FullName
    }
}
