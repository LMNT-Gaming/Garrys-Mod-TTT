--[[
	LMNT TTT – Modul "ttt.maps": Server (echte Dateien, Map-Profile, Overrides, Event)
	API-Referenz: docs/framework/api/maps.md

	Ablauf pro Map (GMod baut den Lua-Zustand bei jedem Mapwechsel neu auf):
	  1. Modulstart          Zustand der aktuellen Map anlegen, Listener registrieren
	  2. Phase "ready"       Reste eines Absturzes aus dem Journal zurücknehmen, Profil lesen und prüfen,
	                         Overrides anwenden (erst jetzt sind die Einstellungen aller Module registriert)
	  3. InitPostEntity      Spawn-Entities der Map zählen, Event lmnt.map.loaded(map, profile)
	  4. ShutDown / Modul aus  alle Overrides zurücknehmen (ShutDown läuft laut GMod-Wiki auch beim Mapwechsel)

	Overrides laufen über LMNT.Settings.Set/Reset mit dem Actor "Map-Profil". Weil Set in die Datenbank
	schreibt, merkt sich das Modul vor jeder Änderung den vorherigen Zustand im Journal
	data/lmnt/maps_overrides_active.json. Stürzt der Server ab, nimmt der nächste Start die Werte zurück.
]]

local Maps = LMNT.Maps
local S = LMNT.Settings

Maps.PROFILE_DIR = "lmnt/maps/"
Maps.JOURNAL_FILE = "lmnt/maps_overrides_active.json"

-- Registry höchstens alle paar Sekunden neu aus den Dateien lesen (Schutz vor Befehls-Spam)
local CACHE_SECONDS = 10

local function log(level, msg)
	LMNT.Log[level]("ttt.maps", msg)
end

local function decodeJSON(raw)
	if string.sub(raw, 1, 3) == "\239\187\191" then raw = string.sub(raw, 4) end
	return util.JSONToTable(raw)
end

local function countGroups(groups)
	local n = 0
	for _, list in pairs(groups or {}) do n = n + #list end
	return n
end

------------------------------------------------------------------------
-- Profile
------------------------------------------------------------------------

function Maps.ProfilePath(name)
	return Maps.PROFILE_DIR .. name .. ".json"
end

--[[
	Liest und prüft das Profil einer Map.
	-> { name, path, exists, state = none|ok|warnings|errors|invalid, profile, errors{}, warnings{} }
	"invalid" = Datei ist kein gültiges JSON-Objekt, das Profil wird dann gar nicht verwendet.
]]
function Maps.LoadProfile(mapName)
	local name = Maps.NormalizeName(mapName)
	if not name then
		return { exists = false, state = "invalid", errors = { "ungültiger Mapname: " .. tostring(mapName) }, warnings = {} }
	end

	local info = { name = name, path = Maps.ProfilePath(name), exists = false, state = "none", errors = {}, warnings = {} }
	local raw = file.Read(info.path, "DATA")
	if raw == nil then return info end
	info.exists = true

	local data = decodeJSON(raw)
	if not istable(data) then
		info.state = "invalid"
		info.errors = { "kein gültiges JSON-Objekt – Profil wird nicht verwendet" }
		return info
	end

	local profile, errors, warnings = Maps.ValidateProfile(data)
	info.profile, info.errors, info.warnings = profile, errors, warnings
	if not profile then
		info.state = "invalid"
	elseif #errors > 0 then
		info.state = "errors"
	elseif #warnings > 0 then
		info.state = "warnings"
	else
		info.state = "ok"
	end
	return info
end

------------------------------------------------------------------------
-- Registry aus echten Dateien
------------------------------------------------------------------------

-- Liest die Mapcycle-Datei (ConVar mapcyclefile, liegt in cfg/). nil = nicht lesbar
local function readMapcycle()
	local cv = GetConVar("mapcyclefile")
	local name = cv and cv:GetString() or ""
	if name == "" then name = "mapcycle.txt" end

	for _, path in ipairs({ "cfg/" .. name, name }) do
		local text = file.Read(path, "GAME")
		if text then return Maps.ParseMapcycle(text), path end
	end
	return nil
end

local function readWorkshop()
	local raw = file.Read("lmnt/workshop.json", "DATA")
	if raw == nil then return nil, "data/lmnt/workshop.json fehlt" end
	local data = decodeJSON(raw)
	if not istable(data) then return nil, "data/lmnt/workshop.json ist kein gültiges JSON" end
	if data.maps ~= nil and not istable(data.maps) then return nil, "workshop.json: \"maps\" ist keine Liste" end
	return data.maps or {}
end

local cache, cacheTime, cacheWarnings

function Maps.Refresh(force)
	if not force and cache and SysTime() - cacheTime < CACHE_SECONDS then return cache, cacheWarnings end

	local workshop, workshopErr = readWorkshop()
	local bsps = file.Find("maps/*.bsp", "GAME")
	local mapcycle = readMapcycle()

	local profiles = {}
	for _, f in ipairs(file.Find(Maps.PROFILE_DIR .. "*.json", "DATA") or {}) do
		local info = Maps.LoadProfile(string.StripExtension(f))
		if info.name then profiles[info.name] = info end
	end

	local registry, warnings = Maps.BuildRegistry({
		workshop = workshop, bsps = bsps, mapcycle = mapcycle, profiles = profiles,
	})
	if workshopErr then table.insert(warnings, 1, workshopErr) end
	if not mapcycle then table.insert(warnings, 1, "Mapcycle-Datei nicht lesbar – Mapcycle-Status unbekannt") end

	cache, cacheTime, cacheWarnings = registry, SysTime(), warnings
	return cache, cacheWarnings
end

function Maps.Get(name)
	local key = Maps.NormalizeName(name)
	if not key then return nil end
	return (Maps.Refresh())[key]
end

-- -> sortierte Liste, Warnungen beim Einlesen
function Maps.List()
	local registry, warnings = Maps.Refresh()
	return Maps.SortedList(registry), warnings
end

------------------------------------------------------------------------
-- Overrides: anwenden, zurücknehmen, Absturz-Wiederherstellung
------------------------------------------------------------------------

local Overrides = {}
Overrides.__index = Overrides

--[[
	Maps.NewOverrides({ journal = "lmnt/datei.json" | false, actor = "Map-Profil" })
	Das laufende Modul nutzt eine Instanz mit Maps.JOURNAL_FILE, Tests eigene Instanzen.
	Eintrag pro Key: { applied = gesetzter Wert, hadStored = gab es vorher einen Ingame-Wert?, stored = dieser Wert }
]]
function Maps.NewOverrides(opts)
	opts = opts or {}
	return setmetatable({
		journal = opts.journal or false,
		actor = opts.actor or Maps.ACTOR,
		active = {},
		map = nil,
		applying = false,
	}, Overrides)
end

-- Ingame-Wert (Tabelle lmnt_config) eines Keys oder nil. LMNT.Settings hat dafür keine öffentliche
-- Funktion, deshalb wird die interne Tabelle nur gelesen (siehe maps.md, „Grenzen“).
local function storedValue(key)
	return S._stored[key]
end

function Overrides:_writeJournal()
	if not self.journal then return end

	if table.IsEmpty(self.active) then
		if file.Exists(self.journal, "DATA") then file.Delete(self.journal) end
		return
	end

	local entries = {}
	for key, e in pairs(self.active) do
		entries[key] = { applied = e.applied, hadStored = e.hadStored, stored = e.stored }
	end
	file.CreateDir(string.GetPathFromFilename(self.journal))
	file.Write(self.journal, util.TableToJSON({
		_info = "LMNT ttt.maps: Werte, die das Map-Profil gerade überschreibt. Nicht von Hand bearbeiten – wird beim Start automatisch zurückgenommen.",
		map = self.map, time = os.time(), entries = entries,
	}, true))
end

-- Setzt bzw. setzt zurück, ohne dass der eigene Änderungs-Listener das als Fremdänderung wertet
function Overrides:_call(fn, ...)
	self.applying = true
	local okCall, ok, result = pcall(fn, ...)
	self.applying = false
	if not okCall then return false, tostring(ok) end
	return ok, result
end

--[[
	Wendet geprüfte Overrides an ({ [key] = normalisierter Wert }). Vorher aktive werden erst zurückgenommen.
	-> Liste { key, value, status = applied|same|failed, message }
	"same": Der Wert galt schon – es wird nichts geschrieben und es gibt nichts zurückzunehmen.
]]
function Overrides:Apply(mapName, overrides)
	self:Revert("neues Profil")
	self.map = mapName

	local results = {}
	local keys = table.GetKeys(overrides or {})
	table.sort(keys)

	for _, key in ipairs(keys) do
		local value = overrides[key]
		if not S.GetDef(key) then
			results[#results + 1] = { key = key, value = value, status = "failed", message = "unbekannte Einstellung" }
		elseif S.Get(key) == value then
			results[#results + 1] = { key = key, value = value, status = "same" }
		else
			local stored = storedValue(key)
			self.active[key] = { applied = value, hadStored = stored ~= nil, stored = stored }
			-- Journal VOR der Änderung schreiben: ein Absturz direkt danach ist so wiederherstellbar
			self:_writeJournal()

			local ok, result = self:_call(S.Set, key, value, self.actor)
			if ok then
				self.active[key].applied = result
				results[#results + 1] = { key = key, value = result, status = "applied" }
			else
				self.active[key] = nil
				results[#results + 1] = { key = key, value = value, status = "failed", message = tostring(result) }
			end
		end
	end

	self:_writeJournal()
	return results
end

-- -> status reverted|skipped|pending|failed, meldung
function Overrides:_revertOne(key, e)
	if not S.GetDef(key) then
		return "pending", "Einstellung derzeit nicht registriert – Rücknahme beim nächsten Start"
	end
	if storedValue(key) ~= e.applied then
		return "skipped", "Wert wurde inzwischen anders gesetzt – bleibt unverändert"
	end

	local ok, result
	if e.hadStored then
		ok, result = self:_call(S.Set, key, e.stored, self.actor)
		if not ok then
			-- Alter Wert ist inzwischen ungültig (z. B. geänderte Grenzen): auf config.json bzw. Standard
			ok, result = self:_call(S.Reset, key, self.actor)
		end
	else
		ok, result = self:_call(S.Reset, key, self.actor)
	end

	if not ok then return "failed", tostring(result) end
	return "reverted", tostring(result)
end

--[[
	Nimmt alle aktiven Overrides zurück. "pending" und "failed" bleiben im Journal und werden beim
	nächsten Aufruf (spätestens beim nächsten Start) erneut versucht.
	-> Liste { key, status, message }
]]
function Overrides:Revert(reason)
	local results = {}
	local keys = table.GetKeys(self.active)
	table.sort(keys)

	for _, key in ipairs(keys) do
		local status, message = self:_revertOne(key, self.active[key])
		if status == "reverted" or status == "skipped" then self.active[key] = nil end
		results[#results + 1] = { key = key, status = status, message = message, reason = reason }
	end

	self:_writeJournal()
	if table.IsEmpty(self.active) then self.map = nil end
	return results
end

-- Übernimmt Einträge aus dem Journal (Absturz oder zuvor nicht registrierte Einstellung) und nimmt sie zurück
function Overrides:Recover()
	if not self.journal then return {} end
	local raw = file.Read(self.journal, "DATA")
	if raw == nil then return {} end

	local data = decodeJSON(raw)
	if not istable(data) or not istable(data.entries) then
		file.Delete(self.journal)
		return { { key = "*", status = "failed", message = "Journal unlesbar und gelöscht: " .. string.sub(raw, 1, 300) } }
	end

	for key, e in pairs(data.entries) do
		if isstring(key) and istable(e) and e.applied ~= nil and not self.active[key] then
			self.active[key] = { applied = e.applied, hadStored = e.hadStored == true, stored = e.stored }
		end
	end
	return self:Revert("Wiederherstellung nach Absturz")
end

-- Ein Admin (oder ein anderes System) hat einen überschriebenen Key selbst geändert: Diese Änderung
-- gewinnt und wird beim Mapwechsel NICHT zurückgedreht. -> true, wenn der Key aktiv war
function Overrides:HandleExternalChange(key)
	if self.applying or not self.active[key] then return false end
	self.active[key] = nil
	self:_writeJournal()
	return true
end

-- -> sortierte Liste { key, applied, hadStored, stored }
function Overrides:List()
	local list = {}
	for key, e in pairs(self.active) do
		list[#list + 1] = { key = key, applied = e.applied, hadStored = e.hadStored, stored = e.stored }
	end
	table.SortByMember(list, "key", true)
	return list
end

------------------------------------------------------------------------
-- Aktuelle Map
------------------------------------------------------------------------

local overrides   -- Instanz des laufenden Moduls
local current     -- { map, name, profileInfo, profile, spawns, overridesApplied, overrideResults, announced }

function Maps.Current()
	return current
end

function Maps.ActiveOverrides()
	return overrides and overrides:List() or {}
end

local function logResults(results, prefix)
	for _, r in ipairs(results) do
		if r.status == "applied" then
			log("Info", prefix .. r.key .. " = " .. tostring(r.value))
		elseif r.status == "reverted" then
			log("Info", prefix .. r.key .. " zurückgenommen (" .. tostring(r.reason) .. "), jetzt " .. r.message)
		elseif r.status == "same" then
			log("Debug", prefix .. r.key .. " = " .. tostring(r.value) .. " galt bereits, nichts geändert")
		elseif r.status == "skipped" or r.status == "pending" then
			log("Warn", prefix .. r.key .. ": " .. r.message)
		else
			log("Error", prefix .. r.key .. ": " .. tostring(r.message))
		end
	end
end

local function logProfile(info)
	for _, err in ipairs(info.errors or {}) do log("Warn", "Profil " .. tostring(info.path) .. ": " .. err) end
	for _, w in ipairs(info.warnings or {}) do log("Info", "Profil " .. tostring(info.path) .. ": " .. w) end
end

-- Zählt Spawn-Entities der Map. Nur aussagekräftig, solange die Map-Entities noch existieren:
-- TTT2 entfernt sie beim Rundenaufbau (entspawn.HandleSpawns) und setzt eigene Spawns.
local function scanMapEntities()
	if istable(map) and isfunction(map.GetPlayerSpawnEntities) then
		return {
			player = countGroups(map.GetPlayerSpawnEntities()),
			weapon = countGroups(map.GetWeaponSpawnEntities()),
			ammo = countGroups(map.GetAmmoSpawnEntities()),
			tttEntities = #ents.FindByClass("ttt_*"),
			source = "Map-Entities beim Laden",
		}
	end
	-- Ohne TTT2-Bibliothek: nur Spieler-Spawns, Waffen/Munition bleiben unbekannt
	return { player = #ents.FindByClass("info_player_*"), tttEntities = #ents.FindByClass("ttt_*"), source = "Map-Entities beim Laden" }
end

-- Bei Aktivierung zur Laufzeit sind die Map-Entities schon ersetzt; TTT2 hält aber eine Kopie der
-- ursprünglichen Map-Spawns im Speicher (entspawnscript.SaveMapStateAsDefault beim ersten Laden).
local function scanTTT2Copy()
	local t = istable(entspawnscript) and entspawnscript.defaultSpawnTable
	if not istable(t) or table.IsEmpty(t) then return nil end
	return {
		player = countGroups(t[SPAWN_TYPE_PLAYER]),
		weapon = countGroups(t[SPAWN_TYPE_WEAPON]),
		ammo = countGroups(t[SPAWN_TYPE_AMMO]),
		source = "TTT2-Kopie der Map-Spawns",
	}
end

-- Spawns, die TTT2 tatsächlich verwendet (aus der Map oder aus einer TTT2-Spawndatei). nil = unbekannt
function Maps.GetEffectiveSpawns()
	if not istable(entspawnscript) or not isfunction(entspawnscript.GetSpawns) then return nil end
	local spawns = entspawnscript.GetSpawns()
	if not istable(spawns) or table.IsEmpty(spawns) then return nil end

	local result = {
		player = countGroups(spawns[SPAWN_TYPE_PLAYER]),
		weapon = countGroups(spawns[SPAWN_TYPE_WEAPON]),
		ammo = countGroups(spawns[SPAWN_TYPE_AMMO]),
	}
	if isfunction(entspawnscript.SpawnFileExists) then result.spawnFile = entspawnscript.SpawnFileExists() == true end
	return result
end

-- Journal-Reste zurücknehmen, Profil lesen und prüfen, Overrides anwenden (einmal pro Map)
function Maps.ApplyCurrent()
	if not current or current.overridesApplied then return end
	current.overridesApplied = true

	logResults(overrides:Recover(), "Wiederherstellung: ")

	-- Erst jetzt prüfen: Module, die nach ttt.maps starten (z. B. ttt.specialrounds), haben ihre
	-- Einstellungen inzwischen registriert. Beim Modulstart wären ihre Keys noch "unbekannt".
	local info = Maps.LoadProfile(current.map)
	logProfile(info)
	current.profileInfo, current.profile = info, info.profile
	cache = nil

	local settings = current.profile and current.profile.settings
	if settings and not table.IsEmpty(settings) then
		current.overrideResults = overrides:Apply(current.map, settings)
		logResults(current.overrideResults, "Map-Profil " .. current.map .. ": ")
	else
		current.overrideResults = {}
	end
end

local function announce()
	if not current or current.announced then return end
	current.announced = true
	LMNT.Events.Emit("lmnt.map.loaded", current.map, current.profile)
end

-- Aufruf aus init() der Modulregistrierung (lmnt_ttt_init.lua)
function Maps.Start(M)
	overrides = Maps.NewOverrides({ journal = Maps.JOURNAL_FILE })

	-- Das Profil wird erst in ApplyCurrent (Phase "ready") gelesen, siehe dort
	local mapName = game.GetMap()
	current = { map = mapName, name = Maps.NormalizeName(mapName), overridesApplied = false, announced = false }

	M:On("lmnt.settings.changed", function(key, new, _, actor)
		if overrides and overrides:HandleExternalChange(key) then
			log("Info", LMNT.Name(actor) .. " hat " .. key .. " auf " .. tostring(new) ..
				" gesetzt – Map-Override aufgegeben, der Wert bleibt auch nach dem Mapwechsel")
		end
	end)

	if LMNT.GetPhase() == "ready" then
		-- Aktivierung zur Laufzeit: alle Einstellungen sind registriert, die Map läuft bereits
		Maps.ApplyCurrent()
		current.spawns = scanTTT2Copy()
		announce()
	else
		M:On("lmnt.core.phase", function(phase)
			if phase == "ready" then Maps.ApplyCurrent() end
		end)
	end
end

-- Aufruf aus shutdown() der Modulregistrierung und beim Mapwechsel/Herunterfahren
function Maps.Stop(reason)
	if overrides then logResults(overrides:Revert(reason), "") end
	current = nil
	cache = nil
end

-- Profil der aktuellen Map neu einlesen und anwenden (Befehl !mapprofile). -> ok, info | fehler, ergebnisse
function Maps.ReloadProfile(actorName)
	if not current or not overrides then return false, "Modul ttt.maps läuft nicht" end

	logResults(overrides:Revert("Profil neu laden durch " .. tostring(actorName)), "")
	current.overridesApplied = false
	Maps.ApplyCurrent()

	local info = current.profileInfo
	log("Info", tostring(actorName) .. " hat das Map-Profil von " .. current.map .. " neu geladen (Zustand: " .. info.state .. ")")
	return true, info, current.overrideResults
end

------------------------------------------------------------------------
-- Hooks (beim Laden des Moduls erfasst, beim Deaktivieren automatisch entfernt)
------------------------------------------------------------------------

-- Läuft vor GM:InitPostEntity von TTT2, die Map-Entities sind also noch unverändert vorhanden
hook.Add("InitPostEntity", "LMNT.Maps.Loaded", function()
	if not current then return end
	current.spawns = scanMapEntities()
	-- Falls die Phase "ready" nie erreicht wurde (Fehler beim Start), Overrides trotzdem anwenden
	Maps.ApplyCurrent()
	announce()
end)

hook.Add("ShutDown", "LMNT.Maps.Revert", function()
	Maps.Stop("Mapwechsel/Herunterfahren")
end)
