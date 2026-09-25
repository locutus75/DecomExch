# DecomExch

PowerShell-tool om een bestaande on-premises Exchange-server (2013/2016/2019/SE) te **onderzoeken**,
erover te **rapporteren**, mailboxen en public folders te **exporteren naar PST**, en de server
op te **ruimen** en **veilig uit te faseren**. Werkt vanuit de Exchange Management Shell, met een
interactief menu of volledig via parameters (voor geplande taken).

## Wat kan het?

**Onderzoek en rapportage** (alleen lezen, uitvoer als HTML-rapport + CSV)

| # | Onderdeel |
|---|-----------|
| 1 | **Volledige inventarisatie**: servers, databases, mailboxen per type (incl. arbitration/audit/public folder), mailboxoverzicht, public folders, losgekoppelde mailboxen, aanvragen, migratiebatches, connectors, domeinen, adresbeleid, certificaten, Autodiscover, hybride configuratie. |
| 2 | **Mailboxoverzicht**: per mailbox grootte, aantal items, archief, laatste aanmelding en of de mailbox *inactief* is (standaard > 90 dagen niet aangemeld). |
| 3 | **Public folder-overzicht**: pad, aantal items, grootte, laatste wijziging en mail-enabled adres. |
| 4 | **Uitfaseringscontrole** per server, met per punt *OK / Info / Waarschuwing / Blokkerend* en de oplossing. |

**Exporteren naar PST**

| # | Onderdeel |
|---|-----------|
| 5 | **Mailboxen exporteren**: alle mailboxen, per database of een selectie, optioneel inclusief online archief (`<alias>.pst` en `<alias>_Archief.pst`). |
| 6 | **Public folders exporteren** (met submappen) naar een PST, via Outlook. |
| 7 | **Status van PST-exports** met voortgang per aanvraag. |

**Opruimen** (wijzigt iets, altijd eerst simuleren)

| # | Onderdeel |
|---|-----------|
| 8 | **Logbestanden**: Exchange `Logging`, Search `ETLTraces`/`Logs` en IIS-logs ouder dan N dagen. Transactielogs en databasemappen worden altijd overgeslagen. |
| 9 | **Afgeronde aanvragen**: move-, export-, import- en restore-aanvragen en migratiebatches. Lopende aanvragen worden nooit aangeraakt. |
| 10 | **Losgekoppelde mailboxen** (Disabled/SoftDeleted) definitief verwijderen (onomkeerbaar). |
| 11 | **Verlopen certificaten**. Gekoppelde certificaten en het OAuth-certificaat worden overgeslagen. |

### Controles bij uitfasering

- Laatste Exchange-server in de organisatie? (advies: Exchange Management Tools bij hybride/directory sync)
- DAG-lidmaatschap
- Mailboxdatabases op de server
- Gebruikers-, arbitration-, AuditLog-, AuxAuditLog-, public folder- en health-mailboxen
- Lopende of afgeronde verplaatsaanvragen
- Send connectors waarvan de server (enige) bronserver is
- Eigen (niet-standaard) receive connectors, bijv. relay voor printers/applicaties
- Edge-abonnementen
- Autodiscover SCP (`AutoDiscoverServiceInternalUri`)
- Hybride verzend-/ontvangstservers en remote mailboxen

## Veiligheid

- Het menu start altijd in **simulatiemodus**: exports en opruimacties draaien met `-WhatIf` en tonen
  alleen wat er zou gebeuren.
- Zet je de simulatiemodus uit (`S`), dan moet je elke opruimactie bevestigen door `JA` te typen.
- Bij gebruik via parameters wordt alleen echt geexporteerd of gewijzigd met `-Execute`.
- Alle functies die iets verwijderen of exporteren ondersteunen `-WhatIf` en `-Confirm`.
- Elke sessie schrijft een logbestand naar `Output\Logs`.

## Exporteren naar PST

### Mailboxen

De export gebruikt `New-MailboxExportRequest`: de Exchange-server schrijft de PST zelf weg. Daarom:

1. Maak een share aan, bijv. `\\fs01\pst$`, en geef de groep **Exchange Trusted Subsystem**
   lees- en schrijfrechten (share en NTFS).
2. Ken jezelf de rol **Mailbox Import Export** toe en open daarna de shell opnieuw:
   ```powershell
   New-ManagementRoleAssignment -Role 'Mailbox Import Export' -User beheerder
   ```
3. Gebruik altijd een UNC-pad; een lokaal pad (`D:\PST`) wordt geweigerd.

Tip: gebruik eerst het **mailboxoverzicht** om te zien hoeveel ruimte de export nodig heeft en welke
mailboxen inactief zijn. Volg de voortgang met menu-optie 7 (of `Get-DxPstExportStatus -Wait`) en ruim
afgeronde exportaanvragen daarna op met menu-optie 9.

### Public folders

Exchange heeft geen ondersteunde cmdlet om public folders naar PST te exporteren. DecomExch gebruikt
daarom **Outlook**: er wordt een PST aan het Outlook-profiel gekoppeld, de gekozen mappen worden er
(met submappen) in gekopieerd en de PST wordt weer ontkoppeld.

- Voer dit uit op een werkstation of beheerserver **met Outlook (desktop)**, niet op de Exchange-server.
- Het Outlook-profiel moet van een account zijn met leesrechten op de public folders.
- Exchange-cmdlets zijn hiervoor niet nodig; het menu werkt ook zonder Exchange-verbinding.
- Outlook opent standaard PST-bestanden tot 50 GB; exporteer grote hoeveelheden per map
  (`-PublicFolder '\Afdelingen\Verkoop'`).
- Het kopieren is synchroon en kan bij grote mappen lang duren.

## Vereisten

- Windows PowerShell 5.1 met de Exchange Management Shell, of een remote verbinding (`-ExchangeServer`).
- Rol *Organization Management*.
- Voor het opruimen van logs op een andere server: lokale beheerder op die server (toegang via `\\server\C$`).
- Voor PST-export: zie hierboven (rol *Mailbox Import Export*, share, en Outlook voor public folders).

## Gebruik

```powershell
# Interactief menu (in de Exchange Management Shell)
.\DecomExch.ps1

# Remote verbinden met een Exchange-server
.\DecomExch.ps1 -ExchangeServer ex01.contoso.local

# Inventarisatie en mailboxoverzicht naar een map
.\DecomExch.ps1 -Action Inventory -OutputPath D:\DecomExch
.\DecomExch.ps1 -Action MailboxReport -InactiveDays 180

# Uitfaseringscontrole voor EX01
.\DecomExch.ps1 -Action Readiness -Server EX01

# Mailboxen naar PST: eerst simuleren, daarna echt uitvoeren
.\DecomExch.ps1 -Action ExportMailboxes -PstPath \\fs01\pst$ -IncludeArchive
.\DecomExch.ps1 -Action ExportMailboxes -PstPath \\fs01\pst$ -IncludeArchive -Execute
.\DecomExch.ps1 -Action ExportMailboxes -Mailbox jan@contoso.com, info@contoso.com -PstPath \\fs01\pst$ -Execute
.\DecomExch.ps1 -Action PstStatus

# Public folders naar PST (op een werkstation met Outlook)
.\DecomExch.ps1 -Action ExportPublicFolders -PublicFolder '\' -PstPath D:\PST -Execute

# Logbestanden ouder dan 30 dagen opruimen
.\DecomExch.ps1 -Action CleanLogs -Server EX01 -OlderThanDays 30 -Execute
```

Acties: `Inventory`, `MailboxReport`, `PublicFolderReport`, `Readiness`, `ExportMailboxes`, `ExportPublicFolders`,
`PstStatus`, `CleanLogs`, `CleanRequests`, `CleanDisconnectedMailboxes`, `CleanCertificates`.

De functies zijn ook los te gebruiken als module:

```powershell
Import-Module .\src\DecomExch\DecomExch.psd1
Test-DxDecomReadiness -Server EX01 | Format-Table -AutoSize -Wrap
Get-DxMailboxReport | Where-Object Inactief | Sort-Object GrootteMB -Descending
Get-DxMailboxReport | Where-Object Inactief | Export-DxMailboxToPst -FilePath \\fs01\pst$ -IncludeArchive -WhatIf
Get-DxPstExportStatus -Wait
Remove-DxStaleRequest -IncludeFailed -WhatIf
Get-DxInventory | Export-DxReport -Path D:\DecomExch
```

Tip: plan `CleanLogs` als dagelijkse taak op elke Exchange-server:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\DecomExch\DecomExch.ps1 -Action CleanLogs -Server %COMPUTERNAME% -OlderThanDays 14 -Execute
```

## Stappenplan uitfaseren (samengevat)

1. **Inventarisatie** maken en bewaren als nulmeting; bepaal met het mailbox- en public folder-overzicht
   wat bewaard moet worden.
2. Wat bewaard moet worden maar niet wordt gemigreerd **exporteren naar PST**.
3. **Uitfaseringscontrole** draaien voor de server.
4. Blokkerende punten oplossen: mailboxen/systeemmailboxen verplaatsen, server uit de DAG halen,
   send connectors aanpassen, relay-klanten omzetten, Autodiscover SCP leegmaken.
5. Opruimen: afgeronde aanvragen, losgekoppelde mailboxen, verlopen certificaten, lege databases.
6. DNS (MX, Autodiscover, SPF), firewall/NAT en load balancer bijwerken.
7. Server enkele dagen **uitgeschakeld** laten staan en logs controleren op resterend verkeer.
8. Exchange verwijderen via *Programs and Features* of `Setup.exe /mode:Uninstall
   /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF`.
   Bij de laatste server met hybride/directory sync: niet verwijderen, maar overstappen op de
   Exchange Management Tools.
9. Server uit het domein halen en DNS-records en AD-computeraccount opruimen.

## Tests

De tests gebruiken stubs voor de Exchange-cmdlets en een nagebootste Outlook-omgeving, en draaien dus
zonder Exchange of Outlook (Pester 4.10+ of 5):

```powershell
Invoke-Pester -Path .\tests
```

## Structuur

```
DecomExch.ps1                 Menu en niet-interactieve acties
src/DecomExch/                PowerShell-module
  Public/                     Get-DxInventory, Get-DxMailboxReport, Export-DxMailboxToPst, ...
  Private/                    Hulpfuncties (logging, UNC-paden, ...)
tests/                        Pester-tests en Exchange-stubs
```
