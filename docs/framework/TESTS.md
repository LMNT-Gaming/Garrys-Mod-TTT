# Testprotokoll

## Werkzeuge

| Werkzeug | Zweck |
|---|---|
| `tools\lint.ps1` | Syntaxprüfung aller Lua-Dateien (luaparse, Lua 5.1) |
| `tools\test_server.ps1` | Integrationstest: Lint → Deploy → srcds mit `-condebug` → RCON-Befehle und Bots → Log-Auswertung (Pflichtmeldungen, Lua-Fehler, unbekannte ConVars) → PASS/FAIL |
| `tools\rcon.py` | RCON-Client für Tests und Administration |

## Läufe

### 02.11.2026 – Release-Prüfung v1.0.0 (TTT2 0.14.6b, GMod 10175)

| Prüfung | Ergebnis | Nachweis |
|---|---|---|
| Lint, 110 Lua-Dateien | ✅ 0 Fehler | `lint.ps1` |
| Boot mit TTT2, Phase `ready`, 9/9 Module aktiv | ✅ | `lmnt status`, `lmnt modules` |
| Unit-Tests auf dem Server | ✅ 244 bestanden, 0 fehlgeschlagen | `lmnt test` |
| TTT2-Integrationstests, Konflikte, Kompatibilitätsmatrix | ✅ | `lmnt integration ttt2 test`, `KOMPATIBILITAET_AUTO.md` |
| Modul-Umschaltung zur Laufzeit (`ttt.stats` aus → Kaskade `ttt.pointshop`, wieder an) | ✅ 10 bzw. 8 Registrierungen entfernt und wiederhergestellt | `lmnt logs` |
| Rundenablauf mit 10 Bots, Spezialrunde „Kettenreaktion“, `slay *`, Rundenende, Stats, `roundrestart` | ✅ | console.log |
| Sicherheitsprüfung beim Start | ✅ 5/5 | `startcheck`-Log |
| LMNT-Lua-Fehler im console.log | ✅ keine (alle `[ERROR]`-Zeilen stammen aus absichtlichen Negativtests) | `test_server.ps1` → **PASS** |
| Nicht ausgeführt | Rollen und UI mit echten Clients (siehe Einschränkungen im CHANGELOG) | – |

### 17.10.2026 – Integration Boot und Client (TTT2 0.14.6b, GMod 2026.04.29 / 10175)

| Prüfung | Ergebnis | Nachweis |
|---|---|---|
| Lint, 40 Lua-Dateien | ✅ 0 Fehler | `lint.ps1` |
| Server bootet mit TTT2 statt klassischem TTT | ✅ „This is [TTT2] … (v0.14.6b)“ | console.log |
| LMNT-Module core, admin, ttt laden | ✅ ohne Lua-Fehler | console.log |
| Workshop-Registrierung (TTT2 + aktuelle Map) | ✅ 2 Einträge | console.log |
| FastDL-Registrierung und Auslieferung | ✅ 3 Dateien, HTTP 200 für `.wav.bz2` und `/loading/` | console.log, HTTP-Abruf |
| server.cfg ohne unbekannte ConVars | ✅ nach Korrektur (vorher 3 klassische TTT-ConVars) | console.log |
| **Echter Client verbindet und lädt alles** | ✅ | Spieler „Freadeax“ betreten 17:11 und erneut nach dem Neustart, Rückmeldung des Betreibers |
| Owner-Bootstrap über `C.Owners` | ✅ `lmnt who` → `[Owner] Freadeax` | RCON |
| Stats-DB und Startguthaben | ✅ `lmnt top` → Lvl 1, 100 Pkt | RCON |
| Admin-Befehle als Konsole (who, regeln, special, top, Fehlermeldungen) | ✅ | RCON |
| VAC im Produktionsstart | ✅ `status` → „secure“ | RCON |
| Rundenablauf mit Bots, Tod, Rundenende, Stats-Vergabe | ⏳ **nicht ausgeführt**, weil RCON beim Lauf noch defekt war → nächster `test_server.ps1`-Lauf | – |
| Rollen ingame (Narr-Sieg, Hacker-Shop, Medigun, Tablet) | ⏳ **nicht ausgeführt** (braucht Spieler oder Rollen-Erzwingung) | – |
| UI (Admin-Menü, Pointshop, HUD) | ⏳ **nicht ausgeführt** (manuell durch den Betreiber) | – |

### 17.10.2026 – Manueller Ingame-Test durch den Betreiber (1 Client + 5 Bots)

| Prüfung | Ergebnis |
|---|---|
| Chat-Tags `[Owner] [Lvl 1]`, `*TOT*`, `!regeln`, `@Team-Chat` | ✅ |
| Admin-Menü: Spieler, Befehle (announce), Godmode, Logs | ✅ |
| Pointshop: Öffnen, Fehlermeldung bei zu wenig Punkten, `!points`, Kauf (Modell, Hut, Spur), Verkauf (50 %) | ✅ |
| Pointshop-Vorschau | ❌ Figuren abgeschnitten → Kamera-Framing neu berechnet (`frameModel`), **erneut zu prüfen** |
| Spezialrunden: `!special`, `!special mond`, Rundenstart mit Bots, Effekt | ✅ („Gamemodes funktionieren“) |
| XP-Leiste | ✅ |
| Ladebildschirm | ❌ nicht sichtbar beim ersten Connect (FastDL-Server lief noch nicht) → neu gestaltet, **erneut zu prüfen** |
| Menüs im LMNT-Look | ❌ nicht markenkonform → Designsystem umgesetzt (siehe unten), **erneut zu prüfen** |

### 17.10.2026 – LMNT-Designsystem live

| Änderung | Status |
|---|---|
| Marken-Tokens in `LMNT.Config.Colors`, Schriften Archivo Black und DM Sans (statische TTF, OFL) per FastDL | implementiert, Server findet die Schriftdateien (`file.Exists` = true) |
| UI-Bibliothek neu: Frame mit Raster und Glow, Buttons (primary/ghost/danger), TextEntry, Listen, Scrollbars, Combo, nummerierte Tabs, LMNT-Dialoge (Prompt/Confirm/Alert), Toasts, Ankündigung | implementiert, Lint grün, **Sichtprüfung offen** |
| Admin-Menü, Pointshop, Spezialrunden-Banner (jetzt unterhalb des TTT2-Timers), Level-up, XP-Leiste | implementiert, **Sichtprüfung offen** |
| TTT2-Skin `lmnt_ttt2` (F1-Menü), wird beim ersten Besuch einmalig gewählt | implementiert, **Sichtprüfung offen** |
| Ladebildschirm im Website-Stil mit lokal ausgelieferten Schriften | im Browser geprüft ✅, ingame offen |

### Gefundene Umgebungsbesonderheiten (dokumentiert, mit Workaround)

| Thema | Befund | Lösung |
|---|---|---|
| Lose `.gma` in `addons/` | werden vom Dedicated Server **nicht** geladen („Mounted 0 of 0“) | `tools\gma_extract.py` entpackt in Ordner |
| Legacy-Workshop-Dateien | LZMA ohne Endmarker | `LZMADecompressor` statt `lzma.decompress` |
| Port 27015 auf `127.0.0.1` | belegt vom **Apple Mobile Device Service** | `RCON_HOST` = LAN-IP in `settings.ini` |
| RCON benötigt `-usercon` | ohne den Parameter ist TCP-RCON aus | in `start.bat` und im Testskript gesetzt |
| GMod schließt die RCON-Verbindung nach jeder Antwort | Leere Ende-Marker-Pakete führen zum Abbruch | eine Verbindung pro Befehl, Ende über Ruhepause erkennen |
| **Engine-Fehler:** RCON-Befehle mit genau 12 Byte werden verworfen | Längen 1–40 getestet, nur 12 betroffen | `rcon.py` hängt ein Leerzeichen an |
| Umlaute in RCON-Antworten | die Engine ersetzt sie durch `�` | kosmetisch, ingame korrekt |
