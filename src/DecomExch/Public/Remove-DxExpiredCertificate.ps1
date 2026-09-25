function Remove-DxExpiredCertificate {
    <#
    .SYNOPSIS
        Verwijdert verlopen certificaten van Exchange-servers.
    .DESCRIPTION
        Certificaten die nog aan een dienst (IIS, SMTP, IMAP, POP) gekoppeld zijn worden
        standaard overgeslagen; gebruik -IncludeAssigned om die ook te verwijderen.
        Het OAuth-certificaat (Get-AuthConfig) wordt nooit verwijderd.
    .EXAMPLE
        Remove-DxExpiredCertificate -Server EX01 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string[]]$Server,

        [switch]$IncludeAssigned
    )

    Assert-DxExchangeShell

    if (-not $Server) {
        $Server = @(Get-ExchangeServer | Where-Object { "$($_.ServerRole)" -notmatch 'Edge' } | ForEach-Object { $_.Name })
    }

    $protected = @()
    $authConfig = Invoke-DxSafe -Section 'AuthConfig' -Action { Get-AuthConfig -ErrorAction Stop }
    if ($authConfig) {
        $protected = @($authConfig.CurrentCertificateThumbprint, $authConfig.PreviousCertificateThumbprint, $authConfig.NextCertificateThumbprint) |
            Where-Object { $_ } | ForEach-Object { "$_".ToUpper() }
    }

    $now = Get-Date
    foreach ($srv in $Server) {
        $expired = @(Get-ExchangeCertificate -Server $srv -ErrorAction SilentlyContinue | Where-Object { $_.NotAfter -lt $now })
        Write-DxLog -Message "$($expired.Count) verlopen certificaat/certificaten op $srv."

        foreach ($cert in $expired) {
            $services = "$($cert.Services)"
            $result = [pscustomobject]@{
                Server     = $srv
                Thumbprint = $cert.Thumbprint
                Subject    = $cert.Subject
                NotAfter   = $cert.NotAfter
                Services   = $services
                Verwijderd = $false
                Opmerking  = $null
            }

            if ($protected -contains "$($cert.Thumbprint)".ToUpper()) {
                $result.Opmerking = 'Overgeslagen: OAuth-certificaat (Get-AuthConfig). Vernieuw dit certificaat in plaats van het te verwijderen.'
            }
            elseif ($services -and $services -ne 'None' -and -not $IncludeAssigned) {
                $result.Opmerking = "Overgeslagen: nog gekoppeld aan $services. Gebruik -IncludeAssigned om toch te verwijderen."
            }
            elseif ($PSCmdlet.ShouldProcess("$srv - $($cert.Subject) ($($cert.Thumbprint), verlopen $($cert.NotAfter))", 'Certificaat verwijderen')) {
                try {
                    Remove-ExchangeCertificate -Server $srv -Thumbprint $cert.Thumbprint -Confirm:$false -ErrorAction Stop
                    $result.Verwijderd = $true
                    Write-DxLog -Level Action -Message "Certificaat verwijderd: $srv $($cert.Thumbprint)"
                }
                catch {
                    $result.Opmerking = $_.Exception.Message
                    Write-DxLog -Level Error -Message "Verwijderen certificaat $($cert.Thumbprint) op $srv mislukt: $($_.Exception.Message)"
                }
            }
            $result
        }
    }
}
