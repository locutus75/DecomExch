function Get-DxConnectionHint {
    <#
    .SYNOPSIS
        Vertaalt een foutmelding van een mislukte remote verbinding naar een concrete oplossing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string]$Message = '',

        [string]$Server,

        [string]$Authentication = 'Kerberos',

        [bool]$HasCredential = $false
    )

    if ($Message -match '0x80090311|domain isn.t available|No authority could be contacted') {
        return ('OPLOSSING: deze computer kan geen domeincontroller van het domein van het account bereiken, ' +
            'en Kerberos heeft die nodig. Maak verbinding met het netwerk of de VPN van de organisatie en controleer ' +
            'of de computer de DNS-servers van dat domein gebruikt (test: nltest /dsgetdc:<domein>). ' +
            'Of start DecomExch op een computer in het domein, of op de Exchange-server zelf.')
    }
    if ($Message -match 'implicit credentials|not joined to a domain') {
        return ('OPLOSSING: deze computer zit niet in het domein. Geef een beheeraccount op met ' +
            '-Credential <domein>\<gebruiker>; bij opnieuw verbinden in de webinterface worden die inloggegevens hergebruikt.')
    }
    if ($Message -match 'TrustedHosts') {
        return ("OPLOSSING: voor $Authentication zonder Kerberos moet de server in TrustedHosts staan. Voer als beheerder uit: " +
            "Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$Server' -Concatenate -Force")
    }
    if ($Message -match 'Access is denied|Toegang geweigerd|401|logon failure|user name or password') {
        return ('OPLOSSING: controleer gebruikersnaam en wachtwoord, en of het account Exchange-beheerder is en remote PowerShell mag ' +
            'gebruiken (Get-User <account> | Format-List RemotePowerShellEnabled).')
    }
    if ($Message -match 'cannot find the computer|could not be resolved|name resolution|WinRM cannot complete the operation') {
        return ("OPLOSSING: $Server is niet bereikbaar. Controleer de naam (volledige naam, bijv. ex01.contoso.local), DNS en of poort 80 open staat " +
            "(Test-NetConnection $Server -Port 80).")
    }
    'Controleer de servernaam (gebruik bij Kerberos de volledige naam, bijv. ex01.contoso.local), of poort 80 bereikbaar is en of het account Exchange-beheerder is.'
}
