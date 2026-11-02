--[[
	LMNT TTT – gemeinsame Helfer

	LMNT.TTT.AddSpeedModifier(id, function(ply) return multiplikator end)
	  Alle Modifikatoren werden multipliziert (Items, Spezialrunden …).
	  Läuft auf Server und Client, damit die Bewegungsvorhersage stimmt.
]]

LMNT.TTT.SpeedMods = LMNT.TTT.SpeedMods or {}

function LMNT.TTT.AddSpeedModifier(id, fn)
	LMNT.TTT.SpeedMods[id] = fn
	LMNT.Modules.TrackUndo(function() LMNT.TTT.SpeedMods[id] = nil end)
end

hook.Add("TTTPlayerSpeedModifier", "LMNT.TTT.Speed", function(ply, _, _, modTable)
	local mult = 1

	for _, fn in pairs(LMNT.TTT.SpeedMods) do
		mult = mult * (fn(ply) or 1)
	end

	if mult == 1 then return end

	-- TTT2 übergibt eine Tabelle, klassisches TTT erwartet einen Rückgabewert
	if istable(modTable) then
		modTable[1] = modTable[1] * mult
		return
	end

	return mult
end)

-- Team eines Spielers (TTT2 oder klassisches TTT)
function LMNT.TTT.GetTeam(ply)
	if ply.GetTeam then return ply:GetTeam() end
	if ply:IsTraitor() then return "traitors" end
	return "innocents"
end

function LMNT.TTT.IsActiveRound()
	return GetRoundState() == ROUND_ACTIVE
end
