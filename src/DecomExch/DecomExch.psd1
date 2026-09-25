@{
    RootModule        = 'DecomExch.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = '5b0f6f0e-8f5d-4a55-9d0e-3c1b7b7d2a11'
    Author            = 'DecomExch'
    Description       = 'Onderzoeken, rapporteren, exporteren naar PST, opruimen en uitfaseren van on-premises Exchange servers.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Connect-DxExchange'
        'Get-DxInventory'
        'Get-DxMailboxReport'
        'Get-DxPublicFolderReport'
        'Export-DxMailboxToPst'
        'Get-DxPstExportStatus'
        'Export-DxPublicFolderToPst'
        'Test-DxDecomReadiness'
        'Get-DxLogCleanupCandidate'
        'Clear-DxExchangeLog'
        'Remove-DxStaleRequest'
        'Remove-DxDisconnectedMailbox'
        'Remove-DxExpiredCertificate'
        'Export-DxReport'
        'Set-DxLogFile'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
