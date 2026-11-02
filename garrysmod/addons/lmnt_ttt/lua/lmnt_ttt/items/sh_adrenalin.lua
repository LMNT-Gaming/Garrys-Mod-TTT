--[[
	LMNT TTT – Adrenalin (item_lmnt_adrenalin) · Modul "ttt.items"

	Fällt die Gesundheit durch Schaden auf <= 30 (und der Träger überlebt), einmal pro Leben:
	  +30 HP (höchstens bis zur Maximalgesundheit) und 6 s lang +30 % Laufgeschwindigkeit.
	Ein tödlicher Treffer wird NICHT abgefangen (PostEntityTakeDamage läuft nach dem Schaden).

	Autorität: Auslösung, Heilung und Laufzeit entscheidet nur der Server.
	Der Client des Trägers erfährt das Ende des Schubs per Net-Nachricht (nur an ihn), damit die
	Bewegungsvorhersage zum Server passt, und bekommt ein TTT2-Status-Icon (STATUS:AddTimedStatus,
	sv_status.lua / cl_status.lua). Andere Clients erhalten nichts.

	Zustand am Spieler (Server): ply.lmntAdrenalinBenutzt, ply.lmntAdrenalinBis
	                  (Client):  LocalPlayer().lmntAdrenalinBis
	Zurückgesetzt bei Spawn, Tod, Rundenvorbereitung und beim Abschalten des Moduls.
]]

LMNT.TTT.Adrenalin = {
	class = "item_lmnt_adrenalin",
	schwelle = 30, -- HP, ab der ausgelöst wird (einschließlich)
	heilung = 30, -- HP sofort
	dauer = 6, -- Sekunden Tempo-Schub
	tempo = 1.3, -- Faktor Laufgeschwindigkeit
	status = "lmnt_adrenalin",
	net = "lmnt_item_adrenalin",
}
local A = LMNT.TTT.Adrenalin

-- Testbar: Soll bei dieser Gesundheit nach dem Treffer ausgelöst werden?
function A.SollAusloesen(hpNachher, schonBenutzt)
	if schonBenutzt then return false end
	hpNachher = tonumber(hpNachher) or 0
	return hpNachher > 0 and hpNachher <= A.schwelle
end

-- Testbar: neue Gesundheit nach der Heilung (nie über dem Maximum, nie weniger als vorher)
function A.NeueGesundheit(hp, maxHp)
	return math.max(hp, math.min(maxHp, hp + A.heilung))
end

-- Tempo-Schub aktiv? Auf dem Server für jeden, auf dem Client nur für sich selbst bekannt
function A.TempoAktiv(ply, jetzt)
	local bis = ply.lmntAdrenalinBis
	return bis ~= nil and bis > (jetzt or CurTime())
end

LMNT.TTT.AddSpeedModifier("item_lmnt_adrenalin", function(ply)
	if A.TempoAktiv(ply) then return A.tempo end
end)

if SERVER then
	util.AddNetworkString(A.net)

	local function sende(ply, bis)
		net.Start(A.net)
		net.WriteFloat(bis)
		net.Send(ply)
	end

	local function zuruecksetzen(ply, informieren)
		local warAktiv = A.TempoAktiv(ply)
		ply.lmntAdrenalinBenutzt = nil
		ply.lmntAdrenalinBis = nil
		if informieren and warAktiv then
			sende(ply, 0)
			if STATUS and STATUS.RemoveStatus then STATUS:RemoveStatus(ply, A.status) end
		end
	end

	hook.Add("PostEntityTakeDamage", "LMNT.TTT.Adrenalin", function(ent, _, took)
		if not took or not IsValid(ent) or not ent:IsPlayer() or not ent:Alive() then return end
		if GetRoundState() ~= ROUND_ACTIVE or not ent:HasEquipmentItem(A.class) then return end
		if not A.SollAusloesen(ent:Health(), ent.lmntAdrenalinBenutzt) then return end

		ent.lmntAdrenalinBenutzt = true
		ent:SetHealth(A.NeueGesundheit(ent:Health(), ent:GetMaxHealth()))
		ent.lmntAdrenalinBis = CurTime() + A.dauer

		-- Hörbares Signal für Umstehende (Gegenspiel), keine Rolleninformation
		ent:EmitSound("items/medshot4.wav", 70, 110)

		sende(ent, ent.lmntAdrenalinBis)
		if STATUS and STATUS.AddTimedStatus then STATUS:AddTimedStatus(ent, A.status, A.dauer, true) end
	end)

	hook.Add("PlayerSpawn", "LMNT.TTT.Adrenalin", function(ply) zuruecksetzen(ply, false) end)
	hook.Add("PostPlayerDeath", "LMNT.TTT.Adrenalin", function(ply) zuruecksetzen(ply, true) end)

	LMNT.Events.On("lmnt.round.prepare", "LMNT.TTT.Adrenalin", function()
		for _, ply in ipairs(player.GetAll()) do zuruecksetzen(ply, true) end
	end)

	LMNT.Modules.TrackUndo(function()
		for _, ply in ipairs(player.GetAll()) do zuruecksetzen(ply, true) end
	end)
else
	net.Receive(A.net, function()
		local bis = net.ReadFloat()
		LocalPlayer().lmntAdrenalinBis = bis > 0 and bis or nil
	end)

	-- Status-Icon registrieren (cl_status.lua: STATUS:RegisterStatus(id, { hud, type, name, sidebarDescription }))
	local function registrieren()
		if not (STATUS and STATUS.RegisterStatus) or STATUS:Registered(A.status) then return end
		STATUS:RegisterStatus(A.status, {
			hud = Material("vgui/ttt/perks/hud_speedrun.png"),
			type = "good",
			name = "Adrenalin",
			sidebarDescription = "Adrenalinschub: geheilt und kurz schneller.",
		})
	end
	registrieren()
	hook.Add("InitPostEntity", "LMNT.TTT.Adrenalin", registrieren)

	LMNT.Modules.TrackUndo(function()
		local ply = LocalPlayer()
		if IsValid(ply) then ply.lmntAdrenalinBis = nil end
		if STATUS and STATUS.registered then
			if STATUS.RemoveStatus then STATUS:RemoveStatus(A.status) end
			STATUS.registered[A.status] = nil
		end
	end)
end

LMNT.Modules.TrackUndo(function() LMNT.TTT.Adrenalin = nil end)
