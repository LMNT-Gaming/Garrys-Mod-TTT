-- LMNT Unit-Tests: Weapon Registry und Shop-Regeln (T-112, T-035)
local T = LMNT.Test

-- pairs() überspringt nil-Werte; "fehlt" wird deshalb mit dem Platzhalter NIL ausgedrückt
local NIL = {}
local function ctx(over)
	local c = { class = "weapon_test", registered = true, enabled = true, lockSeconds = 0, maxPerRound = 0,
		boughtThisRound = 0, roundElapsed = 100, blocked = {} }
	for k, v in pairs(over or {}) do
		if v == NIL then c[k] = nil else c[k] = v end
	end
	return c
end

T.Describe("Shop-Regeln", function(t)
	t:It("erlaubt standardmäßig", function(e)
		e:True(LMNT.Shop.Evaluate(ctx()))
	end)
	t:It("deaktivierte Klasse wird gesperrt", function(e)
		local ok, reason = LMNT.Shop.Evaluate(ctx({ enabled = false }))
		e:False(ok)
		e:True(string.find(reason, "deaktiviert", 1, true) ~= nil)
	end)
	t:It("Map- bzw. Server-Sperrliste gilt auch für nicht registrierte Klassen", function(e)
		e:False(LMNT.Shop.Evaluate(ctx({ registered = false, blocked = { weapon_test = true } })))
	end)
	t:It("Sperrzeit ab Rundenbeginn", function(e)
		local ok, reason = LMNT.Shop.Evaluate(ctx({ lockSeconds = 30, roundElapsed = 10 }))
		e:False(ok)
		e:True(string.find(reason, "20 s", 1, true) ~= nil, "Restzeit im Grund: " .. tostring(reason))
		e:True(LMNT.Shop.Evaluate(ctx({ lockSeconds = 30, roundElapsed = 31 })))
		e:False(LMNT.Shop.Evaluate(ctx({ lockSeconds = 30, roundElapsed = NIL })), "ohne laufende Runde gesperrt")
	end)
	t:It("Limit pro Runde", function(e)
		e:True(LMNT.Shop.Evaluate(ctx({ maxPerRound = 2, boughtThisRound = 1 })))
		e:False(LMNT.Shop.Evaluate(ctx({ maxPerRound = 2, boughtThisRound = 2 })))
		e:True(LMNT.Shop.Evaluate(ctx({ maxPerRound = 0, boughtThisRound = 99 })), "0 = unbegrenzt")
	end)
	t:It("nicht registrierte Klassen: LMNT-Klassenregeln greifen nicht", function(e)
		e:True(LMNT.Shop.Evaluate(ctx({ registered = false, enabled = false, maxPerRound = 1, boughtThisRound = 5 })))
	end)
	t:It("eigene Regel kann sperren, fehlerhafte Regel sperrt zur Sicherheit", function(e)
		LMNT.Shop.AddRule("lmnt.test.rule", function(c) if c.class == "weapon_verboten" then return false, "Testgrund" end end)
		local ok, reason = LMNT.Shop.Evaluate(ctx({ class = "weapon_verboten" }))
		e:False(ok)
		e:Equal(reason, "Testgrund")
		LMNT.Shop.AddRule("lmnt.test.rule", function() error("kaputt") end)
		e:False(LMNT.Shop.Evaluate(ctx()), "Fehler in Regel = sperren")
		for i = #LMNT.Shop._rules, 1, -1 do
			if LMNT.Shop._rules[i].id == "lmnt.test.rule" then table.remove(LMNT.Shop._rules, i) end
		end
	end)
	t:It("Rückgabe des Hooks: bei Erlaubnis nichts (andere Addons laufen weiter)", function(e)
		local hooks = hook.GetTable().TTT2CanOrderEquipment or {}
		e:True(hooks["LMNT.Shop.Rules"] ~= nil, "Hook angebunden")
	end)
end)

T.Describe("Weapon Registry", function(t)
	t:It("LMNT-Ausrüstung ist registriert und TTT2-kompatibel", function(e)
		for _, class in ipairs({ "weapon_lmnt_taser", "weapon_lmnt_giftpfeil", "weapon_lmnt_revolver", "item_lmnt_turbo" }) do
			e:True(LMNT.Weapons._registry[class] ~= nil, class .. " registriert")
			local status = LMNT.Weapons.Check(class)
			e:Equal(status, "ttt2", class)
		end
	end)
	t:It("TTT2-Standardwaffe wird erkannt, ohne registriert zu sein", function(e)
		LMNT.Weapons.Discover()
		local v = LMNT.Weapons.Get("weapon_ttt_c4")
		e:False(v.registered)
		e:Equal(v.compatibilityStatus, "ttt2")
		e:True(v.ttt2 ~= nil and #v.ttt2.roles > 0, "Kaufrollen aus TTT2 gelesen")
	end)
	t:It("unbekannte Klasse = nicht geladen, kein Absturz", function(e)
		e:Equal(LMNT.Weapons.Check("weapon_gibt_es_nicht"), "nicht geladen")
		e:NoError(function() LMNT.Weapons.Get("weapon_gibt_es_nicht") end)
	end)
	t:It("zweite Quelle für dieselbe Klasse wird abgelehnt", function(e)
		local entry, err = LMNT.Weapons.Register("weapon_lmnt_taser", { sourceAddon = "fremdes_addon" })
		e:True(entry == nil and err ~= nil)
		e:Equal(LMNT.Weapons._registry.weapon_lmnt_taser.sourceAddon, "lmnt_ttt", "Original bleibt")
	end)
	t:It("Einstellungen pro Klasse existieren", function(e)
		e:Equal(LMNT.Settings.Get("shop.weapon_lmnt_giftpfeil.lock_seconds"), 30)
		e:Equal(LMNT.Settings.Get("shop.weapon_lmnt_taser.max_per_round"), 1)
	end)
end)
