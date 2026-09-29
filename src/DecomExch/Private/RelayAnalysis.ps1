function Get-DxSmtpReceiveLogFolder {
    <#
    .SYNOPSIS
        Mappen met SMTP Receive-protocollogs op een server (lokale paden op die server).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Server
    )

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($cmd in 'Get-FrontendTransportService', 'Get-TransportService') {
        if (-not (Test-DxCommand -Name $cmd)) { continue }
        $service = & $cmd -Identity $Server -ErrorAction SilentlyContinue
        if ($service -and $service.PSObject.Properties['ReceiveProtocolLogPath'] -and "$($service.ReceiveProtocolLogPath)") {
            $paths.Add("$($service.ReceiveProtocolLogPath)")
        }
    }
    if ($paths.Count -eq 0) {
        $install = Get-DxExchangeInstallPath -ComputerName $Server
        $paths.Add((Join-Path $install 'TransportRoles\Logs\FrontEnd\ProtocolLog\SmtpReceive'))
        $paths.Add((Join-Path $install 'TransportRoles\Logs\Hub\ProtocolLog\SmtpReceive'))
    }
    $paths | Select-Object -Unique
}

function Get-DxExchangeServerAddress {
    <#
    .SYNOPSIS
        IP-adressen van alle Exchange-servers, om hun onderlinge SMTP-verkeer te herkennen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-DxExchangeConnection)) { return }
    foreach ($server in @(Get-ExchangeServer -ErrorAction SilentlyContinue)) {
        $name = if ($server.PSObject.Properties['Fqdn'] -and $server.Fqdn) { "$($server.Fqdn)" } else { "$($server.Name)" }
        try { [System.Net.Dns]::GetHostAddresses($name) | ForEach-Object { $_.IPAddressToString } } catch { }
    }
}

function ConvertTo-DxRelayRecord {
    <#
    .SYNOPSIS
        Zet een SMTP-sessie of message tracking-regel om naar een uniform record voor de analyse.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,

        [ValidateSet('Session', 'Tracking')]
        [string]$Kind = 'Session'
    )

    process {
        if ($Kind -eq 'Session') {
            $remote = Split-DxEndpoint -Endpoint $InputObject.Remote
            $local = Split-DxEndpoint -Endpoint $InputObject.Local
            [pscustomobject]@{
                Client     = $remote.Address
                Port       = $local.Port
                HostName   = $InputObject.Ehlo
                Connector  = $InputObject.Connector
                Server     = $InputObject.Server
                Time       = $InputObject.Start
                Sessions   = 1
                Messages   = [int]$InputObject.Messages
                MessageId  = $null
                Senders    = @($InputObject.Senders)
                Recipients = @($InputObject.Recipients)
                AuthUser   = $InputObject.AuthUser
                AuthMethod = $InputObject.AuthMethod
                Tls        = [bool]$InputObject.Tls
                Detailed   = $true
                # Exchange-servers onderling: poort 2525 (Transport-service) of X-ANONYMOUSTLS.
                ExchangeHop = ($local.Port -eq '2525') -or ($InputObject.PSObject.Properties['AnonymousTls'] -and [bool]$InputObject.AnonymousTls)
            }
        }
        else {
            $original = if ($InputObject.PSObject.Properties['OriginalClientIp']) { "$($InputObject.OriginalClientIp)" } else { '' }
            [pscustomobject]@{
                Client     = if ($original) { $original } else { "$($InputObject.ClientIp)" }
                Port       = ''
                HostName   = if ($original) { '' } else { "$($InputObject.ClientHostname)" }
                Connector  = "$($InputObject.ConnectorId)"
                Server     = "$($InputObject.ServerHostname)"
                Time       = [datetime]$InputObject.Timestamp
                Sessions   = 0
                Messages   = 1
                MessageId  = "$($InputObject.MessageId)"
                Senders    = @("$($InputObject.Sender)".ToLower())
                Recipients = @($InputObject.Recipients | ForEach-Object { "$_".ToLower() })
                AuthUser   = ''
                AuthMethod = ''
                Tls        = $null
                Detailed   = $false
                ExchangeHop = $false
            }
        }
    }
}

function Join-DxTop {
    <#
    .SYNOPSIS
        De eerste N waarden als tekst, met '(+X)' voor de rest.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()]
        [string[]]$Value,

        [int]$Top = 5
    )

    $items = @($Value | Where-Object { $_ })
    if ($items.Count -le $Top) { return ($items -join ', ') }
    '{0} (+{1})' -f (($items | Select-Object -First $Top) -join ', '), ($items.Count - $Top)
}

function Measure-DxRelayMessage {
    <#
    .SYNOPSIS
        Aantal berichten in een set records: berichten uit sessies plus unieke message-id's uit
        message tracking (hetzelfde bericht kan op meerdere servers of hops zijn gelogd).
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [AllowEmptyCollection()]
        [object[]]$Record
    )

    $count = 0
    $ids = New-Object System.Collections.Generic.HashSet[string]
    foreach ($r in $Record) {
        if ($r.MessageId) { [void]$ids.Add($r.MessageId) } else { $count += [int]$r.Messages }
    }
    $count + $ids.Count
}

function Group-DxRelayRecord {
    <#
    .SYNOPSIS
        Vat records samen per client (IP-adres): hoe vaak, door wie en hoe de server wordt gebruikt.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Record,

        [string[]]$Domain,

        [string[]]$ExchangeAddress = @(),

        [switch]$ResolveDns
    )

    foreach ($group in @($Record | Group-Object -Property Client)) {
        $items = @($group.Group)
        $detailed = @($items | Where-Object { $_.Detailed })

        $hostNames = @($items | ForEach-Object { $_.HostName } | Where-Object { $_ } | Sort-Object -Unique)
        $senders = @($items | ForEach-Object { $_.Senders } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | ForEach-Object { $_.Name })
        $recipients = @($items | ForEach-Object { $_.Recipients } | Where-Object { $_ } | Sort-Object -Unique)
        $external = @($recipients | Where-Object { (Test-DxInternalRecipient -Address $_ -Domain $Domain) -eq $false })
        $users = @($detailed | ForEach-Object { $_.AuthUser } | Where-Object { $_ } | Sort-Object -Unique)

        $messages = Measure-DxRelayMessage -Record $items

        $authentication = 'Onbekend'
        $tls = 'Onbekend'
        if ($detailed.Count -gt 0) {
            $authCount = @($detailed | Where-Object { $_.AuthUser -or $_.AuthMethod }).Count
            $authentication = if ($authCount -eq 0) { 'Anoniem' } elseif ($authCount -eq $detailed.Count) { 'Geauthenticeerd' } else { 'Gemengd' }
            $tlsCount = @($detailed | Where-Object { $_.Tls }).Count
            $tls = if ($tlsCount -eq 0) { 'Nee' } elseif ($tlsCount -eq $detailed.Count) { 'Ja' } else { 'Deels' }
        }

        $times = @($items | ForEach-Object { $_.Time } | Sort-Object)
        [pscustomobject]@{
            Client            = $group.Name
            Naam              = Join-DxTop -Value $hostNames -Top 3
            DnsNaam           = if ($ResolveDns) { Resolve-DxHostName -Address $group.Name } else { '' }
            Type              = Get-DxRelayClientType -Address $group.Name -HostName ($hostNames | Select-Object -First 1) -ExchangeAddress $ExchangeAddress -ExchangeHop:(@($items | Where-Object { $_.ExchangeHop }).Count -gt 0)
            Berichten         = $messages
            Sessies           = if ($detailed.Count -gt 0) { $detailed.Count } else { $null }
            Afzenders         = Join-DxTop -Value $senders -Top 5
            AantalAfzenders   = $senders.Count
            Ontvangers        = $recipients.Count
            ExterneOntvangers = if ($null -eq $Domain -or $Domain.Count -eq 0) { $null } else { $external.Count }
            RelayNaarExtern   = $external.Count -gt 0
            Aanmelding        = $authentication
            Accounts          = Join-DxTop -Value $users -Top 3
            TLS               = $tls
            Connectors        = Join-DxTop -Value @($items | ForEach-Object { $_.Connector } | Where-Object { $_ } | Sort-Object -Unique) -Top 3
            Poorten           = (@($items | ForEach-Object { $_.Port } | Where-Object { $_ } | Sort-Object -Unique) -join ', ')
            Servers           = (@($items | ForEach-Object { $_.Server } | Where-Object { $_ } | Sort-Object -Unique) -join ', ')
            EersteKeer        = $times[0]
            LaatsteKeer       = $times[-1]
            VoorbeeldExtern   = Join-DxTop -Value ($external | Select-Object -First 20) -Top 3
        }
    }
}

function Invoke-DxRelayAnalysis {
    <#
    .SYNOPSIS
        Analyseert wie de Exchange-server(s) nog als SMTP-server/relay gebruikt. Zie Get-DxRelayUsage.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Server,

        [ValidateRange(0, 365)]
        [int]$Days = 7,

        [ValidateSet('Auto', 'ProtocolLog', 'MessageTracking', 'Path')]
        [string]$Source = 'Auto',

        [string[]]$Path,

        [string[]]$Domain,

        [switch]$IncludeExchangeServers,

        [switch]$ResolveDns,

        [AllowNull()]
        [pscredential]$Credential
    )

    $end = Get-Date
    $start = if ($Days -gt 0) { $end.AddDays(-$Days) } else { [datetime]::MinValue }
    $notes = New-Object System.Collections.Generic.List[string]
    $records = New-Object System.Collections.Generic.List[object]
    $fileCount = 0
    $usedSource = $Source
    $connected = Test-DxExchangeConnection

    if ($Source -eq 'Path') {
        if (-not $Path) { throw (New-Object System.ArgumentException 'Geef een map met logbestanden op (-Path).') }
    }
    else {
        Assert-DxExchangeShell
        if (-not $Server) {
            $Server = @(Get-ExchangeServer | Where-Object { "$($_.ServerRole)" -notmatch 'Edge' } | ForEach-Object { "$($_.Name)" })
        }
    }

    # Eigen domeinen, om ontvangers als intern of extern te herkennen ('a.nl,b.nl' mag ook).
    $Domain = @($Domain | ForEach-Object { "$_" -split '[,;\s]+' } | Where-Object { $_ })
    if (-not $Domain -and $connected -and (Test-DxCommand -Name 'Get-AcceptedDomain')) {
        $Domain = @(Get-AcceptedDomain -ErrorAction SilentlyContinue | ForEach-Object { "$($_.DomainName)" })
    }
    if (-not $Domain) {
        $notes.Add('Er zijn geen eigen domeinen bekend, dus intern en extern kunnen niet worden onderscheiden. Geef ze op bij "Eigen domeinen" (of -Domain).')
    }
    $exchangeAddress = @(Get-DxExchangeServerAddress)

    # --- SMTP-protocollogs ------------------------------------------------------------------
    $skipped = New-Object System.Collections.Generic.List[string]
    if ($Source -eq 'Path') {
        $files = @(foreach ($p in $Path) {
            if (Test-Path -LiteralPath $p -PathType Leaf) { Get-Item -LiteralPath $p }
            elseif (Test-Path -LiteralPath $p) { Get-ChildItem -LiteralPath $p -Recurse -File -Filter '*.log' -ErrorAction SilentlyContinue }
            else { $notes.Add("Map of bestand '$p' niet gevonden.") }
        })
        $files = @($files | Where-Object { $_.LastWriteTime -ge $start })
        $fileCount = $files.Count
        if ($files.Count -gt 0) {
            $sessions = @(Read-DxSmtpReceiveLog -File $files -Start $start -End $end -ServerLabel 'Map' -SkippedFile $skipped)
            foreach ($r in @($sessions | ConvertTo-DxRelayRecord -Kind Session)) { $records.Add($r) }
            if ($sessions.Count -eq 0) { $notes.Add('De logbestanden bevatten geen SMTP Receive-sessies in deze periode. Gebruik de RECV*.log-bestanden uit de map ProtocolLog\SmtpReceive.') }
        }
    }
    elseif ($Source -in 'Auto', 'ProtocolLog') {
        $cred = Resolve-DxCredential -Credential $Credential
        foreach ($srv in $Server) {
            $folders = @(Get-DxSmtpReceiveLogFolder -Server $srv)
            $drives = @(Mount-DxAdminShare -ComputerName $srv -Path $folders -Credential $cred)
            try {
                $files = @(foreach ($folder in $folders) {
                    $target = ConvertTo-DxUncPath -Path $folder -ComputerName $srv
                    if (Test-Path -LiteralPath $target) {
                        Get-ChildItem -LiteralPath $target -File -Filter 'RECV*.log' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $start }
                    }
                })
                if ($files.Count -eq 0) {
                    $notes.Add("Geen SMTP-protocollogs gevonden op $srv ($($folders -join '; ')). Staat protocol logging aan op de receive connectors, en is \\$srv\C$ bereikbaar?")
                    continue
                }
                $fileCount += $files.Count
                $sessions = @(Read-DxSmtpReceiveLog -File $files -Start $start -End $end -ServerLabel $srv -SkippedFile $skipped)
                foreach ($r in @($sessions | ConvertTo-DxRelayRecord -Kind Session)) { $records.Add($r) }
            }
            finally {
                Dismount-DxAdminShare -Name $drives
            }
        }
        if ($Source -eq 'Auto' -and $records.Count -eq 0) {
            $notes.Add('Geen protocollogs bruikbaar; message tracking is gebruikt (geen informatie over aanmelding en TLS).')
            $usedSource = 'MessageTracking'
        }
        else {
            $usedSource = 'ProtocolLog'
        }
    }
    if ($skipped.Count -gt 0) {
        $notes.Add(("{0} logbestand(en) konden niet worden gelezen en zijn overgeslagen: {1}." -f $skipped.Count, (Join-DxTop -Value $skipped.ToArray() -Top 5)))
    }

    # --- Message tracking --------------------------------------------------------------------
    if ($usedSource -eq 'MessageTracking') {
        if (-not (Test-DxCommand -Name 'Get-MessageTrackingLog')) {
            throw 'Get-MessageTrackingLog is niet beschikbaar in deze Exchange-sessie.'
        }
        foreach ($srv in $Server) {
            try {
                $params = @{ Server = $srv; EventId = 'Receive'; ResultSize = 'Unlimited'; End = $end; ErrorAction = 'Stop' }
                if ($Days -gt 0) { $params['Start'] = $start }
                foreach ($entry in @(Get-MessageTrackingLog @params)) {
                    if ("$($entry.Source)" -ne 'SMTP') { continue }
                    $records.Add((ConvertTo-DxRelayRecord -InputObject $entry -Kind Tracking))
                }
            }
            catch {
                $notes.Add("Message tracking op $srv kon niet worden gelezen: $($_.Exception.Message)")
            }
        }
    }

    # --- Samenvatten --------------------------------------------------------------------------
    $clients = @(Group-DxRelayRecord -Record $records.ToArray() -Domain $Domain -ExchangeAddress $exchangeAddress -ResolveDns:$ResolveDns)
    $excluded = @($clients | Where-Object { $_.Type -eq 'Exchange-server' })
    if (-not $IncludeExchangeServers) { $clients = @($clients | Where-Object { $_.Type -ne 'Exchange-server' }) }
    $clients = @($clients | Sort-Object -Property Berichten -Descending)

    $excludedClients = @($excluded | ForEach-Object { $_.Client })
    $countedRecords = @($records | Where-Object { $IncludeExchangeServers -or ($excludedClients -notcontains $_.Client) })
    $perDay = @($countedRecords | Group-Object -Property { $_.Time.ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Datum = $_.Name; Berichten = Measure-DxRelayMessage -Record @($_.Group) }
    })

    # Aandachtspunten
    $internal = @($clients | Where-Object { $_.Type -eq 'Intern (applicatie/apparaat)' })
    $anonymousRelay = @($clients | Where-Object { $_.RelayNaarExtern -and $_.Aanmelding -in 'Anoniem', 'Gemengd' -and $_.Type -notin 'Exchange-server', 'Exchange Online' })
    $internet = @($clients | Where-Object { $_.Type -eq 'Extern (internet)' })
    $online = @($clients | Where-Object { $_.Type -eq 'Exchange Online' })

    if ($clients.Count -eq 0) {
        $notes.Add('Geen SMTP-verkeer van clients gevonden in deze periode.')
    }
    if ($internal.Count -gt 0) {
        $notes.Add(("{0} interne applicatie(s)/apparaat(en) versturen nog mail via deze server: {1}. Zet ze om naar een andere SMTP-server of relay voordat de server wordt uitgefaseerd." -f $internal.Count, (Join-DxTop -Value ($internal | ForEach-Object { if ($_.Naam) { "$($_.Client) ($($_.Naam))" } else { $_.Client } }) -Top 5)))
    }
    if ($anonymousRelay.Count -gt 0) {
        $notes.Add(("{0} client(s) versturen zonder aanmelding mail naar externe adressen (anonieme relay): {1}." -f $anonymousRelay.Count, (Join-DxTop -Value ($anonymousRelay | ForEach-Object { $_.Client }) -Top 5)))
    }
    if ($internet.Count -gt 0) {
        $notes.Add(("Er komt nog mail binnen van {0} extern(e) server(s) of client(s) op internet. Controleer of het MX-record nog naar deze server wijst." -f $internet.Count))
    }
    if ($online.Count -gt 0) {
        $notes.Add('Er komt mail binnen vanuit Exchange Online (hybride mailflow).')
    }
    if ($excluded.Count -gt 0 -and -not $IncludeExchangeServers) {
        $notes.Add(("Verkeer tussen Exchange-servers ({0} adres(sen)) is niet meegeteld." -f $excluded.Count))
    }

    [pscustomobject]@{
        Bron        = switch ($usedSource) { 'Path' { 'Map met logbestanden' } 'MessageTracking' { 'Message tracking' } default { 'SMTP-protocollogs' } }
        Van         = if ($Days -gt 0) { $start } else { ($records | ForEach-Object { $_.Time } | Sort-Object | Select-Object -First 1) }
        Tot         = $end
        Servers     = if ($Source -eq 'Path') { ($Path -join '; ') } else { ($Server -join ', ') }
        Bestanden   = $fileCount
        Records     = $records.Count
        Clients     = $clients
        PerDag      = $perDay
        Opmerkingen = $notes.ToArray()
    }
}
