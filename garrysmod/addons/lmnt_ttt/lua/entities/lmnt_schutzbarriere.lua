--[[
	Schutzbarriere (Entity zu weapon_lmnt_schutzbarriere)
	Basis: ttt_base_placeable (TTT2) – Schaden nehmen, Zerstören, Schadenslog.

	Eine aufgestellte Combine-Barrikade mit 300 HP, die Kugeln und Explosionen abfängt.
	Sie ist fest verankert, und Spieler können hindurchgehen (COLLISION_GROUP_WEAPON der Basis),
	damit sie keine Türen oder Gänge versperrt. Nach 60 s oder bei 0 HP bricht sie zusammen.
	Gegenspiel: zerschießen, umgehen, Granaten darüber werfen, abwarten.
]]

if SERVER then AddCSLuaFile() end

DEFINE_BASECLASS("ttt_base_placeable")

ENT.Type = "anim"
ENT.Base = "ttt_base_placeable"
ENT.PrintName = "Schutzbarriere"
ENT.Model = Model("models/props_combine/combine_barricade_short01a.mdl")

ENT.CanHavePrints = false
ENT.isDestructible = true

local HEALTH = 300
local LIFETIME = 60

function ENT:SetupDataTables()
	BaseClass.SetupDataTables(self)
	self:NetworkVar("Int", 0, "Durability")   -- für die Farbanzeige auf dem Client
end

function ENT:Initialize()
	self:SetModel(self.Model)
	BaseClass.Initialize(self)

	if SERVER then
		self:SetMaxHealth(HEALTH)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
		self.removeAt = CurTime() + LIFETIME
		self:SetDurability(HEALTH)
	end
	self:SetHealth(HEALTH)
end

if SERVER then
	function ENT:OnTakeDamage(dmgInfo)
		BaseClass.OnTakeDamage(self, dmgInfo)
		if IsValid(self) then self:SetDurability(math.max(0, self:Health())) end
	end

	function ENT:Think()
		if CurTime() >= self.removeAt then
			local ed = EffectData()
			ed:SetOrigin(self:WorldSpaceCenter())
			util.Effect("cball_explode", ed)
			self:EmitSound("ambient/energy/spark1.wav", 70)
			self:Remove()
			return
		end
		self:NextThink(CurTime() + 0.5)
		return true
	end

	function ENT:WasDestroyed()
		local owner = self:GetOriginator()
		if IsValid(owner) and owner:IsPlayer() then
			if LMNT and LMNT.Notify then
				LMNT.Notify(owner, Color(255, 176, 32), "Deine Schutzbarriere wurde zerstört.")
			else
				owner:ChatPrint("Deine Schutzbarriere wurde zerstört.")
			end
		end
	end

	-- Aufräumen am Rundenende
	local function cleanup()
		for _, ent in ipairs(ents.FindByClass("lmnt_schutzbarriere")) do ent:Remove() end
	end
	hook.Add("TTTEndRound", "LMNT.Schutzbarriere.Cleanup", cleanup)
	hook.Add("TTTPrepareRound", "LMNT.Schutzbarriere.Cleanup", cleanup)
end

if CLIENT then
	-- Leichte Blau-Tönung, die mit sinkender Haltbarkeit ins Rote kippt (sichtbar für alle)
	function ENT:Draw()
		local frac = math.Clamp(self:GetDurability() / HEALTH, 0, 1)
		render.SetColorModulation(1 - 0.6 * frac, 0.4 + 0.3 * frac, 0.4 + 0.6 * frac)
		self:DrawModel()
		render.SetColorModulation(1, 1, 1)
	end
end
