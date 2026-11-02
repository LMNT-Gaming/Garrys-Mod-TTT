--[[
	LMNT TTT – Modul "ttt.moderation": TTT-spezifische Team-Befehle
	(Spieler-Befehle wie !shop, !stats und !special gehören zu ihren jeweiligen Modulen.)
]]

local A = LMNT.Admin
local col = LMNT.Config.Colors

-- Slay next round: wird gespeichert und überlebt Reconnects/Mapwechsel
if SERVER then
	LMNT.DB.Query("CREATE TABLE IF NOT EXISTS lmnt_slaynr (steamid TEXT PRIMARY KEY, rounds INTEGER, reason TEXT, admin TEXT)")

	hook.Add("TTTBeginRound", "LMNT.TTT.SlayNR", function()
		timer.Simple(0.5, function()
			for _, ply in ipairs(player.GetAll()) do
				local row = LMNT.DB.Row("SELECT * FROM lmnt_slaynr WHERE steamid = ?", ply:SteamID64())
				if row and ply:Alive() and not ply:IsSpec() then
					ply:Kill()
					LMNT.Notify(nil, ply, color_white, " wurde automatisch geslayt ", col.muted, "(" .. (row.reason or "") .. ")")

					local left = tonumber(row.rounds) - 1
					if left <= 0 then
						LMNT.DB.Query("DELETE FROM lmnt_slaynr WHERE steamid = ?", ply:SteamID64())
					else
						LMNT.DB.Query("UPDATE lmnt_slaynr SET rounds = ? WHERE steamid = ?", left, ply:SteamID64())
					end
				end
			end
		end)
	end)
end

A.AddCommand("slaynr", {
	perm = "slaynr",
	help = "Slayt einen Spieler in den nächsten X Runden",
	args = {
		{ type = "player", name = "spieler" },
		{ type = "number", name = "runden", optional = true, default = 1, min = 1, max = 10 },
		{ type = "string", name = "grund", optional = true, rest = true, default = "RDM" },
	},
	run = function(caller, target, rounds, reason)
		LMNT.DB.Query("REPLACE INTO lmnt_slaynr (steamid, rounds, reason, admin) VALUES (?, ?, ?, ?)", target:SteamID64(), rounds, reason, LMNT.Name(caller))
		A.Broadcast(caller, "slayt", target, " in den nächsten " .. rounds .. " Runde(n) (" .. reason .. ")")
	end,
})

A.AddCommand("unslaynr", {
	perm = "slaynr",
	help = "Hebt einen Slay-next-round auf",
	args = { { type = "player", name = "spieler" } },
	run = function(caller, target)
		LMNT.DB.Query("DELETE FROM lmnt_slaynr WHERE steamid = ?", target:SteamID64())
		A.Broadcast(caller, "hat den Slay von", target, " aufgehoben")
	end,
})

A.AddCommand("respawn", {
	perm = "respawn",
	help = "Belebt einen toten Spieler wieder",
	args = { { type = "player", name = "spieler" } },
	run = function(caller, target)
		if target:Alive() and not target:IsSpec() then
			LMNT.Reply(caller, col.warn, target:Nick() .. " lebt bereits.")
			return
		end
		target:SpawnForRound(true)
		A.Broadcast(caller, "hat", target, " wiederbelebt")
	end,
})

A.AddCommand("roundrestart", {
	perm = "roundrestart",
	help = "Startet die aktuelle Runde neu",
	run = function(caller)
		A.Broadcast(caller, "startet die Runde neu")
		admin.RoundRestart() -- TTT2: lua/ttt2/libraries/admin.lua
	end,
})

A.AddCommand("credits", {
	perm = "credits",
	help = "Gibt einem Spieler Shop-Credits",
	args = {
		{ type = "player", name = "spieler", ignoreImmunity = true },
		{ type = "number", name = "anzahl", min = -10, max = 10 },
	},
	run = function(caller, target, amount)
		target:AddCredits(amount)
		LMNT.Reply(caller, col.good, target:Nick() .. " hat " .. amount .. " Credit(s) erhalten.")
		LMNT.Log.Info("admin", LMNT.Name(caller) .. " gab " .. target:Nick() .. " " .. amount .. " Credits")
	end,
})

A.AddCommand("karma", {
	perm = "karma",
	help = "Setzt das Karma eines Spielers",
	args = {
		{ type = "player", name = "spieler" },
		{ type = "number", name = "karma", min = 1, max = 1500 },
	},
	run = function(caller, target, value)
		target:SetBaseKarma(value)
		target:SetLiveKarma(value)
		A.Broadcast(caller, "hat das Karma von", target, " auf " .. value .. " gesetzt")
	end,
})
