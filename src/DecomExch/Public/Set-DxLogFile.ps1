function Set-DxLogFile {
    <#
    .SYNOPSIS
        Stelt het logbestand in waarin alle acties van DecomExch worden vastgelegd.
    .EXAMPLE
        Set-DxLogFile -Path C:\DecomExch\Logs
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force -WhatIf:$false -Confirm:$false | Out-Null
    }

    $script:DxLogFile = Join-Path -Path $Path -ChildPath ('DecomExch_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Write-DxLog -Message "Logbestand: $script:DxLogFile"
    $script:DxLogFile
}
