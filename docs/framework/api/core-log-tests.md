# API: Core, Log, Datenbank, Tests (seit 1.1.0)

## Core (`sh_core.lua`, shared)

| Funktion | Rückgabe | Hinweise |
|---|---|---|
| `LMNT.Version` | `"1.1.0"` | SemVer |
| `LMNT.CompareVersions(a, b)` | -1/0/1 | numerisch, `1.2.0 < 1.10.0` |
| `LMNT.VersionAtLeast(v)` | bool | |
| `LMNT.RequireVersion(v, wer)` | – | `error` mit Klartext, wenn zu alt |
| `LMNT.GetPhase()` | `boot`/`services`/`modules`/`ready` | |
| `LMNT.OnReady(fn)` | – | sofort oder beim Erreichen von `ready` |
| `LMNT.Include(pfad)` | – | Realm über Präfix `sv_`/`cl_`/`sh_` |

## Log (`sv_log.lua`, server)

| Funktion | Hinweise |
|---|---|
| `LMNT.Log.Debug/Info/Warn/Error/Security(kategorie, text)` | `debug` nur mit `lmnt_log_debug 1`. `warn` und höher zusätzlich farbig in der Konsole. `security` zusätzlich an das Online-Team |
| `LMNT.Log(kategorie, text)` | **veraltet seit 1.1.0** (= `Info`), bleibt kompatibel |
| `LMNT.GetLogs(limit, kategorie, suche, stufe)` | max. 1000 |
| `LMNT.Log.Export(kategorie, suche)` → pfad, anzahl | CSV (`;`-getrennt) nach `data/lmnt/exports/`, max. 10.000 Zeilen, Befehl `!logexport` (Recht `logs.export`) |

Speicher: Tabelle `lmnt_logs` (Spalte `level` seit 1.1.0, Indizes auf Zeit und Kategorie, max. 200.000 Zeilen, Aufbewahrung `core.log.retention_days`) und Tagesdateien `data/lmnt/logs/` (max. 20 MB pro Tag).
**Manipulationsschutz:** Die Logs sind nur serverseitig beschreibbar und Admin-Aktionen werden doppelt protokolliert. Sie sind aber **nicht unveränderbar**, denn wer Dateizugriff auf den Server hat, kann sie ändern.

## Datenbank (`sv_db.lua`, server)

| Funktion | Rückgabe |
|---|---|
| `LMNT.DB.Query(sql, ...)` | Zeilen oder `nil`. `?` wird sicher ersetzt (Strings escaped) |
| `LMNT.DB.Row` / `Value` | erste Zeile / erster Wert |
| `LMNT.DB.Transaction(fn)` | `true, ergebnis` oder `false, fehler` (Rollback) |
| `LMNT.DB.ColumnExists(t, c)` / `EnsureColumn(t, c, def)` | idempotente Migration |

SQLite in GMod ist **synchron**. Es gibt keine vorgetäuschte Asynchronität (ADR-003).

## Unit-Tests (`sv_test.lua` + `lua/lmnt/tests/sv_*.lua`)

Ausführen mit `!test`, `lmnt test` (Konsole/RCON) oder automatisch über `tools\test_server.ps1`. Die letzte Zeile lautet immer `LMNT-TESTS: <n> bestanden, <m> fehlgeschlagen`.

```lua
LMNT.Test.Describe("Mein Modul", function(t)
	t:It("rechnet richtig", function(e)
		e:Equal(1 + 1, 2)
		e:True(true) e:False(false)
		e:Error(function() error("x") end)
	end)
end)
```

## Diagnose-Befehle

| Befehl | Recht | Zweck |
|---|---|---|
| `!status` | dev | Version, Phase, TTT2-Version, Module, Event-Fehler, DB-Größe |
| `!modules` | modules | alle Module mit Zustand und Anzahl Registrierungen |
| `!module <id> an\|aus\|reload` | modules | Laufzeit-Umschaltung (persistiert, wirkt auf Clients) |
| `!config …` | config | siehe settings.md |
| `!events` | dev | Event-Statistik |
| `!hooks` | dev | LMNT-Hooks pro GMod-Hook (Doppelregistrierungen finden) |
| `!logexport` | logs.export | CSV-Export |
| `!test` | dev | Unit-Tests |
