--[[
	LMNT TTT – Pointshop (Client): Menü im LMNT-Design, Hut-Darstellung, Chat-Titel, Konfetti-Todeseffekt
	Der Client zeigt nur an: Preise, Rabatt und Erstattungen kommen fertig berechnet vom Server.
]]

local col = LMNT.Config.Colors
local S = LMNT.UI.Scale
local Shop = LMNT.TTT.Shop
local PS = LMNT.TTT.Pointshop

local inventory = {}            -- id -> true (ausgerüstet) | false (im Besitz)
local refunds = {}              -- id -> Erstattung laut Server
local daily = { id = nil, price = 0, discount = 0, day = "" }
local frame

------------------------------------------------------------------------
-- Preise (nur Anzeige)
------------------------------------------------------------------------

local function displayPrice(item)
	if daily.id == item.id and daily.price > 0 then return daily.price end
	return item.price
end

local function displayRefund(item)
	return refunds[item.id] or PS.ComputeRefund(item, nil, LMNT.TTT.ShopSellFactor)
end

------------------------------------------------------------------------
-- Menü: Karten
------------------------------------------------------------------------

local function sendAction(action, id, price)
	net.Start("lmnt_ps_action")
	net.WriteString(action)
	net.WriteString(id)
	net.WriteUInt(price or 0, 32)
	net.SendToServer()
end

-- Kamera so setzen, dass das Modell vollständig und zentriert im Bild ist
local function frameModel(panel, ent, fov, padding)
	local mn, mx = ent:GetRenderBounds()
	local center = (mn + mx) * 0.5
	local height = mx.z - mn.z
	local width = math.max(mx.x - mn.x, mx.y - mn.y)
	local aspect = panel:GetWide() / math.max(panel:GetTall(), 1)

	-- benötigte Halbausdehnung vertikal bzw. horizontal (umgerechnet über das Seitenverhältnis)
	local half = math.max(height / 2, width / 2 / aspect) * (padding or 1.12)
	local dist = half / math.tan(math.rad(fov / 2))

	panel:SetFOV(fov)
	panel:SetLookAt(center)
	panel:SetCamPos(center + Vector(dist, 0, height * 0.05))
end

local function badge(text, x, y, fill, textCol)
	surface.SetFont("LMNT.Label")
	local tw = surface.GetTextSize(text)
	draw.RoundedBox(S(4), x, y, tw + S(14), S(20), fill)
	draw.SimpleText(text, "LMNT.Label", x + S(7), y + S(10), textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	return tw + S(14)
end

-- Vorschau für Chat-Titel: so sieht die Zeile im Chat aus
local function paintTitlePreview(item, w, h)
	local rarity = PS.GetRarity(item)
	draw.SimpleText("[" .. item.title .. "]", "LMNT.Title", w / 2, h * 0.45, rarity.color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(LocalPlayer():Nick() .. ": gg", "LMNT.Small", w / 2, h * 0.45 + S(26), col.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Vorschau für Todeseffekte: einfache, gezeichnete Partikel (kein echter Effekt im Menü)
local PREVIEW_COLORS = {
	party = { Color(255, 80, 80), Color(255, 200, 60), Color(80, 200, 255), Color(120, 230, 120), Color(220, 120, 255) },
	gold = { Color(255, 210, 90), Color(255, 176, 32), Color(255, 240, 180) },
	engine = { Color(255, 220, 150), Color(255, 255, 255) },
}

local function paintEffectPreview(item, w, h)
	local fx = item.effect
	local palette = PREVIEW_COLORS[fx.kind == "confetti" and fx.palette or "engine"] or PREVIEW_COLORS.engine
	local t = RealTime() % 2
	local cx, cy = w / 2, h * 0.55
	for i = 1, 18 do
		-- feste Richtung je Partikel, Radius wächst mit der Zeit, Partikel verblassen zum Ende
		local a = i * 2.39996
		local r = t * S(38) * (0.6 + (i % 5) * 0.12)
		local c = palette[(i % #palette) + 1]
		local alphaV = math.Clamp(255 * (1 - t / 2), 0, 255)
		local x = cx + math.cos(a) * r
		local y = cy + math.sin(a) * r * 0.7 + (fx.kind == "confetti" and t * t * S(12) or 0)
		surface.SetDrawColor(c.r, c.g, c.b, alphaV)
		surface.DrawRect(x, y, S(4), S(4))
	end
end

local function buildCard(parent, item)
	local card = vgui.Create("DPanel", parent)
	card:SetSize(S(196), S(276))
	card.Item = item
	local previewH = S(170)
	local rarity = PS.GetRarity(item)

	card.Paint = function(self, w, h)
		local state = inventory[item.id]
		local hovered = self:IsHovered() or self:IsChildHovered()

		draw.RoundedBox(S(8), 0, 0, w, h, hovered and col.panel2 or col.panel)
		-- Vorschaufläche mit dunklem Verlauf und rotem Schimmer
		draw.RoundedBoxEx(S(8), 0, 0, w, previewH, Color(12, 11, 18), true, true, false, false)
		LMNT.UI.PaintGlow(w / 2, previewH * 0.6, previewH * 1.3, state and 45 or 18)
		-- Seltenheit als Leiste am unteren Rand der Vorschau
		surface.SetDrawColor(rarity.color)
		surface.DrawRect(0, previewH - S(3), w, S(3))

		if item.category == "title" then
			paintTitlePreview(item, w, previewH)
		elseif item.category == "deathfx" then
			paintEffectPreview(item, w, previewH)
		end

		if state then
			surface.SetDrawColor(col.primary)
			surface.DrawOutlinedRect(0, 0, w, h, S(2))
		elseif hovered then
			surface.SetDrawColor(rarity.color.r, rarity.color.g, rarity.color.b, 120)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end
	end

	-- Name, Seltenheit, Preis/Status über der Vorschau (PaintOver: liegt auch über DModelPanel)
	card.PaintOver = function(_, w, _)
		local state = inventory[item.id]
		draw.SimpleText(item.name, "LMNT.BodyBold", S(12), previewH + S(18), col.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(string.upper(rarity.name), "LMNT.Label", w - S(12), previewH + S(18), rarity.color, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

		local y = previewH + S(40)
		if state then
			draw.SimpleText("AUSGERÜSTET", "LMNT.Label", S(12), y, col.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		elseif state == false then
			draw.SimpleText("IM BESITZ", "LMNT.Label", S(12), y, col.good, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		else
			local price = displayPrice(item)
			if price ~= item.price then
				-- Tagesangebot: alter Preis durchgestrichen, neuer Preis in Markenrot
				surface.SetFont("LMNT.Label")
				local old = string.Comma(item.price)
				local ow = surface.GetTextSize(old)
				draw.SimpleText(old, "LMNT.Label", S(12), y, col.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				surface.SetDrawColor(col.muted)
				surface.DrawRect(S(12), y - 1, ow, 1)
				draw.SimpleText(string.Comma(price) .. " PUNKTE", "LMNT.Label", S(12) + ow + S(8), y, col.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			else
				draw.SimpleText(string.Comma(price) .. " PUNKTE", "LMNT.Label", S(12), y, col.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end

		local x = S(10)
		if item.vip then x = x + badge("VIP", x, S(10), LMNT.Ranks.vip.color, col.bg) + S(6) end
		if daily.id == item.id and daily.discount > 0 then
			badge("ANGEBOT -" .. daily.discount .. " %", x, S(10), col.primary, col.white)
		end
	end

	-- Vorschau
	if item.category == "trail" then
		local img = vgui.Create("DImage", card)
		local size = S(110)
		img:SetPos((card:GetWide() - size) / 2, (previewH - size) / 2)
		img:SetSize(size, size)
		img:SetImage(item.material)
		img:SetImageColor(item.color)
		img:SetMouseInputEnabled(false)
	elseif item.model then
		local mdl = vgui.Create("DModelPanel", card)
		mdl:SetPos(S(4), S(4))
		mdl:SetSize(card:GetWide() - S(8), previewH - S(8))
		mdl:SetModel(item.model)
		mdl:SetMouseInputEnabled(false)
		mdl.LayoutEntity = function(_, ent)
			ent:SetAngles(Angle(0, RealTime() * 40 % 360, 0))
		end

		local ent = mdl:GetEntity()
		if IsValid(ent) then
			frameModel(mdl, ent, item.category == "model" and 30 or 35)
		end
	end

	-- Aktions-Button
	local btn = LMNT.UI.Button(card, "", nil)
	btn:SetPos(S(12), card:GetTall() - S(46))
	btn:SetSize(card:GetWide() - S(24), S(34))

	local function refresh()
		local state = inventory[item.id]
		if state == nil then
			btn.Label = "Kaufen"
			btn.DoClick = function()
				local price = displayPrice(item)
				LMNT.UI.Confirm("Kaufen", item.name .. " für " .. string.Comma(price) .. " Punkte kaufen?", "Kaufen", function()
					sendAction("buy", item.id, price)
				end)
			end
		elseif state then
			btn.Label = "Ablegen"
			btn.DoClick = function() sendAction("unequip", item.id) end
		else
			btn.Label = "Ausrüsten"
			btn.DoClick = function() sendAction("equip", item.id) end
		end
	end
	refresh()
	card.Refresh = refresh

	card.OnMousePressed = function(_, code)
		if code ~= MOUSE_RIGHT or inventory[item.id] == nil then return end
		local refund = displayRefund(item)
		LMNT.UI.Confirm("Verkaufen", item.name .. " für " .. string.Comma(refund) .. " Punkte verkaufen?", "Verkaufen", function()
			sendAction("sell", item.id)
		end, "danger")
	end

	return card
end

------------------------------------------------------------------------
-- Menü: Filter und Sortierung
------------------------------------------------------------------------

local filters = { search = "", rarity = "all", owned = "all", sort = "price_asc" }
local pages = {}                -- je Kategorie: { layout, scroll, cards, visible }

local SORTS = {
	{ id = "price_asc",  name = "Preis aufsteigend" },
	{ id = "price_desc", name = "Preis absteigend" },
	{ id = "name",       name = "Name A–Z" },
	{ id = "rarity",     name = "Seltenheit" },
}

local function compareItems(a, b)
	local s = filters.sort
	local pa, pb = displayPrice(a), displayPrice(b)
	if s == "name" then
		if a.name ~= b.name then return a.name < b.name end
	elseif s == "rarity" then
		local ra, rb = PS.GetRarity(a).rank, PS.GetRarity(b).rank
		if ra ~= rb then return ra > rb end
		if pa ~= pb then return pa > pb end
	elseif s == "price_desc" then
		if pa ~= pb then return pa > pb end
	else
		if pa ~= pb then return pa < pb end
	end
	return a.id < b.id
end

local function matches(item)
	if filters.rarity ~= "all" and (item.rarity or "common") ~= filters.rarity then return false end

	local state = inventory[item.id]
	if filters.owned == "owned" and state == nil then return false end
	if filters.owned == "notowned" and state ~= nil then return false end

	local q = filters.search
	if q ~= "" then
		local hay = string.lower(item.name .. " " .. (item.title or "") .. " " .. PS.GetRarity(item).name)
		if not string.find(hay, q, 1, true) then return false end
	end
	return true
end

-- Filtern = nur Sichtbarkeit umschalten (keine neuen Panels)
local function applyFilters()
	for _, page in pairs(pages) do
		local visible = 0
		for _, card in ipairs(page.cards) do
			if IsValid(card) then
				local show = matches(card.Item)
				card:SetVisible(show)
				if show then visible = visible + 1 end
			end
		end
		page.visible = visible
		if IsValid(page.layout) then page.layout:InvalidateLayout() end
	end
end

-- Sortieren = einmaliges Neu-Aufbauen der Karten einer Kategorie (DIconLayout ordnet nach Reihenfolge der Kinder)
local function buildPage(page, categoryId)
	page.layout:Clear()
	page.cards = {}

	local items = {}
	for _, item in pairs(Shop) do
		if item.category == categoryId then items[#items + 1] = item end
	end
	table.sort(items, compareItems)

	for _, item in ipairs(items) do
		local card = buildCard(page.layout, item)
		page.layout:Add(card)
		page.cards[#page.cards + 1] = card
	end
end

local function rebuildAll()
	for categoryId, page in pairs(pages) do
		if IsValid(page.layout) then buildPage(page, categoryId) end
	end
	applyFilters()
end

local function addCombo(parent, width, choices, current, onSelect)
	local combo = LMNT.UI.StyleCombo(vgui.Create("DComboBox", parent))
	combo:Dock(RIGHT)
	combo:SetWide(S(width))
	combo:DockMargin(S(8), 0, 0, 0)
	combo:SetSortItems(false)
	for _, c in ipairs(choices) do
		combo:AddChoice(c.name, c.id, c.id == current)
	end
	combo.OnSelect = function(_, _, _, value) onSelect(value) end
	return combo
end

------------------------------------------------------------------------
-- Menü: Fenster
------------------------------------------------------------------------

local function openShop()
	if IsValid(frame) then frame:Remove() end

	frame = LMNT.UI.Frame("Pointshop", 1120, 760)
	pages = {}

	-- Kopfbereich: Punktestand als Kennzahl und Tagesangebot
	local header = vgui.Create("DPanel", frame)
	header:Dock(TOP)
	header:SetTall(S(64))
	header:DockMargin(0, 0, 0, S(10))
	header.Paint = function(_, w, h)
		draw.RoundedBox(S(8), 0, 0, w, h, col.panel)
		surface.SetDrawColor(col.primary)
		surface.DrawRect(0, S(12), S(3), h - S(24))
		draw.SimpleText("DEINE PUNKTE", "LMNT.Label", S(20), S(18), col.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(string.Comma(LocalPlayer():GetNWInt("lmnt_points", 0)), "LMNT.Display", S(20), S(42), col.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		local offer = daily.id and Shop[daily.id]
		if offer and daily.discount > 0 then
			local r = PS.GetRarity(offer)
			draw.SimpleText("TAGESANGEBOT · -" .. daily.discount .. " %", "LMNT.Label", w * 0.36, S(18), col.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(offer.name .. "  ·  " .. string.Comma(daily.price) .. " statt " .. string.Comma(offer.price) .. " Punkte",
				"LMNT.BodyBold", w * 0.36, S(42), r.color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end

		draw.SimpleText("Rechtsklick auf ein gekauftes Item = verkaufen (" .. math.Round(LMNT.TTT.ShopSellFactor * 100) .. " % vom Kaufpreis)",
			"LMNT.Small", w - S(20), h / 2, col.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	-- Werkzeugleiste: Suche, Seltenheit, Besitz, Sortierung
	local bar = vgui.Create("DPanel", frame)
	bar:Dock(TOP)
	bar:SetTall(S(34))
	bar:DockMargin(0, 0, 0, S(12))
	bar.Paint = nil

	local rarityChoices = { { id = "all", name = "Alle Seltenheiten" } }
	for _, r in ipairs(PS.RarityList) do rarityChoices[#rarityChoices + 1] = { id = r.id, name = r.name } end

	addCombo(bar, 180, SORTS, filters.sort, function(v)
		if filters.sort == v then return end
		filters.sort = v
		rebuildAll()
	end)
	addCombo(bar, 170, {
		{ id = "all", name = "Alle Items" },
		{ id = "owned", name = "Im Besitz" },
		{ id = "notowned", name = "Nicht im Besitz" },
	}, filters.owned, function(v) filters.owned = v applyFilters() end)
	addCombo(bar, 170, rarityChoices, filters.rarity, function(v) filters.rarity = v applyFilters() end)

	local search = LMNT.UI.TextEntry(bar, "Suchen …")
	search:Dock(FILL)
	search:SetValue(filters.search)
	search:SetUpdateOnType(true)
	search.OnValueChange = function(_, value)
		filters.search = string.lower(string.Trim(value or ""))
		applyFilters()
	end

	local tabs = LMNT.UI.Tabs(frame)

	for _, category in ipairs(LMNT.TTT.ShopCategories) do
		local scroll = LMNT.UI.StyleScroll(vgui.Create("DScrollPanel"))
		local layout = vgui.Create("DIconLayout", scroll)
		layout:Dock(FILL)
		layout:SetSpaceX(S(12))
		layout:SetSpaceY(S(12))

		local page = { layout = layout, scroll = scroll, cards = {}, visible = 0 }
		pages[category.id] = page
		buildPage(page, category.id)

		scroll.PaintOver = function(_, w, _)
			if page.visible == 0 then
				draw.SimpleText("Keine Items passen zu deiner Suche.", "LMNT.Body", w / 2, S(60), col.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end

		tabs:AddTab(category.name, scroll)
	end

	applyFilters()
end

net.Receive("lmnt_ps_sync", function()
	inventory = {}
	refunds = {}
	for _ = 1, net.ReadUInt(10) do
		local id = net.ReadString()
		inventory[id] = net.ReadBool()
		refunds[id] = net.ReadUInt(32)
	end

	local dailyId = net.ReadString()
	daily = {
		id = Shop[dailyId] and dailyId or nil,
		price = net.ReadUInt(32),
		discount = net.ReadUInt(7),
		day = net.ReadString(),
	}

	-- Nur Beschriftungen und Sichtbarkeit aktualisieren, Karten bleiben bestehen
	for _, page in pairs(pages) do
		for _, card in ipairs(page.cards) do
			if IsValid(card) then card:Refresh() end
		end
	end
	if IsValid(frame) then applyFilters() end
end)

net.Receive("lmnt_ps_open", openShop)
concommand.Add("lmnt_shop", openShop)

------------------------------------------------------------------------
-- Chat-Titel
------------------------------------------------------------------------

-- cl_admin.lua fragt LMNT.ChatPrefix per hook.Run ab: Es zählt nur das ERSTE Ergebnis ungleich nil.
-- Der Level-Tag (cl_stats.lua) liefert immer etwas. Damit Level-Tag und Chat-Titel nicht von der
-- zufälligen Hook-Reihenfolge abhängen, sammelt dieser Hook die Ergebnisse der übrigen
-- LMNT.ChatPrefix-Hooks (in fester Namensreihenfolge) ein und hängt den Titel an. Die übrigen Hooks
-- werden dafür durch stumme Platzhalter ersetzt und beim Deaktivieren des Moduls zurückgesetzt.
-- Das Ersetzen passiert bewusst erst NACH dem Laden (Timer/Hook-Callback): So erfasst LMNT.Modules die
-- Platzhalter nicht als Pointshop-Hooks und entfernt beim Abschalten des Pointshops nicht den Level-Tag.
-- Sobald cl_admin.lua die Ergebnisse aller Hooks selbst sammelt, kann dieser Block entfallen.
local PREFIX_HOOK = "LMNT.ChatPrefix"
local OWN_HOOK = "LMNT.Shop.ChatTitle"
local foreignPrefix = {}        -- Hookname -> Originalfunktion
local silenced = setmetatable({}, { __mode = "k" })   -- Platzhalterfunktion -> true

local function titlePrefix(ply)
	local item = Shop[ply:GetNWString("lmnt_title", "")]
	if not item or item.category ~= "title" or not isstring(item.title) then return nil end
	return { PS.GetRarity(item).color, "[" .. item.title .. "] " }
end

local function collectForeign()
	local hooks = hook.GetTable()[PREFIX_HOOK] or {}

	-- Hooks, die inzwischen entfernt wurden (z. B. Modul ttt.stats aus), nicht weiter aufrufen
	for name in pairs(foreignPrefix) do
		if not silenced[hooks[name]] then foreignPrefix[name] = nil end
	end

	local found = {}
	for name, fn in pairs(hooks) do
		if name ~= OWN_HOOK and isfunction(fn) and not silenced[fn] then found[name] = fn end
	end
	for name, fn in pairs(found) do
		foreignPrefix[name] = fn
		local stub = function() end
		silenced[stub] = true
		hook.Add(PREFIX_HOOK, name, stub)
	end
end

hook.Add(PREFIX_HOOK, OWN_HOOK, function(ply)
	-- Während hook.Run die Hook-Tabelle durchläuft, nichts registrieren: hier nur lesen
	local hooks = hook.GetTable()[PREFIX_HOOK] or {}
	local names = {}
	for name in pairs(foreignPrefix) do
		if silenced[hooks[name]] then names[#names + 1] = name end
	end
	table.sort(names)

	local out = {}
	for _, name in ipairs(names) do
		local ok, extra = pcall(foreignPrefix[name], ply)
		if ok and istable(extra) then
			for _, v in ipairs(extra) do out[#out + 1] = v end
		end
	end

	local title = titlePrefix(ply)
	if title then
		for _, v in ipairs(title) do out[#out + 1] = v end
	end

	if #out > 0 then return out end
end)

-- Direkt nach dem Laden einsammeln (nächster Frame), wenn die Welt bereit ist, und danach alle 5 s
-- (falls ein anderes Modul neu geladen wurde und seinen Hook erneut registriert hat)
timer.Simple(0, collectForeign)
hook.Add("InitPostEntity", "LMNT.Shop.ChatTitleInit", collectForeign)
timer.Create("LMNT.Shop.ChatTitleCollect", 5, 0, collectForeign)

-- Modul aus: Original-Hooks zurückgeben, sofern noch unser Platzhalter registriert ist
if LMNT.Modules and LMNT.Modules.TrackUndo then
	LMNT.Modules.TrackUndo(function()
		local hooks = hook.GetTable()[PREFIX_HOOK] or {}
		for name, fn in pairs(foreignPrefix) do
			if silenced[hooks[name]] then hook.Add(PREFIX_HOOK, name, fn) end
		end
		foreignPrefix = {}
	end)
end

------------------------------------------------------------------------
-- Todeseffekt „Konfetti“ (Engine-Effekte spielt der Server über util.Effect ab)
------------------------------------------------------------------------

local CONFETTI_COLORS = {
	party = { Color(255, 80, 80), Color(255, 200, 60), Color(80, 200, 255), Color(120, 230, 120), Color(220, 120, 255) },
	gold = { Color(255, 210, 90), Color(255, 176, 32), Color(255, 240, 180) },
}
local CONFETTI_COUNT = 70
local CONFETTI_MAX_LIFE = 2.5           -- Sekunden; danach ist garantiert nichts mehr sichtbar
local CONFETTI_MAX_DIST = 3000

-- Erstes vorhandene Material nehmen (fehlende Materialien würden als Schachbrett erscheinen)
local confettiMaterial
local function getConfettiMaterial()
	if confettiMaterial ~= nil then return confettiMaterial end
	for _, path in ipairs({ "particles/balloon_bit", "effects/spark", "sprites/light_glow02_add" }) do
		local mat = Material(path)
		if not mat:IsError() then confettiMaterial = mat return mat end
	end
	confettiMaterial = false
	return false
end

net.Receive("lmnt_ps_deathfx", function()
	local id = net.ReadString()
	local pos = net.ReadVector()

	local item = Shop[id]
	if not item or item.category ~= "deathfx" or not istable(item.effect) or item.effect.kind ~= "confetti" then return end
	if pos:DistToSqr(EyePos()) > CONFETTI_MAX_DIST * CONFETTI_MAX_DIST then return end

	local mat = getConfettiMaterial()
	if not mat then return end

	local palette = CONFETTI_COLORS[item.effect.palette] or CONFETTI_COLORS.party
	local emitter = ParticleEmitter(pos)
	if not emitter then return end

	for i = 1, CONFETTI_COUNT do
		local p = emitter:Add(mat, pos)
		if p then
			local c = palette[(i % #palette) + 1]
			p:SetVelocity(VectorRand() * math.Rand(80, 220) + Vector(0, 0, math.Rand(120, 260)))
			p:SetDieTime(math.Rand(1.2, CONFETTI_MAX_LIFE))
			p:SetStartAlpha(255)
			p:SetEndAlpha(0)
			p:SetStartSize(math.Rand(1.5, 3))
			p:SetEndSize(1)
			p:SetRoll(math.Rand(0, 360))
			p:SetRollDelta(math.Rand(-8, 8))
			p:SetColor(c.r, c.g, c.b)
			p:SetGravity(Vector(0, 0, -350))
			p:SetAirResistance(90)
			p:SetCollide(true)
			p:SetBounce(0.2)
		end
	end
	-- Emitter sofort freigeben: die Partikel laufen bis zu ihrer DieTime weiter und verschwinden dann
	emitter:Finish()
end)

------------------------------------------------------------------------
-- Hüte zeichnen
------------------------------------------------------------------------

local hatModels = {}

local function getHatModel(ply, item)
	local cached = hatModels[ply]
	if cached and IsValid(cached.ent) and cached.id == item.id then return cached.ent end
	if cached and IsValid(cached.ent) then cached.ent:Remove() end

	local ent = ClientsideModel(item.model, RENDERGROUP_OPAQUE)
	if not IsValid(ent) then return end
	ent:SetNoDraw(true)
	ent:SetModelScale(item.scale or 1)

	hatModels[ply] = { ent = ent, id = item.id }
	return ent
end

hook.Add("PostPlayerDraw", "LMNT.Shop.Hats", function(ply)
	if not ply:Alive() then return end

	local item = Shop[ply:GetNWString("lmnt_hat", "")]
	if not item or item.category ~= "hat" then return end

	local attachment = ply:LookupAttachment("eyes")
	if not attachment or attachment <= 0 then return end

	local data = ply:GetAttachment(attachment)
	if not data then return end

	local ent = getHatModel(ply, item)
	if not IsValid(ent) then return end

	local ang = data.Ang
	local pos = data.Pos + ang:Up() * (item.up or 0) + ang:Forward() * (item.forward or 0)

	local drawAng = Angle(ang.p, ang.y, ang.r)
	if item.ang then
		drawAng:RotateAroundAxis(drawAng:Right(), item.ang.p)
		drawAng:RotateAroundAxis(drawAng:Up(), item.ang.y)
		drawAng:RotateAroundAxis(drawAng:Forward(), item.ang.r)
	end

	ent:SetPos(pos)
	ent:SetAngles(drawAng)
	ent:SetupBones()
	ent:DrawModel()
end)

hook.Add("EntityRemoved", "LMNT.Shop.HatCleanup", function(ent)
	local cached = hatModels[ent]
	if cached then
		if IsValid(cached.ent) then cached.ent:Remove() end
		hatModels[ent] = nil
	end
end)
