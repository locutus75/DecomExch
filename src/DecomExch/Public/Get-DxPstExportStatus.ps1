function Get-DxPstExportStatus {
    <#
    .SYNOPSIS
        Toont de voortgang van PST-exportaanvragen.
    .DESCRIPTION
        Met -Wait wordt gewacht (met voortgangsbalk) tot alle aanvragen klaar of mislukt zijn.
    .EXAMPLE
        Get-DxPstExportStatus | Format-Table -AutoSize
    .EXAMPLE
        Get-DxPstExportStatus -BatchName DecomExch_20260925 -Wait
    #>
    [CmdletBinding()]
    param(
        [string]$BatchName,

        [switch]$Wait,

        [ValidateRange(5, 3600)]
        [int]$IntervalSeconds = 30
    )

    Assert-DxExchangeShell

    $busyStatuses = @('Queued', 'InProgress', 'CompletionInProgress', 'AutoSuspended', 'Synced')

    while ($true) {
        $params = @{ ErrorAction = 'SilentlyContinue' }
        if ($BatchName) { $params['BatchName'] = $BatchName }

        $rows = @(foreach ($request in @(Get-MailboxExportRequest @params)) {
            $s = Get-MailboxExportRequestStatistics -Identity $request.Identity -ErrorAction SilentlyContinue
            if (-not $s) { continue }
            [pscustomobject]@{
                Aanvraag      = $request.Name
                Mailbox       = if ($s.PSObject.Properties['SourceAlias']) { $s.SourceAlias } else { "$($request.Mailbox)" }
                Status        = "$($s.Status)"
                Procent       = $s.PercentComplete
                Overgezet     = "$($s.BytesTransferred)"
                Bestand       = $s.FilePath
                Batch         = $request.BatchName
                Melding       = if ($s.PSObject.Properties['Message']) { "$($s.Message)" } else { '' }
            }
        })

        $busy = @($rows | Where-Object { $busyStatuses -contains $_.Status })
        if (-not $Wait -or $busy.Count -eq 0) {
            if ($Wait) { Write-Progress -Activity 'PST-export' -Completed }
            return $rows
        }

        $avg = [int](($rows | Measure-Object -Property Procent -Average).Average)
        Write-Progress -Activity 'PST-export' -Status ("{0} van {1} nog bezig ({2}%)" -f $busy.Count, $rows.Count, $avg) -PercentComplete $avg
        Start-Sleep -Seconds $IntervalSeconds
    }
}
