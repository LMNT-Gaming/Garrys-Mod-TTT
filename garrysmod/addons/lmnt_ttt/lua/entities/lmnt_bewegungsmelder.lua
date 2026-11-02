--[[
	Bewegungsmelder (Entity zu weapon_lmnt_bewegungsmelder)
	Basis: ttt_base_placeable (TTT2) – Anbringen an Wand/Boden, Schaden nehmen, Zerstören.

	Erkennt Spieler, die sich schneller als Schleichtempo bewegen, in 320 Einheiten Umkreis
	mit freier Sichtlinie zum Sensor. Meldet dann an alle lebenden Detektive:
	  "Bewegungsmelder #n: Bewegung erkannt" + Markierung AM SENSORSTANDORT für 6 s.

	Informationsschutz (11.6) – gesendet werden NUR Sensornummer und Sensorposition:
	  · keine Identität, keine Rolle, keine Anzahl, keine Richtung, keine Spielerposition
	  · höchstens eine Meldung alle 10 s pro Sensor (kein Mitverfolgen von Personen)
	  · der Sensor reagiert auf alle Spieler gleich (nur der aufstellende Detektiv selbst wird ignoriert,
	    seine Rolle ist ohnehin öffentlich)
	Gegenspiel: Sensor ist sichtbar (grüne LED) und hat 30 HP, geduckt oder langsam gehen löst nicht aus,
	Sichtlinie meiden.
]]

if SERVER then
	AddCSLuaFile()
	util.AddNetworkString("lmnt_bewegungsmelder")
end

DEFINE_BASECLASS("ttt_base_placeable")

ENT.Type = "anim"
ENT.Base = "ttt_base_placeable"
ENT.PrintName = "Bewegungsmelder"
ENT.Model = Model("models/maxofs2d/motion_sensor.mdl")

ENT.CanHavePrints = false
ENT.isDestructible = true

local WEAPON_CLASS = "weapon_lmnt_bewegungsmelder"
local HEALTH = 30
local ARM_TIME = 2
local RADIUS = 320
local MIN_SPEED = 120      -- normales Gehen ~220, geduckt ~65: Schleichen bleibt unbemerkt
local COOLDOWN = 10
local MARKER_TIME = 6

function ENT:SetupDataTables()
	BaseClass.SetupDataTables(self)
	self:NetworkVar("Int", 0, "SensorNumber")
end

function ENT:Initialize()
	self:SetModel(self.Model)
	BaseClass.Initialize(self)

	if SERVER then
		self:SetMaxHealth(HEALTH)
		self:SetUseType(SIMPLE_USE)
		self.armAt = CurTime() + ARM_TIME
		self.nextAlert = 0
	end
	self:SetHealth(HEALTH)
end

if SERVER then
	local function isWatcher(ply)
		return IsValid(ply) and ply:IsTerror() and ply:Alive() and ply:GetBaseRole() == ROLE_DETECTIVE
	end

	function ENT:Detects(ply, pos)
		if ply == self:GetOriginator() or not ply:IsTerror() or not ply:Alive() then return false end
		if ply:GetVelocity():Length2D() < MIN_SPEED then return false end
		if ply:WorldSpaceCenter():DistToSqr(pos) > RADIUS * RADIUS then return false end

		local tr = util.TraceLine({
			start = pos,
			endpos = ply:WorldSpaceCenter(),
			filter = { self, ply },
			mask = MASK_SOLID,
		})
		return not tr.Hit
	end

	function ENT:Alert()
		local receivers = {}
		for _, ply in ipairs(player.GetAll()) do
			if isWatcher(ply) then receivers[#receivers + 1] = ply end
		end
		if #receivers == 0 then return end

		-- Bewusst nur Nummer und Sensorposition
		net.Start("lmnt_bewegungsmelder")
		net.WriteUInt(math.Clamp(self:GetSensorNumber(), 0, 255), 8)
		net.WriteVector(self:GetPos())
		net.Send(receivers)
	end

	function ENT:Think()
		local now = CurTime()
		if now < self.armAt or now < self.nextAlert then
			self:NextThink(now + 0.25)
			return true
		end

		local pos = self:GetPos() + self:GetUp() * 4
		for _, ply in ipairs(player.GetAll()) do
			if self:Detects(ply, pos) then
				self.nextAlert = now + COOLDOWN
				self:EmitSound("buttons/blip2.wav", 55, 120)
				self:Alert()
				break
			end
		end

		self:NextThink(now + 0.25)
		return true
	end

	-- Nur der Aufsteller kann den Sensor wieder einsammeln (gibt genau einen Sensor zurück)
	function ENT:Use(activator)
		if not IsValid(activator) or not activator:IsPlayer() or activator ~= self:GetOriginator() or not activator:IsTerror() then return end

		local wep = activator:GetWeapon(WEAPON_CLASS)
		if IsValid(wep) then
			if wep:Clip1() >= wep.Primary.ClipSize then return end
			wep:SetClip1(wep:Clip1() + 1)
		else
			wep = activator:SafePickupWeaponClass(WEAPON_CLASS, true)
			if not IsValid(wep) then return end
			wep:SetClip1(1)
		end

		activator:EmitSound("items/ammo_pickup.wav")
		self:Remove()
	end

	function ENT:WasDestroyed()
		local owner = self:GetOriginator()
		if not IsValid(owner) then return end
		local text = "Bewegungsmelder #" .. self:GetSensorNumber() .. " wurde zerstört."
		if LMNT and LMNT.Notify then
			LMNT.Notify(owner, Color(255, 176, 32), text)
		else
			owner:ChatPrint(text)
		end
	end

	-- Aufräumen am Rundenende
	local function cleanup()
		for _, ent in ipairs(ents.FindByClass("lmnt_bewegungsmelder")) do ent:Remove() end
		for _, ply in ipairs(player.GetAll()) do ply.lmntSensorCounter = nil end
	end
	hook.Add("TTTEndRound", "LMNT.Bewegungsmelder.Cleanup", cleanup)
	hook.Add("TTTPrepareRound", "LMNT.Bewegungsmelder.Cleanup", cleanup)
end

if CLIENT then
	local glow = Material("sprites/light_glow02_add")
	local green = Color(60, 255, 90)
	local markerColor = Color(80, 170, 255)
	local markers = {}

	function ENT:Draw()
		self:DrawModel()
		if math.sin(CurTime() * 2 * math.pi) > 0.6 then
			render.SetMaterial(glow)
			render.DrawSprite(self:GetPos() + self:GetUp() * 5, 6, 6, green)
		end
	end

	net.Receive("lmnt_bewegungsmelder", function()
		local number = net.ReadUInt(8)
		local pos = net.ReadVector()

		markers[number] = { pos = pos, untilTime = CurTime() + MARKER_TIME }
		MSTACK:AddColoredMessage("Bewegungsmelder #" .. number .. ": Bewegung erkannt", markerColor)
		surface.PlaySound("npc/turret_floor/ping.wav")
	end)

	-- Markierung am Sensorstandort (nicht am Spieler)
	hook.Add("HUDPaint", "LMNT.Bewegungsmelder.Marker", function()
		local now = CurTime()
		for number, m in pairs(markers) do
			if m.untilTime < now then
				markers[number] = nil
			else
				local scr = m.pos:ToScreen()
				if scr.visible then
					local alpha = math.Clamp((m.untilTime - now) / MARKER_TIME, 0, 1) * 255
					local size = 10 + 4 * math.sin(now * 8)
					surface.SetDrawColor(markerColor.r, markerColor.g, markerColor.b, alpha)
					surface.DrawOutlinedRect(scr.x - size, scr.y - size, size * 2, size * 2, 2)
					local dist = math.floor(LocalPlayer():GetPos():Distance(m.pos) * 0.01905)
					draw.SimpleTextOutlined("Bewegung #" .. number .. " · " .. dist .. " m", "DermaDefaultBold", scr.x, scr.y + size + 4,
						Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, alpha))
				end
			end
		end
	end)

	hook.Add("TTTEndRound", "LMNT.Bewegungsmelder.Reset", function() markers = {} end)
	hook.Add("TTTPrepareRound", "LMNT.Bewegungsmelder.Reset", function() markers = {} end)
end
