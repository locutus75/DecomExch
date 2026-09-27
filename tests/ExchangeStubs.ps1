# Lege stand-ins voor Exchange-cmdlets zodat Pester ze kan mocken op een machine zonder Exchange.
# De parameters komen overeen met wat de module gebruikt.

function global:Get-ExchangeServer { param($Identity, $ErrorAction) }
function global:Get-MailboxDatabase { param($Identity, $Server, [switch]$Status, $ErrorAction) }
function global:Get-Mailbox {
    param($Identity, $Database, $ResultSize, [switch]$Arbitration, [switch]$AuditLog, [switch]$AuxAuditLog,
        [switch]$Monitoring, [switch]$PublicFolder, $ErrorAction)
}
function global:Get-RemoteMailbox { param($ResultSize, $ErrorAction) }
function global:Get-MailboxStatistics { param($Identity, $Database, $ErrorAction) }
function global:Remove-StoreMailbox { param($Database, $Identity, $MailboxState, [switch]$Confirm, $ErrorAction) }
function global:Get-MoveRequest { param($ResultSize, $ErrorAction) }
function global:Remove-MoveRequest { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Get-MigrationBatch { param($ErrorAction) }
function global:Remove-MigrationBatch { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Get-MailboxExportRequest { param($BatchName, $ErrorAction) }
function global:Remove-MailboxExportRequest { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Get-MailboxImportRequest { param($ErrorAction) }
function global:Remove-MailboxImportRequest { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Get-MailboxRestoreRequest { param($ErrorAction) }
function global:Remove-MailboxRestoreRequest { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Get-SendConnector { param($ErrorAction) }
function global:Get-ReceiveConnector { param($Identity, $Server, $ErrorAction) }
function global:Get-DatabaseAvailabilityGroup { param($ErrorAction) }
function global:Get-EdgeSubscription { param($ErrorAction) }
function global:Get-ClientAccessService { param($Identity, $ErrorAction) }
function global:Get-HybridConfiguration { param($ErrorAction) }
function global:Get-ExchangeCertificate { param($Server, $Thumbprint, $ErrorAction) }
function global:Remove-ExchangeCertificate { param($Server, $Thumbprint, [switch]$Confirm, $ErrorAction) }
function global:Get-AuthConfig { param($ErrorAction) }
function global:New-MailboxExportRequest { param($Mailbox, $FilePath, $Name, $BatchName, [switch]$IsArchive, [switch]$Confirm, $ErrorAction) }
function global:Get-MailboxExportRequestStatistics { param($Identity, $ErrorAction) }
function global:Get-PublicFolderStatistics { param($ResultSize, $ErrorAction) }
function global:Get-MailPublicFolder { param($ResultSize, $ErrorAction) }
function global:Get-OrganizationConfig { param($ErrorAction) }
function global:Set-ADServerSettings { param($ViewEntireForest, $ErrorAction) }
function global:Get-MessageTrackingLog { param($Server, $Start, $End, $EventId, $ResultSize, $ErrorAction) }
function global:Get-AcceptedDomain { param($ErrorAction) }
function global:Get-FrontendTransportService { param($Identity, $ErrorAction) }
function global:Get-TransportService { param($Identity, $ErrorAction) }

# Hybride koppeling
function global:Get-OrganizationRelationship { param($ErrorAction) }
function global:Remove-OrganizationRelationship { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Get-IntraOrganizationConnector { param($ErrorAction) }
function global:Remove-IntraOrganizationConnector { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Remove-SendConnector { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Get-RemoteDomain { param($ErrorAction) }
function global:Remove-RemoteDomain { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Set-ReceiveConnector { param($Identity, $TlsDomainCapabilities, [switch]$Confirm, $ErrorAction) }
function global:Get-FederatedOrganizationIdentifier { param($ErrorAction) }
function global:Set-FederatedOrganizationIdentifier { param($Enabled, $DelegationFederationTrust, [switch]$Confirm, $ErrorAction) }
function global:Get-FederationTrust { param($ErrorAction) }
function global:Remove-FederationTrust { param($Identity, [switch]$Confirm, $ErrorAction) }
function global:Get-AuthServer { param($ErrorAction) }
function global:Set-AuthServer { param($Identity, $Enabled, [switch]$Confirm, $ErrorAction) }
function global:Get-PartnerApplication { param($ErrorAction) }
function global:Set-PartnerApplication { param($Identity, $Enabled, [switch]$Confirm, $ErrorAction) }
function global:Set-ClientAccessService { param($Identity, $AutoDiscoverServiceInternalUri, [switch]$Confirm, $ErrorAction) }
function global:Remove-HybridConfiguration { param([switch]$Confirm, $ErrorAction) }
if (-not (Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue)) {
    function global:Resolve-DnsName { param($Name, $Type, [switch]$DnsOnly, $ErrorAction) }
}
