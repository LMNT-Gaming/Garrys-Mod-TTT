--[[
	Wurfmesser (Traitor-Shop)
	Drei lautlose Wurfmesser (Entity: lmnt_wurfmesser_proj). 34 Schaden, Kopftreffer 51,
	leichter Bogenflug. Anders als das TTT-Messer kein Sofort-Kill – dafür auf Distanz und dreimal.
]]

if SERVER then AddCSLuaFile() end

DEFINE_BASECLASS("weapon_tttbase")

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.PrintName = "Wurfmesser"
	SWEP.Slot = 6
	SWEP.ViewModelFOV = 54
	SWEP.Icon = "vgui/ttt/icon_knife"
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "3 lautlose Wurfmesser.\n34 Schaden, Kopftreffer 51.\nDie Messer bleiben als Spur liegen.",
	}
end

SWEP.Kind = WEAPON_EQUIP1
SWEP.CanBuy = { ROLE_TRAITOR }
SWEP.credits = 1
SWEP.LimitedStock = true
SWEP.AllowDrop = true
SWEP.IsSilent = true
SWEP.NoSights = true
SWEP.DeploySpeed = 1.5

SWEP.HoldType = "knife"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/cstrike/c_knife_t.mdl"
SWEP.WorldModel = "models/weapons/w_knife_ct.mdl"

SWEP.Primary.ClipSize = 3
SWEP.Primary.DefaultClip = 3
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 0.8

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local THROW_SPEED = 1100

function SWEP:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)

	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	self:SendWeaponAnim(ACT_VM_MISSCENTER)
	owner:SetAnimation(PLAYER_ATTACK1)
	self:EmitSound("weapons/iceaxe/iceaxe_swing1.wav", 45, 130)

	if CLIENT then return end

	self:TakePrimaryAmmo(1)

	local ang = owner:EyeAngles()
	local src = owner:GetShootPos() + ang:Forward() * 8 + ang:Right() * 4 - ang:Up() * 2

	local knifeAng = Angle(ang.p, ang.y, ang.r)
	knifeAng:RotateAroundAxis(knifeAng:Right(), -90)

	local knife = ents.Create("lmnt_wurfmesser_proj")
	if not IsValid(knife) then return end
	knife:SetPos(src)
	knife:SetAngles(knifeAng)
	knife:SetOwner(owner)
	knife:Spawn()

	local phys = knife:GetPhysicsObject()
	if IsValid(phys) then
		phys:SetVelocity(owner:GetAimVector() * THROW_SPEED + owner:GetVelocity())
		phys:AddAngleVelocity(Vector(0, 1500, 0))
		phys:Wake()
	end

	if self:Clip1() <= 0 then self:Remove() end
end

function SWEP:SecondaryAttack() end

function SWEP:Reload() return false end

if SERVER then
	function SWEP:PreDrop()
		-- Wie beim TTT-Messer: fallengelassene Wurfmesser tragen keine DNA
		self.fingerprints = {}
	end
end

if CLIENT then
	function SWEP:Initialize()
		self:AddTTT2HUDHelp("Messer werfen")
		return BaseClass.Initialize(self)
	end
end
