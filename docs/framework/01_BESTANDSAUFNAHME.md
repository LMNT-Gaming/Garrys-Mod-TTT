# Phase 1 – Bestandsaufnahme (Stand 17.10.2026)

## 1. Umgebung (geprüft)

| Komponente | Version / Zustand | Nachweis |
|---|---|---|
| Garry's Mod Dedicated Server | App 4020, installiert unter `F:\LMNT\GModServer\gmod` | `install.ps1` erfolgreich, `srcds.exe` vorhanden |
| CS:S-Inhalte | App 232330, per `mount.cfg` eingebunden | `install.ps1` erfolgreich |
| TTT2 | **0.14.6b** (Workshop 1357204556) | `GM.Version` in `sh_init.lua`, Workshop-API-Titel |
| TTT2-Referenzquellcode | GitHub `TTT-2/TTT2`, Commit `30e6b13` (21.07.2026) | nur lesend im Scratchpad |
| Maps | 5 Maps als GMA im Server, BSP-Namen aus den Paketen gelesen | `download_workshop.ps1` |
| Datenbank | nur SQLite (`sql.*`, **synchron**). Das MySQL-Modul `mysqloo` ist **nicht** installiert | `garrysmod/lua/bin` existiert nicht |
| Lua-Tooling | `luaparse` 0.3.1 (Lua 5.1) für Syntaxprüfung, Node 24.18, Python 3.14 | Scratchpad |

## 2. Repository-Struktur (Ist)

```
garrysmod/addons/lmnt_core   LMNT-Core: Config, Util, Chat, SQLite-Wrapper, Logs, Downloads, UI, Admin (14 Lua-Dateien)
garrysmod/addons/lmnt_ttt    TTT2-Inhalte: 3 Rollen, 3 Items, 5 Waffen, Spezialrunden, Stats/Level, Pointshop, TTT-Befehle (26 Lua-Dateien)
server/                      install, deploy, update, start, settings.ini
tools/                       workshop-Prüfung, Workshop-Download, FastDL-Build/-Server, Sounds, Firewall
fastdl/                      Ladebildschirm
docs/                        Betriebsdokumentation
```

Kein Git-Repository vorhanden (siehe Aufgabe T-001).

## 3. Vorhandene Schnittstellen

| Bereich | Ist-Zustand | Bewertung für das Zielbild |
|---|---|---|
| Laden | `LMNT.LoadModule(name, files)`, Präfix-basierter Realm | gut, aber **keine** Abhängigkeiten, Versionen, Deaktivierung oder Bereinigung |
| Konfiguration | Lua-Tabellen (`LMNT.Config`, `LMNT.TTT.Config`) | keine Validierung, keine Ingame-Änderung, keine Overrides |
| Events | direkte `hook.Add`-Aufrufe verteilt in allen Dateien | keine Namensräume, keine Fehlerisolation, kein Lebenszyklus |
| Netzwerk | `util.AddNetworkString` + `net.*` je Datei, eigene Rate-Limits pro Nachricht | uneinheitlich, ohne Schema, Größenlimits und Metriken |
| Datenbank | `LMNT.DB.Query` mit sicherer `?`-Bindung | sicher, aber ohne Migrationen, Transaktionen oder Adapter |
| Spielerdaten | `ply.LMNTStats` und `ply.LMNTInventory` | kein zentraler Cache, gespeichert wird bei Rundenende/Disconnect |
| Berechtigungen | eigenes Rangsystem, `IsAdmin`-Override, CAMI-Gruppen | funktional, aber CAMI-*Privilegien* fehlen, Rechte sind nur fest im Code definiert |
| Logging | DB + Tagesdatei, Kategorien | keine Schweregrade, kein Export, keine Größenbegrenzung der Datei |
| UI | `LMNT.UI.Frame/Button/Tabs/StyleList`, Farben in `LMNT.Config.Colors` | **Farben entsprechen nicht der Marke** (siehe Designsystem) |
| Rollen | TTT2-Rollendateien direkt | keine LMNT-Rollen-API |
| Items/Shop | TTT2-Items, eigener kosmetischer Pointshop | Kaufabwicklung ohne Transaktionsmodell |

## 4. API-Verifikation gegen den TTT2-Quellcode

Jede TTT2-Schnittstelle, die LMNT nutzt, wurde im Quellcode von 0.14.6b nachgeschlagen.

| Schnittstelle | Ergebnis | Fundstelle |
|---|---|---|
| `TTT2 = true`, `roles.InitCustomTeam`, `roles.SetBaseRole`, `roles.Register` | vorhanden | `sh_init.lua:11`, `libraries/roles.lua:451/629/237` |
| `TTTPlayerSpeedModifier(ply, isSlowed, mv, modTable)` | vorhanden. Rückgabewert **und** Tabelle werden multipliziert | `sh_speed.lua:31` |
| `TTTBeginRound`, `TTTEndRound(result)`, `TTTPrepareRound`, `TTTScoreboardColumns` | vorhanden | diverse |
| `GiveEquipmentWeapon`, `SpawnForRound`, `HasEquipmentItem`, `AddCredits`, `IsSpec`, `GetSubRole`, `GetTeam`, `IsActive`, `SetBaseKarma`/`SetLiveKarma` | vorhanden | `sv/sh_player_ext.lua`, `sv_karma.lua` |
| `LANG.GetLanguageTableReference`, Sprach-ID `"de"`, Ordner `terrortown/lang/` (rekursiv) | vorhanden | `cl_lang.lua:275`, `lang/de.lua`, `cl_main.lua:174` |
| `WEAPON_EXTRA`, `INNO_EQUIPMENT`, `TRAITOR_EQUIPMENT`, Icons `icon_deagle/flare/health/radar/knife/disguise/armor` | vorhanden | `sh_init.lua`, `content/materials` |
| `GetRoundState()` | vorhanden, aber nur als **„old function name alias“** von `gameloop.GetRoundState` | `libraries/gameloop.lua:938` → im Adapter umstellen (T-034) |
| `admin.RoundRestart()` | vorhanden. Es gibt **keinen** Befehl `ttt_roundrestart` | `libraries/admin.lua:28` |
| `ROLE.score.*`, `ROLE.conVarData.*` | gültige Felder siehe `ttt_role_base/shared.lua`. `conVarData`: pct, maximum, minPlayers, minKarma, random, traitorButton, credits, creditsAwardDeadEnable, creditsAwardKillEnable, shopFallback | `roles.lua` |
| `shopFallback` | Wert = **Rollenname** (z. B. `"traitor"`) oder `SHOP_DISABLED`/`SHOP_UNSET`. ConVar mit `FCVAR_ARCHIVE` | `sh_equip_items.lua:185`, `roles.lua:186` |

### Gefundene Fehler im bestehenden LMNT-Code

| ID | Fehler | Auswirkung | Schwere |
|---|---|---|---|
| BUG-01 | Hacker nutzt `SHOP_FALLBACK_TRAITOR`. Diese Konstante **existiert nicht** | `shopFallback` wird `nil` → `SHOP_DISABLED` → **der Hacker hat keinen Shop** | hoch |
| BUG-02 | `!roundrestart` ruft `ttt_roundrestart` auf. Den Befehl gibt es in TTT2 nicht | Der Befehl tut nichts | hoch |
| BUG-03 | Die Chat-Überschreibung `OnPlayerChat` ersetzt die TTT2-Logik | Nachrichten öffentlicher Polizei-Rollen (Detektiv) und Team-Chat-Kennzeichnung bei `unknownTeam`/Zuschauern falsch | mittel |
| BUG-04 | Narr-Sieg über `TTTCheckForWin` statt des vorgesehenen `TTT2PreWinChecker` | funktioniert nur, solange kein anderes Addon `TTT2PreWinChecker` beantwortet | mittel |
| BUG-05 | Rollenfelder, die es nicht gibt: `surviveBonus`, `preventKillCredits`, `preventTraitorAloneCredits`, `conVarData.togglable` | wirkungslose Einstellungen (Scheinkonfiguration) | niedrig |
| BUG-06 | Sprachschlüssel `search_role_*`, `target_*`, `ev_win_*` werden von TTT2 nicht genutzt. **`info_popup_<rolle>` fehlt** | kein Rollen-Popup zu Rundenbeginn für Narr, Sanitäter und Hacker | mittel |
| BUG-07 | BSP-Name `ttt_community_bowling` falsch (richtig: `_v5a`) | Map im Mapcycle nicht ladbar | **behoben** |

## 5. TTT2-Bibliotheken, die LMNT nutzen kann statt sie nachzubauen

`database.lua`/`orm.lua`/`migrations.lua` (SQLite-ORM mit Migrationen), `events.lua` (Rundenereignisse und Scoring), `fonts.lua`, `vskin.lua`, `hudelements.lua`/`huds.lua` (HUD-System mit Editiermodus), `marks.lua`/`outline.lua` (Durchsicht-Markierungen), `bind.lua` (Tastenbelegung), `admin.lua` (`admin.RoundRestart`).
**Prinzip:** Das LMNT-HUD baut auf dem TTT2-HUD-System auf und ersetzt es nicht. Für die Durchsicht-Markierung des Hackers ist `marks` besser als `halo` (performanter).

## 6. Technische Risiken

| ID | Risiko | Maßnahme |
|---|---|---|
| R-01 | API-Änderungen in zukünftigen TTT2-Versionen | Kompatibilitätsmatrix, Adapter-Schicht `LMNT.TTT2`, Versionsprüfung beim Start |
| R-02 | SQLite ist synchron: Abfragen blockieren den Server-Tick | Cache mit Write-Behind und gebündelten Transaktionen, Latenzmessung. **Keine Schein-Asynchronität** |
| R-03 | MySQL braucht das Binärmodul `mysqloo`. Es ist nicht installiert und ein Sicherheitsrisiko, wenn die Quelle unklar ist | Adapter-Schnittstelle jetzt, MySQL-Adapter erst nach Entscheidung (Frage F-01) |
| R-04 | Marken-Schriften (Archivo Black, DM Sans) müssen per FastDL verteilt werden. DM Sans gibt es upstream nur als Variable Font, und wie GMod das darstellt, ist ungeprüft | Testen, sonst Fallback-Schrift (Frage F-03) |
| R-05 | Programmatische Rollenregistrierung (`roles.Register`) muss vor `roles.OnLoaded` passieren. Das Timing ist zu verifizieren | LMNT-Rollen-API als Adapter mit Integrationstest |
| R-06 | Es gibt keinen automatischen GMod-Client für UI-Tests | Server-Integrationstests mit Bots und `-condebug`, UI-Tests manuell mit Checkliste |
| R-07 | Hot-Reload in GMod ist nur teilweise möglich (Autorefresh, Netzwerkstrings bleiben registriert) | Module deklarieren `reloadable`, Bereinigung über Lebenszyklus-Registry |
| R-08 | Geheimnisse (RCON, Auth-Key, GSLT) stehen in `settings.ini` | `.gitignore` und `settings.example.ini` (T-001) |
| R-09 | Datenmigration der bestehenden Tabellen (`lmnt_ttt_stats`, `lmnt_ps_inventory` …) ins neue Schema | Migrationen mit Versionsnummer, bevor Spieler Daten erzeugen |
| R-10 | Clients ohne CS:S sehen auf manchen Maps Fehlertexturen | Content-Pack-Entscheidung (Frage F-04) |
| R-11 | VAC erkennt GMod-Lua-Cheats kaum. Heuristische Erkennung erzeugt Fehlalarme | Serverautorität, Anti-Cheat-Modul nur mit Meldungen und Belegen, kein Auto-Bann (WP-09) |
| R-12 | Testläufe nutzen `sv_lan 1`, dabei ist VAC aus. Das gilt **nicht** für den Produktionsstart | Prüfung im Produktionsstart (T-090) |

## 7. Offene Fragen

| ID | Frage |
|---|---|
| F-01 | Soll MySQL unterstützt werden, zum Beispiel für eine spätere Anbindung ans LMNT-Usercenter? Falls ja: externer DB-Server vorhanden? |
| F-02 | Sollen Spielerkonten mit dem **Usercenter/Player Hub** von lmnt-gaming.net verknüpft werden? Das hätte großen Einfluss auf das Datenmodell |
| F-03 | Dürfen Marken-Schriften an Clients ausgeliefert werden (rund 300 KB zusätzlicher Download)? |
| F-04 | Soll ein CS:S-Content-Pack in die Collection aufgenommen werden (rund 200–600 MB für Spieler ohne CS:S)? |
| F-05 | Welche Perks, Achievements und Aufgaben sind inhaltlich gewünscht? Die Architektur ist inhaltsunabhängig |
| F-06 | Bleibt der kosmetische Pointshop oder geht er in einem Freischalt- und Progressionssystem auf? |
