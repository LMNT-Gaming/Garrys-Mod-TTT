--[[
	LMNT Framework – Einstellungen mit Schema (laufzeitänderbar)
	API-Referenz: docs/framework/api/settings.md

	Abgrenzung: LMNT.Config  = statische Grundkonfiguration (Branding, Ränge, Regeln) in Lua-Dateien
	            LMNT.Settings = typisierte Werte, die ingame geändert, gespeichert und repliziert werden

	LMNT.Settings.Define("ttt.special.chance", {
		type = "number",            -- bool | int | number | string | enum
		default = 0.2,
		min = 0, max = 1,           -- int/number
		choices = { "a", "b" },     -- enum
		maxLength = 64,             -- string
		desc = "Chance pro Runde auf eine Spezialrunde",
		category = "Spezialrunden",
		perm = "config",            -- Recht zum Ändern (Standard "config")
		applies = "nextround",      -- live | nextround | restart (wird im Configurator angezeigt)
		replicate = false,          -- an Clients übertragen?
		onChange = function(new, old) end,  -- läuft auf dem Server bzw. bei replizierten Werten auch auf Clients
	})
	LMNT.Settings.Get(key)                       -> aktueller Wert (nie nil für definierte Keys)
	LMNT.Settings.Set(key, wert, actor)          -> true | false, fehlermeldung       (nur Server)
	LMNT.Settings.Reset(key, actor)              -> zurück auf Datei-Override bzw. Standard (nur Server)
	LMNT.Settings.Validate(def, wert)            -> true, normalisiert | false, fehlermeldung
	LMNT.Settings.List()                         -> sortierte Liste der Definitionen

	Rangfolge der Werte (Server): Ingame-Änderung (DB lmnt_config) > data/lmnt/config.json > default
]]

LMNT.Settings = LMNT.Settings or {}
local S = LMNT.Settings

S._defs = S._defs or {}
S._values = S._values or {}     -- aktuelle Werte
S._stored = S._stored or {}     -- Server: Werte aus der DB (Ingame-Änderungen)
S._file = S._file or {}         -- Server: Werte aus config.json

local APPLIES = { live = true, nextround = true, restart = true }

function S.Validate(def, value)
	local t = def.type

	if t == "bool" then
		if isbool(value) then return true, value end
		if value == "1" or value == 1 or value == "true" or value == "an" or value == "on" then return true, true end
		if value == "0" or value == 0 or value == "false" or value == "aus" or value == "off" then return true, false end
		return false, "Erwartet wahr/falsch (1/0, an/aus)"
	elseif t == "int" or t == "number" then
		local n = tonumber(value)
		if not n or n ~= n then return false, "Erwartet eine Zahl" end
		if t == "int" then
			if math.floor(n) ~= n then return false, "Erwartet eine ganze Zahl" end
		end
		if def.min and n < def.min then return false, "Mindestens " .. def.min end
		if def.max and n > def.max then return false, "Höchstens " .. def.max end
		return true, n
	elseif t == "string" then
		if value == nil then return false, "Erwartet Text" end
		value = tostring(value)
		if def.maxLength and #value > def.maxLength then return false, "Höchstens " .. def.maxLength .. " Zeichen" end
		return true, value
	elseif t == "enum" then
		value = tostring(value)
		for _, c in ipairs(def.choices or {}) do
			if c == value then return true, value end
		end
		return false, "Erlaubt: " .. table.concat(def.choices or {}, ", ")
	end

	return false, "Unbekannter Typ " .. tostring(t)
end

local function effective(key)
	local def = S._defs[key]
	for _, source in ipairs({ S._stored, S._file }) do
		local raw = source[key]
		if raw ~= nil then
			local ok, value = S.Validate(def, raw)
			if ok then return value end
			if SERVER and LMNT.Log and LMNT.Log.Warn then
				LMNT.Log.Warn("config", "Ungültiger gespeicherter Wert für " .. key .. " (" .. tostring(raw) .. "): " .. value .. " – Standard wird verwendet")
			end
		end
	end
	return def.default
end

function S.Define(key, def)
	assert(isstring(key) and key ~= "", "Settings.Define: key fehlt")
	assert(istable(def) and def.type, "Settings.Define: type fehlt (" .. key .. ")")
	def.key = key
	def.perm = def.perm or "config"
	def.applies = APPLIES[def.applies] and def.applies or "live"
	def.category = def.category or "Allgemein"

	local ok, normalized = S.Validate(def, def.default)
	assert(ok, "Settings.Define: ungültiger Standardwert für " .. key .. ": " .. tostring(normalized))
	def.default = normalized

	S._defs[key] = def
	if S._values[key] == nil or SERVER then
		S._values[key] = SERVER and effective(key) or def.default
	end
	return def
end

function S.Get(key)
	local v = S._values[key]
	if v == nil then
		local def = S._defs[key]
		if not def then error("Settings.Get: unbekannte Einstellung '" .. tostring(key) .. "'", 2) end
		return def.default
	end
	return v
end

function S.GetDef(key)
	return S._defs[key]
end

function S.List()
	local list = {}
	for _, def in pairs(S._defs) do list[#list + 1] = def end
	table.sort(list, function(a, b)
		if a.category ~= b.category then return a.category < b.category end
		return a.key < b.key
	end)
	return list
end

local function applyChange(key, new, old, actor)
	local def = S._defs[key]
	if new == old then return end
	if def.onChange then
		local ok, err = pcall(def.onChange, new, old)
		if not ok then ErrorNoHalt("[LMNT] Settings onChange für " .. key .. ": " .. tostring(err) .. "\n") end
	end
	LMNT.Events.Emit("lmnt.settings.changed", key, new, old, actor)
end

------------------------------------------------------------------------
-- Netzwerk: kompakte, typisierte Übertragung replizierter Werte
------------------------------------------------------------------------

local TYPE_BITS = { bool = 0, int = 1, number = 2, string = 3, enum = 3 }

local function writeValue(def, value)
	local kind = TYPE_BITS[def.type]
	net.WriteUInt(kind, 2)
	if kind == 0 then net.WriteBool(value)
	elseif kind == 1 then net.WriteInt(value, 32)
	elseif kind == 2 then net.WriteDouble(value)
	else net.WriteString(value) end
end

local function readValue()
	local kind = net.ReadUInt(2)
	if kind == 0 then return net.ReadBool() end
	if kind == 1 then return net.ReadInt(32) end
	if kind == 2 then return net.ReadDouble() end
	return net.ReadString()
end

if SERVER then
	util.AddNetworkString("lmnt_settings")
	util.AddNetworkString("lmnt_settings_req")

	LMNT.DB.Query([[CREATE TABLE IF NOT EXISTS lmnt_config (
		key TEXT PRIMARY KEY,
		value TEXT NOT NULL,
		changed_by TEXT,
		changed_at INTEGER
	)]])

	-- Werte sind als JSON-Fragment gespeichert (0.3 / true / "text"), damit der Typ erhalten bleibt
	for _, row in ipairs(LMNT.DB.Query("SELECT key, value FROM lmnt_config") or {}) do
		local decoded = util.JSONToTable("[" .. row.value .. "]")
		if decoded and decoded[1] ~= nil then
			S._stored[row.key] = decoded[1]
		else
			S._stored[row.key] = row.value
		end
	end

	local raw = file.Read("lmnt/config.json", "DATA")
	if raw then
		local parsed = util.JSONToTable(raw)
		if istable(parsed) then
			for k, v in pairs(parsed) do
				if not string.StartWith(k, "_") then S._file[k] = v end
			end
		else
			ErrorNoHalt("[LMNT] data/lmnt/config.json ist kein gültiges JSON – Datei wird ignoriert.\n")
		end
	end

	local function encode(value)
		return string.sub(util.TableToJSON({ value }), 2, -2)
	end

	local function sendValues(target, keys)
		local defs = {}
		for _, key in ipairs(keys) do
			local def = S._defs[key]
			if def and def.replicate then defs[#defs + 1] = def end
		end
		if #defs == 0 then return end

		net.Start("lmnt_settings")
		net.WriteUInt(#defs, 12)
		for _, def in ipairs(defs) do
			net.WriteString(def.key)
			writeValue(def, S._values[def.key])
		end
		if target then net.Send(target) else net.Broadcast() end
	end

	function S.Set(key, value, actor)
		local def = S._defs[key]
		if not def then return false, "Unbekannte Einstellung: " .. tostring(key) end
		if IsValid(actor) and not LMNT.HasPerm(actor, def.perm) then
			LMNT.Log.Security("config", LMNT.Name(actor) .. " wollte ohne Recht '" .. def.perm .. "' " .. key .. " ändern")
			return false, "Keine Berechtigung"
		end

		local ok, normalized = S.Validate(def, value)
		if not ok then return false, normalized end

		local old = S._values[key]
		S._stored[key] = normalized
		S._values[key] = normalized
		LMNT.DB.Query("REPLACE INTO lmnt_config (key, value, changed_by, changed_at) VALUES (?, ?, ?, ?)", key, encode(normalized), LMNT.Name(actor), os.time())
		LMNT.Log.Info("config", LMNT.Name(actor) .. " änderte " .. key .. ": " .. tostring(old) .. " -> " .. tostring(normalized) .. " (wirkt: " .. def.applies .. ")")

		if def.replicate then sendValues(nil, { key }) end
		applyChange(key, normalized, old, actor)
		return true, normalized
	end

	function S.Reset(key, actor)
		local def = S._defs[key]
		if not def then return false, "Unbekannte Einstellung: " .. tostring(key) end
		if IsValid(actor) and not LMNT.HasPerm(actor, def.perm) then return false, "Keine Berechtigung" end

		local old = S._values[key]
		S._stored[key] = nil
		LMNT.DB.Query("DELETE FROM lmnt_config WHERE key = ?", key)
		S._values[key] = effective(key)
		LMNT.Log.Info("config", LMNT.Name(actor) .. " setzte " .. key .. " zurück: " .. tostring(old) .. " -> " .. tostring(S._values[key]))

		if def.replicate then sendValues(nil, { key }) end
		applyChange(key, S._values[key], old, actor)
		return true, S._values[key]
	end

	-- Client fordert nach dem Laden alle replizierten Werte an (einmal pro 5 s)
	net.Receive("lmnt_settings_req", function(_, ply)
		if (ply.LMNTNextSettingsReq or 0) > CurTime() then return end
		ply.LMNTNextSettingsReq = CurTime() + 5
		sendValues(ply, table.GetKeys(S._defs))
	end)
else
	net.Receive("lmnt_settings", function()
		for _ = 1, net.ReadUInt(12) do
			local key = net.ReadString()
			local value = readValue()
			local def = S._defs[key]
			if def then
				local old = S.Get(key)
				S._values[key] = value
				applyChange(key, value, old, nil)
			end
		end
	end)

	hook.Add("InitPostEntity", "LMNT.Settings.Request", function()
		net.Start("lmnt_settings_req")
		net.SendToServer()
	end)
end

-- Framework-Einstellungen
S.Define("core.log.retention_days", {
	type = "int", default = LMNT.Config.LogRetentionDays or 30, min = 1, max = 365,
	desc = "Wie viele Tage Log-Einträge in der Datenbank bleiben", category = "Logging", applies = "restart",
})
