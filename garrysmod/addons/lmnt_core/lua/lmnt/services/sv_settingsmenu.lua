--[[
	LMNT Admin – Server-Teil des grafischen Configurators (Admin-Menü, Tabs „Module“ und „Einstellungen“)
	API-Referenz: docs/framework/api/admin-configurator.md

	Warum ein eigener Dienst: Beim Client liegen nur replizierte Werte und nur Definitionen aus
	geteilten Dateien. Die vollständige Liste (inkl. sv_-Definitionen) und der Modulzustand kommen
	deshalb vom Server – und nur an Spieler mit dem jeweiligen Recht.

	Netzwerknachrichten (alle Anfragen: Rechteprüfung, Rate-Limit pro Spieler, Größenbegrenzung)
	  lmnt_admin_cfg_modules   C->S Anfrage (Recht "modules")  ·  S->C Modulliste
	  lmnt_admin_cfg_settings  C->S Anfrage (Recht "config")   ·  S->C Definitionen + aktuelle Werte (nur def.perm)
	  lmnt_admin_cfg_set       C->S key, reset?, wert (Text)    -> LMNT.Settings.Set/Reset(key, wert, ply)
	  lmnt_admin_cfg_module    C->S id, an?                     -> LMNT.Settings.Set("module.<id>.enabled", an, ply)
	  lmnt_admin_cfg_result    S->C ok, meldung[, key, neuer wert]  (Client zeigt LMNT.UI.Toast)

	Schreibrechte prüft zusätzlich LMNT.Settings.Set selbst (def.perm, Fehlversuch -> security-Log).
]]

util.AddNetworkString("lmnt_admin_cfg_modules")
util.AddNetworkString("lmnt_admin_cfg_settings")
util.AddNetworkString("lmnt_admin_cfg_set")
util.AddNetworkString("lmnt_admin_cfg_module")
util.AddNetworkString("lmnt_admin_cfg_result")

-- Grenzen für eingehende Nachrichten (len im Receive-Callback ist in Bit)
local MAX_REQUEST_BITS = 64            -- Listen-Anfragen haben keinen Inhalt
local MAX_SET_BITS = 4096 * 8          -- key + Wert; längere Texte erlaubt keine Einstellung sinnvoll
local MAX_MODULE_BITS = 256 * 8        -- Modul-id + Bool

-- Abstände zwischen Anfragen pro Spieler (Sekunden)
local LIST_DELAY = 1
local WRITE_DELAY = 0.3

-- Ausgehende Nachrichten bleiben deutlich unter der 64-KB-Grenze von net
local MAX_OUT_BYTES = 60000
local MAX_TEXT = 400                   -- Beschreibungen, Fehlergründe
local MAX_VALUE_TEXT = 1024            -- Textwerte in der Liste
local MAX_CHOICES = 64

local APPLIES_TEXT = { live = "sofort", nextround = "ab der nächsten Runde", restart = "nach einem Neustart" }

local function clip(text, max)
	text = tostring(text or "")
	if #text > max then return string.sub(text, 1, max) end
	return text
end

local function throttle(ply, field, delay)
	local now = CurTime()
	if (ply[field] or 0) > now then return false end
	ply[field] = now + delay
	return true
end

local function formatValue(value)
	if isbool(value) then return value and "an" or "aus" end
	return tostring(value)
end

-- Werte typgerecht schreiben; der Client liest anhand von def.type (gleiche Reihenfolge wie hier)
local function writeValue(def, value)
	if def.type == "bool" then
		net.WriteBool(value == true)
	elseif def.type == "int" or def.type == "number" then
		net.WriteDouble(tonumber(value) or 0)
	else
		net.WriteString(clip(value, MAX_VALUE_TEXT))
	end
end

local function sendResult(ply, ok, text, key)
	local def = key and LMNT.Settings.GetDef(key)
	-- Den neuen Wert nur mitschicken, wenn der Spieler die Einstellung auch sehen darf
	if def and not LMNT.HasPerm(ply, def.perm) then def = nil end

	net.Start("lmnt_admin_cfg_result")
	net.WriteBool(ok == true)
	net.WriteString(clip(text, MAX_TEXT))
	net.WriteBool(def ~= nil)
	if def then
		net.WriteString(def.key)
		writeValue(def, LMNT.Settings.Get(def.key))
	end
	net.Send(ply)
end

local function deny(ply, what)
	LMNT.Log.Security("config", LMNT.Name(ply) .. " sendete ohne Recht eine Configurator-Anfrage (" .. what .. ")")
	sendResult(ply, false, "Keine Berechtigung")
end

------------------------------------------------------------------------
-- Listen an den Client
------------------------------------------------------------------------

local function moduleKey(id)
	return "module." .. id .. ".enabled"
end

local function sendModules(ply)
	net.Start("lmnt_admin_cfg_modules")
	local truncated = false

	for _, m in ipairs(LMNT.Modules.Status()) do
		if net.BytesWritten() > MAX_OUT_BYTES then truncated = true break end

		-- Gewünschter Zustand: erforderliche Module immer an, sonst die Einstellung module.<id>.enabled
		local wanted = true
		if not m.required and LMNT.Settings.GetDef(moduleKey(m.id)) then
			wanted = LMNT.Settings.Get(moduleKey(m.id)) == true
		end

		net.WriteBool(true)
		net.WriteString(clip(m.id, 128))
		net.WriteString(clip(m.name, 128))
		net.WriteString(clip(m.version, 32))
		net.WriteString(clip(m.state, 16))
		net.WriteString(clip(m.error or "", MAX_TEXT))
		net.WriteBool(m.required)
		net.WriteBool(wanted)
		net.WriteUInt(math.min(m.registrations or 0, 65535), 16)
		net.WriteString(clip(table.concat(m.depends or {}, ", "), 256))
	end

	net.WriteBool(false)
	net.WriteBool(truncated)
	net.Send(ply)
end

local function sendSettings(ply)
	net.Start("lmnt_admin_cfg_settings")
	local truncated = false

	for _, def in ipairs(LMNT.Settings.List()) do
		-- Nur Einstellungen, die der Spieler auch ändern darf (Werte gehen nur an Berechtigte)
		if LMNT.HasPerm(ply, def.perm) then
			if net.BytesWritten() > MAX_OUT_BYTES then truncated = true break end

			net.WriteBool(true)
			net.WriteString(def.key)
			net.WriteString(def.type)
			net.WriteString(clip(def.category, 64))
			net.WriteString(clip(def.desc or "", MAX_TEXT))
			net.WriteString(def.applies)
			writeValue(def, def.default)
			writeValue(def, LMNT.Settings.Get(def.key))

			net.WriteBool(def.min ~= nil)
			if def.min ~= nil then net.WriteDouble(def.min) end
			net.WriteBool(def.max ~= nil)
			if def.max ~= nil then net.WriteDouble(def.max) end
			net.WriteUInt(math.Clamp(def.maxLength or 0, 0, 65535), 16)

			local choices = def.type == "enum" and def.choices or {}
			local count = math.min(#choices, MAX_CHOICES)
			net.WriteUInt(count, 8)
			for i = 1, count do net.WriteString(clip(choices[i], 64)) end
		end
	end

	net.WriteBool(false)
	net.WriteBool(truncated)
	net.Send(ply)
end

net.Receive("lmnt_admin_cfg_modules", function(len, ply)
	if not IsValid(ply) or len > MAX_REQUEST_BITS then return end
	if not throttle(ply, "LMNTNextCfgModules", LIST_DELAY) then return end
	if not LMNT.HasPerm(ply, "modules") then deny(ply, "Modulliste") return end
	sendModules(ply)
end)

net.Receive("lmnt_admin_cfg_settings", function(len, ply)
	if not IsValid(ply) or len > MAX_REQUEST_BITS then return end
	if not throttle(ply, "LMNTNextCfgSettings", LIST_DELAY) then return end
	if not LMNT.HasPerm(ply, "config") then deny(ply, "Einstellungsliste") return end
	sendSettings(ply)
end)

------------------------------------------------------------------------
-- Schreibaktionen
------------------------------------------------------------------------

-- Ergebnis eines Modul-Umschaltens ehrlich melden: Settings.Set gelingt auch dann, wenn der Start
-- danach an einer Abhängigkeit oder einem Fehler scheitert. Deshalb wird der echte Zustand gelesen.
local function moduleOutcome(id, enable)
	local M = LMNT.Modules.Get(id)
	if not M then return false, "Modul " .. id .. " ist nicht mehr registriert" end

	if enable then
		if M.state == "enabled" then return true, "Modul " .. id .. " aktiviert" end
		return false, "Modul " .. id .. " ist " .. M.state .. (M.error and (": " .. M.error) or "")
	end

	if M.state == "enabled" then return false, "Modul " .. id .. " läuft noch" end

	local stopped = {}
	for _, m in ipairs(LMNT.Modules.Status()) do
		if m.state == "blocked" and m.error == "Abhängigkeit nicht aktiv: " .. id then stopped[#stopped + 1] = m.id end
	end
	return true, "Modul " .. id .. " deaktiviert" .. (#stopped > 0 and (" – ebenfalls gestoppt: " .. table.concat(stopped, ", ")) or "")
end

net.Receive("lmnt_admin_cfg_set", function(len, ply)
	if not IsValid(ply) then return end
	if len > MAX_SET_BITS then
		LMNT.Log.Security("config", LMNT.Name(ply) .. " sendete eine zu große Einstellungs-Nachricht (" .. math.ceil(len / 8) .. " Byte)")
		return
	end
	if not throttle(ply, "LMNTNextCfgWrite", WRITE_DELAY) then return end

	local key = net.ReadString()
	local reset = net.ReadBool()
	local raw = not reset and net.ReadString() or nil

	if not LMNT.HasPerm(ply, "config") then deny(ply, "Einstellung " .. clip(key, 64)) return end

	local def = LMNT.Settings.GetDef(key)
	if not def then sendResult(ply, false, "Unbekannte Einstellung: " .. clip(key, 64)) return end
	-- Settings.Set/Reset prüfen def.perm ebenfalls; hier zusätzlich, damit kein Wert zurückgeht
	if not LMNT.HasPerm(ply, def.perm) then deny(ply, "Einstellung " .. key) return end

	local ok, result
	if reset then
		ok, result = LMNT.Settings.Reset(key, ply)
	else
		ok, result = LMNT.Settings.Set(key, raw, ply)
	end

	if not ok then
		sendResult(ply, false, key .. ": " .. tostring(result), key)
		return
	end

	local text = key .. (reset and " zurückgesetzt auf " or " = ") .. formatValue(result) ..
		" (wirkt " .. (APPLIES_TEXT[def.applies] or def.applies) .. ")"

	-- Modul-Schalter über den Einstellungs-Tab: tatsächlichen Modulzustand melden
	local moduleId = string.match(key, "^module%.(.+)%.enabled$")
	if moduleId and LMNT.Modules.Get(moduleId) then
		local mok, mtext = moduleOutcome(moduleId, result == true)
		ok, text = mok, mtext
	end

	sendResult(ply, ok, text, key)
end)

net.Receive("lmnt_admin_cfg_module", function(len, ply)
	if not IsValid(ply) or len > MAX_MODULE_BITS then return end
	if not throttle(ply, "LMNTNextCfgWrite", WRITE_DELAY) then return end

	local id = net.ReadString()
	local enable = net.ReadBool()

	if not LMNT.HasPerm(ply, "modules") then deny(ply, "Modul " .. clip(id, 64)) return end

	local M = LMNT.Modules.Get(id)
	if not M then sendResult(ply, false, "Unbekanntes Modul: " .. clip(id, 64)) return end
	if M.def.required then sendResult(ply, false, "Modul " .. id .. " ist erforderlich und kann nicht umgeschaltet werden") return end

	local key = moduleKey(id)
	if not LMNT.Settings.GetDef(key) then sendResult(ply, false, "Modul " .. id .. " hat keinen Schalter") return end

	if enable and LMNT.Settings.Get(key) == true and M.state ~= "enabled" then
		-- Schalter steht schon auf „an“, Settings.Set würde bei gleichem Wert nichts auslösen.
		-- Das Modul ist blocked/failed -> erneuter Startversuch (z. B. nachdem eine Abhängigkeit wieder läuft).
		local started, err = LMNT.Modules.Enable(id)
		LMNT.Log.Info("modules", LMNT.Name(ply) .. " versuchte, Modul " .. id .. " erneut zu starten: " .. (started and "erfolgreich" or tostring(err)))
	else
		local ok, err = LMNT.Settings.Set(key, enable, ply)
		if not ok then
			sendResult(ply, false, "Modul " .. id .. ": " .. tostring(err), key)
			sendModules(ply)
			return
		end
	end

	local ok, text = moduleOutcome(id, enable)
	sendResult(ply, ok, text, key)
	sendModules(ply)
end)
