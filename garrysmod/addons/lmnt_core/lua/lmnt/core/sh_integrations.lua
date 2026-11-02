--[[
	LMNT Framework – Integration Manager
	Konzept: docs/framework/06_INTEGRATIONEN.md · API: docs/framework/api/integrations.md

	Eine Integration verbindet LMNT mit einem fremden System (TTT2, CAMI, Admin-Mods, Waffen-Addons …).
	Sie ist intern ein Modul (eigene Registry) und erbt damit Lebenszyklus und automatische Bereinigung.
	Zusätzlich: Erkennung (mehrere Belege), Schnittstellenprüfung, Versionsabgleich, Zustand, Nachweisstufe.

	LMNT.Integrations.Register(id, def)       def siehe unten
	LMNT.Integrations.StartAll()               erkennt, prüft und aktiviert (einmal beim Start)
	LMNT.Integrations.Evaluate(id)             erneut erkennen + prüfen (ändert nichts am Aktivzustand)
	LMNT.Integrations.Enable(id) / Disable(id) -> ok, meldung
	LMNT.Integrations.GetStatus(id)            -> Kopie des Status
	LMNT.Integrations.List()                   -> Liste aller Status
	LMNT.Integrations.RunTests(id)             -> bestanden, fehlgeschlagen, meldungen
	LMNT.Integrations.Conflicts()              -> Liste erkannter Konflikte
	LMNT.Integrations.New({ persist = false }) -> unabhängige Instanz (Tests)

	def = {
		name, description, version, vendor,
		lmnt = "1.2.0",                        -- benötigte LMNT-Mindestversion
		testedVersions = { "0.14.6b" },        -- mit diesen Versionen des Zielsystems geprüft
		depends = { "int-id" | "modul-id" }, optional = { ... }, conflicts = { "int-id" },
		detectOnly = false,                    -- true: nur erkennen/melden, kein Adapter
		live = true,                           -- Live-Umschaltung erlaubt (sonst Neustart nötig)
		default = true,                        -- automatisch aktivieren, wenn kompatibel
		detect = function() return gefunden, { belege }, version end,
		validate = function() return { { name = "...", ok = bool, optional = bool } } end,
		files = {}, init = function(M) end, shutdown = function(M) end,
		tests = { { name = "...", run = function(e) end } },
		limitations = { "..." },
	}
]]

local STATES = {
	NOT_INSTALLED = true, DETECTED = true, COMPATIBLE = true, INCOMPATIBLE = true, MISSING_DEPENDENCY = true,
	DISABLED = true, INITIALIZING = true, ACTIVE = true, DEGRADED = true, FAILED = true,
}
local LEVELS = { unknown = 0, detected = 1, interface = 2, partial = 3, basic_test = 4, verified = 5 }

local Manager = {}
Manager.__index = Manager

local function newManager(opts)
	opts = opts or {}
	return setmetatable({
		defs = {}, status = {}, order = {},
		persist = opts.persist ~= false,
		modules = LMNT.Modules.New({ persist = false }),
	}, Manager)
end

local function log(level, msg)
	if SERVER and LMNT.Log and LMNT.Log[level] then
		LMNT.Log[level]("integrations", msg)
	else
		MsgC(Color(255, 49, 49), "[LMNT][integrations] ", color_white, msg .. "\n")
	end
end

local function setState(st, state, reason)
	assert(STATES[state], "unbekannter Integrationszustand " .. tostring(state))
	local previous = st.state
	st.state = state
	st.reason = reason
	st.changed = os.time()
	if previous ~= state then LMNT.Events.Emit("lmnt.integration.changed", st.id, state) end
end

local function raiseLevel(st, level)
	if LEVELS[level] > LEVELS[st.level] then st.level = level end
end

local function settingKey(id) return "integration." .. id .. ".enabled" end

function Manager:Register(id, def)
	assert(isstring(id) and string.match(id, "^[%w%._%-]+$"), "Integrations.Register: ungültige id " .. tostring(id))
	assert(istable(def), "Integrations.Register: Definition fehlt")
	assert(isfunction(def.detect), "Integrations.Register: detect() fehlt (" .. id .. ")")
	if self.defs[id] then
		local st = self.status[id]
		if st and (st.state == "ACTIVE" or st.state == "DEGRADED") then
			error("Integrations.Register: '" .. id .. "' ist bereits registriert und aktiv", 2)
		end
	end

	def.id = id
	def.name = def.name or id
	def.version = def.version or "1.0.0"
	def.depends = def.depends or {}
	def.optional = def.optional or {}
	def.conflicts = def.conflicts or {}
	def.files = def.files or {}
	def.tests = def.tests or {}
	def.limitations = def.limitations or {}
	if def.live == nil then def.live = true end

	self.defs[id] = def
	if not self.status[id] then self.order[#self.order + 1] = id end
	self.status[id] = { id = id, state = "NOT_INSTALLED", level = "unknown", evidence = {}, checks = {}, warnings = {} }

	if not def.detectOnly then
		self.modules:Register({ id = id, name = def.name, version = def.version, framework = def.lmnt,
			files = def.files, init = def.init, shutdown = def.shutdown })
	end

	if self.persist and not def.detectOnly then
		local manager = self
		LMNT.Settings.Define(settingKey(id), {
			type = "bool", default = def.default ~= false, category = "Integrationen", perm = "integrations",
			desc = "Integration „" .. def.name .. "“ aktiv (sofern kompatibel)",
			applies = def.live and "live" or "restart", replicate = true,
			onChange = function(enabled)
				if not def.live then
					manager.status[id].pendingRestart = true
					return
				end
				if enabled then manager:Enable(id) else manager:Disable(id) end
			end,
		})
	end

	return def
end

function Manager:IsWanted(id)
	local def = self.defs[id]
	if not self.persist or def.detectOnly then return def.default ~= false end
	return LMNT.Settings.Get(settingKey(id))
end

local function depSatisfied(self, dep)
	local st = self.status[dep]
	if st then return st.state == "ACTIVE" or st.state == "DEGRADED" end
	local M = LMNT.Modules.Get(dep)
	return M ~= nil and M.state == "enabled"
end

-- Erkennung + Prüfung. Ändert den Aktivzustand nicht.
function Manager:Evaluate(id)
	local def, st = self.defs[id], self.status[id]
	if not def then return nil end
	if st.state == "ACTIVE" or st.state == "DEGRADED" or st.state == "INITIALIZING" then return st end

	st.evidence, st.checks, st.warnings, st.detectedVersion = {}, {}, {}, nil

	if def.lmnt and not LMNT.VersionAtLeast(def.lmnt) then
		setState(st, "INCOMPATIBLE", "benötigt LMNT " .. def.lmnt .. ", installiert " .. LMNT.Version)
		return st
	end

	local ok, found, evidence, version = pcall(def.detect)
	if not ok then
		setState(st, "FAILED", "Erkennung fehlgeschlagen: " .. tostring(found))
		return st
	end
	st.evidence = istable(evidence) and evidence or {}
	st.detectedVersion = version and tostring(version) or nil

	if not found then
		setState(st, "NOT_INSTALLED", "nicht gefunden")
		st.level = "unknown"
		return st
	end
	raiseLevel(st, "detected")

	if #st.evidence < 2 then
		setState(st, "DETECTED", "Erkennung nur schwach belegt (" .. #st.evidence .. " Merkmal) – keine automatische Aktivierung")
		st.weak = true
		return st
	end
	st.weak = false

	for _, dep in ipairs(def.depends) do
		if not depSatisfied(self, dep) then
			setState(st, "MISSING_DEPENDENCY", "benötigt " .. dep)
			return st
		end
	end
	for _, opt in ipairs(def.optional) do
		if not depSatisfied(self, opt) then
			table.insert(st.warnings, "optionale Abhängigkeit fehlt: " .. opt)
		end
	end

	if def.validate then
		local vOk, checks = pcall(def.validate)
		if not vOk then
			setState(st, "FAILED", "Prüfung fehlgeschlagen: " .. tostring(checks))
			return st
		end
		st.checks = istable(checks) and checks or {}
		for _, c in ipairs(st.checks) do
			if not c.ok and not c.optional then
				setState(st, "INCOMPATIBLE", "Schnittstelle fehlt: " .. tostring(c.name))
				return st
			elseif not c.ok then
				table.insert(st.warnings, "optionale Schnittstelle fehlt: " .. tostring(c.name))
			end
		end
		raiseLevel(st, "interface")
	end

	if def.testedVersions and #def.testedVersions > 0 then
		if not st.detectedVersion then
			table.insert(st.warnings, "Version des Zielsystems unbekannt – nicht als getestet einstufbar")
		elseif not table.HasValue(def.testedVersions, st.detectedVersion) then
			table.insert(st.warnings, "Version " .. st.detectedVersion .. " ungetestet (getestet: " .. table.concat(def.testedVersions, ", ") .. ")")
		end
	end

	if def.detectOnly then
		setState(st, "DETECTED", "nur Erkennung (kein Adapter)")
	else
		setState(st, "COMPATIBLE", nil)
	end
	return st
end

function Manager:Enable(id)
	local def, st = self.defs[id], self.status[id]
	if not def then return false, "Unbekannte Integration: " .. tostring(id) end
	if def.detectOnly then return false, "Integration " .. id .. " ist nur eine Erkennung (kein Adapter)" end
	if st.state == "ACTIVE" or st.state == "DEGRADED" then return true end

	for _, other in ipairs(def.conflicts) do
		local o = self.status[other]
		if o and (o.state == "ACTIVE" or o.state == "DEGRADED" or o.state == "DETECTED") then
			setState(st, "INCOMPATIBLE", "Konflikt mit " .. other .. " – explizite Auswahl nötig (eine der beiden deaktivieren)")
			log("Warn", id .. ": " .. st.reason)
			return false, st.reason
		end
	end

	self:Evaluate(id)
	if st.state ~= "COMPATIBLE" then return false, st.state .. ": " .. tostring(st.reason) end

	setState(st, "INITIALIZING")
	local ok, err = self.modules:Enable(id)
	if not ok then
		setState(st, "FAILED", tostring(err))
		log("Error", "Integration " .. id .. " fehlgeschlagen: " .. tostring(err))
		return false, err
	end

	if #st.warnings > 0 then
		setState(st, "DEGRADED", table.concat(st.warnings, "; "))
	else
		setState(st, "ACTIVE")
	end
	log("Info", "Integration " .. id .. " " .. st.state .. (st.reason and (" (" .. st.reason .. ")") or ""))
	return true
end

function Manager:Disable(id)
	local def, st = self.defs[id], self.status[id]
	if not def then return false, "Unbekannte Integration: " .. tostring(id) end
	if not def.live and (st.state == "ACTIVE" or st.state == "DEGRADED") then
		st.pendingRestart = true
		return false, "Integration " .. id .. " unterstützt kein Live-Abschalten – für den nächsten Neustart vorgemerkt"
	end
	if st.state == "ACTIVE" or st.state == "DEGRADED" then
		self.modules:Disable(id)
	end
	setState(st, "DISABLED", "vom Admin deaktiviert")
	return true
end

function Manager:StartAll()
	-- Mehrere Durchläufe, damit Integrationen, die von anderen Integrationen abhängen, nachziehen
	for _ = 1, 3 do
		for _, id in ipairs(self.order) do
			local st = self.status[id]
			if st.state ~= "ACTIVE" and st.state ~= "DEGRADED" then
				self:Evaluate(id)
				if st.state == "COMPATIBLE" then
					if self:IsWanted(id) then self:Enable(id) else setState(st, "DISABLED", "deaktiviert (Einstellung)") end
				end
			end
		end
	end

	for _, c in ipairs(self:Conflicts()) do
		log("Warn", "Konflikt: " .. c.description)
	end
end

function Manager:RunTests(id)
	local def, st = self.defs[id], self.status[id]
	if not def then return 0, 0, { "Unbekannte Integration" } end
	if #def.tests == 0 then return 0, 0, { "keine Tests hinterlegt" } end

	local passed, failed, messages = 0, 0, {}
	for _, t in ipairs(def.tests) do
		local e = LMNT.Test and LMNT.Test.NewExpect and LMNT.Test.NewExpect()
		local ok, err = pcall(t.run, e)
		if ok then
			passed = passed + 1
		else
			failed = failed + 1
			messages[#messages + 1] = t.name .. ": " .. (istable(err) and err.message or tostring(err))
		end
	end

	st.lastTest = { time = os.time(), passed = passed, failed = failed }
	if failed == 0 then
		raiseLevel(st, def.testLevel or "basic_test")
	elseif passed > 0 then
		raiseLevel(st, "partial")
	end
	return passed, failed, messages
end

function Manager:Conflicts()
	local list, seen = {}, {}
	for id, def in pairs(self.defs) do
		local st = self.status[id]
		if st.state ~= "NOT_INSTALLED" then
			for _, other in ipairs(def.conflicts) do
				local o = self.status[other]
				-- Paar nur einmal melden, egal welche Seite den Konflikt deklariert
				local key = id < other and (id .. "|" .. other) or (other .. "|" .. id)
				if o and o.state ~= "NOT_INSTALLED" and not seen[key] then
					seen[key] = true
					list[#list + 1] = { a = id, b = other, kind = "declared",
						description = def.name .. " und " .. self.defs[other].name .. " schließen sich aus" }
				end
			end
			for _, c in ipairs(def.conflictsWithCore or {}) do
				list[#list + 1] = { a = id, b = c.with, kind = "core", description = c.description }
			end
		end
	end
	return list
end

function Manager:GetStatus(id)
	local st = self.status[id]
	if not st then return nil end
	local def = self.defs[id]
	local copy = table.Copy(st)
	copy.name, copy.version, copy.vendor = def.name, def.version, def.vendor
	copy.detectOnly, copy.live, copy.limitations = def.detectOnly == true, def.live, def.limitations
	copy.testedVersions, copy.depends, copy.optional = def.testedVersions, def.depends, def.optional
	copy.registrations = (not def.detectOnly and self.modules:Get(id)) and #self.modules:Get(id).undo or 0
	return copy
end

function Manager:List()
	local out = {}
	for _, id in ipairs(self.order) do out[#out + 1] = self:GetStatus(id) end
	return out
end

------------------------------------------------------------------------
-- Globale Instanz mit Punkt-Syntax
------------------------------------------------------------------------

local default = LMNT.Integrations and LMNT.Integrations._manager or newManager()

LMNT.Integrations = { _manager = default, New = newManager, States = STATES, Levels = LEVELS }
for _, method in ipairs({ "Register", "Evaluate", "Enable", "Disable", "StartAll", "RunTests", "Conflicts", "GetStatus", "List", "IsWanted" }) do
	LMNT.Integrations[method] = function(...) return default[method](default, ...) end
end

LMNT.Events.Define("lmnt.integration.changed", { desc = "Zustand einer Integration geändert", args = { "id", "state" } })
