function Test-DxDecomReadiness {
    <#
    .SYNOPSIS
        Controleert of een Exchange-server veilig kan worden uitgefaseerd (alleen lezen).
    .DESCRIPTION
        Voert een reeks controles uit en geeft per controle een status terug:
          OK           - niets te doen
          Info         - ter informatie
          Waarschuwing - controleren of opruimen, maar niet blokkerend voor de-installatie
          Blokkerend   - moet opgelost zijn voordat Exchange kan worden verwijderd
    .EXAMPLE
        Test-DxDecomReadiness -Server EX01 | Format-Table -AutoSize -Wrap
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Server
    )

    Assert-DxExchangeShell

    $exServer = Get-ExchangeServer -Identity $Server -ErrorAction Stop
    $name = [string]$exServer.Name
    Write-DxLog -Level Action -Message "Uitfaseringscontrole voor $name ..."

    $results = New-Object System.Collections.Generic.List[object]
    $add = { param($r) $results.Add($r) }

    # --- Algemeen ------------------------------------------------------------
    & $add (New-DxCheckResult -Check 'Server' -Status Info -Details ("{0} - {1} - rol(len): {2}" -f $name, $exServer.AdminDisplayVersion, $exServer.ServerRole))

    $otherServers = @(Get-ExchangeServer | Where-Object { $_.Name -ne $name -and "$($_.ServerRole)" -notmatch 'Edge' })
    $isLastServer = $otherServers.Count -eq 0

    if ($isLastServer) {
        & $add (New-DxCheckResult -Check 'Laatste Exchange-server' -Status Waarschuwing `
            -Details 'Dit is de laatste (niet-Edge) Exchange-server in de organisatie.' `
            -Oplossing ('Worden gebruikers gesynchroniseerd met Entra ID (hybride), verwijder Exchange dan niet volledig maar ' +
                'stap over op de Exchange Management Tools (Exchange 2019 CU12+ / Exchange SE) voor ontvangerbeheer. ' +
                'Controleer dat MX, Autodiscover en SPF naar Exchange Online wijzen voordat de server wordt uitgeschakeld.'))
    }
    else {
        & $add (New-DxCheckResult -Check 'Laatste Exchange-server' -Status OK -Details ("Overige servers: {0}" -f (($otherServers | ForEach-Object { $_.Name }) -join ', ')))
    }

    # --- DAG -------------------------------------------------------------------
    $dags = @(Invoke-DxSafe -Section 'DAG' -Action {
        Get-DatabaseAvailabilityGroup -ErrorAction Stop | Where-Object { @($_.Servers | ForEach-Object { "$_" }) -contains $name }
    })
    if ($dags.Count -gt 0) {
        & $add (New-DxCheckResult -Check 'DAG-lidmaatschap' -Status Blokkerend `
            -Details ("Server is lid van DAG: {0}" -f (($dags | ForEach-Object { $_.Name }) -join ', ')) `
            -Oplossing 'Verwijder eerst alle databasekopieen op deze server (Remove-MailboxDatabaseCopy) en daarna de server uit de DAG (Remove-DatabaseAvailabilityGroupServer).')
    }
    else {
        & $add (New-DxCheckResult -Check 'DAG-lidmaatschap' -Status OK -Details 'Geen DAG-lid.')
    }

    # --- Databases en mailboxen ---------------------------------------------------
    $databases = @(Get-MailboxDatabase -Server $name -ErrorAction SilentlyContinue)
    if ($databases.Count -eq 0) {
        & $add (New-DxCheckResult -Check 'Mailboxdatabases' -Status OK -Details 'Geen mailboxdatabases op deze server.')
    }
    else {
        & $add (New-DxCheckResult -Check 'Mailboxdatabases' -Status Waarschuwing `
            -Details ("{0} database(s): {1}" -f $databases.Count, (($databases | ForEach-Object { $_.Name }) -join ', ')) `
            -Oplossing 'Verwijder de databases met Remove-MailboxDatabase zodra ze leeg zijn, en ruim daarna de .edb- en logbestanden op.')
    }

    $mailboxChecks = @(
        @{ Type = 'User';         Check = 'Gebruikers-/gedeelde mailboxen'; Status = 'Blokkerend';   Fix = 'Verplaats de mailboxen (New-MoveRequest / migratie naar Exchange Online) of verwijder ze.' }
        @{ Type = 'Arbitration';  Check = 'Arbitration-mailboxen';         Status = 'Blokkerend';   Fix = 'Verplaats naar een andere server: Get-Mailbox -Arbitration -Database <db> | New-MoveRequest -TargetDatabase <doel>. Bij de laatste server: laten staan (Management Tools-scenario).' }
        @{ Type = 'AuditLog';     Check = 'AuditLog-mailboxen';            Status = 'Blokkerend';   Fix = 'Verplaats met Get-Mailbox -AuditLog -Database <db> | New-MoveRequest -TargetDatabase <doel>.' }
        @{ Type = 'AuxAuditLog';  Check = 'AuxAuditLog-mailboxen';         Status = 'Blokkerend';   Fix = 'Verplaats met Get-Mailbox -AuxAuditLog -Database <db> | New-MoveRequest -TargetDatabase <doel>.' }
        @{ Type = 'PublicFolder'; Check = 'Public folder-mailboxen';       Status = 'Blokkerend';   Fix = 'Verplaats of migreer public folders (naar een andere server of Exchange Online) voordat de server wordt verwijderd.' }
        @{ Type = 'Monitoring';   Check = 'Monitoring (health) mailboxen'; Status = 'Waarschuwing'; Fix = 'Health-mailboxen worden door Exchange opnieuw aangemaakt; verwijder ze met Get-Mailbox -Monitoring -Database <db> | Disable-Mailbox voordat de database wordt verwijderd.' }
    )

    foreach ($mc in $mailboxChecks) {
        $found = @(foreach ($db in $databases) { Get-DxMailboxOnDatabase -Database $db.Name -Type $mc.Type })
        if ($found.Count -gt 0) {
            $sample = ($found | Select-Object -First 5 | ForEach-Object { if ($_.PSObject.Properties['DisplayName']) { $_.DisplayName } else { "$_" } }) -join ', '
            if ($found.Count -gt 5) { $sample += ', ...' }
            & $add (New-DxCheckResult -Check $mc.Check -Status $mc.Status -Details ("{0} gevonden: {1}" -f $found.Count, $sample) -Oplossing $mc.Fix)
        }
        else {
            & $add (New-DxCheckResult -Check $mc.Check -Status OK -Details 'Geen gevonden.')
        }
    }

    # --- Verplaatsaanvragen ----------------------------------------------------------
    $dbNames = @($databases | ForEach-Object { $_.Name })
    $moves = @(Invoke-DxSafe -Section 'Verplaatsaanvragen' -Action {
        Get-MoveRequest -ResultSize Unlimited -ErrorAction Stop | Where-Object {
            ($dbNames -contains "$($_.SourceDatabase)") -or ($dbNames -contains "$($_.TargetDatabase)")
        }
    })
    $activeMoves = @($moves | Where-Object { "$($_.Status)" -notmatch '^Completed' })
    if ($activeMoves.Count -gt 0) {
        & $add (New-DxCheckResult -Check 'Verplaatsaanvragen' -Status Blokkerend `
            -Details ("{0} lopende of mislukte aanvraag/aanvragen met deze server als bron of doel." -f $activeMoves.Count) `
            -Oplossing 'Laat de aanvragen afronden of verwijder ze (Remove-MoveRequest).')
    }
    elseif ($moves.Count -gt 0) {
        & $add (New-DxCheckResult -Check 'Verplaatsaanvragen' -Status Waarschuwing `
            -Details ("{0} afgeronde aanvraag/aanvragen." -f $moves.Count) `
            -Oplossing 'Ruim afgeronde aanvragen op via menu-optie "Oude aanvragen opruimen" (Remove-DxStaleRequest).')
    }
    else {
        & $add (New-DxCheckResult -Check 'Verplaatsaanvragen' -Status OK -Details 'Geen aanvragen voor deze server.')
    }

    # --- Transport -------------------------------------------------------------------
    $sendConnectors = @(Invoke-DxSafe -Section 'Send connectors' -Action {
        Get-SendConnector -ErrorAction Stop | Where-Object { @($_.SourceTransportServers | ForEach-Object { "$_" }) -contains $name }
    })
    if ($sendConnectors.Count -eq 0) {
        & $add (New-DxCheckResult -Check 'Send connectors' -Status OK -Details 'Server is geen bronserver van een send connector.')
    }
    foreach ($sc in $sendConnectors) {
        $sources = @($sc.SourceTransportServers | ForEach-Object { "$_" })
        if ($sources.Count -le 1) {
            & $add (New-DxCheckResult -Check "Send connector '$($sc.Name)'" -Status Blokkerend `
                -Details 'Deze server is de enige bronserver van de connector.' `
                -Oplossing 'Voeg een andere bronserver toe (Set-SendConnector -SourceTransportServers) of verwijder de connector als hij niet meer nodig is.')
        }
        else {
            & $add (New-DxCheckResult -Check "Send connector '$($sc.Name)'" -Status Waarschuwing `
                -Details ("Server is een van de bronservers: {0}" -f ($sources -join ', ')) `
                -Oplossing 'Haal deze server uit de lijst SourceTransportServers.')
        }
    }

    $defaultReceive = @('Default', 'Client Proxy', 'Default Frontend', 'Outbound Proxy Frontend', 'Client Frontend') |
        ForEach-Object { "$_ $name" }
    $customReceive = @(Invoke-DxSafe -Section 'Receive connectors' -Action {
        Get-ReceiveConnector -Server $name -ErrorAction Stop | Where-Object { $defaultReceive -notcontains $_.Name }
    })
    if ($customReceive.Count -gt 0) {
        & $add (New-DxCheckResult -Check 'Eigen receive connectors' -Status Waarschuwing `
            -Details ("Niet-standaard connectors: {0}" -f (($customReceive | ForEach-Object { $_.Name }) -join ', ')) `
            -Oplossing ('Controleer welke applicaties, scanners of printers via deze server relayen (Relaygebruik / Get-DxRelayUsage) ' +
                'en verplaats ze (bijv. naar een andere server of Exchange Online / SMTP-relay).'))
    }
    else {
        & $add (New-DxCheckResult -Check 'Eigen receive connectors' -Status OK -Details 'Alleen standaardconnectors.')
    }

    $edge = @(Invoke-DxSafe -Section 'Edge-abonnementen' -Action { Get-EdgeSubscription -ErrorAction Stop })
    if ($edge.Count -gt 0) {
        & $add (New-DxCheckResult -Check 'Edge-abonnementen' -Status Waarschuwing `
            -Details ("{0} Edge-abonnement(en) aanwezig." -f $edge.Count) `
            -Oplossing 'Controleer of de Edge-abonnementen nog naar een andere Mailbox-server kunnen synchroniseren; anders Remove-EdgeSubscription.')
    }

    # --- Client access -------------------------------------------------------------
    $cas = Invoke-DxSafe -Section 'Autodiscover SCP' -Action {
        $cmd = if (Test-DxCommand -Name 'Get-ClientAccessService') { 'Get-ClientAccessService' } else { 'Get-ClientAccessServer' }
        & $cmd -Identity $name -ErrorAction Stop
    }
    if ($cas -and $cas.AutoDiscoverServiceInternalUri) {
        & $add (New-DxCheckResult -Check 'Autodiscover SCP' -Status Waarschuwing `
            -Details ("AutoDiscoverServiceInternalUri: {0}" -f $cas.AutoDiscoverServiceInternalUri) `
            -Oplossing "Voorkom dat Outlook deze server nog benadert: Set-ClientAccessService -Identity $name -AutoDiscoverServiceInternalUri `$null")
    }
    else {
        & $add (New-DxCheckResult -Check 'Autodiscover SCP' -Status OK -Details 'Geen interne Autodiscover-URI ingesteld.')
    }

    # --- Hybride ----------------------------------------------------------------------
    $hybrid = Invoke-DxSafe -Section 'Hybride configuratie' -Action { Get-HybridConfiguration -ErrorAction Stop }
    if ($hybrid) {
        $hybridServers = @($hybrid.SendingTransportServers) + @($hybrid.ReceivingTransportServers) | ForEach-Object { "$_" }
        if ($hybridServers -contains $name) {
            & $add (New-DxCheckResult -Check 'Hybride configuratie' -Status Waarschuwing `
                -Details 'Server is een hybride verzend- of ontvangstserver.' `
                -Oplossing 'Voer de Hybrid Configuration Wizard opnieuw uit met andere transportservers, of schakel mailflow eerst volledig om naar Exchange Online.')
        }
        else {
            & $add (New-DxCheckResult -Check 'Hybride configuratie' -Status Info -Details 'Hybride configuratie aanwezig; deze server wordt er niet in gebruikt.')
        }

        if ($isLastServer) {
            $remote = @(Invoke-DxSafe -Section 'Remote mailboxen' -Action { Get-RemoteMailbox -ResultSize Unlimited -ErrorAction Stop })
            & $add (New-DxCheckResult -Check 'Remote mailboxen' -Status Waarschuwing `
                -Details ("{0} remote mailbox(en) worden via deze organisatie beheerd." -f $remote.Count) `
                -Oplossing 'Houd een beheermogelijkheid voor ontvangers (Exchange Management Tools) aan zolang identiteiten vanuit AD worden gesynchroniseerd.')
        }
    }

    $blockers = @($results | Where-Object { $_.Status -eq 'Blokkerend' }).Count
    if ($blockers -eq 0) {
        Write-DxLog -Level Success -Message "Geen blokkerende punten gevonden voor $name."
    }
    else {
        Write-DxLog -Level Warning -Message "$blockers blokkerend(e) punt(en) gevonden voor $name."
    }

    $results
}
