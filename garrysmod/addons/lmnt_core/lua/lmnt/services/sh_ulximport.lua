--[[
	LMNT Service – Einmalige Migration aus ULX/ULib (T-130, ADR-011: LMNT-Admin ist führend)

	!ulximport               Probelauf: zeigt, was übernommen würde (schreibt nichts)
	!ulximport ausfuehren    übernimmt Ränge und Banns (Transaktion, jede Änderung im Log)

	Quelle zur Laufzeit (offizielle ULib-Tabellen):
	  ULib.ucl.users[id] = { name, group, allow, deny }      id = SteamID oder IP
	  ULib.bans[steamid] = { name, reason, admin, unban }    unban = Unix-Zeit, 0 = permanent

	Regeln:
	  - Gruppen werden über LMNT.Config.ULXGroupMap zugeordnet; unbekannte Gruppen werden übersprungen
	  - nie herabstufen (nur übernehmen, wenn der LMNT-Rang niedriger ist), nie "owner" vergeben
	  - IP-basierte Einträge werden übersprungen (LMNT arbeitet mit SteamID64)
	  - abgelaufene Banns und bereits gebannte SteamIDs werden übersprungen
	  - kein laufender Abgleich: ULX-Änderungen danach werden nicht übernommen

	API (Server):
	  LMNT.Migration.PlanULib(users, bans) -> plan { ranks = {...}, bans = {...}, skipped = {...} }
	  LMNT.Migration.ApplyULib(plan, actor) -> ok, fehler
]]

-- Standard-Zuordnung der ULX-Gruppen zu LMNT-Rängen (in sh_config.lua überschreibbar)
LMNT.Config.ULXGroupMap = LMNT.Config.ULXGroupMap or {
	superadmin = "superadmin",
	admin = "admin",
	operator = "moderator",
	user = "user",
}

LMNT.Migration = LMNT.Migration or {}

if SERVER then
	local function currentRank(sid64)
		local row = LMNT.DB.Row("SELECT rank FROM lmnt_users WHERE steamid = ?", sid64)
		return row and row.rank or "user"
	end

	function LMNT.Migration.PlanULib(users, bans)
		local plan = { ranks = {}, bans = {}, skipped = {} }
		local map = LMNT.Config.ULXGroupMap
		local now = os.time()

		local function skip(id, why)
			plan.skipped[#plan.skipped + 1] = { id = tostring(id), reason = why }
		end

		for id, user in pairs(users or {}) do
			local sid64 = LMNT.ToSteamID64(tostring(id))
			local group = istable(user) and user.group or nil
			local target = group and map[group]

			if not sid64 then
				skip(id, "kein SteamID-Eintrag (z. B. IP-basiert)")
			elseif not target or not LMNT.Ranks[target] then
				skip(id, "ULX-Gruppe '" .. tostring(group) .. "' hat keine LMNT-Zuordnung")
			elseif target == "owner" then
				skip(id, "Owner wird nie per Import vergeben")
			else
				local current = currentRank(sid64)
				if LMNT.GetRank(target).level <= LMNT.GetRank(current).level then
					skip(id, "LMNT-Rang " .. current .. " ist gleich oder höher als " .. target .. " (keine Herabstufung)")
				else
					plan.ranks[#plan.ranks + 1] = { steamid = sid64, name = user.name, from = current, to = target, ulxGroup = group }
				end
			end
		end

		for id, ban in pairs(bans or {}) do
			local sid64 = LMNT.ToSteamID64(tostring(id))
			local unban = istable(ban) and tonumber(ban.unban) or 0

			if not sid64 then
				skip(id, "Bann ohne gültige SteamID")
			elseif unban ~= 0 and unban <= now then
				skip(id, "Bann bereits abgelaufen")
			elseif LMNT.Bans.Get(sid64) then
				skip(id, "in LMNT bereits gebannt")
			else
				plan.bans[#plan.bans + 1] = {
					steamid = sid64,
					name = ban.name,
					reason = (ban.reason and ban.reason ~= "") and ban.reason or "ULX-Import",
					admin = "ULX-Import (" .. tostring(ban.admin or "?") .. ")",
					minutes = unban == 0 and 0 or math.ceil((unban - now) / 60),
				}
			end
		end

		table.SortByMember(plan.ranks, "steamid", true)
		table.SortByMember(plan.bans, "steamid", true)
		return plan
	end

	function LMNT.Migration.ApplyULib(plan, actor)
		local who = LMNT.Name(actor)
		-- Ränge innerhalb der Transaktion nur speichern; auf Online-Spieler erst nach dem Commit anwenden.
		-- Banns: LMNT.Bans.Add kickt einen online befindlichen Spieler sofort. Bei ULX-gebannten SteamIDs
		-- ist das praktisch nie der Fall (ULX verhindert den Join); dokumentierte Grenze.
		local ok, err = LMNT.DB.Transaction(function()
			for _, r in ipairs(plan.ranks) do
				LMNT.Admin.SetRank(r.steamid, r.to, r.name, true)
				LMNT.Log.Info("migration", who .. ": Rang " .. r.steamid .. " (" .. tostring(r.name) .. ") " .. r.from .. " -> " .. r.to .. " (ULX-Gruppe " .. r.ulxGroup .. ")")
			end
			for _, b in ipairs(plan.bans) do
				LMNT.Bans.Add(b.steamid, b.minutes, b.reason, b.admin, b.name)
			end
		end)

		if ok then
			for _, r in ipairs(plan.ranks) do
				local ply = player.GetBySteamID64(r.steamid)
				if IsValid(ply) then ply:SetUserGroup(r.to) end
			end
			LMNT.Log.Info("migration", who .. " hat den ULX-Import ausgeführt: " .. #plan.ranks .. " Ränge, " .. #plan.bans .. " Banns, " .. #plan.skipped .. " übersprungen")
		end
		return ok, err
	end
end

LMNT.Admin.AddCommand("ulximport", {
	perm = "dev",
	help = "Einmalige Migration von Rängen und Banns aus ULX (ohne 'ausfuehren' nur Probelauf)",
	args = { { type = "string", name = "ausfuehren", optional = true } },
	run = function(caller, mode)
		local col = LMNT.Config.Colors

		if not (istable(ULib) and istable(ULib.ucl) and istable(ULib.ucl.users)) then
			LMNT.Reply(caller, col.warn, "ULX/ULib ist nicht installiert – nichts zu importieren.")
			return
		end

		local plan = LMNT.Migration.PlanULib(ULib.ucl.users, istable(ULib.bans) and ULib.bans or {})
		local execute = mode and string.lower(mode) == "ausfuehren"

		LMNT.Reply(caller, col.primary, (execute and "ULX-Import" or "ULX-Import – PROBELAUF") .. ": ",
			color_white, #plan.ranks .. " Ränge, " .. #plan.bans .. " Banns, " .. #plan.skipped .. " übersprungen (Details in der Konsole)")

		local function console(line)
			if IsValid(caller) then caller:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
		end
		for _, r in ipairs(plan.ranks) do console("RANG  " .. r.steamid .. "  " .. tostring(r.name) .. "  " .. r.from .. " -> " .. r.to) end
		for _, b in ipairs(plan.bans) do console("BANN  " .. b.steamid .. "  " .. tostring(b.name) .. "  " .. LMNT.FormatMinutes(b.minutes) .. "  " .. b.reason) end
		for _, s in ipairs(plan.skipped) do console("SKIP  " .. s.id .. "  " .. s.reason) end

		if not execute then
			LMNT.Reply(caller, col.muted, "Zum Übernehmen: !ulximport ausfuehren")
			return
		end

		local ok, err = LMNT.Migration.ApplyULib(plan, caller)
		LMNT.Reply(caller, ok and col.good or col.bad, ok and "Import abgeschlossen. Empfehlung: ULX jetzt entfernen (ADR-011)." or ("Import fehlgeschlagen und zurückgerollt: " .. tostring(err)))
	end,
})
