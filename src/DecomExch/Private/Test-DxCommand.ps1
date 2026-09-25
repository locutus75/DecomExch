function Test-DxCommand {
    <#
    .SYNOPSIS
        Geeft $true terug als het opgegeven (Exchange) commando beschikbaar is.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Assert-DxExchangeShell {
    <#
    .SYNOPSIS
        Stopt met een duidelijke fout als er geen Exchange-sessie actief is.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-DxCommand -Name 'Get-ExchangeServer')) {
        throw 'Geen Exchange-cmdlets gevonden. Start de Exchange Management Shell of gebruik eerst Connect-DxExchange.'
    }
}
