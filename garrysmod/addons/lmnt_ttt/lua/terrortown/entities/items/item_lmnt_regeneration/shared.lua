-- Regeneration: +1 HP alle 2 Sekunden (Wirkung: lua/lmnt_ttt/sh_items.lua)
if SERVER then AddCSLuaFile() end

ITEM.EquipMenuData = {
	type = "item_passive",
	name = "Regeneration",
	desc = "Du heilst dich langsam selbst: +1 HP alle 2 Sekunden.",
}
ITEM.material = "vgui/ttt/icon_health"
ITEM.CanBuy = { ROLE_DETECTIVE }
