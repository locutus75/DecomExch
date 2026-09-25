function Get-DxExchangeInstallPath {
    <#
    .SYNOPSIS
        Bepaalt de installatiemap van Exchange op de opgegeven server.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ComputerName
    )

    $isLocal = (-not $ComputerName) -or $ComputerName -eq $env:COMPUTERNAME -or $ComputerName -eq 'localhost'

    if ($isLocal -and $env:ExchangeInstallPath) {
        return $env:ExchangeInstallPath.TrimEnd('\')
    }

    if (-not $isLocal -and (Test-DxCommand -Name 'Get-ExchangeServer')) {
        $server = Get-ExchangeServer -Identity $ComputerName -ErrorAction SilentlyContinue
        if ($server -and $server.PSObject.Properties['DataPath'] -and $server.DataPath) {
            # DataPath is <install>\Mailbox; de installatiemap is de bovenliggende map.
            return (Split-Path -Path ([string]$server.DataPath) -Parent).TrimEnd('\')
        }
    }

    'C:\Program Files\Microsoft\Exchange Server\V15'
}
