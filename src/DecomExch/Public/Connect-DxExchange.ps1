function Connect-DxExchange {
    <#
    .SYNOPSIS
        Zorgt voor een werkende Exchange-sessie.
    .DESCRIPTION
        - Met -Server wordt een remote PowerShell-sessie naar http://<server>/PowerShell geopend,
          bijvoorbeeld vanaf een beheerlaptop. Een eerdere DecomExch-sessie wordt eerst gesloten,
          zodat je ook naar een andere server kunt overstappen.
        - Zonder -Server: zijn de Exchange-cmdlets al geladen (Exchange Management Shell), dan
          gebeurt er niets; anders wordt de lokale Exchange Management Shell geladen.

        Met -Credential verbind je met een ander account dan waarmee je bent aangemeld. De
        inloggegevens worden in deze PowerShell-sessie onthouden (alleen in het geheugen) en ook
        gebruikt om logbestanden via \\server\C$ op te ruimen en bij opnieuw verbinden vanuit de
        webinterface.
    .EXAMPLE
        Connect-DxExchange -Server ex01.contoso.local
    .EXAMPLE
        Connect-DxExchange -Server ex01.contoso.local -Credential contoso\beheerder
    #>
    [CmdletBinding()]
    param(
        [string]$Server,

        [System.Management.Automation.Credential()]
        [pscredential]$Credential = [pscredential]::Empty,

        [ValidateSet('Kerberos', 'Negotiate', 'Basic')]
        [string]$Authentication = 'Kerberos'
    )

    $hasCredential = $Credential -and $Credential -ne [pscredential]::Empty
    if ($hasCredential -and -not $Server) {
        throw 'Geef -Server op: inloggegevens (-Credential) worden alleen gebruikt voor een remote verbinding.'
    }

    if ($Server) {
        if ($script:DxSession) {
            Write-DxLog -Message "Bestaande verbinding met $script:DxExchangeServer sluiten."
            Remove-DxExchangeSession -Session $script:DxSession -Module $script:DxSessionModule
            $script:DxSession = $null
            $script:DxSessionModule = $null
            $script:DxExchangeServer = $null
        }

        $params = @{
            ConfigurationName = 'Microsoft.Exchange'
            ConnectionUri     = "http://$Server/PowerShell/"
            Authentication    = $Authentication
            ErrorAction       = 'Stop'
        }
        if ($hasCredential) { $params['Credential'] = $Credential }

        # Direct onthouden, zodat opnieuw proberen (bijv. vanuit de webinterface) dezelfde
        # inloggegevens en methode gebruikt, ook als deze poging mislukt.
        $script:DxAuthentication = $Authentication
        if ($hasCredential) { $script:DxCredential = $Credential }

        $account = if ($hasCredential) { $Credential.UserName } else { "$env:USERDOMAIN\$env:USERNAME".TrimStart('\') }
        Write-DxLog -Level Action -Message "Verbinden met Exchange op $Server als $account ($Authentication) ..."
        try {
            $connection = New-DxExchangeSession -SessionParameters $params
        }
        catch {
            $detail = $_.Exception.Message
            throw ("Verbinden met $Server mislukt: $detail " + (Get-DxConnectionHint -Message $detail -Server $Server -Authentication $Authentication -HasCredential $hasCredential))
        }

        $script:DxSession = $connection.Session
        $script:DxSessionModule = $connection.Module
        $script:DxExchangeServer = $Server
    }
    elseif (Test-DxCommand -Name 'Get-ExchangeServer') {
        Write-DxLog -Level Success -Message 'Exchange-cmdlets zijn al beschikbaar.'
        return
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
    if (Test-DxCommand -Name 'Set-ADServerSettings') {
        Set-ADServerSettings -ViewEntireForest $true -ErrorAction SilentlyContinue
    }
    Write-DxLog -Level Success -Message 'Verbonden met Exchange.'
}
