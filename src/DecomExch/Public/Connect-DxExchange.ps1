function Connect-DxExchange {
    <#
    .SYNOPSIS
        Zorgt voor een werkende Exchange-sessie.
    .DESCRIPTION
        - Zijn de Exchange-cmdlets al geladen (Exchange Management Shell), dan gebeurt er niets.
        - Met -Server wordt een remote PowerShell-sessie naar http://<server>/PowerShell geopend.
        - Zonder -Server wordt geprobeerd de lokale Exchange Management Shell te laden.
    .EXAMPLE
        Connect-DxExchange -Server ex01.contoso.local
    #>
    [CmdletBinding()]
    param(
        [string]$Server,

        [pscredential]$Credential,

        [ValidateSet('Kerberos', 'Negotiate', 'Basic')]
        [string]$Authentication = 'Kerberos'
    )

    if (Test-DxCommand -Name 'Get-ExchangeServer') {
        Write-DxLog -Level Success -Message 'Exchange-cmdlets zijn al beschikbaar.'
        return
    }

    if ($Server) {
        $params = @{
            ConfigurationName = 'Microsoft.Exchange'
            ConnectionUri     = "http://$Server/PowerShell/"
            Authentication    = $Authentication
            ErrorAction       = 'Stop'
        }
        if ($Credential) { $params['Credential'] = $Credential }

        Write-DxLog -Level Action -Message "Verbinden met Exchange op $Server ..."
        $session = New-PSSession @params
        Import-Module (Import-PSSession -Session $session -DisableNameChecking -AllowClobber) -Global -DisableNameChecking | Out-Null
    }
    else {
        $remoteExchange = if ($env:ExchangeInstallPath) { Join-Path $env:ExchangeInstallPath 'bin\RemoteExchange.ps1' }
        if (-not $remoteExchange -or -not (Test-Path -Path $remoteExchange)) {
            throw 'Exchange Management Shell niet gevonden op deze computer. Geef -Server op om remote te verbinden.'
        }

        Write-DxLog -Level Action -Message 'Lokale Exchange Management Shell laden ...'
        . $remoteExchange
        Connect-ExchangeServer -auto -ClientApplication:ManagementShell
    }

    Assert-DxExchangeShell
    Set-ADServerSettings -ViewEntireForest $true -ErrorAction SilentlyContinue
    Write-DxLog -Level Success -Message 'Verbonden met Exchange.'
}
