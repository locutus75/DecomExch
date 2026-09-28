# Tests voor het opruimen van de hybride koppeling. Compatibel met Pester 4.10+ en 5.

Describe 'DecomExch hybride koppeling' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'ExchangeStubs.ps1')
        Import-Module (Join-Path $PSScriptRoot '..\src\DecomExch\DecomExch.psd1') -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Variable -Name DxHybridCalls -Scope Global -ErrorAction SilentlyContinue
        Remove-Module DecomExch -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $global:DxHybridCalls = New-Object System.Collections.Generic.List[string]

        # Een typische omgeving na de Hybrid Configuration Wizard.
        Mock -ModuleName DecomExch Get-ExchangeServer { [pscustomobject]@{ Name = 'EX01'; ServerRole = 'Mailbox' } }
        Mock -ModuleName DecomExch Get-OrganizationRelationship {
            [pscustomobject]@{ Name = 'On-premises to O365 - 1111'; DomainNames = @('contoso.mail.onmicrosoft.com'); TargetApplicationUri = 'outlook.com'; FreeBusyAccessLevel = 'LimitedDetails' }
        }
        Mock -ModuleName DecomExch Get-IntraOrganizationConnector {
            [pscustomobject]@{ Name = 'HybridIOC - 1111'; TargetAddressDomains = @('contoso.mail.onmicrosoft.com'); DiscoveryEndpoint = 'https://outlook.office365.com/autodiscover/autodiscover.svc'; Enabled = $true }
        }
        Mock -ModuleName DecomExch Get-SendConnector {
            [pscustomobject]@{ Name = 'Outbound to Office 365 - 1111'; AddressSpaces = @('smtp:contoso.mail.onmicrosoft.com;1'); SmartHosts = @('contoso-nl.mail.protection.outlook.com') }
            [pscustomobject]@{ Name = 'Internet'; AddressSpaces = @('smtp:*;1'); SmartHosts = @() }
        }
        Mock -ModuleName DecomExch Get-RemoteDomain {
            [pscustomobject]@{ Name = 'Default'; DomainName = '*' }
            [pscustomobject]@{ Name = 'Hybrid Domain - contoso.mail.onmicrosoft.com'; DomainName = 'contoso.mail.onmicrosoft.com' }
        }
        Mock -ModuleName DecomExch Get-ReceiveConnector {
            [pscustomobject]@{ Name = 'Default Frontend EX01'; Identity = 'EX01\Default Frontend EX01'; TlsDomainCapabilities = @('mail.protection.outlook.com:AcceptCloudServicesMail'); TlsCertificateName = '<I>CN=R3<S>CN=mail.contoso.nl' }
            [pscustomobject]@{ Name = 'Client Frontend EX01'; Identity = 'EX01\Client Frontend EX01'; TlsDomainCapabilities = @(); TlsCertificateName = $null }
        }
        Mock -ModuleName DecomExch Get-FederatedOrganizationIdentifier { [pscustomobject]@{ Enabled = $true; AccountNamespace = 'FYDIBOHF25SPDLT.contoso.nl'; Domains = @('contoso.nl') } }
        Mock -ModuleName DecomExch Get-FederationTrust { [pscustomobject]@{ Name = 'Microsoft Federation Gateway'; OrgPrivCertificate = 'ABC' } }
        Mock -ModuleName DecomExch Get-AuthServer {
            [pscustomobject]@{ Name = 'ACS - 1111'; AuthMetadataUrl = 'https://accounts.accesscontrol.windows.net/x/metadata/json/1'; Enabled = $true }
            [pscustomobject]@{ Name = 'EvoSts - 1111'; AuthMetadataUrl = 'https://login.windows.net/contoso.onmicrosoft.com/federationmetadata/2007-06/federationmetadata.xml'; Enabled = $true }
            [pscustomobject]@{ Name = 'ADFS'; AuthMetadataUrl = 'https://adfs.contoso.nl/metadata'; Enabled = $true }
        }
        Mock -ModuleName DecomExch Get-PartnerApplication {
            [pscustomobject]@{ Name = 'Exchange Online'; ApplicationIdentifier = '00000002-0000-0ff1-ce00-000000000000'; Enabled = $true }
            [pscustomobject]@{ Name = 'Skype'; ApplicationIdentifier = '00000004-0000-0ff1-ce00-000000000000'; Enabled = $true }
        }
        Mock -ModuleName DecomExch Get-ClientAccessService { [pscustomobject]@{ Name = 'EX01'; AutoDiscoverServiceInternalUri = 'https://autodiscover.contoso.nl/Autodiscover/Autodiscover.xml' } }
        Mock -ModuleName DecomExch Get-AcceptedDomain {
            [pscustomobject]@{ Name = 'contoso.nl'; DomainName = 'contoso.nl'; DomainType = 'Authoritative' }
            [pscustomobject]@{ Name = 'contoso.mail.onmicrosoft.com'; DomainName = 'contoso.mail.onmicrosoft.com'; DomainType = 'Authoritative' }
        }
        Mock -ModuleName DecomExch Get-HybridConfiguration { [pscustomobject]@{ Domains = @('contoso.nl'); Features = @('FreeBusy', 'Mailtips'); SendingTransportServers = @('EX01'); ReceivingTransportServers = @('EX01') } }
        Mock -ModuleName DecomExch Get-Mailbox { [pscustomobject]@{ PrimarySmtpAddress = 'DiscoverySearchMailbox@contoso.nl'; RecipientTypeDetails = 'DiscoveryMailbox' } }
        Mock -ModuleName DecomExch Get-MoveRequest { [pscustomobject]@{ Status = 'Completed' } }
        Mock -ModuleName DecomExch Get-RemoteMailbox { [pscustomobject]@{ Name = 'Jan' }; [pscustomobject]@{ Name = 'Piet' } }
        Mock -ModuleName DecomExch Resolve-DnsName {
            if ($Type -eq 'MX') { [pscustomobject]@{ NameExchange = 'contoso-nl.mail.protection.outlook.com' } }
            else { [pscustomobject]@{ NameHost = 'autodiscover.outlook.com' } }
        }

        foreach ($cmd in 'Remove-OrganizationRelationship', 'Remove-IntraOrganizationConnector', 'Remove-SendConnector', 'Remove-RemoteDomain',
            'Set-ReceiveConnector', 'Set-FederatedOrganizationIdentifier', 'Remove-FederationTrust', 'Set-AuthServer', 'Set-PartnerApplication',
            'Set-ClientAccessService', 'Remove-HybridConfiguration') {
            $body = if ($cmd -eq 'Remove-HybridConfiguration') { "`$global:DxHybridCalls.Add('$cmd')" } else { "`$global:DxHybridCalls.Add('$cmd ' + `$Identity)" }
            Mock -ModuleName DecomExch $cmd ([scriptblock]::Create($body))
        }
    }

    Context 'Get-DxHybridReport' {
        It 'vindt de onderdelen van de HCW met de juiste actie' {
            $r = Get-DxHybridReport
            $r.Aanwezig | Should -BeTrue
            $c = @($r.Onderdelen)

            ($c | Where-Object Type -eq 'SendConnector').Naam | Should -Be 'Outbound to Office 365 - 1111'
            @($c | Where-Object Naam -eq 'Internet').Count | Should -Be 0
            ($c | Where-Object Type -eq 'RemoteDomain').Naam | Should -Be 'Hybrid Domain - contoso.mail.onmicrosoft.com'
            ($c | Where-Object Type -eq 'ReceiveConnectorTls').Naam | Should -Be 'EX01\Default Frontend EX01'
            @($c | Where-Object Type -eq 'AuthServer').Count | Should -Be 2
            @($c | Where-Object Type -eq 'PartnerApplication').Count | Should -Be 1
            ($c | Where-Object Type -eq 'PartnerApplication').Actie | Should -Be 'Uitschakelen'
            ($c | Where-Object Type -eq 'AcceptedDomain').Actie | Should -Be 'Behouden'
            ($c | Where-Object Type -eq 'AcceptedDomain').Standaard | Should -BeFalse
            ($c | Where-Object Type -eq 'AutodiscoverScp').Standaard | Should -BeFalse
            ($c | Where-Object Type -eq 'FederationTrust').Standaard | Should -BeTrue
            ($c | Where-Object Type -eq 'HybridConfiguration').Actie | Should -Be 'Verwijderen'

            # Volgorde: eerst OAuth-connector, als laatste het HCW-object.
            $c[0].Type | Should -Be 'IntraOrganizationConnector'
        }

        It 'heeft geen blokkerende punten als alles in Exchange Online staat' {
            $r = Get-DxHybridReport
            @($r.Controles | Where-Object Status -eq 'Blokkerend').Count | Should -Be 0
            ($r.Controles | Where-Object Check -eq 'MX contoso.nl').Status | Should -Be 'OK'
            ($r.Controles | Where-Object Check -eq 'Remote mailboxen').Details | Should -Match '^2 remote'
            @($r.Handmatig).Count | Should -BeGreaterThan 5
            ($r.Handmatig | Where-Object Stap -eq 1).Opdracht | Should -Match 'contoso\.mail\.protection\.outlook\.com'
            $steps = @($r.Handmatig)
            @($steps | ForEach-Object { $_.Stap }) -join ',' | Should -Be ((1..$steps.Count) -join ',')
            $install = [array]::IndexOf(@($steps | ForEach-Object { $_.Wat }), 'Module installeren (eenmalig)')
            $connect = @($steps | Where-Object { $_.Opdracht -like 'Connect-ExchangeOnline*' })[0]
            $install | Should -BeGreaterThan 0
            $connect.Stap | Should -BeGreaterThan ($install + 1)
            $connect.Opdracht | Should -Match '-DisableWAM'
            ($steps | Where-Object Wat -eq 'Nieuw PowerShell-venster openen').Opdracht | Should -Match 'Exchange Management Shell'
        }

        It 'blokkeert bij mailboxen on-premises en waarschuwt voor de MX' {
            Mock -ModuleName DecomExch Get-Mailbox { [pscustomobject]@{ PrimarySmtpAddress = 'jan@contoso.nl'; RecipientTypeDetails = 'UserMailbox' } }
            Mock -ModuleName DecomExch Resolve-DnsName {
                if ($Type -eq 'MX') { [pscustomobject]@{ NameExchange = 'mail.contoso.nl' } }
                else { [pscustomobject]@{ NameHost = 'mail.contoso.nl' } }
            }
            $r = Get-DxHybridReport
            ($r.Controles | Where-Object Check -eq 'Mailboxen on-premises').Status | Should -Be 'Blokkerend'
            ($r.Controles | Where-Object Check -eq 'MX contoso.nl').Status | Should -Be 'Waarschuwing'
            ($r.Controles | Where-Object Check -eq 'Autodiscover contoso.nl').Status | Should -Be 'Waarschuwing'
        }

        It 'laat federatie standaard staan als een andere organisatie die nog gebruikt' {
            Mock -ModuleName DecomExch Get-OrganizationRelationship {
                [pscustomobject]@{ Name = 'On-premises to O365 - 1111'; DomainNames = @('contoso.mail.onmicrosoft.com'); TargetApplicationUri = 'outlook.com'; FreeBusyAccessLevel = 'LimitedDetails' }
                [pscustomobject]@{ Name = 'Fabrikam'; DomainNames = @('fabrikam.com'); TargetApplicationUri = 'mail.fabrikam.com'; FreeBusyAccessLevel = 'AvailabilityOnly' }
            }
            $c = @((Get-DxHybridReport).Onderdelen)
            ($c | Where-Object Naam -eq 'Fabrikam').Actie | Should -Be 'Behouden'
            ($c | Where-Object Type -eq 'FederationTrust').Standaard | Should -BeFalse
            ($c | Where-Object Type -eq 'FederatedOrganizationIdentifier').Standaard | Should -BeFalse
        }

        It 'markeert een send connector voor alle mail als optioneel' {
            Mock -ModuleName DecomExch Get-SendConnector {
                [pscustomobject]@{ Name = 'Via EXO'; AddressSpaces = @('smtp:*;1'); SmartHosts = @('contoso-nl.mail.protection.outlook.com') }
            }
            $r = Get-DxHybridReport
            ($r.Onderdelen | Where-Object Type -eq 'SendConnector').Standaard | Should -BeFalse
            ($r.Controles | Where-Object Check -eq 'Uitgaande mail via Exchange Online').Status | Should -Be 'Waarschuwing'
        }

        It 'meldt geen koppeling in een omgeving zonder hybride' {
            foreach ($cmd in 'Get-OrganizationRelationship', 'Get-IntraOrganizationConnector', 'Get-RemoteDomain', 'Get-FederationTrust', 'Get-AuthServer',
                'Get-PartnerApplication', 'Get-HybridConfiguration', 'Get-ReceiveConnector', 'Get-ClientAccessService') {
                Mock -ModuleName DecomExch $cmd { }
            }
            Mock -ModuleName DecomExch Get-FederatedOrganizationIdentifier { [pscustomobject]@{ Enabled = $false; AccountNamespace = $null; Domains = @() } }
            Mock -ModuleName DecomExch Get-SendConnector { [pscustomobject]@{ Name = 'Internet'; AddressSpaces = @('smtp:*;1'); SmartHosts = @() } }
            Mock -ModuleName DecomExch Get-AcceptedDomain { [pscustomobject]@{ Name = 'contoso.nl'; DomainName = 'contoso.nl'; DomainType = 'Authoritative' } }
            $r = Get-DxHybridReport
            $r.Aanwezig | Should -BeFalse
            @($r.Onderdelen).Count | Should -Be 0
        }
    }

    Context 'Remove-DxHybridConfiguration' {
        It 'wijzigt niets met -WhatIf' {
            $result = @(Remove-DxHybridConfiguration -WhatIf -BackupPath (Join-Path $TestDrive 'bk1'))
            $result.Count | Should -BeGreaterThan 5
            @($result | Where-Object Uitgevoerd).Count | Should -Be 0
            $global:DxHybridCalls.Count | Should -Be 0
            Test-Path (Join-Path $TestDrive 'bk1') | Should -BeFalse
        }

        It 'ruimt de standaardselectie op in de juiste volgorde, met back-up' {
            $bk = Join-Path $TestDrive 'bk2'
            $result = @(Remove-DxHybridConfiguration -Confirm:$false -BackupPath $bk)
            @($result | Where-Object { -not $_.Uitgevoerd }).Count | Should -Be 0

            $calls = @($global:DxHybridCalls)
            $calls[0] | Should -Be 'Remove-IntraOrganizationConnector HybridIOC - 1111'
            $calls[-1] | Should -Match '^Remove-HybridConfiguration'
            $calls | Should -Contain 'Remove-SendConnector Outbound to Office 365 - 1111'
            $calls | Should -Contain 'Remove-RemoteDomain Hybrid Domain - contoso.mail.onmicrosoft.com'
            $calls | Should -Contain 'Set-ReceiveConnector EX01\Default Frontend EX01'
            $calls | Should -Contain 'Remove-FederationTrust Microsoft Federation Gateway'
            $calls | Should -Contain 'Set-AuthServer ACS - 1111'
            $calls | Should -Contain 'Set-PartnerApplication Exchange Online'
            # Optioneel en dus niet standaard: SCP; nooit: ADFS, Skype, Internet-connector.
            @($calls | Where-Object { $_ -like 'Set-ClientAccessService*' -or $_ -like '*ADFS' -or $_ -like '*Skype' -or $_ -like '*Internet' }).Count | Should -Be 0
            Assert-MockCalled -ModuleName DecomExch Set-AuthServer -Times 2 -Exactly -ParameterFilter { $Enabled -eq $false }

            @(Get-ChildItem -Path $bk -Filter 'HybrideBackup_*.xml').Count | Should -Be 1
            @(Get-ChildItem -Path $bk -Filter 'HybrideBackup_*.txt').Count | Should -Be 1
        }

        It 'ruimt alleen de gekozen onderdelen op en weigert onbekende' {
            $result = @(Remove-DxHybridConfiguration -Id 'AutodiscoverScp|EX01' -Confirm:$false -BackupPath (Join-Path $TestDrive 'bk3'))
            $result.Count | Should -Be 1
            @($global:DxHybridCalls) | Should -Be @('Set-ClientAccessService EX01')

            $global:DxThrown = $null
            try { Remove-DxHybridConfiguration -Id 'SendConnector|Bestaat niet' -Confirm:$false -BackupPath (Join-Path $TestDrive 'bk3') } catch { $global:DxThrown = $_.Exception.Message }
            $global:DxThrown | Should -Match 'Onbekend onderdeel'
            Remove-Variable -Name DxThrown -Scope Global
        }

        It 'stopt bij blokkerende punten, tenzij -Force' {
            Mock -ModuleName DecomExch Get-Mailbox { [pscustomobject]@{ PrimarySmtpAddress = 'jan@contoso.nl'; RecipientTypeDetails = 'UserMailbox' } }
            $global:DxThrown = $null
            try { Remove-DxHybridConfiguration -Confirm:$false -BackupPath (Join-Path $TestDrive 'bk4') } catch { $global:DxThrown = $_.Exception.Message }
            $global:DxThrown | Should -Match 'Mailboxen on-premises'
            Remove-Variable -Name DxThrown -Scope Global
            $global:DxHybridCalls.Count | Should -Be 0

            $result = @(Remove-DxHybridConfiguration -Confirm:$false -Force -BackupPath (Join-Path $TestDrive 'bk4'))
            @($result | Where-Object Uitgevoerd).Count | Should -BeGreaterThan 5
        }

        It 'gaat door na een fout en meldt die per onderdeel' {
            Mock -ModuleName DecomExch Remove-SendConnector { throw 'Toegang geweigerd' }
            $result = @(Remove-DxHybridConfiguration -Confirm:$false -BackupPath (Join-Path $TestDrive 'bk5'))
            $failed = @($result | Where-Object { -not $_.Uitgevoerd })
            $failed.Count | Should -Be 1
            $failed[0].Opmerking | Should -Match 'Toegang geweigerd'
            $global:DxHybridCalls | Should -Contain 'Remove-HybridConfiguration'
        }
    }

    Context 'API' {
        It 'geeft het overzicht als JSON-geschikt object' {
            InModuleScope DecomExch {
                $r = Invoke-DxApiRoute -Method GET -Path '/api/hybrid' -State @{ OutputPath = $TestDrive }
                $r.present | Should -BeTrue
                $r.blockers | Should -Be 0
                @($r.components).Count | Should -BeGreaterThan 5
                @($r.components)[0].Id | Should -Be 'IntraOrganizationConnector|HybridIOC - 1111'
                { ConvertTo-Json -InputObject $r -Depth 5 } | Should -Not -Throw
            }
        }

        It 'simuleert standaard en vraagt bevestiging voor een echte uitvoering' {
            InModuleScope DecomExch {
                $state = @{ OutputPath = $TestDrive }
                $sim = Invoke-DxApiRoute -Method POST -Path '/api/clean/hybrid' -Body ([pscustomobject]@{ ids = @('RemoteDomain|Hybrid Domain - contoso.mail.onmicrosoft.com') }) -State $state
                $sim.Count | Should -Be 1
                $sim[0].Uitgevoerd | Should -BeFalse
                $global:DxHybridCalls.Count | Should -Be 0

                $body = [pscustomobject]@{ ids = @('RemoteDomain|Hybrid Domain - contoso.mail.onmicrosoft.com'); simulate = $false }
                { Invoke-DxApiRoute -Method POST -Path '/api/clean/hybrid' -Body $body -State $state } | Should -Throw -ExceptionType ([System.ArgumentException])

                $body = [pscustomobject]@{ ids = @('RemoteDomain|Hybrid Domain - contoso.mail.onmicrosoft.com'); simulate = $false; confirm = 'JA' }
                $live = Invoke-DxApiRoute -Method POST -Path '/api/clean/hybrid' -Body $body -State $state
                $live[0].Uitgevoerd | Should -BeTrue
                @($global:DxHybridCalls) | Should -Be @('Remove-RemoteDomain Hybrid Domain - contoso.mail.onmicrosoft.com')
                Test-Path (Join-Path $TestDrive 'Backup') | Should -BeTrue
            }
        }

        It 'weigert een verzoek zonder onderdelen' {
            InModuleScope DecomExch {
                { Invoke-DxApiRoute -Method POST -Path '/api/clean/hybrid' -Body ([pscustomobject]@{ ids = @() }) -State @{ OutputPath = $TestDrive } } | Should -Throw -ExceptionType ([System.ArgumentException])
            }
        }
    }
}
