function Get-DxRelayUsage {
    <#
    .SYNOPSIS
        Toont wie de Exchange-server(s) nog gebruikt als SMTP-server of relay: hoe vaak, door wie en hoe.
    .DESCRIPTION
        Analyseert het binnenkomende SMTP-verkeer en vat het samen per client (IP-adres):
        naam (EHLO/DNS), soort client, aantal berichten en sessies, afzenders, ontvangers
        (intern/extern), aanmelding (anoniem of met welk account), TLS, connector, poort en de
        eerste en laatste keer.

        Bronnen (-Source):
          Auto            SMTP-protocollogs als die er zijn, anders message tracking (standaard).
          ProtocolLog     SMTP Receive-protocollogs (RECV*.log) van de servers. Het meest
                          gedetailleerd, maar protocol logging moet aanstaan op de receive connector.
                          Remote via \\server\C$ (met -Credential of die van Connect-DxExchange).
          MessageTracking Get-MessageTrackingLog. Staat standaard aan en werkt via remote PowerShell,
                          maar bevat geen aanmelding, TLS of EHLO-naam.
          Path            Een map met (gekopieerde) RECV*.log-bestanden; hiervoor is geen
                          Exchange-verbinding nodig. Geef dan -Domain op voor intern/extern.

        Verkeer tussen Exchange-servers wordt standaard niet meegeteld (-IncludeExchangeServers).
    .EXAMPLE
        Get-DxRelayUsage -Days 14 | Format-Table Client, Naam, Type, Berichten, Aanmelding, TLS, Afzenders
    .EXAMPLE
        Get-DxRelayUsage -Source Path -Path D:\Logs\SmtpReceive -Domain contoso.nl, contoso.com -Days 0
    .EXAMPLE
        Get-DxRelayUsage -Report | Select-Object -ExpandProperty Opmerkingen
    #>
    [CmdletBinding()]
    param(
        [string[]]$Server,

        # Aantal dagen terug; 0 = alles wat in de logs staat.
        [ValidateRange(0, 365)]
        [int]$Days = 7,

        [ValidateSet('Auto', 'ProtocolLog', 'MessageTracking', 'Path')]
        [string]$Source = 'Auto',

        [string[]]$Path,

        # Eigen domeinen; standaard de accepted domains van Exchange.
        [string[]]$Domain,

        [switch]$IncludeExchangeServers,

        # DNS-naam bij elk IP-adres opzoeken (kan traag zijn).
        [switch]$ResolveDns,

        [System.Management.Automation.Credential()]
        [pscredential]$Credential = [pscredential]::Empty,

        # Het volledige rapport (bron, periode, per dag, aandachtspunten) in plaats van alleen de clients.
        [switch]$Report
    )

    if ($Path -and $Source -eq 'Auto') { $Source = 'Path' }

    $params = @{
        Days                   = $Days
        Source                 = $Source
        IncludeExchangeServers = $IncludeExchangeServers
        ResolveDns             = $ResolveDns
        Credential             = $Credential
    }
    if ($Server) { $params['Server'] = $Server }
    if ($Path) { $params['Path'] = $Path }
    if ($Domain) { $params['Domain'] = $Domain }

    Write-DxLog -Level Action -Message "Relaygebruik analyseren (bron: $Source, $(if ($Days -gt 0) { "$Days dagen" } else { 'alle logs' })) ..."
    $result = Invoke-DxRelayAnalysis @params
    foreach ($note in $result.Opmerkingen) { Write-DxLog -Message $note }
    Write-DxLog -Level Success -Message ("Relaygebruik: {0} client(s), bron {1}." -f @($result.Clients).Count, $result.Bron)

    if ($Report) { return $result }
    $result.Clients
}
