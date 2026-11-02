-- LMNT Unit-Tests: ULX-Migration (T-130) mit Beispieldaten im ULib-Format
local T = LMNT.Test

-- Test-SteamIDs, die auf keinem echten Server vorkommen
local A, B, C, D = "STEAM_0:1:900000001", "STEAM_0:0:900000002", "STEAM_0:0:900000003", "STEAM_0:1:900000004"

local function sid(s) return util.SteamIDTo64(s) end

local function cleanup()
	for _, s in ipairs({ A, B, C, D }) do
		LMNT.DB.Query("DELETE FROM lmnt_users WHERE steamid = ?", sid(s))
		LMNT.DB.Query("DELETE FROM lmnt_bans WHERE steamid = ?", sid(s))
	end
end

local function find(list, steamid)
	for _, e in ipairs(list) do
		if e.steamid == steamid then return e end
	end
end

T.Describe("ULX-Migration", function(t)
	t:It("ordnet Gruppen zu und überspringt Unbekanntes und IP-Einträge", function(e)
		cleanup()
		local plan = LMNT.Migration.PlanULib({
			[A] = { name = "Anna", group = "admin" },
			[B] = { name = "Ben", group = "operator" },
			[C] = { name = "Cem", group = "eigene_gruppe" },
			["127.0.0.1"] = { group = "admin" },
		}, {})
		e:Equal(#plan.ranks, 2)
		e:Equal(find(plan.ranks, sid(A)).to, "admin")
		e:Equal(find(plan.ranks, sid(B)).to, "moderator", "operator -> moderator")
		e:Equal(#plan.skipped, 2, "unbekannte Gruppe + IP")
	end)

	t:It("stuft nie herab", function(e)
		cleanup()
		LMNT.DB.Query("INSERT INTO lmnt_users (steamid, name, rank) VALUES (?, ?, ?)", sid(A), "Anna", "admin")
		local plan = LMNT.Migration.PlanULib({ [A] = { name = "Anna", group = "operator" } }, {})
		e:Equal(#plan.ranks, 0)
		e:Equal(#plan.skipped, 1)
		cleanup()
	end)

	t:It("vergibt nie Owner, auch wenn die Zuordnung es verlangt", function(e)
		cleanup()
		local old = LMNT.Config.ULXGroupMap.superadmin
		LMNT.Config.ULXGroupMap.superadmin = "owner"
		local plan = LMNT.Migration.PlanULib({ [A] = { group = "superadmin" } }, {})
		LMNT.Config.ULXGroupMap.superadmin = old
		e:Equal(#plan.ranks, 0)
	end)

	t:It("Banns: permanent, befristet, abgelaufen", function(e)
		cleanup()
		local now = os.time()
		local plan = LMNT.Migration.PlanULib({}, {
			[A] = { name = "Perm", reason = "Cheat", admin = "Mod", unban = 0 },
			[B] = { name = "Zeit", reason = "", unban = now + 3600 },
			[C] = { name = "Alt", unban = now - 10 },
		})
		e:Equal(#plan.bans, 2)
		e:Equal(find(plan.bans, sid(A)).minutes, 0, "permanent")
		e:Equal(find(plan.bans, sid(B)).minutes, 60)
		e:Equal(find(plan.bans, sid(B)).reason, "ULX-Import", "leerer Grund wird ersetzt")
		e:Equal(#plan.skipped, 1, "abgelaufener Bann")
	end)

	t:It("Ausführung schreibt Rang und Bann, Probelauf schreibt nichts", function(e)
		cleanup()
		local plan = LMNT.Migration.PlanULib({ [D] = { name = "Dora", group = "admin" } }, { [C] = { name = "Gebannt", unban = 0 } })
		e:Equal(LMNT.DB.Value("SELECT COUNT(*) FROM lmnt_users WHERE steamid = ?", sid(D)), "0", "Plan allein schreibt nichts")

		e:True(LMNT.Migration.ApplyULib(plan, nil))
		e:Equal(LMNT.DB.Value("SELECT rank FROM lmnt_users WHERE steamid = ?", sid(D)), "admin")
		e:True(LMNT.Bans.Get(sid(C)) ~= nil, "Bann übernommen")

		local again = LMNT.Migration.PlanULib({ [D] = { group = "admin" } }, { [C] = { unban = 0 } })
		e:Equal(#again.ranks + #again.bans, 0, "zweiter Lauf ist wirkungslos (idempotent)")
		cleanup()
	end)
end)
