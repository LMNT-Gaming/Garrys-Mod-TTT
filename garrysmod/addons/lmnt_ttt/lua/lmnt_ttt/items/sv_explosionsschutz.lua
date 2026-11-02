--[[
	LMNT TTT – Explosionsschutz (item_lmnt_explosionsschutz) · Modul "ttt.items"

	Halbiert Explosionsschaden (DMG_BLAST) und Feuerschaden (DMG_BURN, DMG_SLOWBURN).
	Vorbild: TTT2 item_ttt_noexplosiondmg / item_ttt_nofiredmg (dort 100 % Schutz, je ein Item).
	Unterschied: ein Item für beides, dafür nur 50 %. Trägt jemand zusätzlich das TTT2-Item,
	multiplizieren sich die Faktoren (0 bleibt 0).

	Zustand: keiner (nur HasEquipmentItem; TTT2 entfernt Items bei Tod und Spawn).
]]

LMNT.TTT.Explosionsschutz = {
	class = "item_lmnt_explosionsschutz",
	faktor = 0.5,
	-- Schadensarten, die reduziert werden
	typen = bit.bor(DMG_BLAST, DMG_BURN, DMG_SLOWBURN),
}
local X = LMNT.TTT.Explosionsschutz

-- Testbar: Schadensfaktor für eine Schadensart-Bitmaske (1 = keine Reduktion)
function X.Faktor(dmgType)
	if bit.band(tonumber(dmgType) or 0, X.typen) ~= 0 then return X.faktor end
	return 1
end

hook.Add("EntityTakeDamage", "LMNT.TTT.Explosionsschutz", function(ent, dmg)
	if not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return end
	if not ent:HasEquipmentItem(X.class) then return end

	local f = X.Faktor(dmg:GetDamageType())
	if f < 1 then dmg:ScaleDamage(f) end
end)

LMNT.Modules.TrackUndo(function() LMNT.TTT.Explosionsschutz = nil end)
