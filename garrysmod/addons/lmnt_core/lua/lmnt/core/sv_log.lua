--[[
	LMNT Framework – Strukturierte Protokollierung (Server)
	API-Referenz: docs/framework/api/log.md

	LMNT.Log.Debug(kategorie, text)      nur mit lmnt_log_debug 1
	LMNT.Log.Info(kategorie, text)
	LMNT.Log.Warn(kategorie, text)
	LMNT.Log.Error(kategorie, text)
	LMNT.Log.Security(kategorie, text)   zusätzlich Meldung an Online-Team (Recht "asay")
	LMNT.Log("kategorie", "text")        VERALTET (seit 1.1.0) = LMNT.Log.Info, bleibt kompatibel
	LMNT.GetLogs(limit, kategorie, suche, stufe)
	LMNT.Log.Export(kategorie, suche)    -> Pfad unter data/lmnt/exports/ (CSV)

	Speicherorte: Tabelle lmnt_logs (begrenzte Zeilenzahl + Aufbewahrungsdauer)
	              data/lmnt/logs/JJJJ-MM-TT.txt (begrenzte Größe pro Tag)
	Hinweis: Die Logs sind manipulationserschwerend (nur serverseitig beschreibbar, Admin-Aktionen
	         doppelt protokolliert), aber NICHT unveränderbar – wer Dateizugriff auf den Server hat,
	         kann sie ändern.
]]

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4, security = 5 }
local LEVEL_COLORS = {
	debug = Color(165, 161, 172), info = Color(242, 239, 232), warn = Color(255, 176, 32),
	error = Color(255, 110, 110), security = Color(255, 49, 49),
}

local MAX_ROWS = 200000              -- ältere Einträge werden beim Start entfernt
local MAX_FILE_BYTES = 20 * 1024 * 1024 -- pro Tagesdatei
local cvDebug = CreateConVar("lmnt_log_debug", "0", FCVAR_ARCHIVE, "LMNT: Debug-Logs ausgeben (0/1)")

LMNT.DB.Query([[CREATE TABLE IF NOT EXISTS lmnt_logs (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	time INTEGER NOT NULL,
	category TEXT NOT NULL,
	message TEXT NOT NULL
)]])
-- Migration 1.1.0: Schweregrad
LMNT.DB.EnsureColumn("lmnt_logs", "level", "TEXT NOT NULL DEFAULT 'info'")
LMNT.DB.Query("CREATE INDEX IF NOT EXISTS lmnt_logs_time ON lmnt_logs (time)")
LMNT.DB.Query("CREATE INDEX IF NOT EXISTS lmnt_logs_category ON lmnt_logs (category)")

-- Aufräumen beim Start: Aufbewahrungsdauer und Höchstzahl
LMNT.DB.Query("DELETE FROM lmnt_logs WHERE time < ?", os.time() - LMNT.Settings.Get("core.log.retention_days") * 86400)
LMNT.DB.Query("DELETE FROM lmnt_logs WHERE id <= (SELECT MAX(id) FROM lmnt_logs) - ?", MAX_ROWS)

file.CreateDir("lmnt/logs")
file.CreateDir("lmnt/exports")

local fileFullWarned = {}
local emitting = false

local function write(level, category, message)
	if level == "debug" and not cvDebug:GetBool() then return end

	category = tostring(category or "general")
	message = tostring(message or "")
	local now = os.time()

	LMNT.DB.Query("INSERT INTO lmnt_logs (time, level, category, message) VALUES (?, ?, ?, ?)", now, level, category, message)

	local day = os.date("%Y-%m-%d", now)
	local path = "lmnt/logs/" .. day .. ".txt"
	if file.Size(path, "DATA") < MAX_FILE_BYTES then
		file.Append(path, os.date("[%H:%M:%S] ", now) .. "[" .. string.upper(level) .. "] [" .. category .. "] " .. message .. "\n")
	elseif not fileFullWarned[day] then
		fileFullWarned[day] = true
		ErrorNoHalt("[LMNT] Log-Datei " .. path .. " hat das Tageslimit erreicht – weitere Einträge nur noch in der Datenbank.\n")
	end

	ServerLog("[LMNT][" .. level .. "][" .. category .. "] " .. message .. "\n")

	if LEVELS[level] >= LEVELS.warn then
		MsgC(LEVEL_COLORS[level], "[LMNT][" .. string.upper(level) .. "] ", color_white, "[" .. category .. "] " .. message .. "\n")
	end

	if level == "security" and LMNT.Notify and LMNT.HasPerm then
		local staff = {}
		for _, p in ipairs(player.GetAll()) do
			if LMNT.HasPerm(p, "asay") then staff[#staff + 1] = p end
		end
		if #staff > 0 then
			LMNT.Notify(staff, LEVEL_COLORS.security, "[SICHERHEIT] ", color_white, "[" .. category .. "] " .. message)
		end
	end

	-- Wiedereintrittssperre: ein fehlerhafter Listener darf keine Log-Endlosschleife auslösen
	if LMNT.Events and not emitting then
		emitting = true
		LMNT.Events.Emit("lmnt.log.written", level, category, message)
		emitting = false
	end
end

-- LMNT.Log bleibt als Funktion aufrufbar (Abwärtskompatibilität), ist aber eine Tabelle
LMNT.Log = setmetatable({}, {
	__call = function(_, category, message)
		write("info", category, message)
	end,
})

function LMNT.Log.Write(level, category, message)
	if not LEVELS[level] then level = "info" end
	write(level, category, message)
end

function LMNT.Log.Debug(category, message) write("debug", category, message) end
function LMNT.Log.Info(category, message) write("info", category, message) end
function LMNT.Log.Warn(category, message) write("warn", category, message) end
function LMNT.Log.Error(category, message) write("error", category, message) end
function LMNT.Log.Security(category, message) write("security", category, message) end
LMNT.Log.Levels = LEVELS

function LMNT.GetLogs(limit, category, search, level)
	limit = math.Clamp(tonumber(limit) or 100, 1, 1000)

	local where, args = {}, {}
	if category and category ~= "" then where[#where + 1] = "category = ?" args[#args + 1] = category end
	if search and search ~= "" then where[#where + 1] = "message LIKE ?" args[#args + 1] = "%" .. search .. "%" end
	if level and LEVELS[level] then where[#where + 1] = "level = ?" args[#args + 1] = level end
	args[#args + 1] = limit

	local q = "SELECT * FROM lmnt_logs" .. (#where > 0 and (" WHERE " .. table.concat(where, " AND ")) or "") .. " ORDER BY id DESC LIMIT ?"
	return LMNT.DB.Query(q, unpack(args)) or {}
end

-- CSV-Export (für berechtigte Admins, max. 10.000 Zeilen)
function LMNT.Log.Export(category, search)
	local rows = LMNT.GetLogs(1000, category, search)
	if #rows == 1000 then
		local where, args = {}, {}
		if category and category ~= "" then where[#where + 1] = "category = ?" args[#args + 1] = category end
		if search and search ~= "" then where[#where + 1] = "message LIKE ?" args[#args + 1] = "%" .. search .. "%" end
		args[#args + 1] = 10000
		rows = LMNT.DB.Query("SELECT * FROM lmnt_logs" .. (#where > 0 and (" WHERE " .. table.concat(where, " AND ")) or "") .. " ORDER BY id DESC LIMIT ?", unpack(args)) or {}
	end

	local function csv(v)
		v = tostring(v or "")
		return '"' .. string.gsub(v, '"', '""') .. '"'
	end

	local out = { "id;zeit;stufe;kategorie;nachricht" }
	for i = #rows, 1, -1 do
		local r = rows[i]
		out[#out + 1] = table.concat({ r.id, csv(os.date("%Y-%m-%d %H:%M:%S", tonumber(r.time))), csv(r.level), csv(r.category), csv(r.message) }, ";")
	end

	local path = "lmnt/exports/logs_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
	file.Write(path, table.concat(out, "\n"))
	return "data/" .. path, #rows
end

------------------------------------------------------------------------
-- Standard-Ereignisse
------------------------------------------------------------------------

hook.Add("PlayerInitialSpawn", "LMNT.Log.Join", function(ply)
	LMNT.Log.Info("connect", ply:Nick() .. " (" .. ply:SteamID64() .. ") ist beigetreten")
end)

hook.Add("PlayerDisconnected", "LMNT.Log.Leave", function(ply)
	LMNT.Log.Info("connect", ply:Nick() .. " (" .. ply:SteamID64() .. ") hat den Server verlassen")
end)

hook.Add("PlayerSay", "LMNT.Log.Chat", function(ply, text, teamChat)
	LMNT.Log.Info("chat", (teamChat and "[TEAM] " or "") .. ply:Nick() .. ": " .. text)
end)
