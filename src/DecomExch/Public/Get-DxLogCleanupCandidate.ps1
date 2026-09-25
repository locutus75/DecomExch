function Get-DxLogCleanupCandidate {
    <#
    .SYNOPSIS
        Zoekt oude diagnostische logbestanden van Exchange en IIS (alleen lezen).
    .DESCRIPTION
        Standaard worden deze mappen doorzocht:
          <Exchange>\Logging
          <Exchange>\Bin\Search\Ceres\Diagnostics\ETLTraces
          <Exchange>\Bin\Search\Ceres\Diagnostics\Logs
          C:\inetpub\logs\LogFiles
        Transactielogs van databases (E00*.log, *.jrs, *.chk) worden altijd overgeslagen,
        en mappen met mailboxdatabases (\Mailbox\) worden geweigerd.

        Voor een andere server wordt de administratieve share gebruikt (\\server\C$). Met
        -Credential (of na Connect-DxExchange -Credential) wordt die share als dat account gekoppeld.
    .EXAMPLE
        Get-DxLogCleanupCandidate -ComputerName EX01 -OlderThanDays 30 | Measure-Object Length -Sum
    .EXAMPLE
        Get-DxLogCleanupCandidate -ComputerName ex01.contoso.local -Credential contoso\beheerder
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
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

    $drives = @(Mount-DxAdminShare -ComputerName $ComputerName -Path $Path -Credential (Resolve-DxCredential -Credential $Credential))
    try {
        Find-DxLogFile -ComputerName $ComputerName -Path $Path -OlderThanDays $OlderThanDays -Include $Include
    }
    finally {
        Dismount-DxAdminShare -Name $drives
    }
}
