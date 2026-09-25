function Export-DxMailboxToPst {
    <#
    .SYNOPSIS
        Exporteert mailboxen (en optioneel hun archief) naar PST-bestanden via Exchange-exportaanvragen.
    .DESCRIPTION
        Maakt per mailbox een New-MailboxExportRequest aan. Exchange schrijft de PST zelf weg,
        daarom moet -FilePath een UNC-share zijn (\\server\share) waarop de groep
        'Exchange Trusted Subsystem' lees- en schrijfrechten heeft.

        De uitvoerende gebruiker heeft de rol 'Mailbox Import Export' nodig:
          New-ManagementRoleAssignment -Role 'Mailbox Import Export' -User <gebruiker>
        (daarna de shell opnieuw openen).

        Bestanden: <share>\<alias>.pst en <share>\<alias>_Archief.pst.
        Volg de voortgang met Get-DxPstExportStatus; ruim afgeronde aanvragen op met
        Remove-DxStaleRequest -Type ExportRequest.
    .EXAMPLE
        Export-DxMailboxToPst -Identity jan@contoso.com, piet@contoso.com -FilePath \\fs01\pst$ -IncludeArchive
    .EXAMPLE
        Export-DxMailboxToPst -Database DB01 -FilePath \\fs01\pst$ -WhatIf
    .EXAMPLE
        Export-DxMailboxToPst -All -FilePath \\fs01\pst$ -IncludeArchive
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Identity')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Identity', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('PrimarySmtpAddress')]
        [string[]]$Identity,

        [Parameter(Mandatory, ParameterSetName = 'Database')]
        [string[]]$Database,

        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [switch]$IncludeArchive,

        [string[]]$RecipientTypeDetails = @('UserMailbox', 'SharedMailbox', 'RoomMailbox', 'EquipmentMailbox'),

        [string]$BatchName = ('DecomExch_{0}' -f (Get-Date -Format 'yyyyMMdd'))
    )

    begin {
        Assert-DxExchangeShell

        if (-not (Test-DxCommand -Name 'New-MailboxExportRequest')) {
            throw ("New-MailboxExportRequest is niet beschikbaar. Ken de rol toe met: " +
                "New-ManagementRoleAssignment -Role 'Mailbox Import Export' -User $env:USERNAME en open de shell opnieuw.")
        }
        if ($FilePath -notmatch '^\\\\[^\\]+\\[^\\]+') {
            throw "FilePath '$FilePath' moet een UNC-pad zijn (\\server\share). Exchange schrijft de PST zelf weg."
        }
        $share = $FilePath.TrimEnd('\')
        if (-not (Test-Path -LiteralPath $share)) {
            Write-DxLog -Level Warning -Message "Share '$share' is vanaf deze computer niet bereikbaar. Controleer het pad en de rechten van 'Exchange Trusted Subsystem'."
        }

        $identities = New-Object System.Collections.Generic.List[string]
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Identity') {
            foreach ($id in $Identity) { if ($id) { $identities.Add($id) } }
        }
    }

    end {
        $mailboxes = switch ($PSCmdlet.ParameterSetName) {
            'Identity' { foreach ($id in $identities) { Get-Mailbox -Identity $id -ErrorAction Continue } }
            'Database' { foreach ($db in $Database) { Get-Mailbox -Database $db -ResultSize Unlimited } }
            'All'      { Get-Mailbox -ResultSize Unlimited }
        }
        $seen = @{}
        $mailboxes = @($mailboxes | Where-Object { $_ -and -not $seen.ContainsKey("$($_.Identity)") -and ($seen["$($_.Identity)"] = $true) })
        if ($PSCmdlet.ParameterSetName -ne 'Identity') {
            $mailboxes = @($mailboxes | Where-Object { $RecipientTypeDetails -contains "$($_.RecipientTypeDetails)" })
        }
        Write-DxLog -Message "$($mailboxes.Count) mailbox(en) geselecteerd voor PST-export naar $share."

        foreach ($mbx in $mailboxes) {
            $alias = if ($mbx.PSObject.Properties['Alias'] -and $mbx.Alias) { $mbx.Alias } else { "$($mbx.PrimarySmtpAddress)" }
            $baseName = ConvertTo-DxSafeFileName -Name $alias

            $parts = @(@{ Soort = 'Primair'; Archive = $false; Suffix = '' })
            $hasArchive = $mbx.PSObject.Properties['ArchiveGuid'] -and $mbx.ArchiveGuid -and "$($mbx.ArchiveGuid)" -ne [guid]::Empty.ToString()
            if ($IncludeArchive -and $hasArchive) {
                $parts += @{ Soort = 'Archief'; Archive = $true; Suffix = '_Archief' }
            }

            foreach ($part in $parts) {
                $file = '{0}\{1}{2}.pst' -f $share, $baseName, $part.Suffix
                $requestName = 'DecomExch_{0}{1}' -f $baseName, $part.Suffix

                $result = [pscustomobject]@{
                    Mailbox    = $mbx.DisplayName
                    Soort      = $part.Soort
                    Bestand    = $file
                    Aanvraag   = $requestName
                    Status     = 'Simulatie'
                    Fout       = $null
                }

                if ($PSCmdlet.ShouldProcess("$($mbx.DisplayName) ($($part.Soort))", "Exporteren naar $file")) {
                    $params = @{
                        Mailbox     = "$($mbx.Identity)"
                        FilePath    = $file
                        Name        = $requestName
                        BatchName   = $BatchName
                        ErrorAction = 'Stop'
                        Confirm     = $false
                    }
                    if ($part.Archive) { $params['IsArchive'] = $true }

                    try {
                        New-MailboxExportRequest @params | Out-Null
                        $result.Status = 'Aangemaakt'
                        Write-DxLog -Level Action -Message "Exportaanvraag aangemaakt: $($mbx.DisplayName) ($($part.Soort)) -> $file"
                    }
                    catch {
                        $result.Status = 'Mislukt'
                        $result.Fout = $_.Exception.Message
                        Write-DxLog -Level Error -Message "Export van $($mbx.DisplayName) ($($part.Soort)) mislukt: $($_.Exception.Message)"
                    }
                }
                $result
            }
        }
    }
}
