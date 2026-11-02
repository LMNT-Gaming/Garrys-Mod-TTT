-- LMNT Unit-Tests: Modul ttt.pointshop (Preise, Tagesangebot, Kaufprüfung, Transaktionen, Sperre)
-- Datenbank-Tests laufen mit einer erfundenen SteamID64 gegen die echten Tabellen
-- (lmnt_ttt_stats, lmnt_ps_inventory) und räumen vorher und nachher auf.
local T = LMNT.Test

if not (LMNT.TTT and LMNT.TTT.Pointshop and LMNT.TTT.Pointshop.ExecuteBuy) then
	T.Describe("Pointshop", function(t)
		t:It("Modul ttt.pointshop ist geladen", function(e)
			e:True(false, "LMNT.TTT.Pointshop fehlt – Modul ttt.pointshop ist aus oder nicht gestartet (!modules)")
		end)
	end)
	return
end

local PS = LMNT.TTT.Pointshop

-- SteamID64 unterhalb von 76561197960265728 gehören zu keinem echten Steam-Konto
local SID = "76561190000000201"
local GHOST = "76561190000000202"    -- hat absichtlich keine Zeile in lmnt_ttt_stats

-- Erfundene Items nur für die reinen Funktionen
local ITEM = { id = "test_item", name = "Testitem", category = "hat", rarity = "common", price = 400 }
local VIP_ITEM = { id = "test_vip", name = "VIP-Testitem", category = "hat", rarity = "epic", price = 1000, vip = true }
local CHEAP = { id = "test_cheap", name = "Billig", category = "hat", rarity = "common", price = 1 }

------------------------------------------------------------------------
-- Hilfen für Datenbank-Tests
------------------------------------------------------------------------

local function cleanup()
	LMNT.DB.Query("DELETE FROM lmnt_ps_inventory WHERE steamid = ? OR steamid = ?", SID, GHOST)
	LMNT.DB.Query("DELETE FROM lmnt_ttt_stats WHERE steamid = ? OR steamid = ?", SID, GHOST)
end

local function dbPoints(sid)
	return tonumber(LMNT.DB.Value("SELECT points FROM lmnt_ttt_stats WHERE steamid = ?", sid or SID))
end

local function owns(id, sid)
	return tonumber(LMNT.DB.Value("SELECT COUNT(*) FROM lmnt_ps_inventory WHERE steamid = ? AND item = ?", sid or SID, id)) == 1
end

-- Testspieler mit Punktestand anlegen, fn ausführen, immer aufräumen
local function withFixture(points, fn)
	cleanup()
	LMNT.DB.Query("INSERT INTO lmnt_ttt_stats (steamid, name, points, last_seen) VALUES (?, ?, ?, ?)", SID, "LMNT-Test", points, os.time())
	local ok, err = pcall(fn)
	cleanup()
	if not ok then error(err, 0) end
end

------------------------------------------------------------------------
-- Preise
------------------------------------------------------------------------

T.Describe("Pointshop.Preise", function(t)
	t:It("Basispreis nur als positive ganze Zahl", function(e)
		e:Equal(PS.BasePrice(ITEM), 400)
		e:Equal(PS.BasePrice({ price = 0 }), nil, "0")
		e:Equal(PS.BasePrice({ price = -50 }), nil, "negativ")
		e:Equal(PS.BasePrice({ price = 12.5 }), nil, "Komma")
		e:Equal(PS.BasePrice({ price = 0 / 0 }), nil, "NaN")
		e:Equal(PS.BasePrice({ price = math.huge }), nil, "unendlich")
		e:Equal(PS.BasePrice({ price = "400" }), nil, "Text")
		e:Equal(PS.BasePrice(nil), nil, "kein Item")
	end)
	t:It("ohne Tagesangebot gilt der Basispreis", function(e)
		e:Equal(PS.ComputePrice(ITEM, false, 25), 400)
		e:Equal(PS.ComputePrice(ITEM, false, 90), 400, "Rabatt wirkt nur auf das Tagesangebot")
	end)
	t:It("Tagesangebot: Rabatt abgerundet, mindestens 1 Punkt", function(e)
		e:Equal(PS.ComputePrice(ITEM, true, 25), 300)
		e:Equal(PS.ComputePrice({ price = 333 }, true, 10), 299, "299,7 -> 299")
		e:Equal(PS.ComputePrice(CHEAP, true, 90), 1, "nie 0")
		e:Equal(PS.ComputePrice(ITEM, true, 0), 400, "Rabatt 0")
	end)
	t:It("Rabatt wird auf 0–90 % begrenzt, Unsinn = 0", function(e)
		e:Equal(PS.ComputePrice(ITEM, true, 150), 40, "150 % -> 90 %")
		e:Equal(PS.ComputePrice(ITEM, true, -20), 400, "negativ -> 0 %")
		e:Equal(PS.ComputePrice(ITEM, true, 0 / 0), 400, "NaN -> 0 %")
		e:Equal(PS.ComputePrice(ITEM, true, "25"), 400, "Text -> 0 %")
		e:Equal(PS.ClampDiscount(33.9), 33, "abgerundet")
	end)
	t:It("ungültiges Item hat keinen Preis (nicht kaufbar)", function(e)
		e:Equal(PS.ComputePrice({ price = -1 }, true, 25), nil)
		e:Equal(PS.ComputePrice(nil, false, 0), nil)
	end)
	t:It("Erstattung: Anteil vom bezahlten Preis, höchstens vom Basispreis", function(e)
		e:Equal(PS.ComputeRefund(ITEM, nil, 0.5), 200, "Altbestand ohne Preis")
		e:Equal(PS.ComputeRefund(ITEM, 300, 0.5), 150, "im Angebot gekauft")
		e:Equal(PS.ComputeRefund(ITEM, 9999, 0.5), 200, "höherer Preis zählt nicht")
		e:Equal(PS.ComputeRefund(ITEM, -5, 0.5), 200, "ungültiger Preis -> Basispreis")
		e:Equal(PS.ComputeRefund(ITEM, 300, 5), 300, "Faktor auf 1 begrenzt")
		e:Equal(PS.ComputeRefund({ price = 0 }, 300, 0.5), 0, "ungültiges Item")
	end)
	t:It("Kauf im Angebot + Verkauf bringt nie Gewinn (alle Items, alle Rabatte)", function(e)
		for id, item in pairs(LMNT.TTT.Shop) do
			for d = 0, PS.MaxDiscount, 5 do
				local paid = PS.ComputePrice(item, true, d)
				e:True(PS.ComputeRefund(item, paid, LMNT.TTT.ShopSellFactor) <= paid, id .. " bei " .. d .. " %")
			end
		end
	end)
end)

------------------------------------------------------------------------
-- Tagesangebot
------------------------------------------------------------------------

T.Describe("Pointshop.Tagesangebot", function(t)
	local catalog = { a = { price = 100 }, b = { price = 200 }, c = { price = 300 }, v = { price = 400, vip = true }, x = { price = 0 } }

	t:It("gleicher Tag -> gleiches Item", function(e)
		e:Equal(PS.PickDaily("2026-10-18", catalog), PS.PickDaily("2026-10-18", catalog))
		e:Equal(PS.PickDaily("2026-10-18"), PS.PickDaily("2026-10-18"), "echter Katalog")
	end)
	t:It("unabhängig von der Einfügereihenfolge des Katalogs", function(e)
		local reversed = {}
		for _, k in ipairs({ "x", "v", "c", "b", "a" }) do reversed[k] = catalog[k] end
		for day = 1, 28 do
			local key = string.format("2026-02-%02d", day)
			e:Equal(PS.PickDaily(key, reversed), PS.PickDaily(key, catalog), key)
		end
	end)
	t:It("nur kaufbare Nicht-VIP-Items, über Tage verteilt", function(e)
		local seen = {}
		for day = 1, 31 do
			local id = PS.PickDaily(string.format("2026-03-%02d", day), catalog)
			e:True(id == "a" or id == "b" or id == "c", "Tag " .. day .. ": " .. tostring(id))
			seen[id] = true
		end
		e:True(table.Count(seen) >= 2, "mehr als ein Item in 31 Tagen")
		for _, id in ipairs(PS.DailyCandidates()) do
			e:False(LMNT.TTT.Shop[id].vip, id .. " ist VIP")
		end
	end)
	t:It("leerer Katalog -> kein Angebot", function(e)
		e:Equal(PS.PickDaily("2026-10-18", {}), nil)
	end)
	t:It("Tagesschlüssel im Format JJJJ-MM-TT", function(e)
		e:True(string.match(PS.DayKey(0), "^%d%d%d%d%-%d%d%-%d%d$") ~= nil)
	end)
	t:It("Serverpreis folgt der Einstellung (nur das Tagesangebot ist reduziert)", function(e)
		local daily, discount = PS.CurrentDaily()
		e:Equal(discount, PS.ClampDiscount(LMNT.Settings.Get("ttt.pointshop.daily_discount")))
		for id, item in pairs(LMNT.TTT.Shop) do
			local expected = PS.ComputePrice(item, id == daily, discount)
			e:Equal(PS.PriceFor(id), expected, id)
		end
		e:Equal(PS.PriceFor("gibt_es_nicht"), nil, "unbekanntes Item")
	end)
end)

------------------------------------------------------------------------
-- Katalog
------------------------------------------------------------------------

T.Describe("Pointshop.Katalog", function(t)
	t:It("jeder Eintrag: Seltenheit, Preisband, Titel, Effekt", function(e)
		local problems = PS.ValidateCatalog()
		e:Equal(#problems, 0, table.concat(problems, "; "))
	end)
	t:It("fehlerhafte Einträge werden erkannt", function(e)
		local problems = PS.ValidateCatalog({
			a = { rarity = "mythisch", price = 100 },
			b = { rarity = "legendary", price = 100 },
			c = { rarity = "common", price = 200, category = "title", title = string.rep("x", 40) },
			d = { rarity = "common", price = 200, category = "deathfx", effect = { kind = "blut" } },
		})
		e:Equal(#problems, 4, table.concat(problems, "; "))
	end)
end)

------------------------------------------------------------------------
-- Kaufprüfung
------------------------------------------------------------------------

T.Describe("Pointshop.Kaufprüfung", function(t)
	-- pairs() überspringt nil-Werte; "fehlt" wird deshalb mit dem Platzhalter NIL ausgedrückt
	local NIL = {}
	local function check(over)
		local ctx = { item = ITEM, owned = false, isVip = false, points = 1000, price = 400 }
		for k, v in pairs(over or {}) do
			if v == NIL then ctx[k] = nil else ctx[k] = v end
		end
		local ok, code = PS.CheckBuy(ctx)
		return ok and "ok" or code
	end

	t:It("gültiger Kauf", function(e)
		e:Equal(check(), "ok")
		e:Equal(check({ points = 400 }), "ok", "genau passend")
		e:Equal(check({ expected = 400 }), "ok", "bestätigter Preis stimmt")
	end)
	t:It("Doppelkauf wird abgelehnt", function(e)
		e:Equal(check({ owned = true }), "owned")
	end)
	t:It("zu wenig Punkte", function(e)
		e:Equal(check({ points = 399 }), "points")
		e:Equal(check({ points = 0 }), "points")
		local _, _, msg = PS.CheckBuy({ item = ITEM, owned = false, isVip = false, points = 150, price = 400 })
		e:True(string.find(msg, "250", 1, true) ~= nil, "Meldung nennt die Differenz")
	end)
	t:It("VIP-Item nur mit VIP-Recht", function(e)
		e:Equal(check({ item = VIP_ITEM, price = 1000, isVip = false }), "vip")
		e:Equal(check({ item = VIP_ITEM, price = 1000, isVip = true }), "ok")
	end)
	t:It("unbekanntes Item", function(e)
		e:Equal(check({ item = false }), "unknown")
	end)
	t:It("Preis muss serverseitig berechnet, ganzzahlig und > 0 sein", function(e)
		e:Equal(check({ price = NIL }), "price")
		e:Equal(check({ price = 0 }), "price")
		e:Equal(check({ price = -100 }), "price")
		e:Equal(check({ price = 12.5 }), "price")
	end)
	t:It("geänderter Preis (z. B. Tageswechsel) wird nicht stillschweigend abgebucht", function(e)
		e:Equal(check({ expected = 300 }), "changed")
	end)
	t:It("Reihenfolge: Besitz vor VIP vor Preis vor Punkten", function(e)
		e:Equal(check({ owned = true, points = 0 }), "owned")
		e:Equal(check({ item = VIP_ITEM, price = 0, points = 0 }), "vip")
		e:Equal(check({ price = 0, points = 0 }), "price")
	end)
	t:It("Verkaufsprüfung", function(e)
		e:True(PS.CheckSell({ item = ITEM, owned = true }))
		e:False(PS.CheckSell({ item = ITEM, owned = false }), "nicht im Besitz")
		e:False(PS.CheckSell({ item = nil, owned = true }), "unbekannt")
	end)
end)

------------------------------------------------------------------------
-- Transaktionen (echte Datenbank)
------------------------------------------------------------------------

T.Describe("Pointshop.Transaktion", function(t)
	t:It("Kauf schreibt Punkte und Inventar (mit bezahltem Preis)", function(e)
		withFixture(1000, function()
			local ok, newPoints = PS.ExecuteBuy(SID, "hat_cone", 300, 1000)
			e:True(ok, "Kauf erfolgreich")
			e:Equal(newPoints, 700)
			e:Equal(dbPoints(), 700, "Punkte in der DB")
			e:True(owns("hat_cone"), "Inventarzeile")
			e:Equal(tonumber(LMNT.DB.Value("SELECT paid FROM lmnt_ps_inventory WHERE steamid = ? AND item = ?", SID, "hat_cone")), 300, "bezahlter Preis")
		end)
	end)
	t:It("Doppelkauf auf Datenbankebene: Punkte werden zurückgerollt", function(e)
		withFixture(1000, function()
			e:True((PS.ExecuteBuy(SID, "hat_cone", 300, 1000)), "erster Kauf")
			local ok = PS.ExecuteBuy(SID, "hat_cone", 300, 700)
			e:False(ok, "zweiter Kauf scheitert am Primärschlüssel")
			e:Equal(dbPoints(), 700, "kein zweiter Abzug")
		end)
	end)
	t:It("Fehler nach dem Inventar-Schritt -> alles zurückgerollt", function(e)
		withFixture(1000, function()
			local ok, err = PS.ExecuteBuy(SID, "hat_cone", 300, 1000, { failAfter = "inventory" })
			e:False(ok, "Kauf gescheitert")
			e:True(isstring(err) and err ~= "", "Fehlermeldung")
			e:Equal(dbPoints(), 1000, "Punkte unverändert")
			e:False(owns("hat_cone"), "keine Inventarzeile")
		end)
	end)
	t:It("Fehler nach dem Punkte-Schritt -> Punkte zurückgerollt", function(e)
		withFixture(1000, function()
			e:False((PS.ExecuteBuy(SID, "hat_cone", 300, 1000, { failAfter = "points" })))
			e:Equal(dbPoints(), 1000)
			e:False(owns("hat_cone"))
		end)
	end)
	t:It("zu wenig Punkte oder ungültiger Preis -> keine Datenbankänderung", function(e)
		withFixture(100, function()
			e:False((PS.ExecuteBuy(SID, "hat_cone", 300, 100)), "zu wenig Punkte")
			e:False((PS.ExecuteBuy(SID, "hat_cone", 0, 100)), "Preis 0")
			e:False((PS.ExecuteBuy(SID, "hat_cone", -5, 100)), "negativer Preis")
			e:Equal(dbPoints(), 100)
			e:False(owns("hat_cone"))
		end)
	end)
	t:It("Spieler ohne Statistikzeile: kein Item ohne Abbuchung", function(e)
		withFixture(1000, function()
			e:False((PS.ExecuteBuy(GHOST, "hat_cone", 300, 1000)))
			e:False(owns("hat_cone", GHOST), "keine Inventarzeile")
		end)
	end)
	t:It("Verkauf löscht Inventar und schreibt Erstattung gut", function(e)
		withFixture(1000, function()
			PS.ExecuteBuy(SID, "hat_cone", 300, 1000)
			local ok, newPoints = PS.ExecuteSell(SID, "hat_cone", 150, 700)
			e:True(ok)
			e:Equal(newPoints, 850)
			e:Equal(dbPoints(), 850)
			e:False(owns("hat_cone"))
		end)
	end)
	t:It("Verkauf ohne Besitz -> keine Gutschrift", function(e)
		withFixture(1000, function()
			e:False((PS.ExecuteSell(SID, "hat_cone", 150, 1000)))
			e:Equal(dbPoints(), 1000)
		end)
	end)
	t:It("Fehler beim Verkauf -> Item bleibt, keine Gutschrift", function(e)
		withFixture(1000, function()
			PS.ExecuteBuy(SID, "hat_cone", 300, 1000)
			e:False((PS.ExecuteSell(SID, "hat_cone", 150, 700, { failAfter = "points" })))
			e:Equal(dbPoints(), 700)
			e:True(owns("hat_cone"), "Item noch im Besitz")
			e:False((PS.ExecuteSell(SID, "hat_cone", -1, 700)), "negative Erstattung")
		end)
	end)
	t:It("Ausrüsten tauscht innerhalb der Kategorie", function(e)
		withFixture(2000, function()
			PS.ExecuteBuy(SID, "hat_cone", 300, 2000)
			PS.ExecuteBuy(SID, "hat_melon", 250, 1700)
			e:True((PS.ExecuteEquip(SID, "hat_cone", true)))
			e:True((PS.ExecuteEquip(SID, "hat_melon", true, "hat_cone")))
			local function equipped(id)
				return tonumber(LMNT.DB.Value("SELECT equipped FROM lmnt_ps_inventory WHERE steamid = ? AND item = ?", SID, id))
			end
			e:Equal(equipped("hat_cone"), 0)
			e:Equal(equipped("hat_melon"), 1)
			e:False((PS.ExecuteEquip(SID, "hat_pot", true)), "nicht im Besitz")
		end)
	end)
	t:It("innerhalb einer fremden Transaktion verweigert", function(e)
		withFixture(1000, function()
			local inner
			LMNT.DB.Transaction(function() inner = { PS.ExecuteBuy(SID, "hat_cone", 300, 1000) } end)
			e:False(inner[1])
			e:Equal(dbPoints(), 1000)
			e:False(owns("hat_cone"))
		end)
	end)
end)

------------------------------------------------------------------------
-- In-Flight-Sperre
------------------------------------------------------------------------

T.Describe("Pointshop.Sperre", function(t)
	t:It("zweite Aktion während der ersten wird abgewiesen", function(e)
		local innerOk, innerCode
		local ok, result = PS.WithLock(SID, function()
			innerOk, innerCode = PS.WithLock(SID, function() return "zweite" end)
			return "erste"
		end)
		e:True(ok)
		e:Equal(result, "erste")
		e:False(innerOk, "verschachtelt")
		e:Equal(innerCode, "busy")
		e:False(PS.IsBusy(SID), "nach Ende freigegeben")
	end)
	t:It("andere Spieler sind nicht betroffen", function(e)
		local other
		PS.WithLock(SID, function() other = PS.WithLock(GHOST, function() return true end) end)
		e:True(other)
	end)
	t:It("Fehler in der Aktion gibt die Sperre frei", function(e)
		local ok, code = PS.WithLock(SID, function() error("Testfehler (erwartet)") end)
		e:False(ok)
		e:Equal(code, "error")
		e:False(PS.IsBusy(SID))
	end)
end)
