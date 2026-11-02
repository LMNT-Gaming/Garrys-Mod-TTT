--[[
	Integration "ttt2": TTT2 als primäre Gameplay-Plattform
	Prüft Version und die Schnittstellen, die LMNT tatsächlich nutzt (Fundstellen: docs/framework/01_BESTANDSAUFNAHME.md),
	und übersetzt TTT2-Hooks in einheitliche LMNT-Events (Adapter, T-110).

	Event-Zuordnung (Fundstellen TTT2 0.14.6b):
	  lmnt.round.prepare                      ← TTTPrepareRound            (gameloop.lua:198 / :781)   shared
	  lmnt.round.begin                        ← TTTBeginRound              (gameloop.lua:256 / :785)   shared
	  lmnt.round.end (result)                 ← TTTEndRound(result)        (gameloop.lua:299)          shared – result nur auf dem Server, Client: nil (:789)
	  lmnt.player.death (victim, attacker, inflictor) ← TTT2PostPlayerDeath (sv_player.lua:898)        server – nach TTT2-Verarbeitung (Leiche existiert)
	  lmnt.player.role (ply, alt, neu)        ← TTT2UpdateSubrole          (sh_player_ext.lua:153)     shared
	  lmnt.player.team (ply, alt, neu)        ← TTT2UpdateTeam             (sh_player_ext.lua:173/372) shared
	  lmnt.player.ready (ply)                 ← TTT2PlayerReady            (sv_player_ext.lua:1714)    shared
	  lmnt.shop.purchase (ply, klasse, istItem, credits) ← TTT2OrderedEquipment (sh_shop.lua:348)       server

	Schutz vor Doppel- und Scheinereignissen:
	  - Käufe lösen in TTT2 ZWEI Hooks aus (TTTOrderedEquipment mit Legacy-ID und TTT2OrderedEquipment mit
	    Klassenname). Angebunden wird nur TTT2OrderedEquipment.
	  - SetRole kann TTT2UpdateSubrole/TTT2UpdateTeam mit forceHooks auch ohne Änderung auslösen;
	    lmnt.player.role/team werden nur bei echter Änderung gesendet.
]]

local function check(name, ok, optional)
	return { name = name, ok = ok and true or false, optional = optional }
end

local EVENTS = {
	{ "lmnt.round.prepare", "Vorbereitungsphase beginnt", {} },
	{ "lmnt.round.begin", "Runde beginnt (Rollen vergeben)", {} },
	{ "lmnt.round.end", "Runde endet (result = Gewinnerteam, nur Server)", { "result" } },
	{ "lmnt.player.death", "Spieler gestorben, nach TTT2-Verarbeitung (Server)", { "victim", "attacker", "inflictor" } },
	{ "lmnt.player.role", "Unterrolle tatsächlich geändert", { "ply", "oldSubrole", "newSubrole" } },
	{ "lmnt.player.team", "Team tatsächlich geändert", { "ply", "oldTeam", "newTeam" } },
	{ "lmnt.player.ready", "Spieler vollständig geladen", { "ply" } },
	{ "lmnt.shop.purchase", "Ausrüstung gekauft (Server)", { "ply", "equipmentClass", "isItem", "credits" } },
}

-- Nur echte Änderungen weitergeben (Schutz gegen forceHooks); als Funktion für Tests sichtbar
function LMNT.TTT2ChangedOnly(old, new)
	return old ~= new
end

local function initAdapter()
	for _, e in ipairs(EVENTS) do
		LMNT.Events.Define(e[1], { desc = e[2], args = e[3] })
	end

	local Emit = LMNT.Events.Emit

	hook.Add("TTTPrepareRound", "LMNT.TTT2.Adapter.Prepare", function() Emit("lmnt.round.prepare") end)
	hook.Add("TTTBeginRound", "LMNT.TTT2.Adapter.Begin", function() Emit("lmnt.round.begin") end)
	hook.Add("TTTEndRound", "LMNT.TTT2.Adapter.End", function(result) Emit("lmnt.round.end", result) end)

	hook.Add("TTT2UpdateSubrole", "LMNT.TTT2.Adapter.Role", function(ply, old, new)
		if LMNT.TTT2ChangedOnly(old, new) then Emit("lmnt.player.role", ply, old, new) end
	end)
	hook.Add("TTT2UpdateTeam", "LMNT.TTT2.Adapter.Team", function(ply, old, new)
		if LMNT.TTT2ChangedOnly(old, new) then Emit("lmnt.player.team", ply, old, new) end
	end)
	hook.Add("TTT2PlayerReady", "LMNT.TTT2.Adapter.Ready", function(ply) Emit("lmnt.player.ready", ply) end)

	if SERVER then
		hook.Add("TTT2PostPlayerDeath", "LMNT.TTT2.Adapter.Death", function(victim, inflictor, attacker)
			Emit("lmnt.player.death", victim, attacker, inflictor)
		end)
		hook.Add("TTT2OrderedEquipment", "LMNT.TTT2.Adapter.Purchase", function(ply, equipmentName, isItem, credits)
			Emit("lmnt.shop.purchase", ply, equipmentName, isItem, credits)
		end)
	end
end

LMNT.Integrations.Register("ttt2", {
	name = "TTT2",
	description = "Trouble in Terrorist Town 2 – Rollen, Runden, Equipment",
	version = "1.0.0",
	vendor = "TTT2 Dev Team (Workshop 1357204556)",
	lmnt = "1.2.0",
	testedVersions = { "0.14.6b" },
	live = false, -- TTT2 ist das Gamemode; ein Abschalten zur Laufzeit ist nicht sinnvoll

	detect = function()
		local evidence = {}
		if TTT2 == true then evidence[#evidence + 1] = "Global TTT2 = true" end
		if GAMEMODE and isstring(GAMEMODE.Version) then evidence[#evidence + 1] = "GAMEMODE.Version = " .. GAMEMODE.Version end
		if istable(roles) and isfunction(roles.Register) then evidence[#evidence + 1] = "roles.Register vorhanden" end
		if istable(gameloop) and isfunction(gameloop.GetRoundState) then evidence[#evidence + 1] = "gameloop-Bibliothek vorhanden" end
		return TTT2 == true, evidence, GAMEMODE and GAMEMODE.Version
	end,

	validate = function()
		local plymeta = FindMetaTable("Player")
		local checks = {
			check("roles.InitCustomTeam", istable(roles) and isfunction(roles.InitCustomTeam)),
			check("roles.SetBaseRole", istable(roles) and isfunction(roles.SetBaseRole)),
			check("roles.GetStored", istable(roles) and isfunction(roles.GetStored)),
			check("gameloop.GetRoundState", istable(gameloop) and isfunction(gameloop.GetRoundState)),
			check("ROUND_ACTIVE", isnumber(ROUND_ACTIVE)),
			check("Player:GetSubRole", isfunction(plymeta.GetSubRole)),
			check("Player:GetTeam", isfunction(plymeta.GetTeam)),
			check("Player:IsSpec", isfunction(plymeta.IsSpec)),
			check("Player:HasEquipmentItem", isfunction(plymeta.HasEquipmentItem)),
			check("WEAPON_EXTRA", isnumber(WEAPON_EXTRA)),
			check("TRAITOR_EQUIPMENT", TRAITOR_EQUIPMENT ~= nil),
		}
		if SERVER then
			checks[#checks + 1] = check("admin.RoundRestart", istable(admin) and isfunction(admin.RoundRestart))
			checks[#checks + 1] = check("Player:AddCredits", isfunction(plymeta.AddCredits))
			checks[#checks + 1] = check("Player:SpawnForRound", isfunction(plymeta.SpawnForRound))
			checks[#checks + 1] = check("Player:GiveEquipmentWeapon", isfunction(plymeta.GiveEquipmentWeapon))
		else
			checks[#checks + 1] = check("LANG.GetLanguageTableReference", istable(LANG) and isfunction(LANG.GetLanguageTableReference))
			checks[#checks + 1] = check("vskin.SelectVSkin", istable(vskin) and isfunction(vskin.SelectVSkin), true)
		end
		return checks
	end,

	init = initAdapter,

	tests = {
		{ name = "Adapter: alle TTT2-Hooks genau einmal angebunden", run = function(e)
			local t = hook.GetTable()
			local expected = { TTTPrepareRound = "LMNT.TTT2.Adapter.Prepare", TTTBeginRound = "LMNT.TTT2.Adapter.Begin",
				TTTEndRound = "LMNT.TTT2.Adapter.End", TTT2UpdateSubrole = "LMNT.TTT2.Adapter.Role",
				TTT2UpdateTeam = "LMNT.TTT2.Adapter.Team", TTT2PlayerReady = "LMNT.TTT2.Adapter.Ready",
				TTT2PostPlayerDeath = "LMNT.TTT2.Adapter.Death", TTT2OrderedEquipment = "LMNT.TTT2.Adapter.Purchase" }
			for hookName, id in pairs(expected) do
				e:True(t[hookName] and t[hookName][id] ~= nil, hookName .. " angebunden")
			end
			e:True(not (t.TTTOrderedEquipment and t.TTTOrderedEquipment["LMNT.TTT2.Adapter.Purchase"]), "Legacy-Kaufhook NICHT angebunden (keine Doppelzählung)")
		end },
		{ name = "Adapter: forceHooks ohne Änderung erzeugt kein Event", run = function(e)
			e:False(LMNT.TTT2ChangedOnly(ROLE_INNOCENT, ROLE_INNOCENT))
			e:True(LMNT.TTT2ChangedOnly(ROLE_INNOCENT, ROLE_TRAITOR))
		end },
		{ name = "LMNT-Rollen sind in TTT2 registriert", run = function(e)
			for _, name in ipairs({ "narr", "sanitaeter", "hacker" }) do
				e:True(roles.GetStored(name) ~= nil, "Rolle " .. name)
			end
		end },
		{ name = "Narr-Team existiert (roles.InitCustomTeam)", run = function(e)
			e:Equal(TEAM_NARR, "narrs")
		end },
		{ name = "Hacker hat Traitor-Shop (Regression BUG-01)", run = function(e)
			e:Equal(GetGlobalString("ttt_hck_shop_fallback"), "traitor")
		end },
		{ name = "Rundenstatus lesbar", run = function(e)
			e:True(isnumber(gameloop.GetRoundState()))
		end },
	},
	testLevel = "basic_test",

	limitations = {
		"Hook-Signaturen werden nicht zur Laufzeit geprüft, sondern sind im TTT2-Quellcode 0.14.6b verifiziert (Fundstellen im Dateikopf)",
		"lmnt.round.end liefert das Gewinnerteam nur auf dem Server",
		"Bestehende LMNT-Module nutzen noch die TTT2-Hooks direkt; Umstellung auf die LMNT-Events schrittweise",
	},
})
