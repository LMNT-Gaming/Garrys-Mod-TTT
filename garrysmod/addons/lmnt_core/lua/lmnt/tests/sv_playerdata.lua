-- LMNT Unit-Tests: Migrationen (T-032) und Spielerdaten-Cache (T-033)
-- Nur Test-Modulnamen und erfundene SteamID64; jeder Test räumt vorher und nachher auf.
local T = LMNT.Test
local PD = LMNT.PlayerData
local R = PD.Raw

local MIG = "lmnt_test.migrate"
local MIG_TABLE = "lmnt_test_mig"
local MOD = "lmnt_test.pd"
-- SteamID64 unterhalb von 76561197960265728 gehören zu keinem echten Steam-Konto
local A, B, C, D = "76561190000000101", "76561190000000102", "76561190000000103", "76561190000000104"

local function cleanupMigration()
	LMNT.DB.Query("DELETE FROM lmnt_schema WHERE module = ?", MIG)
	LMNT.DB.Query("DROP TABLE IF EXISTS " .. MIG_TABLE)
end

local function cleanupData()
	for _, sid in ipairs({ A, B, C, D }) do
		R.Unload(sid, true)
		LMNT.DB.Query("DELETE FROM lmnt_player_data WHERE steamid = ? AND module = ?", sid, MOD)
	end
end

local function rowCount(sid)
	return tonumber(LMNT.DB.Value("SELECT COUNT(*) FROM lmnt_player_data WHERE steamid = ? AND module = ?", sid, MOD))
end

-- Führt fn aus, während jede Abfrage des Dienstes fehlschlägt (simulierter Datenbankfehler)
local function withFailingDB(fn)
	local original = PD._query
	PD._query = function() return nil, "simulierter Datenbankfehler (Test)" end
	local ok, a, b = pcall(fn)
	PD._query = original
	if not ok then error(a, 0) end
	return a, b
end

T.Describe("DB.QueryStrict", function(t)
	t:It("unterscheidet leeres Ergebnis von SQL-Fehler", function(e)
		local rows = LMNT.DB.QueryStrict("SELECT version FROM lmnt_schema WHERE module = ?", "lmnt_test.gibt_es_nicht")
		e:True(istable(rows) and #rows == 0, "leeres Ergebnis ist eine leere Tabelle")

		local bad, err = LMNT.DB.QueryStrict("SELECT * FROM lmnt_test_gibt_es_nicht")
		e:Equal(bad, nil, "SQL-Fehler liefert nil")
		e:True(isstring(err) and err ~= "", "Fehlermeldung vorhanden")

		e:Equal(LMNT.DB.QueryStrict("SELECT ? AS v", "x'); --")[1].v, "x'); --", "Bindung escaped Strings")
	end)
end)

T.Describe("DB.Migrate", function(t)
	t:It("führt fehlende Schritte in aufsteigender Reihenfolge aus", function(e)
		cleanupMigration()
		local order = {}
		local steps = {}
		-- absichtlich in umgekehrter Reihenfolge eingetragen
		steps[3] = function(exec) order[#order + 1] = 3 exec("ALTER TABLE " .. MIG_TABLE .. " ADD COLUMN c INTEGER") end
		steps[2] = function(exec) order[#order + 1] = 2 exec("ALTER TABLE " .. MIG_TABLE .. " ADD COLUMN b TEXT") end
		steps[1] = function(exec) order[#order + 1] = 1 exec("CREATE TABLE " .. MIG_TABLE .. " (a INTEGER)") end

		local ok, version = LMNT.DB.Migrate(MIG, steps)
		e:True(ok, "Migration erfolgreich")
		e:Equal(version, 3)
		e:Equal(table.concat(order, ","), "1,2,3")
		e:Equal(LMNT.DB.SchemaVersion(MIG), 3)
		e:True(LMNT.DB.ColumnExists(MIG_TABLE, "c"), "Spalte aus Schritt 3")
		cleanupMigration()
	end)

	t:It("ist idempotent: zweiter Lauf führt nichts aus, neue Schritte laufen allein", function(e)
		cleanupMigration()
		local calls = { 0, 0 }
		local steps = {
			function(exec) calls[1] = calls[1] + 1 exec("CREATE TABLE " .. MIG_TABLE .. " (a INTEGER)") end,
		}
		e:True(LMNT.DB.Migrate(MIG, steps))
		local ok, version = LMNT.DB.Migrate(MIG, steps)
		e:True(ok, "zweiter Lauf")
		e:Equal(version, 1)
		e:Equal(calls[1], 1, "Schritt 1 lief nur einmal")

		steps[2] = function(exec) calls[2] = calls[2] + 1 exec("ALTER TABLE " .. MIG_TABLE .. " ADD COLUMN b TEXT") end
		ok, version = LMNT.DB.Migrate(MIG, steps)
		e:True(ok, "Lauf mit neuem Schritt")
		e:Equal(version, 2)
		e:Equal(calls[1], 1, "Schritt 1 nicht wiederholt")
		e:Equal(calls[2], 1, "Schritt 2 genau einmal")
		cleanupMigration()
	end)

	t:It("bricht bei einem Fehler ab: Rollback, Version bleibt beim letzten erfolgreichen Schritt", function(e)
		cleanupMigration()
		local ran3 = false
		local steps = {
			function(exec) exec("CREATE TABLE " .. MIG_TABLE .. " (a INTEGER)") end,
			function(exec)
				exec("INSERT INTO " .. MIG_TABLE .. " (a) VALUES (1)")
				error("absichtlicher Testfehler")
			end,
			function() ran3 = true end,
		}

		local ok, version, err = LMNT.DB.Migrate(MIG, steps)
		e:False(ok, "Migration meldet Fehler")
		e:Equal(version, 1)
		e:True(isstring(err) and string.find(err, "Schritt 2", 1, true) ~= nil, "Fehlermeldung nennt Schritt 2")
		e:False(ran3, "Schritt 3 darf nicht laufen")
		e:Equal(LMNT.DB.SchemaVersion(MIG), 1)
		e:Equal(LMNT.DB.Value("SELECT COUNT(*) FROM " .. MIG_TABLE), "0", "Einfügen aus Schritt 2 zurückgerollt")

		-- Nach der Korrektur laufen genau die fehlenden Schritte
		steps[2] = function(exec) exec("INSERT INTO " .. MIG_TABLE .. " (a) VALUES (1)") end
		ok, version = LMNT.DB.Migrate(MIG, steps)
		e:True(ok, "Lauf nach Korrektur")
		e:Equal(version, 3)
		e:True(ran3, "Schritt 3 lief nach der Korrektur")
		e:Equal(LMNT.DB.Value("SELECT COUNT(*) FROM " .. MIG_TABLE), "1")
		cleanupMigration()
	end)

	t:It("SQL-Fehler über exec bricht ab und rollt den ganzen Schritt zurück", function(e)
		cleanupMigration()
		local ok, version = LMNT.DB.Migrate(MIG, {
			function(exec)
				exec("CREATE TABLE " .. MIG_TABLE .. " (a INTEGER)")
				exec("INSERT INTO lmnt_test_gibt_es_nicht (a) VALUES (1)")
			end,
		})
		e:False(ok)
		e:Equal(version, 0)
		e:Equal(LMNT.DB.SchemaVersion(MIG), 0)
		e:False(sql.TableExists(MIG_TABLE), "CREATE TABLE zurückgerollt")
		cleanupMigration()
	end)

	t:It("Lücken, falsche Schlüssel und Nicht-Funktionen sind Programmierfehler", function(e)
		cleanupMigration()
		local fn = function() end
		e:Error(function() LMNT.DB.Migrate(MIG, { [1] = fn, [3] = fn }) end, "Lücke")
		e:Error(function() LMNT.DB.Migrate(MIG, { fn, "kein Schritt" }) end, "Nicht-Funktion")
		e:Error(function() LMNT.DB.Migrate(MIG, { eins = fn }) end, "Text-Schlüssel")
		e:Error(function() LMNT.DB.Migrate("", { fn }) end, "leerer Modulname")
		e:Equal(LMNT.DB.SchemaVersion(MIG), 0, "nichts ausgeführt")
	end)

	t:It("führt nichts aus, wenn die Datenbank neuer ist als der Code", function(e)
		cleanupMigration()
		e:True(LMNT.DB.Migrate(MIG, {
			function(exec) exec("CREATE TABLE " .. MIG_TABLE .. " (a INTEGER)") end,
			function(exec) exec("ALTER TABLE " .. MIG_TABLE .. " ADD COLUMN b TEXT") end,
		}))

		local ran = false
		local ok, version = LMNT.DB.Migrate(MIG, { function() ran = true end })
		e:False(ok)
		e:Equal(version, 2)
		e:False(ran, "kein Schritt ausgeführt")
		e:Equal(LMNT.DB.SchemaVersion(MIG), 2, "Version unverändert")
		cleanupMigration()
	end)

	t:It("verweigert den Start innerhalb einer laufenden Transaktion", function(e)
		cleanupMigration()
		local ran = false
		local result
		LMNT.DB.Transaction(function()
			result = { LMNT.DB.Migrate(MIG, { function() ran = true end }) }
		end)
		e:False(result[1])
		e:False(ran)
		e:Equal(LMNT.DB.SchemaVersion(MIG), 0)
		cleanupMigration()
	end)
end)

T.Describe("PlayerData.ValidateValue", function(t)
	local V = PD.ValidateValue

	t:It("erlaubt Zahl, Text, Bool und flache Tabellen", function(e)
		e:True(V(42), "Ganzzahl")
		e:True(V(-0.5), "Kommazahl")
		e:True(V('Text mit "Anführungszeichen", \\ und Ümlauten'), "Text")
		e:True(V(false), "Bool")
		e:True(V({ 1, 2, 3 }), "Liste")
		e:True(V({ farbe = "rot", stufe = 3, aktiv = true }), "Text-Schlüssel")
	end)

	t:It("lehnt andere Typen, Verschachtelung und problematische Schlüssel ab", function(e)
		e:False(V(function() end), "Funktion")
		e:False(V(Vector(1, 2, 3)), "Vector")
		e:False(V(0 / 0), "NaN")
		e:False(V(math.huge), "Unendlich")
		e:False(V(nil), "nil (Löschen geht über Set mit nil)")
		e:False(V({ a = { b = 1 } }), "verschachtelte Tabelle")
		e:False(V({ 1, 2, x = 3 }), "Liste mit Text-Schlüssel gemischt")
		e:False(V({ ["5"] = "x" }), "numerischer Text-Schlüssel")
		e:False(V({ [5] = "x" }), "Zahlenschlüssel ohne Liste ab 1")
	end)

	t:It("Größenlimit für Texte und Tabellen", function(e)
		local L = PD.Limits
		e:True(V(string.rep("x", L.valueBytes - 2)), "genau an der Grenze (2 Bytes für Anführungszeichen)")
		e:False(V(string.rep("x", L.valueBytes - 1)), "ein Byte zu viel")

		local big = {}
		for i = 1, L.tableEntries + 1 do big[i] = i end
		e:False(V(big), "ein Eintrag zu viel")
		big[#big] = nil
		e:True(V(big), "genau an der Grenze")
	end)
end)

T.Describe("PlayerData (interne Ebene über SteamID64)", function(t)
	t:It("Tabelle ist per Migration angelegt", function(e)
		e:True(PD._ready, "Migration core.playerdata erfolgreich")
		e:True((LMNT.DB.SchemaVersion("core.playerdata") or 0) >= 1, "Schemaversion >= 1")
		e:True(sql.TableExists("lmnt_player_data"))
	end)

	t:It("Set, Flush und erneutes Laden liefern exakt dieselben Werte", function(e)
		cleanupData()
		e:True(R.Load(A), "Laden")
		e:Equal(R.Status(A), "loaded")
		e:True(R.Set(A, MOD, "punkte", 42))
		e:True(R.Set(A, MOD, "anteil", 0.1))
		e:True(R.Set(A, MOD, "gross", 2 ^ 40 + 1))
		e:True(R.Set(A, MOD, "zahltext", "123"))
		e:True(R.Set(A, MOD, "name", 'Max "der" Tester \\ ä\nZeile 2'))
		e:True(R.Set(A, MOD, "vip", false))
		e:True(R.Set(A, MOD, "liste", { "a", "b" }))
		e:True(R.Set(A, MOD, "karte", { farbe = "rot", stufe = 3 }))

		local ok, count = R.Flush(A)
		e:True(ok, "Flush")
		e:Equal(count, 8)
		e:Equal(rowCount(A), 8)

		e:True(R.Unload(A), "Freigeben")
		e:Equal(R.Status(A), "not_loaded")
		e:True(R.Load(A), "erneut laden")
		e:Equal(R.Get(A, MOD, "punkte"), 42)
		e:Equal(R.Get(A, MOD, "anteil"), 0.1, "Kommazahl exakt")
		e:Equal(R.Get(A, MOD, "gross"), 2 ^ 40 + 1, "große Ganzzahl exakt")
		e:Equal(R.Get(A, MOD, "zahltext"), "123", "Text bleibt Text")
		e:Equal(R.Get(A, MOD, "name"), 'Max "der" Tester \\ ä\nZeile 2', "Sonderzeichen")
		e:Equal(R.Get(A, MOD, "vip", true), false, "false ist ein Wert, nicht der Standard")
		e:Equal(R.Get(A, MOD, "liste")[2], "b")
		e:Equal(R.Get(A, MOD, "karte").stufe, 3)
		cleanupData()
	end)

	t:It("Dirty-Tracking: nur Änderungen werden geschrieben, Löschen entfernt die Zeile", function(e)
		cleanupData()
		e:True(R.Load(B))
		e:Equal(R.DirtyCount(B), 0)
		R.Set(B, MOD, "a", 1)
		R.Set(B, MOD, "a", 2)
		e:Equal(R.DirtyCount(B), 1, "zweimal derselbe Schlüssel = ein Eintrag")
		R.Set(B, MOD, "b", "x")
		e:Equal(R.DirtyCount(B), 2)

		local _, count = R.Flush(B)
		e:Equal(count, 2)
		e:Equal(R.DirtyCount(B), 0, "nach dem Flush sauber")

		R.Set(B, MOD, "a", 2)
		e:Equal(R.DirtyCount(B), 0, "unveränderter Wert markiert nichts")
		local ok, nothing = R.Flush(B)
		e:True(ok)
		e:Equal(nothing, 0, "nichts zu schreiben")

		R.Set(B, MOD, "b", nil)
		e:Equal(R.DirtyCount(B), 1, "Löschen ist eine Änderung")
		e:Equal(R.Get(B, MOD, "b", "weg"), "weg", "gelöscht -> Standardwert")
		R.Flush(B)
		e:Equal(rowCount(B), 1, "Zeile b in der DB gelöscht, a bleibt")
		cleanupData()
	end)

	t:It("erneutes Laden behält ungespeicherte Änderungen (kein Überschreiben aus der DB)", function(e)
		cleanupData()
		e:True(R.Load(B))
		R.Set(B, MOD, "punkte", 10)
		R.Flush(B)
		R.Set(B, MOD, "punkte", 11)
		e:True(R.Load(B))
		e:Equal(R.Get(B, MOD, "punkte"), 11)
		e:Equal(R.DirtyCount(B), 1)
		cleanupData()
	end)

	t:It("Increment zählt hoch und prüft den Typ", function(e)
		cleanupData()
		e:True(R.Load(B))
		local ok, value = R.Increment(B, MOD, "kills", 1)
		e:True(ok)
		e:Equal(value, 1, "fehlender Wert zählt ab 0")
		_, value = R.Increment(B, MOD, "kills", 4)
		e:Equal(value, 5)
		_, value = R.Increment(B, MOD, "kills", -2)
		e:Equal(value, 3)

		R.Set(B, MOD, "name", "Text")
		e:False(R.Increment(B, MOD, "name", 1), "Text lässt sich nicht hochzählen")
		e:False(R.Increment(B, MOD, "kills", "1"), "delta muss eine Zahl sein")
		e:False(R.Increment(B, MOD, "kills", 0 / 0), "NaN als delta")
		e:Equal(R.Get(B, MOD, "kills"), 3, "fehlgeschlagene Aufrufe ändern nichts")
		cleanupData()
	end)

	t:It("Typprüfung, Größenlimit und Namen: Ungültiges wird abgelehnt und nicht markiert", function(e)
		cleanupData()
		e:True(R.Load(A))
		e:False(R.Set(A, MOD, "f", function() end), "Funktion")
		e:False(R.Set(A, MOD, "t", { a = {} }), "verschachtelt")
		e:False(R.Set(A, MOD, "gross", string.rep("x", PD.Limits.valueBytes)), "zu groß")
		e:False(R.Set(A, "", "x", 1), "leerer Modulname")
		e:False(R.Set(A, MOD, "mit leerzeichen", 1), "unerlaubte Zeichen im Schlüssel")
		e:False(R.Set(A, MOD, string.rep("k", PD.Limits.nameLength + 1), 1), "zu langer Schlüssel")
		e:Equal(R.DirtyCount(A), 0, "nichts markiert")
		e:False(R.Load(76561190000000101), "SteamID64 als Zahl wird abgelehnt")
		e:False(R.Load("123"), "zu kurze SteamID64")
		cleanupData()
	end)

	t:It("Get liefert Standardwert bei fehlendem Schlüssel und Kopien von Tabellen; Statistik zählt", function(e)
		cleanupData()
		e:True(R.Load(A))
		local before = PD.Stats()
		e:Equal(R.Get(A, MOD, "fehlt", 7), 7)
		R.Set(A, MOD, "karte", { farbe = "rot" })
		local copy = R.Get(A, MOD, "karte")
		copy.farbe = "blau"
		e:Equal(R.Get(A, MOD, "karte").farbe, "rot", "Änderung an der Kopie wirkt nicht auf den Cache")

		local after = PD.Stats()
		e:Equal(after.misses - before.misses, 1, "Fehlzugriff gezählt")
		e:Equal(after.hits - before.hits, 2, "Treffer gezählt")
		e:True(after.dirty >= 1, "Dirty-Einträge in der Statistik")
		cleanupData()
	end)

	t:It("Ladefehler: dataUnavailable, Get/Set liefern klare Fehler, erneutes Laden klappt", function(e)
		cleanupData()
		local before = PD.Stats()
		local ok, err = withFailingDB(function() return R.Load(C) end)
		e:False(ok, "Laden schlägt fehl")
		e:True(isstring(err), "Grund wird geliefert")
		e:Equal(R.Status(C), "unavailable")

		local value, getErr = R.Get(C, MOD, "punkte", 0)
		e:Equal(value, nil, "kein Standardwert bei dataUnavailable")
		e:True(isstring(getErr) and string.find(getErr, "dataUnavailable", 1, true) ~= nil, "Fehler nennt dataUnavailable")

		local setOk, setErr = R.Set(C, MOD, "punkte", 5)
		e:False(setOk, "Set wird abgewiesen")
		e:True(isstring(setErr) and string.find(setErr, "NICHT", 1, true) ~= nil, "Fehler sagt, dass nichts übernommen wurde")
		e:False(R.Increment(C, MOD, "punkte", 5), "Increment wird abgewiesen")
		e:Equal(PD.Stats().rejected - before.rejected, 3, "abgewiesene Zugriffe gezählt")
		e:False(R.Flush(C), "Flush meldet, dass nichts gesichert werden kann")

		e:True(R.Load(C), "erneuter Ladeversuch nach Behebung")
		e:Equal(R.Status(C), "loaded")
		e:True(R.Set(C, MOD, "punkte", 5))
		cleanupData()
	end)

	t:It("Speicherfehler: Änderungen bleiben dirty und werden beim nächsten Flush geschrieben", function(e)
		cleanupData()
		e:True(R.Load(D))
		R.Set(D, MOD, "punkte", 9)
		local ok = withFailingDB(function() return R.Flush(D) end)
		e:False(ok, "Flush schlägt fehl")
		e:Equal(R.DirtyCount(D), 1, "Änderung bleibt markiert")
		e:Equal(rowCount(D), 0, "nichts halb geschrieben")
		e:Equal(R.Get(D, MOD, "punkte"), 9, "Wert bleibt im Cache")

		e:True(R.Flush(D), "nächster Flush klappt")
		e:Equal(rowCount(D), 1)
		e:Equal(R.DirtyCount(D), 0)
		cleanupData()
	end)

	t:It("Unload schützt ungespeicherte Änderungen; Flush in fremder Transaktion wird verweigert", function(e)
		cleanupData()
		e:True(R.Load(A))
		R.Set(A, MOD, "x", 1)
		e:False(R.Unload(A), "Unload mit Dirty-Einträgen verweigert")
		e:Equal(R.Status(A), "loaded")

		local inner
		LMNT.DB.Transaction(function() inner = { R.Flush(A) } end)
		e:False(inner[1], "Flush innerhalb einer Transaktion verweigert")
		e:Equal(R.DirtyCount(A), 1, "bleibt markiert")

		e:True(R.Unload(A, true), "Verwerfen ausdrücklich erlaubt")
		e:Equal(R.Status(A), "not_loaded")
		e:Equal(rowCount(A), 0)
		cleanupData()
	end)

	t:It("beschädigte Werte werden gemeldet und bleiben in der DB unverändert", function(e)
		cleanupData()
		LMNT.DB.Query("INSERT INTO lmnt_player_data (steamid, module, key, value, updated_at) VALUES (?, ?, ?, ?, ?)", A, MOD, "kaputt", "{nicht json", os.time())
		local before = PD.Stats().corrupt
		e:True(R.Load(A), "Laden gelingt trotzdem")
		e:Equal(R.Get(A, MOD, "kaputt", "std"), "std")
		e:Equal(PD.Stats().corrupt - before, 1, "gezählt")
		e:Equal(LMNT.DB.Value("SELECT value FROM lmnt_player_data WHERE steamid = ? AND module = ? AND key = ?", A, MOD, "kaputt"), "{nicht json", "Rohwert bleibt erhalten")
		cleanupData()
	end)

	t:It("Spieler-API lehnt ungültige Spieler ab", function(e)
		local value, err = PD.Get(NULL, MOD, "x", 1)
		e:Equal(value, nil, "kein Standardwert")
		e:True(isstring(err))
		e:False(PD.Set(nil, MOD, "x", 1))
		e:False(PD.Increment(NULL, MOD, "x", 1))
		e:False(PD.IsLoaded(NULL))
		e:False(PD.Flush(NULL))
	end)
end)
