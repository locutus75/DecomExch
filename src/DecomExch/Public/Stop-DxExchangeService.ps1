function Stop-DxExchangeService {
    <#
    .SYNOPSIS
        Stopt alle Exchange-diensten van een server en zet ze op Uitgeschakeld (Disabled).
    .DESCRIPTION
        Bedoeld om een server buiten gebruik te zetten zonder hem te verwijderen ("scream test"): wie
        of wat de server nog gebruikt, merkt het. Met Restore-DxExchangeService gaat alles terug.

        - Eerst wordt de oorspronkelijke toestand (status en opstarttype, ook 'vertraagd starten')
          opgeslagen in -StatePath. Een tweede keer stoppen overschrijft die niet.
        - Daarna gaan alle diensten op Disabled (zodat Managed Availability of herstelacties ze niet
          opnieuw starten) en worden de draaiende diensten gestopt, afhankelijke diensten eerst.
        - Met -IncludeIis stopt ook IIS (W3SVC, WAS, IISADMIN): OWA, ECP, EWS, ActiveSync en
          Autodiscover reageren dan helemaal niet meer. Let op: ook andere websites op de server.
        Werkt via CIM, ook vanaf een beheerlaptop (-Credential of die van Connect-DxExchange).
    .EXAMPLE
        Stop-DxExchangeService -ComputerName EX01 -WhatIf
    .EXAMPLE
        Stop-DxExchangeService -ComputerName EX01 -IncludeIis -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [pscredential]$Credential,

        [switch]$IncludeIis,

        [string]$StatePath = (Join-Path -Path (Get-Location).Path -ChildPath 'Output\Diensten'),

        # Maximale wachttijd (seconden) tot de diensten gestopt zijn.
        [ValidateRange(10, 3600)]
        [int]$TimeoutSeconds = 300
    )

    $session = New-DxCimSession -ComputerName $ComputerName -Credential (Resolve-DxCredential -Credential $Credential)
    try {
        $services = @(Get-DxServiceCim -CimSession $session | Where-Object { Test-DxExchangeServiceObject -Service $_ -IncludeIis:$IncludeIis } | Sort-Object Name)
        if ($services.Count -eq 0) { throw "Geen Exchange-diensten gevonden op $ComputerName." }

        $results = [ordered]@{}
        foreach ($svc in $services) {
            $results["$($svc.Name)"] = [pscustomobject]@{
                Server         = $ComputerName
                Dienst         = "$($svc.Name)"
                Weergavenaam   = "$($svc.DisplayName)"
                WasStatus      = "$($svc.State)"
                WasOpstarttype = ConvertTo-DxStartModeText -StartMode "$($svc.StartMode)" -Delayed ([bool](Get-DxObjectValue $svc 'DelayedAutoStart'))
                Status         = "$($svc.State)"
                Opstarttype    = "$($svc.StartMode)"
                Uitgevoerd     = $false
                Opmerking      = ''
            }
        }

        $target = "$ComputerName ($($services.Count) diensten)"
        if (-not $PSCmdlet.ShouldProcess($target, 'Exchange-diensten stoppen en uitschakelen')) {
            foreach ($r in $results.Values) { $r.Opmerking = if ($r.WasStatus -eq 'Running') { 'Wordt gestopt en uitgeschakeld' } else { 'Wordt uitgeschakeld' } }
            return @($results.Values | ForEach-Object { $_ })
        }

        # 1. Oorspronkelijke toestand bewaren (bestaande waarden niet overschrijven).
        if (-not (Test-Path -LiteralPath $StatePath)) { New-Item -Path $StatePath -ItemType Directory -Force | Out-Null }
        $stateFile = Get-DxServiceStatePath -Path $StatePath -ComputerName $ComputerName
        $saved = Read-DxServiceState -File $stateFile
        foreach ($svc in $services) {
            if (-not $saved.ContainsKey("$($svc.Name)")) {
                $saved["$($svc.Name)"] = @{ Name = "$($svc.Name)"; DisplayName = "$($svc.DisplayName)"; StartMode = "$($svc.StartMode)"; State = "$($svc.State)"; DelayedAutoStart = [bool](Get-DxObjectValue $svc 'DelayedAutoStart') }
            }
        }
        [ordered]@{
            Server   = $ComputerName
            Opgeslagen = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Services = @($saved.Values | Sort-Object { $_.Name } | ForEach-Object { [pscustomobject]$_ })
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stateFile -Encoding UTF8
        Write-DxLog -Level Action -Message "Toestand van $($services.Count) diensten op $ComputerName opgeslagen: $stateFile"

        # 2. Uitschakelen, zodat niets ze opnieuw start.
        foreach ($svc in $services) {
            if ("$($svc.StartMode)" -eq 'Disabled') { continue }
            $rc = Invoke-DxServiceMethod -Service $svc -Method ChangeStartMode -StartMode 'Disabled' -CimSession $session
            if ($rc -ne 0) { $results["$($svc.Name)"].Opmerking = "Uitschakelen mislukt: $(Get-DxServiceReturnText -Code $rc)" }
        }

        # 3. Stoppen; diensten waar andere nog van afhangen komen in een volgende ronde.
        $pending = @($services | Where-Object { "$($_.State)" -ne 'Stopped' } | ForEach-Object { "$($_.Name)" })
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $round = 0
        while ($pending.Count -gt 0 -and $round -lt 10 -and (Get-Date) -lt $deadline) {
            $round++
            $retry = New-Object System.Collections.Generic.List[string]
            $issued = New-Object System.Collections.Generic.List[string]
            foreach ($name in $pending) {
                $svc = @(Get-DxServiceCim -CimSession $session -Name $name)[0]
                if (-not $svc -or "$($svc.State)" -eq 'Stopped') { continue }
                if ("$($svc.State)" -eq 'Stop Pending') { $issued.Add($name); continue }
                $rc = Invoke-DxServiceMethod -Service $svc -Method StopService -CimSession $session
                switch ($rc) {
                    0 { $issued.Add($name) }
                    3 { $retry.Add($name) }
                    5 { $retry.Add($name) }
                    default { $results[$name].Opmerking = "Stoppen mislukt: $(Get-DxServiceReturnText -Code $rc)" }
                }
            }
            if ($issued.Count -gt 0) {
                $left = [math]::Max(10, [int]($deadline - (Get-Date)).TotalSeconds)
                $slow = @(Wait-DxServiceState -CimSession $session -Name $issued.ToArray() -State 'Stopped' -TimeoutSeconds $left)
                foreach ($s in $slow) { $retry.Add($s) }
            }
            if ($retry.Count -eq $pending.Count -and $issued.Count -eq 0) { break }
            $pending = @($retry | Select-Object -Unique)
        }
        foreach ($name in $pending) {
            if (-not $results[$name].Opmerking) { $results[$name].Opmerking = 'Niet gestopt binnen de wachttijd' }
        }

        # 4. Eindtoestand.
        foreach ($svc in @(Get-DxServiceCim -CimSession $session | Where-Object { $results.Contains("$($_.Name)") })) {
            $r = $results["$($svc.Name)"]
            $r.Status = "$($svc.State)"
            $r.Opstarttype = "$($svc.StartMode)"
            $r.Uitgevoerd = ($r.Status -eq 'Stopped' -and $r.Opstarttype -eq 'Disabled')
            if ($r.Uitgevoerd) { $r.Opmerking = '' }
        }
        $ok = @($results.Values | Where-Object Uitgevoerd).Count
        Write-DxLog -Level Action -Message ("Exchange-diensten op {0}: {1} van {2} gestopt en uitgeschakeld." -f $ComputerName, $ok, $results.Count)
        $results.Values | ForEach-Object { $_ }
    }
    finally {
        if ($session) { Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue }
    }
}
