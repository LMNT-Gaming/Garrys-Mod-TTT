-- Fallschutz: kein Fallschaden (Wirkung: lua/lmnt_ttt/sh_items.lua)
if SERVER then AddCSLuaFile() end

ITEM.EquipMenuData = {
	type = "item_passive",
	name = "Fallschutz",
	desc = "Du erleidest keinen Fallschaden mehr.",
}
ITEM.material = "vgui/ttt/icon_armor"
ITEM.CanBuy = { ROLE_TRAITOR, ROLE_DETECTIVE }
