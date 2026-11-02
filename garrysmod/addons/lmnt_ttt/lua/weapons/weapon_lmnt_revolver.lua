--[[
	Revolver (.357) – Bodenwaffe, spawnt zufällig auf der Map
	Langsam, aber starker Kopfschuss-Multiplikator.
]]

if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_tttbase"

if CLIENT then
	SWEP.PrintName = "Revolver"
	SWEP.Slot = 1
	SWEP.ViewModelFOV = 60
	SWEP.Icon = "vgui/ttt/icon_deagle"
end

SWEP.Kind = WEAPON_PISTOL
SWEP.AutoSpawnable = true
SWEP.AmmoEnt = "item_ammo_revolver_ttt"
SWEP.AllowDrop = true
SWEP.IsSilent = false

SWEP.HoldType = "revolver"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_357.mdl"
SWEP.WorldModel = "models/weapons/w_357.mdl"

SWEP.Primary.Sound = Sound("Weapon_357.Single")
SWEP.Primary.Damage = 40
SWEP.Primary.NumShots = 1
SWEP.Primary.Cone = 0.012
SWEP.Primary.Recoil = 5
SWEP.Primary.Delay = 0.6
SWEP.Primary.ClipSize = 6
SWEP.Primary.ClipMax = 36
SWEP.Primary.DefaultClip = 6
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "AlyxGun"

SWEP.HeadshotMultiplier = 3

SWEP.IronSightsPos = Vector(-4.64, -3.96, 0.68)
SWEP.IronSightsAng = Vector(0.214, -0.1767, 0)
