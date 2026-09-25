function Get-DxInventory {
    <#
    .SYNOPSIS
        Inventariseert de Exchange-organisatie (alleen lezen).
    .DESCRIPTION
        Verzamelt servers, databases, mailboxen (met grootte en laatste aanmelding),
        public folders, aanvragen, connectors,
        domeinen, certificaten en hybride configuratie. Het resultaat is een
        geordende hashtable met per onderdeel een lijst objecten, geschikt voor
        Export-DxReport.
    .EXAMPLE
        Get-DxInventory | Export-DxReport -Path C:\DecomExch\Rapport
    #>
    [CmdletBinding()]
    param(
        [switch]$SkipMailboxDetails,

        [ValidateRange(1, 3650)]
        [int]$InactiveDays = 90
    )

    Assert-DxExchangeShell
    Write-DxLog -Level Action -Message 'Inventarisatie gestart ...'

    $inventory = [ordered]@{}

    $inventory['Organisatie'] = Invoke-DxSafe -Section 'Organisatie' -Action {
        Get-OrganizationConfig | Select-Object Name, AdminDisplayVersion, IsDehydrated, PublicFoldersEnabled
    }

    $inventory['Servers'] = Invoke-DxSafe -Section 'Servers' -Action {
        Get-ExchangeServer | Sort-Object Name |
            Select-Object Name, Fqdn, Edition, AdminDisplayVersion, @{ n = 'ServerRole'; e = { "$($_.ServerRole)" } }, Site
    }

    $inventory['Databases'] = Invoke-DxSafe -Section 'Databases' -Action {
        Get-MailboxDatabase -Status | Sort-Object Name |
            Select-Object Name, Server, Mounted, EdbFilePath, LogFolderPath,
                @{ n = 'DatabaseSize'; e = { "$($_.DatabaseSize)" } },
                @{ n = 'AvailableNewMailboxSpace'; e = { "$($_.AvailableNewMailboxSpace)" } },
                @{ n = 'CircularLoggingEnabled'; e = { $_.CircularLoggingEnabled } }
    }

    $inventory['Mailboxtypes'] = Invoke-DxSafe -Section 'Mailboxtypes' -Action {
        $rows = @()
        $rows += Get-Mailbox -ResultSize Unlimited -ErrorAction Stop |
            Group-Object -Property RecipientTypeDetails |
            ForEach-Object { [pscustomobject]@{ Type = "$($_.Name)"; Aantal = $_.Count } }

        $systemTypes = [ordered]@{
            Arbitration  = 'Arbitration (systeem)'
            AuditLog     = 'AuditLog (systeem)'
            AuxAuditLog  = 'AuxAuditLog (systeem)'
            Monitoring   = 'Monitoring/Health (systeem)'
            PublicFolder = 'PublicFolder'
        }
        foreach ($sw in $systemTypes.Keys) {
            if ((Get-Command -Name Get-Mailbox).Parameters.ContainsKey($sw)) {
                $params = @{ ResultSize = 'Unlimited'; ErrorAction = 'SilentlyContinue'; $sw = $true }
                $rows += [pscustomobject]@{ Type = $systemTypes[$sw]; Aantal = @(Get-Mailbox @params).Count }
            }
        }
        $rows += [pscustomobject]@{ Type = 'RemoteMailbox (Exchange Online)'; Aantal = @(Get-RemoteMailbox -ResultSize Unlimited -ErrorAction SilentlyContinue).Count }
        $rows
    }

    if (-not $SkipMailboxDetails) {
        $inventory['Mailboxen'] = Invoke-DxSafe -Section 'Mailboxen' -Action {
            Get-DxMailboxReport -InactiveDays $InactiveDays | Sort-Object Database, DisplayName
        }
    }

    $inventory['Public folders'] = Invoke-DxSafe -Section 'Public folders' -Action {
        Get-DxPublicFolderReport | Sort-Object Map
    }

    $inventory['Losgekoppelde mailboxen'] = Invoke-DxSafe -Section 'Losgekoppelde mailboxen' -Action {
        Get-MailboxDatabase | ForEach-Object {
            Get-MailboxStatistics -Database $_.Name -ErrorAction SilentlyContinue |
                Where-Object { $_.DisconnectDate } |
                Select-Object DisplayName, Database, DisconnectDate, DisconnectReason, MailboxGuid,
                    @{ n = 'TotalItemSize'; e = { "$($_.TotalItemSize)" } }
        }
    }

    $inventory['Verplaatsaanvragen'] = Invoke-DxSafe -Section 'Verplaatsaanvragen' -Action {
        Get-MoveRequest -ResultSize Unlimited |
            Select-Object DisplayName, Status, SourceDatabase, TargetDatabase, BatchName
    }

    $inventory['Migratiebatches'] = Invoke-DxSafe -Section 'Migratiebatches' -Action {
        Get-MigrationBatch | Select-Object Identity, Status, TotalCount, FailedCount, CreationDateTime
    }

    $inventory['Export/import-aanvragen'] = Invoke-DxSafe -Section 'Export/import-aanvragen' -Action {
        @(Get-MailboxExportRequest | Select-Object Name, Mailbox, Status, @{ n = 'Soort'; e = { 'Export' } }) +
        @(Get-MailboxImportRequest | Select-Object Name, Mailbox, Status, @{ n = 'Soort'; e = { 'Import' } })
    }

    $inventory['Send connectors'] = Invoke-DxSafe -Section 'Send connectors' -Action {
        Get-SendConnector | Select-Object Name, Enabled,
            @{ n = 'AddressSpaces'; e = { $_.AddressSpaces -join '; ' } },
            @{ n = 'SmartHosts'; e = { $_.SmartHosts -join '; ' } },
            @{ n = 'SourceTransportServers'; e = { $_.SourceTransportServers -join '; ' } }
    }

    $inventory['Receive connectors'] = Invoke-DxSafe -Section 'Receive connectors' -Action {
        Get-ReceiveConnector | Select-Object Identity, Enabled, TransportRole,
            @{ n = 'Bindings'; e = { $_.Bindings -join '; ' } },
            @{ n = 'RemoteIPRanges'; e = { $_.RemoteIPRanges -join '; ' } }
    }

    $inventory['Accepted domains'] = Invoke-DxSafe -Section 'Accepted domains' -Action {
        Get-AcceptedDomain | Select-Object Name, DomainName, DomainType, Default
    }

    $inventory['E-mailadresbeleid'] = Invoke-DxSafe -Section 'E-mailadresbeleid' -Action {
        Get-EmailAddressPolicy | Select-Object Name, Priority, RecipientFilter,
            @{ n = 'Templates'; e = { $_.EnabledEmailAddressTemplates -join '; ' } }
    }

    $inventory['Certificaten'] = Invoke-DxSafe -Section 'Certificaten' -Action {
        $now = Get-Date
        Get-ExchangeServer | Where-Object { $_.ServerRole -notmatch 'Edge' } | ForEach-Object {
            $server = $_.Name
            Get-ExchangeCertificate -Server $server -ErrorAction SilentlyContinue |
                Select-Object @{ n = 'Server'; e = { $server } }, Thumbprint, Subject, NotAfter,
                    @{ n = 'Services'; e = { "$($_.Services)" } },
                    @{ n = 'Verlopen'; e = { $_.NotAfter -lt $now } }
        }
    }

    $inventory['Client access'] = Invoke-DxSafe -Section 'Client access' -Action {
        $cmd = if (Test-DxCommand -Name 'Get-ClientAccessService') { 'Get-ClientAccessService' } else { 'Get-ClientAccessServer' }
        & $cmd | Select-Object Name, AutoDiscoverServiceInternalUri, @{ n = 'AutoDiscoverSiteScope'; e = { $_.AutoDiscoverSiteScope -join '; ' } }
    }

    $inventory['Hybride configuratie'] = Invoke-DxSafe -Section 'Hybride configuratie' -Action {
        Get-HybridConfiguration | Select-Object @{ n = 'Domains'; e = { $_.Domains -join '; ' } },
            @{ n = 'Features'; e = { $_.Features -join '; ' } },
            @{ n = 'SendingTransportServers'; e = { $_.SendingTransportServers -join '; ' } },
            @{ n = 'ReceivingTransportServers'; e = { $_.ReceivingTransportServers -join '; ' } }
    }

    Write-DxLog -Level Success -Message 'Inventarisatie afgerond.'
    $inventory
}
