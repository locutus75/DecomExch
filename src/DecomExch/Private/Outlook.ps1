function New-DxOutlookNamespace {
    <#
    .SYNOPSIS
        Start (of koppelt aan) Outlook en geeft de MAPI-namespace terug.
    #>
    [CmdletBinding()]
    param()

    try {
        $outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
    }
    catch {
        throw ('Outlook kon niet worden gestart. Public folders exporteren vereist Outlook (desktop) met een ' +
            'profiel van een account dat de public folders kan lezen. Voer dit uit op een werkstation of ' +
            'beheerserver met Outlook, niet op de Exchange-server zelf.')
    }
    $outlook.GetNamespace('MAPI')
}

function Resolve-DxOutlookFolder {
    <#
    .SYNOPSIS
        Zoekt een map op pad (\Niveau1\Niveau2) onder een Outlook-map. Hoofdletterongevoelig.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Root,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $current = $Root
    foreach ($segment in ($Path -split '[\\/]' | Where-Object { $_ })) {
        $next = $null
        foreach ($child in $current.Folders) {
            if ($child.Name -eq $segment) { $next = $child; break }
        }
        if (-not $next) {
            throw "Public folder '$Path' niet gevonden (map '$segment' ontbreekt)."
        }
        $current = $next
    }
    $current
}
