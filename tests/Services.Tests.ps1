# Tests voor het stoppen en herstellen van Exchange-diensten. Compatibel met Pester 4.10+ en 5.

Describe 'DecomExch Exchange-diensten' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'ExchangeStubs.ps1')
        Import-Module (Join-Path $PSScriptRoot '..\src\DecomExch\DecomExch.psd1') -Force -DisableNameChecking
    }

    AfterAll {
        foreach ($v in 'DxSvc', 'DxSvcCalls', 'DxSvcState') { Remove-Variable -Name $v -Scope Global -ErrorAction SilentlyContinue }
        Remove-Module DecomExch -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $exBin = 'C:\Program Files\Microsoft\Exchange Server\V15\Bin'
        $global:DxSvc = @(
            [pscustomobject]@{ Name = 'MSExchangeADTopology'; DisplayName = 'Microsoft Exchange Active Directory Topology'; State = 'Running'; StartMode = 'Auto'; DelayedAutoStart = $false; PathName = "$exBin\Microsoft.Exchange.Directory.TopologyService.exe" }
            [pscustomobject]@{ Name = 'MSExchangeTransport'; DisplayName = 'Microsoft Exchange Transport'; State = 'Running'; StartMode = 'Auto'; DelayedAutoStart = $false; PathName = "$exBin\MSExchangeTransport.exe" }
            [pscustomobject]@{ Name = 'MSExchangeIS'; DisplayName = 'Microsoft Exchange Information Store'; State = 'Running'; StartMode = 'Auto'; DelayedAutoStart = $true; PathName = "$exBin\Microsoft.Exchange.Store.Service.exe" }
            [pscustomobject]@{ Name = 'MSExchangeImap4'; DisplayName = 'Microsoft Exchange IMAP4'; State = 'Stopped'; StartMode = 'Manual'; DelayedAutoStart = $false; PathName = "$exBin\Microsoft.Exchange.Imap4Service.exe" }
            [pscustomobject]@{ Name = 'MSExchangePop3'; DisplayName = 'Microsoft Exchange POP3'; State = 'Stopped'; StartMode = 'Disabled'; DelayedAutoStart = $false; PathName = "$exBin\Microsoft.Exchange.Pop3Service.exe" }
            [pscustomobject]@{ Name = 'HostControllerService'; DisplayName = 'Microsoft Exchange Search Host Controller'; State = 'Running'; StartMode = 'Auto'; DelayedAutoStart = $false; PathName = "$exBin\Search\Ceres\HostController\hostcontrollerservice.exe" }
            [pscustomobject]@{ Name = 'W3SVC'; DisplayName = 'World Wide Web Publishing Service'; State = 'Running'; StartMode = 'Auto'; DelayedAutoStart = $false; PathName = 'C:\Windows\system32\svchost.exe -k iissvcs' }
            [pscustomobject]@{ Name = 'Spooler'; DisplayName = 'Print Spooler'; State = 'Running'; StartMode = 'Auto'; DelayedAutoStart = $false; PathName = 'C:\Windows\System32\spoolsv.exe' }
        )
        $global:DxSvcCalls = New-Object System.Collections.Generic.List[string]
        $global:DxSvcState = Join-Path $TestDrive ('state' + [guid]::NewGuid().ToString('N'))

        Mock -ModuleName DecomExch New-DxCimSession { $null }
        Mock -ModuleName DecomExch Start-Sleep { }
        Mock -ModuleName DecomExch Get-DxServiceCim {
            if ($Name) { $global:DxSvc | Where-Object Name -eq $Name } else { $global:DxSvc }
        }
        Mock -ModuleName DecomExch Set-DxServiceDelayedStart { $global:DxSvcCalls.Add("Delayed $Name $Enabled") }
        Mock -ModuleName DecomExch Invoke-DxServiceMethod {
            $global:DxSvcCalls.Add("$Method $($Service.Name) $StartMode".Trim())
            $svc = $global:DxSvc | Where-Object Name -eq $Service.Name
            switch ($Method) {
                'ChangeStartMode' { $svc.StartMode = if ($StartMode -eq 'Automatic') { 'Auto' } else { $StartMode }; return 0 }
                'StopService' {
                    # ADTopology kan pas stoppen als de andere Exchange-diensten gestopt zijn.
                    if ($svc.Name -eq 'MSExchangeADTopology' -and @($global:DxSvc | Where-Object { $_.Name -like 'MSExchange*' -and $_.Name -ne 'MSExchangeADTopology' -and $_.State -ne 'Stopped' }).Count -gt 0) { return 3 }
                    $svc.State = 'Stopped'; return 0
                }
                'StartService' { if ($svc.StartMode -eq 'Disabled') { return 14 }; $svc.State = 'Running'; return 0 }
            }
        }
    }

    It 'herkent Exchange-diensten, en IIS alleen op verzoek' {
        $rows = @(Get-DxExchangeService -ComputerName EX01 -StatePath $global:DxSvcState)
        @($rows | ForEach-Object Dienst) -join ',' | Should -Be 'HostControllerService,MSExchangeADTopology,MSExchangeImap4,MSExchangeIS,MSExchangePop3,MSExchangeTransport'
        ($rows | Where-Object Dienst -eq 'MSExchangeIS').Opstarttype | Should -Be 'Auto (vertraagd)'

        $withIis = @(Get-DxExchangeService -ComputerName EX01 -IncludeIis -StatePath $global:DxSvcState)
        @($withIis | Where-Object Dienst -eq 'W3SVC').Count | Should -Be 1
        @($withIis | Where-Object Dienst -eq 'Spooler').Count | Should -Be 0
    }

    It 'wijzigt niets met -WhatIf' {
        $rows = @(Stop-DxExchangeService -ComputerName EX01 -StatePath $global:DxSvcState -WhatIf)
        $rows.Count | Should -Be 6
        @($rows | Where-Object Uitgevoerd).Count | Should -Be 0
        $global:DxSvcCalls.Count | Should -Be 0
        Test-Path $global:DxSvcState | Should -BeFalse
    }

    It 'stopt alle Exchange-diensten, zet ze op Disabled en bewaart de oorspronkelijke toestand' {
        $rows = @(Stop-DxExchangeService -ComputerName EX01 -StatePath $global:DxSvcState -Confirm:$false)
        @($rows | Where-Object { -not $_.Uitgevoerd }).Count | Should -Be 0
        @($global:DxSvc | Where-Object { $_.Name -like 'MSExchange*' -or $_.Name -eq 'HostControllerService' } | Where-Object { $_.State -ne 'Stopped' -or $_.StartMode -ne 'Disabled' }).Count | Should -Be 0
        ($global:DxSvc | Where-Object Name -eq 'W3SVC').State | Should -Be 'Running'
        ($global:DxSvc | Where-Object Name -eq 'Spooler').State | Should -Be 'Running'

        # Eerst uitschakelen, dan stoppen; ADTopology als laatste; al uitgeschakelde dienst niet opnieuw.
        $calls = @($global:DxSvcCalls)
        $firstStop = [array]::IndexOf($calls, @($calls | Where-Object { $_ -like 'StopService*' })[0])
        @($calls[0..($firstStop - 1)] | Where-Object { $_ -notlike 'ChangeStartMode*' }).Count | Should -Be 0
        @($calls | Where-Object { $_ -like 'StopService*' })[-1] | Should -Be 'StopService MSExchangeADTopology'
        $calls | Should -Not -Contain 'ChangeStartMode MSExchangePop3 Disabled'

        $file = Join-Path $global:DxSvcState 'Diensten_EX01.json'
        $saved = Get-Content $file -Raw | ConvertFrom-Json
        (@($saved.Services) | Where-Object Name -eq 'MSExchangeIS').DelayedAutoStart | Should -BeTrue
        (@($saved.Services) | Where-Object Name -eq 'MSExchangeImap4').StartMode | Should -Be 'Manual'
    }

    It 'overschrijft de opgeslagen toestand niet bij een tweede keer stoppen' {
        Stop-DxExchangeService -ComputerName EX01 -StatePath $global:DxSvcState -Confirm:$false | Out-Null
        Stop-DxExchangeService -ComputerName EX01 -StatePath $global:DxSvcState -Confirm:$false | Out-Null
        $saved = Get-Content (Join-Path $global:DxSvcState 'Diensten_EX01.json') -Raw | ConvertFrom-Json
        (@($saved.Services) | Where-Object Name -eq 'MSExchangeTransport').StartMode | Should -Be 'Auto'
        (@($saved.Services) | Where-Object Name -eq 'MSExchangeTransport').State | Should -Be 'Running'
    }

    It 'herstelt precies de oorspronkelijke toestand' {
        Stop-DxExchangeService -ComputerName EX01 -StatePath $global:DxSvcState -Confirm:$false | Out-Null
        $global:DxSvcCalls.Clear()

        $rows = @(Restore-DxExchangeService -ComputerName EX01 -StatePath $global:DxSvcState -Confirm:$false)
        @($rows | Where-Object { -not $_.Uitgevoerd }).Count | Should -Be 0
        foreach ($n in 'MSExchangeADTopology', 'MSExchangeTransport', 'MSExchangeIS', 'HostControllerService') {
            ($global:DxSvc | Where-Object Name -eq $n).State | Should -Be 'Running'
            ($global:DxSvc | Where-Object Name -eq $n).StartMode | Should -Be 'Auto'
        }
        ($global:DxSvc | Where-Object Name -eq 'MSExchangeImap4').StartMode | Should -Be 'Manual'
        ($global:DxSvc | Where-Object Name -eq 'MSExchangeImap4').State | Should -Be 'Stopped'
        ($global:DxSvc | Where-Object Name -eq 'MSExchangePop3').StartMode | Should -Be 'Disabled'
        $global:DxSvcCalls | Should -Contain 'Delayed MSExchangeIS True'
        @($global:DxSvcCalls | Where-Object { $_ -like 'StartService*' })[0] | Should -Be 'StartService MSExchangeADTopology'

        Test-Path (Join-Path $global:DxSvcState 'Diensten_EX01.json') | Should -BeFalse
        @(Get-ChildItem $global:DxSvcState -Filter 'Diensten_EX01_hersteld_*.json').Count | Should -Be 1
    }

    It 'gebruikt de standaardwaarden als er geen opgeslagen toestand is' {
        foreach ($s in $global:DxSvc) { if ($s.Name -like 'MSExchange*' -or $s.Name -eq 'HostControllerService') { $s.State = 'Stopped'; $s.StartMode = 'Disabled' } }
        $rows = @(Restore-DxExchangeService -ComputerName EX01 -StatePath $global:DxSvcState -Confirm:$false)
        ($rows | Where-Object Dienst -eq 'MSExchangeTransport').Opmerking | Should -Match 'Standaardwaarde'
        ($global:DxSvc | Where-Object Name -eq 'MSExchangeTransport').State | Should -Be 'Running'
        ($global:DxSvc | Where-Object Name -eq 'MSExchangePop3').StartMode | Should -Be 'Manual'
        ($global:DxSvc | Where-Object Name -eq 'MSExchangePop3').State | Should -Be 'Stopped'
        ($global:DxSvc | Where-Object Name -eq 'W3SVC').StartMode | Should -Be 'Auto'
    }

    It 'meldt een dienst die niet wil stoppen' {
        Mock -ModuleName DecomExch Invoke-DxServiceMethod {
            $svc = $global:DxSvc | Where-Object Name -eq $Service.Name
            if ($Method -eq 'ChangeStartMode') { $svc.StartMode = $StartMode; return 0 }
            if ($svc.Name -eq 'MSExchangeTransport') { return 2 }
            $svc.State = 'Stopped'; return 0
        }
        $rows = @(Stop-DxExchangeService -ComputerName EX01 -StatePath $global:DxSvcState -Confirm:$false)
        $bad = @($rows | Where-Object { -not $_.Uitgevoerd })
        $bad.Count | Should -Be 1
        $bad[0].Dienst | Should -Be 'MSExchangeTransport'
        $bad[0].Opmerking | Should -Match 'Toegang geweigerd'
    }

    It 'herkent de lokale computer' {
        InModuleScope DecomExch {
            Test-DxLocalComputer -ComputerName 'localhost' | Should -BeTrue
            Test-DxLocalComputer -ComputerName '' | Should -BeTrue
            Test-DxLocalComputer -ComputerName 'ergens-anders-01.contoso.local' | Should -BeFalse
            if ($env:COMPUTERNAME) { Test-DxLocalComputer -ComputerName "$($env:COMPUTERNAME).contoso.local" | Should -BeTrue }
        }
    }

    It 'API: simuleert standaard en vraagt bevestiging voor een echte uitvoering' {
        InModuleScope DecomExch {
            $state = @{ OutputPath = $global:DxSvcState }
            $sim = Invoke-DxApiRoute -Method POST -Path '/api/services/stop' -Body ([pscustomobject]@{ server = 'EX01' }) -State $state
            $sim.Count | Should -Be 6
            $global:DxSvcCalls.Count | Should -Be 0

            { Invoke-DxApiRoute -Method POST -Path '/api/services/stop' -Body ([pscustomobject]@{ server = 'EX01'; simulate = $false }) -State $state } | Should -Throw -ExceptionType ([System.ArgumentException])
            { Invoke-DxApiRoute -Method POST -Path '/api/services/stop' -Body ([pscustomobject]@{ server = ''; simulate = $true }) -State $state } | Should -Throw -ExceptionType ([System.ArgumentException])

            $live = Invoke-DxApiRoute -Method POST -Path '/api/services/stop' -Body ([pscustomobject]@{ server = 'EX01'; simulate = $false; confirm = 'JA'; includeIis = $true }) -State $state
            $live.Count | Should -Be 7
            ($global:DxSvc | Where-Object Name -eq 'W3SVC').StartMode | Should -Be 'Disabled'

            $status = Invoke-DxApiRoute -Method GET -Path '/api/services' -Query @{ server = 'EX01'; iis = '1' } -State $state
            ($status | Where-Object { $_.Dienst -eq 'W3SVC' }).Oorspronkelijk | Should -Be 'Running, Auto'

            $restored = Invoke-DxApiRoute -Method POST -Path '/api/services/restore' -Body ([pscustomobject]@{ server = 'EX01'; simulate = $false; confirm = 'JA' }) -State $state
            @($restored | Where-Object { -not $_.Uitgevoerd }).Count | Should -Be 0
            ($global:DxSvc | Where-Object Name -eq 'W3SVC').State | Should -Be 'Running'
        }
    }
}
