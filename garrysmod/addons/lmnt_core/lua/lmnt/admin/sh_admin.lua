--[[
	LMNT Admin – Befehlsregister (Server + Client)

	Befehle werden geteilt registriert, damit das Admin-Menü sie kennt.
	"run" wird nur auf dem Server ausgeführt.

	LMNT.Admin.AddCommand("kick", {
		perm = "kick",                         -- nil = für alle
		help = "Kickt einen Spieler",
		aliases = { "rauswerfen" },
		args = {
			{ type = "player", name = "spieler" },
			{ type = "string", name = "grund", optional = true, rest = true, default = "Kein Grund" },
		},
		run = function(caller, target, reason) ... end,
	})

	Argumenttypen: player, players, steamid, number, string, time, rank, map
]]

LMNT.Admin = LMNT.Admin or {}
LMNT.Admin.Commands = LMNT.Admin.Commands or {}
LMNT.Admin.Aliases = LMNT.Admin.Aliases or {}

function LMNT.Admin.AddCommand(name, data)
	name = string.lower(name)
	data.name = name
	data.args = data.args or {}
	LMNT.Admin.Commands[name] = data

	for _, alias in ipairs(data.aliases or {}) do
		LMNT.Admin.Aliases[string.lower(alias)] = name
	end

	-- Wird der Befehl beim Laden eines Moduls registriert, verschwindet er beim Deaktivieren wieder
	if LMNT.Modules and LMNT.Modules.TrackUndo then
		LMNT.Modules.TrackUndo(function() LMNT.Admin.RemoveCommand(name) end)
	end
end

function LMNT.Admin.RemoveCommand(name)
	name = string.lower(name)
	if not LMNT.Admin.Commands[name] then return false end
	LMNT.Admin.Commands[name] = nil
	for alias, target in pairs(LMNT.Admin.Aliases) do
		if target == name then LMNT.Admin.Aliases[alias] = nil end
	end
	return true
end

function LMNT.Admin.GetCommand(name)
	name = string.lower(name or "")
	return LMNT.Admin.Commands[name] or LMNT.Admin.Commands[LMNT.Admin.Aliases[name] or ""]
end

function LMNT.Admin.Usage(cmd)
	local parts = { "!" .. cmd.name }

	for _, spec in ipairs(cmd.args) do
		local label = spec.name or spec.type
		parts[#parts + 1] = spec.optional and ("[" .. label .. "]") or ("<" .. label .. ">")
	end

	return table.concat(parts, " ")
end

-- Zerlegt 'ban "Max Mustermann" 1d Grund' in Tokens (Anführungszeichen gruppieren)
function LMNT.Admin.Tokenize(str)
	local out = {}
	local i, len = 1, #str

	while i <= len do
		local c = string.sub(str, i, i)

		if string.match(c, "%s") then
			i = i + 1
		elseif c == '"' then
			local j = string.find(str, '"', i + 1, true) or (len + 1)
			out[#out + 1] = string.sub(str, i + 1, j - 1)
			i = j + 1
		else
			local j = string.find(str, "%s", i) or (len + 1)
			out[#out + 1] = string.sub(str, i, j - 1)
			i = j
		end
	end

	return out
end
