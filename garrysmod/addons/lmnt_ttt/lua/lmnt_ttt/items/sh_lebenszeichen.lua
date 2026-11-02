--[[
	LMNT TTT – Lebenszeichen-Monitor (item_lmnt_lebenszeichen) · Modul "ttt.items"

	Detektiv-Item. Stirbt ein Spieler in bis zu 2400 Einheiten (~45 m) Entfernung, erfährt der Träger:
	  "Lebenszeichen erloschen, ca. <x> m entfernt" (auf 5 m gerundet) und seit wann (Seitenleiste).
	Bewusst NICHT übertragen: Name, Rolle oder Team des Opfers, Täter, Waffe, Richtung, Position.
	So bleibt es eine Spur ("hier stimmt etwas nicht"), aber kein Rollenleck.

	Autorität: Entfernungsprüfung nur auf dem Server (lmnt.player.death = TTT2PostPlayerDeath).
	Die Net-Nachricht geht nur an den Träger und enthält nur die gerundete Entfernung.

	Zustand: Client LocalPlayer().lmntLebenszeichen (CurTime der letzten Meldung),
	         Server ply.lmntLebenszeichenGemeldet (Anzeige beim Tod des Trägers leeren).
	Zurückgesetzt bei Rundenvorbereitung, Tod des Trägers und beim Abschalten des Moduls.
]]

LMNT.TTT.Lebenszeichen = {
	class = "item_lmnt_lebenszeichen",
	reichweite = 2400, -- Einheiten (1 Einheit = 1,905 cm)
	raster = 5, -- Meter, auf die gerundet wird
	net = "lmnt_item_lebenszeichen",
}
local L = LMNT.TTT.Lebenszeichen

-- Testbar: Einheiten -> auf das Raster gerundete Meter (mindestens ein Rasterschritt)
function L.Meter(einheiten)
	local m = (tonumber(einheiten) or 0) * 0.01905
	return math.max(L.raster, math.Round(m / L.raster) * L.raster)
end

-- Testbar: liegt ein Tod (quadrierte Entfernung) im Messbereich?
function L.InReichweite(distSqr)
	return (tonumber(distSqr) or math.huge) <= L.reichweite * L.reichweite
end

if SERVER then
	util.AddNetworkString(L.net)

	-- meter = 0 bedeutet "Anzeige zurücksetzen"
	local function sende(ply, meter)
		net.Start(L.net)
		net.WriteUInt(math.Clamp(meter, 0, 255), 8)
		net.Send(ply)
	end

	LMNT.Events.On("lmnt.player.death", "LMNT.TTT.Lebenszeichen", function(victim)
		if not IsValid(victim) then return end

		-- Der Träger selbst ist tot: seine Anzeige leeren. Das Item hat TTT2 hier schon entfernt
		-- (DoPlayerDeath -> StripAll), daher merkt sich der Server, wem er etwas gemeldet hat.
		if victim.lmntLebenszeichenGemeldet then
			victim.lmntLebenszeichenGemeldet = nil
			sende(victim, 0)
		end

		if GetRoundState() ~= ROUND_ACTIVE then return end
		local pos = victim:GetPos()

		for _, ply in ipairs(player.GetAll()) do
			if ply ~= victim and ply:Alive() and ply:HasEquipmentItem(L.class) then
				local d = ply:GetPos():DistToSqr(pos)
				if L.InReichweite(d) then
					ply.lmntLebenszeichenGemeldet = true
					sende(ply, L.Meter(math.sqrt(d)))
				end
			end
		end
	end)

	local function vergessen()
		for _, ply in ipairs(player.GetAll()) do ply.lmntLebenszeichenGemeldet = nil end
	end
	LMNT.Events.On("lmnt.round.prepare", "LMNT.TTT.Lebenszeichen", vergessen)
	LMNT.Modules.TrackUndo(vergessen)
else
	net.Receive(L.net, function()
		local meter = net.ReadUInt(8)
		local ply = LocalPlayer()

		if meter == 0 then
			ply.lmntLebenszeichen = nil
			return
		end

		ply.lmntLebenszeichen = CurTime()
		local text = "Lebenszeichen erloschen – ca. " .. meter .. " m entfernt"
		if MSTACK and MSTACK.AddMessage then MSTACK:AddMessage(text) else chat.AddText(Color(255, 176, 32), text) end
		surface.PlaySound("buttons/blip1.wav")
	end)

	-- Für ITEM:DrawInfo: Sekunden seit der letzten Meldung
	function L.Anzeige()
		local ply = LocalPlayer()
		if not IsValid(ply) or not ply.lmntLebenszeichen then return "" end
		return math.min(999, math.floor(CurTime() - ply.lmntLebenszeichen)) .. "s"
	end

	hook.Add("TTTPrepareRound", "LMNT.TTT.Lebenszeichen", function()
		local ply = LocalPlayer()
		if IsValid(ply) then ply.lmntLebenszeichen = nil end
	end)

	LMNT.Modules.TrackUndo(function()
		local ply = LocalPlayer()
		if IsValid(ply) then ply.lmntLebenszeichen = nil end
	end)
end

LMNT.Modules.TrackUndo(function() LMNT.TTT.Lebenszeichen = nil end)
