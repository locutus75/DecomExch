function Get-DxBodyValue {
    <#
    .SYNOPSIS
        Leest een veld uit de (JSON-)body van een API-verzoek, met standaardwaarde.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Body,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Default = $null
    )

    if ($null -eq $Body) { return $Default }
    if ($Body -is [System.Collections.IDictionary]) {
        if ($Body.Contains($Name) -and $null -ne $Body[$Name]) { return $Body[$Name] }
        return $Default
    }
    $prop = $Body.PSObject.Properties[$Name]
    if ($prop -and $null -ne $prop.Value) { return $prop.Value }
    $Default
}

function Get-DxStringList {
    <#
    .SYNOPSIS
        Maakt van een lijst of van tekst met komma's/regels een opgeschoonde lijst strings.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()]
        [object]$Value
    )

    # Geeft losse strings uit; aanroepers verzamelen ze met @(...).
    if ($null -eq $Value) { return }
    foreach ($v in @($Value)) {
        foreach ($part in ("$v" -split '[,;\r\n]+')) {
            $trimmed = $part.Trim()
            if ($trimmed) { $trimmed }
        }
    }
}

function Assert-DxConfirmed {
    <#
    .SYNOPSIS
        Een echte (niet-gesimuleerde) opruimactie via de webinterface moet met 'JA' bevestigd zijn.
    #>
    [CmdletBinding()]
    param(
        [bool]$Simulate,

        [AllowNull()]
        [object]$Body
    )

    if (-not $Simulate -and (Get-DxBodyValue -Body $Body -Name 'confirm') -cne 'JA') {
        throw (New-Object System.ArgumentException 'Bevestiging ontbreekt: typ JA om deze actie echt uit te voeren.')
    }
}

function Get-DxOverview {
    <#
    .SYNOPSIS
        Samenvatting (kerncijfers) van een inventarisatie voor het dashboard.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Inventory,

        [datetime]$Generated = (Get-Date)
    )

    $section = { param($name) if ($Inventory.Contains($name)) { @($Inventory[$name] | Where-Object { $null -ne $_ }) } else { @() } }

    $mailboxes = @(& $section 'Mailboxen')
    $publicFolders = @(& $section 'Public folders')
    $certs = @(& $section 'Certificaten')
    $moves = @(& $section 'Verplaatsaanvragen')

    $sizeMb = ($mailboxes | Where-Object { $_.PSObject.Properties['GrootteMB'] -and $null -ne $_.GrootteMB } | Measure-Object -Property GrootteMB -Sum).Sum
    $pfSizeMb = ($publicFolders | Where-Object { $_.PSObject.Properties['GrootteMB'] -and $null -ne $_.GrootteMB } | Measure-Object -Property GrootteMB -Sum).Sum

    [ordered]@{
        generated = $Generated.ToString('yyyy-MM-dd HH:mm')
        kpis      = [ordered]@{
            servers              = @(& $section 'Servers').Count
            databases            = @(& $section 'Databases').Count
            mailboxes            = $mailboxes.Count
            mailboxSizeGb        = [math]::Round([double]$sizeMb / 1024, 1)
            inactiveMailboxes    = @($mailboxes | Where-Object { $_.PSObject.Properties['Inactief'] -and $_.Inactief }).Count
            publicFolders        = $publicFolders.Count
            publicFolderSizeMb   = [math]::Round([double]$pfSizeMb, 1)
            disconnected         = @(& $section 'Losgekoppelde mailboxen').Count
            expiredCertificates  = @($certs | Where-Object { $_.PSObject.Properties['Verlopen'] -and $_.Verlopen }).Count
            openMoveRequests     = @($moves | Where-Object { $_.PSObject.Properties['Status'] -and "$($_.Status)" -notmatch '^Completed' }).Count
        }
        servers   = @(& $section 'Servers' | ConvertTo-DxJsonSafe)
        databases = @(& $section 'Databases' | ConvertTo-DxJsonSafe)
        mailboxTypes = @(& $section 'Mailboxtypes' | ConvertTo-DxJsonSafe)
    }
}

function Invoke-DxApiRoute {
    <#
    .SYNOPSIS
        Verwerkt een API-verzoek van de webinterface en geeft een JSON-geschikt resultaat terug.
    .DESCRIPTION
        Los van de HTTP-laag, zodat de routes direct te testen zijn.
        Fouten door ongeldige invoer (ArgumentException) worden 400, overige fouten 500;
        dat onderscheid maakt Start-DxWebUI.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [hashtable]$Query = @{},

        [AllowNull()]
        [object]$Body,

        [Parameter(Mandatory)]
        [hashtable]$State
    )

    $simulate = [bool](Get-DxBodyValue -Body $Body -Name 'simulate' -Default $true)
    $route = '{0} {1}' -f $Method.ToUpper(), $Path.TrimEnd('/').ToLower()

    switch ($route) {
        'GET /api/status' {
            $connected = Test-DxExchangeConnection
            if ($connected -and -not $State['Organization']) {
                $State['Organization'] = Invoke-DxSafe -Section 'Organisatie' -Action { "$((Get-OrganizationConfig -ErrorAction Stop).Name)" }
            }
            return [ordered]@{
                connected    = $connected
                organization = if ($connected) { $State['Organization'] } else { $null }
                user         = $env:USERNAME
                computer     = $env:COMPUTERNAME
                exchangeServer = $script:DxExchangeServer
                account      = if ($script:DxCredential) { $script:DxCredential.UserName } else { $null }
                authentication = $script:DxAuthentication
                version      = "$($MyInvocation.MyCommand.Module.Version)"
                outputPath   = $State['OutputPath']
                logFile      = $script:DxLogFile
            }
        }

        'POST /api/connect' {
            $server = "$(Get-DxBodyValue -Body $Body -Name 'server' -Default '')".Trim()
            if ($server) {
                # Inloggegevens van de start (-Credential) opnieuw gebruiken; het wachtwoord gaat nooit via de browser.
                $authentication = "$(Get-DxBodyValue -Body $Body -Name 'authentication' -Default $script:DxAuthentication)"
                if ($authentication -notin 'Kerberos', 'Negotiate', 'Basic') {
                    throw (New-Object System.ArgumentException "Onbekende aanmeldmethode: $authentication")
                }
                $params = @{ Server = $server; Authentication = $authentication }
                if ($script:DxCredential) { $params['Credential'] = $script:DxCredential }
                Connect-DxExchange @params
            }
            else {
                Connect-DxExchange
            }
            $State['Organization'] = $null
            $State['Inventory'] = $null
            return [ordered]@{ connected = (Test-DxExchangeConnection) }
        }

        'GET /api/servers' {
            Assert-DxExchangeShell
            return ,@(Get-ExchangeServer | Sort-Object Name | ForEach-Object {
                [ordered]@{ name = "$($_.Name)"; role = "$($_.ServerRole)"; version = "$($_.AdminDisplayVersion)"; edge = ("$($_.ServerRole)" -match 'Edge') }
            })
        }

        'GET /api/databases' {
            Assert-DxExchangeShell
            return ,@(Get-MailboxDatabase | Sort-Object Name | ForEach-Object { "$($_.Name)" })
        }

        'GET /api/overview' {
            if (-not $State['Inventory'] -or $Query['refresh']) {
                $State['Inventory'] = Get-DxInventory
                $State['InventoryTime'] = Get-Date
            }
            return Get-DxOverview -Inventory $State['Inventory'] -Generated $State['InventoryTime']
        }

        'GET /api/inventory' {
            if (-not $State['Inventory'] -or $Query['refresh']) {
                $State['Inventory'] = Get-DxInventory
                $State['InventoryTime'] = Get-Date
            }
            return [ordered]@{
                generated = $State['InventoryTime'].ToString('yyyy-MM-dd HH:mm')
                sections  = @(foreach ($key in $State['Inventory'].Keys) {
                    [ordered]@{ name = "$key"; rows = @($State['Inventory'][$key] | Where-Object { $null -ne $_ } | ConvertTo-DxJsonSafe) }
                })
            }
        }

        'POST /api/inventory/report' {
            if (-not $State['Inventory']) { throw (New-Object System.ArgumentException 'Er is nog geen inventarisatie; open eerst het dashboard of de inventaris.') }
            $file = $State['Inventory'] | Export-DxReport -Path $State['OutputPath'] -Title 'Exchange inventarisatie'
            return [ordered]@{ file = $file }
        }

        'POST /api/report' {
            $title = "$(Get-DxBodyValue -Body $Body -Name 'title' -Default 'DecomExch rapport')"
            $rows = @(Get-DxBodyValue -Body $Body -Name 'rows' -Default @())
            if ($rows.Count -eq 0) { throw (New-Object System.ArgumentException 'Geen gegevens om op te slaan.') }
            $file = $rows | Export-DxReport -Path $State['OutputPath'] -Title $title
            return [ordered]@{ file = $file }
        }

        'GET /api/mailboxes' {
            $days = 90
            if ($Query['inactiveDays']) { $days = [int]$Query['inactiveDays'] }
            return ,@(Get-DxMailboxReport -InactiveDays $days | Sort-Object DisplayName | ConvertTo-DxJsonSafe)
        }

        'GET /api/publicfolders' {
            return ,@(Get-DxPublicFolderReport | Sort-Object Map | ConvertTo-DxJsonSafe)
        }

        'POST /api/relay' {
            $source = "$(Get-DxBodyValue -Body $Body -Name 'source' -Default 'Auto')"
            if ($source -notin 'Auto', 'ProtocolLog', 'MessageTracking', 'Path') {
                throw (New-Object System.ArgumentException "Onbekende bron: $source")
            }
            $params = @{
                Source                 = $source
                Days                   = [int](Get-DxBodyValue -Body $Body -Name 'days' -Default 7)
                IncludeExchangeServers = [bool](Get-DxBodyValue -Body $Body -Name 'includeExchangeServers' -Default $false)
                ResolveDns             = [bool](Get-DxBodyValue -Body $Body -Name 'resolveDns' -Default $false)
                Report                 = $true
            }
            if ($params['Days'] -lt 0 -or $params['Days'] -gt 365) { throw (New-Object System.ArgumentException 'Periode moet tussen 0 en 365 dagen liggen.') }
            $servers = @(Get-DxStringList (Get-DxBodyValue -Body $Body -Name 'servers'))
            if ($servers.Count -gt 0) { $params['Server'] = $servers }
            $domains = @(Get-DxStringList (Get-DxBodyValue -Body $Body -Name 'domains'))
            if ($domains.Count -gt 0) { $params['Domain'] = $domains }
            if ($source -eq 'Path') {
                $paths = @(Get-DxStringList (Get-DxBodyValue -Body $Body -Name 'path'))
                if ($paths.Count -eq 0) { throw (New-Object System.ArgumentException 'Geef de map met logbestanden op.') }
                $params['Path'] = $paths
            }

            $r = Get-DxRelayUsage @params
            $format = { param($d) if ($d -is [datetime] -and $d -gt [datetime]::MinValue) { $d.ToString('yyyy-MM-dd HH:mm') } else { $null } }
            return [ordered]@{
                source  = $r.Bron
                from    = & $format $r.Van
                to      = & $format $r.Tot
                servers = $r.Servers
                files   = $r.Bestanden
                records = $r.Records
                clients = @($r.Clients | ConvertTo-DxJsonSafe)
                perDay  = @($r.PerDag | ConvertTo-DxJsonSafe)
                notes   = @($r.Opmerkingen)
            }
        }

        'GET /api/receiveconnectors' {
            return ,@(Get-DxReceiveConnectorReport | ConvertTo-DxJsonSafe)
        }

        'POST /api/readiness' {
            $server = "$(Get-DxBodyValue -Body $Body -Name 'server' -Default '')".Trim()
            if (-not $server) { throw (New-Object System.ArgumentException 'Kies een server.') }
            $checks = @(Test-DxDecomReadiness -Server $server)
            return [ordered]@{
                server    = $server
                blockers  = @($checks | Where-Object Status -eq 'Blokkerend').Count
                warnings  = @($checks | Where-Object Status -eq 'Waarschuwing').Count
                checks    = @($checks | ConvertTo-DxJsonSafe)
            }
        }

        'POST /api/export/mailboxes' {
            $params = @{
                FilePath       = "$(Get-DxBodyValue -Body $Body -Name 'filePath' -Default '')".Trim()
                IncludeArchive = [bool](Get-DxBodyValue -Body $Body -Name 'includeArchive' -Default $false)
                WhatIf         = $simulate
                Confirm        = $false
            }
            switch ("$(Get-DxBodyValue -Body $Body -Name 'mode' -Default 'selection')") {
                'all'      { $params['All'] = $true }
                'database' {
                    $params['Database'] = @(Get-DxStringList (Get-DxBodyValue -Body $Body -Name 'databases'))
                    if ($params['Database'].Count -eq 0) { throw (New-Object System.ArgumentException 'Kies minimaal een database.') }
                }
                default {
                    $params['Identity'] = @(Get-DxStringList (Get-DxBodyValue -Body $Body -Name 'identities'))
                    if ($params['Identity'].Count -eq 0) { throw (New-Object System.ArgumentException 'Kies minimaal een mailbox.') }
                }
            }
            if ($params['FilePath'] -notmatch '^\\\\[^\\]+\\[^\\]+') {
                throw (New-Object System.ArgumentException 'Geef een UNC-pad op (\\server\share): Exchange schrijft de PST zelf weg.')
            }
            return ,@(Export-DxMailboxToPst @params | ConvertTo-DxJsonSafe)
        }

        'POST /api/export/publicfolders' {
            $filePath = "$(Get-DxBodyValue -Body $Body -Name 'filePath' -Default '')".Trim()
            if (-not $filePath) { throw (New-Object System.ArgumentException 'Geef een PST-bestand of map op.') }
            $folders = @(Get-DxStringList (Get-DxBodyValue -Body $Body -Name 'folders' -Default '\'))
            if ($folders.Count -eq 0) { $folders = @('\') }
            return ,@(Export-DxPublicFolderToPst -FolderPath $folders -FilePath $filePath -WhatIf:$simulate -Confirm:$false | ConvertTo-DxJsonSafe)
        }

        'GET /api/export/status' {
            return ,@(Get-DxPstExportStatus | ConvertTo-DxJsonSafe)
        }

        'POST /api/clean/logs' {
            Assert-DxConfirmed -Simulate $simulate -Body $Body
            $server = "$(Get-DxBodyValue -Body $Body -Name 'server' -Default '')".Trim()
            $days = [int](Get-DxBodyValue -Body $Body -Name 'days' -Default 14)
            $params = @{ OlderThanDays = $days }
            if ($server) { $params['ComputerName'] = $server }

            if ($simulate) {
                $files = @(Get-DxLogCleanupCandidate @params)
                return [ordered]@{
                    simulated = $true
                    files     = $files.Count
                    sizeMb    = [math]::Round(([double]($files | Measure-Object -Property Length -Sum).Sum) / 1MB, 1)
                    folders   = @($files | Group-Object -Property DirectoryName | Sort-Object Name | ForEach-Object {
                        [ordered]@{ Map = $_.Name; Bestanden = $_.Count; MB = [math]::Round(([double]($_.Group | Measure-Object -Property Length -Sum).Sum) / 1MB, 1) }
                    })
                }
            }
            $summary = Clear-DxExchangeLog @params -Confirm:$false
            return [ordered]@{ simulated = $false; summary = if ($summary) { ConvertTo-DxJsonSafe $summary } else { $null } }
        }

        'POST /api/clean/requests' {
            Assert-DxConfirmed -Simulate $simulate -Body $Body
            $params = @{ IncludeFailed = [bool](Get-DxBodyValue -Body $Body -Name 'includeFailed' -Default $false); WhatIf = $simulate; Confirm = $false }
            $types = @(Get-DxStringList (Get-DxBodyValue -Body $Body -Name 'types'))
            if ($types.Count -gt 0) { $params['Type'] = $types }
            return ,@(Remove-DxStaleRequest @params | ConvertTo-DxJsonSafe)
        }

        'POST /api/clean/disconnected' {
            Assert-DxConfirmed -Simulate $simulate -Body $Body
            $days = [int](Get-DxBodyValue -Body $Body -Name 'days' -Default 0)
            return ,@(Remove-DxDisconnectedMailbox -OlderThanDays $days -WhatIf:$simulate -Confirm:$false | ConvertTo-DxJsonSafe)
        }

        'POST /api/clean/certificates' {
            Assert-DxConfirmed -Simulate $simulate -Body $Body
            $params = @{ IncludeAssigned = [bool](Get-DxBodyValue -Body $Body -Name 'includeAssigned' -Default $false); WhatIf = $simulate; Confirm = $false }
            $server = "$(Get-DxBodyValue -Body $Body -Name 'server' -Default '')".Trim()
            if ($server) { $params['Server'] = $server }
            return ,@(Remove-DxExpiredCertificate @params | ConvertTo-DxJsonSafe)
        }

        'GET /api/hybrid' {
            $r = Get-DxHybridReport
            return [ordered]@{
                present    = $r.Aanwezig
                blockers   = @($r.Controles | Where-Object Status -eq 'Blokkerend').Count
                warnings   = @($r.Controles | Where-Object Status -eq 'Waarschuwing').Count
                components = @($r.Onderdelen | ConvertTo-DxJsonSafe)
                checks     = @($r.Controles | ConvertTo-DxJsonSafe)
                manual     = @($r.Handmatig | ConvertTo-DxJsonSafe)
            }
        }

        'POST /api/clean/hybrid' {
            Assert-DxConfirmed -Simulate $simulate -Body $Body
            # Niet splitsen op komma's: namen van onderdelen kunnen die bevatten.
            $ids = @(@(Get-DxBodyValue -Body $Body -Name 'ids' -Default @()) | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
            if ($ids.Count -eq 0) { throw (New-Object System.ArgumentException 'Kies minimaal een onderdeel.') }
            $params = @{
                Id         = $ids
                BackupPath = (Join-Path -Path $State['OutputPath'] -ChildPath 'Backup')
                Force      = [bool](Get-DxBodyValue -Body $Body -Name 'force' -Default $false)
                WhatIf     = $simulate
                Confirm    = $false
            }
            return ,@(Remove-DxHybridConfiguration @params | ConvertTo-DxJsonSafe)
        }

        'GET /api/services' {
            $server = "$($Query['server'])".Trim()
            if (-not $server) { throw (New-Object System.ArgumentException 'Kies een server.') }
            return ,@(Get-DxExchangeService -ComputerName $server -IncludeIis:([bool]$Query['iis']) -StatePath (Join-Path -Path $State['OutputPath'] -ChildPath 'Diensten') | ConvertTo-DxJsonSafe)
        }

        'POST /api/services/stop' {
            Assert-DxConfirmed -Simulate $simulate -Body $Body
            $server = "$(Get-DxBodyValue -Body $Body -Name 'server' -Default '')".Trim()
            if (-not $server) { throw (New-Object System.ArgumentException 'Kies een server.') }
            $params = @{
                ComputerName = $server
                IncludeIis   = [bool](Get-DxBodyValue -Body $Body -Name 'includeIis' -Default $false)
                StatePath    = (Join-Path -Path $State['OutputPath'] -ChildPath 'Diensten')
                WhatIf       = $simulate
                Confirm      = $false
            }
            return ,@(Stop-DxExchangeService @params | ConvertTo-DxJsonSafe)
        }

        'POST /api/services/restore' {
            Assert-DxConfirmed -Simulate $simulate -Body $Body
            $server = "$(Get-DxBodyValue -Body $Body -Name 'server' -Default '')".Trim()
            if (-not $server) { throw (New-Object System.ArgumentException 'Kies een server.') }
            $params = @{
                ComputerName = $server
                IncludeIis   = [bool](Get-DxBodyValue -Body $Body -Name 'includeIis' -Default $false)
                StatePath    = (Join-Path -Path $State['OutputPath'] -ChildPath 'Diensten')
                WhatIf       = $simulate
                Confirm      = $false
            }
            return ,@(Restore-DxExchangeService @params | ConvertTo-DxJsonSafe)
        }

        'GET /api/log' {
            # Nieuwste eerst, maximaal 300 regels.
            $lines = $script:DxLogBuffer.ToArray()
            $newest = for ($i = $lines.Count - 1; $i -ge [math]::Max(0, $lines.Count - 300); $i--) { $lines[$i] }
            return ,@($newest | ConvertTo-DxJsonSafe)
        }

        default {
            throw (New-Object System.Collections.Generic.KeyNotFoundException "Onbekende API-route: $route")
        }
    }
}
