# Akzeptanzkriterien

## Reifegrade (werden für jedes Feature getrennt ausgewiesen)

| Grad | Bedeutung | Nachweis |
|---|---|---|
| **implementiert** | Code geschrieben, Syntaxprüfung grün | `tools/lint.ps1` |
| **lokal getestet** | Unit-Tests oder Teilprüfung grün | `lmnt_test`-Ausgabe |
| **integriert getestet** | auf echtem srcds mit TTT2 0.14.6b geprüft (Server-Log, Bots) bzw. manuell mit einem Client | Testprotokoll in `TESTS.md` |
| **produktionsbereit** | integriert getestet, dokumentiert, keine offenen P1/P2-Fehler, Migration erprobt | Release-Notes |

## Definition of Done (pro Aufgabe)

1. Bestehender Code und betroffene TTT2-Stellen wurden gelesen. Genutzte APIs sind mit Fundstelle belegt.
2. Die Akzeptanzkriterien der Aufgabe sind erfüllt und geprüft.
3. Die Syntaxprüfung ist grün, und die relevanten Tests wurden *ausgeführt*. Was nicht ausgeführt werden konnte, ist als „nicht ausgeführt“ markiert.
4. Client-Eingaben werden serverseitig validiert, und Rechte werden auf dem Server geprüft.
5. Die Dokumentation (API-Referenz, Betriebsdoku, Aufgabenliste) ist aktualisiert.
6. Restrisiken sind benannt.

## Release-Kriterien (Auszug aus dem Auftrag, messbar formuliert)

| Kriterium | Prüfung |
|---|---|
| Core initialisiert unter den dokumentierten Voraussetzungen | Serverstart: `lmnt_status` → Phase `ready`, 0 Lua-Fehler im `console.log` |
| Rollen und Items lassen sich über die APIs registrieren | Beispielrolle und Beispielitem aus der Doku laden fehlerfrei. Ungültige Definitionen werden mit Meldung abgelehnt |
| Module sind unabhängig aktivierbar | Jedes Modul einzeln aus → Neustart → keine Fehler. Deaktivieren zur Laufzeit hinterlässt 0 Hooks und Timer des Moduls |
| Rechte werden serverseitig geprüft | Test: jede privilegierte Netzwerknachricht ohne Recht → abgewiesen + `security`-Log |
| Netzwerkdaten werden validiert | Test: übergroße, falsch typisierte und geflutete Pakete werden verworfen |
| DB-Fehler werden behandelt | Test: Abfrage gegen fehlende Tabelle → Fehlerlog, kein Absturz, keine Belohnung ohne Speicherung |
| Persistenz ist konsistent | Test: Kauf, Disconnect, Reconnect → Saldo und Inventar stimmen |
| HUD und Menüs sind an echte Datenquellen gebunden | Checkliste je Element (Datenquelle, Sichtbarkeit, Update-Strategie) |
| Adminänderungen sind validiert und protokolliert | Test: Config-Änderung → Audit-Eintrag mit altem und neuem Wert |
| Reload erzeugt keine Doppelregistrierungen | `lmnt_hooks` vorher und nachher identisch |
| Öffentliche APIs sind dokumentiert | Jede Funktion in `docs/framework/api/` mit Parametern, Rückgabe, Fehlern und Beispiel |
| Bekannte Einschränkungen sind dokumentiert | Abschnitt in den Release-Notes |
