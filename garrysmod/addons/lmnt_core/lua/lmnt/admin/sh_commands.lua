--[[
	LMNT Admin – Standardbefehle
	TTT-spezifische Befehle (slaynr, credits, karma …) registriert das Addon lmnt_ttt.
]]

local A = LMNT.Admin
local col = LMNT.Config.Colors

local function self_(caller) return caller end

------------------------------------------------------------------------
-- Für alle
------------------------------------------------------------------------

A.AddCommand("hilfe", {
	help = "Zeigt alle Befehle, die du nutzen darfst",
	aliases = { "help", "befehle" },
	run = function(caller)
		local names = table.GetKeys(A.Commands)
		table.sort(names)

		LMNT.Reply(caller, col.primary, "Verfügbare Befehle (Details in der Konsole):")
		for _, name in ipairs(names) do
			local cmd = A.Commands[name]
			if LMNT.HasPerm(caller, cmd.perm) then
				if IsValid(caller) then
					caller:PrintMessage(HUD_PRINTCONSOLE, A.Usage(cmd) .. "  –  " .. (cmd.help or ""))
				else
					print(A.Usage(cmd) .. "  –  " .. (cmd.help or ""))
				end
			end
		end
	end,
})

A.AddCommand("regeln", {
	help = "Zeigt die Serverregeln",
	aliases = { "rules" },
	run = function(caller)
		LMNT.Reply(caller, col.primary, "Regeln von " .. LMNT.Config.ServerName .. ":")
		for _, rule in ipairs(LMNT.Config.Rules) do
			LMNT.Reply(caller, color_white, rule)
		end
	end,
})

A.AddCommand("discord", {
	help = "Zeigt den Discord-Link",
	run = function(caller)
		LMNT.Reply(caller, col.primary, "Discord: ", color_white, LMNT.Config.Discord)
	end,
})

A.AddCommand("pm", {
	help = "Private Nachricht an einen Spieler",
	aliases = { "msg" },
	playerOnly = true,
	args = {
		{ type = "player", name = "spieler", ignoreImmunity = true },
		{ type = "string", name = "nachricht", rest = true },
	},
	run = function(caller, target, text)
		LMNT.Notify(target, col.accent, "[PM] ", caller, color_white, ": " .. text)
		LMNT.Notify(caller, col.accent, "[PM an ", target, col.accent, "] ", color_white, text)
		LMNT.Log("pm", caller:Nick() .. " -> " .. target:Nick() .. ": " .. text)
	end,
})

------------------------------------------------------------------------
-- Moderation
------------------------------------------------------------------------

A.AddCommand("menu", {
	perm = "menu", log = false, playerOnly = true,
	help = "Öffnet das Admin-Menü",
	aliases = { "admin" },
	run = function(caller)
		net.Start("lmnt_admin_open")
		net.Send(caller)
	end,
})

A.AddCommand("who", {
	perm = "who", log = false,
	help = "Liste aller Spieler mit Rang und SteamID",
	run = function(caller)
		for _, ply in ipairs(player.GetAll()) do
			local rank = LMNT.GetRank(ply:GetUserGroup())
			LMNT.Reply(caller, rank.color, "[" .. rank.name .. "] ", color_white, ply:Nick() .. "  ", col.muted, ply:SteamID() .. "  #" .. ply:UserID())
		end
	end,
})

A.AddCommand("asay", {
	perm = "asay", log = false, playerOnly = true,
	help = "Nachricht in den Team-Chat (oder einfach @Text schreiben)",
	args = { { type = "string", name = "nachricht", rest = true } },
	run = function(caller, text)
		hook.Run("PlayerSay", caller, "@" .. text, false)
	end,
})

A.AddCommand("kick", {
	perm = "kick",
	help = "Kickt einen Spieler",
	args = {
		{ type = "player", name = "spieler" },
		{ type = "string", name = "grund", optional = true, rest = true, default = "Kein Grund angegeben" },
	},
	run = function(caller, target, reason)
		A.Broadcast(caller, "hat", target, " gekickt (" .. reason .. ")")
		target:Kick("Gekickt von " .. LMNT.Name(caller) .. ": " .. reason)
	end,
})

local function checkBanLength(caller, minutes)
	if not IsValid(caller) then return true end
	local maxBan = LMNT.GetRank(caller:GetUserGroup()).maxBan
	if maxBan == nil then return false end
	if maxBan == 0 then return true end
	return minutes ~= 0 and minutes <= maxBan
end

A.AddCommand("ban", {
	perm = "ban",
	help = "Bannt einen Spieler (Zeit: 30m, 2h, 1d, 1w, 0 = permanent)",
	args = {
		{ type = "player", name = "spieler" },
		{ type = "time", name = "zeit" },
		{ type = "string", name = "grund", optional = true, rest = true, default = "Kein Grund angegeben" },
	},
	run = function(caller, target, minutes, reason)
		if not checkBanLength(caller, minutes) then
			LMNT.Reply(caller, col.bad, "So lange darfst du nicht bannen (max. " .. LMNT.FormatMinutes(LMNT.GetRank(caller:GetUserGroup()).maxBan or 0) .. ").")
			return
		end
		A.Broadcast(caller, "hat", target, " gebannt (" .. LMNT.FormatMinutes(minutes) .. ", " .. reason .. ")")
		LMNT.Bans.Add(target:SteamID64(), minutes, reason, LMNT.Name(caller), target:Nick())
	end,
})

A.AddCommand("banid", {
	perm = "banid",
	help = "Bannt eine SteamID (auch offline)",
	args = {
		{ type = "steamid", name = "steamid" },
		{ type = "time", name = "zeit" },
		{ type = "string", name = "grund", optional = true, rest = true, default = "Kein Grund angegeben" },
	},
	run = function(caller, sid, minutes, reason)
		if not checkBanLength(caller, minutes) then
			LMNT.Reply(caller, col.bad, "So lange darfst du nicht bannen.")
			return
		end
		local row = LMNT.DB.Row("SELECT name, rank FROM lmnt_users WHERE steamid = ?", sid)
		if row and IsValid(caller) and LMNT.GetRank(row.rank).level >= LMNT.GetLevel(caller) then
			LMNT.Reply(caller, col.bad, "Diese SteamID hat einen gleich hohen oder höheren Rang.")
			return
		end
		A.Broadcast(caller, "hat", (row and row.name or sid), " gebannt (" .. LMNT.FormatMinutes(minutes) .. ", " .. reason .. ")")
		LMNT.Bans.Add(sid, minutes, reason, LMNT.Name(caller), row and row.name)
	end,
})

A.AddCommand("unban", {
	perm = "unban",
	help = "Hebt einen Bann auf",
	args = { { type = "steamid", name = "steamid" } },
	run = function(caller, sid)
		if LMNT.Bans.Remove(sid) then
			A.Broadcast(caller, "hat", sid, " entbannt")
			LMNT.Log("ban", sid .. " entbannt von " .. LMNT.Name(caller))
		else
			LMNT.Reply(caller, col.warn, "Kein aktiver Bann für " .. sid .. ".")
		end
	end,
})

A.AddCommand("warn", {
	perm = "warn",
	help = "Verwarnt einen Spieler (automatischer Kick/Bann bei zu vielen Warns)",
	args = {
		{ type = "player", name = "spieler" },
		{ type = "string", name = "grund", rest = true },
	},
	run = function(caller, target, reason)
		A.Broadcast(caller, "hat", target, " verwarnt (" .. reason .. ")")
		LMNT.Notify(target, col.bad, "Du wurdest verwarnt: ", color_white, reason)
		local count = LMNT.Warns.Add(target, reason, caller)
		LMNT.Reply(caller, col.muted, target:Nick() .. " hat jetzt " .. count .. " Verwarnung(en).")
	end,
})

A.AddCommand("warns", {
	perm = "warn", log = false,
	help = "Zeigt die Verwarnungen eines Spielers",
	args = { { type = "player", name = "spieler", ignoreImmunity = true } },
	run = function(caller, target)
		local list = LMNT.Warns.List(target:SteamID64())
		LMNT.Reply(caller, col.primary, target:Nick() .. " hat " .. #list .. " Verwarnung(en):")
		for _, w in ipairs(list) do
			LMNT.Reply(caller, col.muted, os.date("%d.%m.%y ", tonumber(w.time)), color_white, w.reason .. " ", col.muted, "(" .. w.admin .. ")")
		end
	end,
})

A.AddCommand("clearwarns", {
	perm = "clearwarns",
	help = "Löscht alle Verwarnungen eines Spielers",
	args = { { type = "player", name = "spieler" } },
	run = function(caller, target)
		LMNT.Warns.Clear(target:SteamID64())
		A.Broadcast(caller, "hat die Verwarnungen von", target, " gelöscht")
	end,
})

A.AddCommand("mute", {
	perm = "mute",
	help = "Schaltet den Chat eines Spielers stumm",
	args = { { type = "players", name = "spieler" } },
	run = function(caller, targets)
		for _, t in ipairs(targets) do t.LMNTMuted = true end
		A.Broadcast(caller, "hat", targets, " im Chat stummgeschaltet")
	end,
})

A.AddCommand("unmute", {
	perm = "mute",
	help = "Hebt die Chat-Stummschaltung auf",
	args = { { type = "players", name = "spieler" } },
	run = function(caller, targets)
		for _, t in ipairs(targets) do t.LMNTMuted = nil end
		A.Broadcast(caller, "hat die Chat-Stummschaltung von", targets, " aufgehoben")
	end,
})

A.AddCommand("gag", {
	perm = "gag",
	help = "Schaltet das Mikrofon eines Spielers stumm",
	args = { { type = "players", name = "spieler" } },
	run = function(caller, targets)
		for _, t in ipairs(targets) do t.LMNTGagged = true end
		A.Broadcast(caller, "hat", targets, " im Voice-Chat stummgeschaltet")
	end,
})

A.AddCommand("ungag", {
	perm = "gag",
	help = "Hebt die Voice-Stummschaltung auf",
	args = { { type = "players", name = "spieler" } },
	run = function(caller, targets)
		for _, t in ipairs(targets) do t.LMNTGagged = nil end
		A.Broadcast(caller, "hat die Voice-Stummschaltung von", targets, " aufgehoben")
	end,
})

A.AddCommand("slay", {
	perm = "slay",
	help = "Tötet Spieler sofort",
	args = { { type = "players", name = "spieler" } },
	run = function(caller, targets)
		for _, t in ipairs(targets) do
			if t:Alive() then t:Kill() end
		end
		A.Broadcast(caller, "hat", targets, " getötet")
	end,
})

A.AddCommand("freeze", {
	perm = "freeze",
	help = "Friert Spieler ein",
	args = { { type = "players", name = "spieler" } },
	run = function(caller, targets)
		for _, t in ipairs(targets) do t:Freeze(true) t.LMNTFrozen = true end
		A.Broadcast(caller, "hat", targets, " eingefroren")
	end,
})

A.AddCommand("unfreeze", {
	perm = "freeze",
	help = "Taut Spieler wieder auf",
	args = { { type = "players", name = "spieler" } },
	run = function(caller, targets)
		for _, t in ipairs(targets) do t:Freeze(false) t.LMNTFrozen = nil end
		A.Broadcast(caller, "hat", targets, " aufgetaut")
	end,
})

------------------------------------------------------------------------
-- Teleport
------------------------------------------------------------------------

local function findFreeSpot(target)
	local base = target:GetPos()
	local dirs = { Vector(50, 0, 0), Vector(-50, 0, 0), Vector(0, 50, 0), Vector(0, -50, 0), Vector(0, 0, 80) }

	for _, d in ipairs(dirs) do
		local pos = base + d
		local tr = util.TraceHull({ start = pos, endpos = pos, mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), filter = target })
		if not tr.Hit then return pos end
	end

	return base + Vector(0, 0, 80)
end

local function teleport(ply, pos)
	ply.LMNTReturnPos = ply:GetPos()
	if ply:InVehicle() then ply:ExitVehicle() end
	ply:SetPos(pos)
	ply:SetLocalVelocity(vector_origin)
end

A.AddCommand("goto", {
	perm = "goto", playerOnly = true,
	help = "Teleportiert dich zu einem Spieler",
	args = { { type = "player", name = "spieler", ignoreImmunity = true } },
	run = function(caller, target)
		teleport(caller, findFreeSpot(target))
		A.Broadcast(caller, "hat sich zu", target, " teleportiert")
	end,
})

A.AddCommand("bring", {
	perm = "bring", playerOnly = true,
	help = "Holt Spieler zu dir",
	args = { { type = "players", name = "spieler" } },
	run = function(caller, targets)
		for _, t in ipairs(targets) do
			if t ~= caller then teleport(t, findFreeSpot(caller)) end
		end
		A.Broadcast(caller, "hat", targets, " zu sich geholt")
	end,
})

A.AddCommand("return", {
	perm = "return",
	help = "Bringt Spieler an ihre Position vor dem Teleport zurück",
	args = { { type = "player", name = "spieler", optional = true, default = self_ } },
	run = function(caller, target)
		if not IsValid(target) or not target.LMNTReturnPos then
			LMNT.Reply(caller, col.warn, "Keine gespeicherte Position.")
			return
		end
		target:SetPos(target.LMNTReturnPos)
		target.LMNTReturnPos = nil
		A.Broadcast(caller, "hat", target, " zurückgebracht")
	end,
})

------------------------------------------------------------------------
-- Moderator+
------------------------------------------------------------------------

A.AddCommand("noclip", {
	perm = "noclip",
	help = "Schaltet Noclip um",
	args = { { type = "player", name = "spieler", optional = true, default = self_ } },
	run = function(caller, target)
		if not IsValid(target) then return end
		local on = target:GetMoveType() ~= MOVETYPE_NOCLIP
		target:SetMoveType(on and MOVETYPE_NOCLIP or MOVETYPE_WALK)
		LMNT.Reply(caller, col.good, "Noclip für " .. target:Nick() .. ": " .. (on and "an" or "aus"))
	end,
})

A.AddCommand("god", {
	perm = "god",
	help = "Schaltet Unverwundbarkeit um",
	args = { { type = "player", name = "spieler", optional = true, default = self_ } },
	run = function(caller, target)
		if not IsValid(target) then return end
		target.LMNTGod = not target.LMNTGod or nil
		LMNT.Reply(caller, col.good, "Godmode für " .. target:Nick() .. ": " .. (target.LMNTGod and "an" or "aus"))
	end,
})

A.AddCommand("hp", {
	perm = "hp",
	help = "Setzt die Lebenspunkte",
	args = {
		{ type = "players", name = "spieler" },
		{ type = "number", name = "hp", min = 1, max = 1000 },
	},
	run = function(caller, targets, hp)
		for _, t in ipairs(targets) do t:SetHealth(hp) end
		A.Broadcast(caller, "hat die HP von", targets, " auf " .. hp .. " gesetzt")
	end,
})

A.AddCommand("announce", {
	perm = "announce",
	help = "Große Bildschirm-Ankündigung für alle",
	aliases = { "ankuendigung" },
	args = { { type = "string", name = "text", rest = true } },
	run = function(_, text)
		LMNT.Announce(text, col.accent, 7)
	end,
})

A.AddCommand("cleardecals", {
	perm = "cleardecals",
	help = "Entfernt Blut und Einschusslöcher bei allen",
	run = function(caller)
		for _, ply in ipairs(player.GetAll()) do ply:ConCommand("r_cleardecals") end
		A.Broadcast(caller, "hat alle Decals entfernt")
	end,
})

------------------------------------------------------------------------
-- Admin+
------------------------------------------------------------------------

A.AddCommand("setrank", {
	perm = "setrank",
	help = "Setzt den Rang eines Spielers",
	args = {
		{ type = "player", name = "spieler" },
		{ type = "rank", name = "rang" },
	},
	run = function(caller, target, rankId)
		if IsValid(caller) and LMNT.Ranks[rankId].level >= LMNT.GetLevel(caller) then
			LMNT.Reply(caller, col.bad, "Du kannst nur Ränge unterhalb deines eigenen vergeben.")
			return
		end
		LMNT.Admin.SetRank(target:SteamID64(), rankId, target:Nick())
		A.Broadcast(caller, "hat", target, " den Rang " .. LMNT.Ranks[rankId].name .. " gegeben")
	end,
})

A.AddCommand("setrankid", {
	perm = "setrank",
	help = "Setzt den Rang einer SteamID (auch offline)",
	args = {
		{ type = "steamid", name = "steamid" },
		{ type = "rank", name = "rang" },
	},
	run = function(caller, sid, rankId)
		if IsValid(caller) then
			local row = LMNT.DB.Row("SELECT rank FROM lmnt_users WHERE steamid = ?", sid)
			local current = row and LMNT.GetRank(row.rank).level or 0
			if LMNT.Ranks[rankId].level >= LMNT.GetLevel(caller) or current >= LMNT.GetLevel(caller) then
				LMNT.Reply(caller, col.bad, "Dafür ist dein Rang zu niedrig.")
				return
			end
		end
		LMNT.Admin.SetRank(sid, rankId)
		LMNT.Reply(caller, col.good, sid .. " hat jetzt den Rang " .. LMNT.Ranks[rankId].name .. ".")
	end,
})

A.AddCommand("map", {
	perm = "map",
	help = "Wechselt die Map",
	args = { { type = "map", name = "map" } },
	run = function(caller, map)
		A.Broadcast(caller, "wechselt die Map zu", map, " (in 5 Sekunden)")
		timer.Simple(5, function() RunConsoleCommand("changelevel", map) end)
	end,
})

A.AddCommand("logs", {
	perm = "logs", log = false,
	help = "Zeigt die letzten Logs in der Konsole",
	args = {
		{ type = "number", name = "anzahl", optional = true, default = 30, min = 1, max = 200 },
		{ type = "string", name = "kategorie", optional = true },
	},
	run = function(caller, amount, category)
		local logs = LMNT.GetLogs(amount, category)
		for i = #logs, 1, -1 do
			local l = logs[i]
			local line = os.date("%d.%m %H:%M:%S", tonumber(l.time)) .. " [" .. l.category .. "] " .. l.message
			if IsValid(caller) then caller:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
		end
		LMNT.Reply(caller, col.muted, #logs .. " Log-Einträge in der Konsole ausgegeben.")
	end,
})
