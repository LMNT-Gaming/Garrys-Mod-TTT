--[[
	LMNT Service – Spielerdaten mit Cache (T-033, ADR-003)
	API-Referenz: docs/framework/api/playerdata.md (inkl. Konsistenzmodell)

	Ein Profil pro SteamID64, Werte in Modul-Namensräumen (Tabelle lmnt_player_data).
	Laden beim Join mit EINER Abfrage, Schreiben gebündelt als Transaktion: im Intervall, beim
	Disconnect, beim Herunterfahren (ShutDown) und auf Anforderung (Flush/FlushAll).

	LMNT.PlayerData.Get(ply, modul, key, standard)     -> wert | nil, fehler
	LMNT.PlayerData.Set(ply, modul, key, wert)         -> true | false, fehler      (wert = nil löscht)
	LMNT.PlayerData.Increment(ply, modul, key, delta)  -> true, neuerWert | false, fehler
	LMNT.PlayerData.IsLoaded(ply)                      -> bool
	LMNT.PlayerData.Status(ply)                        -> "loaded" | "unavailable" | "not_loaded", grund
	LMNT.PlayerData.Load(ply)                          -> true | false, fehler   (läuft beim Join automatisch)
	LMNT.PlayerData.Flush(ply)                         -> true, anzahl | false, fehler
	LMNT.PlayerData.FlushAll()                         -> true, anzahl | false, fehler
	LMNT.PlayerData.Stats()                            -> Treffer, Fehlzugriffe, Dirty, letzter Flush …
	LMNT.PlayerData.ValidateValue(wert)                -> true, json | false, fehler
	LMNT.PlayerData.Raw.*  dieselbe Logik mit SteamID64 (Text) statt Spielerobjekt (Tests, Werkzeuge)

	Werte: Zahl (endlich), Text, Bool oder flache Tabelle (Liste 1..n oder nicht-numerische
	Text-Schlüssel) aus diesen Typen, kodiert höchstens MAX_VALUE_BYTES. Gespeichert als JSON-Fragment
	(wie lmnt_config). Jeder Wert wird beim Set einmal kodiert und zurückgelesen: Was nicht exakt
	zurückkommt, wird abgelehnt statt später verfälscht geladen.

	dataUnavailable: Schlägt das Laden fehl, liefert Get nil + Fehler (NIE den Standardwert) und
	Set/Increment liefern false + Fehler mit Log-Warnung. Eine Belohnung geht damit nicht still verloren,
	der Aufrufer sieht die Ablehnung. Das Intervall versucht das Laden erneut.

	Events: lmnt.playerdata.loaded (ply), lmnt.playerdata.saved (ply, anzahl)
	Befehl: !datastats (Recht "dev")      Einstellung: core.playerdata.flush_interval (Sekunden)
]]

local MODULE_ID = "core.playerdata"
local MAX_VALUE_BYTES = 4096      -- kodierte Größe eines Werts
local MAX_TABLE_ENTRIES = 64      -- Einträge einer flachen Tabelle
local MAX_NAME_LENGTH = 64        -- Modul- und Schlüsselnamen
local NAME_PATTERN = "^[%w_%.%-:]+$"
local REJECT_LOG_INTERVAL = 60    -- Sekunden zwischen zwei Ablehnungs-Warnungen pro Spieler
local TIMER = "LMNT.PlayerData.Flush"

LMNT.PlayerData = LMNT.PlayerData or {}
local PD = LMNT.PlayerData
PD.Raw = PD.Raw or {}
local Raw = PD.Raw

-- Zustand bleibt bei einem Lua-Refresh erhalten (sonst gingen ungespeicherte Änderungen verloren)
PD._profiles = PD._profiles or {}
PD._stats = PD._stats or { hits = 0, misses = 0, rejected = 0, loadErrors = 0, flushErrors = 0, corrupt = 0, lastFlush = {} }
PD._rejectLog = PD._rejectLog or {}
-- Abfragefunktion austauschbar, damit Tests Lade- und Speicherfehler simulieren können
PD._query = LMNT.DB.QueryStrict
PD.Limits = { valueBytes = MAX_VALUE_BYTES, tableEntries = MAX_TABLE_ENTRIES, nameLength = MAX_NAME_LENGTH }

local profiles = PD._profiles
local stats = PD._stats
local rejectLog = PD._rejectLog

LMNT.Events.Define("lmnt.playerdata.loaded", { desc = "Spielerdaten geladen, Get/Set sind ab jetzt möglich", args = { "ply" } })
LMNT.Events.Define("lmnt.playerdata.saved", { desc = "Geänderte Spielerdaten gespeichert (nur bei anzahl > 0)", args = { "ply", "anzahl" } })

------------------------------------------------------------------------
-- Tabelle (über die eigene Migration angelegt)
------------------------------------------------------------------------

local MIGRATIONS = {
	[1] = function(exec)
		exec([[CREATE TABLE IF NOT EXISTS lmnt_player_data (
			steamid TEXT NOT NULL,
			module TEXT NOT NULL,
			key TEXT NOT NULL,
			value TEXT NOT NULL,
			updated_at INTEGER NOT NULL,
			PRIMARY KEY (steamid, module, key)
		)]])
		exec("CREATE INDEX IF NOT EXISTS lmnt_player_data_module ON lmnt_player_data (module)")
	end,
}

local migrated, _, migrateErr = LMNT.DB.Migrate(MODULE_ID, MIGRATIONS)
PD._ready = migrated
PD._readyError = migrateErr

------------------------------------------------------------------------
-- Kodierung und Prüfung der Werte
------------------------------------------------------------------------

local function isFiniteNumber(v)
	return isnumber(v) and v == v and v ~= math.huge and v ~= -math.huge
end

local function isScalar(v)
	return isstring(v) or isbool(v) or isFiniteNumber(v)
end

local function scalarError(v)
	if isnumber(v) then return "Zahl muss endlich sein (kein NaN oder Unendlich)" end
	if istable(v) then return "verschachtelte Tabellen sind nicht erlaubt" end
	return "Typ " .. type(v) .. " ist nicht erlaubt (nur Zahl, Text, Bool oder flache Tabelle)"
end

-- Kürzeste Darstellung, die beim Einlesen exakt dieselbe Zahl ergibt (%.17g genügt für jede Zahl)
local function encodeNumber(n)
	for _, fmt in ipairs({ "%.15g", "%.16g" }) do
		local s = string.format(fmt, n)
		if tonumber(s) == n then return s end
	end
	return string.format("%.17g", n)
end

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(s)
	local escaped = string.gsub(s, '[%c"\\]', function(c)
		return ESCAPES[c] or string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. escaped .. '"'
end

local function encodeScalar(v)
	if isnumber(v) then return encodeNumber(v) end
	if isbool(v) then return v and "true" or "false" end
	return encodeString(v)
end

-- JSON-Fragment -> ok, wert (Format wie lmnt_config: Fragment in [] einlesen)
local function decode(json)
	local t = util.JSONToTable("[" .. tostring(json) .. "]")
	if not istable(t) or t[1] == nil then return false end
	return true, t[1]
end

-- Gleichheit für Skalare und flache Tabellen (Typ muss übereinstimmen, 1 ~= "1")
local function sameValue(a, b)
	if type(a) ~= type(b) then return false end
	if not istable(a) then return a == b end
	for k, v in pairs(a) do
		if type(b[k]) ~= type(v) or b[k] ~= v then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

local function copy(v)
	if not istable(v) then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = x end
	return out
end

local function encodeTable(value)
	local count = 0
	for _ in pairs(value) do count = count + 1 end
	if count > MAX_TABLE_ENTRIES then
		return nil, "Tabelle hat " .. count .. " Einträge, erlaubt sind höchstens " .. MAX_TABLE_ENTRIES
	end

	local isList = true
	for i = 1, count do
		if value[i] == nil then isList = false break end
	end

	local parts = {}
	if isList then
		for i = 1, count do
			if not isScalar(value[i]) then return nil, "Listenelement " .. i .. ": " .. scalarError(value[i]) end
			parts[i] = encodeScalar(value[i])
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end

	-- Numerische Text-Schlüssel ("5") würde util.JSONToTable beim Laden in Zahlen umwandeln
	local keys = {}
	for k, v in pairs(value) do
		if not isstring(k) or k == "" or tonumber(k) ~= nil then
			return nil, "Schlüssel müssen nicht-numerische Texte sein oder eine Liste 1..n bilden (Schlüssel " .. tostring(k) .. ")"
		end
		if #k > MAX_NAME_LENGTH then return nil, "Schlüssel '" .. string.sub(k, 1, 20) .. "…' ist länger als " .. MAX_NAME_LENGTH .. " Zeichen" end
		if not isScalar(v) then return nil, "Feld '" .. k .. "': " .. scalarError(v) end
		keys[#keys + 1] = k
	end
	table.sort(keys)
	for i, k in ipairs(keys) do parts[i] = encodeString(k) .. ":" .. encodeScalar(value[k]) end
	return "{" .. table.concat(parts, ",") .. "}"
end

function PD.ValidateValue(value)
	local json, err
	if istable(value) then
		json, err = encodeTable(value)
		if not json then return false, err end
	elseif isScalar(value) then
		json = encodeScalar(value)
	else
		return false, scalarError(value)
	end

	if #json > MAX_VALUE_BYTES then
		return false, "Wert ist kodiert " .. #json .. " Bytes groß, erlaubt sind höchstens " .. MAX_VALUE_BYTES
	end

	-- Rundreise: Nur was beim Laden exakt so zurückkommt, wird angenommen
	local ok, decoded = decode(json)
	if not ok or not sameValue(decoded, value) then
		return false, "Wert lässt sich nicht verlustfrei speichern (z. B. ungültiges UTF-8 im Text)"
	end

	return true, json
end

------------------------------------------------------------------------
-- Profile (Cache) – interne Ebene über SteamID64
------------------------------------------------------------------------

local function checkSteamID(sid)
	if not isstring(sid) or #sid ~= 17 or not string.match(sid, "^%d+$") then
		return false, "ungültige SteamID64 '" .. tostring(sid) .. "' (erwartet 17 Ziffern als Text)"
	end
	return true
end

local function checkName(what, name)
	if not isstring(name) or name == "" then return false, what .. " fehlt" end
	if #name > MAX_NAME_LENGTH then return false, what .. " ist länger als " .. MAX_NAME_LENGTH .. " Zeichen" end
	if not string.match(name, NAME_PATTERN) then
		return false, what .. " '" .. name .. "' enthält unerlaubte Zeichen (erlaubt: Buchstaben, Ziffern, _ . - :)"
	end
	return true
end

local function checkKey(module, key)
	local ok, err = checkName("Modulname", module)
	if not ok then return false, err end
	return checkName("Schlüssel", key)
end

local function describe(sid)
	local ply = player.GetBySteamID64(sid)
	if IsValid(ply) then return ply:Nick() .. " (" .. sid .. ")" end
	return sid
end

-- state: "not_loaded" (angelegt, noch nicht geladen) | "loaded" | "unavailable" (dataUnavailable)
-- ply: verbundener Spieler · orphan: Spieler weg, Speichern beim Disconnect fehlgeschlagen
-- volatile: nur im Speicher (Bots), wird nie geschrieben
local function newProfile(sid)
	return { steamid = sid, state = "not_loaded", data = {}, dirty = {}, dirtyCount = 0, orphan = false, volatile = false }
end

local function clearDirty(p)
	p.dirty = {}
	p.dirtyCount = 0
end

local function markDirty(p, module, key)
	if p.volatile then return end
	local d = p.dirty[module]
	if not d then
		d = {}
		p.dirty[module] = d
	end
	if not d[key] then
		d[key] = true
		p.dirtyCount = p.dirtyCount + 1
	end
end

-- Schreibt einen Wert in den Cache und markiert ihn als geändert; unveränderte Werte bleiben sauber
local function store(p, module, key, value, json)
	local entries = p.data[module]
	local entry = entries and entries[key]

	if value == nil then
		if not entry then return end
		entries[key] = nil
		if next(entries) == nil then p.data[module] = nil end
	else
		if entry and entry.json == json then return end
		if not entries then
			entries = {}
			p.data[module] = entries
		end
		entries[key] = { value = copy(value), json = json }
	end

	markDirty(p, module, key)
end

local function markUnavailable(p, reason)
	local first = p.state ~= "unavailable"
	p.state = "unavailable"
	p.error = reason
	p.data = {}
	clearDirty(p)
	stats.loadErrors = stats.loadErrors + 1

	if first then
		LMNT.Log.Error("playerdata", "dataUnavailable für " .. describe(p.steamid) .. ": " .. reason .. " – Änderungen werden abgewiesen, bis das Laden gelingt")
	else
		LMNT.Log.Debug("playerdata", "Erneuter Ladeversuch für " .. describe(p.steamid) .. " fehlgeschlagen: " .. reason)
	end
	return false, reason
end

-- Warnung bei abgewiesenen Schreibzugriffen, höchstens einmal pro Minute und Spieler
local function logRejected(sid, msg)
	local entry = rejectLog[sid]
	local now = SysTime()
	if entry and entry.nextAt > now then
		entry.suppressed = entry.suppressed + 1
		return
	end

	local extra = (entry and entry.suppressed > 0) and (" (+" .. entry.suppressed .. " weitere seit der letzten Meldung)") or ""
	rejectLog[sid] = { nextAt = now + REJECT_LOG_INTERVAL, suppressed = 0 }
	LMNT.Log.Warn("playerdata", msg .. extra)
end

local function rejectWrite(sid, module, key, reason)
	local msg = "Schreibzugriff " .. module .. "/" .. key .. " abgewiesen: " .. reason .. " – Änderung wurde NICHT übernommen"
	logRejected(sid, msg)
	return false, msg
end

-- Liefert das geladene Profil oder nil + Grund (zählt als abgewiesener Zugriff)
local function access(sid)
	local ok, err = checkSteamID(sid)
	if not ok then return nil, err end

	local p = profiles[sid]
	if p and p.state == "loaded" then return p end

	stats.rejected = stats.rejected + 1
	if p and p.state == "unavailable" then
		return nil, "Spielerdaten von " .. describe(sid) .. " sind nicht verfügbar (dataUnavailable: " .. tostring(p.error) .. ")"
	end
	return nil, "Spielerdaten von " .. describe(sid) .. " sind nicht geladen"
end

function Raw.Load(sid)
	local ok, err = checkSteamID(sid)
	if not ok then return false, err end

	-- Ein geladenes Profil wird weiterverwendet: Es kann ungespeicherte Änderungen enthalten (z. B.
	-- nach einem fehlgeschlagenen Speichern beim Verlassen), die erneutes Laden überschreiben würde.
	local p = profiles[sid]
	if p and p.state == "loaded" then return true end

	if not p then
		p = newProfile(sid)
		profiles[sid] = p
	end

	if not PD._ready then
		return markUnavailable(p, "Tabelle lmnt_player_data nicht bereit (" .. tostring(PD._readyError) .. ")")
	end

	local rows, qErr = PD._query("SELECT module, key, value FROM lmnt_player_data WHERE steamid = ?", sid)
	if not rows then return markUnavailable(p, "Laden fehlgeschlagen: " .. tostring(qErr)) end

	p.data = {}
	clearDirty(p)
	for _, row in ipairs(rows) do
		local decoded, value = decode(row.value)
		if decoded then
			p.data[row.module] = p.data[row.module] or {}
			p.data[row.module][row.key] = { value = value, json = row.value }
		else
			-- Nicht still verwerfen: Rohwert steht im Log, die Zeile bleibt in der DB unverändert
			stats.corrupt = stats.corrupt + 1
			LMNT.Log.Warn("playerdata", "Beschädigter Wert ignoriert: " .. describe(sid) .. " " .. tostring(row.module) .. "/" .. tostring(row.key) .. " = " .. tostring(row.value))
		end
	end

	p.state = "loaded"
	p.error = nil
	p.loadedAt = os.time()
	return true
end

function Raw.Status(sid)
	local p = profiles[sid]
	if not p or p.state == "not_loaded" then return "not_loaded" end
	if p.state == "unavailable" then return "unavailable", p.error end
	return "loaded"
end

function Raw.DirtyCount(sid)
	local p = profiles[sid]
	return p and p.dirtyCount or 0
end

function Raw.Get(sid, module, key, default)
	local ok, err = checkKey(module, key)
	if not ok then return nil, err end

	local p, aErr = access(sid)
	if not p then return nil, aErr end

	local entries = p.data[module]
	local entry = entries and entries[key]
	if entry then
		stats.hits = stats.hits + 1
		return copy(entry.value)
	end

	stats.misses = stats.misses + 1
	return copy(default)
end

function Raw.Set(sid, module, key, value)
	local ok, err = checkKey(module, key)
	if not ok then return false, err end

	local json
	if value ~= nil then
		local valid, result = PD.ValidateValue(value)
		if not valid then return false, "Wert für " .. module .. "/" .. key .. " abgelehnt: " .. result end
		json = result
	end

	local p, aErr = access(sid)
	if not p then return rejectWrite(sid, module, key, aErr) end

	store(p, module, key, value, json)
	return true
end

function Raw.Increment(sid, module, key, delta)
	local ok, err = checkKey(module, key)
	if not ok then return false, err end
	if not isFiniteNumber(delta) then return false, "Increment: delta muss eine endliche Zahl sein" end

	local p, aErr = access(sid)
	if not p then return rejectWrite(sid, module, key, aErr) end

	local entries = p.data[module]
	local entry = entries and entries[key]
	local current = 0
	if entry then
		if not isnumber(entry.value) then
			return false, "Increment: " .. module .. "/" .. key .. " ist keine Zahl (" .. type(entry.value) .. ")"
		end
		current = entry.value
	end

	local new = current + delta
	local valid, json = PD.ValidateValue(new)
	if not valid then return false, "Increment: " .. json end

	store(p, module, key, new, json)
	return true, new
end

------------------------------------------------------------------------
-- Speichern (gebündelt, als Transaktion)
------------------------------------------------------------------------

-- Läuft innerhalb der Transaktion; ein Fehler wirft und rollt alles zurück
local function writeProfile(p, now)
	local count = 0
	for module, keys in pairs(p.dirty) do
		local entries = p.data[module]
		for key in pairs(keys) do
			local entry = entries and entries[key]
			local rows, err
			if entry then
				rows, err = PD._query("REPLACE INTO lmnt_player_data (steamid, module, key, value, updated_at) VALUES (?, ?, ?, ?, ?)", p.steamid, module, key, entry.json, now)
			else
				rows, err = PD._query("DELETE FROM lmnt_player_data WHERE steamid = ? AND module = ? AND key = ?", p.steamid, module, key)
			end
			if not rows then error("SQL-Fehler bei " .. module .. "/" .. key .. ": " .. tostring(err), 0) end
			count = count + 1
		end
	end
	return count
end

-- Gemeinsamer Ablauf für Flush und FlushAll: EINE Transaktion für alle übergebenen Profile.
-- Dirty-Markierungen werden erst nach dem Commit entfernt; bei Fehler bleibt alles markiert.
local function flushProfiles(list)
	-- In einer fremden Transaktion könnte ein späterer Rollback die Zeilen verwerfen, während der
	-- Cache sie schon für gespeichert hält. Deshalb verweigern (Feld aus core/sv_db.lua).
	if LMNT.DB._inTransaction then
		return false, "Flush ist innerhalb einer laufenden Transaktion nicht erlaubt"
	end

	local pending = {}
	for _, p in ipairs(list) do
		if p.state == "loaded" and not p.volatile and p.dirtyCount > 0 then pending[#pending + 1] = p end
	end
	if #pending == 0 then return true, 0 end

	local start = SysTime()
	local now = os.time()
	local counts = {}
	local ok, result = LMNT.DB.Transaction(function()
		local total = 0
		for i, p in ipairs(pending) do
			counts[i] = writeProfile(p, now)
			total = total + counts[i]
		end
		return total
	end)

	stats.lastFlush = {
		at = os.time(), ms = (SysTime() - start) * 1000, profiles = #pending,
		entries = ok and result or 0, ok = ok, error = (not ok) and tostring(result) or nil,
	}

	if not ok then
		stats.flushErrors = stats.flushErrors + 1
		LMNT.Log.Error("playerdata", "Speichern fehlgeschlagen (" .. #pending .. " Profil(e)), Änderungen bleiben im Cache: " .. tostring(result))
		return false, tostring(result)
	end

	for i, p in ipairs(pending) do
		clearDirty(p)
		if IsValid(p.ply) and counts[i] > 0 then
			LMNT.Events.Emit("lmnt.playerdata.saved", p.ply, counts[i])
		end
	end
	return true, result
end

function Raw.Flush(sid)
	local ok, err = checkSteamID(sid)
	if not ok then return false, err end

	local p = profiles[sid]
	if not p or p.state == "not_loaded" then return false, "Spielerdaten von " .. describe(sid) .. " sind nicht geladen" end
	if p.state == "unavailable" then
		return false, "Spielerdaten von " .. describe(sid) .. " sind nicht verfügbar (dataUnavailable) – es gibt nichts Gespeichertes zu sichern"
	end

	return flushProfiles({ p })
end

-- Gibt den Cache frei. Ungespeicherte Änderungen nur mit verwerfen = true; verbundene Spieler nie.
function Raw.Unload(sid, discard)
	local p = profiles[sid]
	if not p then return true end
	if IsValid(p.ply) then return false, "Profil gehört zu einem verbundenen Spieler" end
	if p.dirtyCount > 0 and not discard then
		return false, p.dirtyCount .. " ungespeicherte Änderung(en) – erst Flush, oder Unload(sid, true) zum Verwerfen"
	end

	profiles[sid] = nil
	rejectLog[sid] = nil
	return true
end

function PD.FlushAll()
	local list = {}
	for _, p in pairs(profiles) do list[#list + 1] = p end

	local ok, result = flushProfiles(list)
	if ok then
		-- Profile verlassener Spieler, deren Speichern beim Disconnect fehlschlug, sind jetzt gesichert
		for sid, p in pairs(profiles) do
			if p.orphan and p.dirtyCount == 0 then
				profiles[sid] = nil
				rejectLog[sid] = nil
			end
		end
	end
	return ok, result
end

------------------------------------------------------------------------
-- Spieler-API
------------------------------------------------------------------------

local function steamIDOf(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return nil, "kein gültiger Spieler" end
	local sid = ply:SteamID64()
	local ok = checkSteamID(sid)
	if not ok then return nil, LMNT.Name(ply) .. " hat keine gültige SteamID64 (" .. tostring(sid) .. ")" end
	return sid
end

function PD.Load(ply)
	local sid, err = steamIDOf(ply)
	if not sid then return false, err end

	-- Bots: Profil nur im Speicher, wird nie geschrieben (keine Bot-Daten in der Datenbank)
	if ply:IsBot() then
		local p = profiles[sid]
		if not p or not p.volatile then
			p = newProfile(sid)
			p.volatile = true
			p.state = "loaded"
			profiles[sid] = p
		end
		p.ply = ply
		LMNT.Events.Emit("lmnt.playerdata.loaded", ply)
		return true
	end

	local wasUnavailable = Raw.Status(sid) == "unavailable"
	local ok, loadErr = Raw.Load(sid)

	local p = profiles[sid]
	if p then
		p.ply = ply
		p.orphan = false
	end
	if not ok then return false, loadErr end

	if wasUnavailable then
		LMNT.Log.Info("playerdata", "Spielerdaten von " .. describe(sid) .. " nach früherem Fehler geladen")
	end
	LMNT.Events.Emit("lmnt.playerdata.loaded", ply)
	return true
end

function PD.Status(ply)
	local sid, err = steamIDOf(ply)
	if not sid then return "not_loaded", err end
	return Raw.Status(sid)
end

function PD.IsLoaded(ply)
	return PD.Status(ply) == "loaded"
end

function PD.Get(ply, module, key, default)
	local sid, err = steamIDOf(ply)
	if not sid then return nil, err end
	return Raw.Get(sid, module, key, default)
end

function PD.Set(ply, module, key, value)
	local sid, err = steamIDOf(ply)
	if not sid then return false, err end
	return Raw.Set(sid, module, key, value)
end

function PD.Increment(ply, module, key, delta)
	local sid, err = steamIDOf(ply)
	if not sid then return false, err end
	return Raw.Increment(sid, module, key, delta)
end

function PD.Flush(ply)
	local sid, err = steamIDOf(ply)
	if not sid then return false, err end
	return Raw.Flush(sid)
end

function PD.Stats()
	local out = {
		hits = stats.hits, misses = stats.misses, rejected = stats.rejected,
		loadErrors = stats.loadErrors, flushErrors = stats.flushErrors, corrupt = stats.corrupt,
		lastFlush = table.Copy(stats.lastFlush),
		profiles = 0, online = 0, orphans = 0, bots = 0, unavailable = 0, dirty = 0,
		interval = LMNT.Settings.Get("core.playerdata.flush_interval"),
		ready = PD._ready, readyError = PD._readyError,
	}

	for _, p in pairs(profiles) do
		out.profiles = out.profiles + 1
		if IsValid(p.ply) then out.online = out.online + 1 end
		if p.orphan then out.orphans = out.orphans + 1 end
		if p.volatile then out.bots = out.bots + 1 end
		if p.state == "unavailable" then out.unavailable = out.unavailable + 1 end
		out.dirty = out.dirty + p.dirtyCount
	end
	return out
end

------------------------------------------------------------------------
-- Lebenszyklus: Join, Intervall, Disconnect, Herunterfahren
------------------------------------------------------------------------

-- Letzte Rettung beim Herunterfahren: Was nicht in die DB kam, landet als Datei unter data/lmnt/
local function writeRescueFile(reason)
	local entries = {}
	for sid, p in pairs(profiles) do
		if p.state == "loaded" and not p.volatile then
			for module, keys in pairs(p.dirty) do
				for key in pairs(keys) do
					local entry = p.data[module] and p.data[module][key]
					entries[#entries + 1] = { steamid = sid, module = module, key = key, value = entry and entry.json or nil, deleted = entry == nil }
				end
			end
		end
	end
	if #entries == 0 then return end

	file.CreateDir("lmnt")
	local path = "lmnt/playerdata_unsaved_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
	file.Write(path, util.TableToJSON({ reason = reason, time = os.date("%Y-%m-%d %H:%M:%S"), entries = entries }, true))
	LMNT.Log.Error("playerdata", #entries .. " ungespeicherte Änderung(en) beim Herunterfahren nach data/" .. path .. " gesichert – manuelle Wiederherstellung nötig")
end

local function tick()
	PD.FlushAll()

	-- dataUnavailable: erneut laden; Belohnungen gibt es erst nach erfolgreichem Laden
	for _, ply in ipairs(player.GetAll()) do
		if PD.Status(ply) == "unavailable" then PD.Load(ply) end
	end
end

local function startTimer(seconds)
	timer.Create(TIMER, seconds, 0, tick)
end

LMNT.Settings.Define("core.playerdata.flush_interval", {
	type = "int", default = 60, min = 15, max = 1800,
	desc = "Abstand in Sekunden, in dem geänderte Spielerdaten gebündelt gespeichert werden (zusätzlich bei Disconnect und Serverende). Höchstens so viel geht bei einem Absturz verloren.",
	category = "Spielerdaten", applies = "live",
	onChange = function(new) startTimer(new) end,
})
startTimer(LMNT.Settings.Get("core.playerdata.flush_interval"))

hook.Add("PlayerInitialSpawn", "LMNT.PlayerData.Load", function(ply)
	PD.Load(ply)
end)

hook.Add("PlayerDisconnected", "LMNT.PlayerData.Save", function(ply)
	local sid = steamIDOf(ply)
	local p = sid and profiles[sid]
	if not p then return end

	if p.state == "loaded" and not p.volatile and p.dirtyCount > 0 then
		local ok = flushProfiles({ p })
		if not ok then
			-- Nicht freigeben: Das Intervall versucht es erneut, ein Reconnect übernimmt den Cache
			p.ply = nil
			p.orphan = true
			LMNT.Log.Warn("playerdata", describe(sid) .. " hat den Server verlassen, " .. p.dirtyCount .. " Änderung(en) bleiben bis zum nächsten erfolgreichen Speichern im Speicher")
			return
		end
	end

	profiles[sid] = nil
	rejectLog[sid] = nil
end)

-- Läuft auch beim Mapwechsel; ein Absturz des Servers (Crash) löst ShutDown NICHT aus
hook.Add("ShutDown", "LMNT.PlayerData.SaveAll", function()
	local ok, err = PD.FlushAll()
	if not ok then writeRescueFile(err) end
end)

-- Bereits verbundene Spieler (Lua-Refresh oder spätes Laden) übernehmen
for _, ply in ipairs(player.GetAll()) do
	if not PD.IsLoaded(ply) then PD.Load(ply) end
end

------------------------------------------------------------------------
-- Diagnose
------------------------------------------------------------------------

LMNT.Admin.AddCommand("datastats", {
	perm = "dev", log = false,
	help = "Statistik des Spielerdaten-Caches (Treffer, Dirty-Einträge, letzter Flush, Ladefehler)",
	run = function(caller)
		local col = LMNT.Config.Colors
		local s = PD.Stats()

		LMNT.Reply(caller, col.primary, "Spielerdaten-Cache (Schema v" .. tostring(LMNT.DB.SchemaVersion(MODULE_ID)) .. ", Flush alle " .. s.interval .. " s):")
		if not s.ready then
			LMNT.Reply(caller, col.bad, "Tabelle nicht bereit: " .. tostring(s.readyError) .. " – alle Spieler sind dataUnavailable")
		end
		LMNT.Reply(caller, color_white, string.format("Profile: %d (verbunden %d, Bots %d, wartend auf Speichern %d)", s.profiles, s.online, s.bots, s.orphans))
		LMNT.Reply(caller, color_white, string.format("Lesezugriffe: %d Treffer, %d Fehlzugriffe (Standardwert)   abgewiesen: %d", s.hits, s.misses, s.rejected))
		LMNT.Reply(caller, s.dirty > 0 and col.warn or col.good, "Ungespeicherte Einträge (dirty): " .. s.dirty)

		local lf = s.lastFlush
		if lf.at then
			LMNT.Reply(caller, lf.ok and col.good or col.bad, string.format("Letzter Flush: vor %d s, %.2f ms, %d Einträge aus %d Profil(en)%s",
				os.time() - lf.at, lf.ms, lf.entries, lf.profiles, lf.ok and "" or (" – FEHLER: " .. tostring(lf.error))))
		else
			LMNT.Reply(caller, col.muted, "Seit dem Start wurde noch nichts gespeichert")
		end

		LMNT.Reply(caller, (s.unavailable + s.loadErrors + s.flushErrors + s.corrupt) > 0 and col.warn or color_white,
			string.format("dataUnavailable: %d   Ladefehler: %d   Speicherfehler: %d   beschädigte Werte: %d", s.unavailable, s.loadErrors, s.flushErrors, s.corrupt))

		for sid, p in pairs(profiles) do
			if p.state == "unavailable" then
				LMNT.Reply(caller, col.bad, "  " .. describe(sid) .. ": " .. tostring(p.error))
			end
		end
	end,
})
