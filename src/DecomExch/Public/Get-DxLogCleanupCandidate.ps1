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
    .EXAMPLE
        Get-DxLogCleanupCandidate -ComputerName EX01 -OlderThanDays 30 | Measure-Object Length -Sum
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [string]$ComputerName,

        [string[]]$Path,

        [ValidateRange(1, 3650)]
        [int]$OlderThanDays = 14,

        [string[]]$Include = @('*.log', '*.blg', '*.etl', '*.txt')
    )

    if (-not $Path) {
        $installPath = Get-DxExchangeInstallPath -ComputerName $ComputerName
        $Path = @(
            Join-Path $installPath 'Logging'
            Join-Path $installPath 'Bin\Search\Ceres\Diagnostics\ETLTraces'
            Join-Path $installPath 'Bin\Search\Ceres\Diagnostics\Logs'
            'C:\inetpub\logs\LogFiles'
        )
    }

    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    # Namen van ESE-transactielogs/checkpoints: E00.log, E0000001A2B.log, E00tmp.log, E00res00001.jrs, E00.chk
    $transactionLogPattern = '^E[0-9A-F]{2}([0-9A-F]{8,}|tmp|res\d+)?\.(log|jrs|chk)$'

    foreach ($p in $Path) {
        $target = ConvertTo-DxUncPath -Path $p -ComputerName $ComputerName

        if ($target -match '[\\/]Mailbox([\\/]|$)') {
            Write-DxLog -Level Warning -Message "Pad '$target' lijkt een databasemap te zijn en wordt overgeslagen."
            continue
        }
        if (-not (Test-Path -LiteralPath $target)) {
            Write-DxLog -Message "Pad '$target' bestaat niet; overgeslagen."
            continue
        }

        Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $file = $_
                ($file.LastWriteTime -lt $cutoff) -and
                ($file.Name -notmatch $transactionLogPattern) -and
                (@($Include | Where-Object { $file.Name -like $_ }).Count -gt 0)
            }
    }
}
