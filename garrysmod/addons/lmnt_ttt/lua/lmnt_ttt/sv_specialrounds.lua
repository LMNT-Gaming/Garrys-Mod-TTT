--[[
	LMNT TTT – Spezialrunden (Auswahl, Start, Ende)
	Admins können mit "!special <id>" die nächste Runde festlegen.
]]

util.AddNetworkString("lmnt_special")

local roundsSinceSpecial = 99
local forcedNext
local active

function LMNT.TTT.ForceSpecial(id)
	forcedNext = id
end

local function pickSpecial()
	if forcedNext then
		local id = forcedNext
		forcedNext = nil
		return LMNT.TTT.Specials[id]
	end

	local Get = LMNT.Settings.Get
	if player.GetCount() < Get("ttt.special.min_players") then return nil end
	if roundsSinceSpecial < Get("ttt.special.min_gap") then return nil end
	if math.random() > Get("ttt.special.chance") then return nil end

	local total = 0
	for _, s in pairs(LMNT.TTT.Specials) do total = total + s.weight end

	local roll = math.random() * total
	for _, s in pairs(LMNT.TTT.Specials) do
		roll = roll - s.weight
		if roll <= 0 then return s end
	end
end

local function stopActive()
	if not active then return end

	if active.stop then
		local ok, err = pcall(active.stop)
		if not ok then ErrorNoHalt("[LMNT] Spezialrunde " .. active.id .. " stop: " .. tostring(err) .. "\n") end
	end

	active = nil
	SetGlobalString("lmnt_special", "")
end

hook.Add("TTTBeginRound", "LMNT.Special.Begin", function()
	stopActive()

	local special = pickSpecial()
	if not special then
		roundsSinceSpecial = roundsSinceSpecial + 1
		return
	end

	roundsSinceSpecial = 0
	active = special
	SetGlobalString("lmnt_special", special.id)

	if special.start then
		local ok, err = pcall(special.start)
		if not ok then ErrorNoHalt("[LMNT] Spezialrunde " .. special.id .. " start: " .. tostring(err) .. "\n") end
	end

	net.Start("lmnt_special")
	net.WriteString(special.id)
	net.Broadcast()

	LMNT.Log("round", "Spezialrunde gestartet: " .. special.name)
end)

-- Wird beim Deaktivieren des Moduls aufgerufen (shutdown), damit z. B. die Schwerkraft zurückgesetzt wird
LMNT.TTT.StopSpecial = stopActive

hook.Add("TTTEndRound", "LMNT.Special.End", stopActive)
hook.Add("TTTPrepareRound", "LMNT.Special.Prepare", stopActive)
hook.Add("ShutDown", "LMNT.Special.Shutdown", stopActive)
