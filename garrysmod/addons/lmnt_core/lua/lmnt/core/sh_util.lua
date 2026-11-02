--[[
	LMNT Framework – Hilfsfunktionen (Zeit, Spielersuche, Namen)
]]

-- "Konsole" für den Server, sonst der Spielername
function LMNT.Name(ply)
	if not IsValid(ply) then return "Konsole" end
	return ply:Nick()
end

-- Minuten -> "2T 3Std 15Min" (0 = permanent)
function LMNT.FormatMinutes(minutes)
	minutes = math.floor(tonumber(minutes) or 0)
	if minutes <= 0 then return "permanent" end

	local d = math.floor(minutes / 1440)
	local h = math.floor((minutes % 1440) / 60)
	local m = minutes % 60
	local out = {}

	if d > 0 then out[#out + 1] = d .. "T" end
	if h > 0 then out[#out + 1] = h .. "Std" end
	if m > 0 then out[#out + 1] = m .. "Min" end

	return table.concat(out, " ")
end

-- "1d2h30m", "90", "perm" -> Minuten (0 = permanent), nil bei Fehler
function LMNT.ParseTime(str)
	if not str then return nil end
	str = string.lower(str)

	if str == "0" or str == "perm" or str == "permanent" then return 0 end
	if tonumber(str) then return math.max(0, math.floor(tonumber(str))) end

	local units = { w = 10080, d = 1440, t = 1440, h = 60, m = 1 }
	local total, matched = 0, false

	for num, unit in string.gmatch(str, "(%d+)(%a)") do
		local mult = units[unit]
		if not mult then return nil end
		total = total + tonumber(num) * mult
		matched = true
	end

	return matched and total or nil
end

-- Normalisiert STEAM_0:1:123 bzw. SteamID64 -> SteamID64 (oder nil)
function LMNT.ToSteamID64(str)
	if not str then return nil end
	if string.match(str, "^STEAM_%d:%d:%d+$") then return util.SteamIDTo64(str) end
	if string.match(str, "^7656%d+$") then return str end
	return nil
end

--[[
	Spielersuche für Befehle:
	  ^        du selbst
	  *        alle
	  @        Spieler, den du ansiehst
	  #<id>    UserID (vom Admin-Menü verwendet)
	  STEAM_.. / 7656..  SteamID
	  sonst    Teil des Namens (Groß/Klein egal)
]]
function LMNT.FindPlayers(caller, str)
	if not str or str == "" then return {} end

	if str == "^" then return IsValid(caller) and { caller } or {} end
	if str == "*" then return player.GetAll() end

	if str == "@" then
		if IsValid(caller) then
			local ent = caller:GetEyeTrace().Entity
			if IsValid(ent) and ent:IsPlayer() then return { ent } end
		end
		return {}
	end

	if string.sub(str, 1, 1) == "#" then
		local ply = Player(tonumber(string.sub(str, 2)) or -1)
		return IsValid(ply) and { ply } or {}
	end

	local sid64 = LMNT.ToSteamID64(str)
	if sid64 then
		local ply = player.GetBySteamID64(sid64)
		return IsValid(ply) and { ply } or {}
	end

	local needle = string.lower(str)
	local found = {}

	for _, ply in ipairs(player.GetAll()) do
		local nick = string.lower(ply:Nick())
		if nick == needle then return { ply } end
		if string.find(nick, needle, 1, true) then found[#found + 1] = ply end
	end

	return found
end
