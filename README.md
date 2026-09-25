# DecomExch

PowerShell-tool om een bestaande on-premises Exchange-server (2013/2016/2019/SE) **op te ruimen** en
**veilig uit te faseren**. Werkt vanuit de Exchange Management Shell, met een interactief menu of
volledig via parameters (voor geplande taken).

## Wat kan het?

| # | Onderdeel | Wijzigt iets? |
|---|-----------|---------------|
| 1 | **Inventarisatie**: servers, databases, mailboxen per type (incl. arbitration/audit/public folder), losgekoppelde mailboxen, verplaatsaanvragen, migratiebatches, connectors, domeinen, adresbeleid, certificaten, Autodiscover, hybride configuratie. Uitvoer als HTML-rapport + CSV per onderdeel. | Nee |
| 2 | **Uitfaseringscontrole** per server, met per punt *OK / Info / Waarschuwing / Blokkerend* en de oplossing (zie hieronder). | Nee |
| 3 | **Logbestanden opruimen**: Exchange `Logging`, Search `ETLTraces`/`Logs` en IIS-logs ouder dan N dagen. Transactielogs en databasemappen worden altijd overgeslagen. | Ja |
| 4 | **Afgeronde aanvragen opruimen**: move-, export-, import- en restore-aanvragen en migratiebatches. Lopende aanvragen worden nooit aangeraakt. | Ja |
| 5 | **Losgekoppelde mailboxen** (Disabled/SoftDeleted) definitief verwijderen. | Ja (onomkeerbaar) |
| 6 | **Verlopen certificaten** verwijderen. Gekoppelde certificaten en het OAuth-certificaat worden overgeslagen. | Ja |

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

- Het menu start altijd in **simulatiemodus**: acties draaien met `-WhatIf` en tonen alleen wat er zou gebeuren.
- Zet je de simulatiemodus uit (`S`), dan moet je elke wijziging bevestigen door `JA` te typen.
- Bij gebruik via parameters wordt alleen echt gewijzigd met `-Execute`.
- Alle functies die iets verwijderen ondersteunen `-WhatIf` en `-Confirm` (ConfirmImpact High).
- Elke sessie schrijft een logbestand naar `Output\Logs`.

## Vereisten

- Windows PowerShell 5.1 met de Exchange Management Shell, of een remote verbinding (`-ExchangeServer`).
- Rol *Organization Management*.
- Voor het opruimen van logs op een andere server: lokale beheerder op die server (toegang via `\\server\C$`).

## Gebruik

```powershell
# Interactief menu (in de Exchange Management Shell)
.\DecomExch.ps1

# Remote verbinden met een Exchange-server
.\DecomExch.ps1 -ExchangeServer ex01.contoso.local

# Inventarisatie naar een map
.\DecomExch.ps1 -Action Inventory -OutputPath D:\DecomExch

# Uitfaseringscontrole voor EX01
.\DecomExch.ps1 -Action Readiness -Server EX01

# Logbestanden ouder dan 30 dagen: eerst simuleren, daarna echt uitvoeren
.\DecomExch.ps1 -Action CleanLogs -Server EX01 -OlderThanDays 30
.\DecomExch.ps1 -Action CleanLogs -Server EX01 -OlderThanDays 30 -Execute
```

Acties: `Inventory`, `Readiness`, `CleanLogs`, `CleanRequests`, `CleanDisconnectedMailboxes`, `CleanCertificates`.

De functies zijn ook los te gebruiken als module:

```powershell
Import-Module .\src\DecomExch\DecomExch.psd1
Test-DxDecomReadiness -Server EX01 | Format-Table -AutoSize -Wrap
Remove-DxStaleRequest -IncludeFailed -WhatIf
Get-DxInventory | Export-DxReport -Path D:\DecomExch
```

Tip: plan `CleanLogs` als dagelijkse taak op elke Exchange-server:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\DecomExch\DecomExch.ps1 -Action CleanLogs -Server %COMPUTERNAME% -OlderThanDays 14 -Execute
```

## Stappenplan uitfaseren (samengevat)

1. **Inventarisatie** maken en bewaren als nulmeting.
2. **Uitfaseringscontrole** draaien voor de server.
3. Blokkerende punten oplossen: mailboxen/systeemmailboxen verplaatsen, server uit de DAG halen,
   send connectors aanpassen, relay-klanten omzetten, Autodiscover SCP leegmaken.
4. Opruimen: afgeronde aanvragen, losgekoppelde mailboxen, verlopen certificaten, lege databases.
5. DNS (MX, Autodiscover, SPF), firewall/NAT en load balancer bijwerken.
6. Server enkele dagen **uitgeschakeld** laten staan en logs controleren op resterend verkeer.
7. Exchange verwijderen via *Programs and Features* of `Setup.exe /mode:Uninstall
   /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF`.
   Bij de laatste server met hybride/directory sync: niet verwijderen, maar overstappen op de
   Exchange Management Tools.
8. Server uit het domein halen en DNS-records en AD-computeraccount opruimen.

## Tests

De tests gebruiken stubs voor de Exchange-cmdlets en draaien dus zonder Exchange (Pester 4.10+ of 5):

```powershell
Invoke-Pester -Path .\tests
```

## Structuur

```
DecomExch.ps1                 Menu en niet-interactieve acties
src/DecomExch/                PowerShell-module
  Public/                     Get-DxInventory, Test-DxDecomReadiness, Clear-DxExchangeLog, ...
  Private/                    Hulpfuncties (logging, UNC-paden, ...)
tests/                        Pester-tests en Exchange-stubs
```
