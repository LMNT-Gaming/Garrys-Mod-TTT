# API: Migrationen und LMNT.PlayerData (T-032, T-033)

Dateien: `lmnt_core/lua/lmnt/services/sv_migrations.lua`, `lmnt_core/lua/lmnt/services/sv_playerdata.lua` · Realm: Server
Tests: `lmnt_core/lua/lmnt/tests/sv_playerdata.lua` · Grundlage: ADR-003 (SQLite synchron, Cache, gebündeltes Schreiben)

Beide Dateien liegen in `lua/lmnt/services/` und werden vom Core automatisch geladen. Die Reihenfolge ist alphabetisch, deshalb steht `sv_migrations` vor `sv_playerdata`. Der Spielerdaten-Dienst legt seine Tabelle selbst über `LMNT.DB.Migrate` an (Modul `core.playerdata`).

## Migrationen

| Funktion | Rückgabe | Hinweise |
|---|---|---|
| `LMNT.DB.Migrate(modul, schritte)` | `ok, version, fehler` | `version` = Stand nach dem Lauf (letzter erfolgreicher Schritt) |
| `LMNT.DB.SchemaVersion(modul)` | Zahl (`0` = nie migriert) / `nil, fehler` | liest `lmnt_schema` |
| `LMNT.DB.QueryStrict(sql, ...)` | Zeilen (leere Tabelle, wenn keine) / `nil, fehler` | wie `LMNT.DB.Query`, aber ein SQL-Fehler ist von „keine Zeilen“ unterscheidbar und wird zurückgegeben statt ausgegeben |

Tabelle `lmnt_schema`: `module TEXT PRIMARY KEY, version INTEGER NOT NULL, applied_at INTEGER NOT NULL`.

```lua
LMNT.DB.Migrate("mein.modul", {
	[1] = function(exec)
		exec("CREATE TABLE IF NOT EXISTS mein_modul_daten (id INTEGER PRIMARY KEY, wert TEXT)")
	end,
	[2] = function(exec)
		exec("ALTER TABLE mein_modul_daten ADD COLUMN erstellt INTEGER")
	end,
})
```

**Regeln**
- Fehlende Schritte laufen aufsteigend, **jeder in einer eigenen Transaktion**. Der Eintrag in `lmnt_schema` wird in derselben Transaktion geschrieben, Schritt und Versionsnummer sind also atomar.
- Wirft ein Schritt einen Fehler, wird dieser Schritt zurückgerollt und die Migration bricht ab. Es entsteht ein `error`-Log in der Kategorie `db`. Die Version bleibt beim letzten erfolgreichen Schritt, spätere Schritte laufen nicht. Ein erneuter Aufruf (nach der Korrektur) setzt genau dort fort.
- In Schritten **`exec(...)` verwenden, nicht `LMNT.DB.Query(...)`**. `LMNT.DB.Query` gibt bei einem SQL-Fehler nur `nil` zurück und schreibt in die Konsole. Die Transaktion würde dann trotzdem bestätigt. `exec` wirft bei einem SQL-Fehler und löst so den Rollback aus.
- Idempotent: Ein zweiter Lauf mit denselben Schritten führt nichts aus.
- Die Schritte müssen lückenlos ab 1 nummeriert und Funktionen sein, sonst gibt es einen `error` (Programmierfehler). Veröffentlichte Schritte werden nie geändert, nur ergänzt.
- Ist die Datenbank neuer als der Code (Version > Anzahl Schritte), läuft nichts und das Ergebnis ist `false` mit Begründung.
- Innerhalb einer laufenden Transaktion wird `Migrate` verweigert. `LMNT.DB.Transaction` würde dort nur `pcall` ausführen, ein fehlerhafter Schritt wäre dann nicht zurückrollbar.

## LMNT.PlayerData

Ein Profil pro SteamID64, Werte in Modul-Namensräumen, Tabelle `lmnt_player_data`:

| Spalte | Typ | Inhalt |
|---|---|---|
| `steamid` | TEXT | SteamID64 als Text |
| `module` | TEXT | Namensraum, z. B. `ttt.stats` |
| `key` | TEXT | Schlüssel im Namensraum |
| `value` | TEXT | JSON-Fragment (`42`, `0.1`, `true`, `"Text"`, `[1,2]`, `{"a":1}`), Format wie `lmnt_config` |
| `updated_at` | INTEGER | Unix-Zeit des letzten Schreibens |

Primärschlüssel `(steamid, module, key)`, Index `lmnt_player_data_module` auf `module`.

### Funktionen

| Funktion | Rückgabe | Hinweise |
|---|---|---|
| `Get(ply, modul, key, standard)` | Wert / `nil, fehler` | Tabellen werden als Kopie geliefert. Fehlt der Schlüssel, kommt `standard`. Sind die Daten nicht geladen oder nicht verfügbar, kommt `nil, fehler`, **nie** der Standardwert |
| `Set(ply, modul, key, wert)` | `true` / `false, fehler` | `wert = nil` löscht den Schlüssel. Ein unveränderter Wert erzeugt keinen Schreibvorgang |
| `Increment(ply, modul, key, delta)` | `true, neuerWert` / `false, fehler` | Ein fehlender Wert zählt ab 0. Ist der vorhandene Wert keine Zahl, kommt ein Fehler |
| `IsLoaded(ply)` | bool | nur `true`, wenn Get/Set möglich sind |
| `Status(ply)` | `"loaded"` / `"unavailable", grund` / `"not_loaded"` | `unavailable` = Flag **dataUnavailable** |
| `Load(ply)` | `true` / `false, fehler` | läuft automatisch bei `PlayerInitialSpawn` (eine Abfrage pro Spieler). Bei dataUnavailable ist ein erneuter Aufruf möglich |
| `Flush(ply)` | `true, anzahl` / `false, fehler` | schreibt die geänderten Einträge des Spielers in einer Transaktion |
| `FlushAll()` | `true, anzahl` / `false, fehler` | alle geänderten Profile in **einer** Transaktion |
| `Stats()` | Tabelle | siehe Statistik |
| `ValidateValue(wert)` | `true, json` / `false, fehler` | die Prüfung, die `Set` verwendet |
| `Limits` | `{ valueBytes, tableEntries, nameLength }` | 4096 / 64 / 64 |

`LMNT.PlayerData.Raw.Load/Get/Set/Increment/Flush/Status/DirtyCount/Unload(sid, ...)` enthält dieselbe Logik mit einer SteamID64 (Text) statt eines Spielerobjekts. Gedacht ist das für Tests und Werkzeuge, etwa für Änderungen an Offline-Spielern: `Load → Set → Flush → Unload`. `Raw.Unload(sid)` verweigert die Freigabe bei ungespeicherten Änderungen (außer mit `Unload(sid, true)`) und bei verbundenen Spielern. Module verwenden die Spieler-API.

### Werte und Namen
- Erlaubt sind **Zahl** (endlich, kein NaN oder Unendlich), **Text**, **Bool** und **flache Tabellen** aus diesen Typen. Eine flache Tabelle ist entweder eine Liste `1..n` oder eine Tabelle mit nicht-numerischen Text-Schlüsseln. Höchstens 64 Einträge, kodiert höchstens 4096 Bytes.
- Abgelehnt werden verschachtelte Tabellen, gemischte Schlüssel, Zahlenschlüssel ohne Liste und numerische Text-Schlüssel wie `"5"`. `util.JSONToTable` würde solche Schlüssel beim Laden in Zahlen umwandeln.
- Jeder Wert wird beim `Set` kodiert und sofort wieder eingelesen. Was nicht exakt gleich zurückkommt (z. B. Text mit ungültigem UTF-8), wird abgelehnt, statt später verfälscht geladen zu werden. Zahlen werden in der kürzesten exakt rückführbaren Form gespeichert (`0.1`, `1099511627777`).
- Modul- und Schlüsselnamen: 1–64 Zeichen aus Buchstaben, Ziffern und `_ . - :`.

### dataUnavailable (Ladefehler)
Schlägt das Laden fehl (SQL-Fehler oder Tabelle nicht bereit, weil die Migration fehlschlug), bekommt das Profil den Status `unavailable`:
- `Get` liefert `nil, fehler` (mit dem Wort `dataUnavailable`), **nie** den Standardwert. Ein Modul kann also nicht versehentlich mit 0 Punkten weiterrechnen und damit den echten Stand überschreiben.
- `Set`/`Increment` liefern `false, "… – Änderung wurde NICHT übernommen"` und schreiben eine `warn`-Meldung (höchstens einmal pro Minute und Spieler, mit Zähler der unterdrückten Meldungen). Jeder abgewiesene Zugriff erscheint in `Stats().rejected` und `!datastats`.
- **Belohnungen gehen nicht still verloren**: Wer eine Belohnung vergibt, prüft den Rückgabewert (oder vorher `IsLoaded`) und reagiert, etwa mit einem Hinweis an den Spieler. Gemäß Zielarchitektur gibt es keine Belohnungen bis zum erfolgreichen Laden. Abgewiesene Werte werden nicht gepuffert.
- Das Intervall versucht das Laden für betroffene Spieler erneut. Gelingt es, kommt `lmnt.playerdata.loaded` und ein `info`-Log.

### Lebenszyklus
| Zeitpunkt | Was passiert |
|---|---|
| `PlayerInitialSpawn` | `Load`: eine Abfrage, danach Event `lmnt.playerdata.loaded` |
| Intervall (`core.playerdata.flush_interval`, Standard 60 s, 15–1800, wirkt sofort) | `FlushAll` als eine Transaktion, danach erneuter Ladeversuch für dataUnavailable |
| `PlayerDisconnected` | `Flush` des Spielers, danach Freigabe des Caches. Schlägt das Speichern fehl, bleibt das Profil als „wartend“ im Speicher. Das Intervall speichert es nach und gibt es danach frei, ein Reconnect übernimmt den Cache |
| `ShutDown` (auch beim Mapwechsel) | `FlushAll`. Schlägt das fehl, werden alle ungespeicherten Einträge nach `data/lmnt/playerdata_unsaved_<Zeit>.json` geschrieben (manuelle Wiederherstellung) |
| auf Anforderung | `Flush(ply)` / `FlushAll()`, z. B. am Rundenende (Aufruf aus `lmnt_ttt`, der Core kennt kein TTT) |

**Bots** erhalten ein Profil nur im Speicher. Get/Set funktionieren, geschrieben wird nie. So landen keine Bot-Daten in der Datenbank.

### Konsistenzmodell
- **Quelle der Wahrheit während der Sitzung ist der Cache.** Die Datenbank hat den Stand des letzten erfolgreichen Flush. Dazwischen liegende Änderungen sind „dirty“.
- **Gespeichert ist ein Wert erst nach einem erfolgreichen Flush**: Intervall, Disconnect, ShutDown oder expliziter `Flush`. `Set` allein schreibt nichts in die Datenbank.
- **Atomar pro Flush**: Ein Flush schreibt alle geänderten Einträge der betroffenen Profile in einer Transaktion. Entweder ist alles gespeichert oder nichts. Dirty-Markierungen werden erst nach dem Commit entfernt. Nach einem Fehler bleibt alles markiert und wird beim nächsten Flush erneut versucht. Ändert ein Modul Punkte und Inventar desselben Spielers vor einem Flush, landen beide Änderungen gemeinsam.
- **`Set` ist nicht Teil einer DB-Transaktion.** Wird eine eigene `LMNT.DB.Transaction` zurückgerollt, bleiben Cache-Änderungen bestehen. Das Modul muss den alten Wert selbst zurücksetzen (relevant für die Kauf-Transaktion T-035).
- **`Flush`/`FlushAll` innerhalb einer laufenden Transaktion werden verweigert.** Ein späterer Rollback würde sonst Zeilen verwerfen, die der Cache bereits für gespeichert hält.
- **Was bei einem Absturz verloren geht**: Ein Absturz des srcds-Prozesses (Crash, Prozess beendet, Stromausfall) löst **kein** `ShutDown` aus. Verloren sind alle Änderungen seit dem letzten erfolgreichen Flush, also höchstens ein Intervall (Standard 60 s) plus die Änderungen von Spielern, deren Speichern beim Disconnect fehlschlug und die bis dahin nicht nachgespeichert wurden. Ein geordnetes Beenden oder ein Mapwechsel speichert alles. Gelingt auch das nicht, gibt es die Rettungsdatei. Ein Lua-Refresh der Datei behält den Cache.
- **Beschädigte Werte** (nicht lesbares JSON in der Datenbank) werden beim Laden übersprungen, mit Rohwert ins Log geschrieben und in `Stats().corrupt` gezählt. Die Zeile bleibt unverändert, bis das Modul den Schlüssel neu setzt.
- **Bekannte Grenze in `sv_db.lua`**: `LMNT.DB.Transaction` prüft das Ergebnis von `COMMIT` nicht. Scheitert ausgerechnet der Commit (z. B. volle Platte), hält der Dienst die Einträge für gespeichert. Das ist ein Folgepunkt für `sv_db.lua`, nicht Teil dieser Aufgabe.

### Events
| Event | Argumente | Wann |
|---|---|---|
| `lmnt.playerdata.loaded` | `ply` | nach erfolgreichem Laden (auch nach erneutem Versuch oder Reconnect mit übernommenem Cache) |
| `lmnt.playerdata.saved` | `ply, anzahl` | nach erfolgreichem Flush mit `anzahl > 0`, nur für verbundene Spieler (Raw- und wartende Profile lösen kein Event aus) |

Hinweis: Schreibzugriffe aus anderen `PlayerDisconnected`-Hooks können nach der Freigabe des Caches kommen und werden dann als „nicht geladen“ abgewiesen. Die Reihenfolge von GMod-Hooks ist nicht festgelegt.

### Statistik und `!datastats`
`Stats()` liefert `hits` (Get fand den Schlüssel), `misses` (Get ohne Eintrag, Standardwert geliefert), `rejected` (Zugriffe ohne geladene Daten), `dirty` (ungespeicherte Einträge gesamt), `lastFlush` (`at`, `ms`, `entries`, `profiles`, `ok`, `error`; nur Flushes mit Schreibzugriff oder Fehler), `loadErrors`, `flushErrors`, `corrupt`, `profiles`, `online`, `orphans`, `bots`, `unavailable`, `interval`, `ready`.
`!datastats` (Recht `dev`) zeigt diese Werte samt Schemaversion und listet Spieler mit dataUnavailable samt Grund.

## Unit-Tests (`lmnt test`)
Datei `tests/sv_playerdata.lua`, 23 Tests in 4 Gruppen: `DB.QueryStrict` (1), `DB.Migrate` (7: Reihenfolge, Idempotenz, Abbruch mit Rollback und Fortsetzung, SQL-Fehler über `exec`, Programmierfehler, Datenbank neuer als Code, Verweigerung in Transaktion), `PlayerData.ValidateValue` (3: erlaubte Typen, abgelehnte Typen und Schlüssel, Größenlimit) und `PlayerData (interne Ebene über SteamID64)` (12: Tabelle angelegt, Set/Flush/erneutes Laden mit exakten Werten, Dirty-Tracking und Löschen, ungespeicherte Änderungen beim erneuten Laden, Increment, Typ- und Namensprüfung, Standardwerte/Kopien/Statistik, dataUnavailable, Speicherfehler, Unload-Schutz und Transaktionssperre, beschädigte Werte, ungültige Spieler).
Die Tests verwenden die Modulnamen `lmnt_test.migrate` / `lmnt_test.pd`, die Tabelle `lmnt_test_mig` und SteamID64 unterhalb des gültigen Bereichs (`765611900000001xx`). Sie räumen vorher und nachher auf. Datenbankfehler werden über das austauschbare `LMNT.PlayerData._query` simuliert. Erwartete `warn`/`error`-Logs der Kategorien `db` und `playerdata` während der Tests sind gewollt.

## Migrationsplan: `lmnt_ttt_stats` und `lmnt_ps_inventory` → `lmnt_player_data`
Noch **nicht umgesetzt**. `sv_stats.lua` und `sv_pointshop.lua` bleiben unverändert, bis die Umstellung als eigene Aufgabe läuft (T-033 Teil 2 / T-035).

### Spaltenzuordnung
| Alt | Neu (`module` / `key`) | Wert |
|---|---|---|
| `lmnt_ttt_stats.level` | `ttt.stats` / `level` | Zahl, mindestens 1 |
| `xp`, `points`, `kills`, `deaths`, `teamkills`, `wins`, `rounds`, `traitor_rounds`, `playtime` | `ttt.stats` / gleicher Name | Zahl (NULL → 0) |
| `name` | – | nicht übernommen: der Name gehört zum Spielerprofil (`lmnt_users.name`, Ziel `lmnt_players`) |
| `last_seen` | – | nicht übernommen: steht in `lmnt_users.last_seen` |
| `lmnt_ps_inventory (steamid, item, equipped)` | `ttt.pointshop` / `item.<item>` | Bool: `true` = ausgerüstet, `false` = nur besessen. Kein Eintrag = nicht besessen |

Ein Eintrag pro Item statt einer Tabelle pro Spieler: Es gibt kein 64-Einträge-Limit, Kauf und Verkauf ändern nur einen Schlüssel, und Verkaufen ist `Set(…, nil)`. Die Item-IDs (`mdl_kleiner`, `hat_cone`, `trail_laser` …) erfüllen die Namensregeln, `item.` plus ID bleibt unter 64 Zeichen.

### Migrationsschritt (in `lmnt_ttt`, Modul `ttt.stats`)
Er läuft beim Serverstart mit der neuen Modulversion, bevor ein Spieler joint. Es werden nur echte Konten übernommen (`7656119…`, 17 Ziffern), Bot-Zeilen bleiben zurück. `INSERT OR IGNORE` überschreibt nichts, was bereits in `lmnt_player_data` steht. Am Ende prüft der Schritt die Summen. Bei einer Abweichung wirft er einen Fehler und alles wird zurückgerollt.

```lua
local REAL = "steamid GLOB '7656119[0-9]*' AND length(steamid) = 17"
local STAT_FIELDS = { "level", "xp", "points", "kills", "deaths", "teamkills", "wins", "rounds", "traitor_rounds", "playtime" }

LMNT.DB.Migrate("ttt.stats", {
	[1] = function(exec)
		local now = os.time()
		for _, f in ipairs(STAT_FIELDS) do
			local fallback = f == "level" and 1 or 0
			exec("INSERT OR IGNORE INTO lmnt_player_data (steamid, module, key, value, updated_at) " ..
				"SELECT steamid, 'ttt.stats', '" .. f .. "', CAST(CAST(IFNULL(" .. f .. ", " .. fallback .. ") AS INTEGER) AS TEXT), ? " ..
				"FROM lmnt_ttt_stats WHERE " .. REAL, now)
		end
		exec("INSERT OR IGNORE INTO lmnt_player_data (steamid, module, key, value, updated_at) " ..
			"SELECT steamid, 'ttt.pointshop', 'item.' || item, CASE WHEN equipped = 1 THEN 'true' ELSE 'false' END, ? " ..
			"FROM lmnt_ps_inventory WHERE " .. REAL, now)

		-- Kontrolle über die migrierten SteamIDs: Punktesumme und Anzahl der Items müssen übereinstimmen
		local old = exec("SELECT IFNULL(SUM(CAST(IFNULL(points, 0) AS INTEGER)), 0) AS s FROM lmnt_ttt_stats WHERE " .. REAL)[1].s
		local new = exec("SELECT IFNULL(SUM(CAST(value AS INTEGER)), 0) AS s FROM lmnt_player_data WHERE module = 'ttt.stats' AND key = 'points' " ..
			"AND steamid IN (SELECT steamid FROM lmnt_ttt_stats WHERE " .. REAL .. ")")[1].s
		if old ~= new then error("Punktesumme weicht ab: alt " .. old .. ", neu " .. new) end
		local oldItems = exec("SELECT COUNT(*) AS n FROM lmnt_ps_inventory WHERE " .. REAL)[1].n
		local newItems = exec("SELECT COUNT(*) AS n FROM lmnt_player_data WHERE module = 'ttt.pointshop' AND key LIKE 'item.%' " ..
			"AND steamid IN (SELECT steamid FROM lmnt_ps_inventory WHERE " .. REAL .. ")")[1].n
		if oldItems ~= newItems then error("Itemanzahl weicht ab: alt " .. oldItems .. ", neu " .. newItems) end
	end,
})
```
Hat ein Spieler in `lmnt_player_data` schon einen eigenen Wert für denselben Schlüssel, lässt `INSERT OR IGNORE` ihn stehen. Die Summenprüfung schlägt dann an und rollt zurück. Das ist gewollt, denn ein solcher Konflikt braucht eine Entscheidung und keine stille Auflösung.

### Umstellung der Module (danach)
- `sv_stats.lua`: `ply.LMNTStats` entfällt. `AddXP`/`AddPoints` laufen über `Increment` bzw. `Set` (`ttt.stats`), `SaveStats` wird zu `LMNT.PlayerData.Flush(ply)`, am Rundenende kommt `LMNT.PlayerData.FlushAll()`. Startbonus: Nach `lmnt.playerdata.loaded` wird `points` gesetzt, wenn der Schlüssel fehlt. Belohnungen prüfen den Rückgabewert (dataUnavailable). `playtime` wird beim Flush aus der Sitzungsdauer fortgeschrieben.
- `GetTop` liest aus `lmnt_player_data`: `WHERE module = 'ttt.stats' AND key = ?` mit `ORDER BY CAST(value AS INTEGER) DESC`, den Namen per `LEFT JOIN lmnt_users`. Der Index auf `module` reicht für die derzeitige Spielerzahl. Für große Ranglisten ist laut Zielarchitektur `lmnt_stats` vorgesehen.
- `sv_pointshop.lua`: Das Inventar kommt aus `ttt.pointshop/item.*`. Ein Kauf ist `Increment(points, -preis)` plus `Set(item.x, false)`. Beide Änderungen landen im selben Flush und damit in derselben Transaktion (heute sind es drei unabhängige Abfragen).
- Danach werden `lmnt_ttt_stats` und `lmnt_ps_inventory` **nicht mehr beschrieben, aber nicht gelöscht** (Zielarchitektur: „übernommen und danach nicht mehr beschrieben“).

### Rollback-Gedanke
1. **Vorher**: `garrysmod/sv.db` bei gestopptem Server sichern. Der Migrationsschritt verändert die Alt-Tabellen nicht, sie bleiben der Stand zum Umstellungszeitpunkt.
2. **Schritt schlägt fehl**: Die Transaktion rollt automatisch zurück, `ttt.stats` bleibt auf Version 0. Die alten Module laufen dann aber nicht mehr, deshalb ist das Deployment zurückzunehmen, bis der Fehler behoben ist. Es gehen keine Daten verloren.
3. **Rückkehr zum alten Code nach Betrieb mit dem neuen**: Neuere Werte stehen nur in `lmnt_player_data`. Zurückkopieren bei gestopptem Server:
   ```sql
   UPDATE lmnt_ttt_stats SET points = COALESCE((SELECT CAST(value AS INTEGER) FROM lmnt_player_data d
       WHERE d.steamid = lmnt_ttt_stats.steamid AND d.module = 'ttt.stats' AND d.key = 'points'), points);
   -- analog für level, xp, kills, deaths, teamkills, wins, rounds, traitor_rounds, playtime
   DELETE FROM lmnt_ps_inventory WHERE steamid GLOB '7656119[0-9]*';
   INSERT INTO lmnt_ps_inventory (steamid, item, equipped)
       SELECT steamid, substr(key, 6), CASE WHEN value = 'true' THEN 1 ELSE 0 END
       FROM lmnt_player_data WHERE module = 'ttt.pointshop' AND key LIKE 'item.%';
   ```
   Neue Spieler, die es nur in `lmnt_player_data` gibt, erzeugt der alte Code beim nächsten Join neu (Startbonus). Wer sie übernehmen will, braucht zusätzlich ein `INSERT` in `lmnt_ttt_stats`. Den Eintrag `ttt.stats` in `lmnt_schema` lässt man stehen. Ein späterer erneuter Umstieg braucht dann einen Schritt 2, der die Werte aus den Alt-Tabellen erneut übernimmt (dann mit `REPLACE`), weil Schritt 1 bereits als angewendet gilt.
