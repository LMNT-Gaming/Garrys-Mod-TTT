--[[
	LMNT Framework – Einstiegspunkt (Server + Client)
	Lebenszyklus: boot → services (Core-Dienste geladen) → modules (Module starten) → ready
	Siehe docs/framework/02_ZIELARCHITEKTUR.md (Ladereihenfolge)

	Dateipräfixe bestimmen den Realm:
	  sv_  nur Server
	  cl_  nur Client (wird vom Server verschickt)
	  sh_  beides
]]

LMNT = LMNT or {}

function LMNT.Include(path)
	local prefix = string.sub(string.GetFileFromFilename(path), 1, 3)

	if prefix == "sv_" then
		if SERVER then include(path) end
	elseif prefix == "cl_" then
		if SERVER then AddCSLuaFile(path) else include(path) end
	else
		if SERVER then AddCSLuaFile(path) end
		include(path)
	end
end

-- Lädt Dateien eines Framework-Teils (Core-Dienste). Spiel-Features sind Module (LMNT.Modules).
function LMNT.LoadModule(name, files)
	for _, f in ipairs(files) do
		LMNT.Include(f)
	end
	MsgC(Color(255, 49, 49), "[LMNT] ", color_white, "Modul geladen: " .. name .. "\n")
end

LMNT.Include("lmnt/core/sh_core.lua")
LMNT.SetPhase("boot")

LMNT.LoadModule("core", {
	"lmnt/core/sh_config.lua",
	"lmnt/core/sh_util.lua",
	"lmnt/core/sh_net.lua",
	"lmnt/core/sv_db.lua",
	"lmnt/core/sh_events.lua",
	"lmnt/core/sh_settings.lua",
	"lmnt/core/sv_log.lua",
	"lmnt/core/sh_modules.lua",
	"lmnt/core/sh_integrations.lua",
	"lmnt/core/sv_resources.lua",
	"lmnt/core/cl_ui.lua",
	"lmnt/core/sv_test.lua",
})

LMNT.LoadModule("admin", {
	"lmnt/admin/sh_ranks.lua",
	"lmnt/admin/sh_admin.lua",
	"lmnt/admin/sv_admin.lua",
	"lmnt/admin/sv_bans.lua",
	"lmnt/admin/sh_commands.lua",
	"lmnt/admin/sh_devcommands.lua",
	"lmnt/admin/sh_integrationcommands.lua",
	"lmnt/admin/cl_admin.lua",
})

-- Erweiterungspunkt: Alle Dateien in lua/lmnt/services/ (aus jedem Addon) werden automatisch
-- alphabetisch geladen. Neue Dienste brauchen so keine Änderung an dieser Datei.
-- Präfix sv_/cl_/sh_ bestimmt den Realm. Integrationen liegen analog in lua/lmnt/integrations/.
local function loadFolder(folder)
	local files = file.Find(folder .. "/*.lua", "LUA")
	table.sort(files)
	for _, f in ipairs(files) do
		LMNT.Include(folder .. "/" .. f)
	end
	return #files
end

local serviceCount = loadFolder("lmnt/services")
MsgC(Color(255, 49, 49), "[LMNT] ", color_white, serviceCount .. " Service-Datei(en) geladen\n")

LMNT.SetPhase("services")
hook.Run("LMNT.Loaded")

-- Module starten, sobald das Gamemode geladen ist (Addons wie lmnt_ttt registrieren ihre Module vorher)
hook.Add("PostGamemodeLoaded", "LMNT.Modules.Start", function()
	hook.Run("LMNT.RegisterModules")

	LMNT.SetPhase("modules")
	local started, total = LMNT.Modules.StartAll()
	MsgC(Color(255, 49, 49), "[LMNT] ", color_white, started .. "/" .. total .. " Module aktiv\n")

	for _, m in ipairs(LMNT.Modules.Status()) do
		if m.state == "failed" or m.state == "blocked" then
			MsgC(Color(255, 110, 110), "[LMNT] Modul " .. m.id .. ": " .. m.state .. " – " .. tostring(m.error) .. "\n")
		end
	end

	-- Integrationen erst nach dem Gamemode (TTT2) und den Modulen erkennen und aktivieren
	loadFolder("lmnt/integrations")
	hook.Run("LMNT.RegisterIntegrations")
	LMNT.Integrations.StartAll()

	LMNT.SetPhase("ready")
end)
