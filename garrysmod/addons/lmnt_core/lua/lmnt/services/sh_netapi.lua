--[[
	LMNT Framework – Netzwerk-Dienst LMNT.Net (T-030, T-092)
	API-Referenz: docs/framework/api/net.md

	Jede Nachricht wird GETEILT registriert (sh_-Datei), damit Server und Client dasselbe Schema kennen.
	Schreiben und Lesen laufen nach Schema. Eingehende Pakete prüft der Server vor dem Handler in dieser
	Reihenfolge: Richtung -> Größe (len, vor dem Lesen) -> Rate-Limit -> Recht -> Schema.
	Verstoß: verwerfen, security-Log (gedrosselt, ohne Paketinhalt), Event lmnt.net.violation,
	Verstoßpunkte mit Zeitverfall, ab lmnt.net.kick_threshold Kick mit neutraler Meldung.

	LMNT.Net.Register("lmnt_shop_buy", {
		direction = "c2s",                         -- c2s | s2c | both
		schema = {
			{ name = "id", type = "string", max = 64 },
			{ name = "anzahl", type = "uint", bits = 8, min = 1, max = 200 },
		},
		perm = "shop.buy",                         -- c2s/both: Pflicht. false = jeder verbundene Spieler
		rateLimit = { count = 5, perSeconds = 1 }, -- Standard 10 pro 1 s
		maxBits = 1024,                            -- optional, sonst aus dem Schema berechnet
		handler = function(ply, data) end,         -- Server: ply = Absender · Client: ply = nil
	})
	LMNT.Net.Receive(name, fn)               Handler im aktuellen Realm setzen (z. B. in einer sv_-/cl_-Datei)
	LMNT.Net.Send(name, data, ziel)          Server -> Client (Spieler, Spielerliste, RecipientFilter, nil = alle)
	LMNT.Net.SendToServer(name, data)        Client -> Server
	LMNT.Net.Stats()                         -> { [name] = { received, bytesIn, dropped, violations, ... } }
	LMNT.Net.Get(name), LMNT.Net.List()      Definitionen (Kopie) bzw. sortierte Namen

	Typen: string (max), uint/int (bits, min, max), bool, float (min, max), entity, player,
	       list (max, of) und record (fields) – Tabellen gibt es nur mit festen Grenzen.

	Testbare Bausteine ohne Netzwerk: CompileSchema, Validate, Encode, Decode, NewBuffer, NewLimiter,
	NewViolationCounter, NewRegistry, NewGuard (Tests: lua/lmnt/tests/sv_netapi.lua)
]]

LMNT.Net = LMNT.Net or {}
local N = LMNT.Net

-- Wiki (net.Start): höchstens 65.533 Byte je Nachricht; net.BytesWritten zählt 3 Byte Verwaltung mit
local NET_MAX_BYTES = 65530
local NET_MAX_BITS = NET_MAX_BYTES * 8
local MAX_DEPTH = 3                 -- Schema = Ebene 1, darunter höchstens zwei Ebenen list/record
local MAX_LIST = 65535
local DEFAULT_RATE = { count = 10, perSeconds = 1 }
local CLIENT_RATE_FACTOR = 1.1      -- Client drosselt sich etwas strenger als der Server prüft (Jitter)
local LOG_INTERVAL = 10             -- Sekunden zwischen zwei security-Logs je Spieler, Nachricht und Grund
local KICK_TEXT = "Die Verbindung wurde vom Server getrennt (Netzwerkfehler)."

-- Verstoßpunkte je Grund. Ein kurzer Flood kann bei Lag auch von einem normalen Client kommen,
-- falsche Richtung oder kaputte Pakete schickt ein unveränderter Client nie.
N.Weights = { rate = 1, perm = 2, size = 5, schema = 5, direction = 10 }

local DIRECTIONS = { c2s = true, s2c = true, both = true }

------------------------------------------------------------------------
-- Hilfsfunktionen
------------------------------------------------------------------------

local function isFinite(v)
	return isnumber(v) and v == v and v ~= math.huge and v ~= -math.huge
end

local function isInt(v)
	return isFinite(v) and math.floor(v) == v
end

-- kleinste Bitzahl für 0..n
local function bitsFor(n)
	local b = 1
	while b < 32 and 2 ^ b - 1 < n do b = b + 1 end
	return b
end

-- kleinste Bitzahl (vorzeichenbehaftet) für lo..hi
local function signedBitsFor(lo, hi)
	local b = 2
	while b < 32 and (-(2 ^ (b - 1)) > lo or 2 ^ (b - 1) - 1 < hi) do b = b + 1 end
	return b
end

-- Länge einer lückenlosen Liste 1..n, sonst nil (verlässt sich nicht darauf, was # bei Lücken liefert)
local function seqLength(t)
	local count = 0
	for k in pairs(t) do
		if not isInt(k) or k < 1 then return nil end
		count = count + 1
	end
	for i = 1, count do
		if t[i] == nil then return nil end
	end
	return count
end

local function where(path)
	return path and ("Feld '" .. path .. "': ") or ""
end

-- Server: strukturiertes Log, Client: Konsole
local function logLine(level, text)
	if SERVER and LMNT.Log and LMNT.Log.Write then
		LMNT.Log.Write(level, "net", text)
	else
		MsgC(Color(255, 176, 32), "[LMNT][net] ", color_white, text .. "\n")
	end
end

------------------------------------------------------------------------
-- Schema kompilieren (Fehler hier sind Entwicklerfehler)
------------------------------------------------------------------------

-- Schemafehler werden als Tabelle geworfen und von catch() in einen Rückgabewert verwandelt,
-- damit die öffentliche Funktion mit Ebene 2 auf die Zeile des Aufrufers zeigen kann.
local SchemaError = {}

local function fail(path, text)
	error(setmetatable({ text = where(path ~= "" and path or nil) .. text }, SchemaError), 0)
end

local function catch(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then return res end
	if getmetatable(res) == SchemaError then return nil, res.text end
	error(res, 0) -- echter Programmfehler: unverändert weiterreichen
end

local COMMON_KEYS = { name = true, type = true, optional = true, desc = true }
local FIELD_KEYS = {
	string = { max = true, min = true, utf8 = true, pattern = true },
	uint = { bits = true, min = true, max = true },
	int = { bits = true, min = true, max = true },
	bool = {},
	float = { min = true, max = true },
	entity = { allowNull = true, class = true },
	player = { allowNull = true },
	list = { max = true, min = true, of = true },
	record = { fields = true },
}

local compileFields

local function compileField(f, depth, path)
	if not istable(f) then fail(path, "Definition ist keine Tabelle") end
	local t = f.type
	local allowed = FIELD_KEYS[t]
	if not allowed then fail(path, "unbekannter Typ '" .. tostring(t) .. "' (erlaubt: string, uint, int, bool, float, entity, player, list, record)") end
	for k in pairs(f) do
		if not COMMON_KEYS[k] and not allowed[k] then fail(path, "unbekannter Schlüssel '" .. tostring(k) .. "' für Typ " .. t) end
	end

	local c = { type = t, name = f.name, optional = f.optional == true }

	if t == "string" then
		if not isInt(f.max) or f.max < 1 or f.max > NET_MAX_BYTES - 1 then fail(path, "string braucht max (1–" .. (NET_MAX_BYTES - 1) .. " Byte)") end
		c.max, c.min = f.max, f.min or 0
		if not isInt(c.min) or c.min < 0 or c.min > c.max then fail(path, "min muss zwischen 0 und max liegen") end
		c.utf8 = f.utf8 ~= false
		if f.pattern ~= nil then
			if not isstring(f.pattern) or f.pattern == "" or not pcall(string.find, "", f.pattern) then fail(path, "pattern ist kein gültiges Lua-Muster") end
			c.pattern = f.pattern
		end
		c.minBits, c.maxBits = (c.min + 1) * 8, (c.max + 1) * 8
	elseif t == "uint" then
		local bits = f.bits
		if bits == nil then
			if not isInt(f.max) or f.max < 0 then fail(path, "uint braucht bits oder max") end
			bits = bitsFor(f.max)
		end
		if not isInt(bits) or bits < 1 or bits > 32 then fail(path, "bits muss 1–32 sein") end
		local hi = 2 ^ bits - 1
		c.bits, c.min, c.max = bits, f.min or 0, f.max or hi
		if not isInt(c.min) or not isInt(c.max) or c.min < 0 or c.max > hi or c.min > c.max then
			fail(path, "min/max müssen ganze Zahlen mit 0 ≤ min ≤ max ≤ " .. hi .. " sein")
		end
		c.minBits, c.maxBits = bits, bits
	elseif t == "int" then
		local bits = f.bits
		if bits == nil then
			if not isInt(f.min) or not isInt(f.max) then fail(path, "int braucht bits oder min und max") end
			bits = signedBitsFor(f.min, f.max)
		end
		if not isInt(bits) or bits < 2 or bits > 32 then fail(path, "bits muss 2–32 sein") end
		local lo, hi = -(2 ^ (bits - 1)), 2 ^ (bits - 1) - 1
		c.bits, c.min, c.max = bits, f.min or lo, f.max or hi
		if not isInt(c.min) or not isInt(c.max) or c.min < lo or c.max > hi or c.min > c.max then
			fail(path, "min/max müssen ganze Zahlen mit " .. lo .. " ≤ min ≤ max ≤ " .. hi .. " sein")
		end
		c.minBits, c.maxBits = bits, bits
	elseif t == "bool" then
		c.bits = 1
		c.minBits, c.maxBits = 1, 1
	elseif t == "float" then
		-- net.WriteFloat überträgt 32 Bit (Wiki: Net_Library_Usage)
		if not isFinite(f.min) or not isFinite(f.max) or f.min > f.max then fail(path, "float braucht endliche Grenzen min ≤ max") end
		c.bits, c.min, c.max = 32, f.min, f.max
		c.minBits, c.maxBits = 32, 32
	elseif t == "entity" then
		-- net.WriteEntity schreibt den Index mit MAX_EDICT_BITS Bit (garrysmod/lua/includes/extensions/net.lua)
		if not isInt(MAX_EDICT_BITS) then fail(path, "MAX_EDICT_BITS fehlt (GMod-Version zu alt)") end
		c.bits = MAX_EDICT_BITS
		c.allowNull = f.allowNull == true
		if f.class ~= nil then
			local list = isstring(f.class) and { f.class } or f.class
			if not istable(list) or #list == 0 then fail(path, "class muss ein Klassenname oder eine Liste davon sein") end
			c.classes = {}
			for _, cls in ipairs(list) do
				if not isstring(cls) or cls == "" then fail(path, "class enthält einen ungültigen Eintrag") end
				c.classes[cls] = true
			end
		end
		c.minBits, c.maxBits = c.bits, c.bits
	elseif t == "player" then
		-- net.WritePlayer schreibt den Index mit MAX_PLAYER_BITS Bit (hängt von den Server-Slots ab)
		if not isInt(MAX_PLAYER_BITS) then fail(path, "MAX_PLAYER_BITS fehlt (GMod-Version zu alt)") end
		c.bits = MAX_PLAYER_BITS
		c.allowNull = f.allowNull == true
		c.minBits, c.maxBits = c.bits, c.bits
	elseif t == "list" then
		if depth >= MAX_DEPTH then fail(path, "zu tief verschachtelt (höchstens " .. (MAX_DEPTH - 1) .. " Ebenen list/record)") end
		if not isInt(f.max) or f.max < 1 or f.max > MAX_LIST then fail(path, "list braucht max (1–" .. MAX_LIST .. " Einträge)") end
		c.max, c.min = f.max, f.min or 0
		if not isInt(c.min) or c.min < 0 or c.min > c.max then fail(path, "min muss zwischen 0 und max liegen") end
		if not istable(f.of) then fail(path, "list braucht of = { type = ... }") end
		if f.of.optional then fail(path, "Listeneinträge können nicht optional sein") end
		if f.of.name ~= nil then fail(path, "Listeneinträge haben keinen Namen") end
		c.of = compileField(f.of, depth + 1, path .. "[]")
		c.countBits = bitsFor(c.max)
		c.minBits = c.countBits + c.min * c.of.minBits
		c.maxBits = c.countBits + c.max * c.of.maxBits
	elseif t == "record" then
		if depth >= MAX_DEPTH then fail(path, "zu tief verschachtelt (höchstens " .. (MAX_DEPTH - 1) .. " Ebenen list/record)") end
		local rec = compileFields(f.fields, depth + 1, path)
		c.fields, c.byName, c.minBits, c.maxBits = rec.fields, rec.byName, rec.minBits, rec.maxBits
	end

	if c.optional then
		c.minBits = 1               -- nur das Vorhanden-Bit
		c.maxBits = c.maxBits + 1
	end
	return c
end

compileFields = function(list, depth, path)
	if not istable(list) then fail(path, "schema/fields muss eine Liste von Feldern sein") end
	if not seqLength(list) then fail(path, "schema/fields muss eine fortlaufende Liste sein") end

	local rec = { type = "record", fields = {}, byName = {}, minBits = 0, maxBits = 0 }
	for i, f in ipairs(list) do
		local fname = istable(f) and f.name
		if not isstring(fname) or not string.match(fname, "^[%a_][%w_]*$") then
			fail(path, "Feld " .. i .. " braucht einen Namen aus Buchstaben, Ziffern und _")
		end
		local sub = path == "" and fname or (path .. "." .. fname)
		if rec.byName[fname] then fail(sub, "Name doppelt vergeben") end
		local c = compileField(f, depth, sub)
		rec.fields[i] = c
		rec.byName[fname] = c
		rec.minBits = rec.minBits + c.minBits
		rec.maxBits = rec.maxBits + c.maxBits
	end
	return rec
end

-- Eindeutige Beschreibung eines kompilierten Schemas (für den Vergleich bei erneuter Registrierung)
local function signature(c)
	local t = c.type
	local s
	if t == "record" then
		local parts = {}
		for i, f in ipairs(c.fields) do parts[i] = signature(f) end
		s = "{" .. table.concat(parts, ",") .. "}"
	elseif t == "list" then
		s = "list(" .. c.min .. "-" .. c.max .. ")[" .. signature(c.of) .. "]"
	elseif t == "string" then
		s = "string(" .. c.min .. "-" .. c.max .. (c.utf8 and ",utf8" or "") .. (c.pattern and (",p=" .. c.pattern) or "") .. ")"
	elseif t == "uint" or t == "int" then
		s = t .. c.bits .. "(" .. c.min .. "-" .. c.max .. ")"
	elseif t == "float" then
		s = string.format("float(%.17g-%.17g)", c.min, c.max)
	elseif t == "entity" then
		local cls = {}
		for k in pairs(c.classes or {}) do cls[#cls + 1] = k end
		table.sort(cls)
		s = "entity(" .. (c.allowNull and "null;" or "") .. table.concat(cls, "|") .. ")"
	elseif t == "player" then
		s = "player(" .. (c.allowNull and "null" or "") .. ")"
	else
		s = t
	end
	return (c.name and (c.name .. "=") or "") .. s .. (c.optional and "?" or "")
end

-- Schema -> kompilierte Beschreibung (wirft bei ungültigem Schema einen Fehler)
function N.CompileSchema(schema)
	local spec, err = catch(compileFields, schema or {}, 1, "")
	if not spec then error("LMNT.Net.CompileSchema: " .. err, 2) end
	return spec
end

------------------------------------------------------------------------
-- Werte prüfen
------------------------------------------------------------------------

-- mode: "send" (eigene Daten vor dem Senden), "server" (eingehend vom Client, streng),
--       "client" (eingehend vom Server; Entities außerhalb des PVS sind dort NULL und werden durchgelassen)
local function checkScalar(c, v, mode)
	local t = c.type
	if t == "string" then
		if not isstring(v) then return false, "erwartet Text" end
		if #v > c.max then return false, "länger als " .. c.max .. " Byte" end
		if #v < c.min then return false, "kürzer als " .. c.min .. " Byte" end
		-- net.WriteString bricht am ersten Nullbyte ab (Wiki); der Rest ginge stillschweigend verloren
		if string.find(v, "\0", 1, true) then return false, "enthält ein Nullbyte" end
		if c.utf8 and mode == "server" and not utf8.len(v) then return false, "kein gültiges UTF-8" end
		if c.pattern and not string.find(v, c.pattern) then return false, "passt nicht zum erlaubten Muster" end
	elseif t == "uint" or t == "int" then
		if not isInt(v) then return false, "erwartet eine ganze Zahl" end
		if v < c.min or v > c.max then return false, "außerhalb " .. c.min .. "–" .. c.max end
	elseif t == "bool" then
		if not isbool(v) then return false, "erwartet true/false" end
	elseif t == "float" then
		if not isFinite(v) then return false, "erwartet eine endliche Zahl" end
		if v < c.min or v > c.max then return false, "außerhalb " .. c.min .. "–" .. c.max end
	elseif t == "entity" or t == "player" then
		if not IsValid(v) then
			if c.allowNull or mode == "client" then return true end
			return false, t == "player" and "kein gültiger Spieler" or "keine gültige Entity"
		end
		if t == "player" then
			if not v:IsPlayer() then return false, "kein Spieler" end
		else
			if mode == "send" and v:EntIndex() < 0 then return false, "Entity ist nicht vernetzt (nur clientseitig)" end
			if c.classes and not c.classes[v:GetClass()] then return false, "Entity-Klasse nicht erlaubt" end
		end
	end
	return true
end

local validateRecord

-- Rückgabe: true, bits | false, grund, pfad
local function validateField(c, v, mode)
	local t = c.type
	if v == nil then
		if c.optional then return true, 1 end
		-- allowNull: nil bedeutet "keine Entity" (Lua-Tabellen können NULL nicht von "fehlt" trennen)
		if (t == "entity" or t == "player") and c.allowNull then return true, c.bits end
		return false, "fehlt"
	end

	local bits
	if t == "list" then
		if not istable(v) then return false, "erwartet eine Liste" end
		local n = seqLength(v)
		if not n then return false, "Liste mit Lücken oder fremden Schlüsseln" end
		if n < c.min or n > c.max then return false, "Liste muss " .. c.min .. "–" .. c.max .. " Einträge haben" end
		bits = c.countBits
		for i = 1, n do
			local ok, b, sub = validateField(c.of, v[i], mode)
			if not ok then return false, b, "[" .. i .. "]" .. (sub or "") end
			bits = bits + b
		end
	elseif t == "record" then
		local ok, b, sub = validateRecord(c, v, mode)
		if not ok then return false, b, sub end
		bits = b
	else
		local ok, reason = checkScalar(c, v, mode)
		if not ok then return false, reason end
		bits = t == "string" and (#v + 1) * 8 or c.bits
	end
	return true, bits + (c.optional and 1 or 0)
end

validateRecord = function(c, v, mode)
	if not istable(v) then return false, "erwartet eine Tabelle" end
	for k in pairs(v) do
		if not c.byName[k] then return false, "unbekanntes Feld '" .. tostring(k) .. "'" end
	end
	local bits = 0
	for _, f in ipairs(c.fields) do
		local ok, b, sub = validateField(f, v[f.name], mode)
		if not ok then return false, b, "." .. f.name .. (sub or "") end
		bits = bits + b
	end
	return true, bits
end

local function stripPath(path)
	if path and string.sub(path, 1, 1) == "." then return string.sub(path, 2) end
	return path
end

-- Prüft Daten gegen ein kompiliertes Schema (Sendeseite). Rückgabe: true, bits | false, grund, pfad
function N.Validate(spec, data)
	local ok, bits, path = validateRecord(spec, data == nil and {} or data, "send")
	if ok then return true, bits end
	return false, bits, stripPath(path)
end

------------------------------------------------------------------------
-- Schreiben und Lesen (Writer/Reader: echte net-Bibliothek oder NewBuffer)
------------------------------------------------------------------------

local function writeField(c, v, w)
	if c.optional then
		w:WriteBool(v ~= nil)
		if v == nil then return end
	end
	local t = c.type
	if t == "record" then
		for _, f in ipairs(c.fields) do writeField(f, v[f.name], w) end
	elseif t == "list" then
		w:WriteUInt(#v, c.countBits)
		for i = 1, #v do writeField(c.of, v[i], w) end
	elseif t == "string" then
		w:WriteString(v)
	elseif t == "uint" then
		w:WriteUInt(v, c.bits)
	elseif t == "int" then
		w:WriteInt(v, c.bits)
	elseif t == "bool" then
		w:WriteBool(v)
	elseif t == "float" then
		w:WriteFloat(v)
	elseif t == "entity" then
		w:WriteEntity(v == nil and NULL or v) -- ungültige Entity -> Index 0
	elseif t == "player" then
		w:WritePlayer(v == nil and NULL or v)
	end
end

-- Prüft und schreibt Daten. Rückgabe: Anzahl Bits. Ungültige Daten -> Fehler für den Entwickler.
function N.Encode(spec, data, writer)
	local ok, bits, path = N.Validate(spec, data)
	if not ok then error("LMNT.Net.Encode: " .. where(path) .. bits, 2) end
	writeField(spec, data == nil and {} or data, writer)
	return bits
end

-- float32 rundet: knapp außerhalb der Grenze liegende Werte auf die Grenze ziehen statt verwerfen
local function clampFloat(c, v)
	if not isFinite(v) then return v end
	if v < c.min and v >= c.min - math.max(math.abs(c.min), 1) * 1e-6 then return c.min end
	if v > c.max and v <= c.max + math.max(math.abs(c.max), 1) * 1e-6 then return c.max end
	return v
end

local SHORT = "Paket zu kurz"
local readRecord

-- st = { used = gelesene Bits, len = Paketlänge in Bit, mode }. Rückgabe: true, wert | false, grund, pfad
local function readField(c, r, st)
	if c.optional then
		st.used = st.used + 1
		if st.used > st.len then return false, SHORT end
		if not r:ReadBool() then return true, nil end
	end

	local t = c.type
	if t == "record" then
		return readRecord(c, r, st)
	elseif t == "list" then
		st.used = st.used + c.countBits
		if st.used > st.len then return false, SHORT end
		local n = r:ReadUInt(c.countBits)
		if not isInt(n) or n < c.min or n > c.max then return false, "Liste muss " .. c.min .. "–" .. c.max .. " Einträge haben" end
		local out = {}
		for i = 1, n do
			local ok, v, sub = readField(c.of, r, st)
			if not ok then return false, v, "[" .. i .. "]" .. (sub or "") end
			out[i] = v
		end
		return true, out
	end

	local v
	if t == "string" then
		v = r:ReadString()
		if not isstring(v) then return false, "erwartet Text" end
		st.used = st.used + (#v + 1) * 8
		if st.used > st.len then return false, SHORT end
	else
		-- Länge vor dem Lesen prüfen: net liest über das Ende hinaus sonst Nullwerte
		st.used = st.used + c.bits
		if st.used > st.len then return false, SHORT end
		if t == "uint" then v = r:ReadUInt(c.bits)
		elseif t == "int" then v = r:ReadInt(c.bits)
		elseif t == "bool" then v = r:ReadBool()
		elseif t == "float" then v = clampFloat(c, r:ReadFloat())
		elseif t == "entity" then v = r:ReadEntity()
		else v = r:ReadPlayer() end
	end

	local ok, reason = checkScalar(c, v, st.mode)
	if not ok then return false, reason end
	if (t == "entity" or t == "player") and not IsValid(v) then v = NULL end
	return true, v
end

readRecord = function(c, r, st)
	local out = {}
	for _, f in ipairs(c.fields) do
		local ok, v, sub = readField(f, r, st)
		if not ok then return false, v, "." .. f.name .. (sub or "") end
		out[f.name] = v
	end
	return true, out
end

-- Liest ein Paket nach Schema. len = Länge in Bit (wie im net.Receive-Callback).
-- mode: "server" (Standard, Clientdaten, streng) | "client". Rückgabe: data | nil, grund, pfad
-- Die Gründe enthalten nie Werte aus dem Paket, nur Feldnamen und Grenzen.
function N.Decode(spec, reader, len, mode)
	local st = { used = 0, len = len, mode = mode or "server" }
	local ok, data, path = readRecord(spec, reader, st)
	if not ok then return nil, data, stripPath(path) end
	-- len ist exakt (net.Incoming zieht nur den 16-Bit-Kopf ab); unter 8 Bit Rest gilt als Auffüllung
	if len - st.used >= 8 then return nil, "überzählige Daten (" .. (len - st.used) .. " Bit)" end
	return data
end

-- Adapter auf die echte net-Bibliothek (gleiche Methoden wie NewBuffer)
local NetIO = {}
function NetIO.WriteUInt(_, v, bits) net.WriteUInt(v, bits) end
function NetIO.WriteInt(_, v, bits) net.WriteInt(v, bits) end
function NetIO.WriteBool(_, v) net.WriteBool(v) end
function NetIO.WriteFloat(_, v) net.WriteFloat(v) end
function NetIO.WriteString(_, v) net.WriteString(v) end
function NetIO.WriteEntity(_, v) net.WriteEntity(v) end
function NetIO.WritePlayer(_, v) net.WritePlayer(v) end
function NetIO.ReadUInt(_, bits) return net.ReadUInt(bits) end
function NetIO.ReadInt(_, bits) return net.ReadInt(bits) end
function NetIO.ReadBool() return net.ReadBool() end
function NetIO.ReadFloat() return net.ReadFloat() end
function NetIO.ReadString() return net.ReadString() end
function NetIO.ReadEntity() return net.ReadEntity() end
function NetIO.ReadPlayer() return net.ReadPlayer() end

-- Testpuffer statt net: speichert Werte UNVERÄNDERT (ohne Bitmaske), damit Tests manipulierte Pakete
-- nachbilden können, und zählt die Bits wie die net-Bibliothek.
local Buffer = {}
Buffer.__index = Buffer

function N.NewBuffer()
	return setmetatable({ items = {}, n = 0, pos = 0, bits = 0 }, Buffer)
end

local function push(self, v, bits)
	self.n = self.n + 1
	self.items[self.n] = v
	self.bits = self.bits + bits
end

local function pop(self, default)
	self.pos = self.pos + 1
	if self.pos > self.n then return default end
	local v = self.items[self.pos]
	if v == nil then return default end
	return v
end

function Buffer:WriteUInt(v, bits) push(self, v, bits) end
function Buffer:WriteInt(v, bits) push(self, v, bits) end
function Buffer:WriteBool(v) push(self, v, 1) end
function Buffer:WriteFloat(v) push(self, v, 32) end
function Buffer:WriteString(v) push(self, v, (#v + 1) * 8) end
function Buffer:WriteEntity(v) push(self, v, MAX_EDICT_BITS) end
function Buffer:WritePlayer(v) push(self, v, MAX_PLAYER_BITS) end
function Buffer:ReadUInt() return pop(self, 0) end
function Buffer:ReadInt() return pop(self, 0) end
function Buffer:ReadBool() return pop(self, false) end
function Buffer:ReadFloat() return pop(self, 0) end
function Buffer:ReadString() return pop(self, "") end
function Buffer:ReadEntity() return pop(self, NULL) end
function Buffer:ReadPlayer() return pop(self, NULL) end
function Buffer:Bits() return self.bits end
function Buffer:Rewind() self.pos = 0 end

------------------------------------------------------------------------
-- Rate-Limiter (Token-Bucket je Schlüssel, Zeitverfall = Nachfüllen)
------------------------------------------------------------------------

local Limiter = {}
Limiter.__index = Limiter

-- count Pakete je perSeconds, Spitzen bis count auf einmal
function N.NewLimiter(count, perSeconds)
	assert(isInt(count) and count >= 1, "LMNT.Net.NewLimiter: count muss eine ganze Zahl ≥ 1 sein")
	assert(isFinite(perSeconds) and perSeconds > 0, "LMNT.Net.NewLimiter: perSeconds muss > 0 sein")
	return setmetatable({ count = count, per = perSeconds, buckets = {} }, Limiter)
end

local function refill(self, b, now)
	-- Zeit läuft nie rückwärts: ein kleinerer Zeitstempel bringt keine zusätzlichen Pakete
	local dt = math.max(0, now - b.t)
	b.tokens = math.min(self.count, b.tokens + dt * self.count / self.per)
	b.t = math.max(b.t, now)
end

function Limiter:Allow(key, now)
	local b = self.buckets[key]
	if not b then
		b = { tokens = self.count, t = now }
		self.buckets[key] = b
	else
		refill(self, b, now)
	end
	if b.tokens >= 1 then
		b.tokens = b.tokens - 1
		return true
	end
	return false
end

function Limiter:Reset(key)
	self.buckets[key] = nil
end

-- entfernt Schlüssel, deren Kontingent wieder voll ist (Speicher begrenzen)
function Limiter:Prune(now)
	for key, b in pairs(self.buckets) do
		refill(self, b, now)
		if b.tokens >= self.count then self.buckets[key] = nil end
	end
end

------------------------------------------------------------------------
-- Verstoßzähler je Spieler (Punkte mit linearem Zeitverfall)
------------------------------------------------------------------------

local Counter = {}
Counter.__index = Counter

-- decay: Punkte, die pro Minute verfallen (Zahl oder Funktion, die live gelesen wird)
function N.NewViolationCounter(decay)
	return setmetatable({ entries = {}, decay = decay or 0 }, Counter)
end

local function decayPerSecond(self)
	local d = self.decay
	if isfunction(d) then d = d() end
	return math.max(tonumber(d) or 0, 0) / 60
end

function Counter:Get(key, now)
	local e = self.entries[key]
	if not e then return 0 end
	return math.max(0, e.score - math.max(0, now - e.t) * decayPerSecond(self))
end

function Counter:Add(key, points, now)
	local score = self:Get(key, now) + points
	self.entries[key] = { score = score, t = math.max(now, self.entries[key] and self.entries[key].t or now) }
	return score
end

function Counter:Reset(key)
	self.entries[key] = nil
end

function Counter:Prune(now)
	for key in pairs(self.entries) do
		if self:Get(key, now) <= 0 then self.entries[key] = nil end
	end
end

------------------------------------------------------------------------
-- Registry: Definitionen prüfen, Doppelregistrierung erkennen
------------------------------------------------------------------------

local DEF_KEYS = { direction = true, schema = true, perm = true, rateLimit = true, maxBits = true, handler = true, unreliable = true, desc = true }

local function newStats()
	return { received = 0, bytesIn = 0, dropped = 0, violations = 0, errors = 0, sent = 0, bytesOut = 0, throttled = 0, reasons = {} }
end

local function compileMessage(name, def)
	if not isstring(name) or #name > 64 or not string.match(name, "^[%l%d_%.]+$") then
		fail("", "Name muss 1–64 Zeichen aus a–z, 0–9, _ und . haben")
	end
	if not istable(def) then fail("", "Definition fehlt") end
	for k in pairs(def) do
		if not DEF_KEYS[k] then fail("", "unbekannter Schlüssel '" .. tostring(k) .. "'") end
	end
	if not DIRECTIONS[def.direction] then fail("", "direction muss c2s, s2c oder both sein") end
	local incoming = def.direction ~= "s2c" -- der Server empfängt diese Nachricht

	-- Deny-by-default: wer vom Client empfängt, muss das Recht ausdrücklich angeben
	local perm = def.perm
	if incoming then
		if perm == nil then fail("", "perm fehlt: Recht angeben oder perm = false (jeder verbundene Spieler)") end
		if perm ~= false and (not isstring(perm) or perm == "") then fail("", "perm muss ein Rechtename oder false sein") end
	elseif perm ~= nil then
		fail("", "perm gilt nur für c2s/both")
	end

	local rate
	if incoming then
		local r = def.rateLimit or DEFAULT_RATE
		if not istable(r) or not isInt(r.count) or r.count < 1 or r.count > 1000 or not isFinite(r.perSeconds) or r.perSeconds <= 0 or r.perSeconds > 3600 then
			fail("", "rateLimit muss { count = 1–1000, perSeconds = >0–3600 } sein")
		end
		for k in pairs(r) do
			if k ~= "count" and k ~= "perSeconds" then fail("", "rateLimit: unbekannter Schlüssel '" .. tostring(k) .. "'") end
		end
		rate = { count = r.count, perSeconds = r.perSeconds }
	elseif def.rateLimit ~= nil then
		fail("", "rateLimit gilt nur für c2s/both")
	end

	if def.handler ~= nil and not isfunction(def.handler) then fail("", "handler muss eine Funktion sein") end
	if def.unreliable ~= nil and not isbool(def.unreliable) then fail("", "unreliable muss true/false sein") end
	if def.desc ~= nil and not isstring(def.desc) then fail("", "desc muss Text sein") end

	local spec = compileFields(def.schema or {}, 1, "")
	local maxBits = math.min(spec.maxBits, NET_MAX_BITS)
	if def.maxBits ~= nil then
		if not isInt(def.maxBits) or def.maxBits < 1 or def.maxBits > NET_MAX_BITS then
			fail("", "maxBits muss 1–" .. NET_MAX_BITS .. " sein (64-KB-Grenze von net)")
		end
		maxBits = math.min(maxBits, def.maxBits)
	end
	if maxBits < spec.minBits then fail("", "maxBits ist kleiner als das kleinste gültige Paket (" .. spec.minBits .. " Bit)") end

	return {
		name = name, direction = def.direction, spec = spec, perm = perm, rate = rate,
		maxBits = maxBits, minBits = spec.minBits, unreliable = def.unreliable == true, desc = def.desc,
		handler = def.handler, signature = def.direction .. "|" .. signature(spec),
	}
end

local function newLimiterFor(rate)
	if not rate then return nil end
	-- Client: eigenes, etwas strengeres Kontingent, damit ein schneller Klicker keinen Verstoß auslöst
	return N.NewLimiter(rate.count, rate.perSeconds * (CLIENT and CLIENT_RATE_FACTOR or 1))
end

local Registry = {}
Registry.__index = Registry

function N.NewRegistry()
	return setmetatable({ msgs = {} }, Registry)
end

-- Rückgabe: msg, neu (bool) | nil, fehlermeldung
function Registry:TryRegister(name, def)
	local msg, err = catch(compileMessage, name, def)
	if not msg then return nil, "LMNT.Net.Register('" .. tostring(name) .. "'): " .. err end

	local old = self.msgs[name]
	if old then
		if old.signature ~= msg.signature then
			return nil, "LMNT.Net.Register('" .. name .. "'): bereits mit anderem Schema oder anderer Richtung registriert " ..
				"(Protokolländerungen brauchen einen Neustart)"
		end
		-- Reload mit gleichem Schema: Richtlinien übernehmen, Statistik und Limiter-Zustand bleiben
		old.perm, old.maxBits, old.unreliable, old.desc = msg.perm, msg.maxBits, msg.unreliable, msg.desc
		if msg.rate and (old.rate.count ~= msg.rate.count or old.rate.perSeconds ~= msg.rate.perSeconds) then
			old.rate = msg.rate
			old.limiter = newLimiterFor(msg.rate)
		end
		if msg.handler then old.handler = msg.handler end
		return old, false
	end

	msg.limiter = newLimiterFor(msg.rate)
	msg.stats = newStats()
	self.msgs[name] = msg
	return msg, true
end

-- wie TryRegister, wirft aber den Fehler (für Tests und eigene Registries)
function Registry:Register(name, def)
	local msg, isNew = self:TryRegister(name, def)
	if not msg then error(isNew, 2) end
	return msg, isNew
end

function Registry:Get(name)
	return self.msgs[name]
end

------------------------------------------------------------------------
-- Guard: Prüfkette für eingehende Pakete (Server) mit Verstoßbehandlung
------------------------------------------------------------------------

--[[
	env (alles Funktionen, damit Tests eine eigene Umgebung ohne Log/Kick einsetzen können):
	  now()  key(ply)  name(ply)  hasPerm(ply, perm)  threshold()  decay()
	  log(text)  emit(ply, name, grund)  kick(ply, text)
]]
local Guard = {}
Guard.__index = Guard

function N.NewGuard(env)
	return setmetatable({ env = env, counter = N.NewViolationCounter(env.decay), gates = {}, kicked = {} }, Guard)
end

-- Verwerfen + Verstoß zählen. Rückgabe immer nil, grund
function Guard:Report(ply, msg, code, detail)
	local env = self.env
	local now = env.now()
	local key = env.key(ply)
	local st = msg.stats
	st.dropped = st.dropped + 1
	st.violations = st.violations + 1
	st.reasons[code] = (st.reasons[code] or 0) + 1

	local score = self.counter:Add(key, N.Weights[code] or 1, now)
	local threshold = tonumber(env.threshold()) or 0

	-- security-Log gedrosselt: ein Flood darf Datenbank, Logdatei und Team-Chat nicht selbst überlasten
	local gateKey = key .. "|" .. msg.name .. "|" .. code
	local gate = self.gates[gateKey]
	if not gate or now >= gate.next then
		local suppressed = gate and gate.suppressed or 0
		self.gates[gateKey] = { next = now + LOG_INTERVAL, suppressed = 0, who = env.name(ply), msgName = msg.name, code = code }
		env.log(string.format("%s: %s verworfen – %s [%s, %.1f/%s Punkte]%s", env.name(ply), msg.name, detail, code, score,
			threshold > 0 and tostring(threshold) or "aus",
			suppressed > 0 and (" (+" .. suppressed .. " gleiche seit der letzten Meldung)") or ""))
	else
		gate.suppressed = gate.suppressed + 1
	end

	env.emit(ply, msg.name, code)

	if threshold > 0 and score >= threshold and not self.kicked[key] then
		self.kicked[key] = now
		env.log(string.format("%s wird getrennt: %.1f Verstoßpunkte (Schwelle %s, zuletzt %s: %s)", env.name(ply), score, tostring(threshold), msg.name, code))
		env.kick(ply, KICK_TEXT)
	end
	return nil, code
end

-- Prüft ein eingehendes Paket. Rückgabe: data | nil, grund
function Guard:Incoming(msg, ply, len, reader)
	local st = msg.stats
	st.received = st.received + 1
	st.bytesIn = st.bytesIn + math.ceil(len / 8)

	local env = self.env
	local key = env.key(ply)
	if self.kicked[key] then
		-- Kick läuft bereits: Rest verwerfen, ohne weitere Punkte oder Logs
		st.dropped = st.dropped + 1
		return nil, "kicked"
	end

	if msg.direction == "s2c" then
		return self:Report(ply, msg, "direction", "Nachricht darf nur der Server senden")
	end
	if len > msg.maxBits or len < msg.minBits then
		return self:Report(ply, msg, "size", string.format("Größe %d Bit, erlaubt %d–%d", len, msg.minBits, msg.maxBits))
	end
	if not msg.limiter:Allow(key, env.now()) then
		return self:Report(ply, msg, "rate", string.format("mehr als %d in %s s", msg.rate.count, tostring(msg.rate.perSeconds)))
	end
	-- Deny-by-default: nur perm == false ist offen, alles andere braucht ein vorhandenes Recht
	if msg.perm ~= false and not (isstring(msg.perm) and env.hasPerm(ply, msg.perm)) then
		return self:Report(ply, msg, "perm", "fehlendes Recht '" .. tostring(msg.perm) .. "'")
	end
	local data, why, path = N.Decode(msg.spec, reader, len, "server")
	if data == nil then
		return self:Report(ply, msg, "schema", where(path) .. why)
	end
	return data
end

-- Spieler hat den Server verlassen
function Guard:Forget(key)
	self.kicked[key] = nil
end

function Guard:Prune(now)
	self.counter:Prune(now)
	for k, g in pairs(self.gates) do
		if now >= g.next then
			-- unterdrückte Meldungen nicht verlieren, wenn danach nichts mehr kommt
			if g.suppressed > 0 then
				self.env.log(string.format("%s: %s – %d weitere Verstöße (%s) seit der letzten Meldung", g.who, g.msgName, g.suppressed, g.code))
			end
			self.gates[k] = nil
		end
	end
	for k, t in pairs(self.kicked) do
		if now - t > 120 then self.kicked[k] = nil end
	end
end

------------------------------------------------------------------------
-- Globaler Dienst (Zustand übersteht einen Lua-Reload)
------------------------------------------------------------------------

local registry = setmetatable(N._registry or { msgs = {} }, Registry)
N._registry = registry
for _, msg in pairs(registry.msgs) do
	if msg.limiter then setmetatable(msg.limiter, Limiter) end
end

local function playerKey(ply)
	return ply:SteamID64() or ("uid" .. ply:UserID())
end

local guard
if SERVER then
	LMNT.Settings.Define("lmnt.net.kick_threshold", {
		type = "int", default = 60, min = 0, max = 100000, category = "Netzwerk", applies = "live",
		desc = "Verstoßpunkte, ab denen ein Spieler wegen ungültiger Netzwerkpakete getrennt wird (0 = nie)",
	})
	LMNT.Settings.Define("lmnt.net.decay_per_minute", {
		type = "number", default = 6, min = 0, max = 600, category = "Netzwerk", applies = "live",
		desc = "Wie viele Verstoßpunkte pro Minute verfallen",
	})
	LMNT.Events.Define("lmnt.net.violation", { desc = "Ungültiges Netzwerkpaket verworfen (Server)", args = { "ply", "name", "grund" } })

	local serverEnv = {
		now = SysTime,
		key = playerKey,
		name = function(ply) return LMNT.Name(ply) .. " (" .. tostring(ply:SteamID64()) .. ")" end,
		hasPerm = function(ply, perm) return LMNT.HasPerm(ply, perm) end,
		threshold = function() return LMNT.Settings.Get("lmnt.net.kick_threshold") end,
		decay = function() return LMNT.Settings.Get("lmnt.net.decay_per_minute") end,
		log = function(text) LMNT.Log.Security("net", text) end,
		emit = function(ply, name, code) LMNT.Events.Emit("lmnt.net.violation", ply, name, code) end,
		kick = function(ply, text)
			if not IsValid(ply) or ply:IsListenServerHost() then return end
			-- game.KickID wirkt auch bei Spielern, die noch nicht vollständig beigetreten sind (Wiki)
			game.KickID(tostring(ply:UserID()), text)
		end,
	}

	guard = N._guard and setmetatable(N._guard, Guard) or N.NewGuard(serverEnv)
	guard.env = serverEnv
	setmetatable(guard.counter, Counter)
	guard.counter.decay = serverEnv.decay
	N._guard = guard
end

local function traceback(err)
	return debug.traceback(tostring(err), 2)
end

local function runHandler(msg, ply, data)
	local fn = msg.handler
	if not fn then
		msg.stats.dropped = msg.stats.dropped + 1
		if not msg.warnedNoHandler then
			msg.warnedNoHandler = true
			logLine("warn", msg.name .. ": gültiges Paket, aber kein Handler gesetzt – verworfen")
		end
		return
	end
	local ok, err = xpcall(fn, traceback, ply, data)
	if not ok then
		msg.stats.errors = msg.stats.errors + 1
		logLine("error", "Handler für " .. msg.name .. " fehlgeschlagen: " .. tostring(err))
	end
end

local function serverReceive(name, len, ply)
	local msg = registry.msgs[name]
	if not msg or not IsValid(ply) or not ply:IsPlayer() then return end
	local data = guard:Incoming(msg, ply, len, NetIO)
	if data == nil then return end
	runHandler(msg, ply, data)
end

local function clientReceive(name, len)
	local msg = registry.msgs[name]
	if not msg then return end
	local st = msg.stats
	st.received = st.received + 1
	st.bytesIn = st.bytesIn + math.ceil(len / 8)

	if len > msg.maxBits or len < msg.minBits then
		st.dropped = st.dropped + 1
		logLine("warn", name .. ": Paket vom Server mit unerwarteter Größe verworfen (" .. len .. " Bit)")
		return
	end
	local data, why, path = N.Decode(msg.spec, NetIO, len, "client")
	if data == nil then
		st.dropped = st.dropped + 1
		logLine("warn", name .. ": ungültiges Paket vom Server verworfen – " .. where(path) .. why)
		return
	end
	runHandler(msg, nil, data)
end

-- Netzwerkstring anlegen und Empfänger binden. Der Server bindet auch s2c-Nachrichten, damit ein
-- Client, der sie trotzdem schickt, als Verstoß "direction" auffällt.
local function bind(msg)
	local name = msg.name
	if SERVER then
		util.AddNetworkString(name)
		net.Receive(name, function(len, ply) serverReceive(name, len, ply) end)
	elseif msg.direction ~= "c2s" then
		net.Receive(name, function(len) clientReceive(name, len) end)
	end
end

-- Nach einem Reload zeigen die Empfänger auf den neuen Code
for _, msg in pairs(registry.msgs) do bind(msg) end

-- Wird ein Handler beim Laden eines Moduls gesetzt, verschwindet er beim Deaktivieren wieder
-- (Pakete werden danach als "kein Handler" verworfen, ohne Verstoß)
local function trackHandler(msg, fn)
	if LMNT.Modules and LMNT.Modules.TrackUndo then
		LMNT.Modules.TrackUndo(function()
			if msg.handler == fn then msg.handler = nil end
		end)
	end
end

------------------------------------------------------------------------
-- Öffentliche API
------------------------------------------------------------------------

function N.Register(name, def)
	local msg, isNew = registry:TryRegister(name, def)
	if not msg then error(isNew, 2) end
	bind(msg)
	if def.handler then
		msg.warnedNoHandler = nil
		trackHandler(msg, def.handler)
	end
end

function N.Receive(name, fn)
	local msg = registry.msgs[name]
	if not msg then error("LMNT.Net.Receive: '" .. tostring(name) .. "' ist nicht registriert (zuerst LMNT.Net.Register, geteilt)", 2) end
	if not isfunction(fn) then error("LMNT.Net.Receive: fn muss eine Funktion sein", 2) end
	if SERVER and msg.direction == "s2c" then error("LMNT.Net.Receive: '" .. name .. "' ist s2c, der Server empfängt sie nicht", 2) end
	if CLIENT and msg.direction == "c2s" then error("LMNT.Net.Receive: '" .. name .. "' ist c2s, der Client empfängt sie nicht", 2) end
	msg.handler = fn
	msg.warnedNoHandler = nil
	trackHandler(msg, fn)
end

-- Gemeinsame Prüfung vor dem Senden (Ebene 3 = Aufrufer von Send/SendToServer)
local function prepare(name, data, dir)
	local msg = registry.msgs[name]
	if not msg then error("LMNT.Net: '" .. tostring(name) .. "' ist nicht registriert", 3) end
	if msg.direction ~= "both" and msg.direction ~= dir then
		error("LMNT.Net: '" .. name .. "' hat die Richtung " .. msg.direction .. " und kann so nicht gesendet werden", 3)
	end
	local ok, bits, path = N.Validate(msg.spec, data)
	if not ok then error("LMNT.Net: '" .. name .. "': " .. where(path) .. bits, 3) end
	if bits > msg.maxBits then error("LMNT.Net: '" .. name .. "': Nachricht zu groß (" .. bits .. " Bit, erlaubt " .. msg.maxBits .. ")", 3) end
	return msg, bits
end

if SERVER then
	-- Rückgabe: true = gesendet, false = kein (gültiger) Empfänger mehr da
	function N.Send(name, data, target)
		local msg, bits = prepare(name, data, "s2c")

		-- Ziel vollständig prüfen, bevor net.Start eine Nachricht beginnt
		local recipients
		if target == nil then
			recipients = player.GetCount()
		elseif istable(target) then
			local list = {}
			for _, p in ipairs(target) do
				if IsValid(p) and p:IsPlayer() then list[#list + 1] = p end
			end
			target, recipients = list, #list
		elseif isentity(target) then
			if not IsValid(target) then return false end -- Spieler ist inzwischen weg
			if not target:IsPlayer() then error("LMNT.Net.Send: Ziel ist kein Spieler", 2) end
			recipients = 1
		elseif type(target) == "CRecipientFilter" then
			recipients = target:GetCount()
		else
			error("LMNT.Net.Send: Ziel muss ein Spieler, eine Spielerliste, ein RecipientFilter oder nil (alle) sein", 2)
		end
		if recipients == 0 then return false end

		net.Start(name, msg.unreliable)
		writeField(msg.spec, data == nil and {} or data, NetIO)
		if target == nil then net.Broadcast() else net.Send(target) end

		local st = msg.stats
		st.sent = st.sent + 1
		st.bytesOut = st.bytesOut + math.ceil(bits / 8) * recipients
		return true
	end

	function N.SendToServer()
		error("LMNT.Net.SendToServer gibt es nur auf dem Client", 2)
	end

	function N.GetViolationScore(ply)
		if not IsValid(ply) then return 0 end
		return guard.counter:Get(playerKey(ply), SysTime())
	end

	-- Aufräumen: verfallene Punkte, volle Kontingente, alte Log-Drosseln
	timer.Create("LMNT.Net.Prune", 60, 0, function()
		local now = SysTime()
		guard:Prune(now)
		for _, msg in pairs(registry.msgs) do
			if msg.limiter then msg.limiter:Prune(now) end
		end
	end)

	hook.Add("PlayerDisconnected", "LMNT.Net.Forget", function(ply)
		local key = playerKey(ply)
		guard:Forget(key) -- Punkte bleiben (mit Verfall) auch über einen Reconnect erhalten
		for _, msg in pairs(registry.msgs) do
			if msg.limiter then msg.limiter:Reset(key) end
		end
	end)
else
	local nextThrottleWarn = {}

	-- Rückgabe: true = gesendet, false = clientseitig zurückgehalten (Rate-Limit oder Recht)
	function N.SendToServer(name, data)
		local msg, bits = prepare(name, data, "c2s")
		if util.NetworkStringToID(name) == 0 then
			error("LMNT.Net.SendToServer: '" .. name .. "' ist auf dem Server nicht registriert (Register muss geteilt laufen)", 2)
		end

		-- Vorprüfungen nur aus Komfort, damit normale Clients keine Verstöße sammeln. Entscheidend ist der Server.
		if isstring(msg.perm) and not LMNT.HasPerm(LocalPlayer(), msg.perm) then return false end
		if not msg.limiter:Allow("self", SysTime()) then
			msg.stats.throttled = msg.stats.throttled + 1
			if (nextThrottleWarn[name] or 0) < SysTime() then
				nextThrottleWarn[name] = SysTime() + 5
				logLine("warn", name .. ": clientseitiges Rate-Limit erreicht, Nachricht nicht gesendet")
			end
			return false
		end

		net.Start(name, msg.unreliable)
		writeField(msg.spec, data == nil and {} or data, NetIO)
		net.SendToServer()

		local st = msg.stats
		st.sent = st.sent + 1
		st.bytesOut = st.bytesOut + math.ceil(bits / 8)
		return true
	end

	function N.Send()
		error("LMNT.Net.Send gibt es nur auf dem Server", 2)
	end
end

function N.Stats()
	local out = {}
	for name, msg in pairs(registry.msgs) do
		local s = msg.stats
		local reasons = {}
		for k, v in pairs(s.reasons) do reasons[k] = v end
		out[name] = {
			direction = msg.direction, received = s.received, bytesIn = s.bytesIn, dropped = s.dropped,
			violations = s.violations, errors = s.errors, sent = s.sent, bytesOut = s.bytesOut,
			throttled = s.throttled, reasons = reasons,
		}
	end
	return out
end

-- Kopie der Definition (ohne Handler und Zustand), z. B. für Diagnose und Admin-Menü
function N.Get(name)
	local msg = registry.msgs[name]
	if not msg then return nil end
	return {
		name = msg.name, direction = msg.direction, perm = msg.perm, desc = msg.desc,
		rateLimit = msg.rate and { count = msg.rate.count, perSeconds = msg.rate.perSeconds } or nil,
		maxBits = msg.maxBits, minBits = msg.minBits, unreliable = msg.unreliable, hasHandler = msg.handler ~= nil,
	}
end

function N.List()
	local names = table.GetKeys(registry.msgs)
	table.sort(names)
	return names
end

------------------------------------------------------------------------
-- Selbsttest für T-092 (Abnahme ohne Unit-Test-Grenzen): echte Pakete an den Server
--   lmnt_net_selftest ok | flood | oversize | badvalue | short   (Client-Konsole, Recht "dev")
-- Die fehlerhaften Varianten schreiben bewusst an LMNT.Net vorbei, so wie es ein veränderter Client täte.
------------------------------------------------------------------------

N.Register("lmnt_net_selftest", {
	direction = "c2s",
	desc = "Selbsttest der Prüfkette (nur Recht dev)",
	perm = "dev",
	rateLimit = { count = 5, perSeconds = 1 },
	schema = { { name = "n", type = "uint", bits = 8, max = 100 } },
})

if SERVER then
	N.Receive("lmnt_net_selftest", function(ply, data)
		LMNT.Reply(ply, LMNT.Config.Colors.good, "LMNT.Net-Selbsttest: gültiges Paket angekommen (n = " .. data.n .. ")")
	end)
else
	local function raw(fill)
		net.Start("lmnt_net_selftest")
		fill()
		net.SendToServer()
	end

	concommand.Add("lmnt_net_selftest", function(_, _, args)
		if not LMNT.HasPerm(LocalPlayer(), "dev") then
			MsgC(Color(255, 110, 110), "[LMNT][net] Selbsttest nur mit Recht dev\n")
			return
		end
		local mode = args[1] or "ok"
		if mode == "ok" then
			N.SendToServer("lmnt_net_selftest", { n = 42 })
		elseif mode == "flood" then
			for _ = 1, 20 do raw(function() net.WriteUInt(1, 8) end) end   -- 15 über dem Limit
		elseif mode == "oversize" then
			raw(function() net.WriteString(string.rep("x", 1000)) end)    -- 8008 Bit statt 8
		elseif mode == "badvalue" then
			raw(function() net.WriteUInt(250, 8) end)                     -- max ist 100
		elseif mode == "short" then
			raw(function() end)                                           -- 0 Bit statt 8
		else
			MsgC(color_white, "Benutzung: lmnt_net_selftest ok|flood|oversize|badvalue|short\n")
			return
		end
		MsgC(color_white, "[LMNT][net] Selbsttest '" .. mode .. "' gesendet – Ergebnis: !netstats und security-Log\n")
	end)
end

------------------------------------------------------------------------
-- Admin-Befehl !netstats (geteilt registriert, ausgeführt auf dem Server)
------------------------------------------------------------------------

local function formatBytes(n)
	if n < 1024 then return n .. " B" end
	if n < 1024 * 1024 then return string.format("%.1f KB", n / 1024) end
	return string.format("%.1f MB", n / 1024 / 1024)
end

if LMNT.Admin and LMNT.Admin.AddCommand then
	LMNT.Admin.AddCommand("netstats", {
		perm = "dev", log = false,
		help = "Netzwerk-Statistik je LMNT.Net-Nachricht: Pakete, Bytes, verworfene Pakete, Verstöße",
		run = function(caller)
			local col = LMNT.Config.Colors
			local list = {}
			for name, s in pairs(N.Stats()) do
				s.name = name
				list[#list + 1] = s
			end
			if #list == 0 then
				LMNT.Reply(caller, col.muted, "Keine Nachricht über LMNT.Net registriert.")
				return
			end
			table.sort(list, function(a, b)
				if a.violations ~= b.violations then return a.violations > b.violations end
				return a.bytesIn + a.bytesOut > b.bytesIn + b.bytesOut
			end)

			for i = 1, math.min(#list, 25) do
				local s = list[i]
				local reasons = {}
				for code, n in SortedPairs(s.reasons) do reasons[#reasons + 1] = code .. " " .. n end
				LMNT.Reply(caller, s.violations > 0 and col.warn or color_white, s.name, col.muted, string.format(
					"  %s · ein %d (%s) · aus %d (%s) · verworfen %d · Verstöße %d%s · Handler-Fehler %d",
					s.direction, s.received, formatBytes(s.bytesIn), s.sent, formatBytes(s.bytesOut), s.dropped, s.violations,
					#reasons > 0 and (" (" .. table.concat(reasons, ", ") .. ")") or "", s.errors))
			end
			if #list > 25 then LMNT.Reply(caller, col.muted, "… " .. (#list - 25) .. " weitere Nachrichten") end

			local scores = {}
			for _, p in ipairs(player.GetAll()) do
				local score = N.GetViolationScore(p)
				if score > 0 then scores[#scores + 1] = LMNT.Name(p) .. " " .. string.format("%.1f", score) end
			end
			local threshold = LMNT.Settings.Get("lmnt.net.kick_threshold")
			LMNT.Reply(caller, col.primary, "Verstoßpunkte (Schwelle " .. (threshold > 0 and threshold or "aus") .. "): ",
				color_white, #scores > 0 and table.concat(scores, ", ") or "keine")
		end,
	})
end
