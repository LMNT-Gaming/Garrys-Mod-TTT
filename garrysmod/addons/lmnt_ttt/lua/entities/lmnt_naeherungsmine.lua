--[[
	Näherungsmine (Entity zu weapon_lmnt_naeherungsmine)
	Basis: ttt_base_placeable (TTT2) – Anbringen, Schaden nehmen, Zerstören.

	Ablauf: 3 s Scharfschaltzeit -> scharf (rotes Blinklicht, für alle sichtbar)
	        -> aufrecht gehender Spieler im Radius mit Sichtlinie -> Warnton -> 0,9 s -> Explosion.
	Gegenspiel: geduckt schleichen löst nicht aus, geduckt mit E entschärfen, Detektiv-Entschärfer,
	            zerschießen (40 HP, die Mine verpufft dann ohne Explosion), DNA-Spuren des Legers.

	Informationsschutz (11.6): Die Mine löst für ALLE aus (auch für Traitor und den Leger),
	sonst würde ein Spieler, der unbeschadet darüber läuft, als Traitor erkennbar.
	Der Leger wird NICHT an die Clients übertragen (eigenes Originator-Feld nur auf dem Server).
]]

if SERVER then AddCSLuaFile() end

DEFINE_BASECLASS("ttt_base_placeable")

ENT.Type = "anim"
ENT.Base = "ttt_base_placeable"
ENT.PrintName = "Näherungsmine"
ENT.Model = Model("models/props_combine/combine_mine01.mdl")

ENT.CanHavePrints = true      -- DNA-Spuren wie beim C4 (Gegenspiel für Detektive)
ENT.isDestructible = true
ENT.Defusable = true          -- weapon_ttt_defuser prüft Defusable und ruft Disarm(ply) auf

local ARM_TIME = 3            -- Sekunden bis scharf
local TRIGGER_RADIUS = 110    -- Auslöseradius
local FUSE = 0.9              -- Warnton bis Explosion
local BLAST_RADIUS = 260
local BLAST_DAMAGE = 125      -- im Zentrum tödlich, fällt zum Rand hin linear ab
local HEALTH = 40

local soundArm = Sound("npc/roller/mine/combine_mine_deploy1.wav")
local soundWarn = Sound("npc/roller/mine/rmine_blip3.wav")
local soundDisarm = Sound("weapons/c4/c4_disarm.wav")

-- Bewusst KEIN BaseClass.SetupDataTables: die Basis würde den Leger (Originator) an alle Clients senden
function ENT:SetupDataTables()
	self:NetworkVar("Bool", 0, "Armed")
	self:NetworkVar("Float", 0, "TriggerTime")
end

if SERVER then
	-- Ersatz für das vernetzte Originator-Feld der Basis (StickEntity und OnTakeDamage nutzen diese beiden)
	function ENT:SetOriginator(ply) self.lmntOriginator = ply end
	function ENT:GetOriginator() return self.lmntOriginator end
end

function ENT:Initialize()
	self:SetModel(self.Model)
	BaseClass.Initialize(self)

	if SERVER then
		self:SetMaxHealth(HEALTH)
		self:SetUseType(SIMPLE_USE)
		self.armAt = CurTime() + ARM_TIME
		self:SetArmed(false)
		self:SetTriggerTime(0)
	end
	self:SetHealth(HEALTH)
end

if SERVER then
	local function canTrigger(self, ply, pos)
		if not ply:IsTerror() or not ply:Alive() or ply:Crouching() then return false end
		if ply:GetPos():DistToSqr(pos) > TRIGGER_RADIUS * TRIGGER_RADIUS then return false end

		-- Keine Auslösung durch Wände oder Böden
		local tr = util.TraceLine({
			start = pos + Vector(0, 0, 8),
			endpos = ply:WorldSpaceCenter(),
			filter = { self, ply },
			mask = MASK_SOLID_BRUSHONLY,
		})
		return not tr.Hit
	end

	function ENT:Think()
		local now = CurTime()

		if self:GetTriggerTime() > 0 then
			if now >= self:GetTriggerTime() then self:Detonate() return end
			self:NextThink(now)
			return true
		end

		if not self:GetArmed() then
			if now >= self.armAt then
				self:SetArmed(true)
				self:EmitSound(soundArm, 60)
			end
			self:NextThink(now + 0.2)
			return true
		end

		local pos = self:GetPos()
		for _, ply in ipairs(player.GetAll()) do
			if canTrigger(self, ply, pos) then
				self:SetTriggerTime(now + FUSE)
				self:EmitSound(soundWarn, 85, 110)
				break
			end
		end

		self:NextThink(now + 0.1)
		return true
	end

	function ENT:Detonate()
		if self.exploded then return end
		self.exploded = true

		local pos = self:GetPos()
		local attacker = self:GetOriginator()

		local ed = EffectData()
		ed:SetOrigin(pos)
		ed:SetScale(1)
		ed:SetRadius(BLAST_RADIUS)
		ed:SetMagnitude(BLAST_DAMAGE)
		util.Effect("Explosion", ed, true, true)

		-- Schaden serverseitig mit Leger als Angreifer (Karma, Schadenslog) und der Mine als Inflictor
		local dmg = DamageInfo()
		dmg:SetDamage(BLAST_DAMAGE)
		dmg:SetAttacker(IsValid(attacker) and attacker or self)
		dmg:SetInflictor(self)
		dmg:SetDamageType(DMG_BLAST)
		dmg:SetDamagePosition(pos)

		self:SetSolid(SOLID_NONE)
		util.BlastDamageInfo(dmg, pos, BLAST_RADIUS)
		util.PaintDown(pos, "Scorch", self)

		self:Remove()
	end

	-- Entschärfen mit dem Detektiv-Entschärfer (weapon_ttt_defuser)
	function ENT:Disarm(ply)
		if self.exploded then return end
		self.exploded = true
		sound.Play(soundDisarm, self:GetPos(), 70)
		DamageLog(Format("MINE:\t %s [%s] hat eine Näherungsmine entschärft", IsValid(ply) and ply:Nick() or "?", IsValid(ply) and ply:GetRoleString() or "?"))
		self:Remove()
	end

	-- Entschärfen mit E: nur geduckt (aufrecht hätte man sie längst ausgelöst), für jeden Spieler gleich
	function ENT:Use(activator)
		if not IsValid(activator) or not activator:IsPlayer() or not activator:IsTerror() then return end
		if self:GetTriggerTime() > 0 or not activator:Crouching() then return end
		self:Disarm(activator)
	end

	-- Zerschossen: verpufft ohne Explosion (base_placeable erledigt Gibs, Sound und Entfernen)
	function ENT:WasDestroyed()
		self.exploded = true
	end
end

if CLIENT then
	local glow = Material("sprites/light_glow02_add")
	local red = Color(255, 40, 40)

	-- Rotes Blinklicht, sobald scharf; schnelles Blinken nach dem Auslösen
	function ENT:Draw()
		self:DrawModel()
		if not self:GetArmed() then return end

		local rate = self:GetTriggerTime() > 0 and 12 or 1.5
		if math.sin(CurTime() * rate * math.pi) < 0 then return end

		render.SetMaterial(glow)
		render.DrawSprite(self:GetPos() + self:GetUp() * 12, 14, 14, red)
	end
end

-- Aufräumen: keine Minen in die Nachrunde bzw. die nächste Runde mitnehmen
if SERVER then
	local function cleanup()
		for _, ent in ipairs(ents.FindByClass("lmnt_naeherungsmine")) do
			ent.exploded = true
			ent:Remove()
		end
	end
	hook.Add("TTTEndRound", "LMNT.Naeherungsmine.Cleanup", cleanup)
	hook.Add("TTTPrepareRound", "LMNT.Naeherungsmine.Cleanup", cleanup)
end
