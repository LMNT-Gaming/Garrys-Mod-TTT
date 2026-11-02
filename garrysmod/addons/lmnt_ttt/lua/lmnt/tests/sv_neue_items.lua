-- LMNT Unit-Tests: neue Shop-Items (Leisetreter, Adrenalin, Explosionsschutz, Energieschild, Lebenszeichen-Monitor)
-- Prüft TTT2-Registrierung, LMNT-Metadaten und die reinen Wirkungsfunktionen. Keine Spieler nötig,
-- am laufenden Server wird nichts verändert (Fake-Spieler sind einfache Tabellen).
local T = LMNT.Test

local ITEMS = {
	item_lmnt_leisetreter = { ROLE_TRAITOR },
	item_lmnt_adrenalin = { ROLE_TRAITOR, ROLE_DETECTIVE },
	item_lmnt_explosionsschutz = { ROLE_TRAITOR, ROLE_DETECTIVE },
	item_lmnt_energieschild = { ROLE_TRAITOR, ROLE_DETECTIVE },
	item_lmnt_lebenszeichen = { ROLE_DETECTIVE },
}

-- TTT2 nutzt CanBuy als Liste { ROLE_X } oder als Menge [subrole] = subrole (items.lua, sh_shop.lua)
local function kannKaufen(stored, role)
	if not istable(stored) or not istable(stored.CanBuy) or role == nil then return false end
	for k, v in pairs(stored.CanBuy) do
		if v == role or (k == role and v) then return true end
	end
	return false
end

T.Describe("Neue Items – TTT2-Registrierung", function(t)
	t:It("alle fünf Items sind über items.GetStored geladen", function(e)
		e:True(istable(items) and isfunction(items.GetStored), "TTT2-Bibliothek items fehlt")
		for class in SortedPairs(ITEMS) do
			e:True(istable(items.GetStored(class)), class .. " nicht geladen")
		end
	end)
	t:It("TTT2-Felder belegt: EquipMenuData, material, credits, limited", function(e)
		for class in SortedPairs(ITEMS) do
			local it = items.GetStored(class)
			e:True(istable(it.EquipMenuData), class .. ": EquipMenuData")
			e:Equal(it.EquipMenuData.type, "item_passive", class .. ": type")
			e:True(isstring(it.EquipMenuData.name) and it.EquipMenuData.name ~= "", class .. ": name")
			e:True(isstring(it.EquipMenuData.desc) and it.EquipMenuData.desc ~= "", class .. ": desc")
			e:True(isstring(it.material) and it.material ~= "", class .. ": material")
			e:Equal(it.credits, 1, class .. ": credits")
			e:Equal(it.limited, true, class .. ": limited")
		end
	end)
	t:It("Shop-Rollen wie geplant (Traitor/Detektiv)", function(e)
		for class, roles in SortedPairs(ITEMS) do
			local it = items.GetStored(class)
			for _, role in ipairs(roles) do
				e:True(kannKaufen(it, role), class .. ": Rolle " .. tostring(role) .. " fehlt in CanBuy")
			end
		end
		e:False(kannKaufen(items.GetStored("item_lmnt_leisetreter"), ROLE_DETECTIVE), "Leisetreter nur Traitor")
		e:False(kannKaufen(items.GetStored("item_lmnt_lebenszeichen"), ROLE_TRAITOR), "Lebenszeichen nur Detektiv")
	end)
end)

T.Describe("Neue Items – LMNT-Metadaten", function(t)
	t:It("LMNT.Weapons.Check meldet ttt2", function(e)
		e:True(LMNT.Weapons and isfunction(LMNT.Weapons.Check), "Modul ttt.shop ist aus")
		for class in SortedPairs(ITEMS) do
			e:Equal((LMNT.Weapons.Check(class)), "ttt2", class)
		end
	end)
	t:It("registriert als Item der Kategorie Passiv mit Kaufgrenze 1", function(e)
		for class in SortedPairs(ITEMS) do
			local v = LMNT.Weapons.Get(class)
			e:True(v.registered, class .. ": nicht registriert")
			e:Equal(v.kind, "item", class)
			e:Equal(v.category, "Passiv", class)
			e:Equal(v.sourceAddon, "lmnt_ttt", class)
			e:Equal(LMNT.Weapons._registry[class].shopDefaults.maxPerRound, 1, class .. ": maxPerRound")
		end
		e:Equal(LMNT.Weapons._registry.item_lmnt_energieschild.shopDefaults.lockSeconds, 20, "Energieschild-Sperrzeit")
	end)
end)

-- Ab hier braucht es das Modul ttt.items
if not (LMNT.TTT and LMNT.TTT.Leisetreter and LMNT.TTT.Adrenalin and LMNT.TTT.Explosionsschutz
	and LMNT.TTT.Energieschild and LMNT.TTT.Lebenszeichen) then
	T.Describe("Neue Items – Wirkung", function(t)
		t:It("Modul ttt.items ist geladen", function(e)
			e:True(false, "Wirkungen fehlen – Modul ttt.items ist aus oder nicht gestartet (!modules)")
		end)
	end)
	return
end

T.Describe("Neue Items – Leisetreter", function(t)
	local L = LMNT.TTT.Leisetreter
	local function fake(hat, lebt)
		return { HasEquipmentItem = function(_, c) return hat and c == L.class end, Alive = function() return lebt end }
	end

	t:It("stumm nur mit Item und lebend", function(e)
		e:True(L.IstStumm(fake(true, true)))
		e:False(L.IstStumm(fake(false, true)), "ohne Item")
		e:False(L.IstStumm(fake(true, false)), "tot")
		e:False(L.IstStumm(nil), "nil")
	end)
	t:It("PlayerFootstep-Hook ist registriert", function(e)
		e:True(isfunction((hook.GetTable().PlayerFootstep or {})["LMNT.TTT.Leisetreter"]))
	end)
end)

T.Describe("Neue Items – Adrenalin", function(t)
	local A = LMNT.TTT.Adrenalin

	t:It("löst nur bei 1..30 HP und nur einmal aus", function(e)
		e:True(A.SollAusloesen(30, false), "30 HP")
		e:True(A.SollAusloesen(1, nil), "1 HP")
		e:False(A.SollAusloesen(31, false), "31 HP")
		e:False(A.SollAusloesen(0, false), "tot")
		e:False(A.SollAusloesen(-5, false), "negativ")
		e:False(A.SollAusloesen(10, true), "schon benutzt")
	end)
	t:It("Heilung +30, gedeckelt auf das Maximum, nie Verlust", function(e)
		e:Equal(A.NeueGesundheit(10, 100), 40)
		e:Equal(A.NeueGesundheit(20, 40), 40, "Deckel")
		e:Equal(A.NeueGesundheit(120, 100), 120, "über Maximum bleibt")
	end)
	t:It("Tempo-Schub läuft ab und ist als Speed-Modifikator eingetragen", function(e)
		e:True(A.TempoAktiv({ lmntAdrenalinBis = 10 }, 5))
		e:False(A.TempoAktiv({ lmntAdrenalinBis = 10 }, 10), "abgelaufen")
		e:False(A.TempoAktiv({}, 5), "nie ausgelöst")
		local mod = LMNT.TTT.SpeedMods.item_lmnt_adrenalin
		e:True(isfunction(mod), "SpeedMod fehlt")
		e:Equal(mod({ lmntAdrenalinBis = CurTime() + 5 }), A.tempo)
		e:Equal(mod({}), nil)
	end)
	t:It("Hook und Net-Nachricht registriert", function(e)
		e:True(isfunction((hook.GetTable().PostEntityTakeDamage or {})["LMNT.TTT.Adrenalin"]))
		e:True(util.NetworkStringToID(A.net) ~= 0)
	end)
end)

T.Describe("Neue Items – Explosionsschutz", function(t)
	local X = LMNT.TTT.Explosionsschutz

	t:It("Explosion und Feuer halbiert, anderes unverändert", function(e)
		e:Equal(X.Faktor(DMG_BLAST), 0.5, "Explosion")
		e:Equal(X.Faktor(DMG_BURN), 0.5, "Feuer")
		e:Equal(X.Faktor(DMG_SLOWBURN), 0.5, "Schwelbrand")
		e:Equal(X.Faktor(bit.bor(DMG_BLAST, DMG_BULLET)), 0.5, "gemischt")
		e:Equal(X.Faktor(DMG_BULLET), 1, "Kugel")
		e:Equal(X.Faktor(DMG_FALL), 1, "Fall")
		e:Equal(X.Faktor(nil), 1, "nil")
	end)
	t:It("EntityTakeDamage-Hook ist registriert", function(e)
		e:True(isfunction((hook.GetTable().EntityTakeDamage or {})["LMNT.TTT.Explosionsschutz"]))
	end)
end)

T.Describe("Neue Items – Energieschild", function(t)
	local S = LMNT.TTT.Energieschild

	t:It("Schaden wird vom Vorrat abgezogen", function(e)
		local rest, vorrat = S.Absorbiere(40, 25)
		e:Equal(rest, 0)
		e:Equal(vorrat, 15)
		rest, vorrat = S.Absorbiere(15, 30)
		e:Equal(rest, 15, "Durchschlag")
		e:Equal(vorrat, 0, "leer")
		rest, vorrat = S.Absorbiere(40, 0)
		e:Equal(rest, 0)
		e:Equal(vorrat, 40, "kein Schaden")
		rest, vorrat = S.Absorbiere(40, -10)
		e:Equal(rest, 0, "negativer Schaden heilt nicht")
		e:Equal(vorrat, 40)
	end)
	t:It("Fall und Ertrinken gehen vorbei", function(e)
		e:False(S.FaengtAb(DMG_FALL))
		e:False(S.FaengtAb(DMG_DROWN))
		e:True(S.FaengtAb(DMG_BULLET))
		e:True(S.FaengtAb(DMG_BLAST))
	end)
	t:It("Hook und Net-Nachricht registriert", function(e)
		e:True(isfunction((hook.GetTable().EntityTakeDamage or {})["LMNT.TTT.Energieschild"]))
		e:True(util.NetworkStringToID(S.net) ~= 0)
	end)
end)

T.Describe("Neue Items – Lebenszeichen-Monitor", function(t)
	local L = LMNT.TTT.Lebenszeichen

	t:It("Entfernung auf 5 m gerundet, mindestens 5 m", function(e)
		e:Equal(L.Meter(0), 5)
		e:Equal(L.Meter(262.5), 5, "5 m")
		e:Equal(L.Meter(787.4), 15, "15 m")
		e:Equal(L.Meter(2400), 45, "Reichweitengrenze")
	end)
	t:It("Reichweite 2400 Einheiten", function(e)
		e:True(L.InReichweite(2400 * 2400))
		e:False(L.InReichweite(2401 * 2401))
		e:False(L.InReichweite(nil), "nil")
	end)
	t:It("Net-Nachricht registriert", function(e)
		e:True(util.NetworkStringToID(L.net) ~= 0)
	end)
end)
