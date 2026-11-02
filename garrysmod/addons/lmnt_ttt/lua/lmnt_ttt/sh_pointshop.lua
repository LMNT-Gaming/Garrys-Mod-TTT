--[[
	LMNT TTT – Pointshop-Katalog und reine Shop-Logik (geteilt)
	Alles nutzt Inhalte, die mit Garry's Mod mitkommen – kein Extra-Download nötig.

	Kategorien: model (Spielermodell), hat (Kopfbedeckung), trail (Spur),
	            title (Chat-Titel), deathfx (Todeseffekt)
	Pro Kategorie kann genau ein Item ausgerüstet sein.
	vip = true      -> nur für Ränge mit dem Recht "vip"
	rarity          -> common | rare | epic | legendary (Preisband siehe RarityList)

	Die Funktionen in LMNT.TTT.Pointshop sind rein (keine Spieler, kein Netzwerk, keine Datenbank)
	und werden in lua/lmnt/tests/sv_pointshop.lua getestet. Preise entscheidet immer der Server,
	der Client nutzt sie nur zur Anzeige.
]]

LMNT.TTT.Shop = {}
LMNT.TTT.ShopCategories = {
	{ id = "model",   name = "Spielermodelle" },
	{ id = "hat",     name = "Hüte" },
	{ id = "trail",   name = "Spuren" },
	{ id = "title",   name = "Chat-Titel" },
	{ id = "deathfx", name = "Todeseffekte" },
}
LMNT.TTT.ShopSellFactor = 0.5

local PS = {}
LMNT.TTT.Pointshop = PS

------------------------------------------------------------------------
-- Seltenheiten
------------------------------------------------------------------------

-- Farben: gewöhnlich = muted, selten = info, legendär = warn aus dem Designsystem (kontrastgeprüft auf ink).
-- Episch ist ergänzt (helles Violett #ba80ff, Kontrast auf #08070c > 7:1). Bewusst keine Rollenfarben als
-- Bedeutungsträger: Die Farbe hängt nur am Item, nie an Rolle oder Team.
local C = LMNT.Config.Colors
PS.RarityList = {
	{ id = "common",    name = "Gewöhnlich", rank = 1, color = C.muted,              min = 150,  max = 450 },
	{ id = "rare",      name = "Selten",     rank = 2, color = C.info,               min = 500,  max = 850 },
	{ id = "epic",      name = "Episch",     rank = 3, color = Color(186, 128, 255), min = 900,  max = 1450 },
	{ id = "legendary", name = "Legendär",   rank = 4, color = C.warn,               min = 1500, max = 3000 },
}
PS.Rarities = {}
for _, r in ipairs(PS.RarityList) do PS.Rarities[r.id] = r end

function PS.GetRarity(item)
	return PS.Rarities[item and item.rarity or "common"] or PS.Rarities.common
end

------------------------------------------------------------------------
-- Katalog
------------------------------------------------------------------------

local function add(id, data)
	data.id = id
	LMNT.TTT.Shop[id] = data
end

-- Spielermodelle
add("mdl_kleiner",  { category = "model", rarity = "common",    name = "Dr. Kleiner",    price = 400,  model = "models/player/kleiner.mdl" })
add("mdl_barney",   { category = "model", rarity = "common",    name = "Barney",         price = 400,  model = "models/player/barney.mdl" })
add("mdl_alyx",     { category = "model", rarity = "rare",      name = "Alyx",           price = 550,  model = "models/player/alyx.mdl" })
add("mdl_mossman",  { category = "model", rarity = "rare",      name = "Mossman",        price = 550,  model = "models/player/mossman.mdl" })
add("mdl_police",   { category = "model", rarity = "rare",      name = "Metrocop",       price = 700,  model = "models/player/police.mdl" })
add("mdl_breen",    { category = "model", rarity = "rare",      name = "Dr. Breen",      price = 850,  model = "models/player/breen.mdl" })
add("mdl_combine",  { category = "model", rarity = "epic",      name = "Combine-Soldat", price = 950,  model = "models/player/combine_soldier.mdl" })
add("mdl_elite",    { category = "model", rarity = "epic",      name = "Combine-Elite",  price = 1300, model = "models/player/combine_super_soldier.mdl" })
add("mdl_gman",     { category = "model", rarity = "legendary", name = "G-Man",          price = 1800, model = "models/player/gman_high.mdl" })
add("mdl_skeleton", { category = "model", rarity = "legendary", name = "Skelett",        price = 2500, model = "models/player/skeleton.mdl", vip = true })

-- Hüte (Position relativ zum "eyes"-Attachment: up/forward in Einheiten, ang = Drehung)
add("hat_melon",    { category = "hat", rarity = "common", name = "Melonenhelm",     price = 250,  model = "models/props_junk/watermelon01.mdl",   scale = 0.7, up = 5, forward = -3, ang = Angle(0, 0, 0) })
add("hat_cone",     { category = "hat", rarity = "common", name = "Verkehrshütchen", price = 300,  model = "models/props_junk/TrafficCone001a.mdl", scale = 0.4, up = 9, forward = -3, ang = Angle(0, 0, 0) })
add("hat_bucket",   { category = "hat", rarity = "common", name = "Eimer",           price = 350,  model = "models/props_junk/MetalBucket01a.mdl", scale = 0.6, up = 6, forward = -3, ang = Angle(180, 0, 0) })
add("hat_pot",      { category = "hat", rarity = "common", name = "Kochtopf",        price = 350,  model = "models/props_interiors/pot02a.mdl",    scale = 0.9, up = 5, forward = -3, ang = Angle(180, 0, 0) })
add("hat_headcrab", { category = "hat", rarity = "epic",   name = "Kopfkrabbe",      price = 1000, model = "models/headcrabclassic.mdl",           scale = 0.7, up = 3, forward = -4, ang = Angle(0, 0, 0), vip = true })

-- Spuren
add("trail_smoke",    { category = "trail", rarity = "common",    name = "Rauch",   price = 400,  material = "trails/smoke",    color = Color(220, 220, 220) })
add("trail_laser",    { category = "trail", rarity = "rare",      name = "Laser",   price = 500,  material = "trails/laser",    color = Color(255, 60, 60) })
add("trail_plasma",   { category = "trail", rarity = "rare",      name = "Plasma",  price = 500,  material = "trails/plasma",   color = Color(80, 160, 255) })
add("trail_electric", { category = "trail", rarity = "rare",      name = "Elektro", price = 750,  material = "trails/electric", color = Color(255, 255, 120) })
add("trail_love",     { category = "trail", rarity = "epic",      name = "Herzen",  price = 950,  material = "trails/love",     color = Color(255, 120, 200) })
add("trail_lol",      { category = "trail", rarity = "legendary", name = "LOL",     price = 1500, material = "trails/lol",      color = Color(255, 255, 255), vip = true })

-- Chat-Titel: fester Text aus dem Katalog (höchstens PS.TitleMaxLength Zeichen), Farbe = Seltenheit.
-- Bewusst keine Rollen- oder Teamnamen, damit ein Titel nie wie eine Rolleninfo aussieht.
add("title_rookie",   { category = "title", rarity = "common",    name = "Frischling",     price = 200,  title = "Frischling" })
add("title_regular",  { category = "title", rarity = "common",    name = "Stammgast",      price = 300,  title = "Stammgast" })
add("title_lucky",    { category = "title", rarity = "rare",      name = "Glückspilz",     price = 600,  title = "Glückspilz" })
add("title_shadow",   { category = "title", rarity = "rare",      name = "Schattenläufer", price = 750,  title = "Schattenläufer" })
add("title_tactic",   { category = "title", rarity = "epic",      name = "Taktiker",       price = 1000, title = "Taktiker" })
add("title_legend",   { category = "title", rarity = "legendary", name = "Legende",        price = 2000, title = "Legende", vip = true })

-- Todeseffekte: rein kosmetisch, für jede Rolle identisch (hängt nur am Item).
-- kind = "engine": eingebauter Effekt über util.Effect (Server), Feldwerte für EffectData
-- kind = "confetti": Partikel auf dem Client (cl_pointshop.lua), feste Farben, Lebensdauer begrenzt
add("fx_sparks",   { category = "deathfx", rarity = "common",    name = "Funkenregen", price = 300,  effect = { kind = "engine", name = "Sparks", magnitude = 4, scale = 2, radius = 8 } })
add("fx_glass",    { category = "deathfx", rarity = "common",    name = "Scherben",    price = 350,  effect = { kind = "engine", name = "GlassImpact", magnitude = 1, scale = 1, radius = 1 } })
add("fx_dust",     { category = "deathfx", rarity = "rare",      name = "Staubwolke",  price = 600,  effect = { kind = "engine", name = "ThumperDust", magnitude = 1, scale = 48, radius = 48 } })
add("fx_energy",   { category = "deathfx", rarity = "rare",      name = "Energieball", price = 800,  effect = { kind = "engine", name = "cball_explode", magnitude = 1, scale = 1, radius = 1 } })
add("fx_confetti", { category = "deathfx", rarity = "epic",      name = "Konfetti",    price = 1200, effect = { kind = "confetti", palette = "party" } })
add("fx_gold",     { category = "deathfx", rarity = "legendary", name = "Goldregen",   price = 2000, effect = { kind = "confetti", palette = "gold" }, vip = true })

------------------------------------------------------------------------
-- Reine Logik (testbar)
------------------------------------------------------------------------

PS.TitleMaxLength = 16
PS.MaxDiscount = 90          -- Obergrenze für das Tagesangebot in Prozent
PS.MaxIdLength = 48

-- Basispreis eines Items: nur positive ganze Zahlen sind gültig, sonst nil (Item nicht kaufbar)
function PS.BasePrice(item)
	local p = istable(item) and item.price
	if not isnumber(p) or p ~= p or p < 1 or p ~= math.floor(p) or p == math.huge then return nil end
	return p
end

-- Rabatt auf 0–MaxDiscount ganzzahlig begrenzen (Einstellung könnte über config.json Unsinn liefern)
function PS.ClampDiscount(discount)
	if not isnumber(discount) or discount ~= discount then return 0 end
	return math.Clamp(math.floor(discount), 0, PS.MaxDiscount)
end

-- Preis für einen Kauf. isDaily = Item ist heute das Tagesangebot. Rückgabe: ganze Zahl >= 1 oder nil
function PS.ComputePrice(item, isDaily, discount)
	local base = PS.BasePrice(item)
	if not base then return nil end
	if not isDaily then return base end

	local d = PS.ClampDiscount(discount)
	return math.max(1, math.floor(base * (100 - d) / 100))
end

-- Erstattung beim Verkauf: Anteil vom tatsächlich bezahlten Preis, höchstens vom Basispreis.
-- So bringt ein im Tagesangebot gekauftes Item beim Verkauf nie mehr ein, als es gekostet hat.
-- paid = nil (Altbestand ohne gespeicherten Preis) -> Basispreis
function PS.ComputeRefund(item, paid, factor)
	local base = PS.BasePrice(item)
	if not base then return 0 end
	local basis = base
	if isnumber(paid) and paid >= 0 and paid < base then basis = math.floor(paid) end
	factor = math.Clamp(tonumber(factor) or LMNT.TTT.ShopSellFactor, 0, 1)
	return math.max(0, math.floor(basis * factor))
end

-- Kandidaten für das Tagesangebot: alle kaufbaren Nicht-VIP-Items, nach ID sortiert (stabile Reihenfolge)
function PS.DailyCandidates(catalog)
	local ids = {}
	for id, item in pairs(catalog or LMNT.TTT.Shop) do
		if not item.vip and PS.BasePrice(item) then ids[#ids + 1] = id end
	end
	table.sort(ids)
	return ids
end

-- Deterministische Auswahl: gleicher Tag + gleicher Katalog = gleiches Item, auch nach einem Neustart
function PS.PickDaily(dayKey, catalog)
	local ids = PS.DailyCandidates(catalog)
	if #ids == 0 then return nil end
	local hash = tonumber(util.CRC("lmnt_ps_daily:" .. tostring(dayKey))) or 0
	return ids[(hash % #ids) + 1]
end

-- Tagesschlüssel in Serverzeit (Wechsel um Mitternacht)
function PS.DayKey(time)
	return os.date("%Y-%m-%d", time or os.time())
end

-- Kaufprüfung ohne Spielerobjekt.
-- ctx = { item = Katalogeintrag|nil, owned = bool, isVip = bool, points = Zahl, price = Serverpreis|nil,
--         expected = vom Client angezeigter Preis|nil }
-- Rückgabe: true | false, code, meldung   (code: unknown, owned, vip, price, changed, points)
function PS.CheckBuy(ctx)
	local item = ctx.item
	if not istable(item) then return false, "unknown", "Dieses Item gibt es nicht." end
	if ctx.owned then return false, "owned", "Du besitzt " .. item.name .. " bereits." end
	if item.vip and not ctx.isVip then return false, "vip", "Dieses Item gibt es nur für VIPs." end

	local price = ctx.price
	if not isnumber(price) or price < 1 or price ~= math.floor(price) then
		return false, "price", "Dieses Item ist gerade nicht kaufbar."
	end
	-- Der Client hat einen anderen Preis bestätigt (z. B. Tageswechsel): nicht zum neuen Preis abbuchen
	if ctx.expected ~= nil and ctx.expected ~= price then
		return false, "changed", "Der Preis hat sich geändert (jetzt " .. price .. " Punkte). Bitte erneut kaufen."
	end

	local points = tonumber(ctx.points) or 0
	if points < price then return false, "points", "Dir fehlen " .. (price - points) .. " Punkte." end
	return true
end

-- Verkaufsprüfung. ctx = { item, owned }
function PS.CheckSell(ctx)
	if not istable(ctx.item) then return false, "unknown", "Dieses Item gibt es nicht." end
	if not ctx.owned then return false, "notowned", "Du besitzt dieses Item nicht." end
	return true
end

-- Kurze Prüfung des Katalogs (für Tests und Entwickler): Preis passt zur Seltenheit, Titel kurz genug
function PS.ValidateCatalog(catalog)
	local problems = {}
	for id, item in pairs(catalog or LMNT.TTT.Shop) do
		local r = PS.Rarities[item.rarity or ""]
		local price = PS.BasePrice(item)
		if not r then
			problems[#problems + 1] = id .. ": unbekannte Seltenheit"
		elseif not price or price < r.min or price > r.max then
			problems[#problems + 1] = id .. ": Preis passt nicht zu " .. r.name
		end
		if #id > PS.MaxIdLength then problems[#problems + 1] = id .. ": ID zu lang" end
		if item.category == "title" and (not isstring(item.title) or utf8.len(item.title) == false
			or utf8.len(item.title) > PS.TitleMaxLength or item.title == "") then
			problems[#problems + 1] = id .. ": ungültiger Titel"
		end
		if item.category == "deathfx" and not (istable(item.effect) and (item.effect.kind == "engine" or item.effect.kind == "confetti")) then
			problems[#problems + 1] = id .. ": ungültiger Effekt"
		end
	end
	table.sort(problems)
	return problems
end

------------------------------------------------------------------------
-- Einstellungen und Befehl
------------------------------------------------------------------------

LMNT.Settings.Define("ttt.pointshop.daily_discount", {
	type = "int", default = 25, min = 0, max = PS.MaxDiscount, category = "Pointshop", applies = "live",
	desc = "Rabatt in Prozent auf das tägliche Angebot im Pointshop (0 = kein Tagesangebot)",
})

LMNT.Admin.AddCommand("shop", {
	help = "Öffnet den Pointshop (auch F4)",
	aliases = { "pointshop", "ps" },
	playerOnly = true,
	run = function(caller) LMNT.TTT.OpenShop(caller) end,
})
