--[[
	Giftpfeil (Traitor-Shop)
	Lautloser Pfeil: 10 Sofortschaden, danach 6 Schaden pro Sekunde für 10 Sekunden.
	Ein Sanitäter kann das Gift mit der Medigun entfernen.
]]

if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.PrintName = "Giftpfeil"
	SWEP.Slot = 6
	SWEP.ViewModelFOV = 54
	SWEP.Icon = "vgui/ttt/icon_knife"
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "Lautloser Pfeil, der das Ziel langsam vergiftet.\n2 Schuss. Sanitäter können das Gift heilen.",
	}
end

SWEP.Kind = WEAPON_EQUIP1
SWEP.CanBuy = { ROLE_TRAITOR }
SWEP.LimitedStock = true
SWEP.AllowDrop = true
SWEP.IsSilent = true
SWEP.NoSights = true

SWEP.HoldType = "crossbow"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_crossbow.mdl"
SWEP.WorldModel = "models/weapons/w_crossbow.mdl"

SWEP.Primary.ClipSize = 2
SWEP.Primary.DefaultClip = 2
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 1.2

local RANGE = 2000
local INITIAL = 10
local TICK_DAMAGE = 6
local DURATION = 10

local function poison(target, attacker, weapon)
	target:SetNWFloat("lmnt_poison_until", CurTime() + DURATION)

	local name = "LMNT.Poison." .. target:EntIndex()
	timer.Create(name, 1, DURATION, function()
		if not IsValid(target) or not target:Alive() or target:GetNWFloat("lmnt_poison_until", 0) <= CurTime() then
			timer.Remove(name)
			return
		end

		local dmg = DamageInfo()
		dmg:SetDamage(TICK_DAMAGE)
		dmg:SetAttacker(IsValid(attacker) and attacker or game.GetWorld())
		dmg:SetInflictor(IsValid(weapon) and weapon or game.GetWorld())
		dmg:SetDamageType(DMG_GENERIC)
		target:TakeDamageInfo(dmg)
	end)
end

function SWEP:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
	self:TakePrimaryAmmo(1)

	local owner = self:GetOwner()
	self:EmitSound("weapons/crossbow/bolt_fly4.wav", 40, 140)
	self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
	owner:SetAnimation(PLAYER_ATTACK1)

	if CLIENT then return end

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
		local dmg = DamageInfo()
		dmg:SetDamage(INITIAL)
		dmg:SetAttacker(owner)
		dmg:SetInflictor(self)
		dmg:SetDamageType(DMG_GENERIC)
		target:TakeDamageInfo(dmg)

		poison(target, owner, self)
	end
end

function SWEP:SecondaryAttack() end

if SERVER then
	hook.Add("PlayerSpawn", "LMNT.Poison.Reset", function(ply)
		ply:SetNWFloat("lmnt_poison_until", 0)
	end)
end

if CLIENT then
	-- Grüner Schleier, solange man vergiftet ist
	hook.Add("RenderScreenspaceEffects", "LMNT.Poison.Effect", function()
		local lp = LocalPlayer()
		if not IsValid(lp) or lp:GetNWFloat("lmnt_poison_until", 0) <= CurTime() then return end

		local pulse = 0.5 + 0.5 * math.sin(CurTime() * 4)
		DrawColorModify({
			["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0.06 + 0.04 * pulse, ["$pp_colour_addb"] = 0,
			["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 0.7,
			["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0.3, ["$pp_colour_mulb"] = 0,
		})
		DrawMotionBlur(0.3, 0.4, 0.01)
	end)
end
