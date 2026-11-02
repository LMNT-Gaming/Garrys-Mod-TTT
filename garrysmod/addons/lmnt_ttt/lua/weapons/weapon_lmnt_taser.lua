--[[
	Taser (Detektiv-Shop)
	Lähmt das Ziel für 4 Sekunden und lässt es seine aktuelle Waffe fallen.
	Ein Schuss, lädt sich nach 30 Sekunden wieder auf.
]]

if SERVER then
	AddCSLuaFile()
	util.AddNetworkString("lmnt_stun")
end

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.PrintName = "Taser"
	SWEP.Slot = 6
	SWEP.ViewModelFOV = 54
	SWEP.Icon = "vgui/ttt/icon_flare"
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "Lähmt ein Ziel für 4 Sekunden und entwaffnet es.\nLädt sich nach 30 Sekunden wieder auf.",
	}
end

SWEP.Kind = WEAPON_EQUIP1
SWEP.CanBuy = { ROLE_DETECTIVE }
SWEP.LimitedStock = true
SWEP.AllowDrop = true
SWEP.NoSights = true

SWEP.HoldType = "pistol"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_pistol.mdl"
SWEP.WorldModel = "models/weapons/w_pistol.mdl"

SWEP.Primary.ClipSize = 1
SWEP.Primary.DefaultClip = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 1

local RANGE = 450
local STUN_TIME = 4
local RECHARGE = 30

local function stun(target, attacker, weapon)
	target:Freeze(true)
	target.LMNTStunned = true

	local wep = target:GetActiveWeapon()
	if IsValid(wep) and wep.AllowDrop then
		target:DropWeapon(wep)
	end

	local dmg = DamageInfo()
	dmg:SetDamage(1)
	dmg:SetAttacker(attacker)
	dmg:SetInflictor(weapon)
	dmg:SetDamageType(DMG_SHOCK)
	target:TakeDamageInfo(dmg)

	net.Start("lmnt_stun")
	net.WriteFloat(STUN_TIME)
	net.Send(target)

	target:EmitSound("ambient/energy/spark" .. math.random(1, 6) .. ".wav")

	timer.Create("LMNT.Stun." .. target:EntIndex(), STUN_TIME, 1, function()
		if IsValid(target) then
			target:Freeze(false)
			target.LMNTStunned = nil
		end
	end)
end

function SWEP:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
	self:TakePrimaryAmmo(1)

	local owner = self:GetOwner()
	self:EmitSound("weapons/stunstick/stunstick_fleshhit1.wav")
	self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
	owner:SetAnimation(PLAYER_ATTACK1)

	if CLIENT then return end

	self.RechargeAt = CurTime() + RECHARGE

	owner:LagCompensation(true)
	local tr = util.TraceLine({
		start = owner:GetShootPos(),
		endpos = owner:GetShootPos() + owner:GetAimVector() * RANGE,
		filter = owner,
		mask = MASK_SHOT,
	})
	owner:LagCompensation(false)

	local ed = EffectData()
	ed:SetStart(owner:GetShootPos())
	ed:SetOrigin(tr.HitPos)
	ed:SetEntity(self)
	ed:SetAttachment(1)
	util.Effect("ToolTracer", ed)

	local target = tr.Entity
	if IsValid(target) and target:IsPlayer() and target:Alive() then
		stun(target, owner, self)
	end
end

function SWEP:SecondaryAttack() end

function SWEP:Think()
	if SERVER and self.RechargeAt and self.RechargeAt < CurTime() then
		self.RechargeAt = nil
		self:SetClip1(1)
	end
end

if SERVER then
	-- Sicherheitsnetz: Lähmung nie in die nächste Runde/Spawn mitnehmen
	hook.Add("PlayerSpawn", "LMNT.Taser.Reset", function(ply)
		if ply.LMNTStunned then
			ply:Freeze(false)
			ply.LMNTStunned = nil
		end
	end)
end

if CLIENT then
	local stunUntil, stunLength = 0, 1

	net.Receive("lmnt_stun", function()
		stunLength = net.ReadFloat()
		stunUntil = CurTime() + stunLength
	end)

	hook.Add("RenderScreenspaceEffects", "LMNT.Taser.Effect", function()
		if stunUntil < CurTime() then return end

		local frac = (stunUntil - CurTime()) / stunLength
		DrawMotionBlur(0.2, 0.8 * frac, 0.01)
		DrawColorModify({
			["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0.08 * frac,
			["$pp_colour_brightness"] = 0.05 * frac, ["$pp_colour_contrast"] = 1,
			["$pp_colour_colour"] = 1 - 0.7 * frac,
			["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
		})
	end)
end
