--[[
	Bewegungsmelder (Detektiv-Shop)
	Zwei Sensoren zum Anbringen an Wand oder Boden (Entity: lmnt_bewegungsmelder).
	Meldet Detektiven NUR "Bewegung erkannt" und den Standort des Sensors – nie wer, wie viele
	oder welche Rolle. Höchstens eine Meldung alle 10 s pro Sensor. Mit E wieder einsammelbar.
]]

if SERVER then AddCSLuaFile() end

DEFINE_BASECLASS("weapon_tttbase")

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.PrintName = "Bewegungsmelder"
	SWEP.Slot = 7
	SWEP.ViewModelFOV = 54
	SWEP.ShowDefaultViewModel = false
	SWEP.Icon = "vgui/ttt/icon_beacon"
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "2 Sensoren für Wand oder Boden.\nMeldet allen Detektiven \"Bewegung erkannt\" und den Sensorstandort.\nVerrät nie, wer sich bewegt hat. Schleichen löst nicht aus.",
	}
end

SWEP.Kind = WEAPON_EQUIP2
SWEP.CanBuy = { ROLE_DETECTIVE }
SWEP.credits = 1
SWEP.LimitedStock = true
SWEP.AllowDrop = false
SWEP.NoSights = true

SWEP.HoldType = "slam"
SWEP.ViewModel = "models/weapons/v_crowbar.mdl"
SWEP.WorldModel = "models/maxofs2d/motion_sensor.mdl"

SWEP.Primary.ClipSize = 2
SWEP.Primary.DefaultClip = 2
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 1

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:PrimaryAttack()
	self:SetNextPrimaryFire(CurTime() + self.Primary.Delay)
	if CLIENT or not self:CanPrimaryAttack() then return end

	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	local sensor = ents.Create("lmnt_bewegungsmelder")
	if not IsValid(sensor) then return end

	if sensor:StickEntity(owner, Angle(90, 0, 0), 0) then
		owner.lmntSensorCounter = (owner.lmntSensorCounter or 0) + 1
		sensor:SetSensorNumber(owner.lmntSensorCounter)
		owner:ChatPrint("Bewegungsmelder #" .. owner.lmntSensorCounter .. " angebracht.")

		self:TakePrimaryAmmo(1)
		if self:Clip1() <= 0 then self:Remove() end
	else
		sensor:Remove()
		owner:EmitSound("HL2Player.UseDeny")
	end
end

function SWEP:SecondaryAttack() end

function SWEP:Reload() return false end

if CLIENT then
	function SWEP:Initialize()
		self:AddTTT2HUDHelp("Sensor an Wand oder Boden anbringen (mit E wieder einsammeln)")
		return BaseClass.Initialize(self)
	end

	function SWEP:DrawWorldModel()
		if IsValid(self:GetOwner()) then return end
		self:DrawModel()
	end
end
