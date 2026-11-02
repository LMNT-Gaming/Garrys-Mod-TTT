--[[
	Pumpgun – Bodenwaffe, spawnt zufällig auf der Map (Schrot)
	Basis: weapon_zm_shotgun (TTT2-Schrotflinte) – übernimmt Patrone-für-Patrone-Nachladen und den
	entfernungsabhängigen Kopfschuss-Multiplikator. Munition: Buckshot / item_box_buckshot_ttt.
	Gegenüber der TTT-Schrotflinte: engere Streuung (mehr Reichweite), aber langsamer und kleineres Magazin.
]]

if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_zm_shotgun"

if CLIENT then
	SWEP.PrintName = "Pumpgun"
	SWEP.Slot = 2
	SWEP.ViewModelFlip = false
	SWEP.ViewModelFOV = 54
	SWEP.Icon = "vgui/ttt/icon_shotgun"
end

SWEP.Kind = WEAPON_HEAVY
SWEP.spawnType = WEAPON_TYPE_SHOTGUN
SWEP.AutoSpawnable = true
SWEP.Spawnable = true
SWEP.AmmoEnt = "item_box_buckshot_ttt"
SWEP.AllowDrop = true
SWEP.IsSilent = false
SWEP.builtin = false

SWEP.HoldType = "shotgun"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_shotgun.mdl"
SWEP.WorldModel = "models/weapons/w_shotgun.mdl"

SWEP.Primary.Sound = Sound("Weapon_Shotgun.Single")
SWEP.Primary.Ammo = "Buckshot"
SWEP.Primary.Damage = 9
SWEP.Primary.NumShots = 10
SWEP.Primary.Cone = 0.06
SWEP.Primary.Delay = 1.05
SWEP.Primary.Recoil = 7
SWEP.Primary.ClipSize = 6
SWEP.Primary.ClipMax = 24
SWEP.Primary.DefaultClip = 6
SWEP.Primary.Automatic = false

-- Kein passendes Visier für das HL2-Modell: Rechtsklick ohne Funktion (SecondaryAttack der Basis prüft NoSights)
SWEP.NoSights = true

SWEP.DryFireSound = ")weapons/shotgun/shotgun_empty.wav"
