function New-DxExchangeSession {
    <#
    .SYNOPSIS
        Opent een remote PowerShell-sessie naar Exchange en importeert de cmdlets globaal.
        Geeft de sessie en de geimporteerde module terug.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SessionParameters
    )

    $session = New-PSSession @SessionParameters
    $module = Import-Module (Import-PSSession -Session $session -DisableNameChecking -AllowClobber) -Global -DisableNameChecking -PassThru
    [pscustomobject]@{ Session = $session; Module = $module }
}

function Remove-DxExchangeSession {
    <#
    .SYNOPSIS
        Sluit een eerder geopende remote Exchange-sessie en verwijdert de geimporteerde cmdlets.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Session,

        [AllowNull()]
        [object]$Module
    )

    if ($Module) { Remove-Module -ModuleInfo $Module -Force -ErrorAction SilentlyContinue }
    if ($Session) { Remove-PSSession -Session $Session -ErrorAction SilentlyContinue }
}
