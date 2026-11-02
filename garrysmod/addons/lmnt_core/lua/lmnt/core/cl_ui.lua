--[[
	LMNT Framework – UI-Komponentenbibliothek im LMNT-Design (Tokens: LMNT.Config.Colors / .Fonts)
	Referenz: docs/framework/05_DESIGNSYSTEM.md

	Skalierung
	  LMNT.UI.Scale(px)                         -> px relativ zu 1080p
	Fenster & Layout
	  LMNT.UI.Frame(titel, breite, höhe)         -> DFrame (Raster-Hintergrund, rote Kopfzeile)
	  LMNT.UI.Tabs(parent)                       -> Seitennavigation, :AddTab(name, panel) – nummeriert "01 / NAME"
	  LMNT.UI.Section(parent, nummer, titel)     -> Abschnittstitel im Web-Stil
	Steuerelemente
	  LMNT.UI.Button(parent, text, onClick, variante)   variante: "primary" (Standard) | "ghost" | "danger" | "success" | Color
	  LMNT.UI.TextEntry(parent, platzhalter)
	  LMNT.UI.StyleList(dlistview), LMNT.UI.StyleScroll(dscrollpanel), LMNT.UI.StyleCombo(dcombobox)
	Dialoge & Meldungen
	  LMNT.UI.Prompt(titel, text, standard, onOk)      Texteingabe
	  LMNT.UI.Confirm(titel, text, okText, onOk)       Bestätigung
	  LMNT.UI.Alert(titel, text)
	  LMNT.UI.Toast(text, farbe, sekunden)             kleine Meldung unten rechts
]]

LMNT.UI = LMNT.UI or {}
local col = LMNT.Config.Colors
local fonts = LMNT.Config.Fonts

------------------------------------------------------------------------
-- Skalierung & Schriften
------------------------------------------------------------------------

function LMNT.UI.Scale(px)
	return math.max(1, math.Round(px * ScrH() / 1080))
end
local S = LMNT.UI.Scale

--[[
	GMod registriert Schriften aus resource/fonts nur beim Spielstart. Beim ersten Besuch sind die
	gerade heruntergeladenen Marken-Schriften deshalb noch nicht verfügbar und GMod fiele still auf
	Tahoma zurück. Wir messen nach: Ist die Breite eines Testtextes identisch mit Tahoma, fehlt die
	Schrift -> Fallback auf Roboto (Teil von GMod) und einmaliger Hinweis an den Spieler.
]]
local FALLBACK_DISPLAY, FALLBACK_BODY = "Roboto", "Roboto" -- Display-Fallback mit weight 900

local function fontAvailable(family, weight)
	local probe = "LMNT Gaming Collective 0123456789"
	surface.CreateFont("LMNT._Probe", { font = family, size = 40, weight = weight })
	surface.CreateFont("LMNT._ProbeTahoma", { font = "Tahoma", size = 40, weight = weight })
	surface.SetFont("LMNT._Probe")
	local w1 = surface.GetTextSize(probe)
	surface.SetFont("LMNT._ProbeTahoma")
	local w2 = surface.GetTextSize(probe)
	return w1 ~= w2
end

LMNT.UI.BrandFontsLoaded = nil

local function createFonts()
	local display, body, medium = fonts.display, fonts.body, fonts.medium
	local loaded = fontAvailable(display, 400) and fontAvailable(body, 400)

	if not loaded then
		display, body, medium = FALLBACK_DISPLAY, FALLBACK_BODY, FALLBACK_BODY
	end
	LMNT.UI.BrandFontsLoaded = loaded

	-- Display: Archivo Black (Titel, Zahlen, Banner)
	surface.CreateFont("LMNT.Huge",    { font = display, size = S(48), weight = loaded and 400 or 900, extended = true })
	surface.CreateFont("LMNT.Display", { font = display, size = S(26), weight = loaded and 400 or 900, extended = true })
	surface.CreateFont("LMNT.Title",   { font = display, size = S(20), weight = loaded and 400 or 900, extended = true })
	-- Text: DM Sans
	surface.CreateFont("LMNT.Body",    { font = body,   size = S(17), weight = 400, extended = true })
	surface.CreateFont("LMNT.BodyBold",{ font = body,   size = S(17), weight = 700, extended = true })
	surface.CreateFont("LMNT.Small",   { font = body,   size = S(14), weight = 400, extended = true })
	-- Labels: Großbuchstaben, fett, eine Stufe kleiner (GMod kennt keine Laufweite)
	surface.CreateFont("LMNT.Label",   { font = body,   size = S(13), weight = 700, extended = true })
	surface.CreateFont("LMNT.Button",  { font = medium, size = S(15), weight = 500, extended = true })
end

createFonts()
hook.Add("OnScreenSizeChanged", "LMNT.UI.Fonts", createFonts)

hook.Add("InitPostEntity", "LMNT.UI.FontHint", function()
	if LMNT.UI.BrandFontsLoaded then return end
	timer.Simple(8, function()
		chat.AddText(col.primary, "[LMNT] ", col.text, "Die LMNT-Schriften wurden gerade heruntergeladen. ",
			col.muted, "Starte Garry's Mod einmal neu, um das volle Design zu sehen.")
	end)
end)

local function alpha(c, a)
	return Color(c.r, c.g, c.b, a)
end

local function lighten(c, amount)
	return Color(math.min(255, c.r + amount), math.min(255, c.g + amount), math.min(255, c.b + amount), c.a)
end

LMNT.UI.Alpha = alpha
LMNT.UI.Lighten = lighten

-- Raster wie auf lmnt-gaming.net (1-px-Linien, 4,5 % Deckkraft)
local gridColor = Color(255, 255, 255, 11)
function LMNT.UI.PaintGrid(w, h, step)
	step = step or S(32)
	surface.SetDrawColor(gridColor)
	for x = step, w, step do surface.DrawRect(x, 0, 1, h) end
	for y = step, h, step do surface.DrawRect(0, y, w, 1) end
end

-- Roter Glow (radialer Verlauf) als Material aus dem Spiel
local glowMat = Material("gui/center_gradient")
function LMNT.UI.PaintGlow(x, y, size, a)
	if glowMat:IsError() then return end
	surface.SetMaterial(glowMat)
	surface.SetDrawColor(col.accent.r, col.accent.g, col.accent.b, a or 40)
	surface.DrawTexturedRect(x - size / 2, y - size / 2, size, size)
end

------------------------------------------------------------------------
-- Fenster
------------------------------------------------------------------------

function LMNT.UI.Frame(title, w, h)
	local frame = vgui.Create("DFrame")
	frame:SetSize(math.min(S(w), ScrW() - 40), math.min(S(h), ScrH() - 40))
	frame:Center()
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:SetDraggable(true)
	frame:MakePopup()
	local header = S(52)
	frame:DockPadding(S(14), header + S(12), S(14), S(14))

	local upperTitle = string.upper(title)

	frame.Paint = function(_, pw, ph)
		draw.RoundedBox(S(8), 0, 0, pw, ph, col.bg)
		LMNT.UI.PaintGrid(pw, ph)
		LMNT.UI.PaintGlow(pw * 0.85, ph * 0.1, ph * 1.2, 22)

		-- Kopfzeile
		draw.RoundedBoxEx(S(8), 0, 0, pw, header, col.panel, true, true, false, false)
		surface.SetDrawColor(col.primary)
		surface.DrawRect(0, 0, pw, S(3))
		surface.SetDrawColor(col.line)
		surface.DrawRect(0, header - 1, pw, 1)

		surface.SetFont("LMNT.Title")
		local lw = surface.GetTextSize("LMNT")
		draw.SimpleText("LMNT", "LMNT.Title", S(18), header / 2, col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("/", "LMNT.Title", S(18) + lw + S(10), header / 2, col.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(upperTitle, "LMNT.Label", S(18) + lw + S(30), header / 2, col.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local close = vgui.Create("DButton", frame)
	close:SetText("")
	close:SetSize(header, header)
	close.DoClick = function() frame:Close() end
	close.Paint = function(self, pw, ph)
		if self:IsHovered() then draw.RoundedBoxEx(S(8), 0, 0, pw, ph, alpha(col.primary, 40), false, true, false, false) end
		local c = self:IsHovered() and col.primary or col.muted
		local m = S(19)
		surface.SetDrawColor(c)
		for i = 0, 1 do
			surface.DrawLine(m + i, m, pw - m + i, ph - m)
			surface.DrawLine(pw - m + i, m, m + i, ph - m)
		end
	end
	frame.PerformLayout = function(self, pw)
		close:SetPos(pw - header, 0)
	end

	return frame
end

function LMNT.UI.Section(parent, number, title)
	local pnl = vgui.Create("DPanel", parent)
	pnl:Dock(TOP)
	pnl:SetTall(S(30))
	pnl:DockMargin(0, 0, 0, S(8))
	local text = string.format("%02d", number) .. " / " .. string.upper(title)
	pnl.Paint = function(_, _, h)
		draw.SimpleText(text, "LMNT.Label", 0, h / 2, col.primary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	return pnl
end

------------------------------------------------------------------------
-- Buttons
------------------------------------------------------------------------

local variants = {
	primary = { fill = col.primary, text = col.white },
	danger  = { fill = col.accent, text = col.white },
	success = { fill = Color(30, 150, 70), text = col.white },
	ghost   = { fill = nil, text = col.text },
}

function LMNT.UI.Button(parent, text, onClick, variant)
	local btn = vgui.Create("DButton", parent)
	btn:SetText("")
	btn:SetTall(S(34))
	btn.Label = text
	btn.DoClick = onClick

	local v = variants[variant or "primary"]
	if IsColor(variant) then v = { fill = variant, text = col.white } end
	v = v or variants.primary

	btn.Paint = function(self, w, h)
		local disabled = self:GetDisabled()
		local r = S(6)

		if disabled then
			draw.RoundedBox(r, 0, 0, w, h, col.panel2)
		elseif v.fill then
			local fill = v.fill
			if self:IsDown() then fill = col.deep elseif self:IsHovered() then fill = lighten(fill, 22) end
			draw.RoundedBox(r, 0, 0, w, h, fill)
		else
			draw.RoundedBox(r, 0, 0, w, h, self:IsHovered() and col.panel2 or alpha(col.panel2, 0))
			surface.SetDrawColor(self:IsHovered() and col.primary or col.line)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end

		draw.SimpleText(string.upper(self.Label), "LMNT.Button", w / 2, h / 2, disabled and col.muted or v.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	return btn
end

------------------------------------------------------------------------
-- Eingaben, Listen, Scrollbars
------------------------------------------------------------------------

function LMNT.UI.TextEntry(parent, placeholder)
	local entry = vgui.Create("DTextEntry", parent)
	entry:SetTall(S(34))
	entry:SetFont("LMNT.Body")
	entry:SetPlaceholderText(placeholder or "")
	entry:SetPaintBackground(false)
	entry.Paint = function(self, w, h)
		draw.RoundedBox(S(6), 0, 0, w, h, col.panel)
		surface.SetDrawColor(self:HasFocus() and col.primary or col.line)
		surface.DrawOutlinedRect(0, 0, w, h, 1)

		if self:GetValue() == "" and not self:HasFocus() and self:GetPlaceholderText() ~= "" then
			draw.SimpleText(self:GetPlaceholderText(), "LMNT.Body", S(10), h / 2, col.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		self:DrawTextEntryText(col.text, alpha(col.primary, 120), col.white)
	end
	return entry
end

function LMNT.UI.StyleScroll(scroll)
	local bar = scroll.VBar or scroll:GetVBar()
	if not bar then return scroll end
	bar:SetWide(S(6))
	bar:SetHideButtons(true)
	bar.Paint = function(_, w, h) draw.RoundedBox(S(3), 0, 0, w, h, col.panel) end
	bar.btnGrip.Paint = function(self, w, h)
		draw.RoundedBox(S(3), 0, 0, w, h, self:IsHovered() and col.primary or col.panel2)
	end
	return scroll
end

function LMNT.UI.StyleList(list)
	list:SetDataHeight(S(28))
	list:SetHeaderHeight(S(30))
	list.Paint = function(_, w, h)
		draw.RoundedBox(S(6), 0, 0, w, h, col.panel)
	end
	LMNT.UI.StyleScroll(list)

	for _, column in ipairs(list.Columns) do
		column.Header:SetFont("LMNT.Label")
		column.Header:SetTextColor(col.muted)
		column.Header:SetText(string.upper(column.Header:GetText()))
		column.Header.Paint = function(_, w, h)
			surface.SetDrawColor(col.line)
			surface.DrawRect(0, h - 1, w, 1)
		end
	end

	local oldAdd = list.AddLine
	list.AddLine = function(self, ...)
		local line = oldAdd(self, ...)
		for _, lbl in ipairs(line.Columns) do
			lbl:SetFont("LMNT.Small")
			lbl:SetTextColor(col.text)
			lbl:SetTextInset(S(6), 0)
		end
		line.Paint = function(ln, w, h)
			if ln:IsSelected() then
				draw.RoundedBox(0, 0, 0, w, h, alpha(col.primary, 45))
				surface.SetDrawColor(col.primary)
				surface.DrawRect(0, 0, S(3), h)
			elseif ln:IsHovered() then
				draw.RoundedBox(0, 0, 0, w, h, col.panel2)
			end
		end
		return line
	end
end

function LMNT.UI.StyleCombo(combo)
	combo:SetFont("LMNT.Small")
	combo:SetTextColor(col.text)
	combo:SetTall(S(34))
	combo.Paint = function(self, w, h)
		draw.RoundedBox(S(6), 0, 0, w, h, col.panel)
		surface.SetDrawColor(self:IsMenuOpen() and col.primary or col.line)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	return combo
end

------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------

function LMNT.UI.Tabs(parent)
	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = nil

	local side = vgui.Create("DPanel", root)
	side:Dock(LEFT)
	side:SetWide(S(200))
	side:DockMargin(0, 0, S(14), 0)
	side:DockPadding(S(8), S(8), S(8), S(8))
	side.Paint = function(_, w, h)
		draw.RoundedBox(S(8), 0, 0, w, h, alpha(col.panel, 230))
	end

	local content = vgui.Create("DPanel", root)
	content:Dock(FILL)
	content.Paint = nil

	root.Tabs = {}

	function root:AddTab(name, panel)
		panel:SetParent(content)
		panel:Dock(FILL)
		panel:SetVisible(#self.Tabs == 0)

		local index = #self.Tabs + 1
		local number = string.format("%02d", index)
		local label = string.upper(name)

		local btn = vgui.Create("DButton", side)
		btn:Dock(TOP)
		btn:SetTall(S(40))
		btn:DockMargin(0, 0, 0, S(4))
		btn:SetText("")
		btn.Paint = function(b, w, h)
			local active = panel:IsVisible()
			if active then
				draw.RoundedBox(S(6), 0, 0, w, h, alpha(col.primary, 30))
				surface.SetDrawColor(col.primary)
				surface.DrawRect(0, S(8), S(3), h - S(16))
			elseif b:IsHovered() then
				draw.RoundedBox(S(6), 0, 0, w, h, col.panel2)
			end
			draw.SimpleText(number, "LMNT.Label", S(14), h / 2, active and col.primary or col.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(label, "LMNT.Label", S(42), h / 2, active and col.white or col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		btn.DoClick = function()
			for _, t in ipairs(self.Tabs) do t:SetVisible(false) end
			panel:SetVisible(true)
			surface.PlaySound("ui/buttonclick.wav")
		end

		self.Tabs[index] = panel
		return panel
	end

	return root
end

------------------------------------------------------------------------
-- Dialoge
------------------------------------------------------------------------

local function dialog(title, text, height)
	local frame = LMNT.UI.Frame(title, 460, height or 230)
	frame:SetBackgroundBlur(true)
	frame:DoModal()

	local lbl = vgui.Create("DLabel", frame)
	lbl:Dock(TOP)
	lbl:SetFont("LMNT.Body")
	lbl:SetTextColor(col.text)
	lbl:SetText(text)
	lbl:SetWrap(true)
	lbl:SetAutoStretchVertical(true)
	lbl:DockMargin(0, 0, 0, S(12))

	local bar = vgui.Create("DPanel", frame)
	bar:Dock(BOTTOM)
	bar:SetTall(S(34))
	bar.Paint = nil

	return frame, bar
end

function LMNT.UI.Prompt(title, text, default, onOk)
	local frame, bar = dialog(title, text, 250)

	local entry = LMNT.UI.TextEntry(frame, "")
	entry:Dock(TOP)
	entry:SetValue(default or "")
	entry:RequestFocus()

	local function submit()
		local value = entry:GetValue()
		frame:Close()
		if onOk then onOk(value) end
	end
	entry.OnEnter = submit

	local ok = LMNT.UI.Button(bar, "Weiter", submit)
	ok:Dock(RIGHT)
	ok:SetWide(S(130))
	local cancel = LMNT.UI.Button(bar, "Abbrechen", function() frame:Close() end, "ghost")
	cancel:Dock(RIGHT)
	cancel:SetWide(S(130))
	cancel:DockMargin(0, 0, S(8), 0)
	return frame
end

function LMNT.UI.Confirm(title, text, okText, onOk, variant)
	local frame, bar = dialog(title, text)

	local ok = LMNT.UI.Button(bar, okText or "OK", function()
		frame:Close()
		if onOk then onOk() end
	end, variant)
	ok:Dock(RIGHT)
	ok:SetWide(S(150))
	local cancel = LMNT.UI.Button(bar, "Abbrechen", function() frame:Close() end, "ghost")
	cancel:Dock(RIGHT)
	cancel:SetWide(S(130))
	cancel:DockMargin(0, 0, S(8), 0)
	return frame
end

function LMNT.UI.Alert(title, text)
	local frame, bar = dialog(title, text, 200)
	local ok = LMNT.UI.Button(bar, "OK", function() frame:Close() end)
	ok:Dock(RIGHT)
	ok:SetWide(S(130))
	return frame
end

------------------------------------------------------------------------
-- Toasts (unten rechts) und große Ankündigung (LMNT.Announce auf dem Server)
------------------------------------------------------------------------

local toasts = {}

function LMNT.UI.Toast(text, color, seconds)
	table.insert(toasts, 1, { text = text, color = color or col.primary, start = CurTime(), duration = seconds or 4 })
	if #toasts > 5 then table.remove(toasts) end
end

local announce

net.Receive("lmnt_announce", function()
	announce = {
		text = net.ReadString(),
		color = net.ReadColor(),
		start = CurTime(),
		duration = net.ReadFloat(),
	}
	surface.PlaySound("buttons/blip1.wav")
end)

hook.Add("HUDPaint", "LMNT.UI.Overlays", function()
	-- Toasts
	local y = ScrH() - S(120)
	for i = #toasts, 1, -1 do
		local t = toasts[i]
		local age = CurTime() - t.start
		if age > t.duration then
			table.remove(toasts, i)
		end
	end
	for _, t in ipairs(toasts) do
		local age = CurTime() - t.start
		local a = math.Clamp(math.min(age * 6, (t.duration - age) * 3), 0, 1)
		surface.SetFont("LMNT.Body")
		local tw, th = surface.GetTextSize(t.text)
		local w, h = tw + S(36), th + S(18)
		local x = ScrW() - w - S(24) + (1 - a) * S(40)
		y = y - h - S(8)
		draw.RoundedBox(S(6), x, y, w, h, alpha(col.bg, 240 * a))
		surface.SetDrawColor(t.color.r, t.color.g, t.color.b, 255 * a)
		surface.DrawRect(x, y, S(3), h)
		draw.SimpleText(t.text, "LMNT.Body", x + S(18), y + h / 2, alpha(col.text, 255 * a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	-- Große Ankündigung
	if not announce then return end
	local t = CurTime() - announce.start
	if t > announce.duration then announce = nil return end

	local a = math.Clamp(math.min(t * 4, (announce.duration - t) * 2), 0, 1)
	surface.SetFont("LMNT.Display")
	local tw, th = surface.GetTextSize(announce.text)
	local w, h = tw + S(80), th + S(46)
	local x, yy = ScrW() / 2 - w / 2, ScrH() * 0.2

	draw.RoundedBox(S(8), x, yy, w, h, alpha(col.bg, 235 * a))
	surface.SetDrawColor(announce.color.r, announce.color.g, announce.color.b, 255 * a)
	surface.DrawRect(x, yy, w, S(3))
	draw.SimpleText("ANKÜNDIGUNG", "LMNT.Label", ScrW() / 2, yy + S(16), alpha(col.primary, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(announce.text, "LMNT.Display", ScrW() / 2, yy + h / 2 + S(8), alpha(col.white, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)
