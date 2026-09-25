function ConvertTo-DxMegabyte {
    <#
    .SYNOPSIS
        Zet een Exchange-grootte om naar megabytes.
    .DESCRIPTION
        Lokaal (Exchange Management Shell) is een grootte een ByteQuantifiedSize, via remote
        PowerShell een tekst als "1.234 GB (1,324,997,632 bytes)". Beide worden ondersteund
        via het aantal bytes tussen haakjes. Onbekende waarden leveren $null op.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Size
    )

    if ($null -eq $Size) { return $null }
    if ($Size -is [int] -or $Size -is [long] -or $Size -is [double]) { return [math]::Round($Size / 1MB, 1) }

    $text = "$Size"
    if ($text -match '\(([\d,.\s]+) bytes\)') {
        $bytes = [double]($Matches[1] -replace '[^\d]', '')
        return [math]::Round($bytes / 1MB, 1)
    }
    if ($text -match '^0( B|$)') { return 0 }
    $null
}
