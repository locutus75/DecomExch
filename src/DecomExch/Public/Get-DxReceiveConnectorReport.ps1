function Get-DxReceiveConnectorReport {
    <#
    .SYNOPSIS
        Overzicht van de receive connectors: wie mag verbinden, hoe, en of protocol logging aanstaat.
    .DESCRIPTION
        Protocol logging (ProtocolLoggingLevel Verbose) is nodig om met Get-DxRelayUsage te zien
        wie een connector gebruikt. Per connector staat een advies als logging uit staat of als de
        connector anonieme verbindingen toestaat.
    .EXAMPLE
        Get-DxReceiveConnectorReport | Where-Object Advies | Format-List
    #>
    [CmdletBinding()]
    param(
        [string[]]$Server
    )

    Assert-DxExchangeShell

    if (-not $Server) {
        $Server = @(Get-ExchangeServer | Where-Object { "$($_.ServerRole)" -notmatch 'Edge' } | ForEach-Object { "$($_.Name)" })
    }

    foreach ($srv in $Server) {
        $defaults = @('Default', 'Client Proxy', 'Default Frontend', 'Outbound Proxy Frontend', 'Client Frontend') | ForEach-Object { "$_ $srv" }
        foreach ($rc in @(Get-ReceiveConnector -Server $srv -ErrorAction SilentlyContinue)) {
            $level = if ($rc.PSObject.Properties['ProtocolLoggingLevel']) { "$($rc.ProtocolLoggingLevel)" } else { '' }
            $permissions = if ($rc.PSObject.Properties['PermissionGroups']) { "$($rc.PermissionGroups)" } else { '' }
            $custom = $defaults -notcontains "$($rc.Name)"
            $ranges = if ($rc.PSObject.Properties['RemoteIPRanges']) { @($rc.RemoteIPRanges | ForEach-Object { "$_" }) } else { @() }

            $advice = New-Object System.Collections.Generic.List[string]
            if ($level -and $level -ne 'Verbose') {
                $advice.Add("Zet protocol logging aan om het gebruik te zien (Set-ReceiveConnector -Identity '$($rc.Identity)' -ProtocolLoggingLevel Verbose).")
            }
            if ($custom -and $permissions -match 'AnonymousUsers') {
                $advice.Add('Staat anonieme verbindingen toe (relay). Controleer met Relaygebruik welke applicaties en apparaten deze connector nog gebruiken.')
            }

            [pscustomobject]@{
                Server     = $srv
                Connector  = "$($rc.Name)"
                Eigen      = $custom
                Rol        = if ($rc.PSObject.Properties['TransportRole']) { "$($rc.TransportRole)" } else { '' }
                Bindings   = @($rc.Bindings | ForEach-Object { "$_" }) -join ', '
                ExterneIPs = Join-DxTop -Value $ranges -Top 4
                Rechten    = $permissions
                Aanmelding = if ($rc.PSObject.Properties['AuthMechanism']) { "$($rc.AuthMechanism)" } else { '' }
                Logging    = $level
                Advies     = $advice -join ' '
            }
        }
    }
}
