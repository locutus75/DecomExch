# Tests voor het herkennen van een verbroken Exchange-sessie. Compatibel met Pester 4.10+ en 5.

Describe 'DecomExch verbroken Exchange-verbinding' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'ExchangeStubs.ps1')
        Import-Module (Join-Path $PSScriptRoot '..\src\DecomExch\DecomExch.psd1') -Force -DisableNameChecking

        # Nagebootste module van implicit remoting (zoals tmp_xxx.psm1 van Import-PSSession).
        $global:DxFakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ('tmp_dx' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $global:DxFakeDir -ItemType Directory | Out-Null
        Set-Content -Path (Join-Path $global:DxFakeDir 'tmp_dx.psm1') -Value 'function Get-ExchangeServer { param($Identity, $ErrorAction) throw "No session has been associated with this implicit remoting module." }'
        Set-Content -Path (Join-Path $global:DxFakeDir 'tmp_dx.psd1') -Value "@{ ModuleVersion = '1.0'; RootModule = 'tmp_dx.psm1'; FunctionsToExport = @('Get-ExchangeServer'); PrivateData = @{ ImplicitRemoting = `$true } }"
    }

    AfterAll {
        Get-Module tmp_dx | Remove-Module -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $global:DxFakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name DxFakeDir -Scope Global -ErrorAction SilentlyContinue
        # De stub van Get-ExchangeServer terugzetten voor volgende testbestanden.
        . (Join-Path $PSScriptRoot 'ExchangeStubs.ps1')
        Remove-Module DecomExch -Force -ErrorAction SilentlyContinue
    }

    It 'ziet de lokale Exchange-cmdlets als verbonden' {
        InModuleScope DecomExch { Test-DxExchangeConnection | Should -BeTrue }
    }

    It 'ruimt een verbroken remote sessie op en meldt niet verbonden' {
        Import-Module (Join-Path $global:DxFakeDir 'tmp_dx.psd1') -Global -Force
        (Get-Command Get-ExchangeServer).Module.Name | Should -Be 'tmp_dx'

        InModuleScope DecomExch {
            @(Get-DxImplicitExchangeModule).Count | Should -Be 1
            Test-DxExchangeConnection | Should -BeFalse
            @(Get-DxImplicitExchangeModule).Count | Should -Be 0
        }
        @(Get-Module tmp_dx).Count | Should -Be 0
    }

    It 'ruimt op na een fout van implicit remoting in een onderdeel' {
        Import-Module (Join-Path $global:DxFakeDir 'tmp_dx.psd1') -Global -Force
        InModuleScope DecomExch {
            Invoke-DxSafe -Section 'Test' -Action { Get-ExchangeServer -ErrorAction Stop } 3>$null | Out-Null
        }
        @(Get-Module tmp_dx).Count | Should -Be 0
    }

    It 'wijst bij een lege serverfout op gestopte Exchange-diensten' {
        InModuleScope DecomExch {
            $hint = Get-DxConnectionHint -Message 'Connecting to remote server ex01 failed with the following error message :  For more information, see the about_Remote_Troubleshooting Help topic.' -Server 'ex01.contoso.local'
            $hint | Should -Match 'Exchange-diensten'
            $hint | Should -Match 'RestoreServices'
        }
    }
}
