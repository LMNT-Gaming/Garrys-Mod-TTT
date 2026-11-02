--[[
	LMNT Framework – Core: Version und Lebenszyklus
	API-Referenz: docs/framework/api/core.md

	LMNT.Version                       "MAJOR.MINOR.PATCH" (SemVer)
	LMNT.VersionAtLeast("1.1.0")       -> bool
	LMNT.RequireVersion("1.1.0", wer)  -> wirft Fehler, wenn das Framework zu alt ist
	LMNT.GetPhase()                    -> "boot" | "services" | "modules" | "ready"
	LMNT.SetPhase(phase)               (intern) löst das Event "lmnt.core.phase" aus
	LMNT.OnReady(fn)                   fn sofort, wenn bereits "ready", sonst beim Erreichen
]]

LMNT.Version = "1.2.0" -- 1.2.0: Integration Manager, Service-Autoloader

local PHASES = { boot = 1, services = 2, modules = 3, ready = 4 }
LMNT._phase = LMNT._phase or "boot"
LMNT._readyQueue = LMNT._readyQueue or {}

local function parse(v)
	local a, b, c = string.match(tostring(v), "^(%d+)%.(%d+)%.(%d+)")
	return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

-- Vergleicht zwei SemVer-Strings: -1 (a<b), 0, 1 (a>b)
function LMNT.CompareVersions(a, b)
	local a1, a2, a3 = parse(a)
	local b1, b2, b3 = parse(b)
	if a1 ~= b1 then return a1 < b1 and -1 or 1 end
	if a2 ~= b2 then return a2 < b2 and -1 or 1 end
	if a3 ~= b3 then return a3 < b3 and -1 or 1 end
	return 0
end

function LMNT.VersionAtLeast(required)
	return LMNT.CompareVersions(LMNT.Version, required) >= 0
end

function LMNT.RequireVersion(required, who)
	if not LMNT.VersionAtLeast(required) then
		error(string.format("[LMNT] %s benötigt LMNT %s, installiert ist %s", who or "Ein Addon", required, LMNT.Version), 2)
	end
end

function LMNT.GetPhase()
	return LMNT._phase
end

function LMNT.SetPhase(phase)
	assert(PHASES[phase], "unbekannte Phase: " .. tostring(phase))
	if PHASES[phase] <= PHASES[LMNT._phase] and phase ~= "boot" then return end

	LMNT._phase = phase
	MsgC(Color(255, 49, 49), "[LMNT] ", color_white, "Phase: " .. phase .. "\n")

	if LMNT.Events then LMNT.Events.Emit("lmnt.core.phase", phase) end

	if phase == "ready" then
		local queue = LMNT._readyQueue
		LMNT._readyQueue = {}
		for _, fn in ipairs(queue) do
			local ok, err = pcall(fn)
			if not ok then ErrorNoHalt("[LMNT] OnReady-Fehler: " .. tostring(err) .. "\n") end
		end
	end
end

function LMNT.OnReady(fn)
	if LMNT._phase == "ready" then
		fn()
	else
		table.insert(LMNT._readyQueue, fn)
	end
end
