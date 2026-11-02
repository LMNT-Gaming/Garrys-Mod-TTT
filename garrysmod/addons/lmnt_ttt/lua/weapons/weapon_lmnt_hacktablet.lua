--[[
	Hacker-Tablet (Rollenwaffe des Hackers)
	Linksklick: Alle Spieler werden für dein Team 6 Sekunden durch Wände sichtbar.
	            Alle anderen hören ein Störgeräusch. Abklingzeit: 60 Sekunden.
]]

if SERVER then
	AddCSLuaFile()
	util.AddNetworkString("lmnt_hack_pulse")
end

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.PrintName = "Hacker-Tablet"
	SWEP.Slot = 7
	SWEP.ViewModelFOV = 60
	SWEP.Icon = "vgui/ttt/icon_radar"
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "Zeigt deinem Team kurz alle Spieler durch Wände.",
	}
end

SWEP.Kind = WEAPON_EXTRA or WEAPON_EQUIP2
SWEP.CanBuy = nil
SWEP.AllowDrop = false
SWEP.NoSights = true

SWEP.HoldType = "slam"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/weapons/w_slam.mdl"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 60

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local DURATION = 6

function SWEP:PrimaryAttack()
	if self:GetNextPrimaryFire() > CurTime() then return end
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

	if CLIENT then return end

	local owner = self:GetOwner()
	local team = owner:GetTeam()
	local mates, others = {}, {}

	for _, ply in ipairs(player.GetAll()) do
		if ply:GetTeam() == team then mates[#mates + 1] = ply else others[#others + 1] = ply end
	end

	net.Start("lmnt_hack_pulse")
	net.WriteFloat(DURATION)
	net.Send(mates)

	for _, ply in ipairs(others) do
		ply:EmitSound("ambient/energy/zap" .. math.random(1, 3) .. ".wav", 50, 80)
		ply:PrintMessage(HUD_PRINTCENTER, "Störsignal empfangen … irgendwer hackt das Netz!")
	end

	owner:EmitSound("buttons/combine_button7.wav")
end

function SWEP:SecondaryAttack() end
function SWEP:Reload() end

if CLIENT then
	local pulseUntil = 0

	net.Receive("lmnt_hack_pulse", function()
		pulseUntil = CurTime() + net.ReadFloat()
		surface.PlaySound("buttons/combine_button1.wav")
	end)

	hook.Add("PreDrawHalos", "LMNT.Hacker.Pulse", function()
		if pulseUntil < CurTime() then return end

		local lp = LocalPlayer()
		local targets = {}
		for _, ply in ipairs(player.GetAll()) do
			if ply ~= lp and ply:Alive() and not ply:IsSpec() then targets[#targets + 1] = ply end
		end

		halo.Add(targets, Color(120, 230, 60), 2, 2, 2, true, true)
	end)

	function SWEP:DrawHUD()
		local left = self:GetNextPrimaryFire() - CurTime()
		local text = left > 0 and ("Bereit in " .. math.ceil(left) .. " s") or "BEREIT – Linksklick zum Hacken"
		draw.SimpleText(text, "DermaDefaultBold", ScrW() / 2, ScrH() / 2 + 60, left > 0 and Color(200, 200, 200) or Color(120, 230, 60), TEXT_ALIGN_CENTER)
	end
end
