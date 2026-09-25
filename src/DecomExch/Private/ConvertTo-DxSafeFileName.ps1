function ConvertTo-DxSafeFileName {
    <#
    .SYNOPSIS
        Maakt van een naam (alias, e-mailadres, mapnaam) een veilige bestandsnaam.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $safe = ($Name -replace '[\\/:*?"<>|\s@]+', '_').Trim('_. ')
    if (-not $safe) { $safe = 'export' }
    if ($safe.Length -gt 100) { $safe = $safe.Substring(0, 100) }
    $safe
}
