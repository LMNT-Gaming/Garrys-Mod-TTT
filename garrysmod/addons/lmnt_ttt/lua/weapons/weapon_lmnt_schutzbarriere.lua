--[[
	Schutzbarriere (Detektiv-Shop)
	Stellt vor dem Detektiv eine kugelsichere Barrikade auf (Entity: lmnt_schutzbarriere):
	300 HP, hält 60 s, Spieler können hindurchgehen. Einmal pro Kauf.
]]

if SERVER then AddCSLuaFile() end

DEFINE_BASECLASS("weapon_tttbase")

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.PrintName = "Schutzbarriere"
	SWEP.Slot = 7
	SWEP.ViewModelFOV = 54
	SWEP.ShowDefaultViewModel = false
	SWEP.Icon = "vgui/ttt/icon_armor"
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "Stellt vor dir eine Barrikade auf, die Kugeln abfängt.\n300 Haltbarkeit, verschwindet nach 60 Sekunden.\nSpieler können hindurchlaufen – sie blockiert nur Schüsse.",
	}
end

SWEP.Kind = WEAPON_EQUIP2
SWEP.CanBuy = { ROLE_DETECTIVE }
SWEP.credits = 1
SWEP.LimitedStock = true
SWEP.AllowDrop = false
SWEP.NoSights = true

SWEP.HoldType = "normal"
SWEP.ViewModel = "models/weapons/v_crowbar.mdl"
SWEP.WorldModel = "models/props_combine/combine_barricade_short01a.mdl"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 1

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local PLACE_DISTANCE = 60

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
	if CLIENT then return end

	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	local yaw = Angle(0, owner:EyeAngles().y, 0)
	local front = owner:GetPos() + yaw:Forward() * PLACE_DISTANCE

	-- Freie Sicht vom Spieler zum Aufstellort (nicht durch Wände hindurch aufstellen)
	local los = util.TraceLine({
		start = owner:GetShootPos(),
		endpos = front + Vector(0, 0, 32),
		filter = owner,
		mask = MASK_SOLID,
	})
	-- Boden unter dem Aufstellort suchen
	local ground = util.TraceLine({
		start = front + Vector(0, 0, 40),
		endpos = front - Vector(0, 0, 80),
		filter = owner,
		mask = MASK_SOLID_BRUSHONLY,
	})
	if los.Hit or not ground.Hit or ground.HitNormal.z < 0.7 then
		owner:EmitSound("HL2Player.UseDeny")
		return
	end

	local barrier = ents.Create("lmnt_schutzbarriere")
	if not IsValid(barrier) then return end
	barrier:SetPos(ground.HitPos)
	barrier:SetAngles(yaw)
	barrier:SetOriginator(owner)
	barrier:Spawn()
	barrier:EmitSound("buttons/combine_button1.wav", 70)

	owner:SetAnimation(PLAYER_ATTACK1)
	self:Remove()
end

function SWEP:SecondaryAttack() end

function SWEP:Reload() return false end

if CLIENT then
	function SWEP:Initialize()
		self:AddTTT2HUDHelp("Barriere vor dir aufstellen")
		return BaseClass.Initialize(self)
	end

	function SWEP:DrawWorldModel()
		if IsValid(self:GetOwner()) then return end
		self:DrawModel()
	end
end
