function Get-DxDefaultLogPath {
    <#
    .SYNOPSIS
        Standaardmappen met diagnostische logbestanden van Exchange en IIS (lokale paden op de server).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ComputerName
    )

    $installPath = Get-DxExchangeInstallPath -ComputerName $ComputerName
    Join-Path $installPath 'Logging'
    Join-Path $installPath 'Bin\Search\Ceres\Diagnostics\ETLTraces'
    Join-Path $installPath 'Bin\Search\Ceres\Diagnostics\Logs'
    'C:\inetpub\logs\LogFiles'
}

function Find-DxLogFile {
    <#
    .SYNOPSIS
        Zoekt oude logbestanden in de opgegeven mappen. Transactielogs en databasemappen worden overgeslagen.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string[]]$Path,

        [int]$OlderThanDays = 14,

        [string[]]$Include = @('*.log', '*.blg', '*.etl', '*.txt')
    )

    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    # Namen van ESE-transactielogs/checkpoints: E00.log, E0000001A2B.log, E00tmp.log, E00res00001.jrs, E00.chk
    $transactionLogPattern = '^E[0-9A-F]{2}([0-9A-F]{8,}|tmp|res\d+)?\.(log|jrs|chk)$'

    foreach ($p in $Path) {
        $target = ConvertTo-DxUncPath -Path $p -ComputerName $ComputerName

        if ($target -match '[\\/]Mailbox([\\/]|$)') {
            Write-DxLog -Level Warning -Message "Pad '$target' lijkt een databasemap te zijn en wordt overgeslagen."
            continue
        }
        if (-not (Test-Path -LiteralPath $target)) {
            Write-DxLog -Message "Pad '$target' bestaat niet of is niet bereikbaar; overgeslagen."
            continue
        }

        Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object {
                $file = $_
                ($file.LastWriteTime -lt $cutoff) -and
                ($file.Name -notmatch $transactionLogPattern) -and
                (@($Include | Where-Object { $file.Name -like $_ }).Count -gt 0)
            }
    }
}

function Resolve-DxCredential {
    <#
    .SYNOPSIS
        Geeft de opgegeven inloggegevens terug, of anders die van Connect-DxExchange -Credential.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [pscredential]$Credential
    )

    if ($Credential -and $Credential -ne [pscredential]::Empty) { return $Credential }
    $script:DxCredential
}

function Mount-DxAdminShare {
    <#
    .SYNOPSIS
        Koppelt de administratieve shares (\\server\C$) van een remote server met andere
        inloggegevens, zodat logbestanden als dat account bereikbaar zijn. Geeft de namen van de
        tijdelijke PowerShell-stations terug; ruim ze op met Dismount-DxAdminShare.
        Zonder inloggegevens of voor de lokale computer gebeurt er niets.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$ComputerName,

        [string[]]$Path,

        [AllowNull()]
        [pscredential]$Credential
    )

    if (-not $Credential -or -not $ComputerName) { return }

    $shares = @($Path | ForEach-Object { ConvertTo-DxUncPath -Path $_ -ComputerName $ComputerName } |
        Where-Object { $_ -match '^(\\\\[^\\]+\\[^\\]+)' } | ForEach-Object { $Matches[1] } | Sort-Object -Unique)

    foreach ($share in $shares) {
        $name = 'DxAdm' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        try {
            New-PSDrive -Name $name -PSProvider FileSystem -Root $share -Credential $Credential -ErrorAction Stop -WhatIf:$false -Confirm:$false | Out-Null
            Write-DxLog -Message "Share $share gekoppeld als $($Credential.UserName)."
            $name
        }
        catch {
            Write-DxLog -Level Warning -Message "Share $share kon niet worden gekoppeld als $($Credential.UserName): $($_.Exception.Message)"
        }
    }
}

function Dismount-DxAdminShare {
    [CmdletBinding()]
    param(
        [string[]]$Name
    )

    foreach ($n in $Name) {
        if ($n) { Remove-PSDrive -Name $n -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false }
    }
}

function Remove-DxLogFileSet {
    <#
    .SYNOPSIS
        Verwijdert de gevonden logbestanden per map, met ShouldProcess van de aanroepende functie.
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName,
        [string[]]$Path,
        [int]$OlderThanDays,
        [string[]]$Include,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet
    )

    $candidates = @(Find-DxLogFile -ComputerName $ComputerName -Path $Path -OlderThanDays $OlderThanDays -Include $Include)
    if ($candidates.Count -eq 0) {
        Write-DxLog -Level Success -Message "Geen logbestanden ouder dan $OlderThanDays dagen gevonden."
        return
    }

    $removed = 0
    $failed = 0
    [long]$bytes = 0

    foreach ($group in ($candidates | Group-Object -Property DirectoryName)) {
        $size = ($group.Group | Measure-Object -Property Length -Sum).Sum
        $description = '{0} bestand(en), {1:N1} MB' -f $group.Count, ($size / 1MB)

        if (-not $Cmdlet.ShouldProcess($group.Name, "Verwijderen: $description")) { continue }

        foreach ($file in $group.Group) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false
                $removed++
                $bytes += $file.Length
            }
            catch {
                $failed++
                Write-DxLog -Message "Niet verwijderd (in gebruik?): $($file.FullName) - $($_.Exception.Message)"
            }
        }
        Write-DxLog -Level Action -Message "Opgeruimd in $($group.Name): $description"
    }

    $summary = [pscustomobject]@{
        Gevonden       = $candidates.Count
        Verwijderd     = $removed
        Mislukt        = $failed
        VrijgemaaktMB  = [math]::Round($bytes / 1MB, 1)
    }
    Write-DxLog -Level Success -Message ("Logopruiming: {0} verwijderd, {1} mislukt, {2} MB vrijgemaakt." -f $removed, $failed, $summary.VrijgemaaktMB)
    $summary
}
