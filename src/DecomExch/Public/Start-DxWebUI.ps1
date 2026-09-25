function Start-DxWebUI {
    <#
    .SYNOPSIS
        Start de webinterface van DecomExch in de browser.
    .DESCRIPTION
        Start een lokale webserver (alleen bereikbaar via http://localhost) en opent de
        interface in de standaardbrowser. Elke sessie krijgt een eigen geheim token dat in
        de link zit; andere websites of gebruikers kunnen de interface daardoor niet aansturen.

        De webserver draait in deze PowerShell-sessie en gebruikt de Exchange-verbinding
        van deze sessie. Stoppen: Ctrl+C in de console, of de knop 'Afsluiten' in de interface.
    .EXAMPLE
        Start-DxWebUI
    .EXAMPLE
        Start-DxWebUI -Port 9000 -OutputPath D:\DecomExch -NoBrowser
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1024, 65535)]
        [int]$Port = 8765,

        [string]$OutputPath = (Join-Path -Path (Get-Location).ProviderPath -ChildPath 'Output'),

        [switch]$NoBrowser
    )

    $webRoot = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Web'
    if (-not (Test-Path -LiteralPath (Join-Path $webRoot 'index.html'))) {
        throw "Bestanden van de webinterface niet gevonden in '$webRoot'."
    }
    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force -WhatIf:$false -Confirm:$false | Out-Null
    }
    if (-not $script:DxLogFile) {
        Set-DxLogFile -Path (Join-Path -Path $OutputPath -ChildPath 'Logs') | Out-Null
    }

    $state = @{
        Token      = [guid]::NewGuid().ToString('N')
        OutputPath = (Resolve-Path -Path $OutputPath).ProviderPath
        Stop       = $false
    }

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    try {
        $listener.Start()
    }
    catch {
        throw "Kan de webinterface niet starten op poort ${Port}: $($_.Exception.Message). Kies een andere poort met -Port."
    }

    $url = "http://localhost:$Port/?token=$($state.Token)"
    Write-DxLog -Level Success -Message 'Webinterface gestart.'
    Write-Host ''
    Write-Host "  DecomExch webinterface: $url" -ForegroundColor Cyan
    Write-Host '  Deze link bevat een geheim sessietoken; deel hem niet.' -ForegroundColor DarkGray
    Write-Host '  Stoppen: Ctrl+C of de knop Afsluiten in de interface.' -ForegroundColor DarkGray
    Write-Host ''

    if (-not $NoBrowser) {
        try { Start-Process -FilePath $url } catch { Write-DxLog -Level Warning -Message "Browser kon niet automatisch worden geopend; open de link handmatig." }
    }

    try {
        while ($listener.IsListening -and -not $state.Stop) {
            $pending = $listener.BeginGetContext($null, $null)
            # Kort wachten in een lus, zodat Ctrl+C blijft werken.
            while (-not $pending.AsyncWaitHandle.WaitOne(300)) { }
            $context = $listener.EndGetContext($pending)
            Invoke-DxWebRequest -Context $context -State $state -WebRoot $webRoot
        }
    }
    finally {
        $listener.Stop()
        $listener.Close()
        Write-DxLog -Level Success -Message 'Webinterface gestopt.'
    }
}
