# Tests voor remote verbinden met andere inloggegevens (-Credential). Compatibel met Pester 4.10+ en 5.

Describe 'DecomExch remote verbinding' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'ExchangeStubs.ps1')
        Import-Module (Join-Path $PSScriptRoot '..\src\DecomExch\DecomExch.psd1') -Force -DisableNameChecking
        # Globaal, zodat InModuleScope-blokken er ook bij kunnen (Pester 4 kent geen -Parameters).
        $global:DxTestCredential = New-Object System.Management.Automation.PSCredential('contoso\beheerder', (ConvertTo-SecureString 'geheim' -AsPlainText -Force))
    }

    AfterAll {
        Remove-Variable -Name DxTestCredential -Scope Global -ErrorAction SilentlyContinue
        Remove-Module DecomExch -Force -ErrorAction SilentlyContinue
    }

    Context 'Connect-DxExchange' {
        BeforeAll {
            Mock -ModuleName DecomExch New-DxExchangeSession { [pscustomobject]@{ Session = 'sessie'; Module = 'module' } }
            Mock -ModuleName DecomExch Remove-DxExchangeSession { }
        }

        AfterEach {
            InModuleScope DecomExch { $script:DxSession = $null; $script:DxSessionModule = $null; $script:DxExchangeServer = $null; $script:DxCredential = $null }
        }

        It 'verbindt remote met de opgegeven inloggegevens en onthoudt ze' {
            Connect-DxExchange -Server 'ex01.contoso.local' -Credential $global:DxTestCredential

            Assert-MockCalled -ModuleName DecomExch New-DxExchangeSession -Times 1 -Exactly -Scope It -ParameterFilter {
                $SessionParameters.ConnectionUri -eq 'http://ex01.contoso.local/PowerShell/' -and
                $SessionParameters.ConfigurationName -eq 'Microsoft.Exchange' -and
                $SessionParameters.Authentication -eq 'Kerberos' -and
                $SessionParameters.Credential.UserName -eq 'contoso\beheerder'
            }
            InModuleScope DecomExch {
                $script:DxCredential.UserName | Should -Be 'contoso\beheerder'
                $script:DxExchangeServer | Should -Be 'ex01.contoso.local'
            }
        }

        It 'verbindt zonder inloggegevens met het huidige account' {
            Connect-DxExchange -Server 'ex01.contoso.local' -Authentication Negotiate

            Assert-MockCalled -ModuleName DecomExch New-DxExchangeSession -Times 1 -Exactly -Scope It -ParameterFilter {
                -not $SessionParameters.ContainsKey('Credential') -and $SessionParameters.Authentication -eq 'Negotiate'
            }
            InModuleScope DecomExch { $script:DxCredential | Should -BeNullOrEmpty }
        }

        It 'sluit een bestaande sessie bij het wisselen van server' {
            Connect-DxExchange -Server 'ex01.contoso.local' -Credential $global:DxTestCredential
            Connect-DxExchange -Server 'ex02.contoso.local' -Credential $global:DxTestCredential

            Assert-MockCalled -ModuleName DecomExch Remove-DxExchangeSession -Times 1 -Exactly -Scope It
            InModuleScope DecomExch { $script:DxExchangeServer | Should -Be 'ex02.contoso.local' }
        }

        It 'geeft een duidelijke fout als verbinden mislukt' {
            Mock -ModuleName DecomExch New-DxExchangeSession { throw 'Access is denied.' }
            $message = $null
            try { Connect-DxExchange -Server 'ex01.contoso.local' -Credential $global:DxTestCredential } catch { $message = $_.Exception.Message }
            $message | Should -Match 'Verbinden met ex01\.contoso\.local mislukt: Access is denied'
        }

        It 'onthoudt de inloggegevens ook als de eerste poging mislukt' {
            Mock -ModuleName DecomExch New-DxExchangeSession { throw 'Kerberos: 0x80090311' }
            try { Connect-DxExchange -Server 'ex01.contoso.local' -Credential $global:DxTestCredential -Authentication Negotiate } catch { }
            InModuleScope DecomExch {
                $script:DxCredential.UserName | Should -Be 'contoso\beheerder'
                $script:DxAuthentication | Should -Be 'Negotiate'
                $script:DxAuthentication = 'Kerberos'
            }
        }

        It 'weigert -Credential zonder -Server' {
            $message = $null
            try { Connect-DxExchange -Credential $global:DxTestCredential } catch { $message = $_.Exception.Message }
            $message | Should -Match 'Geef -Server op'
        }
    }

    Context 'Logbestanden op een remote server' {
        BeforeAll {
            Mock -ModuleName DecomExch New-PSDrive { }
            Mock -ModuleName DecomExch Remove-PSDrive { }
        }

        AfterEach {
            InModuleScope DecomExch { $script:DxCredential = $null }
        }

        It 'koppelt per station een admin-share met de inloggegevens' {
            InModuleScope DecomExch {
                $Cred = $global:DxTestCredential
                $names = @(Mount-DxAdminShare -ComputerName 'EX01' -Path 'C:\a', 'C:\b', 'D:\Exchange\Logging' -Credential $Cred)
                $names.Count | Should -Be 2
            }
            Assert-MockCalled -ModuleName DecomExch New-PSDrive -Times 2 -Exactly -Scope It
            Assert-MockCalled -ModuleName DecomExch New-PSDrive -Times 1 -Exactly -Scope It -ParameterFilter { $Root -eq '\\EX01\C$' -and $Credential.UserName -eq 'contoso\beheerder' }
            Assert-MockCalled -ModuleName DecomExch New-PSDrive -Times 1 -Exactly -Scope It -ParameterFilter { $Root -eq '\\EX01\D$' }
        }

        It 'koppelt niets zonder inloggegevens of voor de lokale computer' {
            InModuleScope DecomExch {
                $Cred = $global:DxTestCredential
                @(Mount-DxAdminShare -ComputerName 'EX01' -Path 'C:\a' -Credential $null).Count | Should -Be 0
                @(Mount-DxAdminShare -ComputerName '' -Path 'C:\a' -Credential $Cred).Count | Should -Be 0
                @(Mount-DxAdminShare -ComputerName 'localhost' -Path 'C:\a' -Credential $Cred).Count | Should -Be 0
            }
            Assert-MockCalled -ModuleName DecomExch New-PSDrive -Times 0 -Exactly -Scope It
        }

        It 'Clear-DxExchangeLog koppelt de share en ruimt de koppeling weer op' {
            Clear-DxExchangeLog -ComputerName 'EX01' -Path 'C:\inetpub\logs\LogFiles' -Credential $global:DxTestCredential -Confirm:$false | Out-Null
            Assert-MockCalled -ModuleName DecomExch New-PSDrive -Times 1 -Exactly -Scope It -ParameterFilter { $Root -eq '\\EX01\C$' }
            Assert-MockCalled -ModuleName DecomExch Remove-PSDrive -Times 1 -Exactly -Scope It
        }

        It 'gebruikt de inloggegevens van Connect-DxExchange als -Credential ontbreekt' {
            InModuleScope DecomExch { $script:DxCredential = $global:DxTestCredential }
            Get-DxLogCleanupCandidate -ComputerName 'EX01' -Path 'C:\inetpub\logs\LogFiles' | Out-Null
            Assert-MockCalled -ModuleName DecomExch New-PSDrive -Times 1 -Exactly -Scope It -ParameterFilter { $Credential.UserName -eq 'contoso\beheerder' }
            Assert-MockCalled -ModuleName DecomExch Remove-PSDrive -Times 1 -Exactly -Scope It
        }
    }

    Context 'Get-DxConnectionHint' {
        It 'geeft een gerichte oplossing per soort fout' {
            InModuleScope DecomExch {
                Get-DxConnectionHint -Message 'errorcode 0x80090311 occurred: your domain isn''t available' | Should -Match 'domeincontroller'
                Get-DxConnectionHint -Message 'Kerberos authentication cannot be used with implicit credentials if the client computer is not joined to a domain' | Should -Match '-Credential'
                Get-DxConnectionHint -Message 'add the destination computer to the WinRM TrustedHosts configuration' -Server 'ex01' -Authentication Negotiate | Should -Match "TrustedHosts -Value 'ex01'"
                Get-DxConnectionHint -Message 'Access is denied.' | Should -Match 'RemotePowerShellEnabled'
                Get-DxConnectionHint -Message 'iets anders' | Should -Match 'poort 80'
            }
        }
    }

    Context 'Webinterface' {
        It 'toont server en account in de status en geeft het wachtwoord niet door' {
            InModuleScope DecomExch {
                $Cred = $global:DxTestCredential
                $script:DxCredential = $Cred
                $script:DxExchangeServer = 'ex01.contoso.local'
                try {
                    $r = Invoke-DxApiRoute -Method GET -Path '/api/status' -State @{ OutputPath = 'X'; Organization = 'Contoso' }
                    $r.exchangeServer | Should -Be 'ex01.contoso.local'
                    $r.account | Should -Be 'contoso\beheerder'
                    (ConvertTo-Json -InputObject $r -Compress) | Should -Not -Match 'geheim'
                }
                finally {
                    $script:DxCredential = $null
                    $script:DxExchangeServer = $null
                }
            }
        }

        It 'verbindt opnieuw met de onthouden inloggegevens' {
            Mock -ModuleName DecomExch Connect-DxExchange { }
            InModuleScope DecomExch {
                $Cred = $global:DxTestCredential
                $script:DxCredential = $Cred
                try {
                    Invoke-DxApiRoute -Method POST -Path '/api/connect' -Body ([pscustomobject]@{ server = 'ex02.contoso.local' }) -State @{} | Out-Null
                }
                finally { $script:DxCredential = $null }
            }
            Assert-MockCalled -ModuleName DecomExch Connect-DxExchange -Times 1 -Exactly -Scope It -ParameterFilter {
                $Server -eq 'ex02.contoso.local' -and $Credential.UserName -eq 'contoso\beheerder'
            }
        }

        It 'gebruikt de gekozen aanmeldmethode en weigert een onbekende' {
            Mock -ModuleName DecomExch Connect-DxExchange { }
            InModuleScope DecomExch {
                Invoke-DxApiRoute -Method POST -Path '/api/connect' -Body ([pscustomobject]@{ server = 'ex02'; authentication = 'Negotiate' }) -State @{} | Out-Null
                { Invoke-DxApiRoute -Method POST -Path '/api/connect' -Body ([pscustomobject]@{ server = 'ex02'; authentication = 'Digest' }) -State @{} } | Should -Throw -ExceptionType ([System.ArgumentException])
            }
            Assert-MockCalled -ModuleName DecomExch Connect-DxExchange -Times 1 -Exactly -Scope It -ParameterFilter { $Authentication -eq 'Negotiate' }
        }
    }
}
