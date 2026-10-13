function Get-DxSum {
    <#
    .SYNOPSIS
        Telt een numerieke eigenschap op; 0 bij een lege lijst of ontbrekende waarden.
    .NOTES
        Measure-Object geeft in Windows PowerShell 5.1 bij een lege invoer geen Sum-eigenschap,
        wat onder StrictMode een fout geeft ("The property 'Sum' cannot be found").
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [Parameter(Mandatory)]
        [string]$Property
    )

    [double]$total = 0
    foreach ($item in @($InputObject)) {
        if ($null -eq $item) { continue }
        $value = if ($item -is [System.Collections.IDictionary]) { $item[$Property] } else { $p = $item.PSObject.Properties[$Property]; if ($p) { $p.Value } else { $null } }
        $number = 0.0
        if ($null -ne $value -and [double]::TryParse("$value", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { $total += $number }
    }
    $total
}
