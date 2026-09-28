function Restore-DxExchangeService {
    <#
    .SYNOPSIS
        Maakt Stop-DxExchangeService ongedaan: zet de opstarttypes terug en start de diensten die draaiden.
    .DESCRIPTION
        Gebruikt de toestand die Stop-DxExchangeService heeft opgeslagen in -StatePath. Is die er niet
        (bijvoorbeeld gestopt vanaf een andere computer), dan worden de standaardwaarden van Exchange
        gebruikt: Automatisch, behalve IMAP4/POP3 en Windows Server Backup (Handmatig).
        Na een geslaagd herstel wordt het toestandsbestand hernoemd naar *_hersteld_<datum>.json.
    .EXAMPLE
        Restore-DxExchangeService -ComputerName EX01 -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [pscredential]$Credential,

        # Zonder opgeslagen toestand: ook IIS (W3SVC, WAS, IISADMIN) herstellen.
        [switch]$IncludeIis,

        [string]$StatePath = (Join-Path -Path (Get-Location).Path -ChildPath 'Output\Diensten'),

        [ValidateRange(10, 3600)]
        [int]$TimeoutSeconds = 600
    )

    $session = New-DxCimSession -ComputerName $ComputerName -Credential (Resolve-DxCredential -Credential $Credential)
    try {
        $stateFile = Get-DxServiceStatePath -Path $StatePath -ComputerName $ComputerName
        $saved = Read-DxServiceState -File $stateFile
        $fromDefaults = $saved.Count -eq 0
        $current = @{}
        foreach ($svc in @(Get-DxServiceCim -CimSession $session)) { $current["$($svc.Name)"] = $svc }

        if ($fromDefaults) {
            foreach ($svc in @($current.Values | Where-Object { Test-DxExchangeServiceObject -Service $_ -IncludeIis:$IncludeIis })) {
                $manual = "$($svc.Name)" -match 'Imap4|Pop3|^wsbexchange$'
                $saved["$($svc.Name)"] = @{ Name = "$($svc.Name)"; DisplayName = "$($svc.DisplayName)"; StartMode = $(if ($manual) { 'Manual' } else { 'Auto' }); State = $(if ($manual) { 'Stopped' } else { 'Running' }); DelayedAutoStart = $false }
            }
            if ($saved.Count -eq 0) { throw "Geen Exchange-diensten gevonden op $ComputerName." }
            Write-DxLog -Level Warning -Message "Geen opgeslagen toestand voor $ComputerName ($stateFile); de standaardwaarden van Exchange worden gebruikt."
        }

        # ADTopology eerst: vrijwel alle andere Exchange-diensten hebben hem nodig.
        $names = @($saved.Keys | Sort-Object { if ($_ -eq 'MSExchangeADTopology') { 0 } else { 1 } }, { $_ })
        $results = [ordered]@{}
        foreach ($name in $names) {
            $orig = $saved[$name]
            $svc = $current[$name]
            $results[$name] = [pscustomobject]@{
                Server         = $ComputerName
                Dienst         = $name
                Weergavenaam   = $orig.DisplayName
                WasStatus      = if ($svc) { "$($svc.State)" } else { '' }
                WasOpstarttype = if ($svc) { "$($svc.StartMode)" } else { '' }
                Status         = if ($svc) { "$($svc.State)" } else { '' }
                Opstarttype    = ConvertTo-DxStartModeText -StartMode $orig.StartMode -Delayed $orig.DelayedAutoStart
                Uitgevoerd     = $false
                Opmerking      = if (-not $svc) { 'Dienst bestaat niet (meer)' } elseif ($fromDefaults) { 'Standaardwaarde (geen opgeslagen toestand)' } else { '' }
            }
        }

        if (-not $PSCmdlet.ShouldProcess("$ComputerName ($($names.Count) diensten)", 'Exchange-diensten herstellen')) {
            return @($results.Values | ForEach-Object { $_ })
        }

        # 1. Opstarttypes terugzetten.
        foreach ($name in $names) {
            $svc = $current[$name]
            if (-not $svc) { continue }
            $orig = $saved[$name]
            $mode = switch ($orig.StartMode) { 'Auto' { 'Automatic' } 'Automatic' { 'Automatic' } 'Disabled' { 'Disabled' } default { 'Manual' } }
            $rc = Invoke-DxServiceMethod -Service $svc -Method ChangeStartMode -StartMode $mode -CimSession $session
            if ($rc -ne 0) { $results[$name].Opmerking = "Opstarttype terugzetten mislukt: $(Get-DxServiceReturnText -Code $rc)"; continue }
            if ($mode -eq 'Automatic') {
                try { Set-DxServiceDelayedStart -Name $name -Enabled $orig.DelayedAutoStart -CimSession $session }
                catch { $results[$name].Opmerking = "Vertraagd starten niet teruggezet: $($_.Exception.Message)" }
            }
        }

        # 2. Starten wat draaide (afhankelijkheden start Windows zelf mee).
        $toStart = @($names | Where-Object { $current[$_] -and $saved[$_].State -eq 'Running' -and -not $results[$_].Opmerking.StartsWith('Opstarttype') })
        $issued = New-Object System.Collections.Generic.List[string]
        foreach ($name in $toStart) {
            $svc = @(Get-DxServiceCim -CimSession $session -Name $name)[0]
            if (-not $svc) { continue }
            if ("$($svc.State)" -in 'Running', 'Start Pending') { $issued.Add($name); continue }
            $rc = Invoke-DxServiceMethod -Service $svc -Method StartService -CimSession $session
            if ($rc -in 0, 10) { $issued.Add($name) }
            else { $results[$name].Opmerking = "Starten mislukt: $(Get-DxServiceReturnText -Code $rc)" }
        }
        if ($issued.Count -gt 0) {
            foreach ($name in @(Wait-DxServiceState -CimSession $session -Name $issued.ToArray() -State 'Running' -TimeoutSeconds $TimeoutSeconds)) {
                $results[$name].Opmerking = 'Niet gestart binnen de wachttijd'
            }
        }

        # 3. Eindtoestand.
        $failed = 0
        foreach ($name in $names) {
            $r = $results[$name]
            $svc = @(Get-DxServiceCim -CimSession $session -Name $name)[0]
            if (-not $svc) { continue }
            $r.Status = "$($svc.State)"
            $wantMode = switch ($saved[$name].StartMode) { 'Automatic' { 'Auto' } default { $saved[$name].StartMode } }
            $wantRunning = $saved[$name].State -eq 'Running'
            $r.Uitgevoerd = ("$($svc.StartMode)" -eq $wantMode) -and (-not $wantRunning -or $r.Status -eq 'Running')
            if (-not $r.Uitgevoerd) { $failed++ }
            elseif (-not $fromDefaults) { $r.Opmerking = '' }
        }

        if (-not $fromDefaults -and $failed -eq 0) {
            $done = [System.IO.Path]::ChangeExtension($stateFile, $null).TrimEnd('.') + ('_hersteld_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
            Move-Item -LiteralPath $stateFile -Destination $done -Force
        }
        Write-DxLog -Level Action -Message ("Exchange-diensten op {0} hersteld: {1} van {2} gelukt." -f $ComputerName, ($results.Count - $failed), $results.Count)
        $results.Values | ForEach-Object { $_ }
    }
    finally {
        if ($session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
    }
}
