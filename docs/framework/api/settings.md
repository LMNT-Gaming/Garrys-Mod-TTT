# API: LMNT.Settings (seit 1.1.0)

Datei: `lmnt_core/lua/lmnt/core/sh_settings.lua` · Realm: shared (Server ist die Quelle)

**Abgrenzung:** `LMNT.Config` = statische Grundkonfiguration in Lua-Dateien (Branding, Ränge, Regeln). `LMNT.Settings` = typisierte Werte, die ingame änderbar, validiert, gespeichert, protokolliert und optional an Clients repliziert sind.

## Rangfolge der Werte (Server)
1. Ingame-Änderung (Tabelle `lmnt_config`, mit `changed_by`, `changed_at`)
2. `garrysmod/data/lmnt/config.json` (Betreiber-Overrides, Schlüssel mit `_` am Anfang werden ignoriert)
3. `default` aus der Definition

Ungültige gespeicherte Werte → Warnung im Log und Rückfall auf die nächste Stufe. Es entsteht nie `nil`.

## Funktionen

| Funktion | Realm | Rückgabe | Fehler |
|---|---|---|---|
| `Define(key, def)` | shared | def | `error`, wenn Typ fehlt oder der Standardwert ungültig ist |
| `Get(key)` | shared | Wert | `error` bei unbekanntem Key |
| `GetDef(key)`, `List()` | shared | Definition(en) | – |
| `Set(key, wert, actor)` | server | `true, wert` / `false, meldung` | ungültiger Wert, unbekannter Key, fehlendes Recht (→ `security`-Log) |
| `Reset(key, actor)` | server | wie `Set` | – |
| `Validate(def, wert)` | shared | `true, normalisiert` / `false, meldung` | reine Funktion |

### Definition
| Feld | Bedeutung |
|---|---|
| `type` | `bool` · `int` · `number` · `string` · `enum` |
| `default` | Pflicht, wird validiert |
| `min`, `max` / `choices` / `maxLength` | Grenzen |
| `desc`, `category` | für Configurator und `!config` |
| `perm` | Recht zum Ändern (Standard `config`) |
| `applies` | `live` · `nextround` · `restart`. Wird bei jeder Änderung angezeigt und **muss der Wahrheit entsprechen** |
| `replicate` | an Clients übertragen (beim Join und bei Änderung, nur geänderte Keys) |
| `onChange(neu, alt)` | läuft auf dem Server und bei replizierten Werten auch auf Clients |

Jede Änderung erzeugt einen Log-Eintrag `config` mit altem und neuem Wert und das Event `lmnt.settings.changed`.

## Derzeit definiert

| Key | Typ | Standard | wirkt |
|---|---|---|---|
| `core.log.retention_days` | int 1–365 | 30 | restart |
| `module.<id>.enabled` | bool | true | live (repliziert) |
| `ttt.special.chance` | number 0–1 | 0.2 | nextround |
| `ttt.special.min_players` | int 1–64 | 4 | nextround |
| `ttt.special.min_gap` | int 0–20 | 2 | nextround |
| `ttt.stats.min_players` | int 1–64 | 4 | live |
| `ttt.stats.vip_multiplier` | number 1–5 | 1.5 | live |

## Ingame
`!config` listet alles (geänderte Werte in Gelb) · `!config <key>` zeigt Details · `!config <key> <wert>` setzt · `!config <key> reset`
