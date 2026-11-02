-- Energieschild: fängt einmalig 40 Schaden ab und ist danach verbraucht (Wirkung: lua/lmnt_ttt/items/sh_energieschild.lua)
if SERVER then AddCSLuaFile() end

ITEM.EquipMenuData = {
	type = "item_passive",
	name = "Energieschild",
	desc = "Ein Schild fängt insgesamt 40 Schaden ab, bevor deine Gesundheit sinkt.\nIst er leer, bricht er hörbar und das Item ist verbraucht.\nKein Schutz gegen Fall- und Ertrinkungsschaden.",
}
ITEM.material = "vgui/ttt/icon_noenergydmg"
ITEM.hud = Material("vgui/ttt/perks/hud_armor_reinforced.png")
ITEM.CanBuy = { ROLE_TRAITOR, ROLE_DETECTIVE }
ITEM.credits = 1
ITEM.limited = true

if CLIENT then
	-- Restwert unten rechts am Seitenleisten-Symbol (Hook aus item_base: ITEM:DrawInfo)
	function ITEM:DrawInfo()
		local fn = LMNT and LMNT.TTT and LMNT.TTT.Energieschild and LMNT.TTT.Energieschild.Anzeige
		return fn and fn() or ""
	end
end
