# API: LMNT.Maps – Modul `ttt.maps` (seit 1.0.0)

Dateien: `lmnt_ttt/lua/lmnt_ttt/sh_maps.lua` (shared: Validierung, Registry-Aufbau, Befehle) und `sv_maps.lua` (Server: Dateien lesen, Profile anwenden, Event) · Registrierung in `lmnt_ttt/lua/autorun/lmnt_ttt_init.lua` · Tests: `lmnt_ttt/lua/lmnt/tests/sv_maps.lua`

Das Modul ist abschaltbar (`!module ttt.maps aus`). Beim Abschalten werden alle Map-Overrides sofort zurückgenommen.

## Grundsatz

Keine Map-Eigenschaft wird aus dem Mapnamen abgeleitet. Alles stammt aus echten Dateien oder echten Entities. Was sich nicht prüfen lässt, ist `nil` und wird als **„unbekannt“** angezeigt, nie als `false`.

## Registry

| Quelle | Gelesen aus | Ergebnis im Eintrag |
|---|---|---|
| Workshop-Liste | `data/lmnt/workshop.json`, Liste `maps` (`id`, `name`, `map`) | `workshopId`, `workshopName`. Einträge ohne gültiges `map` oder mit nicht numerischer ID werden mit Warnung ignoriert. Der Workshop-Name wird **nicht** als Mapname verwendet |
| BSP-Dateien | `file.Find("maps/*.bsp", "GAME")` (auch gemountete Workshop-Addons) | `bsp = true`. `map` übernimmt die Schreibweise der echten Datei |
| Mapcycle | Datei aus der ConVar `mapcyclefile` (erst `cfg/<name>`, dann `<name>`), `//` = Kommentar | `inMapcycle`. Datei nicht lesbar → `nil` für alle Maps |
| Profile | `data/lmnt/maps/*.json` | `profileState`, `profile`, `displayName`, `knownIssues`, Fehlerlisten |
| laufende Map | Entities beim Laden (siehe unten) | nur über `Maps.Current().spawns` |

Jede Quelle kann eine Map neu aufnehmen. So erscheinen auch Mapcycle-Einträge ohne BSP (`bsp = false`) oder Profile für nicht installierte Maps. Der Schlüssel ist der Mapname in Kleinbuchstaben.

### Eintrag
| Feld | Bedeutung |
|---|---|
| `name` | normalisierter Name (Kleinbuchstaben, nur `[a-z0-9_.-]`, kein führender Punkt) |
| `map` | Schreibweise der BSP-Datei bzw. aus `workshop.json` |
| `sources` | Liste aus `workshop`, `bsp`, `mapcycle`, `profile` |
| `workshopId`, `workshopName` | aus `workshop.json`, sonst `nil` |
| `bsp`, `inMapcycle` | `true` / `false` / `nil` (= unbekannt) |
| `profileState` | `none` · `ok` · `warnings` · `errors` (ungültige Teile verworfen) · `invalid` (kein gültiges JSON, Profil wird nicht verwendet) |
| `profile`, `profilePath`, `profileErrors`, `profileWarnings` | geprüftes Profil und Meldungen |
| `displayName`, `knownIssues` | aus dem Profil (`knownIssues` ist immer eine Liste) |

### Spawns und Entities (nur laufende Map)
`Maps.Current().spawns` = `{ player, weapon, ammo, tttEntities, source }`:

- **Normalfall:** Der Hook `InitPostEntity` läuft vor `GM:InitPostEntity` von TTT2. Gezählt wird mit den TTT2-Funktionen `map.GetPlayerSpawnEntities()`, `map.GetWeaponSpawnEntities()` und `map.GetAmmoSpawnEntities()` (TTT2 0.14.6b, `lua/ttt2/libraries/map.lua`). Sie berücksichtigen den Fallback auf `info_player_start`. Zusätzlich zählt das Modul alle `ttt_*`-Entities. `source = "Map-Entities beim Laden"`.
- **Modul zur Laufzeit eingeschaltet:** TTT2 hat die Map-Spawns beim Rundenaufbau (`entspawn.HandleSpawns`) schon entfernt. Dann wird die Kopie gelesen, die TTT2 beim ersten Laden speichert (`entspawnscript.defaultSpawnTable`). `source = "TTT2-Kopie der Map-Spawns"`, `tttEntities` bleibt unbekannt.
- `Maps.GetEffectiveSpawns()` liefert die Spawns, die TTT2 **tatsächlich** benutzt (`entspawnscript.GetSpawns()`, also aus der Map oder aus einer TTT2-Spawndatei) und `spawnFile` (`entspawnscript.SpawnFileExists()`).
- Für alle anderen Maps sind Spawns und Entities **unbekannt**. Die BSP wird nicht ausgewertet.

## Map-Profile

Datei: `garrysmod/data/lmnt/maps/<mapname>.json`, Mapname in **Kleinbuchstaben** (Linux-Server unterscheiden Groß- und Kleinschreibung). Alle Felder sind optional. Schlüssel mit `_` am Anfang sind Kommentare.

| Feld | Typ | Regeln |
|---|---|---|
| `displayName` | Text | max. 64 Zeichen |
| `author` | Text | max. 64 Zeichen. **Nur belegte Angaben** (Quelle im `_quellen`-Kommentar nennen) |
| `notes` | Text | max. 500 Zeichen |
| `knownIssues` | Liste von Texten | max. 20 Einträge à 200 Zeichen. Leere Einträge entfallen |
| `settings` | Objekt `{ "key": wert }` | Overrides registrierter `LMNT.Settings`, **gültig nur für diese Map** |

Für alle Texte gilt: Die Länge wird in UTF-8-Zeichen gezählt, Steuerzeichen und Zeilenumbrüche sind nicht erlaubt und Leerraum am Rand wird entfernt. Unbekannte Felder erzeugen nur einen Hinweis.

### Regeln für `settings`
1. Der Key muss registriert sein (`LMNT.Settings.GetDef`). Geprüft wird beim Anwenden in der Phase `ready`, wenn alle Module ihre Einstellungen definiert haben.
2. Der JSON-Typ muss passen: `bool` → `true/false`, `int`/`number` → Zahl, `string`/`enum` → Text. `"0.5"` als Text für eine Zahl oder `"an"` für bool wird **abgelehnt**, obwohl `!config` das annimmt.
3. Grenzen, `choices` und `maxLength` prüft `LMNT.Settings.Validate`.
4. **Nicht erlaubt:** Einstellungen mit `applies = "restart"` (sie würden erst nach dem Mapwechsel wirken, also nie für diese Map) sowie `module.*` und `integration.*` (Schalter mit Kaskaden-Wirkung).
5. Ungültige Einträge werden verworfen, im Log (`ttt.maps`) und in `!mapinfo` gemeldet. Gültige Einträge werden trotzdem angewendet.

Beispiel:
```json
{
	"_quellen": "author: Workshop-Beschreibung, abgerufen am …",
	"displayName": "Minecraft",
	"notes": "Hinweise für Spieler und Team",
	"knownIssues": [ "Beschreibung eines geprüften Fehlers" ],
	"settings": { "ttt.special.chance": 0.1, "ttt.special.min_players": 6 }
}
```
Echtes Beispiel ohne Overrides: `garrysmod/data/lmnt/maps/ttt_minecraft_b5.json`. Autor und Spawn-Angaben sind dort mit Quelle belegt.

## Overrides: gewählte Lösung

`LMNT.Settings` wird **nicht** verändert. Das Modul setzt Werte über die öffentliche API `Set`/`Reset` mit dem Actor `"Map-Profil"` (`Maps.ACTOR`) und merkt sich vorher, was zurückzustellen ist.

**Ablauf pro Map** (GMod baut den Lua-Zustand bei jedem Mapwechsel neu auf):

| Zeitpunkt | Aktion |
|---|---|
| Modulstart (`PostGamemodeLoaded`) | Zustand der aktuellen Map anlegen, Listener registrieren. Das Profil wird hier noch **nicht** geprüft: Module wie `ttt.specialrounds` starten alphabetisch nach `ttt.maps`, ihre Keys wären noch unbekannt |
| Phase `ready` | 1. Reste aus dem Journal zurücknehmen (Absturz). 2. Profil lesen und prüfen. 3. Overrides anwenden. Das geschieht vor der ersten Runde, auch `nextround`-Werte gelten also ab Runde 1 |
| `InitPostEntity` | Spawns zählen, Event `lmnt.map.loaded` |
| `ShutDown` (laut GMod-Wiki auch beim Mapwechsel) | alle Overrides zurücknehmen |
| Modul aus (`!module ttt.maps aus`) | alle Overrides zurücknehmen, Hooks/Befehle/Listener entfernt |
| Modul zur Laufzeit an | sofort anwenden, Spawns aus der TTT2-Kopie, Event |

**Pro Key wird vor der Änderung gespeichert:** `applied` (gesetzter Wert), `hadStored` (gab es einen Ingame-Wert in `lmnt_config`?) und `stored` (dieser Wert).
Beim Zurücknehmen gilt:
- Gab es einen Ingame-Wert, wird er mit `Set(key, stored, "Map-Profil")` wiederhergestellt. Ist er inzwischen ungültig, zum Beispiel wegen geänderter Grenzen, folgt `Reset`.
- Ohne Ingame-Wert folgt `Reset(key, "Map-Profil")`. Dann gilt wieder `config.json` bzw. der Standard, und in `lmnt_config` bleibt kein Eintrag.
- Gilt der Wert schon (`status = "same"`), wird nichts geschrieben und es gibt nichts zurückzunehmen.

**Admin-Änderung gewinnt:** Ändert jemand einen überschriebenen Key während der Map (`!config`, Configurator), meldet das `lmnt.settings.changed`. Das Modul gibt den Override auf und dreht diesen Wert beim Mapwechsel **nicht** zurück.

**Absturz-Sicherheit:** Weil `Set` in die Datenbank schreibt, würde ein Absturz den Override dauerhaft machen. Deshalb steht jeder aktive Override **vor** der Änderung im Journal `data/lmnt/maps_overrides_active.json`. Beim nächsten Start (Phase `ready`) wird er zurückgenommen, sofern `lmnt_config` noch genau den gesetzten Wert enthält. Sonst bleibt der Wert unangetastet (`skipped`). Ist eine Einstellung beim Start nicht registriert, weil ihr Modul aus ist, bleibt der Eintrag im Journal (`pending`). Er wird beim nächsten Start erneut versucht.

### Grenzen (bewusst dokumentiert)
- **Protokoll:** `LMNT.Name()` kennt nur Spieler. Deshalb steht im `config`-Log und in `lmnt_config.changed_by` „Konsole“. Wer wirklich geändert hat, zeigen die Einträge der Kategorie `ttt.maps` („Map-Profil ttt_x: key = wert“) und das Event-Argument `actor = "Map-Profil"`. Lösbar nur in `lmnt_core`, etwa wenn `LMNT.Name` Texte durchreicht.
- **Interner Lesezugriff:** Ob ein Ingame-Wert existiert, liest das Modul aus `LMNT.Settings._stored`, nur lesend. Eine öffentliche Funktion (z. B. `LMNT.Settings.GetStored(key)`) oder eine eigene Override-Ebene in `LMNT.Settings` wäre sauberer und würde auch den DB-Schreibzugriff vermeiden. Beides gehört zu `lmnt_core`.
- Während der Map steht der Override in `lmnt_config` und ist in `!config` gelb markiert. Beim Wiederherstellen eines Ingame-Werts werden `changed_by`/`changed_at` neu geschrieben.
- Setzt ein Admin während der Map **denselben** Wert wie der Override, löst `Set` kein Änderungs-Event aus. Der Wert wird beim Mapwechsel trotzdem zurückgenommen.
- Geht das Journal nach einem Absturz verloren (gelöscht oder unlesbar), lässt sich der alte Zustand nicht mehr bestimmen. Ein unlesbares Journal wird mit Inhalt ins Log geschrieben und gelöscht.
- `ShutDown` läuft nicht, wenn der Prozess hart beendet wird. Dafür gibt es das Journal.
- `onChange` der Einstellungen läuft beim Anwenden und beim Zurücknehmen, also auch in `ShutDown`.
- Die Spawn-Kopie `entspawnscript.defaultSpawnTable` ist ein Feld von TTT2 0.14.6b und keine dokumentierte Schnittstelle. Fehlt es, sind die Spawns „unbekannt“.
- Alle Profiltexte sind öffentlich (`!mapinfo` ist für alle lesbar).
- **Deployment:** `server/deploy.ps1` kopiert derzeit nur `data/lmnt/workshop.json`. Profile unter `data/lmnt/maps/` müssen zusätzlich auf den Server.

## Event

| Event | Argumente | Wann |
|---|---|---|
| `lmnt.map.loaded` | `map` (Name wie `game.GetMap()`), `profile` (geprüftes Profil oder `nil`) | einmal pro Map bei `InitPostEntity`, nach dem Anwenden der Overrides. Außerdem beim Einschalten des Moduls zur Laufzeit. Nicht bei `!mapprofile` |

## Befehle

| Befehl | Recht | Zweck |
|---|---|---|
| `!maps` | für alle | alle bekannten Maps mit Workshop-ID, BSP, Mapcycle, Profilstatus und Zahl der bekannten Fehler. Ab 13 Maps erscheint die Liste in der Konsole |
| `!mapinfo [map]` | für alle (Diagnose: `map`) | Details einer Map (ohne Angabe: aktuelle Map). Mit Recht `map` zusätzlich Profilpfad, Fehler, Hinweise und aktive Overrides |
| `!mapprofile` | `map` | Profil der aktuellen Map neu laden: Overrides zurücknehmen, Datei neu prüfen, neu anwenden |

Begründung: Lesen ändert nichts. Mapnamen, öffentliche Workshop-IDs, Mapcycle und bekannte Fehler sind keine Geheimnisse und helfen Spielern beim Melden von Map-Problemen. Die Ausgabe geht nur an den Aufrufer, und die Registry wird höchstens alle 10 Sekunden neu eingelesen. Diagnose und Änderungen bleiben dem Recht `map` vorbehalten (Admin+), das auch `!map` (Mapwechsel) steuert. `modules` wäre fachlich falsch, denn es steuert das Ein- und Ausschalten von Modulen.

## Server-API

| Funktion | Rückgabe |
|---|---|
| `Maps.Refresh(force)` | Registry, Warnungen (Cache 10 s) |
| `Maps.Get(name)` / `Maps.List()` | Eintrag / sortierte Liste, Warnungen |
| `Maps.Current()` | `{ map, name, profileInfo, profile, spawns, overrideResults }` oder `nil` |
| `Maps.ActiveOverrides()` | Liste `{ key, applied, hadStored, stored }` |
| `Maps.LoadProfile(map)` | `{ name, path, exists, state, profile, errors, warnings }` |
| `Maps.GetEffectiveSpawns()` | `{ player, weapon, ammo, spawnFile }` oder `nil` |
| `Maps.ReloadProfile(actorName)` | `true, info, ergebnisse` / `false, fehler` |
| `Maps.NewOverrides({ journal, actor })` | unabhängige Override-Instanz (Tests): `:Apply(map, overrides)`, `:Revert(grund)`, `:Recover()`, `:HandleExternalChange(key)`, `:List()` |

Shared (reine Funktionen): `NormalizeName`, `ValidateOverride(key, wert, getDef)`, `ValidateProfile(raw, { getDef })`, `ParseMapcycle(text)`, `BuildRegistry(quellen)`, `SortedList(registry)`.

## Tests

`lua/lmnt/tests/sv_maps.lua` (`!test`) prüft Namen und Mapcycle, die Override-Validierung (Typen, Grenzen, verbotene Keys), die Profil-Validierung (UTF-8-Länge, Listen, Teilgültigkeit) und den Registry-Aufbau (nichts aus Namen abgeleitet, unbekannt ≠ false). Gegen das echte `LMNT.Settings` mit eigenen Test-Keys und eigenem Journal prüft sie außerdem: Rücknahme ohne DB-Rest, Wiederherstellung eines Ingame-Werts, Actor „Map-Profil“, Admin-Übernahme, Absturz-Wiederherstellung, `skipped` und `pending`. Dazu kommen Modul-Hooks und die aktuelle Map.

**Nur im laufenden Server prüfbar:** echte BSP-Liste und Mapcycle-Lesbarkeit (`file.Find`/`file.Read` im GAME-Pfad), Spawn-Zählung über TTT2 bei `InitPostEntity`, `ShutDown` beim echten `changelevel` und die Wiederherstellung nach einem echten Absturz über einen Neustart.
