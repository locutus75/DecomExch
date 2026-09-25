function Export-DxPublicFolderToPst {
    <#
    .SYNOPSIS
        Exporteert public folders (inclusief submappen) naar een PST-bestand via Outlook.
    .DESCRIPTION
        Exchange heeft geen ondersteunde cmdlet om public folders naar PST te exporteren.
        Deze functie gebruikt daarom Outlook (COM): er wordt een PST aan het profiel
        toegevoegd, de gekozen mappen worden erin gekopieerd en de PST wordt weer ontkoppeld.

        Vereisten:
        - Outlook (desktop) op de computer waar dit draait, met een profiel van een account
          dat leesrechten heeft op de public folders (Exchange-cmdlets zijn niet nodig).
        - Voldoende ruimte; Outlook opent standaard PST-bestanden tot 50 GB.
        Het kopieren is synchroon en kan bij grote mappen lang duren.
    .PARAMETER FolderPath
        Een of meer mappen, bijv. '\Afdelingen\Verkoop'. '\' betekent alle mappen op het hoogste niveau.
    .PARAMETER FilePath
        Volledig pad naar het PST-bestand, of een map (dan wordt PublicFolders_<datum>.pst gebruikt).
    .EXAMPLE
        Export-DxPublicFolderToPst -FolderPath '\' -FilePath D:\PST\PublicFolders.pst
    .EXAMPLE
        Export-DxPublicFolderToPst -FolderPath '\Afdelingen\Verkoop', '\Archief' -FilePath D:\PST -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [string[]]$FolderPath = @('\'),

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if ($FilePath -notmatch '\.pst$') {
        $FilePath = Join-Path -Path $FilePath -ChildPath ('PublicFolders_{0}.pst' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    }
    $directory = Split-Path -Path $FilePath -Parent
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force -WhatIf:$false -Confirm:$false | Out-Null
    }
    if ($directory) {
        $FilePath = Join-Path -Path (Resolve-Path -LiteralPath $directory).ProviderPath -ChildPath (Split-Path -Path $FilePath -Leaf)
    }

    $namespace = New-DxOutlookNamespace
    $pfRoot = $namespace.GetDefaultFolder(18)   # olPublicFoldersAllPublicFolders
    if (-not $pfRoot) {
        throw 'Geen public folders zichtbaar in het Outlook-profiel.'
    }

    # Mappen bepalen
    $folders = New-Object System.Collections.Generic.List[object]
    foreach ($path in $FolderPath) {
        if (($path -replace '[\\/]', '') -eq '') {
            foreach ($child in $pfRoot.Folders) { $folders.Add([pscustomobject]@{ Path = '\' + $child.Name; Folder = $child }) }
        }
        else {
            $folders.Add([pscustomobject]@{ Path = '\' + ($path -replace '/', '\').Trim('\'); Folder = (Resolve-DxOutlookFolder -Root $pfRoot -Path $path) })
        }
    }

    $approved = @()
    $results = foreach ($f in $folders) {
        $result = [pscustomobject]@{
            Map     = $f.Path
            Items   = $f.Folder.Items.Count
            Bestand = $FilePath
            Status  = 'Simulatie'
            Fout    = $null
        }
        if ($PSCmdlet.ShouldProcess($f.Path, "Kopieren (met submappen) naar $FilePath")) {
            $approved += , @($f, $result)
        }
        $result
    }

    if ($approved.Count -gt 0) {
        Write-DxLog -Level Action -Message "PST koppelen: $FilePath"
        $namespace.AddStoreEx($FilePath, 3)   # olStoreUnicode
        $store = $null
        foreach ($s in $namespace.Stores) {
            if ($s.FilePath -eq $FilePath) { $store = $s; break }
        }
        if (-not $store) {
            throw "PST '$FilePath' kon niet aan het Outlook-profiel worden toegevoegd."
        }
        $pstRoot = $store.GetRootFolder()

        try {
            foreach ($pair in $approved) {
                $f = $pair[0]; $result = $pair[1]
                try {
                    Write-DxLog -Level Action -Message "Kopieren: $($f.Path) ($($result.Items) items) ..."
                    $f.Folder.CopyTo($pstRoot) | Out-Null
                    $result.Status = 'Geexporteerd'
                }
                catch {
                    $result.Status = 'Mislukt'
                    $result.Fout = $_.Exception.Message
                    Write-DxLog -Level Error -Message "Kopieren van $($f.Path) mislukt: $($_.Exception.Message)"
                }
            }
        }
        finally {
            try { $namespace.RemoveStore($pstRoot) } catch { Write-DxLog -Level Warning -Message "PST kon niet worden ontkoppeld: $($_.Exception.Message)" }
        }
        Write-DxLog -Level Success -Message "Public folder-export afgerond: $FilePath"
    }

    $results
}
