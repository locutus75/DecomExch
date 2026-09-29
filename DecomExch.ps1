<#
.SYNOPSIS
    DecomExch - onderzoeken, rapporteren, exporteren naar PST, opruimen en uitfaseren
    van een on-premises Exchange-server.

.DESCRIPTION
    Start zonder parameters een interactief menu. Met -Action Web start de
    webinterface in de browser. Met de overige acties kan een taak ook zonder
    menu (bijv. gepland) worden uitgevoerd.

    Het menu start ALTIJD in simulatiemodus: er wordt niets gewijzigd of geexporteerd
    totdat je de simulatiemodus uitzet. Opruimacties vragen daarna nog om bevestiging.

    Draai dit script in de Exchange Management Shell als Organization Management,
    of geef -ExchangeServer op om remote te verbinden. Public folders exporteren gaat via
    Outlook en kan ook op een werkstation zonder Exchange-cmdlets.

.PARAMETER Action
    Menu (standaard), Web, Inventory, MailboxReport, PublicFolderReport, RelayReport, Readiness,
    HybridReport, ExportMailboxes, ExportPublicFolders, PstStatus,
    CleanLogs, CleanRequests, CleanDisconnectedMailboxes, CleanCertificates, CleanHybrid,
    ServiceStatus, StopServices, RestoreServices.

.PARAMETER Execute
    Alleen voor niet-interactieve export- en opruimacties: voer de actie echt uit.
    Zonder -Execute draait de actie als -WhatIf (simulatie).

.EXAMPLE
    .\DecomExch.ps1

.EXAMPLE
    .\DecomExch.ps1 -Action Web

.EXAMPLE
    .\DecomExch.ps1 -Action Web -ExchangeServer ex01.contoso.local -Credential contoso\beheerder

    Start de webinterface op een beheerlaptop en verbindt remote met EX01 als een ander account.

.EXAMPLE
    .\DecomExch.ps1 -Action Inventory -OutputPath D:\DecomExch

.EXAMPLE
    .\DecomExch.ps1 -Action ExportMailboxes -Mailbox jan@contoso.com -PstPath \\fs01\pst$ -IncludeArchive -Execute

.EXAMPLE
    .\DecomExch.ps1 -Action ExportPublicFolders -PublicFolder '\' -PstPath D:\PST -Execute

.EXAMPLE
    .\DecomExch.ps1 -Action CleanLogs -Server EX01 -OlderThanDays 30 -Execute

.EXAMPLE
    .\DecomExch.ps1 -Action RelayReport -Days 14

    Wie gebruikt de server(s) nog als SMTP-relay? (SMTP-protocollogs of message tracking)

.EXAMPLE
    .\DecomExch.ps1 -Action RelayReport -LogPath D:\Logs\SmtpReceive -Domain contoso.nl -Days 0

    Analyseert gekopieerde RECV*.log-bestanden, zonder Exchange-verbinding.

.EXAMPLE
    .\DecomExch.ps1 -Action CleanHybrid

    Simuleert het opruimen van de hybride koppeling met Exchange Online (met -Execute echt uitvoeren;
    er wordt eerst een back-up gemaakt in <OutputPath>\Backup).

.EXAMPLE
    .\DecomExch.ps1 -Action StopServices -Server EX01 -IncludeIis -Execute

    Stopt alle Exchange-diensten (en IIS) op EX01 en zet ze op Disabled. De oorspronkelijke toestand
    staat in <OutputPath>\Diensten; -Action RestoreServices -Server EX01 -Execute zet alles terug.
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Web', 'Inventory', 'MailboxReport', 'PublicFolderReport', 'RelayReport', 'Readiness', 'HybridReport',
        'ExportMailboxes', 'ExportPublicFolders', 'PstStatus',
        'CleanLogs', 'CleanRequests', 'CleanDisconnectedMailboxes', 'CleanCertificates', 'CleanHybrid',
        'ServiceStatus', 'StopServices', 'RestoreServices')]
    [string]$Action = 'Menu',

    [string]$Server,

    # Exchange-server om remote mee te verbinden, bijv. vanaf een beheerlaptop (gebruik de volledige naam).
    [string]$ExchangeServer,

    # Ander account voor de remote verbinding, bijv. contoso\beheerder (vraagt om het wachtwoord).
    # Wordt ook gebruikt om logbestanden via \\server\C$ op te ruimen.
    [System.Management.Automation.Credential()]
    [pscredential]$Credential = [pscredential]::Empty,

    # Authenticatie voor de remote verbinding; Kerberos is de standaard van Exchange.
    [ValidateSet('Kerberos', 'Negotiate', 'Basic')]
    [string]$Authentication = 'Kerberos',

    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Output'),

    [ValidateRange(1, 3650)]
    [int]$OlderThanDays = 14,

    [ValidateRange(1, 3650)]
    [int]$InactiveDays = 90,

    # Mailboxen voor ExportMailboxes; leeg = alle gebruikers-, gedeelde en resourcemailboxen.
    [string[]]$Mailbox,

    # UNC-share voor mailbox-PST's, of pad/map voor de public folder-PST.
    [string]$PstPath,

    [switch]$IncludeArchive,

    [string[]]$PublicFolder = @('\'),

    [switch]$Execute,

    # Poort voor de webinterface (-Action Web).
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765,

    # Webinterface starten zonder automatisch de browser te openen.
    [switch]$NoBrowser,

    # Relaygebruik (-Action RelayReport): aantal dagen terug, 0 = alles in de logs.
    [ValidateRange(0, 365)]
    [int]$Days = 7,

    # Relaygebruik: bron van de gegevens.
    [ValidateSet('Auto', 'ProtocolLog', 'MessageTracking', 'Path')]
    [string]$RelaySource = 'Auto',

    # Relaygebruik: map(pen) met gekopieerde RECV*.log-bestanden (geen Exchange-verbinding nodig).
    [string[]]$LogPath,

    # Relaygebruik: eigen domeinen voor intern/extern (standaard de accepted domains).
    [string[]]$Domain,

    # CleanHybrid: ook uitvoeren als er nog mailboxen of migraties on-premises zijn.
    [switch]$Force,

    # StopServices/RestoreServices/ServiceStatus: ook IIS (W3SVC, WAS, IISADMIN).
    [switch]$IncludeIis
)

$ErrorActionPreference = 'Stop'

if ($Credential -ne [pscredential]::Empty -and -not $ExchangeServer -and $Action -notin 'ServiceStatus', 'StopServices', 'RestoreServices') {
    throw 'Geef ook -ExchangeServer op: -Credential wordt gebruikt voor de remote verbinding met die server.'
}
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'src\DecomExch\DecomExch.psd1') -Force -DisableNameChecking

$logFile = Set-DxLogFile -Path (Join-Path -Path $OutputPath -ChildPath 'Logs')

function Initialize-Connection {
    if ($ExchangeServer) {
        Connect-DxExchange -Server $ExchangeServer -Credential $Credential -Authentication $Authentication
    }
    else {
        # Doet niets als er al een werkende verbinding is; ruimt een verbroken sessie op.
        Connect-DxExchange
    }
}

function Read-Value {
    param([string]$Prompt, [string]$Default)
    $label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $answer = Read-Host $label
    if ([string]::IsNullOrWhiteSpace($answer)) { $Default } else { $answer.Trim() }
}

function Read-Server {
    param([string]$Default)
    $servers = @(Get-ExchangeServer | Sort-Object Name | ForEach-Object { $_.Name })
    if ($servers.Count -gt 0) { Write-Host ('Beschikbare servers: ' + ($servers -join ', ')) }
    if (-not $Default) { $Default = if ($servers -contains $env:COMPUTERNAME) { $env:COMPUTERNAME } else { $servers | Select-Object -First 1 } }
    Read-Value -Prompt 'Server' -Default $Default
}

function Read-Days {
    param([string]$Prompt = 'Ouder dan hoeveel dagen?', [int]$Default)
    $value = 0
    if ([int]::TryParse((Read-Host "$Prompt [$Default]"), [ref]$value) -and $value -ge 1) { $value } else { $Default }
}

function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $false)
    $hint = if ($Default) { 'J/n' } else { 'j/N' }
    $answer = (Read-Host "$Prompt [$hint]").Trim().ToUpper()
    if (-not $answer) { $Default } else { $answer -in 'J', 'JA', 'Y', 'YES' }
}

function Confirm-Execution {
    param([string]$What)
    Write-Host ''
    Write-Host "LET OP: je staat op het punt om echt te wijzigen: $What" -ForegroundColor Yellow
    (Read-Host "Typ JA om door te gaan") -ceq 'JA'
}

function Show-Checks {
    param([object[]]$Checks)
    foreach ($c in $Checks) {
        $color = switch ($c.Status) { 'Blokkerend' { 'Red' } 'Waarschuwing' { 'Yellow' } 'OK' { 'Green' } default { 'Gray' } }
        Write-Host ('[{0,-12}] {1}' -f $c.Status, $c.Check) -ForegroundColor $color
        if ($c.Details) { Write-Host "               $($c.Details)" }
        if ($c.Status -in 'Blokkerend', 'Waarschuwing' -and $c.Oplossing) { Write-Host "               -> $($c.Oplossing)" -ForegroundColor DarkCyan }
    }
    $blockers = @($Checks | Where-Object { $_.Status -eq 'Blokkerend' }).Count
    Write-Host ''
    if ($blockers -eq 0) { Write-Host 'Geen blokkerende punten: de server kan worden uitgefaseerd (controleer de waarschuwingen).' -ForegroundColor Green }
    else { Write-Host "$blockers blokkerend(e) punt(en): los deze eerst op." -ForegroundColor Red }
}

function Show-Result {
    param([object[]]$Result, [string]$Empty, [string[]]$Property)
    if (@($Result).Count -eq 0) { Write-Host $Empty -ForegroundColor Green; return }
    if ($Property) { $Result | Format-Table -Property $Property -AutoSize -Wrap | Out-String -Width 250 | Write-Host }
    else { $Result | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host }
}

function Invoke-Task {
    param(
        [string]$Name,
        [bool]$Simulate,
        [hashtable]$Options
    )

    $whatIf = @{ WhatIf = $Simulate; Confirm = $false }

    switch ($Name) {
        'Inventory' {
            $report = Get-DxInventory -InactiveDays $Options.InactiveDays | Export-DxReport -Path $OutputPath -Title 'Exchange inventarisatie'
            Write-Host "Rapport: $report" -ForegroundColor Green
        }
        'MailboxReport' {
            $rows = @(Get-DxMailboxReport -InactiveDays $Options.InactiveDays | Sort-Object GrootteMB -Descending)
            $totalGb = [math]::Round((($rows | Measure-Object -Property GrootteMB -Sum).Sum) / 1024, 1)
            $inactive = @($rows | Where-Object Inactief).Count
            Write-Host ("{0} mailbox(en), totaal {1} GB, {2} inactief (> {3} dagen niet aangemeld)." -f $rows.Count, $totalGb, $inactive, $Options.InactiveDays) -ForegroundColor Cyan
            Show-Result -Result @($rows | Select-Object -First 15) -Empty 'Geen mailboxen gevonden.' `
                -Property DisplayName, RecipientTypeDetails, GrootteMB, Items, Archief, LaatsteAanmelding, Inactief
            $report = $rows | Export-DxReport -Path $OutputPath -Title 'Mailboxoverzicht'
            Write-Host "Volledig rapport: $report" -ForegroundColor Green
        }
        'PublicFolderReport' {
            $rows = @(Get-DxPublicFolderReport | Sort-Object Map)
            $totalMb = [math]::Round(($rows | Measure-Object -Property GrootteMB -Sum).Sum, 1)
            Write-Host ("{0} public folder(s), totaal {1} MB." -f $rows.Count, $totalMb) -ForegroundColor Cyan
            $report = $rows | Export-DxReport -Path $OutputPath -Title 'Public folders'
            Write-Host "Rapport: $report" -ForegroundColor Green
        }
        'RelayReport' {
            $params = @{ Days = $Options.RelayDays; Source = $Options.RelaySource; Report = $true }
            if ($Options.LogPath) { $params['Path'] = $Options.LogPath }
            if ($Options.Domain) { $params['Domain'] = $Options.Domain }
            $r = Get-DxRelayUsage @params
            Write-Host ("Bron: {0} - {1} client(s)." -f $r.Bron, @($r.Clients).Count) -ForegroundColor Cyan
            foreach ($note in $r.Opmerkingen) { Write-Host " - $note" -ForegroundColor Yellow }
            Show-Result -Result @($r.Clients | Select-Object -First 20) -Empty 'Geen SMTP-verkeer van clients gevonden.' `
                -Property Client, Naam, Type, Berichten, Aanmelding, TLS, ExterneOntvangers, Afzenders, LaatsteKeer
            $sections = [ordered]@{
                'Clients'           = @($r.Clients)
                'Berichten per dag' = @($r.PerDag)
                'Aandachtspunten'   = @($r.Opmerkingen | ForEach-Object { [pscustomobject]@{ Aandachtspunt = $_ } })
            }
            if ($r.Bron -ne 'Map met logbestanden' -and (Get-Command -Name Get-ReceiveConnector -ErrorAction SilentlyContinue)) {
                $sections['Receive connectors'] = @(Get-DxReceiveConnectorReport)
            }
            $report = $sections | Export-DxReport -Path $OutputPath -Title 'Relaygebruik'
            Write-Host "Volledig rapport: $report" -ForegroundColor Green
        }
        'Readiness' {
            $checks = @(Test-DxDecomReadiness -Server $Options.Server)
            Show-Checks -Checks $checks
            $report = $checks | Export-DxReport -Path $OutputPath -Title "Uitfaseringscontrole $($Options.Server)" -NoCsv
            Write-Host "Rapport: $report" -ForegroundColor Green
        }
        'HybridReport' {
            $r = Get-DxHybridReport
            Show-Checks -Checks $r.Controles
            Write-Host ''
            Show-Result -Result $r.Onderdelen -Empty 'Geen hybride koppeling met Exchange Online gevonden.' -Property Onderdeel, Naam, Actie, Standaard, Opmerking
            Write-Host 'Daarnaast handmatig (Exchange Online, DNS, Entra Connect):' -ForegroundColor Cyan
            foreach ($m in $r.Handmatig) { Write-Host (' {0,2}. [{1}] {2}: {3}' -f $m.Stap, $m.Waar, $m.Wat, $m.Opdracht) }
            $report = [ordered]@{ 'Onderdelen' = @($r.Onderdelen); 'Controles' = @($r.Controles); 'Handmatige stappen' = @($r.Handmatig) } |
                Export-DxReport -Path $OutputPath -Title 'Hybride koppeling'
            Write-Host "Rapport: $report" -ForegroundColor Green
        }
        'ServiceStatus' {
            $rows = @(Get-DxExchangeService -ComputerName $Options.Server -IncludeIis:$Options.IncludeIis -StatePath $serviceStatePath @serviceCredential)
            Show-Result -Result $rows -Empty 'Geen Exchange-diensten gevonden.' -Property Dienst, Weergavenaam, Status, Opstarttype, Oorspronkelijk
        }
        'StopServices' {
            $rows = @(Stop-DxExchangeService -ComputerName $Options.Server -IncludeIis:$Options.IncludeIis -StatePath $serviceStatePath @serviceCredential @whatIf)
            Show-Result -Result $rows -Empty 'Geen Exchange-diensten gevonden.' -Property Dienst, WasStatus, WasOpstarttype, Status, Opstarttype, Uitgevoerd, Opmerking
            if (-not $Simulate) { Write-Host "Oorspronkelijke toestand: $serviceStatePath. Ongedaan maken: -Action RestoreServices (of menu 16)." -ForegroundColor Cyan }
        }
        'RestoreServices' {
            $rows = @(Restore-DxExchangeService -ComputerName $Options.Server -IncludeIis:$Options.IncludeIis -StatePath $serviceStatePath @serviceCredential @whatIf)
            Show-Result -Result $rows -Empty 'Geen Exchange-diensten gevonden.' -Property Dienst, WasStatus, Status, Opstarttype, Uitgevoerd, Opmerking
        }
        'ExportMailboxes' {
            $params = @{ FilePath = $Options.PstPath; IncludeArchive = [bool]$Options.IncludeArchive }
            if ($Options.Database) { $params['Database'] = $Options.Database }
            elseif ($Options.Mailbox) { $params['Identity'] = $Options.Mailbox }
            else { $params['All'] = $true }

            $result = @(Export-DxMailboxToPst @params @whatIf)
            Show-Result -Result $result -Empty 'Geen mailboxen geselecteerd.' -Property Mailbox, Soort, Bestand, Status, Fout
            if (-not $Simulate) { Write-Host 'Volg de voortgang via "Status van PST-exports".' -ForegroundColor Cyan }
        }
        'ExportPublicFolders' {
            $result = @(Export-DxPublicFolderToPst -FolderPath $Options.PublicFolder -FilePath $Options.PstPath @whatIf)
            Show-Result -Result $result -Empty 'Geen public folders gevonden.' -Property Map, Items, Bestand, Status, Fout
        }
        'PstStatus' {
            $result = @(Get-DxPstExportStatus)
            Show-Result -Result $result -Empty 'Geen PST-exportaanvragen gevonden.' -Property Aanvraag, Status, Procent, Overgezet, Bestand
        }
        'CleanLogs' {
            $result = Clear-DxExchangeLog -ComputerName $Options.Server -OlderThanDays $Options.Days @whatIf
            if ($Simulate) {
                $files = @(Get-DxLogCleanupCandidate -ComputerName $Options.Server -OlderThanDays $Options.Days)
                $mb = [math]::Round((($files | Measure-Object -Property Length -Sum).Sum) / 1MB, 1)
                Write-Host "Simulatie: $($files.Count) bestand(en), $mb MB zou worden verwijderd." -ForegroundColor Cyan
            }
            elseif ($result) { $result | Format-List | Out-String -Width 250 | Write-Host }
        }
        'CleanRequests' {
            Show-Result -Result @(Remove-DxStaleRequest @whatIf) -Empty 'Niets op te ruimen.'
        }
        'CleanDisconnectedMailboxes' {
            Show-Result -Result @(Remove-DxDisconnectedMailbox -OlderThanDays $Options.Days @whatIf) -Empty 'Geen losgekoppelde mailboxen gevonden.' `
                -Property Database, DisplayName, Reden, DisconnectDate, Verwijderd, Fout
        }
        'CleanCertificates' {
            $params = @{}
            if ($Options.Server) { $params['Server'] = $Options.Server }
            Show-Result -Result @(Remove-DxExpiredCertificate @params @whatIf) -Empty 'Geen verlopen certificaten gevonden.' `
                -Property Server, Subject, NotAfter, Services, Verwijderd, Opmerking
        }
        'CleanHybrid' {
            $result = @(Remove-DxHybridConfiguration -BackupPath (Join-Path $OutputPath 'Backup') -Force:$Options.Force @whatIf)
            Show-Result -Result $result -Empty 'Geen hybride koppeling om op te ruimen.' -Property Onderdeel, Naam, Actie, Uitgevoerd, Opmerking
            if (-not $Simulate -and $result.Count -gt 0) {
                Write-Host "Back-up: $(Join-Path $OutputPath 'Backup'). Vergeet de stappen in Exchange Online en DNS niet (actie HybridReport)." -ForegroundColor Cyan
            }
        }
    }
}

$defaults = @{
    Server       = $Server
    Days         = $OlderThanDays
    InactiveDays = $InactiveDays
    Mailbox      = $Mailbox
    Database     = $null
    PstPath      = $PstPath
    IncludeArchive = [bool]$IncludeArchive
    PublicFolder = $PublicFolder
    RelayDays    = $Days
    RelaySource  = if ($LogPath -and $RelaySource -eq 'Auto') { 'Path' } else { $RelaySource }
    LogPath      = $LogPath
    Domain       = $Domain
    Force        = [bool]$Force
    IncludeIis   = [bool]$IncludeIis
}
$serviceStatePath = Join-Path -Path $OutputPath -ChildPath 'Diensten'
$serviceCredential = @{}
if ($Credential -ne [pscredential]::Empty) { $serviceCredential['Credential'] = $Credential }

# --- Webinterface -------------------------------------------------------------------
if ($Action -eq 'Web') {
    try {
        Initialize-Connection
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Write-Host 'De webinterface start zonder Exchange-verbinding; verbind via de knop rechtsboven.' -ForegroundColor Yellow
    }
    Start-DxWebUI -Port $Port -OutputPath $OutputPath -NoBrowser:$NoBrowser
    return
}

# --- Niet-interactief --------------------------------------------------------------
if ($Action -ne 'Menu') {
    # Diensten gaan via CIM en werken ook als Exchange zelf niet draait.
    $offline = $Action -in 'ExportPublicFolders', 'ServiceStatus', 'StopServices', 'RestoreServices' -or ($Action -eq 'RelayReport' -and $defaults.RelaySource -eq 'Path')
    if (-not $offline) { Initialize-Connection }
    if ($Action -in 'Readiness', 'CleanLogs', 'ServiceStatus', 'StopServices', 'RestoreServices' -and -not $Server) {
        throw "Geef -Server op voor actie '$Action'."
    }
    if ($Action -in 'ExportMailboxes', 'ExportPublicFolders' -and -not $PstPath) {
        throw "Geef -PstPath op voor actie '$Action'."
    }
    if (-not $Execute -and ($Action -like 'Clean*' -or $Action -like 'Export*' -or $Action -in 'StopServices', 'RestoreServices')) {
        Write-Host 'Simulatiemodus (-WhatIf). Gebruik -Execute om echt uit te voeren.' -ForegroundColor Cyan
    }
    Invoke-Task -Name $Action -Simulate (-not $Execute) -Options $defaults
    return
}

# --- Interactief menu --------------------------------------------------------------
$simulate = $true
$menu = [ordered]@{
    '1'  = @{ Group = 'Onderzoek en rapportage'; Task = 'Inventory';                  Text = 'Volledige inventarisatie (HTML/CSV-rapport)' }
    '2'  = @{ Group = 'Onderzoek en rapportage'; Task = 'MailboxReport';              Text = 'Mailboxoverzicht: grootte, archief, laatste aanmelding' }
    '3'  = @{ Group = 'Onderzoek en rapportage'; Task = 'PublicFolderReport';         Text = 'Public folder-overzicht: items en grootte' }
    '4'  = @{ Group = 'Onderzoek en rapportage'; Task = 'RelayReport';                Text = 'Relaygebruik: wie verstuurt nog mail via de server (SMTP-logs)' }
    '5'  = @{ Group = 'Onderzoek en rapportage'; Task = 'Readiness';                  Text = 'Uitfaseringscontrole voor een server' }
    '6'  = @{ Group = 'Onderzoek en rapportage'; Task = 'HybridReport';               Text = 'Hybride koppeling met Exchange Online in kaart brengen' }
    '7'  = @{ Group = 'Exporteren naar PST';     Task = 'ExportMailboxes';            Text = 'Mailboxen exporteren naar PST' }
    '8'  = @{ Group = 'Exporteren naar PST';     Task = 'ExportPublicFolders';        Text = 'Public folders exporteren naar PST (via Outlook)' }
    '9'  = @{ Group = 'Exporteren naar PST';     Task = 'PstStatus';                  Text = 'Status van PST-exports' }
    '10' = @{ Group = 'Opruimen';                Task = 'CleanLogs';                  Text = 'Oude Exchange- en IIS-logbestanden opruimen';          Confirm = $true }
    '11' = @{ Group = 'Opruimen';                Task = 'CleanRequests';              Text = 'Afgeronde verplaats/export/import-aanvragen opruimen'; Confirm = $true }
    '12' = @{ Group = 'Opruimen';                Task = 'CleanDisconnectedMailboxes'; Text = 'Losgekoppelde mailboxen definitief verwijderen';       Confirm = $true }
    '13' = @{ Group = 'Opruimen';                Task = 'CleanCertificates';          Text = 'Verlopen certificaten verwijderen';                    Confirm = $true }
    '14' = @{ Group = 'Opruimen';                Task = 'CleanHybrid';                Text = 'Hybride koppeling met Exchange Online opruimen';        Confirm = $true }
    '15' = @{ Group = 'Diensten';                Task = 'ServiceStatus';              Text = 'Status van de Exchange-diensten' }
    '16' = @{ Group = 'Diensten';                Task = 'StopServices';               Text = 'Alle Exchange-diensten stoppen en uitschakelen';       Confirm = $true }
    '17' = @{ Group = 'Diensten';                Task = 'RestoreServices';            Text = 'Exchange-diensten herstellen (stoppen ongedaan maken)'; Confirm = $true }
}

try {
    Initialize-Connection
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'Zonder Exchange-verbinding werken alleen "Relaygebruik" (map met logbestanden), "Public folders exporteren naar PST (via Outlook)" en de Exchange-diensten (15-17).' -ForegroundColor Yellow
}

while ($true) {
    Write-Host ''
    Write-Host '========================= DecomExch =========================' -ForegroundColor Cyan
    $group = $null
    foreach ($key in $menu.Keys) {
        if ($menu[$key].Group -ne $group) { $group = $menu[$key].Group; Write-Host " $group" -ForegroundColor DarkCyan }
        Write-Host ('  {0,2}. {1}' -f $key, $menu[$key].Text)
    }
    Write-Host ''
    $modeText = if ($simulate) { 'AAN (er wordt niets gewijzigd of geexporteerd)' } else { 'UIT (acties worden echt uitgevoerd!)' }
    $modeColor = if ($simulate) { 'Green' } else { 'Red' }
    Write-Host '   S. Simulatiemodus: ' -NoNewline; Write-Host $modeText -ForegroundColor $modeColor
    Write-Host '   Q. Afsluiten'
    Write-Host "Logbestand: $logFile" -ForegroundColor DarkGray

    $choice = (Read-Host 'Keuze').Trim().ToUpper()
    if ($choice -eq 'Q') { break }
    if ($choice -eq 'S') { $simulate = -not $simulate; continue }
    if (-not $menu.Contains($choice)) { Write-Host 'Onbekende keuze.' -ForegroundColor Yellow; continue }

    $item = $menu[$choice]
    $options = $defaults.Clone()
    try {
        switch ($item.Task) {
            { $_ -in 'Readiness', 'CleanLogs', 'CleanCertificates' } { $options.Server = Read-Server -Default $Server }
            { $_ -in 'ServiceStatus', 'StopServices', 'RestoreServices' } {
                $connected = [bool](Get-Command -Name Get-ExchangeServer -ErrorAction SilentlyContinue)
                $options.Server = if ($connected) { Read-Server -Default $Server } else { Read-Value -Prompt 'Server' -Default $Server }
                if (-not $options.Server) { throw 'Geef een server op.' }
                if ($_ -ne 'ServiceStatus') { $options.IncludeIis = Read-YesNo -Prompt 'Ook IIS stoppen/herstellen (OWA, EWS, ActiveSync, Autodiscover)?' -Default ([bool]$IncludeIis) }
            }
            { $_ -in 'CleanLogs', 'CleanDisconnectedMailboxes' } { $options.Days = Read-Days -Default $OlderThanDays }
            'CleanHybrid' {
                $options.Force = $Force
                if (-not $simulate) {
                    $blockers = @((Get-DxHybridReport).Controles | Where-Object Status -eq 'Blokkerend')
                    if ($blockers.Count -gt 0) {
                        Show-Checks -Checks $blockers
                        $options.Force = Read-YesNo -Prompt 'Toch doorgaan ondanks de blokkerende punten?' -Default $false
                        if (-not $options.Force) { throw 'Geannuleerd: los eerst de blokkerende punten op.' }
                    }
                }
            }
            { $_ -in 'Inventory', 'MailboxReport' } { $options.InactiveDays = Read-Days -Prompt 'Inactief na hoeveel dagen zonder aanmelding?' -Default $InactiveDays }
            'RelayReport' {
                $connected = [bool](Get-Command -Name Get-ExchangeServer -ErrorAction SilentlyContinue)
                $choice = Read-Value -Prompt 'Bron? A = automatisch, P = protocollogs, M = message tracking, F = map met logbestanden' -Default $(if ($connected) { 'A' } else { 'F' })
                $options.RelaySource = switch -Regex ($choice) { '^[Pp]' { 'ProtocolLog' } '^[Mm]' { 'MessageTracking' } '^[Ff]' { 'Path' } default { 'Auto' } }
                if ($options.RelaySource -eq 'Path') {
                    $options.LogPath = @((Read-Value -Prompt 'Map met RECV*.log-bestanden' -Default ($LogPath -join ',')) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    if (-not $options.LogPath) { throw 'Geef een map met logbestanden op.' }
                }
                elseif (-not $connected) {
                    throw 'Zonder Exchange-verbinding kan alleen een map met logbestanden worden geanalyseerd (kies F).'
                }
                $dayAnswer = Read-Value -Prompt 'Hoeveel dagen terug? (0 = alles in de logs)' -Default "$Days"
                $parsed = 0
                $options.RelayDays = if ([int]::TryParse($dayAnswer, [ref]$parsed) -and $parsed -ge 0) { $parsed } else { $Days }
                $domainAnswer = Read-Value -Prompt 'Eigen domeinen, gescheiden door komma''s (leeg = accepted domains van Exchange)' -Default ($Domain -join ',')
                $options.Domain = @($domainAnswer -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
            'ExportMailboxes' {
                $options.PstPath = Read-Value -Prompt 'UNC-share voor de PST-bestanden (\\server\share)' -Default $PstPath
                if ($options.PstPath -notmatch '^\\\\[^\\]+\\[^\\]+') {
                    throw 'Geef een UNC-pad op (\\server\share): Exchange schrijft de PST zelf weg.'
                }
                $selection = Read-Value -Prompt 'Welke mailboxen? A = alle, D = per database, of namen/e-mailadressen gescheiden door komma''s' -Default 'A'
                switch -Regex ($selection) {
                    '^[Aa]$' { $options.Mailbox = $null }
                    '^[Dd]$' {
                        Write-Host ('Databases: ' + ((Get-MailboxDatabase | ForEach-Object { $_.Name }) -join ', '))
                        $options.Database = @((Read-Value -Prompt 'Database(s), gescheiden door komma''s') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    }
                    default { $options.Mailbox = @($selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                }
                $options.IncludeArchive = Read-YesNo -Prompt 'Ook online archieven exporteren?' -Default $true
            }
            'ExportPublicFolders' {
                $defaultPst = if ($PstPath) { $PstPath } else { Join-Path $OutputPath 'PST' }
                $options.PstPath = Read-Value -Prompt 'PST-bestand of map' -Default $defaultPst
                $options.PublicFolder = @((Read-Value -Prompt 'Map(pen), bijv. \Afdelingen\Verkoop (\ = alles)' -Default '\') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
        }

        if ($item.Confirm -and -not $simulate -and -not (Confirm-Execution -What $item.Text)) {
            Write-Host 'Geannuleerd.' -ForegroundColor Yellow
            continue
        }

        Invoke-Task -Name $item.Task -Simulate $simulate -Options $options
    }
    catch {
        Write-Host "Fout: $($_.Exception.Message)" -ForegroundColor Red
    }
}
