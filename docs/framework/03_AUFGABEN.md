# Aufgabenliste

> Stand Release **v1.0.0** (02.11.2026). Offene Pakete sind die Roadmap für folgende Releases; bekannte Einschränkungen stehen im `CHANGELOG.md`.

Status: `OPEN` · `IN_PROGRESS` · `BLOCKED` · `REVIEW` · `TESTING` · `DONE` (`DONE` erst nach nachgewiesener Prüfung)
Prioritäten: P1 Sicherheit/kritische Fehler · P2 Architektur-Blocker · P3 Stabilität · P4 Core · P5 Datenintegrität · P6 Tools · P7 UI · P8 Komfort

## Arbeitspaket WP-01 – Korrektheit gegen TTT2 0.14.6b (Phase 2, Start)

| ID | Prio | Aufgabe | Dateien | Akzeptanzkriterium | Test | Status |
|---|---|---|---|---|---|---|
| T-010 | P1 | BUG-01 Hacker-Shop: `shopFallback = "traitor"` | `roles/hacker/shared.lua` | Hacker öffnet den Traitor-Shop | Integration: Rolle erzwingen, Shop öffnen | REVIEW |
| T-011 | P1 | BUG-02 `!roundrestart` über `admin.RoundRestart()` | `lmnt_ttt/sh_commands.lua` | Runde startet neu | Integration (Konsole) | REVIEW |
| T-012 | P3 | BUG-03 Chat-Tags ohne Bruch der TTT2-Chatlogik | `admin/cl_admin.lua` | Polizei-Rolle und `unknownTeam` verhalten sich wie in TTT2 | manuell (Client) | REVIEW |
| T-013 | P3 | BUG-04 Narr-Sieg über `TTT2PreWinChecker` | `roles/narr/shared.lua` | Narr-Tod durch Spieler beendet die Runde mit Sieg „narrs“ | Integration mit Bots | REVIEW |
| T-014 | P3 | BUG-05 Scheinfelder entfernen, echte Score-Felder nutzen | 3 Rollen | nur Felder aus `ttt_role_base` | Code-Review gegen Quelle | REVIEW |
| T-015 | P3 | BUG-06 Sprachschlüssel korrigieren, `info_popup_*` ergänzen | `terrortown/lang/*` | Rollen-Popup erscheint | manuell (Client) | REVIEW |
| T-016 | P3 | BUG-07 BSP-Namen | `workshop.json`, `mapcycle.txt` | Name aus GMA gelesen | Werkzeug | DONE |
| T-017 | P3 | Server-Integrationstest: Boot mit TTT2 + LMNT, Bots, `-condebug`, keine Lua-Fehler | – | Log ohne `[ERROR]` aus lmnt_* | Server-Start | DONE – 02.11.2026: Boot, 10 Bots, Runde mit Spezialrunde, Rundenende, Stats-Vergabe, 0 LMNT-Lua-Fehler |

## WP-02 – Repository und Sicherheit der Geheimnisse

| ID | Prio | Aufgabe | Abhängig von | Akzeptanzkriterium | Status |
|---|---|---|---|---|---|
| T-001 | P1 | Git-Repo, `.gitignore` (settings.ini, fastdl/www), `settings.example.ini` | – | keine Geheimnisse versionierbar | DONE (Repo `LMNT-Gaming/Garrys-Mod-TTT`, `settings.example.ini`, `.gitignore`, CI-Prüfung auf Geheimnisse) |
| T-002 | P6 | Testlauf-Skript `tools/test_server.ps1` (Lint → Deploy → Start mit Bots → RCON-Befehle → Log auswerten → Stopp) + `tools/rcon.py` | T-017 | ein Befehl liefert PASS/FAIL | DONE (PASS am 02.11.2026) |
| T-003 | P6 | `tools/lint.ps1`: Syntaxprüfung aller Lua-Dateien im Projekt | – | Exit-Code ≠ 0 bei Fehlern | DONE (40 Dateien, 0 Fehler) |
| T-004 | P6 | `tools/download_workshop.ps1`: Workshop-Items per SteamCMD als GMA auf den Server (ohne Collection und API-Key) | – | 6/6 Items als gültiges GMA (`GMAD`-Header) | DONE |

## WP-03 – Core: Lebenszyklus, Log, Config, Events, Module (Phase 2)

| ID | Prio | Aufgabe | Abhängig von | Akzeptanzkriterium | Status |
|---|---|---|---|---|---|
| T-020 | P2 | `LMNT` Core: SemVer, `RequireVersion`, Boot-Phasen | – | Statusabfrage zeigt Phase und Version | DONE (Unit-Tests, `!status` → 1.1.0 / ready) |
| T-021 | P2 | `LMNT.Log` mit Schweregraden, Größenlimit, Export | T-020 | alte API `LMNT.Log(cat,msg)` bleibt kompatibel (deprecated) | TESTING (läuft im Server, Export noch ungetestet) |
| T-022 | P2 | `LMNT.Settings` (statt Umbau von `LMNT.Config`, ADR-007) mit Schema, Validierung, Overrides, Änderungsprotokoll, Replikation | T-021 | ungültiger Wert → abgelehnt bzw. Default + Warnung | DONE (Unit-Tests; Replikation an Clients manuell offen) |
| T-023 | P2 | `LMNT.Events`: Namensräume, Abbrechbarkeit, Isolation, Timing, Eigentümer | T-021 | Fehler in Listener A stoppt Listener B nicht | DONE (Unit-Tests) |
| T-024 | P2 | `LMNT.Modules`: Abhängigkeiten, Konflikte, Start/Stop, automatische Bereinigung (ADR-006) | T-022, T-023 | Deaktivieren entfernt alle Registrierungen | DONE (Unit-Tests + Integrationstest) |
| T-025 | P4 | Bestehende Features als 7 Module (ttt.base, items, specialrounds, stats, pointshop, moderation, theme) | T-024 | jedes Modul einzeln abschaltbar ohne Lua-Fehler | TESTING – 9/9 Module aktiv, ttt.stats → ttt.pointshop-Kaskade zur Laufzeit geprüft (02.11.2026), Client-Seite manuell offen |
| T-026 | P6 | Unit-Test-Runner (`lmnt test`, ADR-008), im Integrationstest automatisiert | T-020 | Ergebnisse in `TESTS.md` | DONE (31 Tests) |
| T-027 | P3 | Admin-Menü-Tab „Module“ und „Einstellungen“ (grafischer Configurator, Basis für WP-06; `lmnt/services/sv_settingsmenu.lua`, Doku `api/admin-configurator.md`) | T-022, T-024 | Umschalten und Ändern ohne Chatbefehle | TESTING – Code geprüft (Rechte, Rate-Limit, Größe, security-Log), Ingame-Test offen |

## WP-04 – Netzwerk, Rechte, Daten (Phasen 3–4)

| ID | Prio | Aufgabe | Abhängig von | Status |
|---|---|---|---|---|
| T-030 | P1 | `LMNT.Net` mit Schema, Limits, Rate-Limits, Metriken; bestehende Nachrichten umstellen | T-024 | IN_PROGRESS (Session net-wrapper; Umstellung danach zentral) |
| T-031 | P1 | `LMNT.Perms`: registrierte Rechte, CAMI-Privilegien, Deny-by-default, Audit | T-022 | OPEN |
| T-032 | P5 | `LMNT.DB`: Adapter, Transaktionen, Migrationen (`lmnt_schema`) | T-021 | IN_PROGRESS (Session playerdata) |
| T-033 | P5 | `LMNT.PlayerData` + Cache (Dirty-Tracking, gebündeltes Speichern) + Migration der Alt-Tabellen | T-032 | IN_PROGRESS (Session playerdata; Umstellung der Alt-Tabellen danach zentral) |
| T-034 | P4 | `LMNT.TTT2`-Adapter + `LMNT.Roles.Register` (inkl. Timing-Nachweis R-05) | T-024 | OPEN |
| T-035 | P1 | `LMNT.Shop`: Regelschicht über `TTT2CanOrderEquipment` (die Transaktion macht TTT2 selbst, keine Doppelimplementierung); Pointshop-Transaktion in Session pointshop-2 | T-030, T-033 | DONE – Unit-Tests auf dem Server grün (02.11.2026) |

## WP-09 – Anti-Cheat (Modul `anticheat`, serverseitig)

**Grundsatz:** VAC erkennt in GMod nur signaturbekannte Cheats, Lua-Cheats kaum. Clientseitige Erkennung lässt sich immer umgehen. LMNT setzt deshalb auf **Serverautorität und serverseitige Heuristiken**. Heuristiken erzeugen Verdachtsmeldungen mit Belegen für das Team, aber **keine automatischen Banns**, weil Fehlalarme bei Heuristiken unvermeidbar sind.

| ID | Prio | Aufgabe | Abhängig von | Akzeptanzkriterium | Status |
|---|---|---|---|---|---|
| T-090 | P1 | Produktionsstart-Prüfung: `sv_lan 0`, `sv_cheats 0`, `sv_allowcslua 0`, RCON-Passwort ist kein Standardwert (`lmnt/services/sv_startupchecks.lua`, `!securitycheck`). VAC ist in Lua nicht abfragbar → Nachweis über `status` („secure“, am 17.10. bestätigt) | T-020 | eine abweichende Einstellung erzeugt eine `security`-Warnung | TESTING |
| T-091 | P1 | Härtung in `server.cfg`: `sv_cheats 0`, `sv_allowcslua 0` explizit gesetzt | – | Werte stehen in der Config, Test ohne „Unknown command“ | REVIEW |
| T-092 | P1 | Netzwerk-Missbrauch: Flood, Übergröße und ungültige Pakete → `security`-Log, Verdachtspunkte, ab Schwelle Kick (Teil von `LMNT.Net`) | T-030 | Testpakete (Flood, Übergröße, falscher Typ) werden verworfen und protokolliert | OPEN |
| T-093 | P3 | Verdachtssystem: Punkte pro Spieler mit Zeitverfall, Belege (Zeit, Runde, Messwerte), Meldung an Team-Chat und Admin-Menü-Tab „Anti-Cheat“ | T-024, T-031 | Verdachtsfälle sind im Menü einsehbar, Punkte verfallen nach Konfiguration | OPEN |
| T-094 | P3 | Aim-Heuristik: Winkelgeschwindigkeit der Blickrichtung kurz vor einem Treffer („Snap“), Kopfschussquote über viele Runden gegen den Serverdurchschnitt, Treffer ohne Sichtlinie | T-093 | Messwerte werden erfasst. Schwellwerte mit Bots und echten Spielern kalibriert und dokumentiert | OPEN |
| T-095 | P3 | Bewegungs-Heuristik: unmögliche Positionssprünge ohne Teleport-Ursache (Admin-Teleport, TTT-Teleporter ausgenommen), dauerhaft perfektes Bhop-Timing | T-093 | Admin-Teleport und Teleporter erzeugen **keinen** Fehlalarm (Test) | OPEN |
| T-096 | P3 | Exploit-Schutz für LMNT-Features: Shop, Pointshop, Admin- und Menü-Nachrichten nur mit Recht und Rate-Limit, Wertebereiche geprüft | T-030, T-035 | Sicherheitstests aus `04_AKZEPTANZKRITERIEN.md` bestanden | OPEN |
| T-097 | P6 | Doku `SICHERHEIT.md`: Was erkannt wird, was nicht, Fehlalarm-Umgang, Datenschutz (welche Messwerte gespeichert werden und wie lange) | T-093 | Doku vorhanden und mit dem Code abgeglichen | OPEN |

**Bewusst nicht geplant:** clientseitige Anti-Cheat-Scanner (umgehbar, Datenschutzproblem, Leistungskosten) und automatische Banns allein auf Basis von Heuristiken.

## WP-10 bis WP-14 – Integrations-Ökosystem (Konzept: `06_INTEGRATIONEN.md`)

| ID | Prio | Aufgabe | Abhängig von | Akzeptanzkriterium | Status |
|---|---|---|---|---|---|
| T-100 | P2 | **Stufe A:** `LMNT.Integrations` (Register, Detect, Validate, Enable/Disable, GetStatus, 10 Zustände, Nachweisstufen, Vormerkung für Neustart) auf Basis von `LMNT.Modules` | T-024 | fehlendes optionales Addon verhindert den Start nicht; inkompatible Schnittstelle → `INCOMPATIBLE` mit Grund (Unit-Tests) | DONE – Unit-Tests auf dem Server grün (02.11.2026) |
| T-101 | P2 | Erste Integrationen: `ttt2` (Versions- und API-Prüfung), `cami`, `ulx` (nur Erkennung + Konflikt mit LMNT-Admin) | T-100 | Status entspricht der echten Serverumgebung (Integrationstest) | IN_PROGRESS |
| T-102 | P3 | Admin: `!integrations`, `!integration <id> [an\|aus\|pruefen]`, Konfliktübersicht `!conflicts` | T-100 | Übersicht zeigt erkannte, aktive und fehlerhafte Integrationen | IN_PROGRESS |
| T-103 | P3 | Integrationsprofile (`default`, `competitive`, `custom_content`, `performance`, `development`) als validierte Settings-Sätze | T-100, T-022 | Profil setzt nur registrierte Settings, Konflikte werden angezeigt | OPEN |
| T-104 | P3 | Kompatibilitätsmatrix automatisch aus dem Status (`!compatmatrix` → `data/lmnt/compat_matrix.md`, vom Integrationstest nach `docs/framework/KOMPATIBILITAET_AUTO.md` kopiert), manuelle Angaben mit (M) gekennzeichnet | T-100 | Matrix stimmt mit dem Status überein | TESTING |
| T-110 | P2 | **Stufe B:** TTT2-Adapter → 8 Events `lmnt.round.*`, `lmnt.player.*`, `lmnt.shop.purchase` mit Schutz gegen Doppelkauf-Hook und forceHooks (in `lmnt/integrations/sh_ttt2.lua`) | T-100 | jedes TTT2-Ereignis genau einmal übersetzt (Integrationstest) | TESTING |
| T-150 | P7 | LMNT-HUD für TTT2 über das TTT2-HUD-System (ADR-004) | – | Elemente im LMNT-Design, Editor nutzbar, keine Rolleninfo-Lecks | IN_PROGRESS (Session lmnt-hud) |
| T-111 | P2 | `LMNT.Roles.Register` + `LMNT.Items` (bisher T-034/T-035) | T-110 | Beispielrolle/-item laden | OPEN |
| T-112 | P3 | `LMNT.Weapons` Weapon Registry (Modul `ttt.shop`, Erweiterungsordner `lmnt_ttt/weapons/`): Metadaten getrennt von der SWEP, Erkennung (Klasse geladen, Basis `weapon_tttbase`, `Kind`, Modell), Live-Werte aus TTT2 nur lesend, Doppelregistrierung abgelehnt, `!weapons`/`!weapon` | T-110 | fehlendes Modell/Icon → Warnung, kein Absturz | DONE – Unit-Tests auf dem Server grün (02.11.2026) |
| T-113a | P4 | Content: 6 neue Waffen (Session neue-waffen), 5 neue Items (Session neue-items), Pointshop 2.0 (Session pointshop-2) | T-112 | je Klasse `Check = ttt2`, Doku in `docs/inhalte/` | IN_PROGRESS |
| T-113 | P3 | Legacy-Kompatibilität (alte TTT-Shopregistrierung `EquipmentItems`, alte Hooks) mit Klassifizierung | T-112 | Klassifizierung je Addon in der Matrix | OPEN |
| T-120 | P3 | **Stufe C:** `LMNT.Maps` (Modul `ttt.maps`: Registry aus workshop.json + echte BSP-Prüfung, Map-Profile mit Overrides, Absturz-Journal, keine Überschreibung von Admin-Änderungen; Doku `api/maps.md`) | T-100 | Mapwechsel hinterlässt keine Profilzustände (Test) | DONE – Tests auf dem Server grün (02.11.2026) |
| T-121 | P4 | Punkte-/Zonen-API, Entity-Integration, Gameplay-Event-Modell (`player.damage/heal/revive`, `weapon.*`, `map.change`) mit Doppelverarbeitungsschutz | T-110, T-120 | jedes externe Ereignis genau einmal | OPEN |
| T-122 | P6 | Bewegungs- und Umwelt-Integrationen (optional, einzeln) | T-121 | Effekte enden spätestens mit dem Rundenende | OPEN |
| T-130 | P3 | **Stufe D:** gemäß ADR-011 (LMNT führend): einmalige Migration aus ULib (Ränge, Banns) mit Probelauf, Gruppen-Zuordnung und ohne Herabstufung oder Owner-Vergabe; Konfliktmeldung bei installiertem Fremd-Admin-Mod | T-101 | Probelauf zeigt den vollständigen Plan ohne Schreibzugriff, Ausführung protokolliert jede Änderung (Unit-Tests mit ULib-Beispieldaten; echter ULX-Test erst mit installiertem ULX) | IN_PROGRESS |
| T-131 | P4 | Zentraler HTTP-Service (`LMNT.HTTP`): Timeouts, Retries, Rate-Limits, Payload-Grenzen, Secrets nur in `data/lmnt/secrets.json`, Wächter für hängende Anfragen; Discord-Webhook für `security`-Logs (nur echte Webhook-URLs); Doku `api/http.md` | T-100 | Ausfall des Dienstes blockiert nichts (Test mit unerreichbarem Endpunkt) | DONE – Tests auf dem Server grün (02.11.2026) |
| T-132 | P6 | Monitoring/Serverstatus-Endpunkt, externe Statistiken | T-131 | – | OPEN |
| T-140 | P6 | **Stufe E:** SDK-Doku + 7 Vorlagen (Addon, Waffe, Rolle, Map, Admin-System, externe API, optionale Abhängigkeiten), ladbar oder als schematisch gekennzeichnet | T-100–T-131 | jede Vorlage lädt im Testserver | OPEN |
| T-141 | P6 | Integrations-Testsystem: statisch / simuliert / echt im Server getrennt ausgewiesen | T-100 | Bericht je Integration | OPEN |
| T-142 | P6 | Admin-Menü-Bereich „Integrationen“ (Übersicht, Detail, Aktionen) | T-027, T-102 | keine Installation/Dateiänderung möglich | OPEN |

~~Offene Frage F-07~~ → **entschieden am 17.10.2026: LMNT-Admin bleibt dauerhaft führend** (ADR-011).

## WP-05 bis WP-08 (Phasen 4–8, Feinplanung nach WP-04)

Progression (XP-Kurve konfigurierbar, Anti-AFK, Audit für Admin-Korrekturen), Statistik mit KDA/Assists und Saisons, Perks, Achievements, Aufgaben, Prestige · Design-Tokens und Schriften, Komponentenbibliothek, F-Menü-Shell, HUD-Elemente über TTT2-`hudelements`, Scoreboard-Spalten-API · Ingame-Configurator, DevTools, kontrolliertes Hot-Reload · Integrations- und Regressionstests, Performance-Messungen, Release-Paket.
