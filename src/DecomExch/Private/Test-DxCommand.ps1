function Test-DxCommand {
    <#
    .SYNOPSIS
        Geeft $true terug als het opgegeven (Exchange) commando beschikbaar is.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Assert-DxExchangeShell {
    <#
    .SYNOPSIS
        Stopt met een duidelijke fout als er geen Exchange-sessie actief is.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-DxExchangeConnection)) {
        throw 'Geen (werkende) Exchange-verbinding. Start de Exchange Management Shell of gebruik eerst Connect-DxExchange; draaien de Exchange-diensten nog?'
    }
}

function Get-DxImplicitExchangeModule {
    <#
    .SYNOPSIS
        Geimporteerde modules van remote Exchange-sessies (implicit remoting, tmp_*), ook van een eerdere run.
    #>
    [CmdletBinding()]
    param()

    Get-Module | Where-Object {
        $_.PrivateData -is [System.Collections.IDictionary] -and $_.PrivateData['ImplicitRemoting'] -and $_.ExportedCommands.ContainsKey('Get-ExchangeServer')
    }
}

function Test-DxExchangeConnection {
    <#
    .SYNOPSIS
        Is er een werkende Exchange-verbinding?
    .DESCRIPTION
        Na het stoppen van de Exchange-diensten (of een herstart van de server) blijft de module van
        een remote sessie geladen, maar is de sessie verbroken. Elke Exchange-cmdlet probeert dan
        opnieuw te verbinden ("Creating a new session for implicit remoting ...") en loopt vast.
        Deze functie herkent dat, verwijdert de verbroken module en sessie, en geeft $false.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $cmd = Get-Command -Name 'Get-ExchangeServer' -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    $module = $cmd.Module
    $implicit = $module -and $module.PrivateData -is [System.Collections.IDictionary] -and $module.PrivateData['ImplicitRemoting']
    if (-not $implicit) { return $true }

    $sessions = @(Get-PSSession -ErrorAction SilentlyContinue | Where-Object { "$($_.ConfigurationName)" -eq 'Microsoft.Exchange' })
    if (@($sessions | Where-Object { "$($_.State)" -eq 'Opened' -and "$($_.Availability)" -ne 'None' }).Count -gt 0) { return $true }

    Write-DxLog -Level Warning -Message ('De verbinding met Exchange is verbroken (draaien de Exchange-diensten nog?). ' +
        'De Exchange-cmdlets zijn verwijderd; maak opnieuw verbinding zodra Exchange weer draait.')
    foreach ($m in @(Get-DxImplicitExchangeModule)) { Remove-Module -ModuleInfo $m -Force -ErrorAction SilentlyContinue }
    foreach ($s in $sessions) { Remove-PSSession -Session $s -ErrorAction SilentlyContinue }
    $script:DxSession = $null
    $script:DxSessionModule = $null
    $false
}
