function Test-DxLocalComputer {
    <#
    .SYNOPSIS
        Is de opgegeven naam deze computer (kort, FQDN of localhost)?
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()] [string]$ComputerName)

    if (-not $ComputerName) { return $true }
    $short = ($ComputerName -split '\.')[0]
    [bool]($ComputerName -in 'localhost', '.', '127.0.0.1' -or ($env:COMPUTERNAME -and $short -eq $env:COMPUTERNAME))
}

function New-DxCimSession {
    <#
    .SYNOPSIS
        CIM-sessie naar een server: eerst WinRM (WSMan), anders DCOM. $null voor de lokale computer.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [AllowNull()]
        [pscredential]$Credential
    )

    if (Test-DxLocalComputer -ComputerName $ComputerName) { return $null }

    $params = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
    if ($Credential) { $params['Credential'] = $Credential }
    try {
        return New-CimSession @params
    }
    catch {
        $wsmanError = $_.Exception.Message
    }
    try {
        return New-CimSession @params -SessionOption (New-CimSessionOption -Protocol Dcom)
    }
    catch {
        throw ("Geen verbinding met de diensten op {0}. WinRM: {1} DCOM: {2} Controleer of WinRM aanstaat (winrm quickconfig), of de firewall RPC/WMI toestaat, en of het account lokale beheerder is. Vanaf een laptop buiten het domein: voeg de server toe aan TrustedHosts." -f $ComputerName, $wsmanError, $_.Exception.Message)
    }
}

function Get-DxServiceCim {
    <#
    .SYNOPSIS
        Win32_Service-objecten van een server (via een CIM-sessie of lokaal).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$CimSession,

        [string]$Name
    )

    $params = @{ ClassName = 'Win32_Service'; ErrorAction = 'Stop' }
    if ($CimSession) { $params['CimSession'] = $CimSession }
    if ($Name) { $params['Filter'] = "Name = '$($Name -replace "'", "''")'" }
    Get-CimInstance @params
}

function Invoke-DxServiceMethod {
    <#
    .SYNOPSIS
        Roept een methode van Win32_Service aan (StopService, StartService, ChangeStartMode) en geeft de ReturnValue.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [object]$Service,

        [Parameter(Mandatory)]
        [ValidateSet('StopService', 'StartService', 'ChangeStartMode')]
        [string]$Method,

        [string]$StartMode,

        [AllowNull()]
        [object]$CimSession
    )

    $params = @{ InputObject = $Service; MethodName = $Method; ErrorAction = 'Stop' }
    if ($CimSession) { $params['CimSession'] = $CimSession }
    if ($Method -eq 'ChangeStartMode') { $params['Arguments'] = @{ StartMode = $StartMode } }
    [int](Invoke-CimMethod @params).ReturnValue
}

function Set-DxServiceDelayedStart {
    <#
    .SYNOPSIS
        Zet 'Automatisch (vertraagd starten)' aan of uit via het register (StdRegProv).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [bool]$Enabled,

        [AllowNull()]
        [object]$CimSession
    )

    $params = @{
        Namespace   = 'root/default'
        ClassName   = 'StdRegProv'
        MethodName  = 'SetDWORDValue'
        Arguments   = @{ hDefKey = [uint32]2147483650; sSubKeyName = "SYSTEM\CurrentControlSet\Services\$Name"; sValueName = 'DelayedAutostart'; uValue = [uint32]([int]$Enabled) }
        ErrorAction = 'Stop'
    }
    if ($CimSession) { $params['CimSession'] = $CimSession }
    [void](Invoke-CimMethod @params)
}

function Get-DxServiceReturnText {
    <#
    .SYNOPSIS
        Uitleg bij de ReturnValue van Win32_Service-methoden.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([int]$Code)

    switch ($Code) {
        0 { 'OK' }
        2 { 'Toegang geweigerd' }
        3 { 'Andere diensten zijn hiervan afhankelijk en draaien nog' }
        5 { 'De dienst kan deze opdracht nu niet aannemen' }
        6 { 'De dienst draait niet' }
        7 { 'De dienst reageerde niet op tijd' }
        8 { 'Onbekende fout' }
        10 { 'De dienst draait al' }
        14 { 'De dienst is uitgeschakeld' }
        21 { 'Ongeldige parameter' }
        default { "Foutcode $Code" }
    }
}

function Test-DxExchangeServiceObject {
    <#
    .SYNOPSIS
        Hoort deze dienst bij Exchange (of bij IIS, met -IncludeIis)?
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$Service,

        [switch]$IncludeIis
    )

    $name = "$($Service.Name)"
    $path = "$(Get-DxObjectValue $Service 'PathName')"
    if ($name -like 'MSExchange*' -or $name -in 'MSComplianceAudit', 'HostControllerService', 'SearchExchangeTracing', 'wsbexchange') { return $true }
    if ($path -match '\\Microsoft\\Exchange Server\\') { return $true }
    if ($IncludeIis -and $name -in 'W3SVC', 'WAS', 'IISADMIN') { return $true }
    $false
}

function Get-DxServiceStatePath {
    <#
    .SYNOPSIS
        Bestand met de oorspronkelijke toestand van de diensten van een server.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$ComputerName
    )

    Join-Path -Path $Path -ChildPath ("Diensten_{0}.json" -f (ConvertTo-DxSafeFileName -Name $ComputerName.ToUpper()))
}

function Read-DxServiceState {
    <#
    .SYNOPSIS
        Leest de opgeslagen toestand (hashtable naam -> @{ StartMode; State; DelayedAutoStart; DisplayName }).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$File)

    $state = @{}
    if (-not (Test-Path -LiteralPath $File)) { return $state }
    $data = Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($s in @($data.Services)) {
        $state["$($s.Name)"] = @{ Name = "$($s.Name)"; DisplayName = "$($s.DisplayName)"; StartMode = "$($s.StartMode)"; State = "$($s.State)"; DelayedAutoStart = [bool]$s.DelayedAutoStart }
    }
    $state
}

function Wait-DxServiceState {
    <#
    .SYNOPSIS
        Wacht tot de diensten de gewenste toestand hebben; geeft de namen die dat niet haalden.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowNull()] [object]$CimSession,
        [Parameter(Mandatory)] [string[]]$Name,
        [Parameter(Mandatory)] [string]$State,
        [int]$TimeoutSeconds = 180
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $current = @{}
        foreach ($svc in @(Get-DxServiceCim -CimSession $CimSession)) { $current["$($svc.Name)"] = "$($svc.State)" }
        $pending = @($Name | Where-Object { $current[$_] -ne $State })
        if ($pending.Count -eq 0) { return }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    $pending
}

function ConvertTo-DxStartModeText {
    <#
    .SYNOPSIS
        Leesbaar opstarttype, bijv. 'Auto (vertraagd)'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()] [string]$StartMode,
        [bool]$Delayed
    )

    if ($StartMode -in 'Auto', 'Automatic' -and $Delayed) { return 'Auto (vertraagd)' }
    $StartMode
}
