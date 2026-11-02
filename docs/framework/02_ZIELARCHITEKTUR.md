# Zielarchitektur LMNT-TTT2 Framework

## Leitentscheidungen

1. **Zwei Addons bleiben bestehen.** `lmnt_core` ist gamemode-unabhängig und kann später auch für andere LMNT-Server dienen. `lmnt_ttt` enthält die gesamte TTT2-Integration und die Inhalte. Eine Migration in ein Monolith-Addon hätte keinen technischen Nutzen.
2. **Auf TTT2 aufbauen statt TTT2 nachbauen.** HUD-Elemente, Rollen, Items, Markierungen, Tastenbelegung und Sprachen laufen über die TTT2-Systeme. LMNT ergänzt nur, was TTT2 nicht bietet.
3. **Adapter statt Direktzugriff.** Alle TTT2-Aufrufe aus LMNT-Modulen laufen über `LMNT.TTT2` (Version prüfen, Hooks übersetzen). Bei TTT2-Updates ändert sich nur der Adapter.
4. **Serverautorität.** Clients senden nur *Absichten* (Kaufwunsch, Menüaktion). Werte wie Geld, XP, Rollen und Rechte entstehen ausschließlich auf dem Server.
5. **Keine Schein-Features.** Was nicht funktionsfähig ist, wird nicht als Einstellung angeboten.

## Schichtenmodell

```
┌──────────────────────────────────────────────────────────────────┐
│ Inhalte (lmnt_ttt)                                               │
│  Rollen · Items · Waffen · Spezialrunden · Kosmetik · Perks …     │
├──────────────────────────────────────────────────────────────────┤
│ Feature-Module (lmnt_ttt/modules, unabhängig deaktivierbar)       │
│  progression · stats · shop · cosmetics · specialrounds · perks  │
│  achievements · quests · prestige · scoreboard · admin_ttt       │
│  anticheat (Heuristiken, Verdachtssystem – nur Meldungen)        │
├──────────────────────────────────────────────────────────────────┤
│ Spiel-APIs (lmnt_ttt/api)            │ TTT2-Adapter (LMNT.TTT2)   │
│  LMNT.Roles · LMNT.Items · LMNT.Shop │  Hooks, Version, Rollen    │
├──────────────────────────────────────────────────────────────────┤
│ Framework-Core (lmnt_core)                                        │
│  Core · Modules · Events · Config · Net · DB · PlayerData · Cache │
│  Permissions · Log · UI · DevTools                                │
└──────────────────────────────────────────────────────────────────┘
```

Abhängigkeiten zeigen nur nach unten. Der Core kennt weder TTT2 noch Inhalte.

## Core-Bereiche

| Bereich | Namespace | Zuständigkeit | Hängt ab von | Fehlerverhalten |
|---|---|---|---|---|
| Core | `LMNT` | Lebenszyklus (`boot → services → modules → ready`), SemVer, `LMNT.RequireVersion` | – | Fataler Fehler stoppt den Boot mit klarer Meldung |
| Log | `LMNT.Log` | Schweregrade `debug/info/warn/error/security`, Kategorien, Größenlimit, Export | Core | Fallback auf `ServerLog`, wenn die DB ausfällt |
| Config | `LMNT.Config` | Schema (Typ, Bereich, Default, Recht, `applies = live/nextround/restart`), Validierung, Overrides aus `data/lmnt/config.json`, Änderungsprotokoll | Log | Ungültiger Wert → Default + Warnung, nie `nil` |
| Events | `LMNT.Events` | Namensräume (`lmnt.player.levelup`), Beobachter vs. abbrechbare Events, `pcall`-Isolation, Laufzeitmessung, Eigentümer-Bindung | Log | Fehler eines Listeners wird geloggt, die anderen laufen weiter |
| Modules | `LMNT.Modules` | Registrierung, Abhängigkeiten (topologische Sortierung), Konflikte, Aktivieren/Deaktivieren, automatische Bereinigung von Hooks, Timern, Events und UI | Events, Config, Log | Modul im Status `failed`, abhängige Module `blocked`, der Rest läuft |
| DB | `LMNT.DB` | Adapter-Interface (`sqlite` jetzt, `mysqloo` optional), Parameterbindung, Transaktionen, Migrationen mit Schemaversion pro Modul | Log | Fehler → `nil, err`, Migration atomar (Transaktion) |
| PlayerData | `LMNT.PlayerData` | ein Profil pro SteamID64, Modul-Namespaces, Cache mit Dirty-Tracking, gebündeltes Speichern (Rundenende, Disconnect, Intervall) | DB, Events | Ladefehler → Spieler-Flag `dataUnavailable`, keine Belohnungen bis zum erfolgreichen Laden |
| Net | `LMNT.Net` | `LMNT.Net.Register(name, schema, opts)`: Typen, Größenlimits, Rechte, Rate-Limit, Deduplizierung, Byte- und Nachrichtenzähler | Permissions, Log | Ungültiges Paket → verwerfen + `security`-Log, ohne Antwortdetails |
| Permissions | `LMNT.Perms` | Rechte registrieren (mit Beschreibung), Gruppen und Ränge, CAMI-Privilegien, Deny-by-default | Config, Log | Unbekanntes Recht = verweigert |
| UI | `LMNT.UI` | Design-Tokens, Schriften, Komponentenbibliothek, Menü-Shell (F-Menü) mit Modul-Seiten | Config (Client) | Fehlerhafte Seite zeigt einen Fehlerzustand, kein Absturz des Menüs |
| DevTools | `LMNT.Dev` | `lmnt_status`, `lmnt_modules`, `lmnt_hooks`, `lmnt_net_stats`, `lmnt_db_stats`, Profiler, Konfigurationsvalidierung | alle | nur mit Recht `lmnt.dev` |

## Spiel-APIs (lmnt_ttt)

- **`LMNT.TTT2`**: Adapter. Versionsprüfung (getestet: 0.14.6b), Zuordnung der LMNT-Events zu TTT2-Hooks (`TTTBeginRound` → `lmnt.round.begin`, `TTT2PreWinChecker` → abbrechbares `lmnt.round.wincheck` …), Helfer für Teams und Rollen.
- **`LMNT.Roles.Register(id, def)`**: Validierung, erzeugt die TTT2-Rolle über `roles.Register` mit `ttt_role_base` als Basis, Sprachschlüssel, Loadout, Fähigkeiten mit Cooldowns, Statistik-Hooks. Die bestehenden Rollen-Dateien werden auf die API umgestellt.
- **`LMNT.Items` / `LMNT.Shop`**: Registrierung, Preisregeln, Kaufgrenzen. Ein Kauf läuft als **Transaktion**: prüfen → Preis berechnen → reservieren → ausgeben → bestätigen, sonst rückabwickeln + protokollieren. Pro Spieler werden Käufe serialisiert, das verhindert Race Conditions.

## Datenmodell (Ziel, SQLite)

| Tabelle | Schlüssel | Inhalt |
|---|---|---|
| `lmnt_schema` | `module` | Schemaversion pro Modul |
| `lmnt_players` | `steamid64` | Name, erster und letzter Besuch, Spielzeit, Rang |
| `lmnt_player_data` | `steamid64, module, key` | Modulwerte (JSON oder Zahl), Index auf `module` |
| `lmnt_stats` | `steamid64, season, stat` | Zähler (kills, deaths, assists, wins, rounds, role:*), Index für Ranglisten |
| `lmnt_inventory` | `steamid64, item` | Besitz und Ausrüstung |
| `lmnt_bans`, `lmnt_warns`, `lmnt_slaynr` | wie bisher | Moderation |
| `lmnt_audit` | `id` | privilegierte Aktionen: wer, was, vorher → nachher |
| `lmnt_logs` | `id` | Betriebslogs mit Schweregrad, Größenlimit |
| `lmnt_config` | `key` | Overrides aus dem Ingame-Configurator |

Die bestehenden Tabellen (`lmnt_users`, `lmnt_ttt_stats`, `lmnt_ps_inventory`) werden per Migration übernommen und danach nicht mehr beschrieben.

**KDA-Definition:** `(Kills + Assists) / max(1, Tode)`. Assist = mindestens 25 Schaden an einem Gegner, der innerhalb von 10 s von jemand anderem getötet wird. Teamkills, Narr-Kills und Selbstmorde zählen nicht als Kill. Selbstmorde zählen als Tod.

## Ladereihenfolge

```
autorun/lmnt_core_init.lua
  └ core/sh_core → log → config → events → perms → net → db(sv) → playerdata(sv) → cache → ui(cl) → dev
  └ LMNT.Modules.Discover("lmnt/modules/")         -- Core-Module (admin)
autorun/lmnt_ttt_init.lua   (wartet auf PostGamemodeLoaded, prüft TTT2)
  └ api/ttt2_adapter → roles → items/shop
  └ LMNT.Modules.Discover("lmnt_ttt/modules/")
  └ LMNT.Modules.StartAll()  -- topologisch sortiert, mit Fehlerstatus
TTT2 lädt: terrortown/entities/roles|items, weapons, terrortown/lang
```

## Dokumentationsstruktur

```
docs/
├─ README.md / Betriebsdokus (ADMIN, INHALTE, WORKSHOP_FASTDL)
└─ framework/
   ├─ 01_BESTANDSAUFNAHME.md      Ist-Zustand, API-Verifikation, Risiken, Fragen
   ├─ 02_ZIELARCHITEKTUR.md       dieses Dokument
   ├─ 03_AUFGABEN.md              Aufgabenliste mit Status
   ├─ 04_AKZEPTANZKRITERIEN.md    Definition of Done, Release-Kriterien
   ├─ 05_DESIGNSYSTEM.md          Tokens und Komponenten aus lmnt-gaming.net
   ├─ ENTSCHEIDUNGEN.md           Architekturentscheidungen (ADR-Log)
   ├─ api/                        je API eine Referenz (core, events, modules, config, net, db, playerdata, perms, ui, roles, items-shop)
   ├─ guides/                     Quickstart „Eigenes Modul in 15 Minuten“, Beispielrolle, Beispielitem
   ├─ KOMPATIBILITAET.md          getestete TTT2- und GMod-Versionen
   ├─ SICHERHEIT.md               Bedrohungsmodell, Annahmen, bekannte Risiken
   └─ TESTS.md                    Testarten, Ausführung, letzte Ergebnisse
```
