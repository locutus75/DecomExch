function Get-DxMailboxOnDatabase {
    <#
    .SYNOPSIS
        Haalt mailboxen van een bepaald type op een database op.
        Type 'User' zijn normale mailboxen; de overige types zijn systeemmailboxen
        die alleen met een aparte schakelaar van Get-Mailbox zichtbaar worden.
        Onbekende schakelaars (oudere Exchange-versies) leveren niets op.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Database,

        [ValidateSet('User', 'Arbitration', 'AuditLog', 'AuxAuditLog', 'Monitoring', 'PublicFolder')]
        [string]$Type = 'User'
    )

    $params = @{
        Database    = $Database
        ResultSize  = 'Unlimited'
        ErrorAction = 'SilentlyContinue'
    }

    if ($Type -ne 'User') {
        if (-not (Get-Command -Name Get-Mailbox).Parameters.ContainsKey($Type)) {
            return
        }
        $params[$Type] = $true
    }

    Get-Mailbox @params
}
