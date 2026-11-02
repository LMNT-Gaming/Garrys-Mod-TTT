-- LMNT Unit-Tests: HTTP-Dienst und Discord-Weiterleitung
-- Eigene Instanzen mit falscher Uhr und aufzeichnendem Transport: Es verlässt nichts den Server.
-- Einzige Ausnahme ist der Test mit dem unerreichbaren Endpunkt 127.0.0.1:1 (prüft, dass nichts blockiert).
local T = LMNT.Test

local URL = "https://example.invalid/lmnt-test"

-- Testinstanz: env.now ist die Uhr, env.requests sammelt alle Anfragen.
-- opts.answer(req) antwortet sofort, opts.queued = false simuliert ein abgeschaltetes HTTP().
local function fakeService(opts)
	opts = opts or {}
	local env = { now = 1000, requests = {} }
	env.http = LMNT.HTTP.New({
		quiet = true,
		started = true,
		secrets = opts.secrets or {},
		clock = function() return env.now end,
		transport = function(req)
			env.requests[#env.requests + 1] = req
			if opts.answer then opts.answer(req) end
			return opts.queued ~= false
		end,
	})
	return env
end

local function answer204(req) req.success(204, "", {}) end

T.Describe("HTTP-Dienst", function(t)
	t:It("unbekannter Endpunkt wird abgelehnt", function(e)
		local env = fakeService()
		local ok, reason = env.http:Send("gibt.es.nicht", "x")
		e:False(ok)
		e:Equal(reason, "unknown_endpoint")
		e:Equal(#env.requests, 0, "keine Anfrage")
	end)

	t:It("fehlendes Secret: Endpunkt sauber deaktiviert, kein Fehler", function(e)
		local env = fakeService({ secrets = {} })
		local enabled, why
		e:NoError(function() enabled, why = env.http:RegisterEndpoint("t.secret", { urlSecret = "fehlt" }) end)
		e:False(enabled)
		e:True(isstring(why) and string.find(why, "fehlt", 1, true) ~= nil, "Grund nennt den fehlenden Schlüssel")
		e:False(env.http:IsEnabled("t.secret"))
		local ok, reason = env.http:Send("t.secret", "x")
		e:False(ok)
		e:Equal(reason, "disabled")
		e:Equal(#env.requests, 0, "keine Anfrage")
		e:Equal(env.http:Stats()["t.secret"].enabled, false)
	end)

	t:It("Secret mit falschem URL-Format bleibt deaktiviert", function(e)
		local wrong = fakeService({ secrets = { hook = "https://example.invalid/api/webhooks/1/abc" } })
		local enabled = wrong.http:RegisterEndpoint("t.pattern", { urlSecret = "hook", urlPattern = LMNT.Discord.URL_PATTERNS })
		e:False(enabled, "fremder Host")
		local right = fakeService({ secrets = { hook = "https://discord.com/api/webhooks/123/abc_DEF-1" } })
		enabled = right.http:RegisterEndpoint("t.pattern", { urlSecret = "hook", urlPattern = LMNT.Discord.URL_PATTERNS })
		e:True(enabled, "Discord-Webhook")
	end)

	t:It("Secrets werden genutzt, erscheinen aber nie in Stats", function(e)
		local secretUrl = "https://discord.com/api/webhooks/1/geheim"
		local env = fakeService({ secrets = { hook = secretUrl, token = "Bearer geheim2" }, answer = answer204 })
		env.http:RegisterEndpoint("t.s", { urlSecret = "hook", headerSecrets = { Authorization = "token" } })
		e:True(env.http:Send("t.s", { a = 1 }))
		e:Equal(env.requests[1].url, secretUrl)
		e:Equal(env.requests[1].headers.Authorization, "Bearer geheim2")
		e:Equal(env.requests[1].body, '{"a":1}', "Tabelle als JSON")
		for k, v in pairs(env.http:Stats()["t.s"]) do
			e:True(not isstring(v) or string.find(v, "geheim", 1, true) == nil, "Stats-Feld " .. k)
		end
	end)

	t:It("Payload-Grenze", function(e)
		local env = fakeService({ answer = answer204 })
		env.http:RegisterEndpoint("t.size", { url = URL, maxPayload = 16 })
		local ok, reason = env.http:Send("t.size", string.rep("a", 17))
		e:False(ok)
		e:Equal(reason, "payload_too_large")
		e:Equal(env.http:Stats()["t.size"].dropped, 1)
		e:True(env.http:Send("t.size", string.rep("a", 16)), "genau an der Grenze erlaubt")
		e:Equal(#env.requests, 1)
	end)

	t:It("Rate-Limit: Überzählige warten, volle Warteschlange verwirft mit Zähler", function(e)
		local env = fakeService({ answer = answer204 })
		env.http:RegisterEndpoint("t.rate", { url = URL, rateLimit = { count = 2, perSeconds = 10 }, queueSize = 2 })
		for i = 1, 4 do e:True(env.http:Send("t.rate", "m" .. i), "Nachricht " .. i) end
		local ok, reason = env.http:Send("t.rate", "m5")
		e:False(ok)
		e:Equal(reason, "queue_full")
		e:Equal(#env.requests, 2, "nur zwei Anfragen im Fenster")
		e:Equal(env.http:Stats()["t.rate"].queued, 2)
		e:Equal(env.http:Stats()["t.rate"].dropped, 1)

		env.now = env.now + 5
		env.http:Pump()
		e:Equal(#env.requests, 2, "Fenster noch nicht abgelaufen")

		env.now = env.now + 5
		env.http:Pump()
		e:Equal(#env.requests, 4)
		e:Equal(env.requests[3].body, "m3", "Reihenfolge bleibt erhalten")
		e:Equal(env.http:Stats()["t.rate"].sent, 4)
	end)

	t:It("Rate-Limit mit merge: wartende Nachrichten werden zusammengefasst", function(e)
		local env = fakeService({ answer = answer204 })
		local results = {}
		env.http:RegisterEndpoint("t.merge", {
			url = URL, rateLimit = { count = 1, perSeconds = 60 },
			merge = function(bodies) return table.concat(bodies, "\n") end,
		})
		for _, m in ipairs({ "a", "b", "c", "d" }) do
			env.http:Send("t.merge", m, function(ok) results[#results + 1] = m .. "=" .. tostring(ok) end)
		end
		e:Equal(#env.requests, 1)

		env.now = env.now + 60
		env.http:Pump()
		e:Equal(#env.requests, 2)
		e:Equal(env.requests[2].body, "b\nc\nd")
		local s = env.http:Stats()["t.merge"]
		e:Equal(s.merged, 2)
		e:Equal(s.sent, 4)
		e:Equal(table.concat(results, ","), "a=true,b=true,c=true,d=true", "jeder Callback genau einmal")
	end)

	t:It("merge hält maxPayload ein", function(e)
		local env = fakeService({ answer = answer204 })
		env.http:RegisterEndpoint("t.mergesize", {
			url = URL, rateLimit = { count = 1, perSeconds = 60 }, maxPayload = 3,
			merge = function(bodies) return table.concat(bodies, "\n") end,
		})
		for _, m in ipairs({ "a", "b", "c", "d" }) do env.http:Send("t.mergesize", m) end
		env.now = env.now + 60
		env.http:Pump()
		e:Equal(env.requests[2].body, "b\nc", "höchstens 3 Bytes")
		e:Equal(env.http:Stats()["t.mergesize"].queued, 1)
	end)

	t:It("Wiederholung mit Backoff nach Serverfehler", function(e)
		local env = fakeService()
		local result
		env.http:RegisterEndpoint("t.retry", { url = URL, retries = 2 })
		env.http:Send("t.retry", "x", function(ok, info) result = { ok = ok, info = info } end)
		env.requests[1].success(503, "", {})
		e:Equal(result, nil, "noch kein Ergebnis")

		env.http:Pump()
		e:Equal(#env.requests, 1, "nicht sofort erneut (Backoff)")

		env.now = env.now + 2
		env.http:Pump()
		e:Equal(#env.requests, 2, "zweiter Versuch nach Backoff")
		env.requests[2].success(204, "", {})
		e:True(result and result.ok, "Erfolg")
		e:Equal(result.info.attempts, 2)
		local s = env.http:Stats()["t.retry"]
		e:Equal(s.retries, 1)
		e:Equal(s.sent, 1)
		e:Equal(s.failed, 0)
	end)

	t:It("429 beachtet Retry-After", function(e)
		local env = fakeService()
		env.http:RegisterEndpoint("t.429", { url = URL, retries = 2 })
		env.http:Send("t.429", "x")
		env.requests[1].success(429, "", { ["Retry-After"] = "30" })
		env.now = env.now + 29
		env.http:Pump()
		e:Equal(#env.requests, 1, "vor Ablauf von Retry-After")
		env.now = env.now + 1
		env.http:Pump()
		e:Equal(#env.requests, 2, "nach Retry-After")
	end)

	t:It("endgültiger Fehler nach allen Wiederholungen, 4xx ohne Wiederholung", function(e)
		local env = fakeService()
		local results = {}
		local function collect(_, info) results[#results + 1] = info end
		env.http:RegisterEndpoint("t.fail", { url = URL, retries = 1 })

		env.http:Send("t.fail", "x", collect)
		env.requests[1].failed("unsuccessful")
		env.now = env.now + 60
		env.http:Pump()
		env.requests[2].failed("unsuccessful")
		e:Equal(#results, 1)
		e:Equal(results[1].error, "unsuccessful")
		e:Equal(results[1].attempts, 2)
		e:Equal(env.http:Stats()["t.fail"].failed, 1)

		env.now = env.now + 600
		env.http:Send("t.fail", "y", collect)
		env.requests[3].success(400, "bad", {})
		e:Equal(#results, 2)
		e:Equal(results[2].code, 400)
		e:Equal(results[2].attempts, 1, "4xx wird nicht wiederholt")
	end)

	t:It("hängende Anfrage: Wächter gibt den Endpunkt frei, späte Antwort wird ignoriert", function(e)
		local env = fakeService()
		local results = {}
		local function collect(_, info) results[#results + 1] = info.error or "ok" end
		env.http:RegisterEndpoint("t.hang", { url = URL, timeout = 5, retries = 0 })
		env.http:Send("t.hang", "a", collect)
		env.http:Send("t.hang", "b", collect)
		e:Equal(#env.requests, 1, "eine Anfrage gleichzeitig pro Endpunkt")

		env.now = env.now + 11
		env.http:Pump()
		e:Equal(results[1], "watchdog_timeout")

		env.now = env.now + 2
		env.http:Pump()
		e:Equal(#env.requests, 2, "nächste Nachricht läuft")

		env.requests[1].success(204, "", {})
		e:Equal(#results, 1, "späte Antwort ignoriert")
		env.requests[2].success(204, "", {})
		e:Equal(results[2], "ok")
		e:Equal(env.http:Stats()["t.hang"].sent, 1)
	end)

	t:It("abgeschaltetes HTTP() zählt als Fehlversuch, ohne Fehler", function(e)
		local env = fakeService({ queued = false })
		env.http:RegisterEndpoint("t.off", { url = URL, retries = 0 })
		local result
		e:NoError(function() env.http:Send("t.off", "x", function(_, info) result = info end) end)
		e:Equal(result and result.error, "not_queued")
		e:Equal(env.http:Stats()["t.off"].failed, 1)
	end)

	t:It("Fehler in Callback und Transport werden isoliert", function(e)
		local env = fakeService({ answer = answer204 })
		env.http:RegisterEndpoint("t.cb", { url = URL })
		e:NoError(function() env.http:Send("t.cb", "x", function() error("absichtlich") end) end)
		e:Equal(env.http:Stats()["t.cb"].sent, 1)

		local broken = LMNT.HTTP.New({
			quiet = true, started = true, secrets = {},
			clock = function() return 0 end,
			transport = function() error("kaputt") end,
		})
		broken:RegisterEndpoint("t.x", { url = URL, retries = 0 })
		local info
		e:NoError(function() broken:Send("t.x", "x", function(_, i) info = i end) end)
		e:True(info and string.find(info.error, "kaputt", 1, true) ~= nil, "Fehler landet im Callback")
	end)

	t:It("Unregister beendet wartende Nachrichten mit Callback", function(e)
		local env = fakeService()
		local results = {}
		local function collect(_, info) results[#results + 1] = info.error end
		env.http:RegisterEndpoint("t.un", { url = URL })
		env.http:Send("t.un", "a", collect)
		env.http:Send("t.un", "b", collect)
		e:True(env.http:Unregister("t.un"))
		e:Equal(table.concat(results, ","), "unregistered,unregistered")
		env.requests[1].success(204, "", {})
		e:Equal(#results, 2, "späte Antwort ignoriert")
		local _, reason = env.http:Send("t.un", "c")
		e:Equal(reason, "unknown_endpoint")
	end)

	t:It("unerreichbarer Endpunkt blockiert nicht (echtes HTTP)", function(e)
		local http = LMNT.HTTP.New({ quiet = true, started = true, secrets = {} })
		http:RegisterEndpoint("t.unreachable", { url = "http://127.0.0.1:1/lmnt-test", retries = 0, timeout = 2 })
		local start = SysTime()
		local ok = http:Send("t.unreachable", "ping")
		local took = SysTime() - start
		e:True(ok, "Nachricht angenommen")
		e:True(took < 0.1, string.format("Send kehrt sofort zurück (%.1f ms)", took * 1000))
		local s = http:Stats()["t.unreachable"]
		e:True(s.inflight or s.failed == 1, "Anfrage läuft asynchron oder ist bereits abgewiesen")
	end)

	t:It("EncodeJSON: ganze Zahlen, leere Arrays, Escaping, Zyklen", function(e)
		local J = LMNT.HTTP.EncodeJSON
		e:Equal(J({ color = 0xFF3131, parse = {}, text = "a\"b\n" }), '{"color":16724273,"parse":[],"text":"a\\"b\\n"}')
		e:Equal(J({ 1, 2.5, true, "x" }), '[1,2.5,true,"x"]')
		e:Error(function()
			local loop = {}
			loop.self = loop
			J(loop)
		end, "Zyklus")
	end)
end)

T.Describe("Discord-Weiterleitung", function(t)
	t:It("Einstellungen definiert, Endpunkt registriert", function(e)
		e:True(LMNT.Settings.GetDef("lmnt.discord.enabled") ~= nil, "lmnt.discord.enabled")
		e:True(LMNT.Settings.GetDef("lmnt.discord.min_level") ~= nil, "lmnt.discord.min_level")
		e:True(LMNT.HTTP.Stats()[LMNT.Discord.ENDPOINT] ~= nil, "Endpunkt registriert (aktiv nur mit secrets.json)")
	end)

	t:It("Filter: Mindeststufe und keine Rückkopplung", function(e)
		local F = LMNT.Discord.ShouldForward
		e:True(F("security", "admin", "security"))
		e:False(F("error", "admin", "security"))
		e:True(F("error", "admin", "error"))
		e:True(F("security", "admin", "error"))
		e:False(F("warn", "admin", "error"))
		e:False(F("security", "http", "security"), "Kategorie http")
		e:False(F("error", "discord", "error"), "Kategorie discord")
	end)

	t:It("Embed: LMNT-Rot, keine Pings, Daten reduziert, Markdown entschärft", function(e)
		local p = LMNT.Discord.BuildPayload({
			{ time = os.time(), level = "security", category = "config", message = "Spieler (76561198000000001) von 192.168.1.20:27005 *fett* @everyone" },
		}, 0, true)
		local embed = p.embeds[1]
		e:Equal(embed.color, 0xFF3131)
		e:Equal(#p.allowed_mentions.parse, 0, "keine Erwähnungen erlaubt")
		e:True(string.find(embed.description, "76561198000000001", 1, true) == nil, "SteamID entfernt")
		e:True(string.find(embed.description, "192.168", 1, true) == nil, "IP entfernt")
		e:True(string.find(embed.description, "\\*fett\\*", 1, true) ~= nil, "Markdown escaped")
		e:True(string.find(LMNT.HTTP.EncodeJSON(p), '"color":16724273', 1, true) ~= nil, "Farbe als ganze Zahl")
	end)

	t:It("viele Einträge: Beschreibung begrenzt, Rest gezählt, gültiges UTF-8", function(e)
		local entries = {}
		for i = 1, 50 do entries[i] = { time = os.time(), level = "error", category = "x", message = string.rep("ä", 200) } end
		local p = LMNT.Discord.BuildPayload(entries, 7, false)
		local desc = p.embeds[1].description
		e:True(#desc <= 3500, "Beschreibung " .. #desc .. " Bytes")
		e:True(string.find(desc, "weitere", 1, true) ~= nil, "Hinweis auf weitere Einträge")
		e:True(string.find(p.embeds[1].title, "(57)", 1, true) ~= nil, "Titel zählt alle Einträge")
		e:True(utf8.len(desc), "kein abgeschnittenes UTF-8-Zeichen")
		e:True(#LMNT.HTTP.EncodeJSON(p) <= 6000, "passt in eine Discord-Nachricht")
	end)

	t:It("Merge bündelt Embeds", function(e)
		local merged = LMNT.Discord.Merge({ { embeds = { { title = "a" } } }, { embeds = { { title = "b" } } } })
		e:Equal(#merged.embeds, 2)
		e:Equal(merged.embeds[2].title, "b")
		e:Equal(#merged.allowed_mentions.parse, 0)
	end)
end)
