--[[
	LMNT Admin – Ränge und Rechte

	level      bestimmt die Immunität: man kann nur Spieler mit niedrigerem Level anvisieren
	inherit    übernimmt alle Rechte des genannten Rangs
	perms      Rechte-Namen (= "perm" der Befehle), "*" = alles
	maxBan     längster erlaubter Bann in Minuten (0 = auch permanent)
	admin / superadmin  steuert ply:IsAdmin() / ply:IsSuperAdmin() für andere Addons (z. B. TTT2)
]]

LMNT.Ranks = {
	user = {
		name = "Spieler", level = 0, color = Color(200, 205, 215),
		perms = {},
	},
	vip = {
		name = "VIP", level = 10, inherit = "user", color = Color(255, 200, 60),
		perms = { "vip" },
	},
	supporter = {
		name = "Supporter", level = 30, inherit = "vip", color = Color(90, 210, 130),
		maxBan = 60,
		perms = { "menu", "asay", "who", "kick", "slay", "slaynr", "mute", "gag", "warn", "freeze", "goto", "bring", "return", "logs", "ban" },
	},
	moderator = {
		name = "Moderator", level = 50, inherit = "supporter", color = Color(60, 160, 255),
		maxBan = 10080, admin = true,
		perms = { "noclip", "hp", "god", "respawn", "announce", "cleardecals", "roundrestart" },
	},
	admin = {
		name = "Admin", level = 80, inherit = "moderator", color = Color(255, 90, 90),
		maxBan = 0, admin = true,
		perms = { "banid", "unban", "setrank", "map", "credits", "karma", "special", "points", "clearwarns",
			"config", "modules", "logs.export", "integrations" },
		-- "dev" (Diagnose, Tests) haben nur Ränge mit "*"
	},
	superadmin = {
		name = "Superadmin", level = 90, inherit = "admin", color = Color(255, 60, 140),
		maxBan = 0, admin = true, superadmin = true,
		perms = { "*" },
	},
	owner = {
		name = "Owner", level = 100, inherit = "superadmin", color = Color(190, 90, 255),
		maxBan = 0, admin = true, superadmin = true,
		perms = { "*" },
	},
}

function LMNT.GetRank(id)
	return LMNT.Ranks[id] or LMNT.Ranks.user
end

function LMNT.RankHasPerm(rankId, perm)
	if not perm then return true end

	local seen = {}
	local id = rankId

	while id and LMNT.Ranks[id] and not seen[id] do
		seen[id] = true
		local rank = LMNT.Ranks[id]

		for _, p in ipairs(rank.perms) do
			if p == "*" or p == perm then return true end
		end

		id = rank.inherit
	end

	return false
end

-- Konsole (NULL) hat immer alle Rechte
function LMNT.HasPerm(ply, perm)
	if not IsValid(ply) then return true end
	return LMNT.RankHasPerm(ply:GetUserGroup(), perm)
end

function LMNT.GetLevel(ply)
	if not IsValid(ply) then return math.huge end
	return LMNT.GetRank(ply:GetUserGroup()).level
end

-- Darf caller target anvisieren? (sich selbst immer, sonst nur niedrigere Ränge)
function LMNT.CanTarget(caller, target)
	if not IsValid(caller) or caller == target then return true end
	return LMNT.GetLevel(caller) > LMNT.GetLevel(target)
end

-- IsAdmin/IsSuperAdmin an LMNT-Ränge koppeln, damit TTT2 und andere Addons sie erkennen
local PLAYER = FindMetaTable("Player")

function PLAYER:IsSuperAdmin()
	local rank = LMNT.Ranks[self:GetUserGroup()]
	if rank then return rank.superadmin == true end
	return self:IsUserGroup("superadmin")
end

function PLAYER:IsAdmin()
	local rank = LMNT.Ranks[self:GetUserGroup()]
	if rank then return rank.admin == true or rank.superadmin == true end
	return self:IsUserGroup("admin") or self:IsSuperAdmin()
end

-- CAMI-Anbindung: siehe Integration "cami" (lua/lmnt/integrations/sh_cami.lua)
