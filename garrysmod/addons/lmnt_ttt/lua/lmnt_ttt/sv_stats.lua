--[[
	LMNT TTT – Statistiken, XP/Level und Punkte

	Pro Spieler (SteamID64) in lmnt_ttt_stats gespeichert.
	Netzwerk-Werte: lmnt_level, lmnt_xp, lmnt_xp_next, lmnt_points
	API:
	  LMNT.TTT.AddXP(ply, menge, grund)
	  LMNT.TTT.AddPoints(ply, menge, grund)
	  LMNT.TTT.GetPoints(ply)
]]

util.AddNetworkString("lmnt_levelup")

local cfg = LMNT.TTT.Config

LMNT.DB.Query([[CREATE TABLE IF NOT EXISTS lmnt_ttt_stats (
	steamid TEXT PRIMARY KEY,
	name TEXT,
	level INTEGER DEFAULT 1,
	xp INTEGER DEFAULT 0,
	points INTEGER DEFAULT 0,
	kills INTEGER DEFAULT 0,
	deaths INTEGER DEFAULT 0,
	teamkills INTEGER DEFAULT 0,
	wins INTEGER DEFAULT 0,
	rounds INTEGER DEFAULT 0,
	traitor_rounds INTEGER DEFAULT 0,
	playtime INTEGER DEFAULT 0,
	last_seen INTEGER
)]])

local FIELDS = { "level", "xp", "points", "kills", "deaths", "teamkills", "wins", "rounds", "traitor_rounds", "playtime" }

local function sync(ply)
	local s = ply.LMNTStats
	if not s then return end

	ply:SetNWInt("lmnt_level", s.level)
	ply:SetNWInt("lmnt_xp", s.xp)
	ply:SetNWInt("lmnt_xp_next", cfg.XPForLevel(s.level))
	ply:SetNWInt("lmnt_points", s.points)
end

local function load(ply)
	local sid = ply:SteamID64()
	local row = LMNT.DB.Row("SELECT * FROM lmnt_ttt_stats WHERE steamid = ?", sid)

	if not row then
		LMNT.DB.Query("INSERT INTO lmnt_ttt_stats (steamid, name, points, last_seen) VALUES (?, ?, ?, ?)", sid, ply:Nick(), cfg.Points.StartBonus, os.time())
		row = LMNT.DB.Row("SELECT * FROM lmnt_ttt_stats WHERE steamid = ?", sid)
	end

	local stats = {}
	for _, f in ipairs(FIELDS) do stats[f] = tonumber(row[f]) or 0 end
	stats.level = math.max(stats.level, 1)

	ply.LMNTStats = stats
	ply.LMNTJoinTime = CurTime()
	sync(ply)
end

function LMNT.TTT.SaveStats(ply)
	local s = ply.LMNTStats
	if not s then return end

	local now = CurTime()
	s.playtime = s.playtime + math.floor(now - (ply.LMNTJoinTime or now))
	ply.LMNTJoinTime = now

	LMNT.DB.Query([[UPDATE lmnt_ttt_stats SET name = ?, level = ?, xp = ?, points = ?, kills = ?, deaths = ?, teamkills = ?,
		wins = ?, rounds = ?, traitor_rounds = ?, playtime = ?, last_seen = ? WHERE steamid = ?]],
		ply:Nick(), s.level, s.xp, s.points, s.kills, s.deaths, s.teamkills, s.wins, s.rounds, s.traitor_rounds, s.playtime, os.time(), ply:SteamID64())
end

local function multiplier(ply)
	return LMNT.RankHasPerm(ply:GetUserGroup(), "vip") and LMNT.Settings.Get("ttt.stats.vip_multiplier") or 1
end

function LMNT.TTT.AddXP(ply, amount)
	local s = ply.LMNTStats
	if not s or amount == 0 then return end

	if amount > 0 then amount = math.floor(amount * multiplier(ply)) end
	s.xp = math.max(0, s.xp + amount)

	local leveled = false
	while s.xp >= cfg.XPForLevel(s.level) do
		s.xp = s.xp - cfg.XPForLevel(s.level)
		s.level = s.level + 1
		leveled = true
	end

	if leveled then
		net.Start("lmnt_levelup")
		net.WriteUInt(s.level, 16)
		net.Send(ply)
		LMNT.Notify(nil, ply, color_white, " hat ", LMNT.Config.Colors.accent, "Level " .. s.level, color_white, " erreicht!")
	end

	sync(ply)
end

function LMNT.TTT.AddPoints(ply, amount)
	local s = ply.LMNTStats
	if not s or amount == 0 then return end

	if amount > 0 then amount = math.floor(amount * multiplier(ply)) end
	s.points = math.max(0, s.points + amount)
	sync(ply)
end

function LMNT.TTT.GetPoints(ply)
	return ply.LMNTStats and ply.LMNTStats.points or 0
end

local function countsForStats()
	return player.GetCount() >= LMNT.Settings.Get("ttt.stats.min_players")
end

------------------------------------------------------------------------
-- Ereignisse
------------------------------------------------------------------------

LMNT.TTT.LoadStats = load
hook.Add("PlayerInitialSpawn", "LMNT.Stats.Load", load)

hook.Add("PlayerDisconnected", "LMNT.Stats.Save", LMNT.TTT.SaveStats)

hook.Add("ShutDown", "LMNT.Stats.SaveAll", function()
	for _, ply in ipairs(player.GetAll()) do LMNT.TTT.SaveStats(ply) end
end)

-- Rundenstatistik für den MVP
local roundKills = {}

hook.Add("TTTBeginRound", "LMNT.Stats.Begin", function()
	roundKills = {}
end)

hook.Add("PlayerDeath", "LMNT.Stats.Death", function(victim, _, attacker)
	if GetRoundState() ~= ROUND_ACTIVE or not countsForStats() then return end
	if not victim.LMNTStats then return end

	victim.LMNTStats.deaths = victim.LMNTStats.deaths + 1

	if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim or not attacker.LMNTStats then return end

	local victimTeam, attackerTeam = LMNT.TTT.GetTeam(victim), LMNT.TTT.GetTeam(attacker)
	local s = attacker.LMNTStats

	-- Den Narren zu töten zählt weder positiv noch negativ
	if TEAM_NARR and victimTeam == TEAM_NARR then return end

	if victimTeam == attackerTeam then
		s.teamkills = s.teamkills + 1
		LMNT.TTT.AddXP(attacker, cfg.XP.TeamKill)
		LMNT.TTT.AddPoints(attacker, cfg.Points.TeamKill)
		LMNT.Log("kill", attacker:Nick() .. " hat TEAMKOLLEGEN " .. victim:Nick() .. " getötet")
	else
		s.kills = s.kills + 1
		roundKills[attacker] = (roundKills[attacker] or 0) + 1
		LMNT.TTT.AddXP(attacker, cfg.XP.Kill)
		LMNT.TTT.AddPoints(attacker, cfg.Points.Kill)
		LMNT.Log("kill", attacker:Nick() .. " [" .. attackerTeam .. "] hat " .. victim:Nick() .. " [" .. victimTeam .. "] getötet")
	end
end)

hook.Add("TTTEndRound", "LMNT.Stats.End", function(result)
	if not countsForStats() then return end

	for _, ply in ipairs(player.GetAll()) do
		local s = ply.LMNTStats
		if s and ply:GetNWBool("lmnt_played_round") then
			s.rounds = s.rounds + 1
			if ply:IsTraitor() then s.traitor_rounds = s.traitor_rounds + 1 end

			local xp, pts = cfg.XP.Played, cfg.Points.Played

			if LMNT.TTT.GetTeam(ply) == result then
				s.wins = s.wins + 1
				xp, pts = xp + cfg.XP.Win, pts + cfg.Points.Win
			end

			if ply:Alive() and not ply:IsSpec() then
				xp, pts = xp + cfg.XP.Survive, pts + cfg.Points.Survive
			end

			LMNT.TTT.AddXP(ply, xp)
			LMNT.TTT.AddPoints(ply, pts)
			LMNT.Notify(ply, LMNT.Config.Colors.muted, "Runde vorbei: +" .. xp .. " XP, +" .. pts .. " Punkte")
		end

		if s then LMNT.TTT.SaveStats(ply) end
	end

	-- MVP der Runde
	local best, bestKills = nil, 0
	for ply, kills in pairs(roundKills) do
		if IsValid(ply) and kills > bestKills then best, bestKills = ply, kills end
	end

	if best and bestKills >= 2 then
		LMNT.Notify(nil, LMNT.Config.Colors.warn, "MVP der Runde: ", best, color_white, " mit " .. bestKills .. " Kills (+10 Punkte)")
		LMNT.TTT.AddPoints(best, 10)
	end

	LMNT.Log("round", "Runde beendet, Gewinner: " .. tostring(result))
end)

-- Wer zu Rundenbeginn lebt, hat die Runde mitgespielt (auch wenn er später stirbt)
hook.Add("TTTBeginRound", "LMNT.Stats.Participants", function()
	for _, ply in ipairs(player.GetAll()) do
		ply:SetNWBool("lmnt_played_round", ply:Alive() and not ply:IsSpec())
	end
end)

------------------------------------------------------------------------
-- Abfragen
------------------------------------------------------------------------

function LMNT.TTT.GetTop(field, limit)
	local allowed = { level = "level DESC, xp DESC", kills = "kills DESC", wins = "wins DESC", points = "points DESC", playtime = "playtime DESC" }
	local order = allowed[field] or allowed.level
	return LMNT.DB.Query("SELECT name, level, xp, kills, deaths, wins, rounds, points, playtime FROM lmnt_ttt_stats ORDER BY " .. order .. " LIMIT ?", limit or 10) or {}
end

function LMNT.TTT.SendStats(caller, target)
	local s = target.LMNTStats
	if not s then return end

	local col = LMNT.Config.Colors
	local kd = s.deaths > 0 and math.Round(s.kills / s.deaths, 2) or s.kills
	local winrate = s.rounds > 0 and math.Round(s.wins / s.rounds * 100) or 0

	LMNT.Reply(caller, col.primary, "Statistik von ", target, col.primary, ":")
	LMNT.Reply(caller, color_white, "Level " .. s.level .. "  (" .. s.xp .. "/" .. cfg.XPForLevel(s.level) .. " XP)   Punkte: " .. s.points)
	LMNT.Reply(caller, color_white, "Kills: " .. s.kills .. "   Tode: " .. s.deaths .. "   K/D: " .. kd .. "   Teamkills: " .. s.teamkills)
	LMNT.Reply(caller, color_white, "Runden: " .. s.rounds .. "   Siege: " .. s.wins .. " (" .. winrate .. " %)   Traitor-Runden: " .. s.traitor_rounds)
	LMNT.Reply(caller, color_white, "Spielzeit: " .. LMNT.FormatMinutes(math.floor(s.playtime / 60)))
end
