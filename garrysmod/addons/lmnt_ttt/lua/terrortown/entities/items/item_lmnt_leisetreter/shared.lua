-- Leisetreter: andere hören deine Schritte nicht (Wirkung: lua/lmnt_ttt/items/sv_leisetreter.lua)
if SERVER then AddCSLuaFile() end

ITEM.EquipMenuData = {
	type = "item_passive",
	name = "Leisetreter",
	desc = "Andere Spieler hören deine Schritte nicht mehr.\nDu selbst hörst sie weiterhin. Sprünge, Landungen und Waffen bleiben hörbar.",
}
ITEM.material = "vgui/ttt/icon_foot"
ITEM.CanBuy = { ROLE_TRAITOR }
ITEM.credits = 1 -- Beleg: sh_shop.lua liest equipment.credits (Standard 1)
ITEM.limited = true -- Beleg: item_base, AddEquipmentItem verweigert ein zweites Exemplar
