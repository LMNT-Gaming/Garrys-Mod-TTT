--[[
	LMNT Admin – Banns und Verwarnungen

	LMNT.Bans.Add(steamid64, minuten, grund, adminName, spielerName)
	LMNT.Bans.Remove(steamid64)
	LMNT.Bans.Get(steamid64)  -> aktiver Bann oder nil
	LMNT.Warns.Add(ply, grund, admin) -> Anzahl Verwarnungen
]]

util.AddNetworkString("lmnt_admin_bans")
util.AddNetworkString("lmnt_admin_logs")

LMNT.Bans = LMNT.Bans or {}
LMNT.Warns = LMNT.Warns or {}

LMNT.DB.Query([[CREATE TABLE IF NOT EXISTS lmnt_bans (
	steamid TEXT PRIMARY KEY,
	name TEXT,
	reason TEXT,
	admin TEXT,
	created INTEGER,
	expires INTEGER
)]])

LMNT.DB.Query([[CREATE TABLE IF NOT EXISTS lmnt_warns (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	steamid TEXT NOT NULL,
	reason TEXT,
	admin TEXT,
	time INTEGER
)]])

local function banMessage(ban)
	local untilText = tonumber(ban.expires) == 0 and "Niemals (permanent)" or os.date("%d.%m.%Y %H:%M", tonumber(ban.expires))

	return "Du bist auf " .. LMNT.Config.ServerName .. " gebannt.\n\n"
		.. "Grund: " .. (ban.reason or "-") .. "\n"
		.. "Von: " .. (ban.admin or "-") .. "\n"
		.. "Endet: " .. untilText .. "\n\n"
		.. "Entbannungsantrag: " .. LMNT.Config.Discord
end

function LMNT.Bans.Get(steamid64)
	local ban = LMNT.DB.Row("SELECT * FROM lmnt_bans WHERE steamid = ?", steamid64)
	if not ban then return nil end

	local expires = tonumber(ban.expires)
	if expires ~= 0 and expires < os.time() then
		LMNT.DB.Query("DELETE FROM lmnt_bans WHERE steamid = ?", steamid64)
		return nil
	end

	return ban
end

function LMNT.Bans.Add(steamid64, minutes, reason, adminName, name)
	local expires = minutes == 0 and 0 or (os.time() + minutes * 60)

	LMNT.DB.Query("REPLACE INTO lmnt_bans (steamid, name, reason, admin, created, expires) VALUES (?, ?, ?, ?, ?, ?)",
		steamid64, name or "?", reason, adminName, os.time(), expires)

	LMNT.Log("ban", (name or steamid64) .. " (" .. steamid64 .. ") gebannt von " .. adminName .. " für " .. LMNT.FormatMinutes(minutes) .. ": " .. reason)

	local ply = player.GetBySteamID64(steamid64)
	if IsValid(ply) then
		ply:Kick(banMessage(LMNT.Bans.Get(steamid64)))
	end
end

function LMNT.Bans.Remove(steamid64)
	local ban = LMNT.Bans.Get(steamid64)
	LMNT.DB.Query("DELETE FROM lmnt_bans WHERE steamid = ?", steamid64)
	return ban ~= nil
end

function LMNT.Bans.List()
	LMNT.DB.Query("DELETE FROM lmnt_bans WHERE expires != 0 AND expires < ?", os.time())
	return LMNT.DB.Query("SELECT * FROM lmnt_bans ORDER BY created DESC") or {}
end

-- Gebannte Spieler gar nicht erst reinlassen
hook.Add("CheckPassword", "LMNT.Bans.Check", function(steamid64)
	local ban = LMNT.Bans.Get(steamid64)
	if ban then
		return false, banMessage(ban)
	end
end)

------------------------------------------------------------------------
-- Verwarnungen mit automatischer Eskalation
------------------------------------------------------------------------

function LMNT.Warns.Count(steamid64)
	return tonumber(LMNT.DB.Value("SELECT COUNT(*) FROM lmnt_warns WHERE steamid = ?", steamid64)) or 0
end

function LMNT.Warns.List(steamid64)
	return LMNT.DB.Query("SELECT * FROM lmnt_warns WHERE steamid = ? ORDER BY time DESC", steamid64) or {}
end

function LMNT.Warns.Clear(steamid64)
	LMNT.DB.Query("DELETE FROM lmnt_warns WHERE steamid = ?", steamid64)
end

function LMNT.Warns.Add(ply, reason, admin)
	local sid = ply:SteamID64()
	LMNT.DB.Query("INSERT INTO lmnt_warns (steamid, reason, admin, time) VALUES (?, ?, ?, ?)", sid, reason, LMNT.Name(admin), os.time())

	local count = LMNT.Warns.Count(sid)
	local cfg = LMNT.Config

	if count >= cfg.WarnBanAt then
		LMNT.Bans.Add(sid, cfg.WarnBanMinutes, "Automatisch: " .. count .. " Verwarnungen", "LMNT-System", ply:Nick())
	elseif count >= cfg.WarnKickAt then
		ply:Kick("Automatischer Kick: " .. count .. " Verwarnungen.\nLetzter Grund: " .. reason)
	end

	return count
end

------------------------------------------------------------------------
-- Daten fürs Admin-Menü
------------------------------------------------------------------------

net.Receive("lmnt_admin_bans", function(_, ply)
	if not LMNT.HasPerm(ply, "ban") then return end
	if (ply.LMNTNextBanList or 0) > CurTime() then return end
	ply.LMNTNextBanList = CurTime() + 1

	local bans = LMNT.Bans.List()
	net.Start("lmnt_admin_bans")
	net.WriteUInt(math.min(#bans, 500), 10)
	for i = 1, math.min(#bans, 500) do
		local b = bans[i]
		net.WriteString(b.steamid)
		net.WriteString(b.name or "?")
		net.WriteString(b.reason or "")
		net.WriteString(b.admin or "")
		net.WriteUInt(tonumber(b.created) or 0, 32)
		net.WriteUInt(tonumber(b.expires) or 0, 32)
	end
	net.Send(ply)
end)

net.Receive("lmnt_admin_logs", function(_, ply)
	if not LMNT.HasPerm(ply, "logs") then return end
	if (ply.LMNTNextLogList or 0) > CurTime() then return end
	ply.LMNTNextLogList = CurTime() + 1

	local category = string.sub(net.ReadString(), 1, 32)
	local search = string.sub(net.ReadString(), 1, 64)
	local logs = LMNT.GetLogs(300, category, search)

	net.Start("lmnt_admin_logs")
	net.WriteUInt(#logs, 10)
	for _, l in ipairs(logs) do
		net.WriteUInt(tonumber(l.time) or 0, 32)
		net.WriteString(l.category)
		net.WriteString(string.sub(l.message, 1, 250))
	end
	net.Send(ply)
end)
