--[[
	LMNT Service – Zentraler HTTP-Dienst und Discord-Weiterleitung (T-131, Stufe D)
	API-Referenz: docs/framework/api/http.md

	Externe Kommunikation läuft ausschließlich über registrierte Endpunkte. Module rufen nie selbst
	HTTP() oder http.Fetch/Post auf und kennen keine URLs mit Geheimnissen.

	LMNT.HTTP.RegisterEndpoint("mein.dienst", {
		url = "https://…",                         -- feste URL (ohne Geheimnis) ODER
		urlSecret = "mein_webhook",                -- Schlüssel in data/lmnt/secrets.json
		urlPattern = { "^https://example%.org/" }, -- optional: erlaubte URL-Formen (Lua-Muster)
		method = "POST",                           -- GET | POST | HEAD | PUT | DELETE | PATCH | OPTIONS
		type = "application/json",                 -- Content-Type des Bodys
		headers = { ["X-Quelle"] = "lmnt" },       -- feste Header
		headerSecrets = { Authorization = "mein_token" }, -- Header-Werte aus secrets.json
		timeout = 10,                              -- Sekunden (1–60)
		maxPayload = 8192,                         -- Bytes des kodierten Bodys
		rateLimit = { count = 10, perSeconds = 60 },
		retries = 2,                               -- Wiederholungen bei Netzfehler, 408, 429, 5xx (0–5)
		queueSize = 50,                            -- wartende Nachrichten, danach wird verworfen
		merge = function(bodies) return body end,  -- optional: wartende Nachrichten zusammenfassen
		mergeMax = 10,                             -- höchstens so viele Nachrichten pro Anfrage
	})                                           -> aktiv (bool), grund
	LMNT.HTTP.Send(id, body, callback)           -> true | false, grund   (body: String oder Tabelle → JSON)
	    callback(ok, info), info = { code, body, headers, error, attempts, latency }
	    Liefert Send true, läuft der Callback genau einmal (Erfolg, endgültiger Fehler oder Verwerfen).
	    Gründe für false: unknown_endpoint · disabled · invalid_body · payload_too_large · queue_full
	LMNT.HTTP.Unregister(id) · IsEnabled(id) · ReloadSecrets() · Pump()
	LMNT.HTTP.Stats()                            -> { [id] = { enabled, reason, sent, failed, dropped, merged,
	                                                 retries, requests, queued, inflight, lastLatency, lastCode,
	                                                 lastError, lastSuccess } }
	LMNT.HTTP.EncodeJSON(wert)                   -> String (ganze Zahlen ohne Nachkommastellen, {} = [])
	LMNT.HTTP.New(opts)                          -> unabhängige Instanz mit :-Methoden (Tests)

	Nie blockierend: Send reiht nur ein. Gesendet wird asynchron über HTTP(), höchstens eine Anfrage
	pro Endpunkt gleichzeitig. Ein Wächter gibt Anfragen frei, die länger als timeout + 5 s offen sind.
	Geheimnisse stehen nur in data/lmnt/secrets.json (Server). Sie landen nie in LMNT.Settings, Logs,
	Stats oder Netzwerknachrichten an Clients.
]]

local SECRETS_FILE = "lmnt/secrets.json"
local SECRETS_LABEL = "data/" .. SECRETS_FILE
local METHODS = { GET = true, POST = true, HEAD = true, PUT = true, DELETE = true, PATCH = true, OPTIONS = true }

local PUMP_INTERVAL = 0.25 -- Sekunden zwischen zwei Durchläufen der Warteschlange
local WATCHDOG_GRACE = 5   -- zusätzliche Sekunden nach dem Timeout, bevor eine Anfrage als verloren gilt
local BACKOFF_BASE = 2     -- Wartezeit nach dem ersten Fehler, verdoppelt sich je weiterem Fehler
local BACKOFF_MAX = 60
local RETRY_AFTER_MAX = 120
local WARN_INTERVAL = 60   -- höchstens eine Störungswarnung pro Endpunkt und Minute
local MAX_DEPTH = 32       -- JSON-Verschachtelung (Schutz vor Zyklen)

------------------------------------------------------------------------
-- JSON
-- Eigene Kodierung, weil das Zahlenformat von util.TableToJSON nicht dokumentiert ist. Externe APIs
-- verlangen teils echte ganze Zahlen (Discord: Farbe) und echte Arrays (allowed_mentions.parse = []).
------------------------------------------------------------------------

local JSON_ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }

local function encodeString(s)
	return '"' .. string.gsub(s, '[%c"\\]', function(c)
		return JSON_ESCAPES[c] or string.format("\\u%04x", string.byte(c))
	end) .. '"'
end

local function encodeValue(value, depth, out)
	local t = type(value)

	if t == "string" then
		out[#out + 1] = encodeString(value)
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			out[#out + 1] = "null"
		else
			out[#out + 1] = string.format("%.14g", value)
		end
	elseif t == "boolean" then
		out[#out + 1] = value and "true" or "false"
	elseif t == "nil" then
		out[#out + 1] = "null"
	elseif t == "table" then
		if depth >= MAX_DEPTH then error("EncodeJSON: zu tief verschachtelt (Zyklus?)", 0) end

		-- Array nur bei reiner Liste 1..n. Leere Tabellen werden als [] geschrieben.
		local n, count = #value, 0
		for _ in pairs(value) do count = count + 1 end

		if count == n then
			out[#out + 1] = "["
			for i = 1, n do
				if i > 1 then out[#out + 1] = "," end
				encodeValue(value[i], depth + 1, out)
			end
			out[#out + 1] = "]"
		else
			-- Schlüssel sortiert: gleiche Eingabe ergibt immer den gleichen Text
			local entries = {}
			for k, v in pairs(value) do
				local kt = type(k)
				if kt ~= "string" and kt ~= "number" then error("EncodeJSON: Schlüssel vom Typ " .. kt .. " nicht möglich", 0) end
				entries[#entries + 1] = { tostring(k), v }
			end
			table.sort(entries, function(a, b) return a[1] < b[1] end)

			out[#out + 1] = "{"
			for i, entry in ipairs(entries) do
				if i > 1 then out[#out + 1] = "," end
				out[#out + 1] = encodeString(entry[1])
				out[#out + 1] = ":"
				encodeValue(entry[2], depth + 1, out)
			end
			out[#out + 1] = "}"
		end
	else
		error("EncodeJSON: Typ " .. t .. " nicht möglich", 0)
	end
end

local function encodeJSON(value)
	local out = {}
	encodeValue(value, 0, out)
	return table.concat(out)
end

------------------------------------------------------------------------
-- Dienst (eine Instanz pro Server, weitere über LMNT.HTTP.New für Tests)
------------------------------------------------------------------------

local Service = {}
Service.__index = Service

local function log(self, level, msg)
	if self.quiet or not (LMNT.Log and LMNT.Log[level]) then return end
	LMNT.Log[level]("http", msg)
end

local function newStats()
	return { sent = 0, failed = 0, dropped = 0, merged = 0, retries = 0, requests = 0 }
end

-- Störungen höchstens einmal pro Minute und Endpunkt melden (Kategorie http wird nie an Discord
-- weitergeleitet, daher keine Rückkopplung)
local function warnThrottled(self, ep, msg)
	local now = self.clock()
	if ep.lastWarn and now - ep.lastWarn < WARN_INTERVAL then return end
	ep.lastWarn = now
	local s = ep.stats
	log(self, "Warn", "Endpunkt '" .. ep.id .. "': " .. msg .. " (gesendet " .. s.sent .. ", Fehler " .. s.failed .. ", verworfen " .. s.dropped .. ")")
end

-- Ruft die Callbacks der Nachrichten auf. Ein fehlerhafter Callback stört weder die anderen noch den Dienst.
local function finishJobs(self, ep, jobs, ok, info)
	for _, job in ipairs(jobs) do
		if job.callback then
			local cbOk, err = pcall(job.callback, ok, info)
			if not cbOk then log(self, "Warn", "Callback für Endpunkt '" .. ep.id .. "' fehlgeschlagen: " .. tostring(err)) end
		end
	end
end

-- Verwirft alle wartenden Nachrichten (Warteschlange und anstehende Wiederholung)
local function dropQueued(self, ep, reason)
	local jobs = {}
	if ep.retry then
		for _, job in ipairs(ep.retry.jobs) do jobs[#jobs + 1] = job end
		ep.retry = nil
	end
	for _, job in ipairs(ep.queue) do jobs[#jobs + 1] = job end
	ep.queue = {}
	if #jobs == 0 then return end

	ep.stats.dropped = ep.stats.dropped + #jobs
	finishJobs(self, ep, jobs, false, { error = reason, attempts = 0 })
end

local function endpointList(self)
	local list = {}
	for _, ep in pairs(self.endpoints) do list[#list + 1] = ep end
	return list
end

------------------------------------------------------------------------
-- Geheimnisse (data/lmnt/secrets.json, nur Server)
------------------------------------------------------------------------

-- -> secrets, problem   (problem = Grund, warum gar keine Geheimnisse verfügbar sind)
local function readSecrets(self)
	if self.secretSource then return self.secretSource, nil end

	local raw = file.Read(SECRETS_FILE, "DATA")
	if not raw then return {}, SECRETS_LABEL .. " fehlt (Vorlage: data/lmnt/secrets.example.json)" end

	local parsed = util.JSONToTable(raw)
	if not istable(parsed) then
		log(self, "Warn", SECRETS_LABEL .. " ist kein gültiges JSON – alle Endpunkte mit Geheimnissen bleiben deaktiviert")
		return {}, SECRETS_LABEL .. " ist kein gültiges JSON"
	end

	-- Schlüssel mit "_" am Anfang sind Kommentare, leere Werte gelten als nicht gesetzt
	local secrets = {}
	for k, v in pairs(parsed) do
		if isstring(k) and not string.StartWith(k, "_") and isstring(v) and v ~= "" then secrets[k] = v end
	end
	return secrets, nil
end

local function missingSecret(self, key)
	return self.secretsProblem or ("Schlüssel '" .. key .. "' fehlt in " .. SECRETS_LABEL)
end

local function matchesAny(url, patterns)
	if patterns == nil then return true end
	if isstring(patterns) then patterns = { patterns } end
	for _, pattern in ipairs(patterns) do
		if string.find(url, pattern) then return true end
	end
	return false
end

-- Setzt URL und Header ein. -> aktiv, grund. Der Grund enthält nie die URL oder einen Geheimwert.
local function resolve(self, ep)
	local def = ep.def
	local url = def.url

	if def.urlSecret then
		url = self.secrets[def.urlSecret]
		if not url then return false, missingSecret(self, def.urlSecret) end
	end
	if not string.find(url, "^https?://") then return false, "URL beginnt nicht mit http:// oder https://" end
	if not matchesAny(url, def.urlPattern) then return false, "URL hat nicht das erwartete Format" end

	local headers = {}
	for name, value in pairs(def.headers or {}) do headers[name] = tostring(value) end
	for name, key in pairs(def.headerSecrets or {}) do
		local value = self.secrets[key]
		if not value then return false, missingSecret(self, key) end
		headers[name] = value
	end

	ep.url = url
	ep.headers = next(headers) and headers or nil
	return true, nil
end

local function applyState(self, ep, enabled, reason)
	local was = ep.enabled
	ep.enabled = enabled
	ep.reason = reason

	if enabled then
		if was ~= true then log(self, "Info", "Endpunkt '" .. ep.id .. "' aktiv") end
		return
	end

	ep.url, ep.headers = nil, nil
	dropQueued(self, ep, "disabled")
	-- Fehlendes Geheimnis ist ein gewollter Zustand (Dienst nicht eingerichtet) → Info statt Fehler
	if was ~= false then log(self, "Info", "Endpunkt '" .. ep.id .. "' deaktiviert: " .. reason) end
end

------------------------------------------------------------------------
-- Senden
------------------------------------------------------------------------

local function rateAllows(ep, now)
	local window = ep.sentAt
	while window[1] and window[1] <= now - ep.ratePeriod do table.remove(window, 1) end
	return #window < ep.rateCount
end

-- Wartezeit nach einem Fehler: wächst mit aufeinanderfolgenden Fehlern, 429 nutzt Retry-After
local function backoff(ep)
	return math.min(BACKOFF_BASE * 2 ^ (ep.failures - 1), BACKOFF_MAX)
end

local function retryAfter(headers, body)
	local seconds
	if istable(headers) then
		for name, value in pairs(headers) do
			if isstring(name) and string.lower(name) == "retry-after" then seconds = tonumber(value) end
		end
	end
	if not seconds and isstring(body) and body ~= "" then
		local parsed = util.JSONToTable(body)
		if istable(parsed) then seconds = tonumber(parsed.retry_after) end
	end
	return seconds and math.Clamp(seconds, 1, RETRY_AFTER_MAX) or nil
end

-- Antwort, Netzfehler oder Wächter. Verspätete Antworten (Wächter, Unregister) werden ignoriert.
local function complete(self, id, token, code, body, headers, reason)
	local ep = self.endpoints[id]
	if not ep or not ep.inflight or ep.inflight.token ~= token then return end

	local inflight = ep.inflight
	ep.inflight = nil

	local now = self.clock()
	local batch = inflight.batch
	local latency = now - inflight.started
	local s = ep.stats
	s.lastLatency = latency
	s.lastCode = code

	if code and code >= 200 and code < 300 then
		s.sent = s.sent + #batch.jobs
		s.lastSuccess = os.time()
		ep.failures = 0
		finishJobs(self, ep, batch.jobs, true, { code = code, body = body, headers = headers, attempts = batch.attempts, latency = latency })
	else
		local err = reason or ("HTTP " .. tostring(code))
		s.lastError = err

		-- Netzfehler, 408, 429 und 5xx sind vorübergehend. Andere 4xx (z. B. gelöschter Webhook) nicht.
		local transient = code == nil or code == 408 or code == 429 or code >= 500
		if transient then
			ep.failures = ep.failures + 1
			ep.nextAttempt = now + (code == 429 and retryAfter(headers, body) or backoff(ep))
		end

		if transient and batch.attempts <= ep.retries and ep.enabled then
			s.retries = s.retries + 1
			ep.retry = batch
		else
			s.failed = s.failed + #batch.jobs
			warnThrottled(self, ep, "Anfrage fehlgeschlagen (" .. err .. ", " .. batch.attempts .. " Versuch(e))")
			finishJobs(self, ep, batch.jobs, false, { code = code, body = body, headers = headers, error = err, attempts = batch.attempts, latency = latency })
		end
	end

	-- Kam die Antwort außerhalb eines Durchlaufs, gleich die nächste Nachricht senden
	if self.started and not self.pumping then self:Pump() end
end

-- Nimmt die nächste Nachricht. Mit merge werden weitere wartende Nachrichten angehängt, solange die
-- zusammengefasste Anfrage höchstens maxPayload Bytes hat.
local function takeBatch(self, ep)
	local first = table.remove(ep.queue, 1)
	local batch = { jobs = { first }, body = first.encoded, attempts = 0 }
	if not ep.merge then return batch end

	local bodies = { first.body }
	while ep.queue[1] and #batch.jobs < ep.mergeMax do
		bodies[#bodies + 1] = ep.queue[1].body
		local ok, merged = pcall(ep.merge, bodies)
		local encoded
		if ok and istable(merged) then
			ok, encoded = pcall(encodeJSON, merged)
		elseif ok and isstring(merged) then
			encoded = merged
		else
			ok = false
		end

		if not ok then
			warnThrottled(self, ep, "merge fehlgeschlagen: " .. tostring(encoded or merged))
			break
		end
		if #encoded > ep.maxPayload then break end

		batch.jobs[#batch.jobs + 1] = table.remove(ep.queue, 1)
		batch.body = encoded
	end

	ep.stats.merged = ep.stats.merged + #batch.jobs - 1
	return batch
end

local function dispatch(self, ep, batch, now)
	batch.attempts = batch.attempts + 1
	local token = {}
	ep.inflight = { token = token, batch = batch, started = now }
	ep.sentAt[#ep.sentAt + 1] = now
	ep.stats.requests = ep.stats.requests + 1

	local id = ep.id
	local request = {
		url = ep.url,
		method = ep.method,
		headers = ep.headers,
		body = batch.body ~= "" and batch.body or nil,
		type = ep.type,
		timeout = ep.timeout,
		success = function(code, body, headers) complete(self, id, token, code, body, headers, nil) end,
		failed = function(reason) complete(self, id, token, nil, nil, nil, tostring(reason or "failed")) end,
	}

	-- HTTP() liefert false, wenn die Anfrage nicht eingereiht wurde (z. B. -disablehttp)
	local ok, queued = pcall(self.transport, request)
	if not ok then
		complete(self, id, token, nil, nil, nil, "transport: " .. tostring(queued))
	elseif queued == false then
		complete(self, id, token, nil, nil, nil, "not_queued")
	end
end

local function pumpEndpoint(self, ep, now)
	-- Wächter: eine Anfrage ohne Antwort hält den Endpunkt nicht dauerhaft fest
	if ep.inflight and now - ep.inflight.started > ep.timeout + WATCHDOG_GRACE then
		complete(self, ep.id, ep.inflight.token, nil, nil, nil, "watchdog_timeout")
	end

	for _ = 1, 100 do
		if ep.inflight or not ep.enabled or self.endpoints[ep.id] ~= ep then return end
		if not ep.retry and not ep.queue[1] then return end
		if now < ep.nextAttempt or not rateAllows(ep, now) then return end

		local batch = ep.retry or takeBatch(self, ep)
		ep.retry = nil
		dispatch(self, ep, batch, now)
	end
end

------------------------------------------------------------------------
-- Öffentliche Methoden
------------------------------------------------------------------------

function Service:RegisterEndpoint(id, def)
	assert(isstring(id) and id ~= "", "HTTP.RegisterEndpoint: id fehlt")
	assert(istable(def), "HTTP.RegisterEndpoint: Definition fehlt (" .. id .. ")")
	assert(isstring(def.url) or isstring(def.urlSecret), "HTTP.RegisterEndpoint: url oder urlSecret fehlt (" .. id .. ")")
	local method = string.upper(def.method or "POST")
	assert(METHODS[method], "HTTP.RegisterEndpoint: ungültige Methode " .. tostring(def.method) .. " (" .. id .. ")")
	assert(def.merge == nil or isfunction(def.merge), "HTTP.RegisterEndpoint: merge ist keine Funktion (" .. id .. ")")

	local rate = def.rateLimit or {}
	local old = self.endpoints[id]

	local ep = {
		id = id,
		def = def,
		method = method,
		type = def.type or "application/json",
		timeout = math.Clamp(tonumber(def.timeout) or 10, 1, 60),
		maxPayload = math.Clamp(math.floor(tonumber(def.maxPayload) or 8192), 1, 1048576),
		rateCount = math.Clamp(math.floor(tonumber(rate.count) or 10), 1, 1000),
		ratePeriod = math.Clamp(tonumber(rate.perSeconds) or 60, 1, 86400),
		retries = math.Clamp(math.floor(tonumber(def.retries) or 2), 0, 5),
		queueSize = math.Clamp(math.floor(tonumber(def.queueSize) or 50), 1, 1000),
		merge = def.merge,
		mergeMax = math.Clamp(math.floor(tonumber(def.mergeMax) or 10), 1, 100),

		-- Laufzeitzustand bleibt bei erneuter Registrierung (Lua-Reload) erhalten
		enabled = old and old.enabled,
		queue = old and old.queue or {},
		retry = old and old.retry,
		inflight = old and old.inflight,
		sentAt = old and old.sentAt or {},
		nextAttempt = old and old.nextAttempt or 0,
		failures = old and old.failures or 0,
		lastWarn = old and old.lastWarn,
		stats = old and old.stats or newStats(),
	}
	self.endpoints[id] = ep

	local enabled, reason = resolve(self, ep)
	applyState(self, ep, enabled, reason)

	if LMNT.Modules and LMNT.Modules.TrackUndo then
		LMNT.Modules.TrackUndo(function() self:Unregister(id) end)
	end

	return enabled, reason
end

function Service:Unregister(id)
	local ep = self.endpoints[id]
	if not ep then return false end
	self.endpoints[id] = nil

	-- Laufende Anfrage: Antwort wird ignoriert, Callbacks laufen jetzt (genau einmal)
	if ep.inflight then
		local jobs = ep.inflight.batch.jobs
		ep.inflight = nil
		ep.stats.dropped = ep.stats.dropped + #jobs
		finishJobs(self, ep, jobs, false, { error = "unregistered", attempts = 0 })
	end
	dropQueued(self, ep, "unregistered")
	return true
end

function Service:IsEnabled(id)
	local ep = self.endpoints[id]
	return ep ~= nil and ep.enabled == true
end

function Service:Send(id, body, callback)
	local ep = self.endpoints[id]
	if not ep then
		local key = tostring(id)
		if not self.warnedUnknown[key] then
			self.warnedUnknown[key] = true
			log(self, "Warn", "Send an unbekannten Endpunkt '" .. key .. "' abgelehnt – vorher LMNT.HTTP.RegisterEndpoint aufrufen")
		end
		return false, "unknown_endpoint"
	end
	if not ep.enabled then return false, "disabled" end

	local encoded
	if istable(body) then
		local ok, result = pcall(encodeJSON, body)
		if not ok then
			warnThrottled(self, ep, "Body nicht kodierbar: " .. tostring(result))
			return false, "invalid_body"
		end
		encoded = result
	elseif isstring(body) then
		encoded = body
	elseif body == nil then
		encoded = ""
	else
		return false, "invalid_body"
	end

	if #encoded > ep.maxPayload then
		ep.stats.dropped = ep.stats.dropped + 1
		warnThrottled(self, ep, "Nachricht verworfen, " .. #encoded .. " Bytes > maxPayload " .. ep.maxPayload)
		return false, "payload_too_large"
	end
	if #ep.queue >= ep.queueSize then
		ep.stats.dropped = ep.stats.dropped + 1
		warnThrottled(self, ep, "Warteschlange voll (" .. ep.queueSize .. "), Nachricht verworfen")
		return false, "queue_full"
	end

	ep.queue[#ep.queue + 1] = { body = body, encoded = encoded, callback = isfunction(callback) and callback or nil }
	if self.started then self:Pump() end
	return true
end

-- Ein Durchlauf über alle Endpunkte: Wächter, Wiederholungen, Rate-Limit, Senden
function Service:Pump()
	if self.pumping then return end
	self.pumping = true
	local now = self.clock()
	for _, ep in ipairs(endpointList(self)) do
		local ok, err = pcall(pumpEndpoint, self, ep, now)
		if not ok then log(self, "Warn", "Warteschlange von '" .. ep.id .. "' fehlerhaft: " .. tostring(err)) end
	end
	self.pumping = false
end

-- Liest secrets.json neu und aktiviert bzw. deaktiviert die Endpunkte entsprechend. -> Anzahl aktiver
function Service:ReloadSecrets()
	self.secrets, self.secretsProblem = readSecrets(self)
	local active = 0
	for _, ep in ipairs(endpointList(self)) do
		local enabled, reason = resolve(self, ep)
		applyState(self, ep, enabled, reason)
		if enabled then active = active + 1 end
	end
	return active
end

-- Kopie der Zähler. Enthält bewusst weder URL noch Header.
function Service:Stats()
	local out = {}
	for id, ep in pairs(self.endpoints) do
		local s = ep.stats
		out[id] = {
			enabled = ep.enabled == true,
			reason = ep.reason,
			sent = s.sent,
			failed = s.failed,
			dropped = s.dropped,
			merged = s.merged,
			retries = s.retries,
			requests = s.requests,
			queued = #ep.queue + (ep.retry and #ep.retry.jobs or 0),
			inflight = ep.inflight ~= nil,
			lastLatency = s.lastLatency,
			lastCode = s.lastCode,
			lastError = s.lastError,
			lastSuccess = s.lastSuccess,
		}
	end
	return out
end

--[[
	opts.transport  function(request) -> bool   Standard: HTTP (GMod)
	opts.clock      function() -> Sekunden      Standard: SysTime
	opts.secrets    Tabelle statt secrets.json  (Tests)
	opts.quiet      true = keine Log-Einträge   (Tests)
	opts.started    true = Send sendet sofort; sonst erst ab dem ersten Timer-Takt
]]
local function newService(opts)
	opts = opts or {}
	local self = setmetatable({
		endpoints = {},
		transport = opts.transport or function(request) return HTTP(request) end,
		clock = opts.clock or SysTime,
		secretSource = opts.secrets,
		quiet = opts.quiet == true,
		started = opts.started == true,
		pumping = false,
		warnedUnknown = {},
	}, Service)
	self.secrets, self.secretsProblem = readSecrets(self)
	return self
end

------------------------------------------------------------------------
-- Globale Instanz: LMNT.HTTP.Send(...) usw. (Punkt-Syntax wie im restlichen Framework)
------------------------------------------------------------------------

local default = LMNT.HTTP and LMNT.HTTP._service
if default then
	setmetatable(default, Service) -- Lua-Reload: Zustand behalten, neue Methoden verwenden
else
	default = newService()
end

LMNT.HTTP = { _service = default, New = newService, EncodeJSON = encodeJSON }
for _, method in ipairs({ "RegisterEndpoint", "Unregister", "IsEnabled", "Send", "Pump", "ReloadSecrets", "Stats" }) do
	LMNT.HTTP[method] = function(...) return default[method](default, ...) end
end

-- Gesendet wird nur im Timer-Takt (nie während des Ladens). Wiederholungen und Wächter brauchen
-- ebenfalls diesen Takt. Hinweis: Bei leerem Server (Hibernation) laufen keine Timer, siehe http.md.
timer.Create("LMNT.HTTP.Pump", PUMP_INTERVAL, 0, function()
	default.started = true
	default:Pump()
end)

------------------------------------------------------------------------
-- Erste Nutzung: Discord-Webhook für Sicherheitsmeldungen
------------------------------------------------------------------------

LMNT.Discord = LMNT.Discord or {}
local D = LMNT.Discord

D.ENDPOINT = "discord.security"
D.COLOR = 0xFF3131 -- LMNT-Rot (--acid, docs/framework/05_DESIGNSYSTEM.md)

local FLUSH_INTERVAL = 5      -- Sekunden: Einträge sammeln und gebündelt senden
local MAX_BUFFER = 50         -- Einträge pro Bündel, weitere werden nur gezählt
local ENTRY_MAX = 300         -- Bytes Log-Text pro Eintrag
local DESCRIPTION_MAX = 3500  -- Bytes pro Embed (Discord: 4096 Zeichen pro Embed, 6000 pro Nachricht)
local IGNORED_CATEGORIES = { http = true, discord = true } -- Störungen des Dienstes nie weiterleiten

-- Nur echte Discord-Webhook-URLs, damit Logs nicht an beliebige Hosts gehen
D.URL_PATTERNS = {}
for _, host in ipairs({ "discord%.com", "discordapp%.com", "canary%.discord%.com", "ptb%.discord%.com" }) do
	D.URL_PATTERNS[#D.URL_PATTERNS + 1] = "^https://" .. host .. "/api/v?%d*/?webhooks/%d+/[%w_%-]+"
end

LMNT.Settings.Define("lmnt.discord.enabled", {
	type = "bool", default = true, category = "Discord", applies = "live",
	desc = "Log-Meldungen an Discord senden (Webhook-URL steht nur in data/lmnt/secrets.json)",
	onChange = function(new) if not new then D.Clear() end end,
})
LMNT.Settings.Define("lmnt.discord.min_level", {
	type = "enum", default = "security", choices = { "security", "error" }, category = "Discord", applies = "live",
	desc = "Ab welcher Log-Stufe weitergeleitet wird (error schließt security ein)",
})
LMNT.Settings.Define("lmnt.discord.redact_ids", {
	type = "bool", default = true, category = "Discord", applies = "live",
	desc = "SteamIDs in Discord-Meldungen durch [SteamID] ersetzen (IP-Adressen werden immer entfernt)",
})

-- Schneidet nach Bytes, aber nie mitten in einem UTF-8-Zeichen
local function cutUtf8(s, maxBytes)
	if #s <= maxBytes then return s end
	local cut = maxBytes
	while cut > 0 do
		local b = string.byte(s, cut + 1)
		if b < 0x80 or b >= 0xC0 then break end -- nächstes Byte beginnt ein Zeichen
		cut = cut - 1
	end
	return string.sub(s, 1, cut)
end

-- Personenbezogene Daten reduzieren: IP-Adressen immer, SteamIDs je nach Einstellung
local function redact(s, redactIds)
	s = string.gsub(s, "%d+%.%d+%.%d+%.%d+:?%d*", "[IP]")
	if redactIds then
		s = string.gsub(s, "STEAM_%d:%d:%d+", "[SteamID]")
		s = string.gsub(s, "7656119%d%d%d%d%d%d%d%d%d%d", "[SteamID]")
	end
	return s
end

-- Discord-Markdown entschärfen (Spielernamen und Chat landen in Logs)
local function escapeMarkdown(s)
	return (string.gsub(s, "[\\%*_~`|>%[%]<#]", "\\%0"))
end

function D.ShouldForward(level, category, minLevel)
	local levels = LMNT.Log.Levels
	if IGNORED_CATEGORIES[category] then return false end
	if not levels[level] or not levels[minLevel] then return false end
	return levels[level] >= levels[minLevel]
end

-- entries: { { time, level, category, message } }, suppressed: zusätzlich verworfene Einträge
function D.BuildPayload(entries, suppressed, redactIds)
	suppressed = suppressed or 0
	local lines, used, shown = {}, 0, 0
	local hasSecurity, hasError = false, false

	for _, entry in ipairs(entries) do
		if entry.level == "security" then hasSecurity = true else hasError = true end

		local text = string.gsub(tostring(entry.message or ""), "%s+", " ")
		text = redact(text, redactIds)
		local cut = cutUtf8(text, ENTRY_MAX)
		if cut ~= text then cut = cut .. "…" end

		local category = cutUtf8(tostring(entry.category or ""), 48)
		local line = string.format("`%s` **%s** · %s: %s", os.date("%H:%M:%S", entry.time or os.time()),
			string.upper(tostring(entry.level)), escapeMarkdown(category), escapeMarkdown(cut))
		-- Platz für den Hinweis auf weitere Einträge freihalten
		if used + #line + 1 > DESCRIPTION_MAX - 80 then break end
		lines[#lines + 1] = line
		used = used + #line + 1
		shown = shown + 1
	end

	local omitted = #entries - shown + suppressed
	if omitted > 0 then
		lines[#lines + 1] = "… und " .. omitted .. " weitere Einträge (siehe Server-Log)"
	end

	local title = hasSecurity and hasError and "Sicherheits- und Fehlermeldungen"
		or hasError and "Fehlermeldungen" or "Sicherheitsmeldungen"

	return {
		allowed_mentions = { parse = {} }, -- nie @everyone, @here, Rollen oder Nutzer anpingen
		embeds = { {
			title = title .. " (" .. (#entries + suppressed) .. ")",
			description = table.concat(lines, "\n"),
			color = D.COLOR,
			timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
			footer = { text = LMNT.Config.ServerName or "LMNT" },
		} },
	}
end

-- Wartende Bündel zu einer Nachricht zusammenfassen (Discord: höchstens 10 Embeds pro Nachricht)
function D.Merge(bodies)
	local out = { allowed_mentions = { parse = {} }, embeds = {} }
	for _, body in ipairs(bodies) do
		for _, embed in ipairs(body.embeds or {}) do out.embeds[#out.embeds + 1] = embed end
	end
	return out
end

LMNT.HTTP.RegisterEndpoint(D.ENDPOINT, {
	urlSecret = "discord_webhook_security",
	urlPattern = D.URL_PATTERNS,
	method = "POST",
	type = "application/json",
	timeout = 10,
	maxPayload = 6000, -- Bytes inkl. JSON, damit bleibt auch der Embed-Text unter dem Discord-Limit
	rateLimit = { count = 10, perSeconds = 60 },
	retries = 3,
	queueSize = 20,
	merge = D.Merge,
	mergeMax = 10,
})

local buffer, suppressed = {}, 0

function D.Clear()
	buffer, suppressed = {}, 0
end

function D.Pending()
	return #buffer, suppressed
end

LMNT.Events.On("lmnt.log.written", "LMNT.Discord.Forward", function(level, category, message)
	if not D.ShouldForward(level, category, LMNT.Settings.Get("lmnt.discord.min_level")) then return end
	if not LMNT.Settings.Get("lmnt.discord.enabled") or not LMNT.HTTP.IsEnabled(D.ENDPOINT) then return end

	if #buffer >= MAX_BUFFER then
		suppressed = suppressed + 1
		return
	end
	buffer[#buffer + 1] = { time = os.time(), level = level, category = tostring(category), message = tostring(message) }
end, { owner = "discord" })

-- Sendet das gesammelte Bündel. -> true | false, grund | nil (nichts zu senden)
function D.Flush()
	if #buffer == 0 and suppressed == 0 then return nil end
	local entries, extra = buffer, suppressed
	D.Clear()
	return LMNT.HTTP.Send(D.ENDPOINT, D.BuildPayload(entries, extra, LMNT.Settings.Get("lmnt.discord.redact_ids")))
end

timer.Create("LMNT.Discord.Flush", FLUSH_INTERVAL, 0, D.Flush)
