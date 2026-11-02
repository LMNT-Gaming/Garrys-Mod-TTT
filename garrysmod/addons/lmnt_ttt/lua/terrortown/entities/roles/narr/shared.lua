--[[
	Rolle: NARR (eigenes Team)
	- Kann keinen Schaden austeilen.
	- Gewinnt allein, wenn ihn ein anderer Spieler tötet.
	- Traitor sehen, wer der Narr ist – Innocents nicht.
]]

if SERVER then
	AddCSLuaFile()
	resource.AddFile("materials/vgui/ttt/dynamic/roles/icon_nar.vmt")
end

roles.InitCustomTeam(ROLE.name, {
	icon = "vgui/ttt/dynamic/roles/icon_nar",
	color = Color(245, 105, 190, 255),
})

function ROLE:PreInitialize()
	self.color = Color(245, 105, 190, 255)
	self.abbr = "nar"

	-- Alle Felder sind in ttt_role_base (TTT2 0.14.6b) definiert
	self.preventFindCredits = true
	self.preventWin = true            -- zählt nicht für den normalen Teamsieg, eigener Sieg unten
	self.unknownTeam = true
	self.visibleForTeam = { TEAM_TRAITOR }

	self.score.killsMultiplier = 0
	self.score.teamKillsMultiplier = 0
	self.score.suicideMultiplier = -2

	self.defaultTeam = TEAM_NARR
	self.defaultEquipment = INNO_EQUIPMENT

	self.conVarData = {
		pct = 0.15,
		maximum = 1,
		minPlayers = 6,
		random = 40, -- Chance in %, dass die Rolle überhaupt vergeben wird
	}
end

if not SERVER then return end

local narrWins = false

local function isNarr(ply)
	return IsValid(ply) and ply:IsPlayer() and ply:GetSubRole() == ROLE_NARR
end

-- Der Narr kann niemandem schaden
hook.Add("EntityTakeDamage", "LMNT.Narr.NoDamage", function(target, dmg)
	local attacker = dmg:GetAttacker()
	if isNarr(attacker) and target ~= attacker then return true end
end)

-- Von einem anderen Spieler getötet -> Narr gewinnt
hook.Add("PlayerDeath", "LMNT.Narr.Death", function(victim, _, attacker)
	if GetRoundState() ~= ROUND_ACTIVE or not isNarr(victim) then return end
	if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end

	narrWins = true

	if LMNT and LMNT.Announce then
		LMNT.Announce(attacker:Nick() .. " ist dem Narren " .. victim:Nick() .. " auf den Leim gegangen!", Color(245, 105, 190), 6)
	end

	BroadcastLua("surface.PlaySound('lmnt/narr_win.wav')")
end)

-- TTT2PreWinChecker ist laut TTT2 (sv_main.lua) der vorgesehene Hook für eigene Siegbedingungen
hook.Add("TTT2PreWinChecker", "LMNT.Narr.Win", function()
	if narrWins then
		narrWins = false
		return TEAM_NARR
	end
end)

hook.Add("TTTPrepareRound", "LMNT.Narr.Reset", function()
	narrWins = false
end)
