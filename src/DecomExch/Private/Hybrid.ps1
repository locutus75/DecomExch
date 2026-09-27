function Get-DxObjectValue {
    <#
    .SYNOPSIS
        Leest een eigenschap veilig (StrictMode) en geeft $null als die niet bestaat.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    $null
}

function Get-DxTextList {
    <#
    .SYNOPSIS
        Een (multi-valued) eigenschap als lijst strings.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return }
    foreach ($v in @($Value)) {
        $text = "$v".Trim()
        if ($text) { $text }
    }
}

function New-DxHybridComponent {
    <#
    .SYNOPSIS
        Uniform object voor een onderdeel van de hybride koppeling.
    .DESCRIPTION
        Actie: Verwijderen, Uitschakelen, Aanpassen (wordt uitgevoerd) of Behouden (alleen ter informatie).
        Standaard: wordt meegenomen als er geen onderdelen zijn gekozen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int]$Volgorde,
        [Parameter(Mandatory)] [string]$Type,
        [Parameter(Mandatory)] [string]$Onderdeel,
        [Parameter(Mandatory)] [string]$Naam,
        [Parameter(Mandatory)] [ValidateSet('Verwijderen', 'Uitschakelen', 'Aanpassen', 'Behouden')] [string]$Actie,
        [bool]$Standaard = $true,
        [string]$Details = '',
        [string]$Opmerking = '',
        [string]$Identity = $Naam
    )

    [pscustomobject]@{
        PSTypeName = 'DecomExch.HybridComponent'
        Id         = "$Type|$Identity"
        Volgorde   = $Volgorde
        Onderdeel  = $Onderdeel
        Naam       = $Naam
        Actie      = $Actie
        Standaard  = ($Standaard -and $Actie -ne 'Behouden')
        Details    = $Details
        Opmerking  = $Opmerking
        Type       = $Type
        Identity   = $Identity
    }
}

function Test-DxOffice365Domain {
    <#
    .SYNOPSIS
        Is dit een Microsoft 365-domein (tenant.onmicrosoft.com / tenant.mail.onmicrosoft.com)?
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] [string]$Domain)

    [bool]("$Domain".Trim().TrimStart('*').TrimStart('.') -match '\.onmicrosoft\.(com|de)$|\.partner\.onmschina\.cn$|\.onmicrosoft\.us$')
}

function Get-DxHybridComponent {
    <#
    .SYNOPSIS
        Zoekt de onderdelen van de hybride koppeling met Exchange Online in de on-premises organisatie.
    .DESCRIPTION
        Wat de Hybrid Configuration Wizard (HCW) aanmaakt of wijzigt, in de volgorde waarin het
        veilig kan worden opgeruimd:
          - IntraOrganizationConnector (OAuth-koppeling, 'HybridIOC - ...')
          - Organization relationship met Exchange Online (free/busy, 'On-premises to O365 - ...')
          - Send connector naar Exchange Online ('Outbound to Office 365 - ...')
          - Remote domain voor het coexistence-domein ('Hybrid Domain - tenant.mail.onmicrosoft.com')
          - TLS-instelling op receive connectors voor mail uit Exchange Online
          - Federated organization identifier en federation trust
          - OAuth: auth servers (ACS / EvoSts) en de partner application Exchange Online
          - Autodiscover service connection point (SCP) in Active Directory
          - Het object HybridConfiguration zelf
        Het accepted domain tenant.mail.onmicrosoft.com wordt bewust behouden: remote mailboxen en
        het adresbeleid gebruiken het nog.
    #>
    [CmdletBinding()]
    param()

    Assert-DxExchangeShell
    $items = New-Object System.Collections.Generic.List[object]

    # --- Organization relationships (bepaalt ook of federatie nog nodig is) -----------------
    $orgRels = @(Invoke-DxSafe -Section 'Organization relationships' -Action { Get-OrganizationRelationship -ErrorAction Stop })
    $otherOrgRels = New-Object System.Collections.Generic.List[string]
    foreach ($rel in $orgRels) {
        $domains = @(Get-DxTextList (Get-DxObjectValue $rel 'DomainNames'))
        $target = "$(Get-DxObjectValue $rel 'TargetApplicationUri')"
        $isCloud = ($target -match 'outlook\.com') -or @($domains | Where-Object { Test-DxOffice365Domain $_ }).Count -gt 0
        if ($isCloud) {
            $items.Add((New-DxHybridComponent -Volgorde 20 -Type 'OrganizationRelationship' -Onderdeel 'Organization relationship' -Naam "$($rel.Name)" -Actie Verwijderen `
                -Details ("Domeinen: {0}; free/busy: {1}" -f ($domains -join ', '), (Get-DxObjectValue $rel 'FreeBusyAccessLevel')) `
                -Opmerking 'Free/busy en MailTips tussen on-premises en Exchange Online stoppen.'))
        }
        else {
            $otherOrgRels.Add("$($rel.Name)")
            $items.Add((New-DxHybridComponent -Volgorde 20 -Type 'OrganizationRelationship' -Onderdeel 'Organization relationship' -Naam "$($rel.Name)" -Actie Behouden `
                -Details ("Domeinen: {0}" -f ($domains -join ', ')) -Opmerking 'Relatie met een andere organisatie (geen Exchange Online); valt buiten de hybride koppeling.'))
        }
    }

    # --- IntraOrganizationConnector (OAuth) ---------------------------------------------------
    foreach ($ioc in @(Invoke-DxSafe -Section 'IntraOrganizationConnector' -Action { Get-IntraOrganizationConnector -ErrorAction Stop })) {
        $domains = @(Get-DxTextList (Get-DxObjectValue $ioc 'TargetAddressDomains'))
        $endpoint = "$(Get-DxObjectValue $ioc 'DiscoveryEndpoint')"
        $isCloud = ($endpoint -match 'outlook\.office365\.com|outlook\.com') -or ("$($ioc.Name)" -like 'HybridIOC*') -or @($domains | Where-Object { Test-DxOffice365Domain $_ }).Count -gt 0
        $items.Add((New-DxHybridComponent -Volgorde 10 -Type 'IntraOrganizationConnector' -Onderdeel 'IntraOrganizationConnector (OAuth)' -Naam "$($ioc.Name)" `
            -Actie $(if ($isCloud) { 'Verwijderen' } else { 'Behouden' }) `
            -Details ("Doeldomeinen: {0}; endpoint: {1}; ingeschakeld: {2}" -f ($domains -join ', '), $endpoint, (Get-DxObjectValue $ioc 'Enabled')) `
            -Opmerking $(if ($isCloud) { 'OAuth-koppeling voor free/busy, eDiscovery en archieven in Exchange Online.' } else { 'Wijst niet naar Exchange Online.' })))
    }

    # --- Send connectors naar Exchange Online ----------------------------------------------------
    foreach ($sc in @(Invoke-DxSafe -Section 'Send connectors' -Action { Get-SendConnector -ErrorAction Stop })) {
        $spaces = @(Get-DxTextList (Get-DxObjectValue $sc 'AddressSpaces'))
        $hosts = @(Get-DxTextList (Get-DxObjectValue $sc 'SmartHosts'))
        $toTenant = @($spaces | Where-Object { Test-DxOffice365Domain (($_ -replace '^smtp:', '') -replace ';\d+$', '') }).Count -gt 0
        $viaEop = @($hosts | Where-Object { $_ -match 'mail\.protection\.outlook\.com|protection\.outlook\.com' }).Count -gt 0
        if (-not ($toTenant -or $viaEop -or "$($sc.Name)" -like 'Outbound to Office 365*')) { continue }

        $allMail = @($spaces | Where-Object { ($_ -replace '^smtp:', '') -match '^\*(;\d+)?$' }).Count -gt 0
        $items.Add((New-DxHybridComponent -Volgorde 30 -Type 'SendConnector' -Onderdeel 'Send connector' -Naam "$($sc.Name)" -Actie Verwijderen -Standaard (-not $allMail) `
            -Details ("Adresruimten: {0}; smarthosts: {1}" -f ($spaces -join ', '), ($hosts -join ', ')) `
            -Opmerking $(if ($allMail) { 'Stuurt ALLE uitgaande mail via Exchange Online. Alleen verwijderen als deze server geen mail meer verstuurt (zie Relaygebruik).' } else { 'Mail van on-premises naar mailboxen in Exchange Online.' })))
    }

    # --- Remote domain voor het coexistence-domein --------------------------------------------------
    foreach ($rd in @(Invoke-DxSafe -Section 'Remote domains' -Action { Get-RemoteDomain -ErrorAction Stop })) {
        $domain = "$(Get-DxObjectValue $rd 'DomainName')"
        if (-not (Test-DxOffice365Domain $domain)) { continue }
        $items.Add((New-DxHybridComponent -Volgorde 40 -Type 'RemoteDomain' -Onderdeel 'Remote domain' -Naam "$($rd.Name)" -Actie Verwijderen `
            -Details "Domein: $domain" -Opmerking 'Instellingen voor mail naar het coexistence-domein (interne afzender, opmaak).'))
    }

    # --- TLS op receive connectors voor Exchange Online -----------------------------------------------
    $servers = @(Get-ExchangeServer | Where-Object { "$($_.ServerRole)" -notmatch 'Edge' } | ForEach-Object { "$($_.Name)" })
    foreach ($srv in $servers) {
        foreach ($rc in @(Get-ReceiveConnector -Server $srv -ErrorAction SilentlyContinue)) {
            $caps = @(Get-DxTextList (Get-DxObjectValue $rc 'TlsDomainCapabilities'))
            if (@($caps | Where-Object { $_ -match 'outlook\.com' }).Count -eq 0) { continue }
            $items.Add((New-DxHybridComponent -Volgorde 50 -Type 'ReceiveConnectorTls' -Onderdeel 'Receive connector (TLS)' -Naam "$($rc.Identity)" -Actie Aanpassen `
                -Details ("TlsDomainCapabilities: {0}; certificaat: {1}" -f ($caps -join ', '), (Get-DxObjectValue $rc 'TlsCertificateName')) `
                -Opmerking 'De vertrouwde TLS-instelling voor Exchange Online (AcceptCloudServicesMail) wordt verwijderd; het certificaat blijft staan.'))
        }
    }

    # --- Federatie ------------------------------------------------------------------------------
    $keepFederation = $otherOrgRels.Count -gt 0
    $keepNote = if ($keepFederation) { "Nog nodig voor: $($otherOrgRels -join ', '). Alleen opruimen als die relaties ook weg mogen." } else { '' }
    $fedOrg = Invoke-DxSafe -Section 'Federated organization identifier' -Action { Get-FederatedOrganizationIdentifier -ErrorAction Stop }
    if ($fedOrg -and ((Get-DxObjectValue $fedOrg 'Enabled') -eq $true -or "$(Get-DxObjectValue $fedOrg 'AccountNamespace')")) {
        $items.Add((New-DxHybridComponent -Volgorde 60 -Type 'FederatedOrganizationIdentifier' -Onderdeel 'Federated organization identifier' -Naam "$(Get-DxObjectValue $fedOrg 'AccountNamespace')" -Identity 'FederatedOrganizationIdentifier' `
            -Actie Uitschakelen -Standaard (-not $keepFederation) `
            -Details ("Ingeschakeld: {0}; domeinen: {1}" -f (Get-DxObjectValue $fedOrg 'Enabled'), (@(Get-DxTextList (Get-DxObjectValue $fedOrg 'Domains')) -join ', ')) `
            -Opmerking $(if ($keepNote) { $keepNote } else { 'Federatie via de Microsoft Federation Gateway (oude free/busy-methode).' })))
    }
    foreach ($trust in @(Invoke-DxSafe -Section 'Federation trust' -Action { Get-FederationTrust -ErrorAction Stop })) {
        $items.Add((New-DxHybridComponent -Volgorde 70 -Type 'FederationTrust' -Onderdeel 'Federation trust' -Naam "$($trust.Name)" -Actie Verwijderen -Standaard (-not $keepFederation) `
            -Details ("Certificaat: {0}" -f (Get-DxObjectValue $trust 'OrgPrivCertificate')) `
            -Opmerking $(if ($keepNote) { $keepNote } else { 'Het federatiecertificaat blijft in het certificaatarchief staan (zie Opruimen > certificaten).' })))
    }

    # --- OAuth ---------------------------------------------------------------------------------------
    foreach ($as in @(Invoke-DxSafe -Section 'Auth servers' -Action { Get-AuthServer -ErrorAction Stop })) {
        $url = "$(Get-DxObjectValue $as 'AuthMetadataUrl')"
        $isCloud = ("$($as.Name)" -match '^(ACS|EvoSts|AzureAD)') -or ($url -match 'accesscontrol\.windows\.net|login\.windows\.net|login\.microsoftonline\.com|sts\.windows\.net')
        if (-not $isCloud) { continue }
        $enabled = Get-DxObjectValue $as 'Enabled'
        $items.Add((New-DxHybridComponent -Volgorde 80 -Type 'AuthServer' -Onderdeel 'OAuth auth server' -Naam "$($as.Name)" `
            -Actie $(if ($enabled -eq $false) { 'Behouden' } else { 'Uitschakelen' }) `
            -Details "Metadata: $url; ingeschakeld: $enabled" `
            -Opmerking $(if ($enabled -eq $false) { 'Al uitgeschakeld.' } else { 'Wordt uitgeschakeld (niet verwijderd), zodat het terug te draaien is.' })))
    }
    foreach ($pa in @(Invoke-DxSafe -Section 'Partner applications' -Action { Get-PartnerApplication -ErrorAction Stop })) {
        if ("$(Get-DxObjectValue $pa 'ApplicationIdentifier')" -ne '00000002-0000-0ff1-ce00-000000000000') { continue }
        $enabled = Get-DxObjectValue $pa 'Enabled'
        $items.Add((New-DxHybridComponent -Volgorde 81 -Type 'PartnerApplication' -Onderdeel 'OAuth partner application' -Naam "$($pa.Name)" `
            -Actie $(if ($enabled -eq $false) { 'Behouden' } else { 'Uitschakelen' }) `
            -Details "Exchange Online (00000002-0000-0ff1-ce00-000000000000); ingeschakeld: $enabled" `
            -Opmerking $(if ($enabled -eq $false) { 'Al uitgeschakeld.' } else { 'Wordt uitgeschakeld (niet verwijderd), zodat het terug te draaien is.' })))
    }

    # --- Autodiscover SCP ------------------------------------------------------------------------------
    foreach ($cas in @(Invoke-DxSafe -Section 'Client Access' -Action { Get-ClientAccessService -ErrorAction Stop })) {
        $uri = "$(Get-DxObjectValue $cas 'AutoDiscoverServiceInternalUri')"
        if (-not $uri) { continue }
        $items.Add((New-DxHybridComponent -Volgorde 85 -Type 'AutodiscoverScp' -Onderdeel 'Autodiscover SCP' -Naam "$($cas.Name)" -Actie Aanpassen -Standaard $false `
            -Details "AutoDiscoverServiceInternalUri: $uri" `
            -Opmerking 'Outlook op domeincomputers zoekt Autodiscover eerst via dit SCP. Leegmaken zodra alle mailboxen in Exchange Online staan, anders blijft Outlook deze server proberen.'))
    }

    # --- Coexistence-domein (behouden) -------------------------------------------------------------
    foreach ($ad in @(Invoke-DxSafe -Section 'Accepted domains' -Action { Get-AcceptedDomain -ErrorAction Stop })) {
        $domain = "$(Get-DxObjectValue $ad 'DomainName')"
        if (-not (Test-DxOffice365Domain $domain)) { continue }
        $items.Add((New-DxHybridComponent -Volgorde 95 -Type 'AcceptedDomain' -Onderdeel 'Accepted domain' -Naam "$($ad.Name)" -Actie Behouden `
            -Details "Domein: $domain" `
            -Opmerking 'Behouden: remote mailboxen (targetAddress) en het e-mailadresbeleid gebruiken dit domein nog.'))
    }

    # --- HybridConfiguration --------------------------------------------------------------------
    $hc = Invoke-DxSafe -Section 'Hybride configuratie' -Action { Get-HybridConfiguration -ErrorAction Stop }
    if ($hc) {
        $items.Add((New-DxHybridComponent -Volgorde 90 -Type 'HybridConfiguration' -Onderdeel 'Hybride configuratie (HCW)' -Naam 'Hybrid Configuration' -Identity 'HybridConfiguration' -Actie Verwijderen `
            -Details ("Domeinen: {0}; features: {1}; transportservers: {2}" -f (@(Get-DxTextList (Get-DxObjectValue $hc 'Domains')) -join ', '),
                (@(Get-DxTextList (Get-DxObjectValue $hc 'Features')) -join ', '),
                (@(Get-DxTextList (Get-DxObjectValue $hc 'SendingTransportServers')) + @(Get-DxTextList (Get-DxObjectValue $hc 'ReceivingTransportServers')) | Select-Object -Unique) -join ', ') `
            -Opmerking 'Het configuratieobject van de Hybrid Configuration Wizard. Zonder dit object past de HCW niets meer aan; opnieuw draaien maakt het weer aan.'))
    }

    $items | Sort-Object Volgorde, Naam
}

function Get-DxHybridPrerequisite {
    <#
    .SYNOPSIS
        Controles voordat de hybride koppeling wordt opgeruimd (alleen lezen).
    #>
    [CmdletBinding()]
    param(
        [object[]]$Component = @()
    )

    $mailboxes = @(Invoke-DxSafe -Section 'Mailboxen' -Action {
        Get-Mailbox -ResultSize Unlimited -ErrorAction Stop | Where-Object { "$($_.RecipientTypeDetails)" -notmatch 'Discovery|Arbitration|Monitoring|AuditLog|PublicFolder' }
    })
    if ($mailboxes.Count -gt 0) {
        New-DxCheckResult -Check 'Mailboxen on-premises' -Status Blokkerend `
            -Details ("{0} mailbox(en) staan nog on-premises, bijv. {1}." -f $mailboxes.Count, (Join-DxTop -Value @($mailboxes | ForEach-Object { "$($_.PrimarySmtpAddress)" }) -Top 5)) `
            -Oplossing 'Migreer deze mailboxen eerst naar Exchange Online (of exporteer ze naar PST en verwijder ze). Zonder hybride koppeling werken mailflow en free/busy tussen beide kanten niet meer.'
    }
    else {
        New-DxCheckResult -Check 'Mailboxen on-premises' -Status OK -Details 'Geen gebruikers-, gedeelde of resourcemailboxen meer on-premises.'
    }

    $moves = @(Invoke-DxSafe -Section 'Verplaatsaanvragen' -Action {
        Get-MoveRequest -ResultSize Unlimited -ErrorAction Stop | Where-Object { "$($_.Status)" -notmatch '^Completed' }
    })
    if ($moves.Count -gt 0) {
        New-DxCheckResult -Check 'Lopende migraties' -Status Blokkerend `
            -Details ("{0} verplaatsaanvraag/-aanvragen nog niet afgerond." -f $moves.Count) `
            -Oplossing 'Rond de migraties af (of verwijder ze) voordat de koppeling wordt verbroken.'
    }
    else {
        New-DxCheckResult -Check 'Lopende migraties' -Status OK -Details 'Geen lopende verplaatsaanvragen.'
    }

    $remote = @(Invoke-DxSafe -Section 'Remote mailboxen' -Action { Get-RemoteMailbox -ResultSize Unlimited -ErrorAction Stop })
    New-DxCheckResult -Check 'Remote mailboxen' -Status Info `
        -Details ("{0} remote mailbox(en) (mailboxen in Exchange Online die vanuit on-premises AD worden beheerd)." -f $remote.Count) `
        -Oplossing 'Zolang Entra Connect gebruikers synchroniseert, beheer je deze ontvangers on-premises. Gebruik daarvoor de Exchange Management Tools (Exchange 2019 CU12+ / Exchange SE), zodat geen draaiende Exchange-server nodig is.'

    $allMail = @($Component | Where-Object { $_.Type -eq 'SendConnector' -and -not $_.Standaard })
    if ($allMail.Count -gt 0) {
        New-DxCheckResult -Check 'Uitgaande mail via Exchange Online' -Status Waarschuwing `
            -Details ("Send connector {0} stuurt alle uitgaande mail via Exchange Online." -f (($allMail | ForEach-Object { $_.Naam }) -join ', ')) `
            -Oplossing 'Controleer met Relaygebruik of applicaties en apparaten nog via deze server mailen, en zet ze eerst om naar Exchange Online.'
    }

    # DNS (vanaf deze computer)
    if (-not (Test-DxCommand -Name 'Resolve-DnsName')) {
        New-DxCheckResult -Check 'DNS (MX / Autodiscover)' -Status Info -Details 'Resolve-DnsName is niet beschikbaar; controleer MX en Autodiscover handmatig.'
        return
    }
    $domains = @(Invoke-DxSafe -Section 'Accepted domains' -Action {
        Get-AcceptedDomain -ErrorAction Stop | Where-Object { "$($_.DomainType)" -ne 'ExternalRelay' } | ForEach-Object { "$($_.DomainName)" } |
            Where-Object { $_ -notmatch '^\*' -and -not (Test-DxOffice365Domain $_) -and $_ -notmatch '\.(local|lan|intern|internal|corp)$' }
    })
    foreach ($d in $domains) {
        $mx = @(Invoke-DxSafe -Section "MX $d" -Action { Resolve-DnsName -Name $d -Type MX -DnsOnly -ErrorAction Stop | Where-Object { $_.PSObject.Properties['NameExchange'] } | ForEach-Object { "$($_.NameExchange)" } })
        if ($mx.Count -eq 0) {
            New-DxCheckResult -Check "MX $d" -Status Info -Details 'Geen MX-record gevonden (of DNS niet bereikbaar).'
        }
        elseif (@($mx | Where-Object { $_ -notmatch '\.mail\.protection\.outlook\.com\.?$' }).Count -gt 0) {
            New-DxCheckResult -Check "MX $d" -Status Waarschuwing -Details ("MX wijst naar: {0}" -f ($mx -join ', ')) `
                -Oplossing 'Laat de MX naar <tenant>.mail.protection.outlook.com wijzen (of naar de mailfilter die daarheen doorstuurt) voordat de koppeling weg is.'
        }
        else {
            New-DxCheckResult -Check "MX $d" -Status OK -Details ("MX wijst naar Exchange Online: {0}" -f ($mx -join ', '))
        }

        $ad = @(Invoke-DxSafe -Section "Autodiscover $d" -Action { Resolve-DnsName -Name "autodiscover.$d" -DnsOnly -ErrorAction Stop | Where-Object { $_.PSObject.Properties['NameHost'] } | ForEach-Object { "$($_.NameHost)" } })
        if ($ad.Count -gt 0 -and @($ad | Where-Object { $_ -match 'autodiscover\.outlook\.com\.?$' }).Count -gt 0) {
            New-DxCheckResult -Check "Autodiscover $d" -Status OK -Details ("autodiscover.$d wijst naar {0}" -f ($ad -join ', '))
        }
        else {
            New-DxCheckResult -Check "Autodiscover $d" -Status Waarschuwing `
                -Details $(if ($ad.Count) { "autodiscover.$d wijst naar $($ad -join ', ')" } else { "autodiscover.$d is geen CNAME naar Exchange Online (of niet gevonden)." }) `
                -Oplossing "Maak autodiscover.$d een CNAME naar autodiscover.outlook.com."
        }
    }
}

function Get-DxHybridManualStep {
    <#
    .SYNOPSIS
        Stappen die buiten de on-premises Exchange-organisatie moeten gebeuren (Exchange Online, DNS, Entra Connect).
    #>
    [CmdletBinding()]
    param(
        [object[]]$Component = @()
    )

    $tenant = @($Component | Where-Object { $_.Type -in 'AcceptedDomain', 'RemoteDomain' } | ForEach-Object { ($_.Details -replace '^Domein:\s*', '') }) |
        Where-Object { $_ -match '^([^.]+)\.mail\.onmicrosoft\.com$' } | ForEach-Object { $Matches[1] } | Select-Object -First 1
    if (-not $tenant) { $tenant = '<tenant>' }

    $step = { param($n, $where, $what, $cmd) [pscustomobject]@{ Stap = $n; Waar = $where; Wat = $what; Opdracht = $cmd } }
    & $step 1 'DNS' 'MX-records naar Exchange Online' "MX -> $tenant.mail.protection.outlook.com (of je mailfilter)"
    & $step 2 'DNS' 'Autodiscover naar Exchange Online' 'autodiscover.<domein>  CNAME  autodiscover.outlook.com'
    & $step 3 'DNS' 'SPF bijwerken' 'Verwijder de on-premises IP-adressen uit het SPF-record; houd include:spf.protection.outlook.com'
    & $step 4 'Exchange Online' 'Verbinden' 'Connect-ExchangeOnline'
    & $step 5 'Exchange Online' 'Hybride connectors verwijderen' "Get-InboundConnector | Where-Object Name -like 'Inbound from *' | Remove-InboundConnector; Get-OutboundConnector | Where-Object Name -like 'Outbound to *' | Remove-OutboundConnector"
    & $step 6 'Exchange Online' 'Organization relationship verwijderen' "Get-OrganizationRelationship | Where-Object Name -like 'O365 to On-premises*' | Remove-OrganizationRelationship"
    & $step 7 'Exchange Online' 'OAuth-koppeling verwijderen' "Get-IntraOrganizationConnector | Where-Object Name -like 'HybridIOC*' | Remove-IntraOrganizationConnector"
    & $step 8 'Exchange Online' 'Migratie-endpoints opruimen (na de laatste migratie)' 'Get-MigrationEndpoint | Remove-MigrationEndpoint'
    & $step 9 'Hybrid Agent' 'Alleen bij moderne hybride (Hybrid Agent)' 'Verwijder de agent: Remove-HybridApplication (module HybridManagement) en deinstalleer "Microsoft Hybrid Service" op de agent-server.'
    & $step 10 'Entra Connect' 'Synchronisatie laten staan' 'Laat Entra Connect gebruikers synchroniseren; beheer ontvangers met de Exchange Management Tools (Exchange 2019 CU12+ / SE) en Add-PSSnapin *RecipientManagement.'
    & $step 11 'Exchange on-premises' 'Server uitfaseren' 'Voer de Uitfaseringscontrole uit en schakel de server daarna uit (laatste server: niet de-installeren als je de Management Tools-methode gebruikt).'
}

function Invoke-DxHybridAction {
    <#
    .SYNOPSIS
        Voert de opruimactie uit voor een onderdeel van Get-DxHybridComponent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Component
    )

    $identity = $Component.Identity
    switch ($Component.Type) {
        'IntraOrganizationConnector' { Remove-IntraOrganizationConnector -Identity $identity -Confirm:$false -ErrorAction Stop }
        'OrganizationRelationship'   { Remove-OrganizationRelationship -Identity $identity -Confirm:$false -ErrorAction Stop }
        'SendConnector'              { Remove-SendConnector -Identity $identity -Confirm:$false -ErrorAction Stop }
        'RemoteDomain'               { Remove-RemoteDomain -Identity $identity -Confirm:$false -ErrorAction Stop }
        'ReceiveConnectorTls' {
            $rc = Get-ReceiveConnector -Identity $identity -ErrorAction Stop
            $keep = @(Get-DxTextList (Get-DxObjectValue $rc 'TlsDomainCapabilities') | Where-Object { $_ -notmatch 'outlook\.com' })
            if ($keep.Count -gt 0) { Set-ReceiveConnector -Identity $identity -TlsDomainCapabilities $keep -Confirm:$false -ErrorAction Stop }
            else { Set-ReceiveConnector -Identity $identity -TlsDomainCapabilities $null -Confirm:$false -ErrorAction Stop }
        }
        'FederatedOrganizationIdentifier' { Set-FederatedOrganizationIdentifier -Enabled $false -Confirm:$false -ErrorAction Stop }
        'FederationTrust' {
            # De trust kan pas weg als de federated organization identifier er niet meer naar verwijst.
            try { Set-FederatedOrganizationIdentifier -DelegationFederationTrust $null -Confirm:$false -ErrorAction Stop } catch { Write-Verbose $_.Exception.Message }
            Remove-FederationTrust -Identity $identity -Confirm:$false -ErrorAction Stop
        }
        'AuthServer'         { Set-AuthServer -Identity $identity -Enabled $false -Confirm:$false -ErrorAction Stop }
        'PartnerApplication' { Set-PartnerApplication -Identity $identity -Enabled $false -Confirm:$false -ErrorAction Stop }
        'AutodiscoverScp'    { Set-ClientAccessService -Identity $identity -AutoDiscoverServiceInternalUri $null -Confirm:$false -ErrorAction Stop }
        'HybridConfiguration' { Remove-HybridConfiguration -Confirm:$false -ErrorAction Stop }
        default { throw "Onderdeel '$($Component.Type)' kan niet automatisch worden opgeruimd." }
    }
}

function Backup-DxHybridConfiguration {
    <#
    .SYNOPSIS
        Slaat de huidige hybride configuratie op (Export-Clixml en een leesbare tekstversie).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -ItemType Directory -Force | Out-Null }
    $file = Join-Path -Path $Path -ChildPath ("HybrideBackup_{0}.xml" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

    $sections = [ordered]@{}
    $get = @{
        'HybridConfiguration'             = { Get-HybridConfiguration -ErrorAction Stop }
        'IntraOrganizationConnector'      = { Get-IntraOrganizationConnector -ErrorAction Stop }
        'OrganizationRelationship'        = { Get-OrganizationRelationship -ErrorAction Stop }
        'SendConnector'                   = { Get-SendConnector -ErrorAction Stop }
        'RemoteDomain'                    = { Get-RemoteDomain -ErrorAction Stop }
        'ReceiveConnector'                = { Get-ExchangeServer | Where-Object { "$($_.ServerRole)" -notmatch 'Edge' } | ForEach-Object { Get-ReceiveConnector -Server "$($_.Name)" -ErrorAction SilentlyContinue } }
        'FederatedOrganizationIdentifier' = { Get-FederatedOrganizationIdentifier -ErrorAction Stop }
        'FederationTrust'                 = { Get-FederationTrust -ErrorAction Stop }
        'AuthServer'                      = { Get-AuthServer -ErrorAction Stop }
        'PartnerApplication'              = { Get-PartnerApplication -ErrorAction Stop }
        'ClientAccessService'             = { Get-ClientAccessService -ErrorAction Stop }
        'AcceptedDomain'                  = { Get-AcceptedDomain -ErrorAction Stop }
    }
    foreach ($key in @($get.Keys | Sort-Object)) {
        $sections[$key] = @(Invoke-DxSafe -Section "Back-up $key" -Action $get[$key])
    }

    $sections | Export-Clixml -LiteralPath $file -Depth 3
    $text = foreach ($key in $sections.Keys) {
        "===== $key ====="
        $sections[$key] | Format-List | Out-String -Width 250
    }
    Set-Content -LiteralPath ([System.IO.Path]::ChangeExtension($file, '.txt')) -Value $text -Encoding UTF8
    $file
}
