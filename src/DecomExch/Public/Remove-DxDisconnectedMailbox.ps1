function Remove-DxDisconnectedMailbox {
    <#
    .SYNOPSIS
        Verwijdert losgekoppelde (disabled of soft-deleted) mailboxen DEFINITIEF uit de databases.
    .DESCRIPTION
        Losgekoppelde mailboxen ontstaan na Disable-Mailbox/Remove-Mailbox (Disabled) of na een
        mailboxverplaatsing (SoftDeleted). Ze nemen ruimte in totdat de retentie verloopt.
        LET OP: verwijderde mailboxen zijn niet meer terug te halen, behalve uit een back-up.
    .EXAMPLE
        Remove-DxDisconnectedMailbox -OlderThanDays 30 -WhatIf
    .EXAMPLE
        Remove-DxDisconnectedMailbox -Database DB01 -State SoftDeleted
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string[]]$Database,

        [ValidateRange(0, 3650)]
        [int]$OlderThanDays = 0,

        [ValidateSet('Disabled', 'SoftDeleted')]
        [string[]]$State = @('Disabled', 'SoftDeleted')
    )

    Assert-DxExchangeShell

    if (-not $Database) {
        $Database = @(Get-MailboxDatabase | ForEach-Object { $_.Name })
    }
    $cutoff = (Get-Date).AddDays(-$OlderThanDays)

    foreach ($db in $Database) {
        $disconnected = @(Get-MailboxStatistics -Database $db -ErrorAction SilentlyContinue | Where-Object {
            $_.DisconnectDate -and
            $_.DisconnectDate -lt $cutoff -and
            ($State -contains "$($_.DisconnectReason)")
        })
        Write-DxLog -Message "$($disconnected.Count) losgekoppelde mailbox(en) gevonden in $db."

        foreach ($mbx in $disconnected) {
            $result = [pscustomobject]@{
                Database        = $db
                DisplayName     = $mbx.DisplayName
                MailboxGuid     = $mbx.MailboxGuid
                DisconnectDate  = $mbx.DisconnectDate
                Reden           = "$($mbx.DisconnectReason)"
                Verwijderd      = $false
                Fout            = $null
            }

            $target = "{0} ({1}, {2}, losgekoppeld {3:yyyy-MM-dd})" -f $mbx.DisplayName, $db, $mbx.DisconnectReason, $mbx.DisconnectDate
            if ($PSCmdlet.ShouldProcess($target, 'Definitief verwijderen')) {
                try {
                    Remove-StoreMailbox -Database $db -Identity $mbx.MailboxGuid -MailboxState "$($mbx.DisconnectReason)" -Confirm:$false -ErrorAction Stop
                    $result.Verwijderd = $true
                    Write-DxLog -Level Action -Message "Definitief verwijderd: $target"
                }
                catch {
                    $result.Fout = $_.Exception.Message
                    Write-DxLog -Level Error -Message "Verwijderen van $target mislukt: $($_.Exception.Message)"
                }
            }
            $result
        }
    }
}
