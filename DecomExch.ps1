<#
.SYNOPSIS
    DecomExch - opruimen en uitfaseren van een on-premises Exchange-server.

.DESCRIPTION
    Start zonder parameters een interactief menu. Met -Action kan een taak ook
    zonder menu (bijv. gepland) worden uitgevoerd.

    Het menu start ALTIJD in simulatiemodus: er wordt niets gewijzigd totdat
    je de simulatiemodus uitzet en de actie expliciet bevestigt.

    Draai dit script in de Exchange Management Shell als Organization Management,
    of geef -ExchangeServer op om remote te verbinden.

.PARAMETER Action
    Menu (standaard), Inventory, Readiness, CleanLogs, CleanRequests,
    CleanDisconnectedMailboxes, CleanCertificates.

.PARAMETER Execute
    Alleen voor niet-interactieve opruimacties: voer de wijziging echt uit.
    Zonder -Execute draait de actie als -WhatIf (simulatie).

.EXAMPLE
    .\DecomExch.ps1

.EXAMPLE
    .\DecomExch.ps1 -Action Inventory -OutputPath D:\DecomExch

.EXAMPLE
    .\DecomExch.ps1 -Action Readiness -Server EX01

.EXAMPLE
    .\DecomExch.ps1 -Action CleanLogs -Server EX01 -OlderThanDays 30 -Execute
#>
[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Inventory', 'Readiness', 'CleanLogs', 'CleanRequests', 'CleanDisconnectedMailboxes', 'CleanCertificates')]
    [string]$Action = 'Menu',

    [string]$Server,

    [string]$ExchangeServer,

    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath 'Output'),

    [ValidateRange(1, 3650)]
    [int]$OlderThanDays = 14,

    [switch]$Execute
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'src\DecomExch\DecomExch.psd1') -Force -DisableNameChecking

$logFile = Set-DxLogFile -Path (Join-Path -Path $OutputPath -ChildPath 'Logs')

function Initialize-Connection {
    if (Get-Command -Name Get-ExchangeServer -ErrorAction SilentlyContinue) { return }
    if ($ExchangeServer) { Connect-DxExchange -Server $ExchangeServer } else { Connect-DxExchange }
}

function Read-Server {
    param([string]$Default)
    $servers = @(Get-ExchangeServer | Sort-Object Name | ForEach-Object { $_.Name })
    if ($servers.Count -gt 0) { Write-Host ('Beschikbare servers: ' + ($servers -join ', ')) }
    if (-not $Default) { $Default = if ($servers -contains $env:COMPUTERNAME) { $env:COMPUTERNAME } else { $servers | Select-Object -First 1 } }
    $answer = Read-Host "Server [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { $Default } else { $answer.Trim() }
}

function Read-Days {
    param([int]$Default)
    $answer = Read-Host "Ouder dan hoeveel dagen? [$Default]"
    $value = 0
    if ([int]::TryParse($answer, [ref]$value) -and $value -ge 1) { $value } else { $Default }
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

function Invoke-Task {
    param(
        [string]$Name,
        [bool]$Simulate,
        [string]$TargetServer,
        [int]$Days
    )

    $whatIf = @{ WhatIf = $Simulate; Confirm = $false }

    switch ($Name) {
        'Inventory' {
            $report = Get-DxInventory | Export-DxReport -Path $OutputPath -Title 'Exchange inventarisatie'
            Write-Host "Rapport: $report" -ForegroundColor Green
        }
        'Readiness' {
            $checks = @(Test-DxDecomReadiness -Server $TargetServer)
            Show-Checks -Checks $checks
            $report = $checks | Export-DxReport -Path $OutputPath -Title "Uitfaseringscontrole $TargetServer" -NoCsv
            Write-Host "Rapport: $report" -ForegroundColor Green
        }
        'CleanLogs' {
            $result = Clear-DxExchangeLog -ComputerName $TargetServer -OlderThanDays $Days @whatIf
            if ($Simulate) {
                $files = @(Get-DxLogCleanupCandidate -ComputerName $TargetServer -OlderThanDays $Days)
                $mb = [math]::Round((($files | Measure-Object -Property Length -Sum).Sum) / 1MB, 1)
                Write-Host "Simulatie: $($files.Count) bestand(en), $mb MB zou worden verwijderd." -ForegroundColor Cyan
            }
            elseif ($result) { $result | Format-List | Out-Host }
        }
        'CleanRequests' {
            $result = @(Remove-DxStaleRequest @whatIf)
            if ($result.Count -eq 0) { Write-Host 'Niets op te ruimen.' -ForegroundColor Green }
            else { $result | Format-Table -AutoSize | Out-Host }
        }
        'CleanDisconnectedMailboxes' {
            $result = @(Remove-DxDisconnectedMailbox -OlderThanDays $Days @whatIf)
            if ($result.Count -eq 0) { Write-Host 'Geen losgekoppelde mailboxen gevonden.' -ForegroundColor Green }
            else { $result | Format-Table Database, DisplayName, Reden, DisconnectDate, Verwijderd, Fout -AutoSize | Out-Host }
        }
        'CleanCertificates' {
            $params = @{}
            if ($TargetServer) { $params['Server'] = $TargetServer }
            $result = @(Remove-DxExpiredCertificate @params @whatIf)
            if ($result.Count -eq 0) { Write-Host 'Geen verlopen certificaten gevonden.' -ForegroundColor Green }
            else { $result | Format-Table Server, Subject, NotAfter, Services, Verwijderd, Opmerking -AutoSize -Wrap | Out-Host }
        }
    }
}

# --- Niet-interactief --------------------------------------------------------------
if ($Action -ne 'Menu') {
    Initialize-Connection
    if ($Action -in 'Readiness', 'CleanLogs' -and -not $Server) {
        throw "Geef -Server op voor actie '$Action'."
    }
    if (-not $Execute -and $Action -like 'Clean*') {
        Write-Host 'Simulatiemodus (-WhatIf). Gebruik -Execute om echt te wijzigen.' -ForegroundColor Cyan
    }
    Invoke-Task -Name $Action -Simulate (-not $Execute) -TargetServer $Server -Days $OlderThanDays
    return
}

# --- Interactief menu --------------------------------------------------------------
$simulate = $true
$menu = [ordered]@{
    '1' = @{ Task = 'Inventory';                  Text = 'Inventarisatie maken (HTML/CSV-rapport)';               NeedsServer = $false; NeedsDays = $false; Changes = $false }
    '2' = @{ Task = 'Readiness';                  Text = 'Uitfaseringscontrole voor een server';                  NeedsServer = $true;  NeedsDays = $false; Changes = $false }
    '3' = @{ Task = 'CleanLogs';                  Text = 'Oude Exchange- en IIS-logbestanden opruimen';           NeedsServer = $true;  NeedsDays = $true;  Changes = $true }
    '4' = @{ Task = 'CleanRequests';              Text = 'Afgeronde verplaats/export/import-aanvragen opruimen';  NeedsServer = $false; NeedsDays = $false; Changes = $true }
    '5' = @{ Task = 'CleanDisconnectedMailboxes'; Text = 'Losgekoppelde mailboxen definitief verwijderen';        NeedsServer = $false; NeedsDays = $true;  Changes = $true }
    '6' = @{ Task = 'CleanCertificates';          Text = 'Verlopen certificaten verwijderen';                     NeedsServer = $true;  NeedsDays = $false; Changes = $true }
}

try {
    Initialize-Connection
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    return
}

while ($true) {
    Write-Host ''
    Write-Host '==================== DecomExch ====================' -ForegroundColor Cyan
    foreach ($key in $menu.Keys) { Write-Host (' {0}. {1}' -f $key, $menu[$key].Text) }
    Write-Host ''
    $modeText = if ($simulate) { 'AAN (er wordt niets gewijzigd)' } else { 'UIT (wijzigingen worden uitgevoerd!)' }
    $modeColor = if ($simulate) { 'Green' } else { 'Red' }
    Write-Host ' S. Simulatiemodus: ' -NoNewline; Write-Host $modeText -ForegroundColor $modeColor
    Write-Host ' Q. Afsluiten'
    Write-Host "Logbestand: $logFile" -ForegroundColor DarkGray

    $choice = (Read-Host 'Keuze').Trim().ToUpper()
    if ($choice -eq 'Q') { break }
    if ($choice -eq 'S') { $simulate = -not $simulate; continue }
    if (-not $menu.Contains($choice)) { Write-Host 'Onbekende keuze.' -ForegroundColor Yellow; continue }

    $item = $menu[$choice]
    try {
        $target = if ($item.NeedsServer) { Read-Server -Default $Server } else { $null }
        $days = if ($item.NeedsDays) { Read-Days -Default $OlderThanDays } else { $OlderThanDays }

        if ($item.Changes -and -not $simulate -and -not (Confirm-Execution -What $item.Text)) {
            Write-Host 'Geannuleerd.' -ForegroundColor Yellow
            continue
        }

        Invoke-Task -Name $item.Task -Simulate $simulate -TargetServer $target -Days $days
    }
    catch {
        Write-Host "Fout: $($_.Exception.Message)" -ForegroundColor Red
    }
}
