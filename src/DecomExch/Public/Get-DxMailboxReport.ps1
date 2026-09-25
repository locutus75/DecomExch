function Get-DxMailboxReport {
    <#
    .SYNOPSIS
        Overzicht van alle mailboxen met grootte, aantal items, archief en laatste aanmelding (alleen lezen).
    .DESCRIPTION
        Handig om te onderzoeken welke mailboxen nog in gebruik zijn, welke weg kunnen of
        naar PST geexporteerd moeten worden, en hoeveel opslag een export kost.
        Een mailbox geldt als inactief als er langer dan -InactiveDays dagen niet is aangemeld
        (of nooit).
    .EXAMPLE
        Get-DxMailboxReport | Where-Object Inactief | Sort-Object GrootteMB -Descending
    .EXAMPLE
        Get-DxMailboxReport -Database DB01 | Export-DxReport -Path D:\DecomExch -Title Mailboxoverzicht
    #>
    [CmdletBinding()]
    param(
        [string[]]$Database,

        [ValidateRange(1, 3650)]
        [int]$InactiveDays = 90
    )

    Assert-DxExchangeShell

    if (-not $Database) {
        $Database = @(Get-MailboxDatabase | ForEach-Object { $_.Name })
    }

    # Statistieken per database ophalen is veel sneller dan per mailbox.
    $stats = @{}
    foreach ($db in $Database) {
        foreach ($s in @(Get-MailboxStatistics -Database $db -ErrorAction SilentlyContinue)) {
            if ($s.PSObject.Properties['DisconnectDate'] -and $s.DisconnectDate) { continue }
            $stats["$($s.MailboxGuid)"] = $s
        }
    }

    $cutoff = (Get-Date).AddDays(-$InactiveDays)
    foreach ($db in $Database) {
        foreach ($mbx in @(Get-Mailbox -Database $db -ResultSize Unlimited -ErrorAction SilentlyContinue)) {
            $s = $stats["$($mbx.ExchangeGuid)"]
            $lastLogon = if ($s -and $s.PSObject.Properties['LastLogonTime'] -and $s.LastLogonTime) { [datetime]$s.LastLogonTime } else { $null }
            $hasArchive = $mbx.PSObject.Properties['ArchiveGuid'] -and $mbx.ArchiveGuid -and "$($mbx.ArchiveGuid)" -ne [guid]::Empty.ToString()

            [pscustomobject]@{
                DisplayName          = $mbx.DisplayName
                PrimarySmtpAddress   = "$($mbx.PrimarySmtpAddress)"
                RecipientTypeDetails = "$($mbx.RecipientTypeDetails)"
                Database             = $db
                GrootteMB            = if ($s) { ConvertTo-DxMegabyte -Size $s.TotalItemSize } else { $null }
                Items                = if ($s) { $s.ItemCount } else { $null }
                Archief              = [bool]$hasArchive
                LaatsteAanmelding    = $lastLogon
                Inactief             = ($null -eq $lastLogon) -or ($lastLogon -lt $cutoff)
                WhenCreated          = $mbx.WhenCreated
            }
        }
    }
}
