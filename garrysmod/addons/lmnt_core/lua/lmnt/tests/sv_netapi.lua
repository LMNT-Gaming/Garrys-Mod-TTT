-- LMNT Unit-Tests: Netzwerk-Dienst LMNT.Net (T-030, T-092) – Schema, Rate-Limiter, Verstöße, Registrierung
-- Echte Übertragung ist im Unit-Test nicht möglich. Geprüft werden die Bausteine: NewBuffer ersetzt die
-- net-Bibliothek, eigene Registries und eine Guard-Instanz mit Test-Umgebung (kein Log, kein Kick, kein
-- Netzwerkstring) verändern den laufenden Server nicht.
local T = LMNT.Test
local N = LMNT.Net

-- Puffer mit rohen (auch manipulierten) Werten, wie sie ein veränderter Client senden könnte
local function raw(fill)
	local buf = N.NewBuffer()
	fill(buf)
	return buf
end

local function roundtrip(schema, data)
	local spec = N.CompileSchema(schema)
	local buf = N.NewBuffer()
	local bits = N.Encode(spec, data, buf)
	return N.Decode(spec, buf, bits), bits, buf
end

-- Ersatz für Spieler/Entities: IsValid() von GMod ruft die Methode IsValid der Tabelle auf
local function fakeEnt(key, isPlayer, class)
	return {
		key = key,
		IsValid = function() return true end,
		IsPlayer = function() return isPlayer == true end,
		EntIndex = function() return 1 end,
		GetClass = function() return class or (isPlayer and "player" or "prop_physics") end,
	}
end

-- Test-Umgebung für den Guard: Zeit, Rechte, Schwelle und Verfall sind steuerbar, Seiteneffekte werden gesammelt
local function newEnv()
	local env = { time = 0, limit = 20, decayRate = 0, perms = {}, logs = {}, events = {}, kicks = {} }
	env.now = function() return env.time end
	env.key = function(ply) return ply.key end
	env.name = function(ply) return ply.key end
	env.hasPerm = function(_, perm) return env.perms[perm] == true end
	env.threshold = function() return env.limit end
	env.decay = function() return env.decayRate end
	env.log = function(text) env.logs[#env.logs + 1] = text end
	env.emit = function(_, name, code) env.events[#env.events + 1] = name .. ":" .. code end
	env.kick = function(_, text) env.kicks[#env.kicks + 1] = text end
	return env
end

local function testMsg(def)
	return N.NewRegistry():Register("lmnt_test_net", def)
end

T.Describe("Net.Schema", function(t)
	t:It("lehnt ungültige Schemas ab", function(e)
		local bad = {
			{ { name = "s", type = "string" } },                                        -- string ohne max
			{ { name = "s", type = "string", max = 70000 } },                           -- über der 64-KB-Grenze
			{ { name = "s", type = "string", max = 8, maxLength = 8 } },                -- Tippfehler im Schlüssel
			{ { name = "s", type = "string", max = 8, pattern = "[" } },                -- kaputtes Muster
			{ { name = "u", type = "uint" } },                                          -- weder bits noch max
			{ { name = "u", type = "uint", bits = 33 } },
			{ { name = "u", type = "uint", bits = 8, max = 300 } },                     -- max passt nicht in bits
			{ { name = "u", type = "uint", bits = 8, min = 5, max = 1 } },
			{ { name = "u", type = "uint", bits = 8, min = -1 } },
			{ { name = "i", type = "int", bits = 8, min = -200 } },
			{ { name = "f", type = "float" } },                                         -- float ohne Grenzen
			{ { name = "f", type = "float", min = 0, max = math.huge } },
			{ { name = "x", type = "table" } },                                         -- table gibt es bewusst nicht
			{ { name = "a", type = "bool" }, { name = "a", type = "bool" } },          -- doppelter Name
			{ { type = "bool" } },                                                      -- Name fehlt
			{ { name = "mit leerzeichen", type = "bool" } },
			{ { name = "l", type = "list", of = { type = "bool" } } },                  -- Liste ohne max
			{ { name = "l", type = "list", max = 4 } },                                 -- Liste ohne of
			{ { name = "l", type = "list", max = 4, of = { type = "bool", optional = true } } },
			{ { name = "l", type = "list", max = 2, of = { type = "list", max = 2, of = { type = "list", max = 2, of = { type = "bool" } } } } },
			{ [1] = { name = "a", type = "bool" }, [3] = { name = "b", type = "bool" } }, -- Lücke
		}
		for i, schema in ipairs(bad) do
			e:Error(function() N.CompileSchema(schema) end, "ungültiges Schema " .. i)
		end
	end)

	t:It("berechnet Bitgrößen und leitet bits aus den Grenzen ab", function(e)
		local spec = N.CompileSchema({
			{ name = "id", type = "string", max = 64 },
			{ name = "anzahl", type = "uint", bits = 8, min = 0, max = 200 },
			{ name = "an", type = "bool" },
			{ name = "grund", type = "string", max = 10, optional = true },
		})
		e:Equal(spec.minBits, 8 + 8 + 1 + 1, "kleinstes Paket")
		e:Equal(spec.maxBits, 65 * 8 + 8 + 1 + 1 + 11 * 8, "größtes Paket")

		e:Equal(N.CompileSchema({ { name = "u", type = "uint", max = 200 } }).fields[1].bits, 8, "uint max 200 -> 8 Bit")
		e:Equal(N.CompileSchema({ { name = "i", type = "int", min = -5, max = 5 } }).fields[1].bits, 4, "int -5..5 -> 4 Bit")
		e:Equal(N.CompileSchema({ { name = "f", type = "float", min = 0, max = 1 } }).fields[1].bits, 32, "float = 32 Bit")
		e:Equal(N.CompileSchema({ { name = "p", type = "player" } }).fields[1].bits, MAX_PLAYER_BITS, "player = MAX_PLAYER_BITS")
		e:Equal(N.CompileSchema({ { name = "x", type = "entity" } }).fields[1].bits, MAX_EDICT_BITS, "entity = MAX_EDICT_BITS")
	end)

	t:It("Validate prüft Typen und Grenzen beim Senden", function(e)
		local spec = N.CompileSchema({
			{ name = "id", type = "string", max = 8 },
			{ name = "anzahl", type = "uint", bits = 8, min = 1, max = 200 },
			{ name = "delta", type = "int", bits = 8, min = -10, max = 10 },
			{ name = "faktor", type = "float", min = 0, max = 1 },
			{ name = "an", type = "bool" },
		})
		local good = { id = "abc", anzahl = 5, delta = -3, faktor = 0.5, an = false }
		local ok, bits = N.Validate(spec, good)
		e:True(ok, "gültige Daten")
		e:Equal(bits, 4 * 8 + 8 + 8 + 32 + 1, "Bits")

		local function with(k, v)
			local d = table.Copy(good)
			d[k] = v
			return d
		end
		local cases = {
			{ "id", "123456789", "Text zu lang" }, { "id", 5, "Zahl statt Text" }, { "id", "a\0b", "Nullbyte" },
			{ "anzahl", 0, "unter min" }, { "anzahl", 201, "über max" }, { "anzahl", 2.5, "keine ganze Zahl" },
			{ "anzahl", "5", "Text statt Zahl" }, { "delta", -11, "int unter min" }, { "faktor", 0 / 0, "NaN" },
			{ "faktor", math.huge, "unendlich" }, { "faktor", 1.5, "float über max" }, { "an", "ja", "Text statt bool" },
			{ "an", nil, "Pflichtfeld fehlt" }, { "extra", 1, "unbekanntes Feld" },
		}
		for _, c in ipairs(cases) do
			e:False(N.Validate(spec, with(c[1], c[2])), c[3])
		end

		local _, why, path = N.Validate(spec, with("anzahl", 201))
		e:Equal(path, "anzahl", "Pfad des Fehlers")
		e:True(isstring(why) and why ~= "", "Grund vorhanden")
		e:Error(function() N.Encode(spec, with("anzahl", 201), N.NewBuffer()) end, "Encode mit ungültigen Daten")
	end)

	t:It("Roundtrip mit Liste, Record und optionalen Feldern", function(e)
		local data, bits, buf = roundtrip({
			{ name = "titel", type = "string", max = 32 },
			{ name = "eintraege", type = "list", max = 4, of = { type = "record", fields = {
				{ name = "id", type = "uint", bits = 10 },
				{ name = "text", type = "string", max = 16, optional = true },
			} } },
			{ name = "zahlen", type = "list", max = 3, of = { type = "int", bits = 6 } },
			{ name = "notiz", type = "string", max = 8, optional = true },
		}, { titel = "Liste", eintraege = { { id = 1, text = "a" }, { id = 1023 } }, zahlen = { -32, 0, 31 } })

		e:True(data ~= nil, "dekodiert")
		e:Equal(data.titel, "Liste")
		e:Equal(#data.eintraege, 2)
		e:Equal(data.eintraege[1].text, "a")
		e:Equal(data.eintraege[2].id, 1023)
		e:Equal(data.eintraege[2].text, nil, "optional fehlt")
		e:Equal(data.zahlen[1], -32)
		e:Equal(data.zahlen[3], 31)
		e:Equal(data.notiz, nil)
		e:Equal(bits, 110, "Bits laut Validate")
		e:Equal(buf:Bits(), bits, "Validate und Puffer zählen gleich")
	end)

	t:It("Listen: Lücken und zu viele Einträge werden abgelehnt", function(e)
		local spec = N.CompileSchema({ { name = "l", type = "list", max = 3, of = { type = "uint", bits = 4 } } })
		e:True(N.Validate(spec, { l = {} }), "leere Liste")
		e:False(N.Validate(spec, { l = { 1, 2, 3, 4 } }), "zu viele")
		e:False(N.Validate(spec, { l = { 1, nil, 3 } }), "Lücke")
		e:False(N.Validate(spec, { l = { a = 1 } }), "fremder Schlüssel")
		local _, _, path = N.Validate(spec, { l = { 1, 99 } })
		e:Equal(path, "l[2]", "Pfad mit Index")

		local buf = raw(function(b) b:WriteUInt(5, 2) end) -- Zähler 5 bei max 3
		e:Equal(N.Decode(spec, buf, 100), nil, "manipulierter Listenzähler")
	end)

	t:It("Decode verwirft manipulierte Werte", function(e)
		local spec = N.CompileSchema({
			{ name = "id", type = "string", max = 8, pattern = "^[%w_]+$" },
			{ name = "anzahl", type = "uint", bits = 8, min = 0, max = 200 },
		})
		local function decode(fill)
			local buf = raw(fill)
			return N.Decode(spec, buf, buf:Bits())
		end
		local ok = decode(function(b) b:WriteString("ok_1") b:WriteUInt(200, 8) end)
		e:True(ok ~= nil and ok.anzahl == 200, "Grenzwert 200 erlaubt")
		e:Equal(decode(function(b) b:WriteString("ok") b:WriteUInt(201, 8) end), nil, "uint über max")
		e:Equal(decode(function(b) b:WriteString("123456789") b:WriteUInt(1, 8) end), nil, "Text zu lang")
		e:Equal(decode(function(b) b:WriteString("a b") b:WriteUInt(1, 8) end), nil, "Muster verletzt")

		local _, why, path = decode(function(b) b:WriteString("ok") b:WriteUInt(250, 8) end)
		e:Equal(path, "anzahl", "Pfad")
		e:False(string.find(why, "250", 1, true), "Grund enthält keinen Paketinhalt")

		local text = N.CompileSchema({ { name = "t", type = "string", max = 8 } })
		local bytes = N.CompileSchema({ { name = "t", type = "string", max = 8, utf8 = false } })
		local bad = raw(function(b) b:WriteString("\255\254") end)
		e:Equal(N.Decode(text, bad, bad:Bits()), nil, "kein gültiges UTF-8")
		bad:Rewind()
		e:True(N.Decode(bytes, bad, bad:Bits()) ~= nil, "utf8 = false erlaubt beliebige Bytes")
		local umlaut = raw(function(b) b:WriteString("Grüße") end)
		e:True(N.Decode(text, umlaut, umlaut:Bits()) ~= nil, "gültiges UTF-8")
	end)

	t:It("float: NaN abgelehnt, Rundung an der Grenze toleriert", function(e)
		local spec = N.CompileSchema({ { name = "f", type = "float", min = 0, max = 1 } })
		local function decode(v)
			local buf = raw(function(b) b:WriteFloat(v) end)
			return N.Decode(spec, buf, buf:Bits())
		end
		e:Equal(decode(0 / 0), nil, "NaN")
		e:Equal(decode(math.huge), nil, "unendlich")
		e:Equal(decode(1.01), nil, "deutlich über max")
		local near = decode(1 + 1e-8)
		e:True(near ~= nil and near.f == 1, "float32-Rundung wird auf die Grenze gezogen")
	end)

	t:It("entity und player werden auf Gültigkeit geprüft", function(e)
		local ent = N.CompileSchema({ { name = "e", type = "entity" } })
		local entNull = N.CompileSchema({ { name = "e", type = "entity", allowNull = true } })
		local prop = N.CompileSchema({ { name = "e", type = "entity", class = { "prop_physics" } } })
		local ply = N.CompileSchema({ { name = "p", type = "player" } })
		local function decode(spec, v, mode)
			local buf = raw(function(b)
				if spec.fields[1].type == "player" then b:WritePlayer(v) else b:WriteEntity(v) end
			end)
			return N.Decode(spec, buf, buf:Bits(), mode)
		end

		e:Equal(decode(ent, NULL), nil, "NULL ohne allowNull")
		e:Equal(decode(ent, game.GetWorld()), nil, "Welt ist keine gültige Entity")
		local d = decode(entNull, NULL)
		e:True(d ~= nil and d.e == NULL, "allowNull liefert NULL")
		e:Equal(decode(prop, fakeEnt("x", false, "func_door")), nil, "Klasse nicht erlaubt")
		e:True(decode(prop, fakeEnt("x", false, "prop_physics")) ~= nil, "erlaubte Klasse")
		e:Equal(decode(ply, fakeEnt("x", false)), nil, "Entity ist kein Spieler")
		e:True(decode(ply, fakeEnt("x", true)) ~= nil, "Spieler")
		e:True(decode(ent, NULL, "client") ~= nil, "Client: Entity außerhalb des PVS ist NULL, kein Fehler")

		e:False(N.Validate(ent, { e = NULL }), "Senden: NULL ohne allowNull")
		e:True(N.Validate(entNull, {}), "Senden: allowNull, Feld leer")
	end)

	t:It("Decode prüft die Paketlänge", function(e)
		local spec = N.CompileSchema({ { name = "a", type = "uint", bits = 8 }, { name = "b", type = "uint", bits = 8 } })
		local buf = raw(function(b) b:WriteUInt(1, 8) b:WriteUInt(2, 8) end)
		e:True(N.Decode(spec, buf, 16) ~= nil, "exakte Länge")
		buf:Rewind()
		e:True(N.Decode(spec, buf, 20) ~= nil, "unter 8 Bit Rest (Auffüllung)")
		buf:Rewind()
		e:Equal(N.Decode(spec, buf, 12), nil, "zu kurz")
		buf:Rewind()
		e:Equal(N.Decode(spec, buf, 32), nil, "überzählige Daten")

		local str = N.CompileSchema({ { name = "s", type = "string", max = 64 } })
		local s = raw(function(b) b:WriteString("abcdef") end)
		e:Equal(N.Decode(str, s, 24), nil, "Text länger als das Paket")
	end)
end)

T.Describe("Net.RateLimiter", function(t)
	t:It("erlaubt count Pakete, danach nicht mehr", function(e)
		local lim = N.NewLimiter(3, 1)
		e:True(lim:Allow("a", 100))
		e:True(lim:Allow("a", 100))
		e:True(lim:Allow("a", 100))
		e:False(lim:Allow("a", 100), "viertes Paket in derselben Sekunde")
	end)

	t:It("Zeitverfall füllt das Kontingent wieder auf, aber nie über count", function(e)
		local lim = N.NewLimiter(4, 2) -- 2 pro Sekunde
		for _ = 1, 4 do lim:Allow("a", 10) end
		e:False(lim:Allow("a", 10), "leer")
		e:True(lim:Allow("a", 10.5), "nach 0,5 s ein Paket zurück")
		e:False(lim:Allow("a", 10.5), "danach wieder leer")
		local allowed = 0
		for _ = 1, 10 do
			if lim:Allow("a", 1000) then allowed = allowed + 1 end
		end
		e:Equal(allowed, 4, "nach langer Pause genau count")
	end)

	t:It("Schlüssel sind unabhängig, Zeit rückwärts bringt nichts", function(e)
		local lim = N.NewLimiter(1, 10)
		e:True(lim:Allow("a", 50))
		e:False(lim:Allow("a", 50))
		e:True(lim:Allow("b", 50), "anderer Spieler")
		e:False(lim:Allow("a", 40), "kleinerer Zeitstempel")
		e:False(lim:Allow("a", 50), "kein Guthaben durch Zeitsprung")
		e:True(lim:Allow("a", 60), "nach perSeconds wieder erlaubt")
	end)

	t:It("Reset und Prune", function(e)
		local lim = N.NewLimiter(2, 1)
		lim:Allow("a", 0) lim:Allow("a", 0)
		e:False(lim:Allow("a", 0))
		lim:Reset("a")
		e:True(lim:Allow("a", 0), "nach Reset frei")
		lim:Prune(0.1)
		e:True(lim.buckets.a ~= nil, "nicht voll -> bleibt")
		lim:Prune(10)
		e:Equal(lim.buckets.a, nil, "volles Kontingent wird entfernt")
	end)

	t:It("Rate-Limit gilt je Nachricht", function(e)
		local reg = N.NewRegistry()
		local def = { direction = "c2s", perm = false, rateLimit = { count = 1, perSeconds = 5 } }
		local a = reg:Register("lmnt_test_a", def)
		local b = reg:Register("lmnt_test_b", def)
		e:True(a.limiter:Allow("p", 0))
		e:False(a.limiter:Allow("p", 0))
		e:True(b.limiter:Allow("p", 0), "andere Nachricht hat eigenes Kontingent")
	end)
end)

T.Describe("Net.Verstöße", function(t)
	t:It("Punkte verfallen mit der Zeit und nie unter 0", function(e)
		local c = N.NewViolationCounter(60) -- 1 Punkt pro Sekunde
		e:Equal(c:Add("a", 5, 0), 5)
		e:Equal(c:Get("a", 2), 3)
		e:Equal(c:Add("a", 1, 2), 4)
		e:Equal(c:Get("a", 100), 0)
		e:Equal(c:Get("unbekannt", 100), 0)
		c:Prune(100)
		e:Equal(c.entries.a, nil, "verfallene Einträge werden entfernt")
	end)

	t:It("Verfall wird live gelesen, 0 = kein Verfall", function(e)
		local rate = 0
		local c = N.NewViolationCounter(function() return rate end)
		c:Add("a", 10, 0)
		e:Equal(c:Get("a", 10), 10)
		rate = 6 -- 0,1 pro Sekunde
		e:Equal(c:Get("a", 10), 9)
	end)

	t:It("gültiges Paket kommt durch, Statistik zählt", function(e)
		local env = newEnv()
		local guard = N.NewGuard(env)
		local msg = testMsg({ direction = "c2s", perm = false, schema = { { name = "n", type = "uint", bits = 8 } } })
		local buf = raw(function(b) b:WriteUInt(7, 8) end)
		local data = guard:Incoming(msg, fakeEnt("p1", true), buf:Bits(), buf)
		e:Equal(data and data.n, 7)
		e:Equal(msg.stats.received, 1)
		e:Equal(msg.stats.bytesIn, 1)
		e:Equal(msg.stats.dropped, 0)
		e:Equal(#env.logs, 0, "kein Log")
	end)

	t:It("Übergröße wird vor dem Lesen verworfen", function(e)
		local env = newEnv()
		local guard = N.NewGuard(env)
		local msg = testMsg({ direction = "c2s", perm = false, schema = { { name = "n", type = "uint", bits = 8 } } })
		local bomb = setmetatable({}, { __index = function() error("Paket darf nicht gelesen werden") end })
		local data, code = guard:Incoming(msg, fakeEnt("p1", true), 70000, bomb)
		e:Equal(data, nil)
		e:Equal(code, "size")
		e:Equal(select(2, guard:Incoming(msg, fakeEnt("p1", true), 0, bomb)), "size", "zu klein")
		e:Equal(msg.stats.violations, 2)
		e:Equal(msg.stats.dropped, 2)
		e:Equal(msg.stats.reasons.size, 2)
		e:Equal(env.events[1], "lmnt_test_net:size", "Event mit Name und Grund")
	end)

	t:It("Flood: Rate-Limit greift, security-Log wird gedrosselt", function(e)
		local env = newEnv()
		local guard = N.NewGuard(env)
		local msg = testMsg({ direction = "c2s", perm = false, rateLimit = { count = 2, perSeconds = 1 } })
		local ply = fakeEnt("p1", true)
		local accepted = 0
		for _ = 1, 10 do
			if guard:Incoming(msg, ply, 0, N.NewBuffer()) then accepted = accepted + 1 end
		end
		e:Equal(accepted, 2)
		e:Equal(msg.stats.reasons.rate, 8)
		e:Equal(#env.events, 8, "Event je Verstoß")
		e:Equal(#env.logs, 1, "nur ein Log im Drosselintervall")

		env.time = 11
		guard:Incoming(msg, ply, 0, N.NewBuffer())
		guard:Incoming(msg, ply, 0, N.NewBuffer())
		guard:Incoming(msg, ply, 0, N.NewBuffer()) -- drittes Paket -> Verstoß nach Ablauf der Drossel
		e:Equal(#env.logs, 2)
		e:True(string.find(env.logs[2], "+7", 1, true) ~= nil, "unterdrückte Meldungen werden mitgezählt")
		e:Equal(#env.kicks, 0, "9 Punkte < Schwelle 20")
	end)

	t:It("Recht fehlt -> perm-Verstoß (Deny-by-default)", function(e)
		local env = newEnv()
		local guard = N.NewGuard(env)
		local msg = testMsg({ direction = "c2s", perm = "test.recht" })
		local data, code = guard:Incoming(msg, fakeEnt("p1", true), 0, N.NewBuffer())
		e:Equal(data, nil)
		e:Equal(code, "perm")
		env.perms["test.recht"] = true
		e:True(guard:Incoming(msg, fakeEnt("p1", true), 0, N.NewBuffer()) ~= nil, "mit Recht erlaubt")

		msg.perm = nil -- darf nie passieren; falls doch: verweigern statt erlauben
		e:Equal(select(2, guard:Incoming(msg, fakeEnt("p1", true), 0, N.NewBuffer())), "perm")
	end)

	t:It("Client sendet eine s2c-Nachricht -> direction-Verstoß", function(e)
		local env = newEnv()
		local guard = N.NewGuard(env)
		local msg = testMsg({ direction = "s2c", schema = {} })
		e:Equal(select(2, guard:Incoming(msg, fakeEnt("p1", true), 0, N.NewBuffer())), "direction")
	end)

	t:It("Schema-Verstoß: Log ohne Paketinhalt", function(e)
		local env = newEnv()
		local guard = N.NewGuard(env)
		local msg = testMsg({ direction = "c2s", perm = false, schema = { { name = "id", type = "string", max = 32, pattern = "^%d+$" } } })
		local buf = raw(function(b) b:WriteString("GEHEIMNIS") end)
		local data, code = guard:Incoming(msg, fakeEnt("p1", true), buf:Bits(), buf)
		e:Equal(data, nil)
		e:Equal(code, "schema")
		e:Equal(#env.logs, 1)
		e:True(string.find(env.logs[1], "Feld 'id'", 1, true) ~= nil, "Feldname im Log")
		e:False(string.find(env.logs[1], "GEHEIMNIS", 1, true), "kein Paketinhalt im Log")
	end)

	t:It("Schwelle: genau ein Kick mit neutraler Meldung, danach verwerfen ohne Punkte", function(e)
		local env = newEnv()
		env.limit = 2 * N.Weights.schema
		local guard = N.NewGuard(env)
		local msg = testMsg({ direction = "c2s", perm = false, schema = { { name = "n", type = "uint", bits = 8, max = 5 } } })
		local ply = fakeEnt("p1", true)
		local function badPacket()
			local buf = raw(function(b) b:WriteUInt(9, 8) end)
			return guard:Incoming(msg, ply, buf:Bits(), buf)
		end

		badPacket()
		e:Equal(#env.kicks, 0, "unter der Schwelle")
		badPacket()
		e:Equal(#env.kicks, 1, "Schwelle erreicht")
		e:False(string.find(env.kicks[1], "lmnt_test_net", 1, true), "Kick-Text ohne interne Details")
		e:Equal(select(2, badPacket()), "kicked")
		e:Equal(msg.stats.violations, 2, "nach dem Kick keine weiteren Punkte")
		e:Equal(#env.kicks, 1)

		guard:Forget("p1") -- Reconnect: Punkte bleiben, nächster Verstoß trennt sofort wieder
		badPacket()
		e:Equal(#env.kicks, 2)
	end)

	t:It("Schwelle 0 = nie kicken, Verfall verhindert Kick bei seltenen Verstößen", function(e)
		local env = newEnv()
		env.limit = 0
		local guard = N.NewGuard(env)
		local msg = testMsg({ direction = "c2s", perm = false, schema = { { name = "n", type = "uint", bits = 8, max = 5 } } })
		local ply = fakeEnt("p1", true)
		for _ = 1, 50 do
			local buf = raw(function(b) b:WriteUInt(9, 8) end)
			guard:Incoming(msg, ply, buf:Bits(), buf)
		end
		e:Equal(#env.kicks, 0, "Schwelle 0")

		local env2 = newEnv()
		env2.limit = 2 * N.Weights.schema
		env2.decayRate = 60 -- 1 Punkt pro Sekunde
		local guard2 = N.NewGuard(env2)
		for i = 0, 5 do
			env2.time = i * 10
			local buf = raw(function(b) b:WriteUInt(9, 8) end)
			guard2:Incoming(msg, fakeEnt("p2", true), buf:Bits(), buf)
		end
		e:Equal(#env2.kicks, 0, "alle 10 s ein Verstoß verfällt vor dem nächsten")
	end)

	t:It("Prune meldet unterdrückte Verstöße nach", function(e)
		local env = newEnv()
		env.limit = 0 -- ohne Kick, sonst würde der Kick-Log mitzählen
		local guard = N.NewGuard(env)
		local msg = testMsg({ direction = "s2c", schema = {} })
		for _ = 1, 4 do guard:Incoming(msg, fakeEnt("p1", true), 0, N.NewBuffer()) end
		e:Equal(#env.logs, 1)
		guard:Prune(60)
		e:Equal(#env.logs, 2)
		e:True(string.find(env.logs[2], "3 weitere", 1, true) ~= nil, "Zusammenfassung")
	end)
end)

T.Describe("Net.Registrierung", function(t)
	local function def(handler, bits)
		return { direction = "c2s", perm = false, schema = { { name = "n", type = "uint", bits = bits or 8 } }, handler = handler }
	end

	t:It("gleiches Schema (Reload) ist erlaubt und übernimmt den neuen Handler", function(e)
		local reg = N.NewRegistry()
		local h1, h2 = function() end, function() end
		local m1, new1 = reg:Register("lmnt_test_reg", def(h1))
		local m2, new2 = reg:Register("lmnt_test_reg", def(h2))
		e:True(new1, "erste Registrierung")
		e:False(new2, "Reload")
		e:True(m1 == m2, "dieselbe Nachricht, Statistik bleibt")
		e:True(m1.handler == h2, "neuer Handler")
		reg:Register("lmnt_test_reg", def(nil))
		e:True(m1.handler == h2, "Registrierung ohne Handler behält den alten")
	end)

	t:It("anderes Schema oder andere Richtung ist ein Fehler", function(e)
		local reg = N.NewRegistry()
		reg:Register("lmnt_test_reg", def())
		e:Error(function() reg:Register("lmnt_test_reg", def(nil, 16)) end, "andere Bitzahl")
		e:Error(function()
			reg:Register("lmnt_test_reg", { direction = "c2s", perm = false, schema = { { name = "n", type = "uint", bits = 8, max = 100 } } })
		end, "andere Grenze")
		e:Error(function()
			reg:Register("lmnt_test_reg", { direction = "both", perm = false, schema = { { name = "n", type = "uint", bits = 8 } } })
		end, "andere Richtung")
		e:NoError(function() reg:Register("lmnt_test_reg", def()) end, "gleiches Schema weiterhin erlaubt")
	end)

	t:It("Reload übernimmt geändertes Recht und Rate-Limit", function(e)
		local reg = N.NewRegistry()
		local m = reg:Register("lmnt_test_reg", def())
		local d = def()
		d.perm = "test.recht"
		d.rateLimit = { count = 3, perSeconds = 2 }
		reg:Register("lmnt_test_reg", d)
		e:Equal(m.perm, "test.recht")
		e:Equal(m.limiter.count, 3)
	end)

	t:It("Rechte: c2s ohne perm ist ein Fehler, perm = false erlaubt", function(e)
		local reg = N.NewRegistry()
		e:Error(function() reg:Register("lmnt_test_p1", { direction = "c2s" }) end, "perm fehlt")
		e:Error(function() reg:Register("lmnt_test_p2", { direction = "both", perm = "" }) end, "leeres Recht")
		e:Error(function() reg:Register("lmnt_test_p3", { direction = "s2c", perm = "x" }) end, "perm bei s2c")
		e:NoError(function() reg:Register("lmnt_test_p4", { direction = "c2s", perm = false }) end)
		e:NoError(function() reg:Register("lmnt_test_p5", { direction = "s2c" }) end)
	end)

	t:It("ungültige Namen und Definitionen", function(e)
		local reg = N.NewRegistry()
		for _, name in ipairs({ "", "Groß", "mit leerzeichen", string.rep("a", 65), 5 }) do
			e:Error(function() reg:Register(name, { direction = "s2c" }) end, "Name " .. tostring(name))
		end
		e:Error(function() reg:Register("lmnt_test_d", { direction = "up" }) end, "Richtung")
		e:Error(function() reg:Register("lmnt_test_d", { direction = "c2s", perm = false, ratelimit = {} }) end, "Tippfehler im Schlüssel")
		e:Error(function() reg:Register("lmnt_test_d", { direction = "c2s", perm = false, rateLimit = { count = 0, perSeconds = 1 } }) end, "count 0")
		e:Error(function() reg:Register("lmnt_test_d", { direction = "s2c", rateLimit = { count = 1, perSeconds = 1 } }) end, "rateLimit bei s2c")
		e:Error(function() reg:Register("lmnt_test_d", { direction = "c2s", perm = false, handler = "x" }) end, "handler kein function")
	end)

	t:It("maxBits: aus dem Schema, enger setzbar, 64-KB-Grenze", function(e)
		local reg = N.NewRegistry()
		local schema = { { name = "s", type = "string", max = 10 } }
		e:Equal(reg:Register("lmnt_test_m1", { direction = "s2c", schema = schema }).maxBits, 88, "aus dem Schema")
		e:Equal(reg:Register("lmnt_test_m2", { direction = "s2c", schema = schema, maxBits = 40 }).maxBits, 40, "enger")
		e:Equal(reg:Register("lmnt_test_m3", { direction = "s2c", schema = schema, maxBits = 4000 }).maxBits, 88, "nie weiter als das Schema")
		e:Error(function() reg:Register("lmnt_test_m4", { direction = "s2c", schema = schema, maxBits = 600000 }) end, "über 64 KB")
		e:Error(function() reg:Register("lmnt_test_m5", { direction = "s2c", schema = schema, maxBits = 4 }) end, "kleiner als das kleinste Paket")
		local big = reg:Register("lmnt_test_m6", { direction = "s2c", schema = { { name = "l", type = "list", max = 1000, of = { type = "string", max = 255 } } } })
		e:True(big.maxBits <= 65530 * 8, "auf die 64-KB-Grenze begrenzt")
	end)
end)

T.Describe("Net.Dienst", function(t)
	t:It("Einstellungen, Event und !netstats sind registriert", function(e)
		local def = LMNT.Settings.GetDef("lmnt.net.kick_threshold")
		e:True(def ~= nil, "lmnt.net.kick_threshold")
		e:True(def.default > 0, "Kick standardmäßig aktiv")
		e:True(LMNT.Settings.GetDef("lmnt.net.decay_per_minute") ~= nil, "lmnt.net.decay_per_minute")
		e:True(LMNT.Events._bus.defs["lmnt.net.violation"] ~= nil, "Event definiert")
		local cmd = LMNT.Admin.GetCommand("netstats")
		e:True(cmd ~= nil and cmd.perm == "dev", "!netstats mit Recht dev")
	end)

	t:It("Selbsttest-Nachricht ist registriert und geschützt", function(e)
		local d = N.Get("lmnt_net_selftest")
		e:True(d ~= nil, "registriert")
		e:Equal(d.perm, "dev")
		e:True(d.hasHandler, "Server-Handler gesetzt")
		e:True(util.NetworkStringToID("lmnt_net_selftest") ~= 0, "Netzwerkstring angelegt")
		e:True(istable(N.Stats()["lmnt_net_selftest"]), "Statistik vorhanden")
	end)

	t:It("Fehlbedienung ist ein Entwicklerfehler", function(e)
		e:Error(function() N.Send("lmnt_test_gibtsnicht", {}) end, "unbekannte Nachricht")
		e:Error(function() N.Send("lmnt_net_selftest", { n = 1 }) end, "c2s-Nachricht vom Server senden")
		e:Error(function() N.Receive("lmnt_test_gibtsnicht", function() end) end, "Receive ohne Register")
		e:Error(function() N.SendToServer("lmnt_net_selftest", { n = 1 }) end, "SendToServer auf dem Server")
		e:Error(function() N.Register("Ungültig", { direction = "s2c" }) end, "ungültiger Name")
	end)
end)
