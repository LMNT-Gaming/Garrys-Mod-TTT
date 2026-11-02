--[[
	Giftgasgranate (Traitor-Shop)
	Granate auf Basis von weapon_tttbasegrenade. Zündet 3 s nach dem Abziehen und hinterlässt eine
	Gaswolke: 12 s lang 5 Schaden pro Sekunde im Radius (Entity: lmnt_giftgas_proj).
	Als Ausrüstung (WEAPON_EQUIP2), damit sie den Granaten-Platz für Boden-Granaten nicht blockiert.
]]

if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_tttbasegrenade"

if CLIENT then
	SWEP.PrintName = "Giftgasgranate"
	SWEP.Slot = 7
	SWEP.ViewModelFlip = false
	SWEP.ViewModelFOV = 54
	SWEP.Icon = "vgui/ttt/icon_smokegrenade"
	SWEP.EquipMenuData = {
		type = "item_weapon",
		desc = "Hinterlässt eine grüne Giftwolke: 5 Schaden pro Sekunde für 12 Sekunden.\nWirkt nicht durch Wände – wer die Wolke verlässt, ist sicher.\nTrifft jeden, auch dich.",
	}
end

SWEP.Kind = WEAPON_EQUIP2
SWEP.CanBuy = { ROLE_TRAITOR }
SWEP.credits = 1
SWEP.LimitedStock = true
SWEP.AllowDrop = true
SWEP.IsSilent = false

SWEP.HoldType = "grenade"
SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/cstrike/c_eq_smokegrenade.mdl"
SWEP.WorldModel = "models/weapons/w_eq_smokegrenade.mdl"

SWEP.detonate_timer = 3

function SWEP:GetGrenadeName()
	return "lmnt_giftgas_proj"
end
