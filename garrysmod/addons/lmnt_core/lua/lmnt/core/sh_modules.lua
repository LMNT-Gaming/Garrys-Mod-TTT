--[[
	LMNT Framework – Modulsystem
	API-Referenz: docs/framework/api/modules.md

	LMNT.Modules.Register({
		id = "ttt.stats",                 -- eindeutig, [a-z0-9._-]
		name = "Statistik & Level",
		version = "1.0.0",
		framework = "1.1.0",              -- benötigte LMNT-Mindestversion
		description = "...",
		files = { "lmnt_ttt/sv_stats.lua", "lmnt_ttt/cl_stats.lua" },  -- Präfix bestimmt den Realm
		depends = { "ttt.base" },         -- müssen aktiv sein
		conflicts = { "anderes.modul" },  -- dürfen nicht aktiv sein
		required = false,                 -- true = nicht abschaltbar
		default = true,                   -- Standardzustand, falls nie umgeschaltet
		init = function(M) end,           -- nach dem Laden der Dateien
		shutdown = function(M) end,       -- vor der Bereinigung beim Deaktivieren
	})
	LMNT.Modules.StartAll()              -- topologisch sortiert; einmal nach allen Registrierungen
	LMNT.Modules.Enable(id) / Disable(id) / Reload(id)
	LMNT.Modules.Get(id), LMNT.Modules.Status() -> Liste { id, name, version, state, error, registrations }
	LMNT.Modules.New({ persist = false }) -> unabhängige Registry (Tests)

	Zustände: registered · enabled · disabled · blocked (Abhängigkeit fehlt/aus, Konflikt) · failed (Fehler)

	Automatische Bereinigung:
	  Während ein Modul seine Dateien lädt bzw. init() ausführt, werden hook.Add, timer.Create,
	  net.Receive, concommand.Add, LMNT.Admin.AddCommand, LMNT.Events.On und weitere Registries
	  (über LMNT.Modules.TrackUndo) erfasst. Beim Deaktivieren und bei Startfehlern wird alles entfernt.
	  NICHT erfasst: Registrierungen, die später zur Laufzeit (z. B. in einem Callback) entstehen –
	  dafür M:Hook / M:Timer / M:On verwenden. timer.Simple lässt sich grundsätzlich nicht entfernen.
	  Persistente Daten (Datenbank) werden beim Deaktivieren nie gelöscht.

	Ein/Aus-Zustand: Einstellung "module.<id>.enabled" (persistiert, an Clients repliziert, Recht "modules").
]]

local ModuleMeta = {}
ModuleMeta.__index = ModuleMeta

local hookCounter = 0

function ModuleMeta:Hook(event, fn)
	hookCounter = hookCounter + 1
	local id = "LMNT." .. self.id .. "." .. event .. "." .. hookCounter
	self._rawHookAdd(event, id, fn)
	table.insert(self.undo, function() hook.Remove(event, id) end)
	return id
end

function ModuleMeta:Timer(name, delay, reps, fn)
	local full = "LMNT." .. self.id .. "." .. name
	self._rawTimerCreate(full, delay, reps, fn)
	table.insert(self.undo, function() timer.Remove(full) end)
	return full
end

function ModuleMeta:On(event, fn, opts)
	hookCounter = hookCounter + 1
	opts = opts or {}
	opts.owner = self.id
	return LMNT.Events.On(event, "mod:" .. self.id .. ":" .. hookCounter, fn, opts)
end

function ModuleMeta:Setting(key)
	return LMNT.Settings.Get(key)
end

function ModuleMeta:LogInfo(msg) if SERVER then LMNT.Log.Info(self.id, msg) end end
function ModuleMeta:LogWarn(msg) if SERVER then LMNT.Log.Warn(self.id, msg) end end
function ModuleMeta:LogError(msg) if SERVER then LMNT.Log.Error(self.id, msg) end end

------------------------------------------------------------------------
-- Erfassung von Registrierungen
------------------------------------------------------------------------

local capturing = nil
local rawHookAdd, rawTimerCreate, rawNetReceive, rawConAdd = hook.Add, timer.Create, net.Receive, concommand.Add

-- Registries des Frameworks melden hierüber, wie sich eine Registrierung rückgängig machen lässt
local function trackUndo(fn)
	if capturing then table.insert(capturing.undo, fn) end
end

local function withCapture(M, fn)
	local prev = capturing
	capturing = M

	hook.Add = function(event, id, f, ...)
		rawHookAdd(event, id, f, ...)
		table.insert(M.undo, function() hook.Remove(event, id) end)
	end
	timer.Create = function(name, ...)
		rawTimerCreate(name, ...)
		table.insert(M.undo, function() timer.Remove(name) end)
	end
	net.Receive = function(name, f)
		rawNetReceive(name, f)
		table.insert(M.undo, function() net.Receivers[string.lower(name)] = nil end)
	end
	concommand.Add = function(name, ...)
		rawConAdd(name, ...)
		table.insert(M.undo, function() concommand.Remove(name) end)
	end

	local ok, err = pcall(fn)

	hook.Add, timer.Create, net.Receive, concommand.Add = rawHookAdd, rawTimerCreate, rawNetReceive, rawConAdd
	capturing = prev
	return ok, err
end

local function runUndo(M)
	local count = #M.undo
	for i = count, 1, -1 do
		local ok, err = pcall(M.undo[i])
		if not ok then ErrorNoHalt("[LMNT] Bereinigung in Modul " .. M.id .. " fehlgeschlagen: " .. tostring(err) .. "\n") end
	end
	M.undo = {}
	LMNT.Events.RemoveOwner(M.id)
	return count
end

------------------------------------------------------------------------
-- Registry
------------------------------------------------------------------------

local Registry = {}
Registry.__index = Registry

local function newRegistry(opts)
	opts = opts or {}
	return setmetatable({ mods = {}, persist = opts.persist ~= false }, Registry)
end

local function log(level, msg)
	if SERVER and LMNT.Log and LMNT.Log[level] then
		LMNT.Log[level]("modules", msg)
	else
		MsgC(Color(255, 49, 49), "[LMNT][modules] ", color_white, msg .. "\n")
	end
end

local function settingKey(id)
	return "module." .. id .. ".enabled"
end

function Registry:IsWanted(M)
	if M.def.required or not self.persist then return M.def.default ~= false or M.def.required == true end
	local def = LMNT.Settings.GetDef(settingKey(M.id))
	return def and LMNT.Settings.Get(settingKey(M.id)) or false
end

function Registry:Register(def)
	assert(istable(def), "Modules.Register: Definition fehlt")
	assert(isstring(def.id) and string.match(def.id, "^[%w%._%-]+$"), "Modules.Register: ungültige id " .. tostring(def.id))

	local existing = self.mods[def.id]
	if existing and existing.state == "enabled" then
		error("Modules.Register: Modul '" .. def.id .. "' ist bereits registriert und aktiv", 2)
	end

	def.name = def.name or def.id
	def.version = def.version or "1.0.0"
	def.files = def.files or {}
	def.depends = def.depends or {}
	def.conflicts = def.conflicts or {}

	local M = setmetatable({ id = def.id, def = def, state = "registered", undo = {}, error = nil,
		_rawHookAdd = rawHookAdd, _rawTimerCreate = rawTimerCreate }, ModuleMeta)
	self.mods[def.id] = M

	-- Clientdateien immer verschicken, damit ein später aktiviertes Modul auch auf Clients laden kann
	if SERVER then
		for _, f in ipairs(def.files) do
			if not string.StartWith(string.GetFileFromFilename(f), "sv_") then AddCSLuaFile(f) end
		end
	end

	if self.persist and not def.required then
		local registry = self
		LMNT.Settings.Define(settingKey(def.id), {
			type = "bool", default = def.default ~= false,
			desc = "Modul „" .. def.name .. "“ aktiv", category = "Module", perm = "modules",
			applies = "live", replicate = true,
			onChange = function(enabled)
				if enabled then registry:Enable(def.id) else registry:Disable(def.id) end
			end,
		})
	end

	return M
end

function Registry:Get(id)
	return self.mods[id]
end

local function setState(M, state, err)
	M.state = state
	M.error = err
end

function Registry:Enable(id)
	local M = self.mods[id]
	if not M then return false, "Unbekanntes Modul: " .. tostring(id) end
	if M.state == "enabled" then return true end
	local def = M.def

	if def.framework and not LMNT.VersionAtLeast(def.framework) then
		setState(M, "failed", "benötigt LMNT " .. def.framework .. " (installiert " .. LMNT.Version .. ")")
		return false, M.error
	end

	for _, other in ipairs(def.conflicts) do
		local o = self.mods[other]
		if o and o.state == "enabled" then
			setState(M, "blocked", "Konflikt mit aktivem Modul " .. other)
			log("Warn", id .. ": " .. M.error)
			return false, M.error
		end
	end

	for _, dep in ipairs(def.depends) do
		local d = self.mods[dep]
		if not d then
			setState(M, "blocked", "Abhängigkeit fehlt: " .. dep)
			log("Warn", id .. ": " .. M.error)
			return false, M.error
		end
		if d.state ~= "enabled" then
			setState(M, "blocked", "Abhängigkeit nicht aktiv: " .. dep)
			return false, M.error
		end
	end

	M.undo = {}
	local ok, err = withCapture(M, function()
		for _, f in ipairs(def.files) do LMNT.Include(f) end
		if def.init then def.init(M) end
	end)

	if not ok then
		local removed = runUndo(M)
		setState(M, "failed", tostring(err))
		log("Error", "Modul " .. id .. " konnte nicht starten (" .. removed .. " Registrierungen zurückgenommen): " .. tostring(err))
		LMNT.Events.Emit("lmnt.module.failed", id, tostring(err))
		return false, M.error
	end

	setState(M, "enabled")
	LMNT.Events.Emit("lmnt.module.enabled", id)

	-- Module, die nur auf dieses gewartet haben, nachziehen
	for otherId, o in pairs(self.mods) do
		if o.state == "blocked" and table.HasValue(o.def.depends, id) and self:IsWanted(o) then
			self:Enable(otherId)
		end
	end

	return true
end

function Registry:Disable(id, reason)
	local M = self.mods[id]
	if not M then return false, "Unbekanntes Modul: " .. tostring(id) end
	if M.def.required then return false, "Modul " .. id .. " ist erforderlich und kann nicht deaktiviert werden" end
	if M.state ~= "enabled" then
		setState(M, "disabled")
		return true
	end

	-- Abhängige Module zuerst kontrolliert herunterfahren (sie werden "blocked", nicht still kaputt)
	local cascaded = {}
	for otherId, o in pairs(self.mods) do
		if o.state == "enabled" and table.HasValue(o.def.depends, id) then
			self:Disable(otherId, "Abhängigkeit " .. id .. " deaktiviert")
			setState(o, "blocked", "Abhängigkeit nicht aktiv: " .. id)
			cascaded[#cascaded + 1] = otherId
		end
	end

	if M.def.shutdown then
		local ok, err = pcall(M.def.shutdown, M)
		if not ok then log("Error", "shutdown von " .. id .. ": " .. tostring(err)) end
	end

	local removed = runUndo(M)
	setState(M, "disabled", reason)
	log("Info", "Modul " .. id .. " deaktiviert (" .. removed .. " Registrierungen entfernt" ..
		(#cascaded > 0 and ("; ebenfalls gestoppt: " .. table.concat(cascaded, ", ")) or "") .. ")")
	LMNT.Events.Emit("lmnt.module.disabled", id)
	return true, cascaded
end

function Registry:Reload(id)
	local M = self.mods[id]
	if not M then return false, "Unbekanntes Modul: " .. tostring(id) end
	if M.state == "enabled" then
		if M.def.required then return false, "Erforderliche Module können nur per Neustart neu geladen werden" end
		self:Disable(id, "Reload")
	end
	return self:Enable(id)
end

-- Topologische Reihenfolge; Zyklen werden erkannt und als "failed" markiert
function Registry:Order()
	local order, visiting, done, cyclic = {}, {}, {}, {}

	local function visit(id, path)
		if done[id] then return end
		if visiting[id] then
			for _, p in ipairs(path) do cyclic[p] = true end
			return
		end
		visiting[id] = true
		local M = self.mods[id]
		if M then
			path[#path + 1] = id
			for _, dep in ipairs(M.def.depends) do visit(dep, path) end
			path[#path] = nil
			order[#order + 1] = id
		end
		visiting[id] = nil
		done[id] = true
	end

	local ids = table.GetKeys(self.mods)
	table.sort(ids)
	for _, id in ipairs(ids) do visit(id, {}) end
	return order, cyclic
end

function Registry:StartAll()
	local order, cyclic = self:Order()
	local started = 0

	for _, id in ipairs(order) do
		local M = self.mods[id]
		if cyclic[id] then
			setState(M, "failed", "Zyklische Abhängigkeit")
			log("Error", "Modul " .. id .. ": zyklische Abhängigkeit")
		elseif M.state ~= "enabled" then
			if self:IsWanted(M) then
				if self:Enable(id) then started = started + 1 end
			else
				setState(M, "disabled")
			end
		end
	end

	return started, #order
end

function Registry:Status()
	local list = {}
	for id, M in pairs(self.mods) do
		list[#list + 1] = {
			id = id, name = M.def.name, version = M.def.version, state = M.state, error = M.error,
			required = M.def.required == true, depends = M.def.depends, registrations = #M.undo,
		}
	end
	table.SortByMember(list, "id", true)
	return list
end

------------------------------------------------------------------------
-- Globale Registry mit Punkt-Syntax
------------------------------------------------------------------------

local default = LMNT.Modules and LMNT.Modules._registry or newRegistry()

LMNT.Modules = { _registry = default, TrackUndo = trackUndo, New = newRegistry }
for _, method in ipairs({ "Register", "Get", "Enable", "Disable", "Reload", "StartAll", "Status", "Order", "IsWanted" }) do
	LMNT.Modules[method] = function(...) return default[method](default, ...) end
end
