--[[
	LMNT TTT – Modul "ttt.stats": Einstellungen und Befehle (geteilt)
	Logik: sv_stats.lua, Anzeige: cl_stats.lua
]]

local A = LMNT.Admin
local col = LMNT.Config.Colors

LMNT.Settings.Define("ttt.stats.min_players", {
	type = "int", default = 4, min = 1, max = 64, category = "Statistik & Level", applies = "live",
	desc = "Statistiken, XP und Punkte werden erst ab dieser Spielerzahl vergeben (Schutz gegen Farming)",
})

LMNT.Settings.Define("ttt.stats.vip_multiplier", {
	type = "number", default = 1.5, min = 1, max = 5, category = "Statistik & Level", applies = "live",
	desc = "Multiplikator für XP und Punkte von Spielern mit dem Recht „vip“",
})

A.AddCommand("stats", {
	help = "Zeigt deine oder fremde Statistiken",
	aliases = { "statistik" },
	args = { { type = "player", name = "spieler", optional = true, ignoreImmunity = true, default = function(c) return c end } },
	run = function(caller, target)
		if not IsValid(target) then return end
		LMNT.TTT.SendStats(caller, target)
	end,
})

A.AddCommand("top", {
	help = "Bestenliste (level, kills, wins, points, playtime)",
	aliases = { "rangliste" },
	args = { { type = "string", name = "kategorie", optional = true, default = "level" } },
	run = function(caller, field)
		local rows = LMNT.TTT.GetTop(field, 10)
		LMNT.Reply(caller, col.primary, "Top 10 – " .. field .. ":")
		for i, r in ipairs(rows) do
			LMNT.Reply(caller, col.warn, i .. ". ", color_white, r.name .. "  ", col.muted,
				"Lvl " .. r.level .. " · " .. r.kills .. " Kills · " .. r.wins .. " Siege · " .. r.points .. " Pkt")
		end
	end,
})

A.AddCommand("points", {
	perm = "points",
	help = "Gibt (oder nimmt) Pointshop-Punkte",
	args = {
		{ type = "player", name = "spieler", ignoreImmunity = true },
		{ type = "number", name = "anzahl", min = -100000, max = 100000 },
	},
	run = function(caller, target, amount)
		local s = target.LMNTStats
		if not s then return end

		s.points = math.max(0, s.points + amount)
		target:SetNWInt("lmnt_points", s.points)
		LMNT.TTT.SaveStats(target)
		LMNT.Reply(caller, col.good, target:Nick() .. " hat jetzt " .. s.points .. " Punkte.")
		LMNT.Notify(target, col.good, "Du hast " .. amount .. " Punkte von " .. LMNT.Name(caller) .. " erhalten.")
	end,
})
