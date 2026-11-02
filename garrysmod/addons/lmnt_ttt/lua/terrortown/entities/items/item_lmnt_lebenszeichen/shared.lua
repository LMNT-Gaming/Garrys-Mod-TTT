-- Lebenszeichen-Monitor: meldet Tode in der Nähe ohne Namen, Rolle oder Täter (Wirkung: lua/lmnt_ttt/items/sh_lebenszeichen.lua)
if SERVER then AddCSLuaFile() end

ITEM.EquipMenuData = {
	type = "item_passive",
	name = "Lebenszeichen-Monitor",
	desc = "Stirbt in bis zu etwa 45 m Entfernung ein Spieler, erfährst du\ndie ungefähre Entfernung und den Zeitpunkt.\nKein Name, keine Rolle, kein Täter, keine Richtung.",
}
ITEM.material = "vgui/ttt/icon_time"
ITEM.hud = Material("vgui/ttt/icon_skull")
ITEM.CanBuy = { ROLE_DETECTIVE }
ITEM.credits = 1
ITEM.limited = true

if CLIENT then
	-- Sekunden seit dem letzten gemeldeten Tod in der Nähe (Hook aus item_base: ITEM:DrawInfo)
	function ITEM:DrawInfo()
		local fn = LMNT and LMNT.TTT and LMNT.TTT.Lebenszeichen and LMNT.TTT.Lebenszeichen.Anzeige
		return fn and fn() or ""
	end
end
