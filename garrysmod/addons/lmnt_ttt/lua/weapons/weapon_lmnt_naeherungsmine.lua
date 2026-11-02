--[[
	Näherungsmine (Traitor-Shop)
	Wird auf den Boden gelegt, ist nach 3 Sekunden scharf und explodiert 0,9 Sekunden nach einem
	Warnton, wenn ein aufrecht gehender Spieler in die Nähe kommt (Entity: lmnt_naeherungsmine).
	Geduckt schleichen löst sie nicht aus; geduckt mit E oder mit dem Entschärfer entschärfbar.
]]

if SERVER then AddCSLuaFile() end

DEFINE_BASECLASS("weapon_tttbase")

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.PrintName = "Näherungsmine"
	SWEP.Slot = 6
	SWEP.ViewModelFOV = 54
	SWEP.Icon = "vgui/ttt/icon_splode"
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "Auf den Boden legen, nach 3 s scharf.\nExplodiert kurz nach einem Warnton, wenn jemand aufrecht vorbeigeht.\nGeduckt schleichen löst sie nicht aus – Gegner können sie geduckt entschärfen oder zerschießen.",
	}
end

SWEP.Kind = WEAPON_EQUIP1
SWEP.CanBuy = { ROLE_TRAITOR }
SWEP.credits = 1
SWEP.LimitedStock = true
SWEP.AllowDrop = false
SWEP.IsSilent = true
SWEP.NoSights = true

SWEP.HoldType = "slam"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/props_combine/combine_mine01.mdl"

SWEP.Primary.ClipSize = 1
SWEP.Primary.DefaultClip = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 1

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local PLACE_RANGE = 100

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
	if CLIENT or not self:CanPrimaryAttack() then return end

	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	-- Nur auf (annähernd) waagerechten Böden, damit die Mine nicht an Wänden oder Decken klebt
	local tr = util.TraceLine({
		start = owner:GetShootPos(),
		endpos = owner:GetShootPos() + owner:GetAimVector() * PLACE_RANGE,
		filter = owner,
		mask = MASK_NPCWORLDSTATIC,
	})
	if not tr.Hit or tr.HitNormal.z < 0.7 then
		owner:EmitSound("HL2Player.UseDeny")
		return
	end

	local mine = ents.Create("lmnt_naeherungsmine")
	if not IsValid(mine) then return end

	if mine:StickEntity(owner, Angle(90, 0, 0)) then
		mine.fingerprints = self.fingerprints
		self:TakePrimaryAmmo(1)
		self:Remove()
	else
		mine:Remove()
	end
end

function SWEP:SecondaryAttack() end

function SWEP:Reload() return false end

if CLIENT then
	function SWEP:Initialize()
		self:AddTTT2HUDHelp("Mine auf den Boden legen")
		return BaseClass.Initialize(self)
	end
end
