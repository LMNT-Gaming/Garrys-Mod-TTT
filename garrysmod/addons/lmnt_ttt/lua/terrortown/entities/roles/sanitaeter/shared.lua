--[[
	Rolle: SANITÄTER (Unterrolle der Innocents)
	- Startet mit der Medigun (heilt andere, heilt Gift).
	- Sieht über den Köpfen anderer Spieler deren Gesundheitszustand.
]]

if SERVER then
	AddCSLuaFile()
	resource.AddFile("materials/vgui/ttt/dynamic/roles/icon_san.vmt")
end

function ROLE:PreInitialize()
	self.color = Color(70, 200, 160, 255)
	self.abbr = "san"

	-- Werte wie beim Innocent (lua/terrortown/entities/roles/innocent/shared.lua)
	self.score.killsMultiplier = 2
	self.score.teamKillsMultiplier = -8
	self.unknownTeam = true

	self.defaultTeam = TEAM_INNOCENT
	self.defaultEquipment = INNO_EQUIPMENT

	self.conVarData = {
		pct = 0.13,
		maximum = 1,
		minPlayers = 5,
		random = 50,
	}
end

function ROLE:Initialize()
	roles.SetBaseRole(self, ROLE_INNOCENT)
end

if SERVER then
	function ROLE:GiveRoleLoadout(ply)
		ply:GiveEquipmentWeapon("weapon_lmnt_medigun")
	end

	function ROLE:RemoveRoleLoadout(ply)
		ply:StripWeapon("weapon_lmnt_medigun")
	end
end

if CLIENT then
	-- Gesundheitsanzeige über Spielern, die der Sanitäter ansieht
	hook.Add("HUDPaint", "LMNT.Sanitaeter.Health", function()
		local lp = LocalPlayer()
		if not IsValid(lp) or not lp:Alive() or lp:GetSubRole() ~= ROLE_SANITAETER then return end

		local tr = lp:GetEyeTrace()
		local target = tr.Entity
		if not IsValid(target) or not target:IsPlayer() or not target:Alive() then return end
		if tr.HitPos:DistToSqr(lp:GetShootPos()) > 600 * 600 then return end

		local frac = math.Clamp(target:Health() / target:GetMaxHealth(), 0, 1)
		local x, y = ScrW() / 2 - 60, ScrH() / 2 + 40

		draw.RoundedBox(4, x, y, 120, 12, Color(0, 0, 0, 180))
		draw.RoundedBox(4, x + 2, y + 2, 116 * frac, 8, Color(255 * (1 - frac), 220 * frac, 60))

		if target:GetNWFloat("lmnt_poison_until", 0) > CurTime() then
			draw.SimpleText("VERGIFTET", "DermaDefaultBold", ScrW() / 2, y + 26, Color(120, 255, 80), TEXT_ALIGN_CENTER)
		end
	end)
end
