--[[
	LMNT TTT – TTT2-Erweiterungen auf Basis des LMNT-Frameworks

	Rollen, Items, Waffen, Skins und Sprachen lädt TTT2 selbst aus:
	  lua/terrortown/entities/roles|items, lua/weapons, lua/terrortown/vskin, lua/terrortown/lang
	Alle anderen Features sind LMNT-Module (einzeln abschaltbar: !module <id> aus).
	Registriert wird über den Hook "LMNT.RegisterModules" (vor LMNT.Modules.StartAll()).
]]

hook.Add("LMNT.RegisterModules", "LMNT.TTT.Register", function()
	if engine.ActiveGamemode() ~= "terrortown" then return end

	if not TTT2 then
		MsgC(Color(255, 176, 32), "[LMNT] Warnung: TTT2 wurde nicht erkannt – einige Features funktionieren nur mit TTT2.\n")
	end

	LMNT.TTT = LMNT.TTT or {}
	local R = LMNT.Modules.Register

	-- Erweiterungspunkt: alle Dateien eines Ordners (aus jedem Addon) alphabetisch an eine Dateiliste anhängen.
	-- So kommen neue Waffen-Metadaten und Item-Wirkungen ohne Änderung dieser Datei ins jeweilige Modul.
	local function withFolder(files, folder)
		local found = file.Find(folder .. "/*.lua", "LUA")
		table.sort(found)
		for _, f in ipairs(found) do files[#files + 1] = folder .. "/" .. f end
		return files
	end

	R({
		id = "ttt.base", name = "TTT-Grundlagen", version = "1.1.0", framework = "1.1.0", required = true,
		description = "Gemeinsame Konfiguration und Helfer (Geschwindigkeit, Teams) für alle TTT-Module",
		files = { "lmnt_ttt/sh_config.lua", "lmnt_ttt/sh_util.lua" },
	})

	R({
		id = "ttt.items", name = "Shop-Items (Wirkung)", version = "1.1.0", framework = "1.1.0",
		description = "Wirkung der LMNT-Items (Turbo-Schuhe, Fallschutz, Regeneration, weitere aus lmnt_ttt/items/)",
		files = withFolder({ "lmnt_ttt/sh_items.lua" }, "lmnt_ttt/items"),
		depends = { "ttt.base" },
	})

	R({
		id = "ttt.shop", name = "Waffen-Registry & Shop-Regeln", version = "1.0.0", framework = "1.2.0",
		description = "Waffen-/Item-Metadaten, Erkennung vorhandener Ausrüstung, LMNT-Kaufregeln über TTT2CanOrderEquipment",
		files = withFolder({ "lmnt_ttt/sh_weapons.lua", "lmnt_ttt/sv_shoprules.lua" }, "lmnt_ttt/weapons"),
		depends = { "ttt.base" },
	})

	R({
		id = "ttt.specialrounds", name = "Spezialrunden", version = "1.1.0", framework = "1.1.0",
		description = "Zufällige Spezialrunden mit Ankündigung",
		files = { "lmnt_ttt/sh_specialrounds.lua", "lmnt_ttt/sv_specialrounds.lua", "lmnt_ttt/cl_specialrounds.lua" },
		depends = { "ttt.base" },
		shutdown = function()
			if SERVER and LMNT.TTT.StopSpecial then LMNT.TTT.StopSpecial() end
		end,
	})

	R({
		id = "ttt.stats", name = "Statistik & Level", version = "1.1.0", framework = "1.1.0",
		description = "XP, Level, Punkte, Statistiken, MVP",
		files = { "lmnt_ttt/sh_stats.lua", "lmnt_ttt/sv_stats.lua", "lmnt_ttt/cl_stats.lua" },
		depends = { "ttt.base" },
		-- Bei Aktivierung zur Laufzeit sind Spieler schon online: deren Daten nachladen
		init = function()
			if not SERVER then return end
			for _, ply in ipairs(player.GetAll()) do
				if not ply.LMNTStats then LMNT.TTT.LoadStats(ply) end
			end
		end,
		shutdown = function()
			if SERVER then
				for _, ply in ipairs(player.GetAll()) do LMNT.TTT.SaveStats(ply) end
			end
		end,
	})

	R({
		id = "ttt.pointshop", name = "Pointshop", version = "1.1.0", framework = "1.1.0",
		description = "Kosmetik: Spielermodelle, Hüte, Spuren",
		files = { "lmnt_ttt/sh_pointshop.lua", "lmnt_ttt/sv_pointshop.lua", "lmnt_ttt/cl_pointshop.lua" },
		depends = { "ttt.stats" },
		init = function()
			if not SERVER then return end
			for _, ply in ipairs(player.GetAll()) do LMNT.TTT.LoadInventory(ply) end
		end,
		-- Sichtbares sofort entfernen; gekaufte Items bleiben in der Datenbank erhalten.
		-- Spielermodelle wechseln erst beim nächsten Spawn zurück (TTT2 vergibt sie dort neu).
		shutdown = function()
			if not SERVER then return end
			for _, ply in ipairs(player.GetAll()) do
				if IsValid(ply.LMNTTrail) then ply.LMNTTrail:Remove() end
				ply.LMNTTrail = nil
				ply:SetNWString("lmnt_hat", "")
			end
		end,
	})

	R({
		id = "ttt.moderation", name = "TTT-Moderation", version = "1.0.0", framework = "1.1.0",
		description = "slaynr, respawn, roundrestart, credits, karma",
		files = { "lmnt_ttt/sh_commands.lua" },
		depends = { "ttt.base" },
	})

	R({
		id = "ttt.theme", name = "TTT2-Menüs im LMNT-Look", version = "1.0.0", framework = "1.1.0",
		description = "Wählt beim ersten Besuch den TTT2-Skin lmnt_ttt2",
		files = { "lmnt_ttt/cl_theme.lua" },
	})

	R({
		id = "ttt.maps", name = "Map-Registry & Map-Profile", version = "1.0.0", framework = "1.1.0",
		description = "Bekannte Maps (Workshop, BSP, Mapcycle) und Map-Profile mit Einstellungs-Overrides nur für die jeweilige Map",
		files = { "lmnt_ttt/sh_maps.lua", "lmnt_ttt/sv_maps.lua" },
		init = function(M)
			if SERVER then LMNT.Maps.Start(M) end
		end,
		-- Overrides zurücknehmen; beim Mapwechsel übernimmt das der ShutDown-Hook in sv_maps.lua
		shutdown = function()
			if SERVER and LMNT.Maps and LMNT.Maps.Stop then LMNT.Maps.Stop("Modul deaktiviert") end
		end,
	})
end)
