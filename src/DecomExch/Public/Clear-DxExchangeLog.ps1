function Clear-DxExchangeLog {
    <#
    .SYNOPSIS
        Verwijdert oude diagnostische Exchange- en IIS-logbestanden.
    .DESCRIPTION
        Gebruikt Get-DxLogCleanupCandidate om bestanden te selecteren en vraagt per map
        om bevestiging. Gebruik -WhatIf om alleen te zien wat er zou gebeuren.
        Bestanden die in gebruik zijn worden overgeslagen.
    .EXAMPLE
        Clear-DxExchangeLog -ComputerName EX01 -OlderThanDays 30 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string]$ComputerName,

        [string[]]$Path,

        [ValidateRange(1, 3650)]
        [int]$OlderThanDays = 14,

        [string[]]$Include = @('*.log', '*.blg', '*.etl', '*.txt')
    )

    $params = @{ OlderThanDays = $OlderThanDays; Include = $Include }
    if ($ComputerName) { $params['ComputerName'] = $ComputerName }
    if ($Path) { $params['Path'] = $Path }

    $candidates = @(Get-DxLogCleanupCandidate @params)
    if ($candidates.Count -eq 0) {
        Write-DxLog -Level Success -Message "Geen logbestanden ouder dan $OlderThanDays dagen gevonden."
        return
    }

    $removed = 0
    $failed = 0
    [long]$bytes = 0

    foreach ($group in ($candidates | Group-Object -Property DirectoryName)) {
        $size = ($group.Group | Measure-Object -Property Length -Sum).Sum
        $description = '{0} bestand(en), {1:N1} MB' -f $group.Count, ($size / 1MB)

        if (-not $PSCmdlet.ShouldProcess($group.Name, "Verwijderen: $description")) { continue }

        foreach ($file in $group.Group) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false
                $removed++
                $bytes += $file.Length
            }
            catch {
                $failed++
                Write-DxLog -Message "Niet verwijderd (in gebruik?): $($file.FullName) - $($_.Exception.Message)"
            }
        }
        Write-DxLog -Level Action -Message "Opgeruimd in $($group.Name): $description"
    }

    $summary = [pscustomobject]@{
        Gevonden       = $candidates.Count
        Verwijderd     = $removed
        Mislukt        = $failed
        VrijgemaaktMB  = [math]::Round($bytes / 1MB, 1)
    }
    Write-DxLog -Level Success -Message ("Logopruiming: {0} verwijderd, {1} mislukt, {2} MB vrijgemaakt." -f $removed, $failed, $summary.VrijgemaaktMB)
    $summary
}
