--[[
	LMNT TTT – Modul "ttt.maps": Map-Registry und Map-Profile (gemeinsamer Teil)
	API-Referenz: docs/framework/api/maps.md

	Registry: bekannte Maps aus data/lmnt/workshop.json ("maps") plus alle tatsächlich vorhandenen
	BSP-Dateien (maps/*.bsp im GAME-Pfad, also auch gemountete Workshop-Addons) plus Mapcycle-Einträge
	und vorhandene Profile. Eigenschaften werden NIE aus dem Mapnamen abgeleitet: Was sich nicht prüfen
	lässt, bleibt nil (= „unbekannt“).

	Map-Profil: data/lmnt/maps/<mapname>.json (Mapname in Kleinbuchstaben), alle Felder optional:
	  {
	    "displayName": "Anzeigename",            Text, max. 64 Zeichen
	    "author": "Autor",                       Text, max. 64 Zeichen (nur belegte Angaben eintragen)
	    "notes": "Hinweise",                     Text, max. 500 Zeichen
	    "knownIssues": [ "Fehler 1" ],           Liste, max. 20 Einträge à 200 Zeichen
	    "settings": { "ttt.special.chance": 0 }  Overrides registrierter LMNT.Settings, NUR für diese Map
	  }
	  Schlüssel mit "_" am Anfang sind Kommentare und werden ignoriert. Unbekannte Felder -> Hinweis.

	LMNT.Maps.NormalizeName(name)                  -> "ttt_map" | nil
	LMNT.Maps.ValidateOverride(key, wert, getDef)  -> true, normalisiert | false, meldung
	LMNT.Maps.ValidateProfile(raw, opts)           -> profil | nil, fehler{}, hinweise{}
	LMNT.Maps.ParseMapcycle(text)                  -> { [name] = true }
	LMNT.Maps.BuildRegistry(quellen)               -> { [name] = eintrag }, warnungen{}
	LMNT.Maps.SortedList(registry)                 -> nach Name sortierte Liste
	Server (sv_maps.lua): Refresh, Get, List, Current, ActiveOverrides, ReloadProfile, NewOverrides …

	Befehle: !maps, !mapinfo [map] (für alle lesbar), !mapprofile (Recht "map")
	Event:   lmnt.map.loaded (map, profile)
]]

LMNT.Maps = LMNT.Maps or {}
local Maps = LMNT.Maps

-- Actor-Name für alle Änderungen, die das Map-Profil an LMNT.Settings vornimmt
Maps.ACTOR = "Map-Profil"

LMNT.Events.Define("lmnt.map.loaded", {
	desc = "Map geladen und ihr Map-Profil angewendet (Server; profile = nil, wenn es kein gültiges Profil gibt)",
	args = { "map", "profile" },
})

------------------------------------------------------------------------
-- Namen und Profil-Validierung (reine Funktionen, siehe Unit-Tests)
------------------------------------------------------------------------

-- Mapnamen landen in Dateipfaden: nur Buchstaben, Ziffern, _ - . und kein führender Punkt
function Maps.NormalizeName(name)
	if not isstring(name) then return nil end
	name = string.lower(string.Trim(name))
	if not string.match(name, "^[%w_][%w_%.%-]*$") then return nil end
	return name
end

local TEXT_FIELDS = { displayName = 64, author = 64, notes = 500 }
local MAX_ISSUES, MAX_ISSUE_LENGTH = 20, 200

-- Schalter mit Kaskaden-Wirkung (Module/Integrationen) sind als Map-Override ausgeschlossen
local FORBIDDEN_PREFIXES = { "module.", "integration." }

-- Erwarteter JSON-Typ je Settings-Typ (strenger als Settings.Validate, das z. B. "an" für bool akzeptiert)
local JSON_TYPE = { bool = "boolean", int = "number", number = "number", string = "string", enum = "string" }
local JSON_TYPE_LABEL = { boolean = "true/false", number = "eine Zahl", string = "Text in Anführungszeichen" }

-- Text prüfen: Typ, gültiges UTF-8, Länge in Zeichen, keine Steuerzeichen. Leerer Text = nicht gesetzt.
local function checkText(value, maxLength)
	if not isstring(value) then return false, "erwartet Text" end
	value = string.Trim(value)
	if value == "" then return true, nil end
	local length = utf8.len(value)
	if not length then return false, "kein gültiges UTF-8" end
	if length > maxLength then return false, "höchstens " .. maxLength .. " Zeichen (hat " .. length .. ")" end
	if string.find(value, "%c") then return false, "Zeilenumbrüche und Steuerzeichen sind nicht erlaubt" end
	return true, value
end

-- Prüft einen einzelnen Settings-Override. getDef ist für Tests austauschbar (Standard: LMNT.Settings.GetDef).
function Maps.ValidateOverride(key, value, getDef)
	getDef = getDef or LMNT.Settings.GetDef
	if not isstring(key) or key == "" then return false, "Schlüssel muss Text sein" end

	for _, prefix in ipairs(FORBIDDEN_PREFIXES) do
		if string.StartWith(key, prefix) then
			return false, "Modul- und Integrationsschalter sind als Map-Override nicht erlaubt"
		end
	end

	local def = getDef(key)
	if not def then return false, "unbekannte Einstellung (nicht registriert)" end
	if def.applies == "restart" then
		return false, "wirkt erst nach einem Serverneustart und ist als Map-Override ungeeignet"
	end

	local expected = JSON_TYPE[def.type]
	if not expected then return false, "Typ " .. tostring(def.type) .. " wird nicht unterstützt" end
	if type(value) ~= expected then
		return false, "erwartet " .. JSON_TYPE_LABEL[expected] .. " (" .. def.type .. "), erhalten " .. type(value)
	end

	return LMNT.Settings.Validate(def, value)
end

--[[
	Prüft ein eingelesenes Profil (Tabelle aus util.JSONToTable).
	Ungültige Felder bzw. Overrides werden verworfen und als Fehler gemeldet, gültige bleiben erhalten
	(wie bei LMNT.Settings: ein Tippfehler legt nicht das ganze Profil lahm).
	opts.getDef: siehe ValidateOverride
	Rückgabe: profil | nil, fehler{}, hinweise{} (beide Listen sortiert)
]]
function Maps.ValidateProfile(raw, opts)
	opts = opts or {}
	local errors, warnings = {}, {}

	if not istable(raw) then
		return nil, { "Profil ist kein JSON-Objekt" }, warnings
	end

	local profile = { knownIssues = {}, settings = {} }

	for field, value in pairs(raw) do
		if not isstring(field) then
			errors[#errors + 1] = "ungültiger Feldname: " .. tostring(field)
		elseif string.StartWith(field, "_") then
			-- Kommentar, wird ignoriert
		elseif TEXT_FIELDS[field] then
			local ok, text = checkText(value, TEXT_FIELDS[field])
			if ok then
				profile[field] = text
			else
				errors[#errors + 1] = field .. ": " .. text
			end
		elseif field == "knownIssues" then
			if not istable(value) or #value ~= table.Count(value) then
				errors[#errors + 1] = "knownIssues: erwartet eine Liste von Texten"
			else
				if #value > MAX_ISSUES then
					errors[#errors + 1] = "knownIssues: höchstens " .. MAX_ISSUES .. " Einträge (weitere ignoriert)"
				end
				for i = 1, math.min(#value, MAX_ISSUES) do
					local ok, text = checkText(value[i], MAX_ISSUE_LENGTH)
					if not ok then
						errors[#errors + 1] = "knownIssues[" .. i .. "]: " .. text
					elseif text then
						profile.knownIssues[#profile.knownIssues + 1] = text
					end
				end
			end
		elseif field == "settings" then
			if not istable(value) then
				errors[#errors + 1] = "settings: erwartet ein Objekt { \"key\": wert }"
			else
				for key, v in pairs(value) do
					local ok, normalized = Maps.ValidateOverride(key, v, opts.getDef)
					if ok then
						profile.settings[key] = normalized
					else
						errors[#errors + 1] = "settings." .. tostring(key) .. ": " .. tostring(normalized)
					end
				end
			end
		else
			warnings[#warnings + 1] = "unbekanntes Feld wird ignoriert: " .. field
		end
	end

	-- pairs() hat keine feste Reihenfolge: sortiert, damit Ausgaben und Tests stabil sind
	table.sort(errors)
	table.sort(warnings)
	return profile, errors, warnings
end

------------------------------------------------------------------------
-- Mapcycle und Registry
------------------------------------------------------------------------

-- Liest den Inhalt einer Mapcycle-Datei: ein Mapname pro Zeile, "//" leitet einen Kommentar ein
function Maps.ParseMapcycle(text)
	local set = {}
	if not isstring(text) then return set end
	if string.sub(text, 1, 3) == "\239\187\191" then text = string.sub(text, 4) end

	for line in string.gmatch(text .. "\n", "(.-)\r?\n") do
		line = string.gsub(line, "//.*$", "")
		local name = Maps.NormalizeName(string.match(line, "^%s*(%S+)"))
		if name then set[name] = true end
	end
	return set
end

--[[
	Führt die Quellen zu einer Registry zusammen. Fehlt eine Quelle (nil), bleibt das zugehörige
	Feld bei allen Maps nil (= unbekannt) statt false.
	quellen = {
		workshop = { { id = "123", name = "…", map = "ttt_x" }, … },   -- workshop.json "maps"
		bsps     = { "ttt_x.bsp", … },                                  -- file.Find("maps/*.bsp", "GAME")
		mapcycle = { ttt_x = true },                                    -- ParseMapcycle
		profiles = { ttt_x = { state, path, profile, errors, warnings } },
	}
	Eintrag: name, map, sources{}, workshopId, workshopName, bsp, inMapcycle,
	         profileState, profilePath, profile, profileErrors, profileWarnings, displayName, knownIssues{}
]]
function Maps.BuildRegistry(src)
	src = src or {}
	local registry, warnings = {}, {}

	-- Ausdrücklich nil statt false, wenn die Quelle nicht ermittelbar war
	local bspDefault, cycleDefault, profileDefault
	if src.bsps then bspDefault = false end
	if src.mapcycle then cycleDefault = false end
	if src.profiles then profileDefault = "none" end

	local function entry(name, mapName, source)
		local e = registry[name]
		if not e then
			e = {
				name = name, map = mapName, sources = {},
				bsp = bspDefault, inMapcycle = cycleDefault, profileState = profileDefault,
				knownIssues = {},
			}
			registry[name] = e
		end
		if not table.HasValue(e.sources, source) then e.sources[#e.sources + 1] = source end
		return e
	end

	for i, item in ipairs(src.workshop or {}) do
		local name = istable(item) and Maps.NormalizeName(item.map)
		local id = istable(item) and item.id ~= nil and tostring(item.id) or nil

		if not name then
			warnings[#warnings + 1] = "workshop.json maps[" .. i .. "]: Feld \"map\" fehlt oder ist ungültig – Eintrag ignoriert"
		elseif not id or not string.match(id, "^%d+$") then
			warnings[#warnings + 1] = "workshop.json maps[" .. i .. "] (" .. name .. "): ungültige Workshop-ID – Eintrag ignoriert"
		else
			local e = entry(name, item.map, "workshop")
			if e.workshopId and e.workshopId ~= id then
				warnings[#warnings + 1] = "workshop.json: " .. name .. " steht mehrfach drin (" .. e.workshopId .. ", " .. id .. ") – " .. id .. " wird verwendet"
			end
			e.workshopId = id
			e.workshopName = isstring(item.name) and item.name or nil
		end
	end

	for _, f in ipairs(src.bsps or {}) do
		local base = string.gsub(f, "%.[bB][sS][pP]$", "")
		local name = Maps.NormalizeName(base)
		if name then
			local e = entry(name, base, "bsp")
			e.map = base -- Schreibweise der echten Datei hat Vorrang
			e.bsp = true
		end
	end

	for name in pairs(src.mapcycle or {}) do
		entry(name, name, "mapcycle").inMapcycle = true
	end

	for name, info in pairs(src.profiles or {}) do
		local e = entry(name, name, "profile")
		e.profileState = info.state
		e.profilePath = info.path
		e.profile = info.profile
		e.profileErrors = info.errors or {}
		e.profileWarnings = info.warnings or {}
		if info.profile then
			e.displayName = info.profile.displayName
			e.knownIssues = info.profile.knownIssues or {}
		end
	end

	table.sort(warnings)
	return registry, warnings
end

function Maps.SortedList(registry)
	local list = {}
	for _, e in pairs(registry or {}) do list[#list + 1] = e end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

------------------------------------------------------------------------
-- Befehle (geteilt registriert, damit das Admin-Menü sie kennt; "run" läuft nur auf dem Server)
--
-- Lesen ist für alle erlaubt: Mapnamen, Workshop-IDs (öffentlich auf Steam), Mapcycle und
-- bekannte Fehler sind keine Geheimnisse und helfen Spielern beim Melden von Map-Problemen.
-- Diagnose (Profilfehler, Dateipfade, aktive Overrides) sieht nur, wer Maps verwalten darf (Recht "map").
-- Ändern (Profil neu laden und Overrides neu anwenden) braucht das Recht "map".
------------------------------------------------------------------------

local A = LMNT.Admin
local col = LMNT.Config.Colors

-- Ab so vielen Maps geht die Liste in die Konsole, damit der Chat nicht überläuft
local CHAT_LIMIT = 12

local PROFILE_LABEL = {
	none = "kein Profil", ok = "Profil ok", warnings = "Profil mit Hinweisen",
	errors = "Profil mit Fehlern", invalid = "Profil ungültig",
}

local function status(value, yes, no)
	if value == nil then return "unbekannt" end
	return value and (yes or "ja") or (no or "nein")
end

local function consoleLine(caller, text)
	if IsValid(caller) then caller:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
end

local function formatSpawns(sp)
	local function n(v) return v ~= nil and tostring(v) or "?" end
	return n(sp.player) .. " Spieler, " .. n(sp.weapon) .. " Waffen, " .. n(sp.ammo) .. " Munition" ..
		(sp.tttEntities and (", " .. sp.tttEntities .. " ttt_*-Entities") or "")
end

local function isCurrentMap(e)
	local current = Maps.Current()
	return current ~= nil and current.name == e.name
end

A.AddCommand("maps", {
	log = false,
	help = "Listet die bekannten Maps mit Status (Workshop, BSP, Mapcycle, Profil)",
	run = function(caller)
		local list, warnings = Maps.List()
		local toConsole = #list > CHAT_LIMIT

		LMNT.Reply(caller, col.primary, #list .. " bekannte Maps" .. (toConsole and " (Liste in der Konsole)" or "") .. ":")
		for _, e in ipairs(list) do
			local parts = {
				e.workshopId and ("Workshop " .. e.workshopId) or "nicht in workshop.json",
				"BSP " .. status(e.bsp, "vorhanden", "fehlt"),
				"Mapcycle " .. status(e.inMapcycle),
				PROFILE_LABEL[e.profileState] or "Profil unbekannt",
			}
			if #e.knownIssues > 0 then parts[#parts + 1] = #e.knownIssues .. " bekannte(r) Fehler" end

			local current = isCurrentMap(e)
			local label = e.map .. (current and " [aktuell]" or "")
			if toConsole then
				consoleLine(caller, label .. "  –  " .. table.concat(parts, " · "))
			else
				local nameColor = current and col.good or (e.bsp == false and col.bad or color_white)
				LMNT.Reply(caller, nameColor, label, col.muted, "  " .. table.concat(parts, " · "))
			end
		end

		if LMNT.HasPerm(caller, "map") then
			for _, w in ipairs(warnings) do LMNT.Reply(caller, col.warn, w) end
		end
	end,
})

A.AddCommand("mapinfo", {
	log = false,
	help = "Details zu einer Map (ohne Angabe: aktuelle Map)",
	args = { { type = "string", name = "map", optional = true } },
	run = function(caller, name)
		local current = Maps.Current()
		name = name or (current and current.map) or game.GetMap()

		local e = Maps.Get(name)
		if not e then
			LMNT.Reply(caller, col.bad, "Unbekannte Map: " .. name .. " (Liste: !maps)")
			return
		end

		local isCurrent = isCurrentMap(e)
		local profile = e.profile

		LMNT.Reply(caller, col.primary, e.map, color_white,
			(e.displayName and ("  „" .. e.displayName .. "“") or "") .. (isCurrent and "  (aktuelle Map)" or ""))
		LMNT.Reply(caller, color_white, "Workshop: " ..
			(e.workshopId and (e.workshopId .. (e.workshopName and (" (" .. e.workshopName .. ")") or "")) or "kein Eintrag in workshop.json") ..
			" · BSP: " .. status(e.bsp, "vorhanden", "fehlt") .. " · Mapcycle: " .. status(e.inMapcycle))

		if profile and profile.author then LMNT.Reply(caller, color_white, "Autor: " .. profile.author) end
		if profile and profile.notes then LMNT.Reply(caller, color_white, "Hinweise: " .. profile.notes) end
		if #e.knownIssues > 0 then
			LMNT.Reply(caller, col.warn, "Bekannte Fehler:")
			for i, issue in ipairs(e.knownIssues) do LMNT.Reply(caller, color_white, "  " .. i .. ". " .. issue) end
		end

		if isCurrent then
			if current.spawns then
				LMNT.Reply(caller, color_white, "Spawns (" .. current.spawns.source .. "): " .. formatSpawns(current.spawns))
			else
				LMNT.Reply(caller, col.muted, "Spawns: unbekannt (beim Laden nicht ermittelbar)")
			end
			local effective = Maps.GetEffectiveSpawns()
			if effective then
				LMNT.Reply(caller, color_white, "TTT2 verwendet: " .. formatSpawns(effective) ..
					" · eigene TTT2-Spawndatei: " .. status(effective.spawnFile))
			end
		else
			LMNT.Reply(caller, col.muted, "Spawns/Entities: unbekannt (nur für die laufende Map ermittelbar)")
		end

		if not LMNT.HasPerm(caller, "map") then return end

		LMNT.Reply(caller, col.muted, (PROFILE_LABEL[e.profileState] or "Profil unbekannt") ..
			" – Datei: data/" .. (e.profilePath or Maps.ProfilePath(e.name)))
		for _, err in ipairs(e.profileErrors or {}) do LMNT.Reply(caller, col.bad, "  Fehler: " .. err) end
		for _, w in ipairs(e.profileWarnings or {}) do LMNT.Reply(caller, col.warn, "  Hinweis: " .. w) end

		if isCurrent then
			local active = Maps.ActiveOverrides()
			if #active == 0 then
				LMNT.Reply(caller, col.muted, "Aktive Map-Overrides: keine")
			else
				LMNT.Reply(caller, col.warn, "Aktive Map-Overrides (werden beim Mapwechsel zurückgenommen):")
				for _, a in ipairs(active) do
					LMNT.Reply(caller, color_white, "  " .. a.key .. " = " .. tostring(a.applied), col.muted,
						"  danach: " .. (a.hadStored and ("Ingame-Wert " .. tostring(a.stored)) or "config.json bzw. Standard"))
				end
			end
		end
	end,
})

A.AddCommand("mapprofile", {
	perm = "map",
	help = "Lädt das Map-Profil der aktuellen Map neu (Overrides zurücknehmen, Datei neu prüfen, neu anwenden)",
	run = function(caller)
		local ok, info, results = Maps.ReloadProfile(LMNT.Name(caller))
		if not ok then
			LMNT.Reply(caller, col.bad, "Nicht möglich: " .. tostring(info))
			return
		end

		LMNT.Reply(caller, info.state == "ok" and col.good or col.warn,
			"Map-Profil neu geladen: " .. (PROFILE_LABEL[info.state] or info.state) .. " (data/" .. info.path .. ")")
		for _, err in ipairs(info.errors or {}) do LMNT.Reply(caller, col.bad, "  Fehler: " .. err) end
		for _, w in ipairs(info.warnings or {}) do LMNT.Reply(caller, col.warn, "  Hinweis: " .. w) end

		for _, r in ipairs(results or {}) do
			if r.status == "applied" then
				LMNT.Reply(caller, col.good, "  " .. r.key .. " = " .. tostring(r.value))
			elseif r.status == "same" then
				LMNT.Reply(caller, col.muted, "  " .. r.key .. " = " .. tostring(r.value) .. " (entsprach bereits dem Wert)")
			else
				LMNT.Reply(caller, col.bad, "  " .. r.key .. ": " .. tostring(r.message))
			end
		end
	end,
})
