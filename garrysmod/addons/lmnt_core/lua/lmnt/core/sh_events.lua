--[[
	LMNT Framework – Event-System
	API-Referenz: docs/framework/api/events.md

	Zwei Arten von Events:
	  Beobachter-Events  LMNT.Events.Emit(name, ...)
	      Alle Listener laufen, Rückgabewerte werden ignoriert. Ein Fehler in einem Listener wird
	      protokolliert und stoppt die anderen NICHT.
	  Entscheidungs-Events  LMNT.Events.Ask(name, ...) -> wert, listenerId
	      Listener laufen nach Priorität (hoch zuerst). Der erste Rückgabewert ~= nil entscheidet,
	      danach laufen keine weiteren Listener. Nur für Events mit Define{ decision = true }.

	LMNT.Events.Define(name, { desc = "...", args = { "ply", "level" }, decision = false })
	LMNT.Events.On(name, id, fn, { owner = "modul", priority = 0 })  -> id
	LMNT.Events.Off(name, id)
	LMNT.Events.RemoveOwner(owner)                -> Anzahl entfernter Listener
	LMNT.Events.Stats()                           -> { [name] = { calls, errors, time, listeners } }
	LMNT.Events.New()                             -> neuer, unabhängiger Bus (z. B. für Tests)

	Namensräume: "lmnt.<bereich>.<ereignis>", z. B. lmnt.player.levelup, lmnt.round.begin
	Debug: ConVar lmnt_events_debug 1 gibt jede Ausführung mit Dauer aus.
]]

local cvDebug = CreateConVar("lmnt_events_debug", "0", FCVAR_ARCHIVE, "LMNT: Event-Ausführungen ausgeben (0/1)")

local Bus = {}
Bus.__index = Bus

local function newBus()
	return setmetatable({ defs = {}, listeners = {}, stats = {}, warnedUndefined = {} }, Bus)
end

function Bus:Define(name, def)
	def = def or {}
	def.name = name
	self.defs[name] = def
	return def
end

function Bus:On(name, id, fn, opts)
	assert(isstring(name) and name ~= "", "Events.On: name fehlt")
	assert(isstring(id) and id ~= "", "Events.On: id fehlt")
	assert(isfunction(fn), "Events.On: fn ist keine Funktion")
	opts = opts or {}

	local list = self.listeners[name]
	if not list then
		list = {}
		self.listeners[name] = list
	end

	-- gleiche id = ersetzen (Schutz vor Doppelregistrierung, z. B. bei Reload)
	for i = #list, 1, -1 do
		if list[i].id == id then table.remove(list, i) end
	end

	list[#list + 1] = { id = id, fn = fn, owner = opts.owner, priority = opts.priority or 0 }
	table.sort(list, function(a, b) return a.priority > b.priority end)

	if LMNT.Modules and LMNT.Modules.TrackUndo then
		LMNT.Modules.TrackUndo(function() self:Off(name, id) end)
	end

	return id
end

function Bus:Off(name, id)
	local list = self.listeners[name]
	if not list then return false end
	for i = #list, 1, -1 do
		if list[i].id == id then
			table.remove(list, i)
			return true
		end
	end
	return false
end

function Bus:RemoveOwner(owner)
	local count = 0
	for _, list in pairs(self.listeners) do
		for i = #list, 1, -1 do
			if list[i].owner == owner then
				table.remove(list, i)
				count = count + 1
			end
		end
	end
	return count
end

local function stat(self, name)
	local s = self.stats[name]
	if not s then
		s = { calls = 0, errors = 0, time = 0 }
		self.stats[name] = s
	end
	return s
end

local function run(self, name, listener, ...)
	local start = SysTime()
	local ok, result = pcall(listener.fn, ...)
	local dt = SysTime() - start

	local s = stat(self, name)
	s.time = s.time + dt

	if cvDebug:GetBool() then
		MsgC(Color(165, 161, 172), string.format("[LMNT][event] %s -> %s (%.3f ms)\n", name, listener.id, dt * 1000))
	end

	if not ok then
		s.errors = s.errors + 1
		local msg = "Listener '" .. listener.id .. "' für '" .. name .. "' fehlgeschlagen: " .. tostring(result)
		if SERVER and LMNT.Log and LMNT.Log.Error then
			LMNT.Log.Error("events", msg)
		else
			ErrorNoHalt("[LMNT][events] " .. msg .. "\n")
		end
		return false, nil
	end

	return true, result
end

local function checkDefined(self, name)
	if self.defs[name] or self.warnedUndefined[name] then return end
	self.warnedUndefined[name] = true
	if cvDebug:GetBool() then
		MsgC(Color(255, 176, 32), "[LMNT][event] Hinweis: Event '" .. name .. "' ist nicht per Define dokumentiert\n")
	end
end

function Bus:Emit(name, ...)
	checkDefined(self, name)
	local s = stat(self, name)
	s.calls = s.calls + 1

	local list = self.listeners[name]
	if not list then return end

	-- Kopie: Listener dürfen sich während der Ausführung entfernen
	local snapshot = { unpack(list) }
	for _, listener in ipairs(snapshot) do
		run(self, name, listener, ...)
	end
end

function Bus:Ask(name, ...)
	checkDefined(self, name)
	local def = self.defs[name]
	if def and not def.decision then
		error("Events.Ask: '" .. name .. "' ist kein Entscheidungs-Event (Define mit decision = true)", 2)
	end

	local s = stat(self, name)
	s.calls = s.calls + 1

	local list = self.listeners[name]
	if not list then return nil end

	local snapshot = { unpack(list) }
	for _, listener in ipairs(snapshot) do
		local ok, result = run(self, name, listener, ...)
		if ok and result ~= nil then return result, listener.id end
	end
	return nil
end

function Bus:Stats()
	local out = {}
	for name, s in pairs(self.stats) do
		out[name] = { calls = s.calls, errors = s.errors, time = s.time, listeners = self.listeners[name] and #self.listeners[name] or 0 }
	end
	for name, list in pairs(self.listeners) do
		if not out[name] then out[name] = { calls = 0, errors = 0, time = 0, listeners = #list } end
	end
	return out
end

function Bus:ListenerCount(name)
	local list = self.listeners[name]
	return list and #list or 0
end

------------------------------------------------------------------------
-- Globaler Bus: LMNT.Events.On(...) usw. (Punkt-Syntax wie im restlichen Framework)
------------------------------------------------------------------------

local default = LMNT.Events and LMNT.Events._bus or newBus()

LMNT.Events = { _bus = default }
for _, method in ipairs({ "Define", "On", "Off", "RemoveOwner", "Emit", "Ask", "Stats", "ListenerCount" }) do
	LMNT.Events[method] = function(...) return default[method](default, ...) end
end
LMNT.Events.New = newBus

-- Framework-Events (weitere definieren Module selbst)
LMNT.Events.Define("lmnt.core.phase", { desc = "Lebenszyklus-Phase gewechselt", args = { "phase" } })
LMNT.Events.Define("lmnt.module.enabled", { desc = "Modul wurde aktiviert", args = { "id" } })
LMNT.Events.Define("lmnt.module.disabled", { desc = "Modul wurde deaktiviert", args = { "id" } })
LMNT.Events.Define("lmnt.module.failed", { desc = "Modul konnte nicht starten", args = { "id", "error" } })
LMNT.Events.Define("lmnt.settings.changed", { desc = "Einstellung geändert", args = { "key", "new", "old", "actor" } })
LMNT.Events.Define("lmnt.log.written", { desc = "Log-Eintrag geschrieben (Server)", args = { "level", "category", "message" } })
