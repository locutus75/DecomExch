function Open-DxHttpListener {
    <#
    .SYNOPSIS
        Start een HttpListener op localhost. Is de gevraagde poort bezet (bijv. door een
        webinterface die nog in een ander venster draait), dan wordt de volgende poort geprobeerd.
        Geeft de listener en de gebruikte poort terug.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1024, 65535)]
        [int]$Port,

        [ValidateRange(1, 100)]
        [int]$MaxAttempts = 10
    )

    $lastError = $null
    $lastPort = [math]::Min(65535, $Port + $MaxAttempts - 1)
    for ($candidate = $Port; $candidate -le $lastPort; $candidate++) {
        # Een HttpListener is na een mislukte Start() niet meer bruikbaar; per poort een nieuwe.
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://localhost:$candidate/")
        try {
            $listener.Start()
        }
        catch {
            $lastError = $_.Exception.Message
            try { $listener.Close() } catch { }
            continue
        }

        if ($candidate -ne $Port) {
            Write-DxLog -Level Warning -Message ("Poort $Port is bezet (draait er nog een DecomExch-webinterface in een ander venster? " +
                "Sluit die met de knop Afsluiten). Poort $candidate wordt gebruikt.")
        }
        return [pscustomobject]@{ Listener = $listener; Port = $candidate }
    }

    throw ("Kan de webinterface niet starten: de poorten $Port t/m $lastPort zijn bezet of niet beschikbaar ($lastError). " +
        'Sluit andere DecomExch-vensters, of kies een andere poort met -Port.')
}
