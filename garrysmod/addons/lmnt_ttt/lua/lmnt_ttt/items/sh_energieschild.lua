--[[
	LMNT TTT – Energieschild (item_lmnt_energieschild) · Modul "ttt.items"

	Verbrauchs-Item: ein Schild-Vorrat von 40 Punkten fängt Schaden ab, bevor die Gesundheit sinkt.
	Ist der Vorrat leer, bricht der Schild hörbar und das Item wird entfernt (RemoveEquipmentItem).
	Nicht abgefangen: Fallschaden, Ertrinken. Nur in der aktiven Runde.

	Reihenfolge: Der Hook läuft in EntityTakeDamage vor GM:EntityTakeDamage (TTT2-Rüstung),
	der Schild wirkt also vor der Rüstung. Die Reihenfolge zu anderen EntityTakeDamage-Hooks
	(z. B. Explosionsschutz) ist in GMod nicht festgelegt.

	Autorität: Vorrat und Verbrauch nur auf dem Server. Der Restwert geht per Net-Nachricht
	ausschließlich an den Träger (Anzeige am Seitenleisten-Symbol über ITEM:DrawInfo).

	Zustand: ply.lmntSchild (Server: Restvorrat, nil = voll bzw. kein Schild; Client: nur LocalPlayer)
	Zurückgesetzt bei Spawn, Tod, Rundenvorbereitung, Verbrauch und beim Abschalten des Moduls.
]]

LMNT.TTT.Energieschild = {
	class = "item_lmnt_energieschild",
	vorrat = 40,
	-- Diese Schadensarten gehen am Schild vorbei
	ausnahmen = bit.bor(DMG_FALL, DMG_DROWN),
	net = "lmnt_item_energieschild",
}
local S = LMNT.TTT.Energieschild

-- Testbar: Wird diese Schadensart vom Schild abgefangen?
function S.FaengtAb(dmgType)
	return bit.band(tonumber(dmgType) or 0, S.ausnahmen) == 0
end

-- Testbar: verteilt Schaden auf den Schild. Rückgabe: Restschaden, neuer Vorrat
function S.Absorbiere(vorrat, schaden)
	vorrat = math.max(0, tonumber(vorrat) or 0)
	schaden = math.max(0, tonumber(schaden) or 0)
	local ab = math.min(vorrat, schaden)
	return schaden - ab, vorrat - ab
end

if SERVER then
	util.AddNetworkString(S.net)

	local function sende(ply, wert)
		net.Start(S.net)
		net.WriteUInt(math.Clamp(math.ceil(wert), 0, 255), 8)
		net.Send(ply)
	end

	hook.Add("EntityTakeDamage", "LMNT.TTT.Energieschild", function(ent, dmg)
		if not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return end
		if GetRoundState() ~= ROUND_ACTIVE or not ent:HasEquipmentItem(S.class) then return end
		if not S.FaengtAb(dmg:GetDamageType()) or dmg:GetDamage() <= 0 then return end

		local rest, vorrat = S.Absorbiere(ent.lmntSchild or S.vorrat, dmg:GetDamage())
		dmg:SetDamage(rest)

		if vorrat > 0 then
			ent.lmntSchild = vorrat
			sende(ent, vorrat)
			return
		end

		-- Verbraucht: Item entfernen (ruft ITEM:Reset und synchronisiert den Client), Bruch hörbar machen
		ent.lmntSchild = nil
		sende(ent, 0)
		ent:EmitSound("ambient/energy/zap1.wav", 75, 90)
		ent:RemoveEquipmentItem(S.class)
	end)

	-- Teilverbrauchten Schild verwerfen und den Client des Trägers informieren
	local function zuruecksetzen(ply)
		if ply.lmntSchild == nil then return end
		ply.lmntSchild = nil
		if IsValid(ply) then sende(ply, 0) end
	end
	hook.Add("PlayerSpawn", "LMNT.TTT.Energieschild", zuruecksetzen)
	hook.Add("PostPlayerDeath", "LMNT.TTT.Energieschild", zuruecksetzen)

	LMNT.Events.On("lmnt.round.prepare", "LMNT.TTT.Energieschild", function()
		for _, ply in ipairs(player.GetAll()) do zuruecksetzen(ply) end
	end)

	LMNT.Modules.TrackUndo(function()
		for _, ply in ipairs(player.GetAll()) do zuruecksetzen(ply) end
	end)
else
	net.Receive(S.net, function()
		local wert = net.ReadUInt(8)
		LocalPlayer().lmntSchild = wert > 0 and wert or nil
	end)

	-- Für ITEM:DrawInfo (Restvorrat am Symbol)
	function S.Anzeige()
		local ply = LocalPlayer()
		if not IsValid(ply) or not ply:HasEquipmentItem(S.class) then return "" end
		return tostring(ply.lmntSchild or S.vorrat)
	end

	-- Neuer Schild nach Tod/Spawn: alten Restwert verwerfen
	hook.Add("TTTPrepareRound", "LMNT.TTT.Energieschild", function()
		local ply = LocalPlayer()
		if IsValid(ply) then ply.lmntSchild = nil end
	end)

	LMNT.Modules.TrackUndo(function()
		local ply = LocalPlayer()
		if IsValid(ply) then ply.lmntSchild = nil end
	end)
end

LMNT.Modules.TrackUndo(function() LMNT.TTT.Energieschild = nil end)
