# Changelog

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionierung nach [SemVer](https://semver.org/lang/de/).
Die Set-Version (`VERSION`) ist unabhängig von der Framework-Version (`LMNT.Version`).

## [Unveröffentlicht]

## [1.0.0] – 2026-11-02

Erstes öffentliches Release des kompletten Sets.

### Enthalten

**LMNT-Framework (`lmnt_core`, Framework 1.2.0)**
- Lebenszyklus mit Boot-Phasen und SemVer-Prüfung (`LMNT.RequireVersion`)
- Module mit Abhängigkeiten, Konflikten und automatischer Bereinigung beim Abschalten (`LMNT.Modules`)
- Einstellungen mit Schema, Validierung, Änderungsprotokoll und Replikation (`LMNT.Settings`), grafischer Configurator im Admin-Menü
- Events mit Namensräumen und Fehlerisolation (`LMNT.Events`), Log mit Schweregraden
- Datenbank mit Transaktionen und Migrationen, `LMNT.PlayerData` mit Cache und gebündeltem Speichern
- Netzwerk-API `LMNT.Net` mit Schema, Größen- und Rate-Limits
- Integrationen (TTT2, CAMI, ULX-Erkennung) mit Status, Konfliktübersicht und automatischer Kompatibilitätsmatrix
- Einmalige Migration aus ULib/ULX (Ränge, Banns) mit Probelauf
- HTTP-Service mit Timeouts und Rate-Limits, optionaler Discord-Webhook für `security`-Logs
- Admin-System: Ränge mit Immunität, 66 Befehle, Banns, Warns, Admin-Menü, Produktionsstart-Sicherheitsprüfung

**TTT2-Inhalte (`lmnt_ttt`)**
- Rollen: Narr, Sanitäter, Hacker
- 11 Waffen: Medigun, Hacker-Tablet, Taser, Giftpfeil, Revolver, Näherungsmine, Giftgasgranate, Wurfmesser, Schutzbarriere, Bewegungsmelder, Pumpgun
- 8 passive Items: Turbo-Schuhe, Fallschutz, Regeneration, Leisetreter, Adrenalin, Explosionsschutz, Energieschild, Lebenszeichen-Monitor
- Shop-Regelschicht (Sperrzeit, Käufe pro Runde) und Waffen-Registry
- 7 Spezialrunden, Level-/XP-System mit Statistik, Pointshop (Modelle, Hüte, Spuren)
- LMNT-HUD für TTT2 und F1-Menü-Skin, Map-Profile mit Absturz-Journal

**Server-Paket**
- Installation, Deploy, Update und Start mit Auto-Neustart (Windows, SteamCMD)
- Zentrale Workshop-Liste für Collection, Client-Downloads und Mapcycle
- FastDL-Builder und Ladebildschirm, synthetisch erzeugte Sounds, Schriften unter OFL
- Lint (`tools/lint.ps1`) und vollautomatischer Integrationstest (`tools/test_server.ps1`) mit 244 Unit-Tests auf echtem srcds

### Geändert gegenüber dem internen Stand
- Owner werden über `OWNERS` in `server/settings.ini` gesetzt (→ `data/lmnt/owners.txt`), nicht mehr fest im Code
- `server/settings.example.ini` als Vorlage; `settings.ini` wird beim ersten Lauf daraus angelegt
- Größenlimit für Admin-Menü-Befehle (`lmnt_admin_run`)

### Geprüft
- Integrationstest am 02.11.2026: TTT2 0.14.6b, GMod 10175, 10 Bots, 9/9 Module aktiv, 244/244 Unit-Tests, TTT2-Adaptertests, Modul-Umschaltung zur Laufzeit, Rundenablauf mit Spezialrunde → **PASS**
- Manueller Ingame-Test (17.10.2026): Chat-Tags, Admin-Menü, Pointshop-Kauf/-Verkauf, Spezialrunden, XP-Leiste

### Bekannte Einschränkungen
- Server-Skripte sind nur für **Windows** ausgelegt (PowerShell, Batch, robocopy).
- Getestet gegen **TTT2 0.14.6b**; andere TTT2-Versionen werden von der TTT2-Integration erkannt, sind aber nicht geprüft.
- Rollen-Icons sind Platzhalter (Innocent-/Traitor-Textur von TTT2).
- Nur mit echten Spielern prüfbar und noch nicht vollständig gesichtet: Narr-Sieg, Hacker-Shop, Medigun/Tablet, Leisetreter, Pointshop-Vorschau, Ladebildschirm ingame, LMNT-HUD.
- Die Anti-Cheat-Heuristiken (WP-09: Verdachtssystem, Aim- und Bewegungsheuristik) sind **nicht** enthalten. Vorhanden sind Serverautorität, Rechte-, Größen- und Rate-Limit-Prüfungen sowie die Sicherheitsprüfung beim Start.
- Die bestehenden Netzwerk-Nachrichten prüfen Rechte und Limits jeweils selbst; die Umstellung auf `LMNT.Net` und CAMI-Privilegien (`LMNT.Perms`) folgt.
- `mysqloo` wird nicht unterstützt, Datenhaltung ausschließlich über SQLite.

[Unveröffentlicht]: https://github.com/LMNT-Gaming/Garrys-Mod-TTT/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/LMNT-Gaming/Garrys-Mod-TTT/releases/tag/v1.0.0
