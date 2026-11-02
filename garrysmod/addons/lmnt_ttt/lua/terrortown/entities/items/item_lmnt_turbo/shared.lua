-- Turbo-Schuhe: +25 % Laufgeschwindigkeit (Wirkung: lua/lmnt_ttt/sh_items.lua)
if SERVER then AddCSLuaFile() end

ITEM.EquipMenuData = {
	type = "item_passive",
	name = "Turbo-Schuhe",
	desc = "Du läufst 25 % schneller.",
}
ITEM.material = "vgui/ttt/icon_disguise"
ITEM.CanBuy = { ROLE_TRAITOR, ROLE_DETECTIVE }
