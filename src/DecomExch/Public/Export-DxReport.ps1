function Export-DxReport {
    <#
    .SYNOPSIS
        Schrijft een HTML-rapport (en CSV per onderdeel) van een inventarisatie of controle.
    .DESCRIPTION
        Invoer is een hashtable met onderdelen (uitvoer van Get-DxInventory) of een lijst
        objecten (bijv. uitvoer van Test-DxDecomReadiness). Geeft het pad van het HTML-bestand terug.
    .EXAMPLE
        Get-DxInventory | Export-DxReport -Path C:\DecomExch\Rapport
    .EXAMPLE
        Test-DxDecomReadiness -Server EX01 | Export-DxReport -Path C:\DecomExch\Rapport -Title 'Uitfaseringscontrole EX01'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Title = 'Exchange inventarisatie',

        [switch]$NoCsv
    )

    begin {
        $items = New-Object System.Collections.Generic.List[object]
    }

    process {
        if ($null -ne $InputObject) { $items.Add($InputObject) }
    }

    end {
        if ($items.Count -eq 1 -and $items[0] -is [System.Collections.IDictionary]) {
            $sections = $items[0]
        }
        else {
            $sections = [ordered]@{ 'Resultaat' = $items.ToArray() }
        }

        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force -WhatIf:$false -Confirm:$false | Out-Null
        }
        $Path = (Resolve-Path -Path $Path).ProviderPath

        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $safeTitle = ($Title -replace '[^\w\-]+', '_').Trim('_')
        $htmlFile = Join-Path -Path $Path -ChildPath "${safeTitle}_$stamp.html"
        $enc = { param($v) [System.Net.WebUtility]::HtmlEncode([string]$v) }

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine('<!DOCTYPE html><html lang="nl"><head><meta charset="utf-8">')
        [void]$sb.AppendLine("<title>$(& $enc $Title)</title>")
        [void]$sb.AppendLine(@'
<style>
 body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; color: #1b1b1b; background: #fff; }
 h1 { font-size: 22px; } h2 { font-size: 17px; margin-top: 28px; border-bottom: 1px solid #ccc; padding-bottom: 4px; }
 table { border-collapse: collapse; font-size: 13px; margin-top: 8px; }
 th, td { border: 1px solid #d0d0d0; padding: 4px 8px; text-align: left; vertical-align: top; }
 th { background: #f0f0f0; }
 tr.Blokkerend td { background: #fde2e1; } tr.Waarschuwing td { background: #fff4ce; } tr.OK td { background: #e6f4ea; }
 .meta, .leeg { color: #666; font-size: 13px; }
 nav a { margin-right: 12px; font-size: 13px; }
</style></head><body>
'@)
        [void]$sb.AppendLine("<h1>$(& $enc $Title)</h1>")
        [void]$sb.AppendLine(("<p class=""meta"">Gegenereerd op {0} door {1} op {2}</p>" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), (& $enc $env:USERNAME), (& $enc $env:COMPUTERNAME)))

        $index = 0
        [void]$sb.Append('<nav>')
        foreach ($key in $sections.Keys) { $index++; [void]$sb.Append("<a href=""#s$index"">$(& $enc $key)</a>") }
        [void]$sb.AppendLine('</nav>')

        $index = 0
        foreach ($key in $sections.Keys) {
            $index++
            $rows = @($sections[$key] | Where-Object { $null -ne $_ })
            [void]$sb.AppendLine("<h2 id=""s$index"">$(& $enc $key) ($($rows.Count))</h2>")

            if ($rows.Count -eq 0) {
                [void]$sb.AppendLine('<p class="leeg">Geen gegevens.</p>')
                continue
            }

            $columns = @($rows[0].PSObject.Properties | Where-Object { $_.MemberType -match 'Property' } | ForEach-Object { $_.Name })
            [void]$sb.Append('<table><tr>')
            foreach ($c in $columns) { [void]$sb.Append("<th>$(& $enc $c)</th>") }
            [void]$sb.AppendLine('</tr>')
            foreach ($row in $rows) {
                $class = if ($row.PSObject.Properties['Status']) { " class=""$(& $enc $row.Status)""" } else { '' }
                [void]$sb.Append("<tr$class>")
                foreach ($c in $columns) {
                    $value = if ($row.PSObject.Properties[$c]) { $row.$c } else { $null }
                    if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { $value = @($value) -join '; ' }
                    [void]$sb.Append("<td>$(& $enc $value)</td>")
                }
                [void]$sb.AppendLine('</tr>')
            }
            [void]$sb.AppendLine('</table>')

            if (-not $NoCsv) {
                $csvName = '{0}_{1}_{2}.csv' -f $safeTitle, (($key -replace '[^\w\-]+', '_').Trim('_')), $stamp
                $rows | Export-Csv -Path (Join-Path $Path $csvName) -NoTypeInformation -Encoding UTF8 -Delimiter ';' -WhatIf:$false -Confirm:$false
            }
        }

        [void]$sb.AppendLine('</body></html>')
        [System.IO.File]::WriteAllText($htmlFile, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))
        Write-DxLog -Level Success -Message "Rapport opgeslagen: $htmlFile"
        $htmlFile
    }
}
