function Send-DxResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerResponse]$Response,

        [int]$StatusCode = 200,

        [string]$ContentType = 'application/json; charset=utf-8',

        [byte[]]$Bytes = @()
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.Headers['X-Content-Type-Options'] = 'nosniff'
    $Response.Headers['Cache-Control'] = 'no-store'
    $Response.Headers['Referrer-Policy'] = 'no-referrer'
    $Response.Headers['Content-Security-Policy'] = "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'; form-action 'none'"
    $Response.ContentLength64 = $Bytes.Length
    if ($Bytes.Length -gt 0) { $Response.OutputStream.Write($Bytes, 0, $Bytes.Length) }
    $Response.OutputStream.Close()
}

function ConvertTo-DxJsonBytes {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [AllowNull()]
        [object]$Data
    )

    $json = if ($null -eq $Data) { 'null' } else { ConvertTo-Json -InputObject $Data -Depth 8 -Compress }
    , [System.Text.Encoding]::UTF8.GetBytes($json)
}

function Get-DxStaticFile {
    <#
    .SYNOPSIS
        Zoekt een bestand van de webinterface op; paden buiten de webmap worden geweigerd.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$WebRoot,

        [Parameter(Mandatory)]
        [string]$UrlPath
    )

    $relative = [System.Uri]::UnescapeDataString($UrlPath).TrimStart('/')
    if (-not $relative) { $relative = 'index.html' }
    if ($relative -match '(^|[\\/])\.\.([\\/]|$)') { return $null }

    $root = [System.IO.Path]::GetFullPath($WebRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::GetFullPath((Join-Path -Path $root -ChildPath $relative))
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    $full
}

function Invoke-DxWebRequest {
    <#
    .SYNOPSIS
        Handelt een HTTP-verzoek af: API-aanroepen (met token) of bestanden van de webinterface.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter(Mandatory)]
        [string]$WebRoot
    )

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath

    try {
        # Alleen verzoeken aan localhost (bescherming tegen DNS-rebinding).
        $hostName = $request.Url.Host
        if ($hostName -notin 'localhost', '127.0.0.1', '[::1]', '::1') {
            Send-DxResponse -Response $response -StatusCode 403 -Bytes (ConvertTo-DxJsonBytes @{ error = 'Alleen toegankelijk via localhost.' })
            return
        }

        if ($path -like '/api/*') {
            if ($request.Headers['X-DecomExch-Token'] -cne $State['Token']) {
                Send-DxResponse -Response $response -StatusCode 401 -Bytes (ConvertTo-DxJsonBytes @{ error = 'Ongeldig of ontbrekend sessietoken. Open de interface via de link in de PowerShell-console.' })
                return
            }

            $body = $null
            if ($request.HasEntityBody) {
                $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                try { $text = $reader.ReadToEnd() } finally { $reader.Close() }
                if ($text.Trim()) { $body = $text | ConvertFrom-Json }
            }

            $query = @{}
            foreach ($key in $request.QueryString.AllKeys) { if ($key) { $query[$key] = $request.QueryString[$key] } }

            if ($request.HttpMethod -eq 'POST' -and $path -eq '/api/shutdown') {
                $State['Stop'] = $true
                Send-DxResponse -Response $response -Bytes (ConvertTo-DxJsonBytes @{ stopped = $true })
                return
            }

            try {
                $data = Invoke-DxApiRoute -Method $request.HttpMethod -Path $path -Query $query -Body $body -State $State
                Send-DxResponse -Response $response -Bytes (ConvertTo-DxJsonBytes $data)
            }
            catch {
                $exception = $_.Exception
                while ($exception -is [System.Management.Automation.RuntimeException] -and $exception.InnerException) { $exception = $exception.InnerException }
                $status = if ($exception -is [System.ArgumentException]) { 400 }
                          elseif ($exception -is [System.Collections.Generic.KeyNotFoundException]) { 404 }
                          else { 500 }
                if ($status -eq 500) { Write-DxLog -Level Error -Message "Webinterface: $path - $($_.Exception.Message)" }
                Send-DxResponse -Response $response -StatusCode $status -Bytes (ConvertTo-DxJsonBytes @{ error = $_.Exception.Message })
            }
            return
        }

        if ($request.HttpMethod -ne 'GET') {
            Send-DxResponse -Response $response -StatusCode 405
            return
        }

        $file = Get-DxStaticFile -WebRoot $WebRoot -UrlPath $path
        if (-not $file) {
            Send-DxResponse -Response $response -StatusCode 404 -ContentType 'text/plain; charset=utf-8' -Bytes ([System.Text.Encoding]::UTF8.GetBytes('Niet gevonden'))
            return
        }

        $types = @{ '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon' }
        $extension = [System.IO.Path]::GetExtension($file).ToLower()
        $contentType = if ($types.ContainsKey($extension)) { $types[$extension] } else { 'application/octet-stream' }
        Send-DxResponse -Response $response -ContentType $contentType -Bytes ([System.IO.File]::ReadAllBytes($file))
    }
    catch {
        Write-DxLog -Level Error -Message "Webinterface: verzoek $path mislukt: $($_.Exception.Message)"
        try { $response.Abort() } catch { }
    }
}
