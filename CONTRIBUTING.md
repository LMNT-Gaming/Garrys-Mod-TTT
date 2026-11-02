# Mitarbeiten

## Ablauf

1. Fork bzw. Branch von `main` anlegen.
2. Änderungen in kleinen, lauffähigen Schritten committen.
3. Vor dem Pull Request prüfen:
   ```bash
   powershell -ExecutionPolicy Bypass -File tools\lint.ps1
   ```
   Mit lokalem Testserver zusätzlich:
   ```bash
   powershell -ExecutionPolicy Bypass -File tools\test_server.ps1
   ```
   Der Integrationstest startet den Server mit Bots, führt alle Unit-Tests (`lmnt test`) aus und wertet `console.log` aus.
4. `CHANGELOG.md` (Abschnitt „Unveröffentlicht“) und die betroffene Doku in `docs/` anpassen.

## Konventionen

- Lua: Tabs, deutsche Kommentare und Spielertexte, englische Bezeichner.
- Neue Funktionen als **Modul** über `LMNT.Modules` registrieren, damit sie einzeln abschaltbar sind (siehe `docs/ENTWICKLUNG.md`).
- Alles, was Clients schicken, ist nicht vertrauenswürdig: Rechte, Rate-Limits und Wertebereiche serverseitig prüfen (`LMNT.Net`).
- Architekturentscheidungen in `docs/framework/ENTSCHEIDUNGEN.md` festhalten.
- Keine fremden Assets ohne passende Lizenz einchecken.
