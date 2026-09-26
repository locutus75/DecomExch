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

    # Domeinnaam voor de tips afleiden uit de volledige servernaam (ex01.contoso.local -> contoso.local).
    $domain = if ($Server -match '^[^.]+\.(.+\..+)$') { $Matches[1] } else { '<domein>' }
    $kerberosRoute = ("Werk vanaf een computer in het domein (of op de Exchange-server zelf), of zorg dat deze computer een " +
        "domeincontroller kan bereiken: test met nltest /dsgetdc:$domain en Resolve-DnsName -Type SRV _kerberos._tcp.$domain " +
        '(bijv. via de VPN of DNS van de organisatie).')

    if ($Message -match '0x80090311|domain isn.t available|No authority could be contacted') {
        return ('OPLOSSING: deze computer kan geen domeincontroller van het domein van het account bereiken, ' +
            "en Kerberos heeft die nodig. $kerberosRoute")
    }
    if ($Message -match 'implicit credentials|not joined to a domain') {
        return ('OPLOSSING: deze computer zit niet in het domein. Geef een beheeraccount op met ' +
            '-Credential <domein>\<gebruiker>; bij opnieuw verbinden in de webinterface worden die inloggegevens hergebruikt.')
    }
    if ($Message -match 'bad request|\(400\)') {
        if ($Authentication -ne 'Kerberos') {
            return ("OPLOSSING: Exchange accepteert voor remote PowerShell standaard alleen Kerberos; $Authentication wordt " +
                "geweigerd (HTTP 400). Verbind met Kerberos. $kerberosRoute")
        }
        return ('OPLOSSING: de server weigerde het verzoek (HTTP 400). Gebruik de volledige servernaam zoals die in DNS ' +
            'en Active Directory staat (geen IP-adres of alias), zodat Kerberos het juiste serviceaccount (SPN) vindt.')
    }
    if ($Message -match 'TrustedHosts') {
        return ('OPLOSSING: zonder Kerberos moet de server in TrustedHosts staan. Controleer eerst de huidige waarde met ' +
            "Get-Item WSMan:\localhost\Client\TrustedHosts. Staat daar '*', dan worden alle servers al vertrouwd. Is de waarde leeg, voer dan " +
            "als beheerder uit: Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$Server' -Force; staan er al andere servers, " +
            'voeg dan -Concatenate toe. Let op: Exchange accepteert voor remote PowerShell standaard alleen Kerberos, dus ' +
            "$Authentication kan daarna alsnog worden geweigerd.")
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
