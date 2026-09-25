function ConvertTo-DxJsonSafe {
    <#
    .SYNOPSIS
        Zet objecten om naar eenvoudige hashtables die in Windows PowerShell 5.1 en 7
        identiek als JSON worden geserialiseerd (datums als tekst, lijsten samengevoegd).
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    process {
        if ($null -eq $InputObject) { return }

        if ($InputObject -is [System.Collections.IDictionary]) {
            $out = [ordered]@{}
            foreach ($key in $InputObject.Keys) { $out["$key"] = ConvertTo-DxJsonValue -Value $InputObject[$key] }
            return $out
        }

        $out = [ordered]@{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            if ($prop.MemberType -notmatch 'Property') { continue }
            $out[$prop.Name] = ConvertTo-DxJsonValue -Value $prop.Value
        }
        $out
    }
}

function ConvertTo-DxJsonValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm') }
    if ($Value -is [bool] -or $Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return $Value }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.Collections.IEnumerable]) { return (@($Value | ForEach-Object { "$_" }) -join '; ') }
    "$Value"
}
