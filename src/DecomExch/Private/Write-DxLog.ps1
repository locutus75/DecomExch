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

    if ($script:DxLogFile) {
        try {
            Add-Content -Path $script:DxLogFile -Value $line -Encoding UTF8 -ErrorAction Stop -WhatIf:$false -Confirm:$false
        }
        catch {
            Write-Warning "Kan niet naar logbestand '$script:DxLogFile' schrijven: $($_.Exception.Message)"
        }
    }
}
