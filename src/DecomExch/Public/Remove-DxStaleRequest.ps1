function Remove-DxStaleRequest {
    <#
    .SYNOPSIS
        Ruimt afgeronde verplaats-, export-, import- en herstelaanvragen en migratiebatches op.
    .DESCRIPTION
        Standaard worden alleen afgeronde aanvragen (Completed/CompletedWithWarning) verwijderd.
        Met -IncludeFailed worden ook mislukte aanvragen verwijderd.
        Lopende aanvragen worden nooit aangeraakt.
    .EXAMPLE
        Remove-DxStaleRequest -WhatIf
    .EXAMPLE
        Remove-DxStaleRequest -Type MoveRequest, MigrationBatch -IncludeFailed
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [ValidateSet('MoveRequest', 'MigrationBatch', 'ExportRequest', 'ImportRequest', 'RestoreRequest')]
        [string[]]$Type = @('MoveRequest', 'MigrationBatch', 'ExportRequest', 'ImportRequest', 'RestoreRequest'),

        [switch]$IncludeFailed
    )

    Assert-DxExchangeShell

    $statuses = @('Completed', 'CompletedWithWarning', 'CompletedWithWarnings')
    if ($IncludeFailed) { $statuses += @('Failed', 'CompletedWithErrors') }

    $kinds = @{
        MoveRequest    = @{ Get = 'Get-MoveRequest';               Remove = 'Remove-MoveRequest';               Label = 'Verplaatsaanvraag' }
        MigrationBatch = @{ Get = 'Get-MigrationBatch';            Remove = 'Remove-MigrationBatch';            Label = 'Migratiebatch' }
        ExportRequest  = @{ Get = 'Get-MailboxExportRequest';      Remove = 'Remove-MailboxExportRequest';      Label = 'Exportaanvraag' }
        ImportRequest  = @{ Get = 'Get-MailboxImportRequest';      Remove = 'Remove-MailboxImportRequest';      Label = 'Importaanvraag' }
        RestoreRequest = @{ Get = 'Get-MailboxRestoreRequest';     Remove = 'Remove-MailboxRestoreRequest';     Label = 'Herstelaanvraag' }
    }

    foreach ($t in $Type) {
        $kind = $kinds[$t]
        if (-not (Test-DxCommand -Name $kind.Get)) {
            Write-DxLog -Message "$($kind.Get) is niet beschikbaar; $t overgeslagen."
            continue
        }

        $items = @(& $kind.Get -ErrorAction SilentlyContinue | Where-Object { $statuses -contains "$($_.Status)" })
        Write-DxLog -Message "$($items.Count) op te ruimen $t(s) gevonden."

        foreach ($item in $items) {
            $label = if ($item.PSObject.Properties['DisplayName'] -and $item.DisplayName) { $item.DisplayName }
                     elseif ($item.PSObject.Properties['Name'] -and $item.Name) { $item.Name }
                     else { "$($item.Identity)" }

            $result = [pscustomobject]@{
                Soort       = $kind.Label
                Naam        = $label
                Status      = "$($item.Status)"
                Verwijderd  = $false
                Fout        = $null
            }

            if ($PSCmdlet.ShouldProcess("$($kind.Label) '$label' ($($item.Status))", 'Verwijderen')) {
                try {
                    & $kind.Remove -Identity $item.Identity -Confirm:$false -ErrorAction Stop
                    $result.Verwijderd = $true
                    Write-DxLog -Level Action -Message "Verwijderd: $($kind.Label) '$label'"
                }
                catch {
                    $result.Fout = $_.Exception.Message
                    Write-DxLog -Level Error -Message "Verwijderen van $($kind.Label) '$label' mislukt: $($_.Exception.Message)"
                }
            }
            $result
        }
    }
}
