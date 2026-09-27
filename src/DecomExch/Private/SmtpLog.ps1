function ConvertFrom-DxCsvLine {
    <#
    .SYNOPSIS
        Splitst een CSV-regel uit een Exchange-log, inclusief velden tussen aanhalingstekens.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line
    )

    if ($Line.IndexOf('"') -lt 0) { return , $Line.Split(',') }

    $fields = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inQuotes = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($inQuotes) {
            if ($c -eq '"') {
                if ($i + 1 -lt $Line.Length -and $Line[$i + 1] -eq '"') { [void]$sb.Append('"'); $i++ }
                else { $inQuotes = $false }
            }
            else { [void]$sb.Append($c) }
        }
        elseif ($c -eq '"') { $inQuotes = $true }
        elseif ($c -eq ',') { $fields.Add($sb.ToString()); [void]$sb.Clear() }
        else { [void]$sb.Append($c) }
    }
    $fields.Add($sb.ToString())
    , $fields.ToArray()
}

function Split-DxEndpoint {
    <#
    .SYNOPSIS
        Splitst '10.0.0.5:25', '[fe80::1]:25' of 'fe80::1:25' in adres en poort.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Endpoint
    )

    if (-not $Endpoint) { return [pscustomobject]@{ Address = ''; Port = '' } }
    if ($Endpoint -match '^\[(?<a>[^\]]+)\]:(?<p>\d+)$') { return [pscustomobject]@{ Address = $Matches['a']; Port = $Matches['p'] } }
    $i = $Endpoint.LastIndexOf(':')
    if ($i -gt 0 -and $Endpoint.Substring($i + 1) -match '^\d+$') {
        return [pscustomobject]@{ Address = $Endpoint.Substring(0, $i); Port = $Endpoint.Substring($i + 1) }
    }
    [pscustomobject]@{ Address = $Endpoint; Port = '' }
}

function Get-DxEmailAddress {
    <#
    .SYNOPSIS
        Haalt het adres uit 'MAIL FROM:<a@b.nl> SIZE=123' of 'RCPT TO:<a@b.nl>'. Leeg adres (<>) wordt '<>'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string]$Command
    )

    if ($Command -match '<(?<a>[^>]*)>') {
        if ($Matches['a']) { return $Matches['a'].ToLower() }
        return '<>'
    }
    $parts = ($Command -split ':', 2)
    if ($parts.Count -eq 2) { return ($parts[1].Trim() -split '\s+')[0].ToLower() }
    ''
}

function Read-DxSmtpReceiveLog {
    <#
    .SYNOPSIS
        Leest SMTP Receive-protocollogs (RECV*.log) en geeft per SMTP-sessie een samenvatting.
    .DESCRIPTION
        Per sessie: server, connector, lokaal/remote eindpunt, EHLO-naam, aanmelding (methode en
        account), TLS, afzenders, ontvangers en het aantal geaccepteerde berichten.
        Tijden in de logs zijn UTC en worden omgezet naar lokale tijd.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo[]]$File,

        [datetime]$Start = [datetime]::MinValue,

        [datetime]$End = [datetime]::MaxValue,

        [string]$ServerLabel = '',

        # Optioneel: hierin komen de namen van bestanden die niet (volledig) gelezen konden worden.
        [System.Collections.Generic.List[string]]$SkippedFile
    )

    $expected = 'date-time,connector-id,session-id,sequence-number,local-endpoint,remote-endpoint,event,data,context'
    $sessions = @{}
    $fileIndex = 0

    foreach ($f in $File) {
        $fileIndex++
        Write-Progress -Activity 'SMTP-protocollogs lezen' -Status $f.Name -PercentComplete ([int](100 * $fileIndex / [math]::Max(1, $File.Count)))

        $fast = $true
        $index = $null
        # Exchange houdt het actieve logbestand open om te schrijven; daarom openen met FileShare
        # ReadWrite/Delete (File.ReadLines staat alleen gedeeld lezen toe en faalt dan).
        $reader = $null
        try {
            $stream = New-Object System.IO.FileStream($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            $reader = New-Object System.IO.StreamReader($stream)
        }
        catch {
            $msg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
            Write-Warning "Logbestand '$($f.FullName)' overgeslagen: $msg"
            if ($null -ne $SkippedFile) { $SkippedFile.Add($f.Name) }
            continue
        }
        try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($line.Length -eq 0) { continue }
            if ($line[0] -eq '#') {
                if ($line.StartsWith('#Fields:')) {
                    $header = $line.Substring(8).Trim()
                    $fast = ($header -eq $expected)
                    $index = @{}
                    $names = $header.Split(',')
                    for ($n = 0; $n -lt $names.Count; $n++) { $index[$names[$n].Trim()] = $n }
                }
                continue
            }

            if ($fast) {
                # Standaardvolgorde: de eerste zeven velden bevatten geen komma's, data en context wel mogelijk.
                $p = $line.Split([char[]]@(','), 8)
                if ($p.Count -lt 8) { continue }
                $evt = $p[6]
                $rest = $p[7]
                # Snel overslaan wat niet nodig is: de meeste regels zijn serverantwoorden.
                if ($evt -eq '>' -and -not ($rest.StartsWith('250 2.6.0', [System.StringComparison]::Ordinal) -or $rest.StartsWith('"250 2.6.0', [System.StringComparison]::Ordinal))) { continue }
                if ($evt -eq '*' -and $rest.IndexOf('authenticated', [System.StringComparison]::Ordinal) -lt 0) { continue }
                $dateText = $p[0]; $connector = $p[1]; $sessionId = $p[2]; $local = $p[4]; $remote = $p[5]
                if ($rest.Length -gt 0 -and $rest[0] -eq '"') {
                    $fields = ConvertFrom-DxCsvLine -Line $rest
                    $data = $fields[0]
                    $context = if ($fields.Count -gt 1) { $fields[1] } else { '' }
                }
                else {
                    $c = $rest.IndexOf(',')
                    if ($c -ge 0) { $data = $rest.Substring(0, $c); $context = $rest.Substring($c + 1).Trim('"') }
                    else { $data = $rest; $context = '' }
                }
            }
            else {
                if (-not $index) { continue }
                $fields = ConvertFrom-DxCsvLine -Line $line
                $get = { param($name) if ($index.ContainsKey($name) -and $index[$name] -lt $fields.Count) { $fields[$index[$name]] } else { '' } }
                $dateText = & $get 'date-time'; $connector = & $get 'connector-id'; $sessionId = & $get 'session-id'
                $local = & $get 'local-endpoint'; $remote = & $get 'remote-endpoint'; $evt = & $get 'event'
                $data = & $get 'data'; $context = & $get 'context'
            }

            if (-not $sessionId) { continue }
            $key = "$ServerLabel|$sessionId"
            $s = $sessions[$key]
            if (-not $s) {
                $time = [datetime]::MinValue
                if (-not [datetime]::TryParse($dateText, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$time)) { continue }
                $s = @{
                    Server     = $ServerLabel
                    Session    = $sessionId
                    Start      = $time.ToLocalTime()
                    End        = $time.ToLocalTime()
                    Connector  = $connector
                    Local      = $local
                    Remote     = $remote
                    Ehlo       = ''
                    AuthMethod = ''
                    AuthUser   = ''
                    Tls        = $false
                    AnonymousTls = $false
                    Senders    = New-Object System.Collections.Generic.List[string]
                    Recipients = New-Object System.Collections.Generic.List[string]
                    Messages   = 0
                }
                $sessions[$key] = $s
            }

            if ($evt -eq '<') {
                if ($data.StartsWith('EHLO ', [System.StringComparison]::OrdinalIgnoreCase) -or $data.StartsWith('HELO ', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $s.Ehlo = $data.Substring(5).Trim()
                }
                elseif ($data.StartsWith('MAIL FROM:', [System.StringComparison]::OrdinalIgnoreCase)) { $s.Senders.Add((Get-DxEmailAddress -Command $data)) }
                elseif ($data.StartsWith('RCPT TO:', [System.StringComparison]::OrdinalIgnoreCase)) { $s.Recipients.Add((Get-DxEmailAddress -Command $data)) }
                elseif ($data.StartsWith('STARTTLS', [System.StringComparison]::OrdinalIgnoreCase)) { $s.Tls = $true }
                elseif ($data.StartsWith('X-ANONYMOUSTLS', [System.StringComparison]::OrdinalIgnoreCase)) {
                    # Exchange-servers onderling
                    $s.Tls = $true
                    $s.AnonymousTls = $true
                }
                elseif ($data.StartsWith('AUTH ', [System.StringComparison]::OrdinalIgnoreCase) -or $data.StartsWith('X-EXPS ', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $s.AuthMethod = ($data -split '\s+')[1].ToUpper()
                }
            }
            elseif ($evt -eq '*') {
                if ($context -eq 'authenticated' -and $data) { $s.AuthUser = $data }
            }
            elseif ($evt -eq '>') {
                if ($data.StartsWith('250 2.6.0', [System.StringComparison]::Ordinal)) { $s.Messages++ }
            }

            # Eindtijd bijwerken bij het einde van de sessie en bij elk geaccepteerd bericht.
            if ($evt -eq '-' -or ($evt -eq '>' -and $data.StartsWith('250 2.6.0', [System.StringComparison]::Ordinal))) {
                $t = [datetime]::MinValue
                if ([datetime]::TryParse($dateText, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$t)) {
                    $s.End = $t.ToLocalTime()
                }
            }
        }
        }
        catch {
            Write-Warning "Logbestand '$($f.FullName)' niet volledig gelezen: $($_.Exception.Message)"
            if ($null -ne $SkippedFile) { $SkippedFile.Add($f.Name) }
        }
        finally {
            $reader.Dispose()
        }
    }
    Write-Progress -Activity 'SMTP-protocollogs lezen' -Completed

    foreach ($s in $sessions.Values) {
        if ($s.Start -lt $Start -or $s.Start -gt $End) { continue }
        [pscustomobject]$s
    }
}

function Test-DxPrivateAddress {
    <#
    .SYNOPSIS
        Geeft $true voor prive-, loopback- en link-local-adressen (RFC 1918, 127/8, 169.254/16, fc00::/7, fe80::/10, ::1).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyString()]
        [string]$Address
    )

    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) { return $false }
    if ([System.Net.IPAddress]::IsLoopback($ip)) { return $true }
    $b = $ip.GetAddressBytes()
    if ($ip.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return ($b[0] -eq 10) -or ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -or ($b[0] -eq 192 -and $b[1] -eq 168) -or ($b[0] -eq 169 -and $b[1] -eq 254)
    }
    (($b[0] -band 0xFE) -eq 0xFC) -or ($b[0] -eq 0xFE -and ($b[1] -band 0xC0) -eq 0x80)
}

function Test-DxInternalRecipient {
    <#
    .SYNOPSIS
        Bepaalt of een adres bij een eigen (accepted) domein hoort. Ondersteunt '*.domein.nl'.
        Geeft $null als er geen domeinen bekend zijn.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Address,

        [string[]]$Domain
    )

    if (-not $Domain -or $Domain.Count -eq 0) { return $null }
    $at = $Address.LastIndexOf('@')
    if ($at -lt 0) { return $true }
    $d = $Address.Substring($at + 1).ToLower()
    foreach ($candidate in $Domain) {
        $c = $candidate.ToLower().Trim()
        if (-not $c) { continue }
        if ($c.StartsWith('*.')) {
            $suffix = $c.Substring(1)
            if ($d.EndsWith($suffix) -or $d -eq $c.Substring(2)) { return $true }
        }
        elseif ($d -eq $c) { return $true }
    }
    $false
}

function Get-DxRelayClientType {
    <#
    .SYNOPSIS
        Deelt een SMTP-client in: Exchange-server, Exchange Online, intern (applicatie/apparaat) of extern.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string]$Address,

        [AllowEmptyString()]
        [string]$HostName = '',

        [string[]]$ExchangeAddress = @(),

        # Sessie via poort 2525 of met X-ANONYMOUSTLS: verkeer tussen Exchange-servers.
        [switch]$ExchangeHop
    )

    if ($ExchangeHop -or $ExchangeAddress -contains $Address -or $Address -eq '127.0.0.1' -or $Address -eq '::1') { return 'Exchange-server' }
    if ($HostName -match '(\.|^)(outbound\.protection\.outlook\.com|protection\.outlook\.com|prod\.outlook\.com|outlook\.com)$') { return 'Exchange Online' }
    if (Test-DxPrivateAddress -Address $Address) { return 'Intern (applicatie/apparaat)' }
    'Extern (internet)'
}

function Resolve-DxHostName {
    <#
    .SYNOPSIS
        Zoekt de DNS-naam bij een IP-adres (reverse lookup); leeg als dat niet lukt.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Address
    )

    try { [System.Net.Dns]::GetHostEntry($Address).HostName } catch { '' }
}
