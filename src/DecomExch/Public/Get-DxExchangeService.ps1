function Get-DxExchangeService {
    <#
    .SYNOPSIS
        Toont de Exchange-diensten van een server: status, opstarttype en (als die is opgeslagen)
        de oorspronkelijke toestand van voor Stop-DxExchangeService.
    .DESCRIPTION
        Werkt via CIM (WinRM, anders DCOM), ook vanaf een beheerlaptop. Er is geen Exchange-verbinding
        voor nodig; wel lokale beheerrechten op de server (-Credential of die van Connect-DxExchange).
    .EXAMPLE
        Get-DxExchangeService -ComputerName EX01 | Format-Table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [pscredential]$Credential,

        # Ook IIS (W3SVC, WAS, IISADMIN) tonen.
        [switch]$IncludeIis,

        # Map met de opgeslagen toestand.
        [string]$StatePath = (Join-Path -Path (Get-Location).Path -ChildPath 'Output\Diensten')
    )

    $session = New-DxCimSession -ComputerName $ComputerName -Credential (Resolve-DxCredential -Credential $Credential)
    try {
        $saved = Read-DxServiceState -File (Get-DxServiceStatePath -Path $StatePath -ComputerName $ComputerName)
        foreach ($svc in @(Get-DxServiceCim -CimSession $session | Where-Object { (Test-DxExchangeServiceObject -Service $_ -IncludeIis:$IncludeIis) -or $saved.ContainsKey("$($_.Name)") } | Sort-Object Name)) {
            $orig = $saved["$($svc.Name)"]
            [pscustomobject]@{
                Server         = $ComputerName
                Dienst         = "$($svc.Name)"
                Weergavenaam   = "$($svc.DisplayName)"
                Status         = "$($svc.State)"
                Opstarttype    = ConvertTo-DxStartModeText -StartMode "$($svc.StartMode)" -Delayed ([bool](Get-DxObjectValue $svc 'DelayedAutoStart'))
                Oorspronkelijk = if ($orig) { '{0}, {1}' -f $orig.State, (ConvertTo-DxStartModeText -StartMode $orig.StartMode -Delayed $orig.DelayedAutoStart) } else { $null }
            }
        }
    }
    finally {
        if ($session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
    }
}
