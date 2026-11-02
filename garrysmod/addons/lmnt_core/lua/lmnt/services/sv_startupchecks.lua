--[[
	LMNT Service – Sicherheitsprüfung beim Serverstart (T-090, Anti-Cheat-Paket WP-09)

	Prüft nach dem Laden von server.cfg die sicherheitsrelevanten Server-Einstellungen und meldet
	Abweichungen als Log-Eintrag (security bzw. warn). Ändert selbst NICHTS an der Konfiguration.

	Geprüft:
	  sv_cheats 0, sv_allowcslua 0          sonst security
	  sv_lan 0                              sonst warn (Testläufe nutzen absichtlich sv_lan 1 → VAC aus)
	  rcon_password gesetzt, kein Standard  sonst security
	  Dedicated Server                      sonst warn
	VAC: Den VAC-Status stellt GMod Lua nicht bereit; er steht im Server-Log ("VAC secure mode …")
	und in der RCON-Ausgabe von "status" ("secure"). Das wird hier bewusst nicht vorgetäuscht.

	Befehl: !securitycheck (Recht "dev")
]]

local DEFAULT_RCON = "bitte-aendern-1234" -- Platzhalter aus server/settings.ini

local function cvarString(name)
	local cv = GetConVar(name)
	return cv and cv:GetString() or nil
end

function LMNT.RunSecurityChecks()
	local results = {}

	local function add(ok, level, text)
		results[#results + 1] = { ok = ok, level = level, text = text }
	end

	add(cvarString("sv_cheats") == "0", "security", "sv_cheats = " .. tostring(cvarString("sv_cheats")) .. " (erwartet 0)")
	add(cvarString("sv_allowcslua") == "0", "security", "sv_allowcslua = " .. tostring(cvarString("sv_allowcslua")) .. " (erwartet 0)")
	add(cvarString("sv_lan") == "0", "warn", "sv_lan = " .. tostring(cvarString("sv_lan")) .. " (erwartet 0; bei 1 ist VAC aus – nur für Tests zulässig)")

	local rcon = cvarString("rcon_password")
	if rcon == nil then
		add(true, "info", "rcon_password nicht lesbar – Prüfung übersprungen")
	else
		add(rcon ~= "" and rcon ~= DEFAULT_RCON, "security",
			rcon == "" and "rcon_password ist leer" or (rcon == DEFAULT_RCON and "rcon_password ist noch der Standardwert aus settings.ini" or "rcon_password gesetzt"))
	end

	add(game.IsDedicated(), "warn", game.IsDedicated() and "Dedicated Server" or "kein Dedicated Server (Listen-Server)")

	local problems = 0
	for _, r in ipairs(results) do
		if not r.ok then
			problems = problems + 1
			if r.level == "security" then
				LMNT.Log.Security("startcheck", r.text)
			else
				LMNT.Log.Warn("startcheck", r.text)
			end
		end
	end

	if problems == 0 then
		LMNT.Log.Info("startcheck", "Sicherheitsprüfung: alle " .. #results .. " Prüfungen bestanden")
	end
	return results, problems
end

-- server.cfg wird nach dem Laden der Map ausgeführt; danach kurz warten
hook.Add("InitPostEntity", "LMNT.StartupChecks", function()
	timer.Simple(5, LMNT.RunSecurityChecks)
end)

LMNT.Admin.AddCommand("securitycheck", {
	perm = "dev", log = false,
	help = "Prüft sicherheitsrelevante Server-Einstellungen (sv_cheats, sv_allowcslua, sv_lan, RCON)",
	run = function(caller)
		local col = LMNT.Config.Colors
		local results, problems = LMNT.RunSecurityChecks()
		for _, r in ipairs(results) do
			LMNT.Reply(caller, r.ok and col.good or (r.level == "security" and col.bad or col.warn), (r.ok and "OK   " or "PRÜFEN ") .. r.text)
		end
		LMNT.Reply(caller, problems == 0 and col.good or col.warn, problems .. " Auffälligkeit(en)")
	end,
})
