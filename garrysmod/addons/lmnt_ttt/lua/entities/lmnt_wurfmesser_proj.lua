--[[
	Geworfenes Wurfmesser (Projektil zu weapon_lmnt_wurfmesser)
	Vorbild: ttt_knife_proj (TTT2) – Trefferprüfung per Trace in Think und PhysicsCollide.
	Trifft genau einen Spieler: 34 Schaden, Kopftreffer x1,5 (51). Kein Sofort-Kill.
	Bleibt danach als Beweisstück liegen bzw. in der Wand stecken und verschwindet nach 20 s.
]]

if SERVER then AddCSLuaFile() end

if CLIENT then
	ENT.PrintName = "Wurfmesser"
	ENT.Icon = "vgui/ttt/icon_knife"
end

ENT.Type = "anim"
ENT.Model = Model("models/weapons/w_knife_ct.mdl")

ENT.Projectile = true      -- Punkte-/Kill-Auswertung behandelt uns wie eine Waffe (wie ttt_knife_proj)
ENT.CanHavePrints = false
ENT.IsSilent = true
ENT.CanPickup = false

ENT.Damage = 34
ENT.HeadshotMultiplier = 1.5

local LIFETIME = 20
local soundHitWall = Sound("weapons/knife/knife_hitwall1.wav")
local soundHitFlesh = Sound("weapons/knife/knife_hit1.wav")

function ENT:Initialize()
	self:SetModel(self.Model)
	self:PhysicsInit(SOLID_VPHYSICS)

	if SERVER then
		self:SetGravity(0.4)
		self:SetFriction(1.0)
		self:SetElasticity(0.3)
		self.removeAt = CurTime() + LIFETIME
		self:NextThink(CurTime())
	end
end

if SERVER then
	function ENT:Spent()
		self.spent = true
		self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	end

	function ENT:HitPlayer(ply, hitgroup)
		if self.spent then return end
		self:Spent()

		local damage = self.Damage
		if hitgroup == HITGROUP_HEAD then damage = damage * self.HeadshotMultiplier end

		local owner = self:GetOwner()
		local dmg = DamageInfo()
		dmg:SetDamage(damage)
		dmg:SetAttacker(IsValid(owner) and owner or self)
		dmg:SetInflictor(self)
		dmg:SetDamageType(DMG_SLASH)
		dmg:SetDamagePosition(self:GetPos())
		dmg:SetDamageForce(self:GetVelocity():GetNormalized() * 200)
		ply:TakeDamageInfo(dmg)

		sound.Play(soundHitFlesh, self:GetPos(), 60)

		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:SetVelocity(phys:GetVelocity() * 0.1) end
	end

	function ENT:Think()
		if CurTime() >= self.removeAt then
			self:Remove()
			return
		end

		if not self.spent then
			local vel = self:GetVelocity()
			if vel:LengthSqr() > 100 then
				local tr = util.TraceLine({
					start = self:GetPos(),
					endpos = self:GetPos() + vel:GetNormalized() * 24,
					filter = { self, self:GetOwner() },
					mask = MASK_SHOT_HULL,
				})
				if tr.Hit and IsValid(tr.Entity) and tr.Entity:IsPlayer() then
					self:HitPlayer(tr.Entity, tr.HitGroup)
				end
			end
		end

		self:NextThink(CurTime())
		return true
	end

	function ENT:PhysicsCollide(data, phys)
		if self.spent then return end
		local other = data.HitEntity

		if IsValid(other) and other:IsPlayer() then
			if other == self:GetOwner() then return end
			local tr = util.TraceLine({
				start = self:GetPos(),
				endpos = other:WorldSpaceCenter(),
				filter = { self, self:GetOwner() },
				mask = MASK_SHOT_HULL,
			})
			self:HitPlayer(other, tr.Entity == other and tr.HitGroup or HITGROUP_GENERIC)
			return
		end

		-- Wand oder Gegenstand: stecken bleiben (einen Tick verzögert, Physik-Callbacks vertragen keine Änderungen)
		self:Spent()
		sound.Play(soundHitWall, self:GetPos(), 60)
		if data.HitEntity and data.HitEntity:IsWorld() then
			local knife = self
			timer.Simple(0, function()
				if not IsValid(knife) then return end
				local p = knife:GetPhysicsObject()
				if IsValid(p) then p:EnableMotion(false) end
			end)
		end
	end

	-- Aufräumen am Rundenende
	local function cleanup()
		for _, ent in ipairs(ents.FindByClass("lmnt_wurfmesser_proj")) do ent:Remove() end
	end
	hook.Add("TTTPrepareRound", "LMNT.Wurfmesser.Cleanup", cleanup)
end
