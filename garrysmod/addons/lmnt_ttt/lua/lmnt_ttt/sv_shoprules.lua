--[[
	LMNT TTT – Shop-Regeln (T-035) · Modul "ttt.shop" · Doku: docs/framework/api/weapons.md

	Die Kaufabwicklung (Credits prüfen und abbuchen, Ausgabe, limited/teamLimited/globalLimited,
	minPlayers) macht TTT2 selbst (gamemode/shared/sh_shop.lua: shop.CanBuyEquipment/BuyEquipment).
	LMNT ergänzt nur Regeln über den offiziellen Hook TTT2CanOrderEquipment (sh_shop.lua:261):

	  1. gesperrt per Einstellung        shop.<klasse>.enabled
	  2. für diese Map gesperrt          ttt.shop.blocked (Komma-Liste; per Map-Profil überschreibbar)
	  3. Sperrzeit ab Rundenbeginn       shop.<klasse>.lock_seconds
	  4. max. N Käufe pro Spieler/Runde  shop.<klasse>.max_per_round (gezählt werden nur echte Käufe)
	  + eigene Regeln: LMNT.Shop.AddRule(id, function(ctx) return erlaubt, grund end, priorität)

	Ist ein Kauf erlaubt, gibt der Hook NICHTS zurück. So laufen die TTT2CanOrderEquipment-Hooks
	anderer Addons weiter (hook.Run stoppt beim ersten Rückgabewert). Gesperrt: return false.
	Gezählt wird über lmnt.shop.purchase (TTT2OrderedEquipment, also nur tatsächlich ausgeführte Käufe),
	zurückgesetzt bei lmnt.round.prepare.
]]

LMNT.Shop = LMNT.Shop or {}
local Shop = LMNT.Shop

Shop._rules = {}
Shop._bought = {}          -- [steamid64][klasse] = Anzahl in dieser Runde
Shop._roundStart = nil     -- CurTime() bei Rundenbeginn
Shop._log = {}             -- letzte Käufe dieser Map (für !shopstats), begrenzt

local MAX_LOG = 200

LMNT.Settings.Define("ttt.shop.blocked", {
	type = "string", default = "", maxLength = 1024, category = "Shop", applies = "live",
	desc = "Für alle gesperrte Klassen (Komma-getrennt, z. B. weapon_ttt_c4). Map-Profile können das pro Map setzen.",
})

function Shop.AddRule(id, fn, priority)
	assert(isstring(id) and isfunction(fn), "Shop.AddRule: id und Funktion nötig")
	for i = #Shop._rules, 1, -1 do
		if Shop._rules[i].id == id then table.remove(Shop._rules, i) end
	end
	Shop._rules[#Shop._rules + 1] = { id = id, fn = fn, priority = priority or 0 }
	table.sort(Shop._rules, function(a, b) return a.priority > b.priority end)
	LMNT.Modules.TrackUndo(function()
		for i = #Shop._rules, 1, -1 do
			if Shop._rules[i].id == id and Shop._rules[i].fn == fn then table.remove(Shop._rules, i) end
		end
	end)
end

local function blockedList()
	local set = {}
	for entry in string.gmatch(LMNT.Settings.Get("ttt.shop.blocked"), "[^,%s]+") do set[entry] = true end
	return set
end

--[[
	Reine Regelprüfung (testbar ohne Spieler):
	ctx = { class, isItem, registered, enabled, lockSeconds, maxPerRound, boughtThisRound, roundElapsed, blocked = set, ply }
	-> true | false, grund
]]
function Shop.Evaluate(ctx)
	if ctx.blocked and ctx.blocked[ctx.class] then
		return false, "auf dieser Map bzw. auf dem Server gesperrt"
	end

	if ctx.registered then
		if ctx.enabled == false then return false, "derzeit deaktiviert" end

		if (ctx.lockSeconds or 0) > 0 then
			if ctx.roundElapsed == nil then return false, "nur während einer laufenden Runde kaufbar" end
			if ctx.roundElapsed < ctx.lockSeconds then
				return false, "erst " .. math.ceil(ctx.lockSeconds - ctx.roundElapsed) .. " s später kaufbar"
			end
		end

		if (ctx.maxPerRound or 0) > 0 and (ctx.boughtThisRound or 0) >= ctx.maxPerRound then
			return false, "pro Runde höchstens " .. ctx.maxPerRound .. "x kaufbar"
		end
	end

	for _, rule in ipairs(Shop._rules) do
		local ok, allow, reason = pcall(rule.fn, ctx)
		if not ok then
			LMNT.Log.Error("shop", "Shop-Regel '" .. rule.id .. "' fehlgeschlagen: " .. tostring(allow) .. " – Kauf wird zur Sicherheit verweigert")
			return false, "interner Regelfehler"
		end
		if allow == false then return false, reason or ("Regel " .. rule.id) end
	end

	return true
end

function Shop.BuildContext(ply, class, isItem)
	local meta = LMNT.Weapons._registry[class]
	local sid = ply:SteamID64()
	local ctx = {
		ply = ply, class = class, isItem = isItem, registered = meta ~= nil,
		blocked = blockedList(),
		boughtThisRound = Shop._bought[sid] and Shop._bought[sid][class] or 0,
		roundElapsed = Shop._roundStart and (CurTime() - Shop._roundStart) or nil,
	}
	if meta then
		ctx.enabled = LMNT.Settings.Get("shop." .. class .. ".enabled")
		ctx.lockSeconds = LMNT.Settings.Get("shop." .. class .. ".lock_seconds")
		ctx.maxPerRound = LMNT.Settings.Get("shop." .. class .. ".max_per_round")
	end
	return ctx
end

-- Offizieller TTT2-Eingriffspunkt (sh_shop.lua:261). Nur bei Sperre einen Wert zurückgeben.
hook.Add("TTT2CanOrderEquipment", "LMNT.Shop.Rules", function(ply, class, isItem)
	if not IsValid(ply) then return end
	local allow, reason = Shop.Evaluate(Shop.BuildContext(ply, class, isItem))
	if allow then return end

	local name = LMNT.Weapons.Get(class).displayName
	LMNT.Notify(ply, LMNT.Config.Colors.bad, "Kauf nicht möglich: ", color_white, name .. " – " .. reason)
	LMNT.Log.Info("shop", ply:Nick() .. " (" .. ply:SteamID64() .. ") Kauf von " .. class .. " verweigert: " .. reason)
	return false
end)

LMNT.Events.On("lmnt.shop.purchase", "LMNT.Shop.Count", function(ply, class, isItem, credits)
	if not IsValid(ply) then return end
	local sid = ply:SteamID64()
	Shop._bought[sid] = Shop._bought[sid] or {}
	Shop._bought[sid][class] = (Shop._bought[sid][class] or 0) + 1

	table.insert(Shop._log, 1, { time = os.time(), class = class, name = ply:Nick(), credits = credits or 0 })
	if #Shop._log > MAX_LOG then table.remove(Shop._log) end
	LMNT.Log.Info("shop", ply:Nick() .. " (" .. sid .. ") kaufte " .. class .. " für " .. tostring(credits) .. " Credit(s)")
end)

LMNT.Events.On("lmnt.round.prepare", "LMNT.Shop.Reset", function()
	Shop._bought = {}
	Shop._roundStart = nil
end)

LMNT.Events.On("lmnt.round.begin", "LMNT.Shop.RoundStart", function()
	Shop._roundStart = CurTime()
end)

LMNT.Admin.AddCommand("shopstats", {
	perm = "config", log = false,
	help = "Käufe auf dieser Map (Anzahl je Klasse, letzte Käufe)",
	run = function(caller)
		local col = LMNT.Config.Colors
		local counts = {}
		for _, e in ipairs(Shop._log) do counts[e.class] = (counts[e.class] or 0) + 1 end
		local list = {}
		for class, n in pairs(counts) do list[#list + 1] = { class = class, n = n } end
		table.SortByMember(list, "n")
		LMNT.Reply(caller, col.primary, #Shop._log .. " Käufe auf dieser Map (max. " .. MAX_LOG .. " gespeichert)")
		for _, e in ipairs(list) do LMNT.Reply(caller, color_white, e.class, col.muted, "  " .. e.n .. "x") end
	end,
})
