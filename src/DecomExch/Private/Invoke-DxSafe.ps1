function Invoke-DxSafe {
    <#
    .SYNOPSIS
        Voert een scriptblock uit en vangt fouten af, zodat een inventarisatie
        doorloopt als een onderdeel niet beschikbaar is (bijv. oudere Exchange-versie).
    .NOTES
        De parameternamen zijn bewust ongebruikelijk: het scriptblock draait in een
        onderliggende scope en zou anders variabelen van de aanroeper (zoals $Name)
        kunnen overschaduwen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Section,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    try {
        & $Action
    }
    catch {
        Write-DxLog -Level Warning -Message "Onderdeel '$Section' kon niet worden opgehaald: $($_.Exception.Message)"
        # Verbroken remote sessie: opruimen, zodat de volgende onderdelen niet elk opnieuw gaan verbinden.
        if ($_.Exception -is [System.Management.Automation.Remoting.PSRemotingTransportException] -or
            $_.Exception.Message -match 'No session has been associated|implicit remoting|PSSessionStateBroken|The session state is Broken') {
            [void](Test-DxExchangeConnection)
        }
    }
}
