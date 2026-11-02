--[[
	Medigun (Rollenwaffe des Sanitäters)
	Linksklick:  Ziel heilen (Reichweite 120) – entfernt auch Gift
	Rechtsklick: sich selbst heilen (halbe Rate)
	Ladung: 100, lädt sich langsam wieder auf
]]

if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.PrintName = "Medigun"
	SWEP.Slot = 7
	SWEP.ViewModelFOV = 54
	SWEP.DrawCrosshair = true
	SWEP.Icon = "vgui/ttt/icon_health"
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "Linksklick heilt andere, Rechtsklick heilt dich selbst. Entfernt Gift.",
	}
end

SWEP.Kind = WEAPON_EXTRA or WEAPON_EQUIP2
SWEP.CanBuy = nil
SWEP.AllowDrop = false
SWEP.IsSilent = true
SWEP.NoSights = true

SWEP.HoldType = "slam"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_medkit.mdl"
SWEP.WorldModel = "models/weapons/w_medkit.mdl"

SWEP.Primary.ClipSize = 100
SWEP.Primary.DefaultClip = 100
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 0.15

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = true
SWEP.Secondary.Ammo = "none"
SWEP.Secondary.Delay = 0.3

local RANGE = 120
local HEAL_AMOUNT = 2
local COST = 2
local RECHARGE_DELAY = 0.5

local function heal(self, target, amount)
	if target:Health() >= target:GetMaxHealth() and target:GetNWFloat("lmnt_poison_until", 0) <= CurTime() then return false end
	if self:Clip1() < COST then return false end

	self:SetClip1(self:Clip1() - COST)
	target:SetHealth(math.min(target:GetMaxHealth(), target:Health() + amount))

	if target:GetNWFloat("lmnt_poison_until", 0) > CurTime() then
		target:SetNWFloat("lmnt_poison_until", 0)
		target:EmitSound("items/medshot4.wav")
	end

	if (self.NextHealSound or 0) < CurTime() then
		self.NextHealSound = CurTime() + 0.7
		target:EmitSound("items/smallmedkit1.wav", 60, 110)
	end

	return true
end

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
	if CLIENT then return end

	local owner = self:GetOwner()
	owner:LagCompensation(true)
	local tr = util.TraceLine({
		start = owner:GetShootPos(),
		endpos = owner:GetShootPos() + owner:GetAimVector() * RANGE,
		filter = owner,
		mask = MASK_SHOT,
	})
	owner:LagCompensation(false)

	local target = tr.Entity
	if IsValid(target) and target:IsPlayer() and target:Alive() then
		heal(self, target, HEAL_AMOUNT)
	end
end

function SWEP:SecondaryAttack()
	self:SetNextSecondaryFire(CurTime() + self.Secondary.Delay)
	if CLIENT then return end

	heal(self, self:GetOwner(), HEAL_AMOUNT / 2)
end

function SWEP:Think()
	if CLIENT then return end

	if (self.NextRecharge or 0) < CurTime() then
		self.NextRecharge = CurTime() + RECHARGE_DELAY
		if self:Clip1() < self.Primary.ClipSize then
			self:SetClip1(self:Clip1() + 1)
		end
	end
end

function SWEP:Reload() end

if CLIENT then
	function SWEP:DrawHUD()
		local frac = self:Clip1() / self.Primary.ClipSize
		local w, h = 160, 10
		local x, y = ScrW() / 2 - w / 2, ScrH() / 2 + 70

		draw.RoundedBox(4, x, y, w, h, Color(0, 0, 0, 170))
		draw.RoundedBox(4, x + 2, y + 2, (w - 4) * frac, h - 4, Color(70, 200, 160))
		draw.SimpleText("Ladung", "DermaDefault", ScrW() / 2, y + 14, color_white, TEXT_ALIGN_CENTER)
	end
end
