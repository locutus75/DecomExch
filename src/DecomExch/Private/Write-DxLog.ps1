function Write-DxLog {
    <#
    .SYNOPSIS
        Schrijft een regel naar het scherm en (indien ingesteld) naar het logbestand.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Action')]
        [string]$Level = 'Info'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpper(), $Message

    switch ($Level) {
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
        'Action'  { Write-Host $Message -ForegroundColor Cyan }
        default   { Write-Verbose $Message }
    }

    # Laatste regels bewaren voor de webinterface (logboek).
    if ($null -eq $script:DxLogBuffer) { $script:DxLogBuffer = New-Object System.Collections.Generic.List[object] }
    $script:DxLogBuffer.Add([pscustomobject]@{ Tijd = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Niveau = $Level; Bericht = $Message })
    if ($script:DxLogBuffer.Count -gt 500) { $script:DxLogBuffer.RemoveRange(0, $script:DxLogBuffer.Count - 500) }

    if ($script:DxLogFile) {
        try {
            Add-Content -Path $script:DxLogFile -Value $line -Encoding UTF8 -ErrorAction Stop -WhatIf:$false -Confirm:$false
        }
        catch {
            Write-Warning "Kan niet naar logbestand '$script:DxLogFile' schrijven: $($_.Exception.Message)"
        }
    }
}
