function Get-DxPublicFolderReport {
    <#
    .SYNOPSIS
        Overzicht van public folders met aantal items, grootte en laatste wijziging (alleen lezen).
    .EXAMPLE
        Get-DxPublicFolderReport | Sort-Object GrootteMB -Descending | Select-Object -First 20
    #>
    [CmdletBinding()]
    param()

    Assert-DxExchangeShell

    $mailEnabled = @{}
    foreach ($mpf in @(Invoke-DxSafe -Section 'Mail-enabled public folders' -Action { Get-MailPublicFolder -ResultSize Unlimited -ErrorAction Stop })) {
        if ($mpf.PSObject.Properties['EntryId'] -and $mpf.EntryId) { $mailEnabled["$($mpf.EntryId)"] = "$($mpf.PrimarySmtpAddress)" }
    }

    foreach ($pf in @(Get-PublicFolderStatistics -ResultSize Unlimited -ErrorAction Stop)) {
        $path = if ($pf.PSObject.Properties['FolderPath'] -and $pf.FolderPath) { '\' + (@($pf.FolderPath) -join '\') } else { "$($pf.Name)" }
        $entryId = if ($pf.PSObject.Properties['EntryId']) { "$($pf.EntryId)" } else { '' }

        [pscustomobject]@{
            Map                  = $path
            Items                = $pf.ItemCount
            GrootteMB            = ConvertTo-DxMegabyte -Size $pf.TotalItemSize
            LaatsteWijziging     = $pf.LastModificationTime
            MailEnabled          = if ($entryId -and $mailEnabled.ContainsKey($entryId)) { $mailEnabled[$entryId] } else { '' }
            ContentMailbox       = if ($pf.PSObject.Properties['ContentMailboxName']) { "$($pf.ContentMailboxName)" } else { '' }
        }
    }
}
