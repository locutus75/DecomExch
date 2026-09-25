# Compatibel met Pester 4.10+ en Pester 5.

Describe 'DecomExch' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'ExchangeStubs.ps1')
        Import-Module (Join-Path $PSScriptRoot '..\src\DecomExch\DecomExch.psd1') -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Module DecomExch -Force -ErrorAction SilentlyContinue
    }

    Context 'Module' {
        It 'exporteert alle publieke functies' {
            $exported = (Get-Module DecomExch).ExportedFunctions.Keys
            foreach ($name in 'Get-DxInventory', 'Test-DxDecomReadiness', 'Clear-DxExchangeLog', 'Remove-DxStaleRequest',
                'Remove-DxDisconnectedMailbox', 'Remove-DxExpiredCertificate', 'Export-DxReport') {
                $exported | Should -Contain $name
            }
        }

        It 'alle verwijderfuncties ondersteunen -WhatIf' {
            foreach ($name in 'Clear-DxExchangeLog', 'Remove-DxStaleRequest', 'Remove-DxDisconnectedMailbox', 'Remove-DxExpiredCertificate') {
                (Get-Command $name).Parameters.ContainsKey('WhatIf') | Should -BeTrue
            }
        }
    }

    Context 'ConvertTo-DxUncPath' {
        It 'zet een lokaal pad om naar een admin-share' {
            InModuleScope DecomExch {
                ConvertTo-DxUncPath -Path 'C:\inetpub\logs\LogFiles' -ComputerName 'EX01' | Should -Be '\\EX01\C$\inetpub\logs\LogFiles'
            }
        }

        It 'laat het pad ongewijzigd zonder computernaam' {
            InModuleScope DecomExch {
                ConvertTo-DxUncPath -Path 'D:\Logs' | Should -Be 'D:\Logs'
            }
        }

        It 'laat een UNC-pad ongewijzigd' {
            InModuleScope DecomExch {
                ConvertTo-DxUncPath -Path '\\EX01\D$\Logs' -ComputerName 'EX01' | Should -Be '\\EX01\D$\Logs'
            }
        }
    }

    Context 'Logbestanden opruimen' {
        BeforeEach {
            $root = Join-Path $TestDrive ('logs_' + [guid]::NewGuid().ToString('N'))
            $sub = Join-Path $root 'Diagnostics'
            New-Item -Path $sub -ItemType Directory -Force | Out-Null

            $old = (Get-Date).AddDays(-60)
            foreach ($name in 'oud.log', 'trace.etl', 'E00.log', 'E0000001A2B.log', 'E00.chk', 'data.edb') {
                $f = New-Item -Path (Join-Path $sub $name) -ItemType File -Value 'x' -Force
                $f.LastWriteTime = $old
            }
            New-Item -Path (Join-Path $sub 'nieuw.log') -ItemType File -Value 'x' -Force | Out-Null
        }

        It 'selecteert alleen oude diagnostische logs en slaat transactielogs over' {
            $names = @(Get-DxLogCleanupCandidate -Path $root -OlderThanDays 14 | ForEach-Object { $_.Name } | Sort-Object)
            $names -join ',' | Should -Be 'oud.log,trace.etl'
        }

        It 'weigert databasemappen' {
            $mailboxDir = Join-Path $TestDrive 'V15\Mailbox'
            New-Item -Path $mailboxDir -ItemType Directory -Force | Out-Null
            $f = New-Item -Path (Join-Path $mailboxDir 'oud.log') -ItemType File -Value 'x' -Force
            $f.LastWriteTime = (Get-Date).AddDays(-60)

            @(Get-DxLogCleanupCandidate -Path $mailboxDir -OlderThanDays 1 -WarningAction SilentlyContinue).Count | Should -Be 0
        }

        It 'verwijdert niets met -WhatIf' {
            Clear-DxExchangeLog -Path $root -OlderThanDays 14 -WhatIf | Out-Null
            Test-Path (Join-Path $root 'Diagnostics\oud.log') | Should -BeTrue
        }

        It 'schrijft het logbestand ook in simulatiemodus' {
            $logFile = Set-DxLogFile -Path (Join-Path $TestDrive 'dxlog')
            Clear-DxExchangeLog -Path $root -OlderThanDays 14 -WhatIf | Out-Null
            Get-Content -Path $logFile -Raw | Should -Match 'Logopruiming'
        }

        It 'verwijdert oude logs en laat de rest staan' {
            $result = Clear-DxExchangeLog -Path $root -OlderThanDays 14 -Confirm:$false
            $result.Verwijderd | Should -Be 2
            Test-Path (Join-Path $root 'Diagnostics\oud.log') | Should -BeFalse
            Test-Path (Join-Path $root 'Diagnostics\trace.etl') | Should -BeFalse
            Test-Path (Join-Path $root 'Diagnostics\nieuw.log') | Should -BeTrue
            Test-Path (Join-Path $root 'Diagnostics\E0000001A2B.log') | Should -BeTrue
            Test-Path (Join-Path $root 'Diagnostics\data.edb') | Should -BeTrue
        }
    }

    Context 'Remove-DxStaleRequest' {
        BeforeAll {
            Mock -ModuleName DecomExch Get-MoveRequest {
                [pscustomobject]@{ Identity = 'm1'; DisplayName = 'Jan';  Status = 'Completed' }
                [pscustomobject]@{ Identity = 'm2'; DisplayName = 'Piet'; Status = 'InProgress' }
                [pscustomobject]@{ Identity = 'm3'; DisplayName = 'Klaas'; Status = 'Failed' }
            }
            Mock -ModuleName DecomExch Remove-MoveRequest { }
        }

        It 'verwijdert niets met -WhatIf' {
            $result = @(Remove-DxStaleRequest -Type MoveRequest -WhatIf)
            $result.Count | Should -Be 1
            Assert-MockCalled -ModuleName DecomExch Remove-MoveRequest -Times 0 -Exactly -Scope It
        }

        It 'verwijdert alleen afgeronde aanvragen' {
            $result = @(Remove-DxStaleRequest -Type MoveRequest -Confirm:$false)
            $result.Count | Should -Be 1
            $result[0].Verwijderd | Should -BeTrue
            Assert-MockCalled -ModuleName DecomExch Remove-MoveRequest -Times 1 -Exactly -Scope It -ParameterFilter { $Identity -eq 'm1' }
        }

        It 'verwijdert met -IncludeFailed ook mislukte, maar nooit lopende aanvragen' {
            Remove-DxStaleRequest -Type MoveRequest -IncludeFailed -Confirm:$false | Out-Null
            Assert-MockCalled -ModuleName DecomExch Remove-MoveRequest -Times 2 -Exactly -Scope It
            Assert-MockCalled -ModuleName DecomExch Remove-MoveRequest -Times 0 -Exactly -Scope It -ParameterFilter { $Identity -eq 'm2' }
        }
    }

    Context 'Remove-DxDisconnectedMailbox' {
        BeforeAll {
            Mock -ModuleName DecomExch Get-MailboxStatistics {
                [pscustomobject]@{ DisplayName = 'Oud';   MailboxGuid = 'g1'; DisconnectDate = (Get-Date).AddDays(-90); DisconnectReason = 'Disabled' }
                [pscustomobject]@{ DisplayName = 'Recent'; MailboxGuid = 'g2'; DisconnectDate = (Get-Date).AddDays(-2);  DisconnectReason = 'SoftDeleted' }
                [pscustomobject]@{ DisplayName = 'Actief'; MailboxGuid = 'g3'; DisconnectDate = $null;                   DisconnectReason = $null }
            }
            Mock -ModuleName DecomExch Remove-StoreMailbox { }
        }

        It 'houdt rekening met de leeftijd en de status' {
            $result = @(Remove-DxDisconnectedMailbox -Database DB01 -OlderThanDays 30 -Confirm:$false)
            $result.Count | Should -Be 1
            $result[0].DisplayName | Should -Be 'Oud'
            Assert-MockCalled -ModuleName DecomExch Remove-StoreMailbox -Times 1 -Exactly -Scope It -ParameterFilter { $Identity -eq 'g1' -and $MailboxState -eq 'Disabled' }
        }

        It 'verwijdert niets met -WhatIf' {
            Remove-DxDisconnectedMailbox -Database DB01 -WhatIf | Out-Null
            Assert-MockCalled -ModuleName DecomExch Remove-StoreMailbox -Times 0 -Exactly -Scope It
        }
    }

    Context 'Remove-DxExpiredCertificate' {
        BeforeAll {
            Mock -ModuleName DecomExch Get-AuthConfig { [pscustomobject]@{ CurrentCertificateThumbprint = 'AUTH'; PreviousCertificateThumbprint = $null; NextCertificateThumbprint = $null } }
            Mock -ModuleName DecomExch Get-ExchangeCertificate {
                [pscustomobject]@{ Thumbprint = 'OLD';   Subject = 'CN=oud';   NotAfter = (Get-Date).AddDays(-10); Services = 'None' }
                [pscustomobject]@{ Thumbprint = 'IIS';   Subject = 'CN=mail';  NotAfter = (Get-Date).AddDays(-10); Services = 'IIS, SMTP' }
                [pscustomobject]@{ Thumbprint = 'auth';  Subject = 'CN=oauth'; NotAfter = (Get-Date).AddDays(-10); Services = 'SMTP' }
                [pscustomobject]@{ Thumbprint = 'VALID'; Subject = 'CN=geldig'; NotAfter = (Get-Date).AddDays(100); Services = 'IIS' }
            }
            Mock -ModuleName DecomExch Remove-ExchangeCertificate { }
        }

        It 'verwijdert alleen verlopen, niet-gekoppelde certificaten en nooit het OAuth-certificaat' {
            $result = @(Remove-DxExpiredCertificate -Server EX01 -Confirm:$false)
            $result.Count | Should -Be 3
            Assert-MockCalled -ModuleName DecomExch Remove-ExchangeCertificate -Times 1 -Exactly -Scope It
            Assert-MockCalled -ModuleName DecomExch Remove-ExchangeCertificate -Times 1 -Exactly -Scope It -ParameterFilter { $Thumbprint -eq 'OLD' }
        }

        It 'verwijdert met -IncludeAssigned ook gekoppelde, maar niet het OAuth-certificaat' {
            Remove-DxExpiredCertificate -Server EX01 -IncludeAssigned -Confirm:$false | Out-Null
            Assert-MockCalled -ModuleName DecomExch Remove-ExchangeCertificate -Times 2 -Exactly -Scope It
            Assert-MockCalled -ModuleName DecomExch Remove-ExchangeCertificate -Times 0 -Exactly -Scope It -ParameterFilter { $Thumbprint -eq 'auth' }
        }
    }

    Context 'Test-DxDecomReadiness' {
        BeforeAll {
            Mock -ModuleName DecomExch Get-ExchangeServer {
                if ($Identity) { [pscustomobject]@{ Name = 'EX01'; AdminDisplayVersion = 'Version 15.2'; ServerRole = 'Mailbox' } }
                else {
                    [pscustomobject]@{ Name = 'EX01'; ServerRole = 'Mailbox' }
                    [pscustomobject]@{ Name = 'EX02'; ServerRole = 'Mailbox' }
                }
            }
            Mock -ModuleName DecomExch Get-DatabaseAvailabilityGroup { }
            Mock -ModuleName DecomExch Get-MailboxDatabase { [pscustomobject]@{ Name = 'DB01' } }
            Mock -ModuleName DecomExch Get-Mailbox { }
            Mock -ModuleName DecomExch Get-MoveRequest { }
            Mock -ModuleName DecomExch Get-SendConnector { }
            Mock -ModuleName DecomExch Get-ReceiveConnector {
                [pscustomobject]@{ Name = 'Default EX01' }
                [pscustomobject]@{ Name = 'Client Frontend EX01' }
            }
            Mock -ModuleName DecomExch Get-EdgeSubscription { }
            Mock -ModuleName DecomExch Get-ClientAccessService { [pscustomobject]@{ AutoDiscoverServiceInternalUri = $null } }
            Mock -ModuleName DecomExch Get-HybridConfiguration { }
        }

        It 'geeft geen blokkerende punten voor een lege server' {
            $checks = @(Test-DxDecomReadiness -Server EX01)
            @($checks | Where-Object Status -eq 'Blokkerend').Count | Should -Be 0
            ($checks | Where-Object Check -eq 'Laatste Exchange-server').Status | Should -Be 'OK'
        }

        It 'blokkeert bij mailboxen en arbitration-mailboxen' {
            Mock -ModuleName DecomExch Get-Mailbox { [pscustomobject]@{ DisplayName = 'Jan' } } -ParameterFilter { -not $Arbitration -and -not $AuditLog -and -not $AuxAuditLog -and -not $Monitoring -and -not $PublicFolder }
            Mock -ModuleName DecomExch Get-Mailbox { [pscustomobject]@{ DisplayName = 'SystemMailbox{1f05a927}' } } -ParameterFilter { $Arbitration }

            $checks = @(Test-DxDecomReadiness -Server EX01)
            ($checks | Where-Object Check -eq 'Gebruikers-/gedeelde mailboxen').Status | Should -Be 'Blokkerend'
            ($checks | Where-Object Check -eq 'Arbitration-mailboxen').Status | Should -Be 'Blokkerend'
            ($checks | Where-Object Check -eq 'AuditLog-mailboxen').Status | Should -Be 'OK'
        }

        It 'blokkeert als de server de enige bron van een send connector is en in een DAG zit' {
            Mock -ModuleName DecomExch Get-SendConnector { [pscustomobject]@{ Name = 'Internet'; SourceTransportServers = @('EX01') } }
            Mock -ModuleName DecomExch Get-DatabaseAvailabilityGroup { [pscustomobject]@{ Name = 'DAG01'; Servers = @('EX01', 'EX02') } }

            $checks = @(Test-DxDecomReadiness -Server EX01)
            ($checks | Where-Object Check -eq "Send connector 'Internet'").Status | Should -Be 'Blokkerend'
            ($checks | Where-Object Check -eq 'DAG-lidmaatschap').Status | Should -Be 'Blokkerend'
        }

        It 'waarschuwt voor eigen receive connectors, lopende moves en de laatste server' {
            Mock -ModuleName DecomExch Get-ExchangeServer { [pscustomobject]@{ Name = 'EX01'; AdminDisplayVersion = 'Version 15.2'; ServerRole = 'Mailbox' } }
            Mock -ModuleName DecomExch Get-ReceiveConnector { [pscustomobject]@{ Name = 'Relay printers' } }
            Mock -ModuleName DecomExch Get-MoveRequest { [pscustomobject]@{ Status = 'InProgress'; SourceDatabase = 'DB01'; TargetDatabase = 'EXO' } }

            $checks = @(Test-DxDecomReadiness -Server EX01)
            ($checks | Where-Object Check -eq 'Eigen receive connectors').Status | Should -Be 'Waarschuwing'
            ($checks | Where-Object Check -eq 'Laatste Exchange-server').Status | Should -Be 'Waarschuwing'
            ($checks | Where-Object Check -eq 'Verplaatsaanvragen').Status | Should -Be 'Blokkerend'
        }
    }

    Context 'Export-DxReport' {
        It 'maakt een HTML-rapport met secties en codeert HTML' {
            $inventory = [ordered]@{
                'Servers' = @([pscustomobject]@{ Name = 'EX01'; Versie = '<15.2>' })
                'Leeg'    = @()
            }
            $out = Join-Path $TestDrive 'rapport'
            $file = $inventory | Export-DxReport -Path $out -Title 'Test rapport'

            Test-Path $file | Should -BeTrue
            $html = Get-Content -Path $file -Raw
            $html | Should -Match 'EX01'
            $html | Should -Match '&lt;15.2&gt;'
            $html | Should -Match 'Geen gegevens'
            # Alleen niet-lege secties krijgen een CSV.
            @(Get-ChildItem -Path $out -Filter '*.csv').Count | Should -Be 1
        }

        It 'kleurt controleresultaten op status' {
            $out = Join-Path $TestDrive 'rapport2'
            $file = @(
                [pscustomobject]@{ Check = 'A'; Status = 'Blokkerend'; Details = ''; Oplossing = '' }
                [pscustomobject]@{ Check = 'B'; Status = 'OK'; Details = ''; Oplossing = '' }
            ) | Export-DxReport -Path $out -Title 'Controle' -NoCsv

            Get-Content -Path $file -Raw | Should -Match '<tr class="Blokkerend">'
        }
    }
}
