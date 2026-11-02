--[[
	LMNT Admin – Server: Ränge speichern, Befehle ausführen, Chat-/Konsolen-Eingabe

	Befehle ausführen:
	  Chat:      !kick Max Grund   /kick Max Grund (unsichtbar)
	  Konsole:   lmnt kick Max Grund   (Serverkonsole hat alle Rechte)
	  Admin-Chat: @Nachricht  (Spieler -> Meldung an das Team, Team -> Team-Chat)
]]

util.AddNetworkString("lmnt_admin_open")
util.AddNetworkString("lmnt_admin_run")

LMNT.DB.Query([[CREATE TABLE IF NOT EXISTS lmnt_users (
	steamid TEXT PRIMARY KEY,
	name TEXT,
	rank TEXT NOT NULL DEFAULT 'user',
	first_seen INTEGER,
	last_seen INTEGER
)]])

------------------------------------------------------------------------
-- Ränge
------------------------------------------------------------------------

-- skipApply = true: nur speichern, nicht sofort auf einen Online-Spieler anwenden
-- (z. B. innerhalb einer Transaktion; der Aufrufer wendet nach dem Commit selbst an)
function LMNT.Admin.SetRank(steamid64, rankId, name, skipApply)
	rankId = LMNT.Ranks[rankId] and rankId or "user"

	local exists = LMNT.DB.Row("SELECT steamid FROM lmnt_users WHERE steamid = ?", steamid64)
	if exists then
		LMNT.DB.Query("UPDATE lmnt_users SET rank = ? WHERE steamid = ?", rankId, steamid64)
	else
		LMNT.DB.Query("INSERT INTO lmnt_users (steamid, name, rank, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)", steamid64, name or "?", rankId, os.time(), os.time())
	end

	if skipApply then return end
	local ply = player.GetBySteamID64(steamid64)
	if IsValid(ply) then ply:SetUserGroup(rankId) end
end

-- Owner aus C.Owners und data/lmnt/owners.txt (eine SteamID64 pro Zeile, von deploy.ps1 aus settings.ini OWNERS geschrieben)
local function isOwner(sid)
	if table.HasValue(LMNT.Config.Owners or {}, sid) then return true end
	local raw = file.Read("lmnt/owners.txt", "DATA")
	if not raw then return false end
	for line in string.gmatch(raw, "[^\r\n]+") do
		if string.Trim(line) == sid then return true end
	end
	return false
end

hook.Add("PlayerInitialSpawn", "LMNT.Admin.LoadRank", function(ply)
	local sid = ply:SteamID64()
	local row = LMNT.DB.Row("SELECT rank FROM lmnt_users WHERE steamid = ?", sid)
	local rankId = row and row.rank or "user"

	if isOwner(sid) then rankId = "owner" end

	if row then
		LMNT.DB.Query("UPDATE lmnt_users SET name = ?, last_seen = ?, rank = ? WHERE steamid = ?", ply:Nick(), os.time(), rankId, sid)
	else
		LMNT.DB.Query("INSERT INTO lmnt_users (steamid, name, rank, first_seen, last_seen) VALUES (?, ?, ?, ?, ?)", sid, ply:Nick(), rankId, os.time(), os.time())
	end

	ply:SetUserGroup(rankId)
end)

------------------------------------------------------------------------
-- Argument-Parser
------------------------------------------------------------------------

local parsers = {}

parsers.player = function(caller, tok, spec)
	local list = LMNT.FindPlayers(caller, tok)
	if #list == 0 then return nil, "Kein Spieler gefunden: " .. tok end
	if #list > 1 then return nil, "Mehrere Spieler passen auf '" .. tok .. "' – bitte genauer angeben." end
	if not spec.ignoreImmunity and not LMNT.CanTarget(caller, list[1]) then
		return nil, list[1]:Nick() .. " hat einen gleich hohen oder höheren Rang."
	end
	return list[1]
end

parsers.players = function(caller, tok, spec)
	local list = LMNT.FindPlayers(caller, tok)
	local allowed = {}

	for _, ply in ipairs(list) do
		if spec.ignoreImmunity or LMNT.CanTarget(caller, ply) then allowed[#allowed + 1] = ply end
	end

	if #list == 0 then return nil, "Kein Spieler gefunden: " .. tok end
	if #allowed == 0 then return nil, "Keiner der Spieler kann von dir anvisiert werden." end
	return allowed
end

parsers.steamid = function(_, tok)
	local sid = LMNT.ToSteamID64(tok)
	if not sid then return nil, "Ungültige SteamID: " .. tok end
	return sid
end

parsers.number = function(_, tok, spec)
	local n = tonumber(tok)
	if not n then return nil, "'" .. tok .. "' ist keine Zahl." end
	if spec.min then n = math.max(n, spec.min) end
	if spec.max then n = math.min(n, spec.max) end
	return n
end

parsers.string = function(_, tok) return tok end

parsers.time = function(_, tok)
	local minutes = LMNT.ParseTime(tok)
	if not minutes then return nil, "Ungültige Zeit '" .. tok .. "' (z. B. 30m, 2h, 1d, 1w, 0 = permanent)." end
	return minutes
end

parsers.rank = function(_, tok)
	local id = string.lower(tok)
	if not LMNT.Ranks[id] then return nil, "Unbekannter Rang: " .. tok end
	return id
end

parsers.map = function(_, tok)
	if not file.Exists("maps/" .. tok .. ".bsp", "GAME") then return nil, "Map nicht gefunden: " .. tok end
	return tok
end

------------------------------------------------------------------------
-- Ausführen
------------------------------------------------------------------------

function LMNT.Admin.Run(caller, name, tokens)
	local cmd = LMNT.Admin.GetCommand(name)
	if not cmd then return false end

	local col = LMNT.Config.Colors

	if not LMNT.HasPerm(caller, cmd.perm) then
		LMNT.Reply(caller, col.bad, "Dafür hast du keine Rechte.")
		return true
	end

	if cmd.playerOnly and not IsValid(caller) then
		LMNT.Reply(caller, col.bad, "Dieser Befehl geht nur ingame.")
		return true
	end

	local values = {}

	for i, spec in ipairs(cmd.args) do
		local tok = tokens[i]
		if spec.rest and tok then tok = table.concat(tokens, " ", i) end
		if tok == "" then tok = nil end

		if tok == nil then
			if not spec.optional then
				LMNT.Reply(caller, col.warn, "Benutzung: ", color_white, LMNT.Admin.Usage(cmd))
				return true
			end

			local default = spec.default
			if isfunction(default) then default = default(caller) end
			values[i] = default
		else
			local value, err = parsers[spec.type](caller, tok, spec)
			if value == nil then
				LMNT.Reply(caller, col.bad, err or "Ungültige Eingabe.")
				return true
			end
			values[i] = value
		end
	end

	local ok, err = pcall(cmd.run, caller, unpack(values, 1, #cmd.args))
	if not ok then
		ErrorNoHalt("[LMNT] Fehler in Befehl " .. cmd.name .. ": " .. tostring(err) .. "\n")
		LMNT.Reply(caller, col.bad, "Beim Ausführen ist ein Fehler aufgetreten (siehe Serverkonsole).")
		return true
	end

	if cmd.perm and cmd.log ~= false then
		LMNT.Log("admin", LMNT.Name(caller) .. ": !" .. cmd.name .. " " .. table.concat(tokens, " "))
	end

	return true
end

-- Schreibt "Admin hat Spieler1, Spieler2 gekickt (Grund)" an alle
function LMNT.Admin.Broadcast(caller, verb, targets, suffix)
	local col = LMNT.Config.Colors
	local msg = { IsValid(caller) and caller or "Konsole", color_white, " " .. verb .. " " }

	if istable(targets) then
		for i, ply in ipairs(targets) do
			msg[#msg + 1] = ply
			if i < #targets then msg[#msg + 1] = ", " end
		end
	elseif targets then
		msg[#msg + 1] = targets
	end

	if suffix then
		msg[#msg + 1] = col.muted
		msg[#msg + 1] = suffix
	end

	LMNT.Notify(nil, unpack(msg))
end

------------------------------------------------------------------------
-- Eingabewege
------------------------------------------------------------------------

local function isPrefix(c)
	for _, p in ipairs(LMNT.Config.ChatPrefixes) do
		if c == p then return true end
	end
	return false
end

hook.Add("PlayerSay", "LMNT.Admin.Chat", function(ply, text)
	local col = LMNT.Config.Colors

	-- Admin-Chat / Meldungen ans Team
	if string.sub(text, 1, 1) == "@" and #text > 1 then
		local msg = string.Trim(string.sub(text, 2))
		local staff = {}

		for _, p in ipairs(player.GetAll()) do
			if LMNT.HasPerm(p, "asay") then staff[#staff + 1] = p end
		end

		if LMNT.HasPerm(ply, "asay") then
			LMNT.Notify(staff, col.accent, "[TEAM] ", ply, color_white, ": " .. msg)
		else
			LMNT.Notify(staff, col.warn, "[MELDUNG] ", ply, color_white, ": " .. msg)
			LMNT.Notify(ply, col.good, "Deine Meldung wurde an " .. #staff .. " Teammitglied(er) gesendet.")
		end

		LMNT.Log("asay", ply:Nick() .. ": " .. msg)
		return ""
	end

	if ply.LMNTMuted then
		LMNT.Notify(ply, col.bad, "Du bist stummgeschaltet.")
		return ""
	end

	local first = string.sub(text, 1, 1)
	if not isPrefix(first) then return end

	local tokens = LMNT.Admin.Tokenize(string.sub(text, 2))
	local name = table.remove(tokens, 1)
	if not name or not LMNT.Admin.GetCommand(name) then return end

	LMNT.Admin.Run(ply, name, tokens)
	return ""
end)

concommand.Add("lmnt", function(ply, _, _, argStr)
	local tokens = LMNT.Admin.Tokenize(argStr or "")
	local name = table.remove(tokens, 1)

	if not name then
		LMNT.Reply(ply, "Benutzung: lmnt <befehl> [argumente]  –  'lmnt hilfe' zeigt alle Befehle")
		return
	end

	if not LMNT.Admin.Run(ply, name, tokens) then
		LMNT.Reply(ply, LMNT.Config.Colors.bad, "Unbekannter Befehl: " .. name)
	end
end)

-- Vom Admin-Menü (mit kleinem Spam-Schutz)
net.Receive("lmnt_admin_run", function(len, ply)
	if len > 32768 then return end -- Befehl + 8 Argumente à 200 Zeichen passen mit Reserve hinein
	if (ply.LMNTNextMenuRun or 0) > CurTime() then return end
	ply.LMNTNextMenuRun = CurTime() + 0.3

	local name = net.ReadString()
	local tokens = {}
	for i = 1, math.min(net.ReadUInt(4), 8) do
		tokens[i] = string.sub(net.ReadString(), 1, 200)
	end

	LMNT.Admin.Run(ply, name, tokens)
end)

------------------------------------------------------------------------
-- Zustände (mute, gag, god, freeze) und ihre Wirkung
------------------------------------------------------------------------

hook.Add("PlayerCanHearPlayersVoice", "LMNT.Admin.Gag", function(_, talker)
	if talker.LMNTGagged then return false, false end
end)

hook.Add("EntityTakeDamage", "LMNT.Admin.God", function(ent)
	if ent:IsPlayer() and ent.LMNTGod then return true end
end)

hook.Add("PlayerSpawn", "LMNT.Admin.ResetFreeze", function(ply)
	if ply.LMNTFrozen then ply:Freeze(true) end
end)
