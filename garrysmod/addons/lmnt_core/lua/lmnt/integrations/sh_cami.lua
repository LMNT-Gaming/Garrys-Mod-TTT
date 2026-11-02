--[[
	Integration "cami": CAMI (Common Admin Mod Interface)
	Adapter: meldet LMNT-Ränge und -Rechte bei CAMI an und beantwortet CAMI-Rechteabfragen anderer Addons
	über das LMNT-Rechtesystem. Nur aktiv, wenn ein Addon CAMI mitbringt (TTT2 selbst tut das nicht).
]]

local registeredGroups, registeredPrivs = {}, {}

-- Niedrigster Rang mit diesem Recht bestimmt die CAMI-MinAccess-Stufe
local function minAccessFor(perm)
	local best
	for id, rank in pairs(LMNT.Ranks) do
		if LMNT.RankHasPerm(id, perm) and (not best or rank.level < LMNT.Ranks[best].level) then best = id end
	end
	local r = best and LMNT.Ranks[best]
	if not r then return "superadmin" end
	return r.superadmin and "superadmin" or (r.admin and "admin" or "user")
end

LMNT.Integrations.Register("cami", {
	name = "CAMI",
	description = "Gemeinsame Admin-Mod-Schnittstelle: andere Addons fragen Rechte über CAMI ab",
	version = "1.0.0",
	vendor = "Community-Standard (glua/CAMI)",
	lmnt = "1.2.0",

	detect = function()
		local evidence = {}
		if istable(CAMI) then evidence[#evidence + 1] = "Global CAMI-Tabelle" end
		if istable(CAMI) and isfunction(CAMI.RegisterUsergroup) then evidence[#evidence + 1] = "CAMI.RegisterUsergroup vorhanden" end
		if istable(CAMI) and isfunction(CAMI.PlayerHasAccess) then evidence[#evidence + 1] = "CAMI.PlayerHasAccess vorhanden" end
		return istable(CAMI), evidence, istable(CAMI) and CAMI.Version and tostring(CAMI.Version) or nil
	end,

	validate = function()
		return {
			{ name = "CAMI.RegisterUsergroup", ok = isfunction(CAMI.RegisterUsergroup) },
			{ name = "CAMI.RegisterPrivilege", ok = isfunction(CAMI.RegisterPrivilege) },
			{ name = "CAMI.UnregisterUsergroup", ok = isfunction(CAMI.UnregisterUsergroup), optional = true },
			{ name = "CAMI.UnregisterPrivilege", ok = isfunction(CAMI.UnregisterPrivilege), optional = true },
			{ name = "CAMI.GetPrivilege", ok = isfunction(CAMI.GetPrivilege), optional = true },
		}
	end,

	init = function()
		registeredGroups, registeredPrivs = {}, {}

		for id, rank in pairs(LMNT.Ranks) do
			if id ~= "user" and id ~= "admin" and id ~= "superadmin" then
				CAMI.RegisterUsergroup({ Name = id, Inherits = rank.superadmin and "superadmin" or (rank.admin and "admin" or "user") }, "LMNT")
				registeredGroups[#registeredGroups + 1] = id
			end
		end

		local perms = {}
		for _, cmd in pairs(LMNT.Admin.Commands) do
			if cmd.perm then perms[cmd.perm] = true end
		end
		for perm in pairs(perms) do
			CAMI.RegisterPrivilege({ Name = "lmnt." .. perm, MinAccess = minAccessFor(perm), Description = "LMNT-Recht " .. perm })
			registeredPrivs[#registeredPrivs + 1] = "lmnt." .. perm
		end

		-- Rechteabfragen anderer Addons über CAMI beantworten (LMNT ist das führende Rechtesystem, ADR-002)
		hook.Add("CAMI.PlayerHasAccess", "LMNT.CAMI.Access", function(actor, privilege, callback)
			if not isfunction(callback) then return end
			if string.StartWith(privilege, "lmnt.") then
				callback(LMNT.HasPerm(actor, string.sub(privilege, 6)), "LMNT")
				return true
			end
			local priv = isfunction(CAMI.GetPrivilege) and CAMI.GetPrivilege(privilege)
			if priv and priv.MinAccess and IsValid(actor) then
				local has = priv.MinAccess == "user" or (priv.MinAccess == "admin" and actor:IsAdmin()) or actor:IsSuperAdmin()
				callback(has, "LMNT (MinAccess " .. priv.MinAccess .. ")")
				return true
			end
		end)
	end,

	shutdown = function()
		if isfunction(CAMI.UnregisterUsergroup) then
			for _, g in ipairs(registeredGroups) do CAMI.UnregisterUsergroup(g, "LMNT") end
		end
		if isfunction(CAMI.UnregisterPrivilege) then
			for _, p in ipairs(registeredPrivs) do CAMI.UnregisterPrivilege(p) end
		end
	end,

	limitations = {
		"Auf diesem Server ungetestet, solange kein Addon CAMI mitbringt",
		"Signatur des Hooks CAMI.PlayerHasAccess nach CAMI-Spezifikation; Prüfung mit einem CAMI-Addon steht aus",
	},
})
