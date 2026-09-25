# Tests voor de webinterface-backend. Compatibel met Pester 4.10+ en Pester 5.

Describe 'DecomExch webinterface' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'ExchangeStubs.ps1')
        Import-Module (Join-Path $PSScriptRoot '..\src\DecomExch\DecomExch.psd1') -Force -DisableNameChecking
    }

    AfterAll {
        Remove-Module DecomExch -Force -ErrorAction SilentlyContinue
    }

    Context 'ConvertTo-DxJsonSafe' {
        It 'zet datums, lijsten en booleans om naar eenvoudige waarden' {
            InModuleScope DecomExch {
                $obj = [pscustomobject]@{ Datum = [datetime]'2026-01-02 03:04:05'; Lijst = @('a', 'b'); Vlag = $true; Getal = 1.5; Leeg = $null; Tekst = 'x' }
                $r = ConvertTo-DxJsonSafe $obj
                $r.Datum | Should -Be '2026-01-02 03:04'
                $r.Lijst | Should -Be 'a; b'
                $r.Vlag | Should -BeTrue
                $r.Getal | Should -Be 1.5
                $r.Leeg | Should -BeNullOrEmpty
                ConvertTo-Json -InputObject $r -Compress | Should -Be '{"Datum":"2026-01-02 03:04","Lijst":"a; b","Vlag":true,"Getal":1.5,"Leeg":null,"Tekst":"x"}'
            }
        }
    }

    Context 'Hulpfuncties' {
        It 'splitst tekst met komma''s en regels in een lijst' {
            InModuleScope DecomExch {
                $list = @(Get-DxStringList "jan@contoso.com, piet`r`n`nklaas;")
                $list -join '|' | Should -Be 'jan@contoso.com|piet|klaas'
                @(Get-DxStringList $null).Count | Should -Be 0
            }
        }

        It 'weigert paden buiten de webmap' {
            InModuleScope DecomExch {
                $root = Join-Path $TestDrive 'web'
                New-Item -Path $root -ItemType Directory -Force | Out-Null
                Set-Content -Path (Join-Path $root 'index.html') -Value 'x'
                Set-Content -Path (Join-Path $TestDrive 'geheim.txt') -Value 'x'

                Get-DxStaticFile -WebRoot $root -UrlPath '/' | Should -Match 'index\.html$'
                Get-DxStaticFile -WebRoot $root -UrlPath '/../geheim.txt' | Should -BeNullOrEmpty
                Get-DxStaticFile -WebRoot $root -UrlPath '/%2e%2e/geheim.txt' | Should -BeNullOrEmpty
                Get-DxStaticFile -WebRoot $root -UrlPath '/bestaatniet.js' | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Get-DxOverview' {
        It 'berekent de kerncijfers uit een inventarisatie' {
            InModuleScope DecomExch {
                $inventory = [ordered]@{
                    'Servers'                 = @([pscustomobject]@{ Name = 'EX01' }, [pscustomobject]@{ Name = 'EX02' })
                    'Databases'               = @([pscustomobject]@{ Name = 'DB01' })
                    'Mailboxtypes'            = @([pscustomobject]@{ Type = 'UserMailbox'; Aantal = 2 })
                    'Mailboxen'               = @(
                        [pscustomobject]@{ DisplayName = 'A'; GrootteMB = 1024; Inactief = $true }
                        [pscustomobject]@{ DisplayName = 'B'; GrootteMB = 512; Inactief = $false }
                    )
                    'Public folders'          = @([pscustomobject]@{ Map = '\X'; GrootteMB = 10 })
                    'Losgekoppelde mailboxen' = $null
                    'Certificaten'            = @([pscustomobject]@{ Verlopen = $true }, [pscustomobject]@{ Verlopen = $false })
                    'Verplaatsaanvragen'      = @([pscustomobject]@{ Status = 'Completed' }, [pscustomobject]@{ Status = 'InProgress' })
                }
                $o = Get-DxOverview -Inventory $inventory
                $o.kpis.servers | Should -Be 2
                $o.kpis.mailboxes | Should -Be 2
                $o.kpis.mailboxSizeGb | Should -Be 1.5
                $o.kpis.inactiveMailboxes | Should -Be 1
                $o.kpis.publicFolders | Should -Be 1
                $o.kpis.disconnected | Should -Be 0
                $o.kpis.expiredCertificates | Should -Be 1
                $o.kpis.openMoveRequests | Should -Be 1
            }
        }
    }

    Context 'Invoke-DxApiRoute' {
        BeforeAll {
            Mock -ModuleName DecomExch Get-MailboxDatabase { [pscustomobject]@{ Name = 'DB01' } }
            Mock -ModuleName DecomExch Get-MailboxStatistics {
                [pscustomobject]@{ DisplayName = 'Oud'; MailboxGuid = 'g1'; DisconnectDate = (Get-Date).AddDays(-90); DisconnectReason = 'Disabled' }
            }
            Mock -ModuleName DecomExch Remove-StoreMailbox { }
            Mock -ModuleName DecomExch Get-OrganizationConfig { [pscustomobject]@{ Name = 'Contoso' } }
        }

        It 'geeft de status van de verbinding' {
            InModuleScope DecomExch {
                $r = Invoke-DxApiRoute -Method GET -Path '/api/status' -State @{ OutputPath = 'X' }
                $r.connected | Should -BeTrue
                $r.organization | Should -Be 'Contoso'
            }
        }

        It 'simuleert standaard (zonder simulate-veld)' {
            InModuleScope DecomExch {
                $r = Invoke-DxApiRoute -Method POST -Path '/api/clean/disconnected' -Body ([pscustomobject]@{ days = 30 }) -State @{}
                $r.Count | Should -Be 1
                $r[0].Verwijderd | Should -BeFalse
            }
            Assert-MockCalled -ModuleName DecomExch Remove-StoreMailbox -Times 0 -Exactly -Scope It
        }

        It 'weigert een echte opruimactie zonder JA-bevestiging' {
            InModuleScope DecomExch {
                $body = [pscustomobject]@{ simulate = $false; days = 30 }
                { Invoke-DxApiRoute -Method POST -Path '/api/clean/disconnected' -Body $body -State @{} } | Should -Throw -ExceptionType ([System.ArgumentException])
            }
            Assert-MockCalled -ModuleName DecomExch Remove-StoreMailbox -Times 0 -Exactly -Scope It
        }

        It 'voert een bevestigde opruimactie uit' {
            InModuleScope DecomExch {
                $body = [pscustomobject]@{ simulate = $false; days = 30; confirm = 'JA' }
                $r = Invoke-DxApiRoute -Method POST -Path '/api/clean/disconnected' -Body $body -State @{}
                $r[0].Verwijderd | Should -BeTrue
            }
            Assert-MockCalled -ModuleName DecomExch Remove-StoreMailbox -Times 1 -Exactly -Scope It
        }

        It 'geeft een lijst met een element als JSON-array terug' {
            InModuleScope DecomExch {
                $r = Invoke-DxApiRoute -Method POST -Path '/api/clean/disconnected' -Body ([pscustomobject]@{ simulate = $true }) -State @{}
                (ConvertTo-Json -InputObject $r -Compress).StartsWith('[') | Should -BeTrue
            }
        }

        It 'weigert een mailboxexport naar een lokaal pad' {
            InModuleScope DecomExch {
                $body = [pscustomobject]@{ mode = 'selection'; identities = 'jan'; filePath = 'D:\PST' }
                { Invoke-DxApiRoute -Method POST -Path '/api/export/mailboxes' -Body $body -State @{} } | Should -Throw -ExceptionType ([System.ArgumentException])
            }
        }

        It 'geeft een 404-fout voor een onbekende route' {
            InModuleScope DecomExch {
                { Invoke-DxApiRoute -Method GET -Path '/api/bestaatniet' -State @{} } | Should -Throw -ExceptionType ([System.Collections.Generic.KeyNotFoundException])
            }
        }

        It 'toont het logboek met de nieuwste regel eerst' {
            InModuleScope DecomExch {
                Write-DxLog -Message 'eerste'
                Write-DxLog -Message 'laatste'
                $r = Invoke-DxApiRoute -Method GET -Path '/api/log' -State @{}
                $r[0].Bericht | Should -Be 'laatste'
            }
        }
    }
}
