-- Explosionsschutz: halbiert Explosions- und Feuerschaden (Wirkung: lua/lmnt_ttt/items/sv_explosionsschutz.lua)
if SERVER then AddCSLuaFile() end

ITEM.EquipMenuData = {
	type = "item_passive",
	name = "Explosionsschutz",
	desc = "Du erleidest nur noch die Hälfte des Schadens durch Explosionen und Feuer.",
}
ITEM.material = "vgui/ttt/icon_splode"
-- Symbol in der Seitenleiste (wie die TTT2-Items item_ttt_noexplosiondmg/nofiredmg)
ITEM.hud = Material("vgui/ttt/perks/hud_noexplosiondmg.png")
ITEM.CanBuy = { ROLE_TRAITOR, ROLE_DETECTIVE }
ITEM.credits = 1
ITEM.limited = true
