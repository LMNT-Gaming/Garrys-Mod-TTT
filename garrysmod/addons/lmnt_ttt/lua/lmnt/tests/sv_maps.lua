-- LMNT Unit-Tests: Modul ttt.maps (Registry, Profil-Validierung, Override-Rücknahme)
-- Overrides laufen gegen das echte LMNT.Settings mit eigenen Test-Keys und eigenem Journal,
-- der laufende Server (aktive Map-Overrides, Journal des Moduls) bleibt unberührt.
local T = LMNT.Test

if not (LMNT.Maps and LMNT.Maps.NewOverrides) then
	T.Describe("Maps", function(t)
		t:It("Modul ttt.maps ist geladen", function(e)
			e:True(false, "LMNT.Maps fehlt – Modul ttt.maps ist aus oder nicht gestartet (!modules)")
		end)
	end)
	return
end

local Maps = LMNT.Maps
local S = LMNT.Settings

-- Erfundene Definitionen nur für die reinen Validierungs-Tests (kein Zugriff auf LMNT.Settings)
local FAKE_DEFS = {
	["x.int"] = { type = "int", min = 0, max = 10, applies = "live" },
	["x.num"] = { type = "number", min = 0, max = 1, applies = "nextround" },
	["x.bool"] = { type = "bool", applies = "live" },
	["x.enum"] = { type = "enum", choices = { "a", "b" }, applies = "live" },
	["x.str"] = { type = "string", maxLength = 5, applies = "live" },
	["x.restart"] = { type = "int", applies = "restart" },
	["module.foo.enabled"] = { type = "bool", applies = "live" },
	["integration.foo.enabled"] = { type = "bool", applies = "live" },
}
local function fakeDef(key) return FAKE_DEFS[key] end

T.Describe("Maps.NormalizeName / ParseMapcycle", function(t)
	t:It("Namen werden klein geschrieben, Pfadzeichen abgelehnt", function(e)
		local N = Maps.NormalizeName
		e:Equal(N("TTT_Minecraft_B5"), "ttt_minecraft_b5")
		e:Equal(N(" ttt_x "), "ttt_x", "getrimmt")
		e:Equal(N("../config"), nil)
		e:Equal(N("a/b"), nil)
		e:Equal(N(".versteckt"), nil)
		e:Equal(N(""), nil)
		e:Equal(N(5), nil)
	end)
	t:It("Mapcycle: BOM, CRLF, Kommentare, Leerzeilen, ungültige Zeilen", function(e)
		local set = Maps.ParseMapcycle("\239\187\191ttt_a\r\n// Kommentar\n\n  TTT_B  // dahinter\nungültig/pfad\n")
		e:True(set.ttt_a, "ttt_a")
		e:True(set.ttt_b, "ttt_b")
		e:Equal(table.Count(set), 2)
		e:Equal(table.Count(Maps.ParseMapcycle(nil)), 0, "nil = leer")
	end)
end)

T.Describe("Maps.ValidateOverride", function(t)
	local function O(key, value) return (Maps.ValidateOverride(key, value, fakeDef)) end

	t:It("JSON-Typ muss zum Settings-Typ passen", function(e)
		e:True(O("x.int", 4))
		e:False(O("x.int", "4"), "Zahl als Text")
		e:True(O("x.bool", false))
		e:False(O("x.bool", "an"), "\"an\" ist im Profil kein bool")
		e:True(O("x.str", "abc"))
		e:False(O("x.str", 1), "Zahl statt Text")
	end)
	t:It("Grenzen und erlaubte Werte aus der Definition", function(e)
		e:False(O("x.int", 4.5), "int mit Komma")
		e:False(O("x.int", 11), "über max")
		e:True(O("x.num", 0.5))
		e:False(O("x.num", 2), "über max")
		e:True(O("x.enum", "a"))
		e:False(O("x.enum", "c"), "nicht in choices")
		e:False(O("x.str", "abcdef"), "zu lang")
	end)
	t:It("unbekannte Keys, restart-Einstellungen und Schalter werden abgelehnt", function(e)
		e:False(O("x.fehlt", 1), "nicht registriert")
		e:False(O(5, 1), "Key keine Zeichenkette")
		e:False(O("x.restart", 1), "applies = restart")
		e:False(O("module.foo.enabled", true), "Modulschalter")
		e:False(O("integration.foo.enabled", true), "Integrationsschalter")
		local _, msg = Maps.ValidateOverride("module.foo.enabled", true, fakeDef)
		e:True(isstring(msg) and msg ~= "", "Fehlermeldung vorhanden")
	end)
end)

T.Describe("Maps.ValidateProfile", function(t)
	local function V(raw) return Maps.ValidateProfile(raw, { getDef = fakeDef }) end

	t:It("gültige Teile bleiben, ungültige werden gemeldet", function(e)
		local p, errors, warnings = V({
			_kommentar = "wird ignoriert",
			displayName = "  Minecraft  ",
			author = 42,
			notes = "Zeile 1\nZeile 2",
			knownIssues = { "Fehler A", "", "Fehler B" },
			unbekannt = true,
			settings = { ["x.int"] = 4, ["x.num"] = 5 },
		})
		e:Equal(p.displayName, "Minecraft", "getrimmt")
		e:Equal(p.author, nil, "Zahl als Autor verworfen")
		e:Equal(p.notes, nil, "Zeilenumbruch verworfen")
		e:Equal(#p.knownIssues, 2, "leere Einträge entfallen")
		e:Equal(p.settings["x.int"], 4)
		e:Equal(p.settings["x.num"], nil, "außerhalb des Bereichs verworfen")
		e:Equal(#errors, 3, "author, notes, settings.x.num")
		e:Equal(#warnings, 1, "unbekanntes Feld")
	end)
	t:It("Länge zählt Zeichen (UTF-8), nicht Bytes", function(e)
		local _, ok = V({ displayName = string.rep("ä", 64) })
		e:Equal(#ok, 0, "64 Umlaute erlaubt")
		local _, tooLong = V({ displayName = string.rep("a", 65) })
		e:Equal(#tooLong, 1, "65 Zeichen zu lang")
	end)
	t:It("knownIssues: nur Listen, höchstens 20 Einträge", function(e)
		local issues = {}
		for i = 1, 21 do issues[i] = "Fehler " .. i end
		local p, errors = V({ knownIssues = issues })
		e:Equal(#p.knownIssues, 20)
		e:Equal(#errors, 1)
		local p2, errors2 = V({ knownIssues = { a = "x" } })
		e:Equal(#p2.knownIssues, 0)
		e:Equal(#errors2, 1, "Objekt statt Liste")
	end)
	t:It("kein JSON-Objekt -> kein Profil", function(e)
		local p, errors = V("text")
		e:Equal(p, nil)
		e:Equal(#errors, 1)
		local p2, errors2, warnings2 = V({})
		e:True(p2 ~= nil, "leeres Profil ist gültig")
		e:Equal(#errors2 + #warnings2, 0)
	end)
end)

T.Describe("Maps.BuildRegistry", function(t)
	t:It("führt Workshop, BSP, Mapcycle und Profile zusammen, ohne aus Namen abzuleiten", function(e)
		local reg, warnings = Maps.BuildRegistry({
			workshop = {
				{ id = "159321088", name = "ttt_minecraft_b5", map = "ttt_minecraft_b5" },
				{ id = "183797802", name = "TTT_island_2013" },    -- ohne "map": nichts erfinden
				{ id = "abc", name = "kaputt", map = "ttt_kaputt" }, -- ungültige ID
			},
			bsps = { "ttt_minecraft_b5.bsp", "GM_Construct.bsp" },
			mapcycle = { ttt_minecraft_b5 = true, ttt_fehlt = true },
			profiles = {
				ttt_nurprofil = { state = "ok", path = "lmnt/maps/ttt_nurprofil.json", errors = {}, warnings = {},
					profile = { displayName = "Nur Profil", knownIssues = { "Fehler" }, settings = {} } },
			},
		})

		local mc = reg.ttt_minecraft_b5
		e:Equal(mc.workshopId, "159321088")
		e:Equal(mc.bsp, true)
		e:Equal(mc.inMapcycle, true)
		e:Equal(mc.profileState, "none")
		e:Equal(reg.ttt_island_2013, nil, "kein Eintrag aus dem Workshop-Namen erfunden")
		e:Equal(reg.ttt_kaputt, nil, "ungültige ID ignoriert")
		e:Equal(#warnings, 2)
		e:Equal(reg.gm_construct.map, "GM_Construct", "Schreibweise der echten Datei")
		e:Equal(reg.gm_construct.inMapcycle, false)
		e:Equal(reg.ttt_fehlt.bsp, false, "Mapcycle-Eintrag ohne BSP")
		e:Equal(reg.ttt_nurprofil.bsp, false, "Profil ohne BSP")
		e:Equal(reg.ttt_nurprofil.displayName, "Nur Profil")
		e:Equal(#reg.ttt_nurprofil.knownIssues, 1)
		e:Equal(#Maps.SortedList(reg), 4, "minecraft, gm_construct, fehlt, nurprofil")
	end)
	t:It("fehlende Quelle = unbekannt (nil), nicht false", function(e)
		local reg = Maps.BuildRegistry({ workshop = { { id = 1, map = "ttt_a" } } })
		e:Equal(reg.ttt_a.workshopId, "1", "Zahl-ID wird Text")
		e:Equal(reg.ttt_a.bsp, nil)
		e:Equal(reg.ttt_a.inMapcycle, nil)
		e:Equal(reg.ttt_a.profileState, nil)
	end)
end)

------------------------------------------------------------------------
-- Overrides gegen das echte LMNT.Settings (eigene Keys, eigenes Journal)
------------------------------------------------------------------------

local KEY_A, KEY_B = "test.maps.a", "test.maps.b"
local JOURNAL = "lmnt/test_maps_journal.json"

local function deleteJournal()
	if file.Exists(JOURNAL, "DATA") then file.Delete(JOURNAL) end
end

local function setup()
	S.Define(KEY_A, { type = "int", default = 3, min = 0, max = 10, category = "Test", applies = "live" })
	S.Define(KEY_B, { type = "number", default = 0.5, min = 0, max = 1, category = "Test", applies = "nextround" })
	S.Reset(KEY_A)
	S.Reset(KEY_B)
	deleteJournal()
end

local function cleanup()
	for _, key in ipairs({ KEY_A, KEY_B }) do
		if S.GetDef(key) then S.Reset(key) end
		S._defs[key] = nil
		S._values[key] = nil
		S._stored[key] = nil
	end
	deleteJournal()
end

-- Aufräumen auch dann, wenn eine Erwartung fehlschlägt
local function withSettings(fn)
	return function(e)
		setup()
		local ok, err = pcall(fn, e)
		cleanup()
		if not ok then error(err, 0) end
	end
end

local function dbCount(key)
	return LMNT.DB.Value("SELECT COUNT(*) FROM lmnt_config WHERE key = ?", key)
end

T.Describe("Maps.Overrides", function(t)
	t:It("Mapwechsel hinterlässt keine Profilzustände (Wert, DB, Journal)", withSettings(function(e)
		local o = Maps.NewOverrides({ journal = JOURNAL })
		local results = o:Apply("ttt_test", { [KEY_A] = 7, [KEY_B] = 0.25 })
		e:Equal(results[1].status, "applied")
		e:Equal(results[2].status, "applied")
		e:Equal(S.Get(KEY_A), 7)
		e:Equal(S.Get(KEY_B), 0.25)
		e:True(file.Exists(JOURNAL, "DATA"), "Journal geschrieben")
		e:Equal(#o:List(), 2)

		o:Revert("Test-Mapwechsel")
		e:Equal(S.Get(KEY_A), 3, "Standard wieder aktiv")
		e:Equal(S.Get(KEY_B), 0.5)
		e:Equal(dbCount(KEY_A), "0", "kein DB-Eintrag bleibt")
		e:Equal(dbCount(KEY_B), "0")
		e:False(file.Exists(JOURNAL, "DATA"), "Journal entfernt")
		e:Equal(#o:List(), 0)
	end))

	t:It("vorheriger Ingame-Wert wird wiederhergestellt", withSettings(function(e)
		S.Set(KEY_A, 5)
		local o = Maps.NewOverrides({ journal = JOURNAL })
		o:Apply("ttt_test", { [KEY_A] = 9 })
		e:Equal(S.Get(KEY_A), 9)
		o:Revert("Test")
		e:Equal(S.Get(KEY_A), 5)
		e:Equal(LMNT.DB.Value("SELECT value FROM lmnt_config WHERE key = ?", KEY_A), "5", "Ingame-Wert wieder gespeichert")
	end))

	t:It("Änderungen laufen mit dem Actor „Map-Profil“", withSettings(function(e)
		local actors = {}
		LMNT.Events.On("lmnt.settings.changed", "test.maps.actor", function(key, _, _, actor)
			if key == KEY_A then actors[#actors + 1] = actor end
		end)
		local o = Maps.NewOverrides({ journal = false })
		o:Apply("ttt_test", { [KEY_A] = 7 })
		o:Revert("Test")
		LMNT.Events.Off("lmnt.settings.changed", "test.maps.actor")
		e:Equal(#actors, 2, "Setzen und Zurücknehmen")
		e:Equal(actors[1], Maps.ACTOR)
		e:Equal(actors[2], Maps.ACTOR)
	end))

	t:It("gleicher Wert: nichts schreiben, nichts zurücknehmen", withSettings(function(e)
		local o = Maps.NewOverrides({ journal = JOURNAL })
		local results = o:Apply("ttt_test", { [KEY_A] = 3 })
		e:Equal(results[1].status, "same")
		e:Equal(#o:List(), 0)
		e:Equal(dbCount(KEY_A), "0")
		e:False(file.Exists(JOURNAL, "DATA"), "kein Journal nötig")
	end))

	t:It("Admin-Änderung während der Map gewinnt und wird nicht zurückgedreht", withSettings(function(e)
		local o = Maps.NewOverrides({ journal = JOURNAL })
		o:Apply("ttt_test", { [KEY_A] = 7 })
		-- wie der Listener in sv_maps.lua (lmnt.settings.changed -> HandleExternalChange)
		LMNT.Events.On("lmnt.settings.changed", "test.maps.takeover", function(key) o:HandleExternalChange(key) end)
		S.Set(KEY_A, 8)
		LMNT.Events.Off("lmnt.settings.changed", "test.maps.takeover")
		e:Equal(#o:List(), 0, "Override aufgegeben")
		o:Revert("Test")
		e:Equal(S.Get(KEY_A), 8, "Admin-Wert bleibt")
	end))

	t:It("Absturz: Journal wird beim nächsten Start zurückgenommen", withSettings(function(e)
		local crashed = Maps.NewOverrides({ journal = JOURNAL })
		crashed:Apply("ttt_test", { [KEY_A] = 7 })
		-- kein Revert (Absturz); neue Instanz wie nach einem Neustart
		local fresh = Maps.NewOverrides({ journal = JOURNAL })
		local results = fresh:Recover()
		e:Equal(#results, 1)
		e:Equal(results[1].status, "reverted")
		e:Equal(S.Get(KEY_A), 3)
		e:Equal(dbCount(KEY_A), "0")
		e:False(file.Exists(JOURNAL, "DATA"), "Journal entfernt")
	end))

	t:It("Absturz: inzwischen anders gesetzte Werte bleiben unangetastet", withSettings(function(e)
		local crashed = Maps.NewOverrides({ journal = JOURNAL })
		crashed:Apply("ttt_test", { [KEY_A] = 7 })
		S.Set(KEY_A, 4)
		local results = Maps.NewOverrides({ journal = JOURNAL }):Recover()
		e:Equal(results[1].status, "skipped")
		e:Equal(S.Get(KEY_A), 4)
		e:False(file.Exists(JOURNAL, "DATA"))
	end))

	t:It("nicht registrierte Einstellung bleibt im Journal und wird später zurückgenommen", withSettings(function(e)
		local o = Maps.NewOverrides({ journal = JOURNAL })
		o:Apply("ttt_test", { [KEY_A] = 7 })
		local def = S._defs[KEY_A]
		S._defs[KEY_A] = nil
		local first = o:Revert("Test")
		S._defs[KEY_A] = def
		e:Equal(first[1].status, "pending")
		e:True(file.Exists(JOURNAL, "DATA"), "bleibt im Journal")

		local second = o:Revert("Test")
		e:Equal(second[1].status, "reverted")
		e:Equal(S.Get(KEY_A), 3)
		e:False(file.Exists(JOURNAL, "DATA"))
	end))

	t:It("Profil-Overrides werden gegen die echte Registrierung geprüft", withSettings(function(e)
		local p, errors = Maps.ValidateProfile({ settings = { [KEY_A] = 7, [KEY_B] = 2 } })
		e:Equal(p.settings[KEY_A], 7)
		e:Equal(p.settings[KEY_B], nil, "außerhalb 0–1")
		e:Equal(#errors, 1)
	end))
end)

T.Describe("Maps.Modul", function(t)
	t:It("Modul aktiv, Bereinigung beim Mapwechsel und Befehle registriert", function(e)
		local M = LMNT.Modules.Get("ttt.maps")
		e:True(M ~= nil and M.state == "enabled", "ttt.maps aktiv")
		e:True((hook.GetTable().ShutDown or {})["LMNT.Maps.Revert"] ~= nil, "ShutDown-Hook")
		e:True((hook.GetTable().InitPostEntity or {})["LMNT.Maps.Loaded"] ~= nil, "InitPostEntity-Hook")
		e:True(LMNT.Admin.GetCommand("maps") ~= nil, "!maps")
		e:True(LMNT.Admin.GetCommand("mapinfo") ~= nil, "!mapinfo")
		e:Equal(LMNT.Admin.GetCommand("mapprofile").perm, "map")
	end)
	t:It("aktuelle Map ist erfasst", function(e)
		local current = Maps.Current()
		e:True(current ~= nil, "Maps.Current()")
		e:Equal(current.name, Maps.NormalizeName(game.GetMap()))
		local entry = Maps.Get(game.GetMap())
		e:True(entry ~= nil, "aktuelle Map in der Registry")
		e:Equal(entry.bsp, true, "BSP der laufenden Map gefunden")
	end)
end)
