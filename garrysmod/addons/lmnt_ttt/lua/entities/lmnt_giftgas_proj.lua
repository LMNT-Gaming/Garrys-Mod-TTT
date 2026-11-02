--[[
	Giftgas-Wolke (Projektil zu weapon_lmnt_giftgas)
	Basis: ttt_basegrenade_proj (TTT2). Nach der Zündung bleibt das Projektil unsichtbar als
	Wolkenzentrum liegen und verursacht 12 s lang 5 Schaden pro Sekunde an allen Spielern im Radius
	mit freier Sichtlinie zum Zentrum (keine Wirkung durch Wände). Wer hinausläuft, nimmt keinen Schaden mehr.

	Schaden nur serverseitig, Angreifer = Werfer (Karma, Schadenslog), Inflictor = diese Wolke.
	Trifft alle gleich – auch den Werfer und andere Traitor (kein Rollen-Leck).
]]

if SERVER then AddCSLuaFile() end

DEFINE_BASECLASS("ttt_basegrenade_proj")

ENT.Type = "anim"
ENT.Base = "ttt_basegrenade_proj"
ENT.PrintName = "Giftgas"
ENT.Model = Model("models/weapons/w_eq_smokegrenade_thrown.mdl")

local RADIUS = 190
local DURATION = 12
local TICK = 1
local TICK_DAMAGE = 5

local soundHiss = Sound("ambient/gas/steam2.wav")
local soundCough = Sound("ambient/voices/cough1.wav")

function ENT:Explode(tr)
	-- Nur einmal zünden: die Basis ruft Explode, solange ExplodeTime in der Vergangenheit liegt
	self:SetDetonateExact(0)

	local center = self:GetPos()
	if tr.Fraction ~= 1.0 then center = tr.HitPos + tr.HitNormal * 0.6 end

	if SERVER then
		self:SetNoDraw(true)
		self:SetSolid(SOLID_NONE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		self:SetPos(center)

		self.cloudCenter = center + Vector(0, 0, 24)
		self.cloudEnd = CurTime() + DURATION
		self.nextTick = CurTime()
		self:EmitSound(soundHiss, 75, 90)
	else
		-- Partikel können am Rundenende nicht aufgeräumt werden, also in der Nachrunde keine erzeugen
		if gameloop.GetRoundState() == ROUND_POST then return end
		self:CreateGas(center)
	end
end

if SERVER then
	function ENT:GasTick()
		local thrower = self:GetThrower()
		local center = self.cloudCenter

		for _, ply in ipairs(player.GetAll()) do
			if ply:IsTerror() and ply:Alive() and ply:WorldSpaceCenter():DistToSqr(center) <= RADIUS * RADIUS then
				local tr = util.TraceLine({
					start = center,
					endpos = ply:WorldSpaceCenter(),
					filter = { self, ply },
					mask = MASK_SOLID_BRUSHONLY,
				})
				if not tr.Hit then
					local dmg = DamageInfo()
					dmg:SetDamage(TICK_DAMAGE)
					dmg:SetAttacker(IsValid(thrower) and thrower or self)
					dmg:SetInflictor(self)
					dmg:SetDamageType(DMG_NERVEGAS)
					dmg:SetDamagePosition(center)
					ply:TakeDamageInfo(dmg)

					if math.random() < 0.35 then ply:EmitSound(soundCough, 70, math.random(95, 110)) end
				end
			end
		end
	end

	function ENT:Think()
		if not self.cloudEnd then
			return BaseClass.Think(self)
		end

		local now = CurTime()
		if now >= self.cloudEnd then
			self:StopSound(soundHiss)
			self:Remove()
			return
		end

		if now >= self.nextTick then
			self.nextTick = now + TICK
			self:GasTick()
		end

		self:NextThink(now + 0.1)
		return true
	end

	function ENT:OnRemove()
		self:StopSound(soundHiss)
	end
end

if CLIENT then
	local gasParticles = {
		Model("particle/particle_smokegrenade"),
		Model("particle/particle_noisesphere"),
	}

	-- Grünliche Wolke in etwa der Größe des Schadensradius, löst sich nach DURATION auf
	function ENT:CreateGas(center)
		local em = ParticleEmitter(center)
		if not em then return end

		for _ = 1, 26 do
			local offset = VectorRand() * RADIUS * 0.45
			offset.z = math.abs(offset.z) * 0.5 + 16
			local p = em:Add(gasParticles[math.random(#gasParticles)], center + offset)
			if p then
				local g = math.random(120, 170)
				p:SetColor(math.floor(g * 0.55), g, math.floor(g * 0.25))
				p:SetStartAlpha(170)
				p:SetEndAlpha(0)
				p:SetVelocity(VectorRand() * math.Rand(40, 90))
				p:SetLifeTime(0)
				p:SetDieTime(DURATION + math.Rand(-1, 1))
				p:SetStartSize(math.random(90, 120))
				p:SetEndSize(math.random(110, 140))
				p:SetRoll(math.random(-180, 180))
				p:SetRollDelta(math.Rand(-0.2, 0.2))
				p:SetAirResistance(120)
				p:SetCollide(true)
				p:SetBounce(0.2)
				p:SetLighting(false)
			end
		end

		em:Finish()
	end
end

-- Aufräumen: Wolken enden mit der Runde (kein Schaden in der Nachrunde oder der nächsten Runde)
if SERVER then
	local function cleanup()
		for _, ent in ipairs(ents.FindByClass("lmnt_giftgas_proj")) do ent:Remove() end
	end
	hook.Add("TTTEndRound", "LMNT.Giftgas.Cleanup", cleanup)
	hook.Add("TTTPrepareRound", "LMNT.Giftgas.Cleanup", cleanup)
end
