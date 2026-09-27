function Remove-DxHybridConfiguration {
    <#
    .SYNOPSIS
        Ruimt de hybride koppeling met Exchange Online op aan de on-premises kant.
    .DESCRIPTION
        Verwijdert of schakelt de onderdelen uit die Get-DxHybridReport vindt, in een veilige volgorde.
        Zonder -Id worden de onderdelen gebruikt die standaard zijn aangevinkt (kolom Standaard);
        onderdelen met actie 'Behouden' worden nooit gewijzigd.

        Voor een echte uitvoering:
          - wordt eerst een back-up (Export-Clixml) van alle gevonden onderdelen gemaakt in -BackupPath;
          - stopt de functie als er blokkerende punten zijn (mailboxen of migraties on-premises),
            tenzij -Force is opgegeven.
        De stappen in Exchange Online, DNS en Entra Connect staan in (Get-DxHybridReport).Handmatig.
    .EXAMPLE
        Remove-DxHybridConfiguration -WhatIf
    .EXAMPLE
        Remove-DxHybridConfiguration -Id 'SendConnector|Outbound to Office 365 - 1234', 'HybridConfiguration|HybridConfiguration'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        # Id's van onderdelen (kolom Id van Get-DxHybridReport). Leeg = de standaardselectie.
        [string[]]$Id,

        # Map voor de back-up van de huidige configuratie.
        [string]$BackupPath = (Join-Path -Path (Get-Location).Path -ChildPath 'Output'),

        # Ook uitvoeren als er nog blokkerende punten zijn.
        [switch]$Force
    )

    Assert-DxExchangeShell

    $all = @(Get-DxHybridComponent)
    if ($Id) {
        $unknown = @($Id | Where-Object { $all.Id -notcontains $_ })
        if ($unknown.Count -gt 0) { throw (New-Object System.ArgumentException ("Onbekend onderdeel: {0}" -f ($unknown -join ', '))) }
        $selected = @($all | Where-Object { $Id -contains $_.Id -and $_.Actie -ne 'Behouden' })
    }
    else {
        $selected = @($all | Where-Object { $_.Standaard })
    }
    if ($selected.Count -eq 0) {
        Write-DxLog -Message 'Hybride koppeling: niets op te ruimen.'
        return
    }

    $live = -not $WhatIfPreference
    if ($live) {
        $blockers = @(Get-DxHybridPrerequisite -Component $all | Where-Object Status -eq 'Blokkerend')
        if ($blockers.Count -gt 0 -and -not $Force) {
            throw ("Hybride koppeling niet opgeruimd: {0}. Los dit eerst op, of gebruik -Force." -f (($blockers | ForEach-Object { "$($_.Check): $($_.Details)" }) -join ' '))
        }
        $backup = Backup-DxHybridConfiguration -Path $BackupPath
        Write-DxLog -Level Action -Message "Back-up van de hybride configuratie: $backup"
    }

    foreach ($c in @($selected | Sort-Object Volgorde)) {
        $result = [pscustomobject]@{
            Onderdeel  = $c.Onderdeel
            Naam       = $c.Naam
            Actie      = $c.Actie
            Uitgevoerd = $false
            Opmerking  = $c.Opmerking
        }
        if ($PSCmdlet.ShouldProcess("$($c.Onderdeel) '$($c.Naam)'", $c.Actie)) {
            try {
                Invoke-DxHybridAction -Component $c
                $result.Uitgevoerd = $true
                $result.Opmerking = ''
                Write-DxLog -Level Action -Message "Hybride koppeling: $($c.Onderdeel) '$($c.Naam)' - $($c.Actie.ToLower())."
            }
            catch {
                $result.Opmerking = $_.Exception.Message
                Write-DxLog -Level Error -Message "Hybride koppeling: $($c.Onderdeel) '$($c.Naam)' mislukt: $($_.Exception.Message)"
            }
        }
        $result
    }
}
