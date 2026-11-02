--[[
	LMNT TTT – Einstellungen für Level, Punkte und Spezialrunden
]]

LMNT.TTT.Config = {
	-- XP und Punkte (Punkte = Pointshop-Währung)
	XP = {
		Kill      = 15,   -- Gegner getötet
		TeamKill  = -30,  -- eigenes Team getötet
		Win       = 30,   -- Team hat gewonnen
		Survive   = 10,   -- Runde überlebt
		Played    = 5,    -- Runde mitgespielt
	},
	Points = {
		Kill      = 5,
		TeamKill  = -10,
		Win       = 15,
		Survive   = 5,
		Played    = 2,
		StartBonus = 100, -- Startguthaben für neue Spieler
	},
	-- XP, die man für das Erreichen von Level n+1 braucht
	XPForLevel = function(level)
		return math.floor(100 * level ^ 1.35)
	end,

	-- Ingame änderbare Werte sind LMNT.Settings (seit 1.1.0):
	--   ttt.special.chance / ttt.special.min_players / ttt.special.min_gap  (sh_specialrounds.lua)
	--   ttt.stats.min_players / ttt.stats.vip_multiplier                   (sh_stats.lua)
}
