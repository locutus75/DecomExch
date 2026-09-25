function Clear-DxExchangeLog {
    <#
    .SYNOPSIS
        Verwijdert oude diagnostische Exchange- en IIS-logbestanden.
    .DESCRIPTION
        Gebruikt Get-DxLogCleanupCandidate om bestanden te selecteren en vraagt per map
        om bevestiging. Gebruik -WhatIf om alleen te zien wat er zou gebeuren.
        Bestanden die in gebruik zijn worden overgeslagen. Voor een andere server wordt
        \\server\C$ gebruikt; met -Credential (of na Connect-DxExchange -Credential) als dat account.
    .EXAMPLE
        Clear-DxExchangeLog -ComputerName EX01 -OlderThanDays 30 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$ComputerName,

        [string[]]$Path,

        [ValidateRange(1, 3650)]
        [int]$OlderThanDays = 14,

        [string[]]$Include = @('*.log', '*.blg', '*.etl', '*.txt'),

        [System.Management.Automation.Credential()]
        [pscredential]$Credential = [pscredential]::Empty
    )

    if (-not $Path) { $Path = @(Get-DxDefaultLogPath -ComputerName $ComputerName) }

    # De share blijft gekoppeld tot na het verwijderen.
    $drives = @(Mount-DxAdminShare -ComputerName $ComputerName -Path $Path -Credential (Resolve-DxCredential -Credential $Credential))
    try {
        Remove-DxLogFileSet -ComputerName $ComputerName -Path $Path -OlderThanDays $OlderThanDays -Include $Include -Cmdlet $PSCmdlet
    }
    finally {
        Dismount-DxAdminShare -Name $drives
    }
}
