# LMNT | TTT2 – kompletter Garry's-Mod-TTT-Server

[![Lint](https://github.com/LMNT-Gaming/Garrys-Mod-TTT/actions/workflows/lint.yml/badge.svg)](https://github.com/LMNT-Gaming/Garrys-Mod-TTT/actions/workflows/lint.yml)
[![Release](https://img.shields.io/github/v/release/LMNT-Gaming/Garrys-Mod-TTT)](https://github.com/LMNT-Gaming/Garrys-Mod-TTT/releases/latest)
[![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-blue.svg)](LICENSE)

Ein von Grund auf gebautes Server-Paket: **TTT2** als Basis, ein eigenes **LMNT-Framework** mit Admin-System, eigene Rollen, Waffen, Items, Spezialrunden, Level-System, Pointshop, eigenes HUD, saubere Workshop-Collection, FastDL und Ladebildschirm.

| | |
|---|---|
| **Rollen** | Narr, Sanitäter, Hacker |
| **Waffen** | 11 – u. a. Medigun, Taser, Giftpfeil, Näherungsmine, Wurfmesser, Bewegungsmelder |
| **Items** | 8 passive Shop-Items – u. a. Adrenalin, Energieschild, Lebenszeichen-Monitor |
| **Spezialrunden** | 7 – Mondlandung, Turbo, Kopfjäger, Vampirnacht, Schwarzmarkt, Kettenreaktion, Wackelköpfe |
| **Progression** | Level/XP, Statistik, Pointshop mit Modellen, Hüten und Spuren |
| **Administration** | Ränge mit Immunität, 66 Befehle, Banns, Warns, Admin-Menü mit grafischem Configurator |
| **Framework** | Module, Settings, Events, Net, PlayerData, Integrationen (TTT2, CAMI, ULX) – 244 Unit-Tests |

## Download

Fertige Pakete gibt es unter [**Releases**](https://github.com/LMNT-Gaming/Garrys-Mod-TTT/releases/latest):

| Paket | Inhalt |
|---|---|
| `LMNT-TTT2-<Version>.zip` | komplettes Set: Addons, Configs, Server-Skripte, Tools, Ladebildschirm, Doku |
| `LMNT-TTT2-Addons-<Version>.zip` | nur `garrysmod/` – für einen bestehenden TTT2-Server |
| `SHA256SUMS.txt` | Prüfsummen |

## Voraussetzungen

- Windows 10/11 (Server-Skripte in PowerShell/Batch)
- Python 3 (RCON-Client, FastDL-Webserver, Workshop-Werkzeuge)
- Node.js (nur für den Lint)
- Workshop: [TTT2](https://steamcommunity.com/sharedfiles/filedetails/?id=1357204556) (getestet mit 0.14.6b) und die Maps aus `garrysmod/data/lmnt/workshop.json`

## Schnellstart (Windows)

1. **Einstellungen:** `server\settings.example.ini` nach `server\settings.ini` kopieren (passiert beim ersten Skriptlauf automatisch) und `SERVER_DIR`, `RCON_PASSWORD`, `OWNERS` (deine SteamID64) und `FASTDL_URL` anpassen.
2. **Server installieren** (lädt SteamCMD, GMod-Server und CS:S-Texturen und kopiert alles):
   ```bash
   powershell -ExecutionPolicy Bypass -File server\install.ps1
   ```
3. **Workshop-Collection anlegen**, siehe [docs/WORKSHOP_FASTDL.md](docs/WORKSHOP_FASTDL.md). Danach `COLLECTION_ID`, `STEAM_AUTHKEY` und `GSLT` in `settings.ini` eintragen und prüfen:
   ```bash
   powershell -ExecutionPolicy Bypass -File tools\workshop.ps1
   ```
4. **FastDL bauen und starten:**
   ```bash
   powershell -ExecutionPolicy Bypass -File tools\build_fastdl.ps1
   ```
   ```bash
   tools\serve_fastdl.bat
   ```
5. **Server starten:**
   ```bash
   server\start.bat
   ```

Nach Änderungen am Projekt genügt `server\deploy.ps1`, danach den Server neu starten.

**Nur die Addons:** Inhalt von `garrysmod/` in den `garrysmod/`-Ordner deines Servers kopieren, Gamemode `terrortown` mit TTT2. Owner per Serverkonsole: `lmnt setrankid <SteamID64> owner`.

## Projektstruktur

```
Garrys-Mod-TTT/
├─ garrysmod/                     ← wird 1:1 in den Server kopiert (deploy.ps1)
│  ├─ addons/
│  │  ├─ lmnt_core/               ← LMNT-Framework (unabhängig vom Gamemode)
│  │  │  ├─ lua/lmnt/core/        Lebenszyklus, Config, Settings, Events, Module, Net, DB, Log, UI
│  │  │  ├─ lua/lmnt/services/    PlayerData, Migrationen, HTTP, Configurator, Startprüfung, ULX-Import
│  │  │  ├─ lua/lmnt/integrations/ CAMI, ULX
│  │  │  ├─ lua/lmnt/admin/       Ränge, Befehle, Banns, Warns, Admin-Menü
│  │  │  └─ lua/lmnt/tests/       Unit-Tests (lmnt test)
│  │  └─ lmnt_ttt/                ← TTT2-Inhalte auf Basis des Frameworks
│  │     ├─ lua/lmnt_ttt/         Spezialrunden, Level/Stats, Pointshop, Shop-Regeln, Maps, Items
│  │     ├─ lua/terrortown/       Rollen, Items, HUD, Menü-Skin, Sprachen
│  │     ├─ lua/weapons/          11 Waffen
│  │     └─ lua/entities/         Minen, Sensoren, Projektile
│  ├─ cfg/server.cfg, mapcycle.txt
│  └─ data/lmnt/                  workshop.json (Collection, Downloads, Mapcycle), Map-Profile, secrets.example.json
├─ server/                        ← Installieren, Kopieren, Starten, Updaten
│  ├─ settings.example.ini        ← Vorlage für settings.ini (lokal, nicht im Repo)
│  └─ install.ps1 · deploy.ps1 · update.ps1 · start.bat
├─ tools/                         Lint, Integrationstest, RCON, Workshop, FastDL, Release-Build
├─ fastdl/loading/                Ladebildschirm (sv_loadingurl)
└─ docs/                          Anleitungen und Framework-Dokumentation
```

## Dokumentation

| Datei | Inhalt |
|---|---|
| [docs/ADMIN.md](docs/ADMIN.md) | Ränge, Rechte, alle Befehle, Admin-Menü, Banns und Warns |
| [docs/INHALTE.md](docs/INHALTE.md) | Rollen, Waffen, Items, Spezialrunden, Level, Pointshop und HUD |
| [docs/WORKSHOP_FASTDL.md](docs/WORKSHOP_FASTDL.md) | Collection, Client-Downloads, FastDL, Ladebildschirm, Ports |
| [docs/ENTWICKLUNG.md](docs/ENTWICKLUNG.md) | Framework-API: eigene Befehle, Rollen, Spezialrunden und Shop-Items |
| [docs/framework/](docs/framework/) | Architektur, Entscheidungen (ADR), Akzeptanzkriterien, Testprotokoll, API-Referenz |

## Testen

```bash
powershell -ExecutionPolicy Bypass -File tools\lint.ps1
```
```bash
powershell -ExecutionPolicy Bypass -File tools\test_server.ps1
```

Der Integrationstest deployt, startet den Server mit Bots, führt alle Unit-Tests auf dem echten srcds aus, schaltet Module zur Laufzeit um, spielt eine Runde und wertet `console.log` aus (PASS/FAIL). Protokoll: [docs/framework/TESTS.md](docs/framework/TESTS.md).

## Mitarbeiten, Sicherheit, Lizenz

- Beiträge: [CONTRIBUTING.md](CONTRIBUTING.md) · Änderungen: [CHANGELOG.md](CHANGELOG.md)
- Sicherheitslücken bitte vertraulich melden: [SECURITY.md](SECURITY.md)
- Code unter [MIT-Lizenz](LICENSE). Die Schriften Archivo Black und DM Sans stehen unter der SIL Open Font License (Lizenztexte liegen bei). Workshop-Inhalte (TTT2, Maps) sind nicht enthalten und unterliegen den Lizenzen ihrer Autoren.
