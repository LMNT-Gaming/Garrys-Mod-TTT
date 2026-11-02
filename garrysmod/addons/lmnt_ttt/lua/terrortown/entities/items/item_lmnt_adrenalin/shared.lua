-- Adrenalin: einmaliger Heil- und Tempo-Schub bei niedriger Gesundheit (Wirkung: lua/lmnt_ttt/items/sh_adrenalin.lua)
if SERVER then AddCSLuaFile() end

ITEM.EquipMenuData = {
	type = "item_passive",
	name = "Adrenalin",
	desc = "Fällt deine Gesundheit durch Schaden auf 30 oder weniger,\nheilst du sofort 30 HP und läufst 6 Sekunden lang 30 % schneller.\nWirkt einmal pro Leben, rettet nicht vor einem tödlichen Treffer.",
}
ITEM.material = "vgui/ttt/icon_halp"
ITEM.CanBuy = { ROLE_TRAITOR, ROLE_DETECTIVE }
ITEM.credits = 1
ITEM.limited = true
