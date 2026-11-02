--[[
	LMNT TTT – Weapon Registry (T-112) · Modul "ttt.shop" · Doku: docs/framework/api/weapons.md

	Metadaten zu Waffen und Items – GETRENNT von der eigentlichen Implementierung (SWEP/ITEM).
	Schaden, Munition und Schussverhalten bleiben bei der Waffe. LMNT verändert fremde SWEPs nicht.

	LMNT.Weapons.Register(class, {
		displayName = "Taser", description = "...",
		category = "Gerät",              -- Pistole | Gewehr | Präzision | Schrot | Nahkampf | Granate | Gerät | Passiv | Sonstiges
		kind = "weapon",                 -- weapon | item
		sourceAddon = "lmnt_ttt",
		balanceProfile = "standard",     -- frei wählbares Etikett für Balance-Übersichten
		shop = {                         -- LMNT-Kaufregeln (Standardwerte, ingame als Einstellung änderbar)
			maxPerRound = 1,             -- pro Spieler und Runde, 0 = unbegrenzt
			lockSeconds = 0,             -- Sperrzeit ab Rundenbeginn
		},
		notes = { "..." },
	})
	LMNT.Weapons.Get(class)            -> zusammengeführte Sicht (Metadaten + Live-Werte aus TTT2, nur lesend)
	LMNT.Weapons.List(filter)          -> Liste (filter: Teilstring in Klasse/Name/Kategorie)
	LMNT.Weapons.Discover()            -> erkennt alle geladenen TTT-Waffen und -Items, prüft Kompatibilität

	Pro registrierter Klasse entstehen die Einstellungen
	  shop.<class>.enabled · shop.<class>.max_per_round · shop.<class>.lock_seconds
	(Durchsetzung: sv_shoprules.lua über den offiziellen Hook TTT2CanOrderEquipment)
]]

LMNT.Weapons = LMNT.Weapons or {}
local W = LMNT.Weapons

W._registry = W._registry or {}
W._discovered = {}

local CATEGORIES = {
	["Pistole"] = true, ["Gewehr"] = true, ["Präzision"] = true, ["Schrot"] = true, ["Nahkampf"] = true,
	["Granate"] = true, ["Gerät"] = true, ["Passiv"] = true, ["Sonstiges"] = true,
}
W.Categories = CATEGORIES

local function settingKey(class, name)
	return "shop." .. class .. "." .. name
end

function W.Register(class, meta)
	assert(isstring(class) and string.match(class, "^[%w_]+$"), "Weapons.Register: ungültige Klasse " .. tostring(class))
	assert(istable(meta), "Weapons.Register: Metadaten fehlen (" .. class .. ")")

	local existing = W._registry[class]
	if existing and existing.sourceAddon ~= (meta.sourceAddon or "unbekannt") then
		-- Zwei Quellen beanspruchen dieselbe Klasse: nicht still überschreiben
		local msg = "Klasse " .. class .. " ist bereits von " .. tostring(existing.sourceAddon) .. " registriert – Registrierung von " .. tostring(meta.sourceAddon) .. " abgelehnt"
		if SERVER then LMNT.Log.Warn("weapons", msg) else MsgC(Color(255, 176, 32), "[LMNT] " .. msg .. "\n") end
		return nil, msg
	end

	local shop = meta.shop or {}
	local entry = {
		class = class,
		displayName = meta.displayName or class,
		description = meta.description or "",
		category = CATEGORIES[meta.category] and meta.category or "Sonstiges",
		kind = meta.kind == "item" and "item" or "weapon",
		sourceAddon = meta.sourceAddon or "unbekannt",
		balanceProfile = meta.balanceProfile or "standard",
		notes = meta.notes or {},
		shopDefaults = {
			maxPerRound = math.Clamp(math.floor(tonumber(shop.maxPerRound) or 0), 0, 10),
			lockSeconds = math.Clamp(math.floor(tonumber(shop.lockSeconds) or 0), 0, 600),
		},
	}
	W._registry[class] = entry

	local category = "Shop: " .. entry.displayName
	LMNT.Settings.Define(settingKey(class, "enabled"), {
		type = "bool", default = true, category = category, applies = "live", replicate = true,
		desc = entry.displayName .. " im Shop kaufbar (LMNT-Regel zusätzlich zu den TTT2-Shop-Einstellungen)",
	})
	LMNT.Settings.Define(settingKey(class, "max_per_round"), {
		type = "int", default = entry.shopDefaults.maxPerRound, min = 0, max = 10, category = category, applies = "live",
		desc = "Höchstens so oft pro Spieler und Runde kaufbar (0 = unbegrenzt)",
	})
	LMNT.Settings.Define(settingKey(class, "lock_seconds"), {
		type = "int", default = entry.shopDefaults.lockSeconds, min = 0, max = 600, category = category, applies = "live",
		desc = "Erst so viele Sekunden nach Rundenbeginn kaufbar",
	})

	-- Wird die Registrierung beim Laden eines Moduls gemacht, verschwindet sie beim Deaktivieren
	LMNT.Modules.TrackUndo(function()
		if W._registry[class] == entry then W._registry[class] = nil end
	end)

	return entry
end

------------------------------------------------------------------------
-- Erkennung und Kompatibilitätsprüfung
------------------------------------------------------------------------

-- Liest TTT2-Werte nur lesend (weapons.GetStored / items.GetStored liefern die Originaltabelle)
local function liveEquipment(class)
	local isItem = istable(items) and isfunction(items.IsItem) and items.IsItem(class)
	local stored = isItem and items.GetStored(class) or weapons.GetStored(class)
	return stored, isItem
end

local function buyRoles(stored)
	local seen, out = {}, {}
	if not istable(stored) or not istable(stored.CanBuy) then return out end
	-- TTT2 nutzt CanBuy als Liste { ROLE_X } (Definition) bzw. als Menge [subrole] = … (sh_shop.lua: CanBuy[subrole])
	for k, v in pairs(stored.CanBuy) do
		local index = isnumber(v) and v or (isnumber(k) and v and k) or nil
		local role = index and roles and roles.GetByIndex and roles.GetByIndex(index)
		if role and role.name and role.name ~= "none" and not seen[role.name] then
			seen[role.name] = true
			out[#out + 1] = role.name
		end
	end
	table.sort(out)
	return out
end

-- Prüft eine Klasse; Rückgabe: status ("ttt2" | "unvollständig" | "nicht TTT-tauglich" | "nicht geladen"), Prüfliste
function W.Check(class)
	local stored, isItem = liveEquipment(class)
	local checks = {}
	local function add(name, ok, severity) checks[#checks + 1] = { name = name, ok = ok and true or false, severity = severity } end

	if not istable(stored) then
		add("Klasse geladen", false, "fatal")
		return "nicht geladen", checks
	end
	add("Klasse geladen", true)

	if isItem then
		add("TTT2-Item (items.GetStored)", true)
		return "ttt2", checks
	end

	local basedOnTTT = class == "weapon_tttbase" or weapons.IsBasedOn(class, "weapon_tttbase")
	add("Basis weapon_tttbase", basedOnTTT, "fatal")
	add("Waffenart (SWEP.Kind) gesetzt", isnumber(stored.Kind), "fatal")

	local model = stored.WorldModel
	local hasModel = isstring(model) and model ~= "" and file.Exists(model, "GAME")
	add("Weltmodell vorhanden (" .. tostring(model) .. ")", hasModel, "warn")

	if CLIENT then
		local icon = stored.Icon
		local hasIcon = isstring(icon) and (file.Exists("materials/" .. icon .. ".vmt", "GAME") or file.Exists("materials/" .. icon, "GAME"))
		add("Shop-Icon vorhanden (" .. tostring(icon) .. ")", hasIcon, "warn")
	else
		add("Shop-Icon (nur auf dem Client prüfbar, da SWEP.Icon meist clientseitig definiert ist)", true, "info")
	end

	for _, c in ipairs(checks) do
		if not c.ok and c.severity == "fatal" then return "nicht TTT-tauglich", checks end
	end
	for _, c in ipairs(checks) do
		if not c.ok and c.severity == "warn" then return "unvollständig", checks end
	end
	return "ttt2", checks
end

function W.Discover()
	W._discovered = {}

	for _, swep in ipairs(weapons.GetList()) do
		local class = swep.ClassName
		local stored = class and weapons.GetStored(class)
		-- Nur TTT-relevante Waffen: kaufbar oder auf dem Boden spawnbar
		if stored and (istable(stored.CanBuy) and not table.IsEmpty(stored.CanBuy) or stored.AutoSpawnable) then
			W._discovered[class] = true
		end
	end

	if istable(items) and isfunction(items.GetList) then
		for _, item in ipairs(items.GetList()) do
			if item.id and istable(item.CanBuy) and not table.IsEmpty(item.CanBuy) then W._discovered[item.id] = true end
		end
	end

	for class in pairs(W._registry) do W._discovered[class] = true end
	return table.Count(W._discovered)
end

function W.Get(class)
	local stored, isItem = liveEquipment(class)
	local meta = W._registry[class]
	local status, checks = W.Check(class)

	local view = {
		class = class,
		registered = meta ~= nil,
		displayName = meta and meta.displayName or (stored and (stored.PrintName or (stored.EquipMenuData and stored.EquipMenuData.name))) or class,
		category = meta and meta.category or "Sonstiges",
		kind = meta and meta.kind or (isItem and "item" or "weapon"),
		sourceAddon = meta and meta.sourceAddon or "erkannt (nicht registriert)",
		balanceProfile = meta and meta.balanceProfile or "–",
		description = meta and meta.description or "",
		notes = meta and meta.notes or {},
		compatibilityStatus = status,
		checks = checks,
		-- Live-Werte aus TTT2 (nur Anzeige; ändern über den TTT2-Shop-Editor)
		ttt2 = stored and {
			credits = stored.credits or 1,
			limited = stored.limited == true or stored.LimitedStock == true,
			teamLimited = stored.teamLimited == true,
			globalLimited = stored.globalLimited == true,
			minPlayers = stored.minPlayers,
			autoSpawn = stored.AutoSpawnable == true,
			roles = buyRoles(stored),
		} or nil,
	}

	if meta then
		view.shop = {
			enabled = LMNT.Settings.Get(settingKey(class, "enabled")),
			maxPerRound = LMNT.Settings.Get(settingKey(class, "max_per_round")),
			lockSeconds = LMNT.Settings.Get(settingKey(class, "lock_seconds")),
		}
	end
	return view
end

function W.List(filter)
	if table.IsEmpty(W._discovered) then W.Discover() end
	local out = {}
	filter = filter and string.lower(filter) or nil

	for class in pairs(W._discovered) do
		local v = W.Get(class)
		if not filter or string.find(string.lower(class .. " " .. v.displayName .. " " .. v.category), filter, 1, true) then
			out[#out + 1] = v
		end
	end
	table.SortByMember(out, "class", true)
	return out
end

-- Erkennung, nachdem TTT2 Waffen und Items geladen hat
hook.Add("InitPostEntity", "LMNT.Weapons.Discover", function()
	local n = W.Discover()
	if SERVER then LMNT.Log.Info("weapons", n .. " TTT-Waffen/Items erkannt, " .. table.Count(W._registry) .. " mit LMNT-Metadaten") end
end)

------------------------------------------------------------------------
-- Befehle
------------------------------------------------------------------------

local col = LMNT.Config.Colors
local statusColors = { ttt2 = col.good, ["unvollständig"] = col.warn, ["nicht TTT-tauglich"] = col.bad, ["nicht geladen"] = col.bad }

LMNT.Admin.AddCommand("weapons", {
	perm = "config", log = false,
	help = "Liste aller erkannten Waffen/Items mit Kompatibilitätsstatus: !weapons [filter]",
	args = { { type = "string", name = "filter", optional = true, rest = true } },
	run = function(caller, filter)
		local list = W.List(filter)
		for _, v in ipairs(list) do
			LMNT.Reply(caller, statusColors[v.compatibilityStatus] or color_white, string.format("%-20s", v.compatibilityStatus), color_white,
				" " .. v.class .. " ", col.muted, v.displayName .. " · " .. v.category .. (v.registered and " · LMNT" or "") ..
				(v.ttt2 and (" · " .. v.ttt2.credits .. " Cr" .. (#v.ttt2.roles > 0 and (" · " .. table.concat(v.ttt2.roles, "/")) or "")) or ""))
		end
		LMNT.Reply(caller, col.primary, #list .. " Einträge")
	end,
})

LMNT.Admin.AddCommand("weapon", {
	perm = "config", log = false,
	help = "Details zu einer Waffe/einem Item: !weapon <klasse>",
	args = { { type = "string", name = "klasse" } },
	run = function(caller, class)
		local v = W.Get(class)
		LMNT.Reply(caller, col.primary, v.displayName .. " (" .. class .. ")", col.muted, "  " .. v.kind .. " · " .. v.category .. " · Quelle: " .. v.sourceAddon)
		LMNT.Reply(caller, statusColors[v.compatibilityStatus] or color_white, "Kompatibilität: " .. v.compatibilityStatus)
		for _, c in ipairs(v.checks) do
			LMNT.Reply(caller, c.ok and col.good or (c.severity == "fatal" and col.bad or col.warn), "  " .. (c.ok and "OK " or "FEHLT ") .. c.name)
		end
		if v.ttt2 then
			LMNT.Reply(caller, color_white, "TTT2: " .. v.ttt2.credits .. " Credit(s)" .. (v.ttt2.limited and " · einmal pro Runde" or "") ..
				(v.ttt2.teamLimited and " · einmal pro Team" or "") .. (v.ttt2.globalLimited and " · einmal pro Runde für alle" or "") ..
				(v.ttt2.autoSpawn and " · Boden-Spawn" or "") .. " · Rollen: " .. (#v.ttt2.roles > 0 and table.concat(v.ttt2.roles, ", ") or "–"))
		end
		if v.shop then
			LMNT.Reply(caller, color_white, "LMNT-Regeln: " .. (v.shop.enabled and "kaufbar" or "GESPERRT") ..
				" · max. " .. (v.shop.maxPerRound == 0 and "unbegrenzt" or (v.shop.maxPerRound .. "x")) .. " pro Runde" ..
				(v.shop.lockSeconds > 0 and (" · ab " .. v.shop.lockSeconds .. " s nach Rundenbeginn") or ""))
		end
		if v.description ~= "" then LMNT.Reply(caller, col.muted, v.description) end
		for _, n in ipairs(v.notes) do LMNT.Reply(caller, col.muted, "  Hinweis: " .. n) end
	end,
})
