# Tests voor de analyse van relaygebruik. Compatibel met Pester 4.10+ en 5.

Describe 'DecomExch relaygebruik' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'ExchangeStubs.ps1')
        Import-Module (Join-Path $PSScriptRoot '..\src\DecomExch\DecomExch.psd1') -Force -DisableNameChecking
        $global:DxFixtureLogs = Join-Path $PSScriptRoot 'Fixtures\SmtpReceive'
    }

    AfterAll {
        Remove-Variable -Name DxFixtureLogs -Scope Global -ErrorAction SilentlyContinue
        Remove-Module DecomExch -Force -ErrorAction SilentlyContinue
    }

    Context 'Hulpfuncties' {
        It 'splitst CSV-regels met aanhalingstekens' {
            InModuleScope DecomExch {
                $f = ConvertFrom-DxCsvLine -Line 'a,"b, met ""komma""",c'
                $f.Count | Should -Be 3
                $f[1] | Should -Be 'b, met "komma"'
            }
        }

        It 'splitst eindpunten in adres en poort' {
            InModuleScope DecomExch {
                (Split-DxEndpoint -Endpoint '10.0.0.5:25').Port | Should -Be '25'
                (Split-DxEndpoint -Endpoint '[fe80::1]:587').Address | Should -Be 'fe80::1'
                (Split-DxEndpoint -Endpoint 'fe80::1:2525').Address | Should -Be 'fe80::1'
            }
        }

        It 'haalt e-mailadressen uit SMTP-opdrachten' {
            InModuleScope DecomExch {
                Get-DxEmailAddress -Command 'MAIL FROM:<Scanner@Contoso.nl> SIZE=123' | Should -Be 'scanner@contoso.nl'
                Get-DxEmailAddress -Command 'MAIL FROM:<>' | Should -Be '<>'
                Get-DxEmailAddress -Command 'RCPT TO:jan@contoso.nl' | Should -Be 'jan@contoso.nl'
            }
        }

        It 'herkent prive-adressen en eigen domeinen' {
            InModuleScope DecomExch {
                Test-DxPrivateAddress -Address '10.1.2.3' | Should -BeTrue
                Test-DxPrivateAddress -Address '172.20.0.1' | Should -BeTrue
                Test-DxPrivateAddress -Address '172.32.0.1' | Should -BeFalse
                Test-DxPrivateAddress -Address '203.0.113.9' | Should -BeFalse
                Test-DxPrivateAddress -Address 'fd00::1' | Should -BeTrue

                Test-DxInternalRecipient -Address 'a@sub.contoso.com' -Domain '*.contoso.com' | Should -BeTrue
                Test-DxInternalRecipient -Address 'a@contoso.com' -Domain '*.contoso.com' | Should -BeTrue
                Test-DxInternalRecipient -Address 'a@gmail.com' -Domain 'contoso.nl' | Should -BeFalse
                Test-DxInternalRecipient -Address 'a@gmail.com' -Domain @() | Should -BeNullOrEmpty
            }
        }

        It 'deelt clients in' {
            InModuleScope DecomExch {
                Get-DxRelayClientType -Address '10.0.0.6' -ExchangeAddress '10.0.0.6' | Should -Be 'Exchange-server'
                Get-DxRelayClientType -Address '40.107.1.2' -HostName 'EUR01-XYZ.outbound.protection.outlook.com' | Should -Be 'Exchange Online'
                Get-DxRelayClientType -Address '10.0.5.20' -HostName 'scanner01' | Should -Be 'Intern (applicatie/apparaat)'
                Get-DxRelayClientType -Address '203.0.113.9' | Should -Be 'Extern (internet)'
            }
        }
    }

    Context 'Read-DxSmtpReceiveLog' {
        It 'leest sessies met EHLO, aanmelding, TLS, afzenders, ontvangers en berichten' {
            InModuleScope DecomExch {
                $files = @(Get-ChildItem -Path $global:DxFixtureLogs -Filter 'RECV2026092010-1.log')
                $sessions = @(Read-DxSmtpReceiveLog -File $files -ServerLabel 'EX01')
                $sessions.Count | Should -Be 6

                $scanner = $sessions | Where-Object Session -eq '08DCAAAA00000001'
                $scanner.Ehlo | Should -Be 'scanner01'
                $scanner.Messages | Should -Be 2
                $scanner.Tls | Should -BeFalse
                $scanner.AuthUser | Should -Be ''
                @($scanner.Recipients) -join ',' | Should -Be 'jan@contoso.nl,leverancier@extern.com,piet@sub.contoso.com'
                $scanner.Connector | Should -Be 'EX01\Relay scanners'

                $app = $sessions | Where-Object Session -eq '08DCAAAA00000002'
                $app.AuthUser | Should -Be 'CONTOSO\svc_app'
                $app.AuthMethod | Should -Be 'LOGIN'
                $app.Tls | Should -BeTrue
                $app.Local | Should -Be '10.0.0.5:587'
            }
        }

        It 'filtert op periode' {
            InModuleScope DecomExch {
                $files = @(Get-ChildItem -Path $global:DxFixtureLogs -Filter '*.log')
                @(Read-DxSmtpReceiveLog -File $files).Count | Should -Be 7
                @(Read-DxSmtpReceiveLog -File $files -Start ([datetime]'2026-09-10')).Count | Should -Be 6
            }
        }

        It 'leest een logbestand dat Exchange nog open heeft om te schrijven' {
            $global:DxLockedCopy = Join-Path ([System.IO.Path]::GetTempPath()) ("RECV-locked-{0}.log" -f [guid]::NewGuid())
            Copy-Item -LiteralPath (Join-Path $global:DxFixtureLogs 'RECV2026092010-1.log') -Destination $global:DxLockedCopy
            # Zoals de Transport-service: open voor schrijven, anderen mogen lezen en schrijven.
            $writer = New-Object System.IO.FileStream($global:DxLockedCopy, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            try {
                InModuleScope DecomExch {
                    $sessions = @(Read-DxSmtpReceiveLog -File (Get-Item -LiteralPath $global:DxLockedCopy))
                    $sessions.Count | Should -Be 6
                }
            }
            finally {
                $writer.Dispose()
                Remove-Item -LiteralPath $global:DxLockedCopy -Force -ErrorAction SilentlyContinue
                Remove-Variable -Name DxLockedCopy -Scope Global -ErrorAction SilentlyContinue
            }
        }

        It 'slaat een onleesbaar bestand over en leest de rest' {
            InModuleScope DecomExch {
                $missing = New-Object System.IO.FileInfo (Join-Path $global:DxFixtureLogs 'RECV-bestaat-niet.log')
                $good = Get-Item -LiteralPath (Join-Path $global:DxFixtureLogs 'RECV2026092010-1.log')
                $skipped = New-Object System.Collections.Generic.List[string]
                $sessions = @(Read-DxSmtpReceiveLog -File @($missing, $good) -SkippedFile $skipped -WarningAction SilentlyContinue)
                $sessions.Count | Should -Be 6
                @($skipped) -join ',' | Should -Be 'RECV-bestaat-niet.log'
            }
        }
    }

    Context 'Get-DxRelayUsage uit een map met logbestanden' {
        BeforeAll {
            Mock -ModuleName DecomExch Get-DxExchangeServerAddress { '10.0.0.6' }
        }

        It 'vat het gebruik per client samen' {
            $report = Get-DxRelayUsage -Source Path -Path $global:DxFixtureLogs -Days 0 -Domain 'contoso.nl', '*.contoso.com' -Report
            $report.Bron | Should -Be 'Map met logbestanden'
            $report.Bestanden | Should -Be 2

            $clients = @($report.Clients)
            # 10.0.0.6 (Exchange-server) wordt niet meegeteld
            @($clients | ForEach-Object Client) -contains '10.0.0.6' | Should -BeFalse
            $clients.Count | Should -Be 5

            $scanner = $clients | Where-Object Client -eq '10.0.5.20'
            $scanner.Type | Should -Be 'Intern (applicatie/apparaat)'
            $scanner.Berichten | Should -Be 3
            $scanner.Sessies | Should -Be 2
            $scanner.Aanmelding | Should -Be 'Anoniem'
            $scanner.TLS | Should -Be 'Nee'
            $scanner.RelayNaarExtern | Should -BeTrue
            $scanner.ExterneOntvangers | Should -Be 1
            $scanner.Afzenders | Should -Be 'scanner@contoso.nl'
            $scanner.Poorten | Should -Be '25'
            $scanner.Naam | Should -Be 'scanner01'
            $scanner.EersteKeer | Should -BeLessThan $scanner.LaatsteKeer

            $app = $clients | Where-Object Client -eq '10.0.6.30'
            $app.Aanmelding | Should -Be 'Geauthenticeerd'
            $app.Accounts | Should -Be 'CONTOSO\svc_app'
            $app.TLS | Should -Be 'Ja'
            $app.Poorten | Should -Be '587'

            ($clients | Where-Object Client -eq '40.107.1.2').Type | Should -Be 'Exchange Online'
            ($clients | Where-Object Client -eq '203.0.113.9').RelayNaarExtern | Should -BeFalse

            # De grootste gebruiker staat bovenaan
            $clients[0].Client | Should -Be '10.0.5.20'

            ($report.Opmerkingen -join ' ') | Should -Match 'anoniem'
            ($report.Opmerkingen -join ' ') | Should -Match 'interne applicatie'
            ($report.Opmerkingen -join ' ') | Should -Match 'MX-record'
            ($report.Opmerkingen -join ' ') | Should -Match 'Exchange-servers'
            (@($report.PerDag) | Measure-Object -Property Berichten -Sum).Sum | Should -Be 7
        }

        It 'telt Exchange-servers mee met -IncludeExchangeServers' {
            $clients = @(Get-DxRelayUsage -Source Path -Path $global:DxFixtureLogs -Days 0 -Domain 'contoso.nl' -IncludeExchangeServers)
            ($clients | Where-Object Client -eq '10.0.0.6').Type | Should -Be 'Exchange-server'
        }

        It 'accepteert domeinen als tekst met komma''s' {
            $clients = @(Get-DxRelayUsage -Source Path -Path $global:DxFixtureLogs -Days 0 -Domain 'contoso.nl, *.contoso.com')
            ($clients | Where-Object Client -eq '10.0.5.20').ExterneOntvangers | Should -Be 1
            ($clients | Where-Object Client -eq '203.0.113.9').RelayNaarExtern | Should -BeFalse
        }

        It 'herkent Exchange-servers aan poort 2525 of X-ANONYMOUSTLS, ook zonder Exchange-verbinding' {
            Mock -ModuleName DecomExch Get-DxExchangeServerAddress { }
            $report = Get-DxRelayUsage -Source Path -Path $global:DxFixtureLogs -Days 0 -Domain 'contoso.nl' -Report
            @($report.Clients | ForEach-Object Client) -contains '10.0.0.6' | Should -BeFalse
            ($report.Opmerkingen -join ' ') | Should -Not -Match '40\.107\.1\.2'
        }

        It 'meldt dat intern/extern onbekend is zonder eigen domeinen' {
            $report = Get-DxRelayUsage -Source Path -Path $global:DxFixtureLogs -Days 0 -Report
            ($report.Opmerkingen -join ' ') | Should -Match 'geen eigen domeinen'
            (@($report.Clients) | Where-Object Client -eq '10.0.5.20').ExterneOntvangers | Should -BeNullOrEmpty
        }
    }

    Context 'Get-DxRelayUsage uit message tracking' {
        BeforeAll {
            Mock -ModuleName DecomExch Get-DxExchangeServerAddress { '10.0.0.5' }
            Mock -ModuleName DecomExch Get-ExchangeServer { [pscustomobject]@{ Name = 'EX01'; ServerRole = 'Mailbox' } }
            Mock -ModuleName DecomExch Get-AcceptedDomain { [pscustomobject]@{ DomainName = 'contoso.nl' } }
            Mock -ModuleName DecomExch Get-MessageTrackingLog {
                # Via Frontend Transport: ClientIp is de server zelf, OriginalClientIp de echte client.
                [pscustomobject]@{ Timestamp = [datetime]'2026-09-20 10:00'; Source = 'SMTP'; EventId = 'RECEIVE'; ClientIp = '10.0.0.5'; OriginalClientIp = '10.0.5.20'; ClientHostname = 'EX01'; ServerHostname = 'EX01'; ConnectorId = 'EX01\Default EX01'; Sender = 'scanner@contoso.nl'; Recipients = @('klant@gmail.com'); MessageId = '<m1@scanner>' }
                # Hetzelfde bericht nogmaals (tweede hop): telt maar een keer.
                [pscustomobject]@{ Timestamp = [datetime]'2026-09-20 10:00'; Source = 'SMTP'; EventId = 'RECEIVE'; ClientIp = '10.0.0.5'; OriginalClientIp = '10.0.5.20'; ClientHostname = 'EX01'; ServerHostname = 'EX01'; ConnectorId = 'EX01\Default EX01'; Sender = 'scanner@contoso.nl'; Recipients = @('klant@gmail.com'); MessageId = '<m1@scanner>' }
                [pscustomobject]@{ Timestamp = [datetime]'2026-09-21 10:00'; Source = 'SMTP'; EventId = 'RECEIVE'; ClientIp = '10.0.5.20'; OriginalClientIp = ''; ClientHostname = 'scanner01'; ServerHostname = 'EX01'; ConnectorId = 'EX01\Relay scanners'; Sender = 'scanner@contoso.nl'; Recipients = @('jan@contoso.nl'); MessageId = '<m2@scanner>' }
                # Interne mail uit een mailbox: geen SMTP, telt niet mee.
                [pscustomobject]@{ Timestamp = [datetime]'2026-09-21 11:00'; Source = 'STOREDRIVER'; EventId = 'RECEIVE'; ClientIp = ''; OriginalClientIp = ''; ClientHostname = 'EX01'; ServerHostname = 'EX01'; ConnectorId = ''; Sender = 'jan@contoso.nl'; Recipients = @('piet@contoso.nl'); MessageId = '<m3@ex01>' }
            }
        }

        It 'gebruikt OriginalClientIp, telt unieke berichten en negeert niet-SMTP' {
            $report = Get-DxRelayUsage -Source MessageTracking -Days 30 -Report
            $report.Bron | Should -Be 'Message tracking'
            $clients = @($report.Clients)
            $clients.Count | Should -Be 1
            $clients[0].Client | Should -Be '10.0.5.20'
            $clients[0].Berichten | Should -Be 2
            $clients[0].Aanmelding | Should -Be 'Onbekend'
            $clients[0].RelayNaarExtern | Should -BeTrue
            $clients[0].Sessies | Should -BeNullOrEmpty
        }

        It 'valt terug op message tracking als er geen protocollogs zijn' {
            Mock -ModuleName DecomExch Get-DxSmtpReceiveLogFolder { 'C:\bestaat\niet' }
            $report = Get-DxRelayUsage -Source Auto -Days 30 -Report
            $report.Bron | Should -Be 'Message tracking'
            ($report.Opmerkingen -join ' ') | Should -Match 'message tracking is gebruikt'
        }
    }

    Context 'Get-DxReceiveConnectorReport' {
        It 'adviseert protocol logging en wijst op anonieme eigen connectors' {
            Mock -ModuleName DecomExch Get-ReceiveConnector {
                [pscustomobject]@{ Name = 'Default Frontend EX01'; Identity = 'EX01\Default Frontend EX01'; TransportRole = 'FrontendTransport'; Bindings = @('0.0.0.0:25'); RemoteIPRanges = @('0.0.0.0-255.255.255.255'); PermissionGroups = 'AnonymousUsers, ExchangeServers'; AuthMechanism = 'Tls'; ProtocolLoggingLevel = 'Verbose' }
                [pscustomobject]@{ Name = 'Relay scanners'; Identity = 'EX01\Relay scanners'; TransportRole = 'FrontendTransport'; Bindings = @('0.0.0.0:25'); RemoteIPRanges = @('10.0.5.20', '10.0.5.21'); PermissionGroups = 'AnonymousUsers'; AuthMechanism = 'None'; ProtocolLoggingLevel = 'None' }
            }
            $rows = @(Get-DxReceiveConnectorReport -Server 'EX01')
            $rows.Count | Should -Be 2
            ($rows | Where-Object Connector -eq 'Default Frontend EX01').Advies | Should -Be ''
            $relay = $rows | Where-Object Connector -eq 'Relay scanners'
            $relay.Eigen | Should -BeTrue
            $relay.Advies | Should -Match "Set-ReceiveConnector -Identity 'EX01\\Relay scanners' -ProtocolLoggingLevel Verbose"
            $relay.Advies | Should -Match 'anonieme'
            $relay.ExterneIPs | Should -Be '10.0.5.20, 10.0.5.21'
        }
    }
}
