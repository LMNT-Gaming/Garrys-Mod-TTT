--[[
	Rolle: HACKER (Unterrolle der Traitor)
	- Startet mit dem Hacker-Tablet: zeigt allen Traitorn für 6 Sekunden
	  alle Spieler durch Wände (60 s Abklingzeit).
	- Innocents hören beim Hack ein Störgeräusch – sie wissen dann, dass ein Hacker aktiv ist.
	- Hat Zugriff auf den Traitor-Shop und +1 Start-Credit.
]]

if SERVER then
	AddCSLuaFile()
	resource.AddFile("materials/vgui/ttt/dynamic/roles/icon_hck.vmt")
end

function ROLE:PreInitialize()
	self.color = Color(120, 230, 60, 255)
	self.abbr = "hck"

	-- Werte wie beim Traitor (lua/terrortown/entities/roles/traitor/shared.lua)
	self.score.surviveBonusMultiplier = 0.5
	self.score.timelimitMultiplier = -0.5
	self.score.killsMultiplier = 2
	self.score.teamKillsMultiplier = -16
	self.score.bodyFoundMuliplier = 0 -- (sic) so heißt das Feld in TTT2

	self.defaultTeam = TEAM_TRAITOR
	self.defaultEquipment = TRAITOR_EQUIPMENT

	self.conVarData = {
		pct = 0.13,
		maximum = 1,
		minPlayers = 7,
		random = 40,
		traitorButton = 1,
		credits = 3,
		creditsAwardDeadEnable = 1,
		creditsAwardKillEnable = 1,
		-- Shop-Fallback ist der Rollenname, auf dessen Shop zugegriffen wird (GetShopFallback in sh_equip_items.lua)
		shopFallback = "traitor",
	}
end

function ROLE:Initialize()
	roles.SetBaseRole(self, ROLE_TRAITOR)
end

if SERVER then
	function ROLE:GiveRoleLoadout(ply)
		ply:GiveEquipmentWeapon("weapon_lmnt_hacktablet")
	end

	function ROLE:RemoveRoleLoadout(ply)
		ply:StripWeapon("weapon_lmnt_hacktablet")
	end
end
