--[[
	LMNT TTT – Pointshop (Server)
	Kauf, Verkauf, Ausrüsten; Modelle/Spuren/Hüte/Chat-Titel anwenden, Todeseffekte abspielen.
	Öffnen: F4, !shop oder Konsole "lmnt_shop"

	Grundsätze:
	- Preise, Rabatte, Erstattungen und Besitz entscheidet nur der Server (Client zeigt nur an)
	- Kauf/Verkauf: Punkte und Inventar in EINER Transaktion, bei Fehler Rollback, keine Punkte ohne Gegenleistung
	- Pro Spieler läuft höchstens eine Shop-Aktion gleichzeitig (In-Flight-Sperre)
	- Die Datenbankfunktionen arbeiten mit der SteamID64 statt mit dem Spielerobjekt (testbar)
]]

util.AddNetworkString("lmnt_ps_open")
util.AddNetworkString("lmnt_ps_sync")
util.AddNetworkString("lmnt_ps_action")
util.AddNetworkString("lmnt_ps_deathfx")

LMNT.DB.Query([[CREATE TABLE IF NOT EXISTS lmnt_ps_inventory (
	steamid TEXT NOT NULL,
	item TEXT NOT NULL,
	equipped INTEGER DEFAULT 0,
	PRIMARY KEY (steamid, item)
)]])
-- Seit Pointshop 2.0: tatsächlich bezahlter Preis (Grundlage der Verkaufserstattung). Altbestand = NULL
LMNT.DB.EnsureColumn("lmnt_ps_inventory", "paid", "INTEGER")

local Shop = LMNT.TTT.Shop
local PS = LMNT.TTT.Pointshop
local col = LMNT.Config.Colors

local function isVip(ply)
	return LMNT.RankHasPerm(ply:GetUserGroup(), "vip")
end

-- VIP-Items wirken nur, solange der Spieler das Recht noch hat
local function usable(ply, item)
	return item ~= nil and (not item.vip or isVip(ply))
end

local function equippedIn(ply, category)
	for id, on in pairs(ply.LMNTInventory or {}) do
		if on and Shop[id] and Shop[id].category == category then return id end
	end
end

local function equippedUsable(ply, category)
	local id = equippedIn(ply, category)
	if id and usable(ply, Shop[id]) then return id end
end

-- Punktestand im Speicher setzen, nachdem die Datenbank ihn per Transaktion geschrieben hat.
-- Bewusst nicht über LMNT.TTT.AddPoints: das multipliziert Gutschriften mit dem VIP-Faktor
-- (Verkauf würde sonst mehr erstatten, als bezahlt wurde).
local function setPoints(ply, value)
	local s = ply.LMNTStats
	if not s then return end
	s.points = value
	ply:SetNWInt("lmnt_points", value)
end

------------------------------------------------------------------------
-- Tagesangebot (serverseitig, deterministisch)
------------------------------------------------------------------------

local dailyCache = {}

-- Rückgabe: Item-ID oder nil (Rabatt 0 = kein Angebot), Rabatt in Prozent, Tagesschlüssel
function PS.CurrentDaily()
	local discount = PS.ClampDiscount(LMNT.Settings.Get("ttt.pointshop.daily_discount"))
	local day = PS.DayKey()
	if discount <= 0 then return nil, 0, day end

	if dailyCache.day ~= day then
		dailyCache = { day = day, id = PS.PickDaily(day) }
	end
	return dailyCache.id, discount, day
end

-- Einziger Ort, an dem ein Kaufpreis entsteht
function PS.PriceFor(id)
	local item = Shop[id]
	if not item then return nil end
	local daily, discount = PS.CurrentDaily()
	return PS.ComputePrice(item, id == daily, discount)
end

------------------------------------------------------------------------
-- Datenbank-Schicht (nur SteamID64, keine Spielerobjekte)
------------------------------------------------------------------------

-- Abfrage, die bei SQL-Fehler wirft (innerhalb einer Transaktion -> Rollback)
local function strict(query, ...)
	local rows, err = LMNT.DB.QueryStrict(query, ...)
	if not rows then error("SQL-Fehler: " .. tostring(err), 0) end
	return rows
end

-- Anzahl der von der letzten erfolgreichen Anweisung geänderten Zeilen (SQLite changes())
local function changes()
	return tonumber(LMNT.DB.Value("SELECT changes()")) or 0
end

-- Testhaken: opts.failAfter = Schrittname -> künstlicher Fehler nach diesem Schritt (prüft den Rollback)
local function step(opts, name)
	if opts and opts.failAfter == name then error("Testfehler nach Schritt '" .. name .. "'", 0) end
end

local function guardTransaction()
	-- In einer fremden Transaktion kann LMNT.DB.Transaction nicht zurückrollen (siehe sv_db.lua)
	if LMNT.DB._inTransaction then return false, "Shop-Aktion innerhalb einer laufenden Transaktion nicht erlaubt" end
	return true
end

local function writePoints(sid, value)
	strict("UPDATE lmnt_ttt_stats SET points = ? WHERE steamid = ?", value, sid)
	if changes() ~= 1 then error("Punktestand für " .. sid .. " nicht gefunden", 0) end
end

-- Kauf: Punkte abziehen + Inventar schreiben. Rückgabe: true, neuerPunktestand | false, fehler
function PS.ExecuteBuy(sid, id, price, pointsBefore, opts)
	local ok, err = guardTransaction()
	if not ok then return false, err end
	if not isnumber(price) or price < 1 then return false, "ungültiger Preis" end
	if not isnumber(pointsBefore) or pointsBefore < price then return false, "zu wenig Punkte" end

	local newPoints = pointsBefore - price
	return LMNT.DB.Transaction(function()
		writePoints(sid, newPoints)
		step(opts, "points")
		-- Primärschlüssel (steamid, item) verhindert Doppelbesitz auch auf Datenbankebene
		strict("INSERT INTO lmnt_ps_inventory (steamid, item, equipped, paid) VALUES (?, ?, 0, ?)", sid, id, price)
		step(opts, "inventory")
		return newPoints
	end)
end

-- Verkauf: Inventar löschen + Punkte gutschreiben. Rückgabe: true, neuerPunktestand | false, fehler
function PS.ExecuteSell(sid, id, refund, pointsBefore, opts)
	local ok, err = guardTransaction()
	if not ok then return false, err end
	if not isnumber(refund) or refund < 0 then return false, "ungültige Erstattung" end
	if not isnumber(pointsBefore) or pointsBefore < 0 then return false, "ungültiger Punktestand" end

	local newPoints = pointsBefore + refund
	return LMNT.DB.Transaction(function()
		strict("DELETE FROM lmnt_ps_inventory WHERE steamid = ? AND item = ?", sid, id)
		if changes() ~= 1 then error("Item " .. id .. " nicht im Besitz", 0) end
		step(opts, "inventory")
		writePoints(sid, newPoints)
		step(opts, "points")
		return newPoints
	end)
end

-- Ausrüsten/Ablegen. previous = bisher ausgerüstetes Item derselben Kategorie (wird abgelegt)
function PS.ExecuteEquip(sid, id, on, previous)
	local ok, err = guardTransaction()
	if not ok then return false, err end

	return LMNT.DB.Transaction(function()
		if previous and previous ~= id then
			strict("UPDATE lmnt_ps_inventory SET equipped = 0 WHERE steamid = ? AND item = ?", sid, previous)
		end
		strict("UPDATE lmnt_ps_inventory SET equipped = ? WHERE steamid = ? AND item = ?", on and 1 or 0, sid, id)
		if changes() ~= 1 then error("Item " .. id .. " nicht im Besitz", 0) end
		return true
	end)
end

function PS.LoadInventoryRows(sid)
	return LMNT.DB.Query("SELECT item, equipped, paid FROM lmnt_ps_inventory WHERE steamid = ?", sid) or {}
end

------------------------------------------------------------------------
-- In-Flight-Sperre
------------------------------------------------------------------------

-- GMod führt Netzwerk-Handler nacheinander aus und SQLite ist synchron. Die Sperre schützt trotzdem
-- gegen Wiedereintritt (z. B. ein Hook, der während einer Aktion eine weitere auslöst) und macht den
-- Ablauf unabhängig von späteren Änderungen (z. B. asynchrone Datenbank).
local busy = {}

-- Rückgabe: true, ergebnis | false, "busy" | false, "error", meldung
function PS.WithLock(key, fn)
	if busy[key] then return false, "busy" end
	busy[key] = true
	local ok, result = xpcall(fn, debug.traceback)
	busy[key] = nil
	if not ok then
		LMNT.Log.Error("shop", "Shop-Aktion abgebrochen (" .. tostring(key) .. "): " .. tostring(result))
		return false, "error", result
	end
	return true, result
end

function PS.IsBusy(key)
	return busy[key] == true
end

------------------------------------------------------------------------
-- Synchronisation
------------------------------------------------------------------------

local function refundFor(ply, id)
	return PS.ComputeRefund(Shop[id], (ply.LMNTInventoryPaid or {})[id], LMNT.TTT.ShopSellFactor)
end

local function sync(ply)
	local inv = ply.LMNTInventory or {}

	net.Start("lmnt_ps_sync")
	net.WriteUInt(table.Count(inv), 10)
	for id, on in pairs(inv) do
		net.WriteString(id)
		net.WriteBool(on)
		net.WriteUInt(refundFor(ply, id), 32)
	end

	-- Tagesangebot: Preis kommt fertig berechnet vom Server
	local daily, discount, day = PS.CurrentDaily()
	net.WriteString(daily or "")
	net.WriteUInt(daily and PS.PriceFor(daily) or 0, 32)
	net.WriteUInt(discount, 7)
	net.WriteString(day)
	net.Send(ply)

	ply:SetNWString("lmnt_hat", equippedUsable(ply, "hat") or "")
	-- Nur die Item-ID wird repliziert, der Text kommt clientseitig aus dem Katalog (keine Freitexte)
	ply:SetNWString("lmnt_title", equippedUsable(ply, "title") or "")
end

------------------------------------------------------------------------
-- Anwenden
------------------------------------------------------------------------

local function applyModel(ply)
	local id = equippedUsable(ply, "model")
	if id and ply:Alive() and not ply:IsSpec() then
		ply:SetModel(Shop[id].model)
		ply:SetupHands()
	end
end

local function removeTrail(ply)
	if IsValid(ply.LMNTTrail) then ply.LMNTTrail:Remove() end
	ply.LMNTTrail = nil
end

local function applyTrail(ply)
	removeTrail(ply)

	local id = equippedUsable(ply, "trail")
	if not id or not ply:Alive() or ply:IsSpec() then return end

	local item = Shop[id]
	ply.LMNTTrail = util.SpriteTrail(ply, 0, item.color, false, 14, 1, 3, 1 / 15 * 0.5, item.material .. ".vmt")
end

hook.Add("PlayerSpawn", "LMNT.Shop.Apply", function(ply)
	timer.Simple(0.2, function()
		if not IsValid(ply) then return end
		applyModel(ply)
		applyTrail(ply)
	end)
end)

-- Todeseffekt: hängt nur am ausgerüsteten Item, nie an Rolle oder Team -> für alle Rollen identisch.
-- Engine-Effekte sind kurzlebig (Funken/Staub < 2 s), Konfetti begrenzt der Client auf höchstens 2,5 s.
local DEATHFX_COOLDOWN = 3

local function playDeathEffect(ply)
	local id = equippedUsable(ply, "deathfx")
	if not id then return end
	if (ply.LMNTNextDeathFx or 0) > CurTime() then return end
	ply.LMNTNextDeathFx = CurTime() + DEATHFX_COOLDOWN

	local fx = Shop[id].effect
	local pos = ply:WorldSpaceCenter()

	if fx.kind == "engine" then
		local data = EffectData()
		data:SetOrigin(pos)
		data:SetNormal(Vector(0, 0, 1))
		data:SetMagnitude(fx.magnitude or 1)
		data:SetScale(fx.scale or 1)
		data:SetRadius(fx.radius or 1)
		util.Effect(fx.name, data)
	elseif fx.kind == "confetti" then
		net.Start("lmnt_ps_deathfx")
		net.WriteString(id)
		net.WriteVector(pos)
		net.SendPVS(pos)
	end
end

hook.Add("PostPlayerDeath", "LMNT.Shop.Death", function(ply)
	removeTrail(ply)
	playDeathEffect(ply)
end)

------------------------------------------------------------------------
-- Laden
------------------------------------------------------------------------

function LMNT.TTT.LoadInventory(ply)
	ply.LMNTInventory = {}
	ply.LMNTInventoryPaid = {}

	for _, row in ipairs(PS.LoadInventoryRows(ply:SteamID64())) do
		if Shop[row.item] then
			ply.LMNTInventory[row.item] = tonumber(row.equipped) == 1
			ply.LMNTInventoryPaid[row.item] = tonumber(row.paid)
		end
	end

	timer.Simple(2, function() if IsValid(ply) then sync(ply) end end)
end

hook.Add("PlayerInitialSpawn", "LMNT.Shop.Load", LMNT.TTT.LoadInventory)

-- Beim Deaktivieren des Moduls Chat-Titel entfernen (Hut/Spur räumt der shutdown in lmnt_ttt_init.lua ab)
if LMNT.Modules and LMNT.Modules.TrackUndo then
	LMNT.Modules.TrackUndo(function()
		for _, ply in ipairs(player.GetAll()) do ply:SetNWString("lmnt_title", "") end
	end)
end

------------------------------------------------------------------------
-- Aktionen (laufen immer unter der Sperre des Spielers)
------------------------------------------------------------------------

local actions = {}

local function equip(ply, id, item)
	local inv = ply.LMNTInventory
	if inv[id] == nil then return false end
	if not usable(ply, item) then
		LMNT.Notify(ply, col.bad, "Dieses Item gibt es nur für VIPs.")
		return false
	end
	if inv[id] then return true end

	local previous = equippedIn(ply, item.category)
	local ok, err = PS.ExecuteEquip(ply:SteamID64(), id, true, previous)
	if not ok then
		LMNT.Log.Error("shop", "Ausrüsten fehlgeschlagen (" .. ply:SteamID64() .. ", " .. id .. "): " .. tostring(err))
		LMNT.Notify(ply, col.bad, "Ausrüsten fehlgeschlagen. Bitte später erneut versuchen.")
		return false
	end

	if previous then inv[previous] = false end
	inv[id] = true
	return true
end

function actions.buy(ply, id, item, expected)
	local sid = ply:SteamID64()
	if not ply.LMNTStats then
		LMNT.Notify(ply, col.bad, "Deine Punkte sind noch nicht geladen. Bitte kurz warten.")
		return false
	end

	local price = PS.PriceFor(id)
	local ok, code, msg = PS.CheckBuy({
		item = item,
		owned = ply.LMNTInventory[id] ~= nil,
		isVip = isVip(ply),
		points = LMNT.TTT.GetPoints(ply),
		price = price,
		-- 0 = kein Preis mitgeschickt (der Abgleich schützt nur den Spieler, nicht den Server)
		expected = (isnumber(expected) and expected > 0) and expected or nil,
	})
	if not ok then
		LMNT.Notify(ply, code == "owned" and col.muted or col.bad, msg)
		return false
	end

	local pointsBefore = LMNT.TTT.GetPoints(ply)
	local done, result = PS.ExecuteBuy(sid, id, price, pointsBefore)
	if not done then
		LMNT.Log.Error("shop", "Kauf zurückgerollt: " .. ply:Nick() .. " (" .. sid .. "), " .. id .. " für " .. price .. ": " .. tostring(result))
		LMNT.Notify(ply, col.bad, "Kauf fehlgeschlagen. Es wurden keine Punkte abgezogen.")
		return false
	end

	-- Erst nach dem Commit den Speicher anpassen
	setPoints(ply, result)
	ply.LMNTInventory[id] = false
	ply.LMNTInventoryPaid[id] = price

	LMNT.Notify(ply, col.good, "Gekauft: " .. item.name .. " (" .. price .. " Punkte)")
	LMNT.Log.Info("shop", ply:Nick() .. " (" .. sid .. ") hat " .. item.name .. " für " .. price .. " Punkte gekauft")

	equip(ply, id, item)
	return true
end

function actions.sell(ply, id, item)
	local sid = ply:SteamID64()
	local ok, _, msg = PS.CheckSell({ item = item, owned = ply.LMNTInventory[id] ~= nil })
	if not ok then
		LMNT.Notify(ply, col.bad, msg)
		return false
	end
	if not ply.LMNTStats then return false end

	local refund = refundFor(ply, id)
	local done, result = PS.ExecuteSell(sid, id, refund, LMNT.TTT.GetPoints(ply))
	if not done then
		LMNT.Log.Error("shop", "Verkauf zurückgerollt: " .. ply:Nick() .. " (" .. sid .. "), " .. id .. ": " .. tostring(result))
		LMNT.Notify(ply, col.bad, "Verkauf fehlgeschlagen. Das Item bleibt in deinem Besitz.")
		return false
	end

	setPoints(ply, result)
	ply.LMNTInventory[id] = nil
	ply.LMNTInventoryPaid[id] = nil

	LMNT.Notify(ply, col.warn, "Verkauft: " .. item.name .. " (+" .. refund .. " Punkte)")
	LMNT.Log.Info("shop", ply:Nick() .. " (" .. sid .. ") hat " .. item.name .. " für " .. refund .. " Punkte verkauft")
	return true
end

function actions.equip(ply, id, item)
	return equip(ply, id, item)
end

function actions.unequip(ply, id)
	if not ply.LMNTInventory[id] then return false end

	local ok, err = PS.ExecuteEquip(ply:SteamID64(), id, false)
	if not ok then
		LMNT.Log.Error("shop", "Ablegen fehlgeschlagen (" .. ply:SteamID64() .. ", " .. id .. "): " .. tostring(err))
		return false
	end
	ply.LMNTInventory[id] = false
	return true
end

-- Größtes gültiges Paket: Aktion (≤ 8 Zeichen) + ID (≤ 48 Zeichen) als String mit Nullbyte + 32-Bit-Preis
local MAX_ACTION_BITS = (8 + 1) * 8 + (PS.MaxIdLength + 1) * 8 + 32

net.Receive("lmnt_ps_action", function(len, ply)
	if len > MAX_ACTION_BITS then return end
	if (ply.LMNTNextShopAction or 0) > CurTime() then return end
	ply.LMNTNextShopAction = CurTime() + 0.25

	local action, id, expected = net.ReadString(), net.ReadString(), net.ReadUInt(32)
	local item = Shop[id]
	if not item or not actions[action] or not ply.LMNTInventory then return end

	local locked, result = PS.WithLock(ply:SteamID64(), function()
		return actions[action](ply, id, item, expected)
	end)
	if not locked then
		if result == "busy" then LMNT.Notify(ply, col.muted, "Deine letzte Shop-Aktion läuft noch.") end
		sync(ply)
		return
	end

	sync(ply)

	-- Modell/Spur nur außerhalb einer laufenden Runde sofort ändern (kein Identitäts-Leak)
	if GetRoundState() ~= ROUND_ACTIVE then
		applyModel(ply)
		applyTrail(ply)
	elseif result and (item.category == "model" or item.category == "trail") then
		LMNT.Notify(ply, col.muted, "Änderung wird ab dem nächsten Spawn sichtbar.")
	end
end)

------------------------------------------------------------------------
-- Tageswechsel / Rabattänderung: allen den neuen Stand schicken
------------------------------------------------------------------------

local lastDailyKey

timer.Create("LMNT.Shop.DailyWatch", 30, 0, function()
	local daily, discount, day = PS.CurrentDaily()
	local key = day .. "|" .. tostring(daily) .. "|" .. discount
	if key == lastDailyKey then return end

	local first = lastDailyKey == nil
	lastDailyKey = key
	if first then return end

	if daily then
		LMNT.Log.Info("shop", "Tagesangebot " .. day .. ": " .. Shop[daily].name .. " (-" .. discount .. " %)")
	end
	for _, ply in ipairs(player.GetAll()) do
		if ply.LMNTInventory then sync(ply) end
	end
end)

------------------------------------------------------------------------
-- Öffnen
------------------------------------------------------------------------

function LMNT.TTT.OpenShop(ply)
	sync(ply)
	net.Start("lmnt_ps_open")
	net.Send(ply)
end

hook.Add("ShowSpare2", "LMNT.Shop.F4", LMNT.TTT.OpenShop)
