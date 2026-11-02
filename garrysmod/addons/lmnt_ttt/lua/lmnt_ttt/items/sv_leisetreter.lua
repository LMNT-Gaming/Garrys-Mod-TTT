--[[
	LMNT TTT – Leisetreter (item_lmnt_leisetreter) · Modul "ttt.items"

	Warum nur serverseitig:
	  GM:PlayerFootstep ist "shared, predicted" (TTT2 sh_main.lua, GMod-Wiki). Der Server spielt das
	  Schrittgeräusch für die ANDEREN Spieler ab (Parameter rf = Empfänger, nur serverseitig vorhanden),
	  der Client des Läufers sagt nur seine eigenen Schritte voraus. Gibt der Server-Hook true zurück,
	  wird das Geräusch für alle anderen unterdrückt; der Träger hört sich selbst weiter.
	  Andere Clients brauchen deshalb KEINE Information, wer das Item trägt – es wird nichts übertragen,
	  was eine Rolle verraten könnte (Ausrüstung ist in TTT2 ohnehin nur dem Besitzer bekannt).
	  TTT2 macht dasselbe beim Schleichen (GM:PlayerFootstep: return true unter 150 Einheiten/s).

	Zustand: keiner – entscheidend ist allein HasEquipmentItem, und TTT2 entfernt das Item bei Tod
	(StripAll -> ResetEquipment) und beim Spawn (ResetRoundFlags).
]]

LMNT.TTT.Leisetreter = {
	class = "item_lmnt_leisetreter",
}
local L = LMNT.TTT.Leisetreter

-- Testbare Entscheidung: Sollen die Schritte dieses Spielers für andere stumm sein?
function L.IstStumm(ply)
	if not ply or not ply.HasEquipmentItem then return false end
	if ply.Alive and not ply:Alive() then return false end
	return ply:HasEquipmentItem(L.class) == true
end

hook.Add("PlayerFootstep", "LMNT.TTT.Leisetreter", function(ply)
	-- true = Standardgeräusch unterdrücken; nil lässt TTT2/andere Hooks entscheiden
	if IsValid(ply) and L.IstStumm(ply) then return true end
end)

LMNT.Modules.TrackUndo(function() LMNT.TTT.Leisetreter = nil end)
