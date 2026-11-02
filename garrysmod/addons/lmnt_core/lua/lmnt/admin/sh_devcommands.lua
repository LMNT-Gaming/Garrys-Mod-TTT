--[[
	LMNT – Diagnose- und Verwaltungsbefehle (DevTools, Module, Einstellungen, Log-Export)
	Rechte: dev (Superadmin), modules, config, logs.export
]]

local A = LMNT.Admin
local col = LMNT.Config.Colors

local stateColors = {
	enabled = col.good, disabled = col.muted, blocked = col.warn, failed = col.bad, registered = col.muted,
}

A.AddCommand("status", {
	perm = "dev", log = false,
	help = "Framework-Status: Version, Phase, Module, Events, Einstellungen",
	run = function(caller)
		local mods = LMNT.Modules.Status()
		local counts = {}
		for _, m in ipairs(mods) do counts[m.state] = (counts[m.state] or 0) + 1 end

		local events, eventErrors = 0, 0
		for _, s in pairs(LMNT.Events.Stats()) do events = events + 1 eventErrors = eventErrors + s.errors end

		LMNT.Reply(caller, col.primary, "LMNT " .. LMNT.Version, color_white, "  Phase: " .. LMNT.GetPhase())
		LMNT.Reply(caller, color_white, "TTT2: " .. (TTT2 and GAMEMODE and GAMEMODE.Version or "nicht aktiv") .. "   Spieler: " .. player.GetCount() .. "/" .. game.MaxPlayers())
		LMNT.Reply(caller, color_white, "Module: " .. #mods .. " (aktiv " .. (counts.enabled or 0) .. ", aus " .. (counts.disabled or 0) ..
			", blockiert " .. (counts.blocked or 0) .. ", Fehler " .. (counts.failed or 0) .. ")")
		LMNT.Reply(caller, color_white, "Events: " .. events .. " genutzt, " .. eventErrors .. " Listener-Fehler   Einstellungen: " .. #LMNT.Settings.List())
		if SERVER then
			-- Die file-Bibliothek darf sv.db nicht lesen; Größe deshalb über SQLite selbst bestimmen
			local pages = tonumber(LMNT.DB.Value("PRAGMA page_count")) or 0
			local pageSize = tonumber(LMNT.DB.Value("PRAGMA page_size")) or 0
			LMNT.Reply(caller, color_white, "Datenbank sv.db: " .. math.Round(pages * pageSize / 1024 / 1024, 2) .. " MB")
		end
	end,
})

A.AddCommand("modules", {
	perm = "modules", log = false,
	help = "Listet alle Module mit Zustand",
	run = function(caller)
		for _, m in ipairs(LMNT.Modules.Status()) do
			LMNT.Reply(caller, stateColors[m.state] or color_white, string.format("%-10s", m.state), color_white, " " .. m.id .. " ",
				col.muted, "v" .. m.version .. " · " .. m.registrations .. " Registrierungen" .. (m.required and " · erforderlich" or "") ..
				(m.error and (" · " .. m.error) or ""))
		end
	end,
})

A.AddCommand("module", {
	perm = "modules",
	help = "Schaltet ein Modul an/aus (wirkt sofort, auch auf Clients) oder lädt es neu",
	args = {
		{ type = "string", name = "id" },
		{ type = "string", name = "an|aus|reload" },
	},
	run = function(caller, id, action)
		local M = LMNT.Modules.Get(id)
		if not M then
			LMNT.Reply(caller, col.bad, "Unbekanntes Modul: " .. id .. " (Liste: !modules)")
			return
		end
		if M.def.required then
			LMNT.Reply(caller, col.bad, "Modul " .. id .. " ist erforderlich und kann nicht geschaltet werden.")
			return
		end

		action = string.lower(action)
		if action == "reload" then
			-- Reload nur auf dem Server; Clients laden geänderte Dateien beim nächsten Verbinden
			local ok, err = LMNT.Modules.Reload(id)
			LMNT.Reply(caller, ok and col.good or col.bad, ok and ("Modul " .. id .. " neu geladen (Server).") or ("Reload fehlgeschlagen: " .. tostring(err)))
			return
		end

		local enable = action == "an" or action == "on" or action == "1"
		local disable = action == "aus" or action == "off" or action == "0"
		if not enable and not disable then
			LMNT.Reply(caller, col.warn, "Benutzung: !module <id> an|aus|reload")
			return
		end

		local ok, err = LMNT.Settings.Set("module." .. id .. ".enabled", enable, caller)
		if not ok then
			LMNT.Reply(caller, col.bad, "Fehler: " .. tostring(err))
			return
		end
		local state = LMNT.Modules.Get(id).state
		LMNT.Reply(caller, stateColors[state] or color_white, "Modul " .. id .. ": " .. state, col.muted, M.error and (" – " .. M.error) or "")
	end,
})

A.AddCommand("config", {
	perm = "config",
	help = "Einstellungen anzeigen/ändern: !config [key] [wert|reset]",
	args = {
		{ type = "string", name = "key", optional = true },
		{ type = "string", name = "wert|reset", optional = true, rest = true },
	},
	run = function(caller, key, value)
		if not key then
			for _, def in ipairs(LMNT.Settings.List()) do
				local current = LMNT.Settings.Get(def.key)
				LMNT.Reply(caller, current == def.default and color_white or col.warn, def.key .. " = " .. tostring(current),
					col.muted, "  [" .. def.type .. ", Standard " .. tostring(def.default) .. ", wirkt: " .. def.applies .. "]")
			end
			return
		end

		local def = LMNT.Settings.GetDef(key)
		if not def then
			LMNT.Reply(caller, col.bad, "Unbekannte Einstellung: " .. key .. " (Liste: !config)")
			return
		end

		if not value then
			LMNT.Reply(caller, col.primary, key .. " = " .. tostring(LMNT.Settings.Get(key)))
			LMNT.Reply(caller, col.muted, def.desc or "", "  Typ " .. def.type ..
				(def.min and (", min " .. def.min) or "") .. (def.max and (", max " .. def.max) or "") ..
				(def.choices and (", erlaubt: " .. table.concat(def.choices, "/")) or "") ..
				", Standard " .. tostring(def.default) .. ", wirkt: " .. def.applies)
			return
		end

		local ok, result
		if string.lower(value) == "reset" then
			ok, result = LMNT.Settings.Reset(key, caller)
		else
			ok, result = LMNT.Settings.Set(key, value, caller)
		end

		if ok then
			local note = ({ nextround = " (ab der nächsten Runde)", restart = " (nach Serverneustart)" })[def.applies] or ""
			LMNT.Reply(caller, col.good, key .. " = " .. tostring(result) .. note)
		else
			LMNT.Reply(caller, col.bad, "Nicht übernommen: " .. tostring(result))
		end
	end,
})

A.AddCommand("events", {
	perm = "dev", log = false,
	help = "Event-Statistik: Aufrufe, Fehler, Laufzeit",
	run = function(caller)
		local list = {}
		for name, s in pairs(LMNT.Events.Stats()) do
			list[#list + 1] = { name = name, calls = s.calls, errors = s.errors, time = s.time, listeners = s.listeners }
		end
		table.SortByMember(list, "time")
		for i = 1, math.min(#list, 25) do
			local e = list[i]
			LMNT.Reply(caller, e.errors > 0 and col.bad or color_white, e.name, col.muted,
				string.format("  %d Listener · %d Aufrufe · %d Fehler · %.2f ms gesamt", e.listeners, e.calls, e.errors, e.time * 1000))
		end
	end,
})

A.AddCommand("hooks", {
	perm = "dev", log = false,
	help = "Zählt registrierte LMNT-Hooks pro GMod-Hook (Diagnose für Doppelregistrierungen)",
	run = function(caller)
		local total = 0
		for event, handlers in SortedPairs(hook.GetTable()) do
			local n = 0
			for id in pairs(handlers) do
				if isstring(id) and string.StartWith(id, "LMNT") then n = n + 1 end
			end
			if n > 0 then
				total = total + n
				LMNT.Reply(caller, color_white, event, col.muted, "  " .. n)
			end
		end
		LMNT.Reply(caller, col.primary, "LMNT-Hooks gesamt: " .. total)
	end,
})

A.AddCommand("logexport", {
	perm = "logs.export",
	help = "Exportiert Logs als CSV nach data/lmnt/exports/",
	args = {
		{ type = "string", name = "kategorie", optional = true },
		{ type = "string", name = "suche", optional = true, rest = true },
	},
	run = function(caller, category, search)
		local path, count = LMNT.Log.Export(category, search)
		LMNT.Reply(caller, col.good, count .. " Einträge exportiert: " .. path)
	end,
})

A.AddCommand("test", {
	perm = "dev", log = false,
	help = "Führt die LMNT-Unit-Tests auf dem Server aus",
	run = function(caller)
		LMNT.Test.RunAll(caller)
	end,
})
