function Get-DxHybridReport {
    <#
    .SYNOPSIS
        Brengt de hybride koppeling met Exchange Online in kaart (alleen lezen).
    .DESCRIPTION
        Geeft een object met:
          Onderdelen  de on-premises onderdelen van de koppeling en wat er mee gebeurt bij opruimen
                      (Verwijderen, Uitschakelen, Aanpassen of Behouden)
          Controles   voorwaarden: mailboxen/migraties on-premises, uitgaande mail, MX en Autodiscover
          Handmatig   stappen in Exchange Online, DNS en Entra Connect (buiten bereik van deze module)
        Opruimen gaat met Remove-DxHybridConfiguration.
    .EXAMPLE
        (Get-DxHybridReport).Onderdelen | Format-Table Onderdeel, Naam, Actie, Standaard
    #>
    [CmdletBinding()]
    param()

    Assert-DxExchangeShell
    Write-DxLog -Level Action -Message 'Hybride koppeling in kaart brengen ...'

    $components = @(Get-DxHybridComponent)
    $checks = @(Get-DxHybridPrerequisite -Component $components)
    Write-DxLog -Message ("Hybride koppeling: {0} onderdeel/onderdelen, {1} blokkerend punt(en)." -f $components.Count, @($checks | Where-Object Status -eq 'Blokkerend').Count)

    [pscustomobject]@{
        PSTypeName = 'DecomExch.HybridReport'
        Aanwezig   = @($components | Where-Object { $_.Actie -ne 'Behouden' }).Count -gt 0
        Onderdelen = $components
        Controles  = $checks
        Handmatig  = @(Get-DxHybridManualStep -Component $components)
    }
}
