--[[
	LMNT Service – Schema-Migrationen pro Modul (T-032)
	API-Referenz: docs/framework/api/playerdata.md (Abschnitt „Migrationen“)

	Tabelle lmnt_schema (module, version, applied_at) speichert pro Modul die zuletzt erfolgreich
	angewendete Schemaversion.

	LMNT.DB.Migrate("mein.modul", {
		[1] = function(exec)
			exec("CREATE TABLE IF NOT EXISTS mein_modul_daten (id INTEGER PRIMARY KEY, wert TEXT)")
		end,
		[2] = function(exec)
			exec("ALTER TABLE mein_modul_daten ADD COLUMN erstellt INTEGER")
		end,
	})                                         -> ok, version, fehler
	LMNT.DB.SchemaVersion("mein.modul")       -> version (0 = noch nie migriert) | nil, fehler
	LMNT.DB.QueryStrict(sql, ...)             -> Zeilen (leere Tabelle, wenn keine) | nil, fehler

	Regeln:
	  - Fehlende Schritte laufen in aufsteigender Reihenfolge, jeder in einer EIGENEN Transaktion.
	    Der Eintrag in lmnt_schema wird in derselben Transaktion geschrieben (Schritt + Version atomar).
	  - Fehler in einem Schritt: Rollback dieses Schritts, Abbruch, Log-Fehler. Die Version bleibt beim
	    letzten erfolgreichen Schritt; spätere Schritte laufen nicht.
	  - In Schritten exec(...) statt LMNT.DB.Query(...) verwenden: LMNT.DB.Query meldet SQL-Fehler nur
	    in der Konsole und gibt nil zurück, die Transaktion würde dann trotzdem bestätigt.
	  - Schritte sind fortlaufend nummeriert (1, 2, 3 …). Lücken oder Nicht-Funktionen sind ein
	    Programmierfehler (error). Bereits veröffentlichte Schritte werden nie geändert, nur ergänzt.
	  - Ist die Datenbank neuer als der Code (Version > Anzahl Schritte), wird nichts ausgeführt.
]]

------------------------------------------------------------------------
-- Strenge Abfrage: unterscheidet „keine Zeilen“ von „SQL-Fehler“
------------------------------------------------------------------------

-- Gleiche Bindungsregeln wie bind() in core/sv_db.lua: "?" wird ersetzt, Strings werden escaped,
-- Zahlen direkt eingesetzt, bool als 1/0, nil als NULL.
local function bind(query, args)
	local i = 0

	return (string.gsub(query, "%?", function()
		i = i + 1
		local v = args[i]

		if v == nil then return "NULL" end
		if isnumber(v) then return tostring(v) end
		if isbool(v) then return v and "1" or "0" end

		return sql.SQLStr(tostring(v))
	end))
end

-- LMNT.DB.Query liefert bei einem Fehler und bei einem leeren Ergebnis gleichermaßen nil. Für
-- Migrationen und Spielerdaten muss beides unterscheidbar sein (ein fehlgeschlagenes Laden darf nicht
-- wie ein neuer Spieler ohne Daten aussehen). Gibt den Fehler zurück, statt ihn auszugeben.
function LMNT.DB.QueryStrict(query, ...)
	local q = bind(query, { ... })
	local result = sql.Query(q)

	if result == false then
		return nil, tostring(sql.LastError())
	end

	return result or {}
end

------------------------------------------------------------------------
-- Schematabelle
------------------------------------------------------------------------

local schemaReady = false

local function ensureSchemaTable()
	if schemaReady then return true end

	local rows, err = LMNT.DB.QueryStrict([[CREATE TABLE IF NOT EXISTS lmnt_schema (
		module TEXT PRIMARY KEY,
		version INTEGER NOT NULL,
		applied_at INTEGER NOT NULL
	)]])
	if not rows then return false, "lmnt_schema konnte nicht angelegt werden: " .. err end

	schemaReady = true
	return true
end

local function checkModuleName(module)
	if not isstring(module) or module == "" then
		error("DB.Migrate/SchemaVersion: Modulname fehlt", 3)
	end
end

function LMNT.DB.SchemaVersion(module)
	checkModuleName(module)

	local ok, err = ensureSchemaTable()
	if not ok then return nil, err end

	local rows, qErr = LMNT.DB.QueryStrict("SELECT version FROM lmnt_schema WHERE module = ?", module)
	if not rows then return nil, qErr end

	return rows[1] and tonumber(rows[1].version) or 0
end

------------------------------------------------------------------------
-- Migration
------------------------------------------------------------------------

-- Prüft die Schrittliste (fortlaufend ab 1, nur Funktionen) und liefert die Zielversion
local function stepCount(module, steps)
	local count = 0
	for k, fn in pairs(steps) do
		if not isnumber(k) or k < 1 or math.floor(k) ~= k then
			error("DB.Migrate(" .. module .. "): ungültiger Schlüssel " .. tostring(k) .. " (erwartet 1, 2, 3 …)", 3)
		end
		if not isfunction(fn) then
			error("DB.Migrate(" .. module .. "): Schritt " .. k .. " ist keine Funktion", 3)
		end
		count = count + 1
	end

	for i = 1, count do
		if not steps[i] then
			error("DB.Migrate(" .. module .. "): Schritt " .. i .. " fehlt (Schritte müssen lückenlos ab 1 nummeriert sein)", 3)
		end
	end

	return count
end

-- Wird an jeden Schritt übergeben: wirft bei einem SQL-Fehler und löst damit den Rollback aus
local function exec(query, ...)
	local rows, err = LMNT.DB.QueryStrict(query, ...)
	if not rows then error("SQL-Fehler: " .. err, 2) end
	return rows
end

function LMNT.DB.Migrate(module, steps)
	checkModuleName(module)
	if not istable(steps) then error("DB.Migrate(" .. module .. "): Schrittliste fehlt", 2) end

	local target = stepCount(module, steps)

	-- In einer fremden Transaktion würde LMNT.DB.Transaction nur pcall ausführen: ein fehlerhafter
	-- Schritt wäre dann nicht zurückrollbar. Deshalb hier verweigern (Feld aus core/sv_db.lua).
	if LMNT.DB._inTransaction then
		local msg = "Migration darf nicht innerhalb einer laufenden Transaktion gestartet werden"
		LMNT.Log.Error("db", "Migration " .. module .. ": " .. msg)
		return false, nil, msg
	end

	local current, err = LMNT.DB.SchemaVersion(module)
	if not current then
		LMNT.Log.Error("db", "Migration " .. module .. ": Schemaversion nicht lesbar – " .. tostring(err))
		return false, nil, err
	end

	if current > target then
		local msg = "Datenbank hat Version " .. current .. ", der Code kennt nur " .. target .. " Schritt(e) – älterer Code auf neuerer Datenbank? Es wird nichts ausgeführt."
		LMNT.Log.Error("db", "Migration " .. module .. ": " .. msg)
		return false, current, msg
	end

	for version = current + 1, target do
		local ok, stepErr = LMNT.DB.Transaction(function()
			steps[version](exec)

			local rows, qErr = LMNT.DB.QueryStrict("REPLACE INTO lmnt_schema (module, version, applied_at) VALUES (?, ?, ?)", module, version, os.time())
			if not rows then error("Schemaversion konnte nicht gespeichert werden: " .. qErr, 0) end
		end)

		if not ok then
			local msg = "Schritt " .. version .. " fehlgeschlagen: " .. tostring(stepErr)
			LMNT.Log.Error("db", "Migration " .. module .. ": " .. msg .. " – Version bleibt " .. (version - 1))
			return false, version - 1, msg
		end

		LMNT.Log.Info("db", "Migration " .. module .. ": Version " .. version .. " angewendet")
	end

	return true, target
end

-- Tabelle sofort anlegen, damit ein Fehler schon beim Start im Log steht
local ok, err = ensureSchemaTable()
if not ok then LMNT.Log.Error("db", err) end
