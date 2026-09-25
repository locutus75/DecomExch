function New-DxCheckResult {
    <#
    .SYNOPSIS
        Maakt een uniform resultaatobject voor de uitfaseringscontrole.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [Parameter(Mandatory)]
        [ValidateSet('OK', 'Waarschuwing', 'Blokkerend', 'Info')]
        [string]$Status,

        [string]$Details = '',

        [string]$Oplossing = ''
    )

    [pscustomobject]@{
        PSTypeName = 'DecomExch.CheckResult'
        Check      = $Check
        Status     = $Status
        Details    = $Details
        Oplossing  = $Oplossing
    }
}
