--- @ignore
--[[
	LMNT-HUD – abstraktes Basiselement mit den Zeichenhelfern im LMNT-Design (05_DESIGNSYSTEM.md)

	Ladepfad: terrortown/gamemode/shared/hud_elements/base_elements/ (TTT2 0.14.6b,
	sh_hudelement_module.lua:2 und :50). Dateien dort bekommen keinen Typ und werden nie selbst
	gezeichnet. Die Datei läuft auf Server und Client (sh_hudelement_module.lua:46), Zeichencode
	steht deshalb hinter "if not CLIENT then return end".

	Nutzung durch die LMNT-Elemente:
	  - als Basis:    HUDELEMENT.Base = "lmnt_element" (lmnt_weaponinfo)
	  - als Zeichner: hudelements.GetStored("lmnt_element"), wenn das Element von einem pure_skin-Element
	    erbt (gleiches Muster wie pure_skin_wswitch mit self.drawer)
	Alle Helfer sind zustandslos: Position, Größe und Skalierung kommen als Parameter.
]]

local base = "pure_skin_element"

DEFINE_BASECLASS(base)

HUDELEMENT.Base = base

if not CLIENT then return end

------------------------------------------------------------------------
-- Farb-Tokens: aus LMNT.Config.Colors (lmnt_core), sonst die Werte aus 05_DESIGNSYSTEM.md
------------------------------------------------------------------------

local cfg = LMNT and LMNT.Config and LMNT.Config.Colors or {}

local function token(key, r, g, b, a)
	local c = cfg[key]
	if istable(c) and c.r then
		return Color(c.r, c.g, c.b, a or c.a or 255)
	end
	return Color(r, g, b, a or 255)
end

local C = {
	ink      = token("bg", 8, 7, 12, 255),     -- Ink #08070c
	inkSoft  = token("panel", 17, 16, 24),     -- Ink-Soft #111018
	raised   = token("panel2", 28, 26, 37),    -- erhöhte Fläche
	line     = token("line", 255, 255, 255, 36),
	paper    = token("text", 242, 239, 232),   -- Primärtext
	white    = token("white", 255, 253, 248),
	muted    = token("muted", 165, 161, 172),  -- Labels, Sekundärtext
	acid     = token("primary", 255, 49, 49),  -- Akzent, Fortschritt
	deep     = token("deep", 168, 0, 22),      -- Dunkelrot
	good     = token("good", 55, 230, 107),
	warn     = token("warn", 255, 176, 32),
	info     = token("info", 127, 180, 255),
	success  = Color(30, 150, 70),             -- wie LMNT.UI.Button "success"
	track    = Color(255, 255, 255, 22),       -- leerer Teil von Balken
	-- Text auf hellen Grundfarben (falls ein Spieler die HUD-Grundfarbe hell einstellt)
	inkText  = Color(8, 7, 12),
	inkMuted = Color(70, 66, 78),
}

---
-- Farb-Tokens (nicht verändern, die Tabelle wird von allen LMNT-Elementen geteilt)
-- @return table
-- @realm client
function HUDELEMENT:Colors()
	return C
end

---
-- Textfarben passend zur Grundfarbe, gleiche Schwelle wie util.GetDefaultColor
-- @param Color bg
-- @return Color, Color primär, sekundär
-- @realm client
function HUDELEMENT:TextColors(bg)
	if bg.r + bg.g + bg.b < 500 then
		return C.paper, C.muted
	end
	return C.inkText, C.inkMuted
end

------------------------------------------------------------------------
-- Schriften
------------------------------------------------------------------------

--[[
	Bevorzugt die LMNT-Schriften aus lmnt_core/lua/lmnt/core/cl_ui.lua. Sie sind dort mit
	LMNT.UI.Scale(px) bereits auf die Bildschirmhöhe (Basis 1080p) skaliert. Fehlt lmnt_core,
	werden einmalig eigene Ersatzschriften in 1080p-Größe angelegt (Roboto, Teil von GMod).
	Die Element-Skalierung (HUD-Editor, appearance.GetGlobalScale) wird beim Zeichnen über
	draw.AdvancedText angewendet. Es entsteht keine Schrift pro Frame.
]]
local FONTS = {
	display = { lmnt = "LMNT.Display",  size = 26, weight = 900 },
	title   = { lmnt = "LMNT.Title",    size = 20, weight = 900 },
	bold    = { lmnt = "LMNT.BodyBold", size = 17, weight = 700 },
	small   = { lmnt = "LMNT.Small",    size = 14, weight = 400 },
	label   = { lmnt = "LMNT.Label",    size = 13, weight = 700 },
}

local brandFonts -- nil = noch nicht entschieden, true = LMNT-Schriften, false = Ersatzschriften
local unitH, units = -1, {}

local function resolveFonts()
	if brandFonts ~= nil then return end

	brandFonts = LMNT ~= nil and LMNT.UI ~= nil and isfunction(LMNT.UI.Scale)

	for key, spec in pairs(FONTS) do
		if brandFonts then
			spec.name = spec.lmnt
		else
			spec.name = "LMNT.HUD." .. key
			surface.CreateFont(spec.name, { font = "Roboto", size = spec.size, weight = spec.weight, extended = true })
		end
	end
end

-- Verhältnis tatsächliche Schriftgröße zu 1080p-Größe. Neu berechnet nur bei geänderter Bildschirmhöhe
-- (cl_ui.lua erzeugt die LMNT-Schriften in OnScreenSizeChanged neu).
local function fontUnit(key)
	local h = ScrH()
	if h ~= unitH then
		unitH = h
		for k, spec in pairs(FONTS) do
			units[k] = brandFonts and LMNT.UI.Scale(spec.size) / spec.size or 1
		end
	end
	return units[key]
end

---
-- Name der GMod-Schrift zu einem Schlüssel (display, title, bold, small, label)
-- @param string key
-- @return string
-- @realm client
function HUDELEMENT:Font(key)
	resolveFonts()
	return FONTS[key].name
end

---
-- Textskalierung für draw.AdvancedText, damit Text mit dem Element skaliert
-- @param string key Schriftschlüssel
-- @param number scale Element-Skalierung
-- @return number
-- @realm client
function HUDELEMENT:TextScale(key, scale)
	resolveFonts()

	local s = (scale or 1) / fontUnit(key)

	-- Rundungsreste der Schriftgröße nicht per Matrix skalieren, das wäre nur unscharf
	if s > 0.97 and s < 1.03 then
		s = 1
	end

	return s
end

---
-- Zeichnet Text in einer LMNT-Schrift
-- @realm client
function HUDELEMENT:Text(text, key, x, y, color, xalign, yalign, scale, shadow)
	local s = self:TextScale(key, scale)
	draw.AdvancedText(text, FONTS[key].name, x, y, color, xalign, yalign, shadow or false, s)
end

---
-- Größe eines Textes nach Skalierung
-- @return number, number Breite, Höhe
-- @realm client
function HUDELEMENT:TextSize(text, key, scale)
	local s = self:TextScale(key, scale)
	surface.SetFont(FONTS[key].name)
	local w, h = surface.GetTextSize(text)
	return w * s, h * s
end

---
-- Skalierung <= scale, mit der text höchstens maxW breit ist (mindestens 60 % von scale)
-- @realm client
function HUDELEMENT:FitScale(text, key, maxW, scale)
	local w = self:TextSize(text, key, scale)
	if w <= maxW or w <= 0 then
		return scale
	end
	return math.max(scale * 0.6, scale * maxW / w)
end

---
-- Kürzt Text mit "..." auf maxW (TTT2 draw.GetLimitedLengthText). Ergebnis zwischenspeichern!
-- @realm client
function HUDELEMENT:Limit(text, key, maxW, scale)
	return draw.GetLimitedLengthText(text, maxW, self:Font(key), "...", self:TextScale(key, scale))
end

------------------------------------------------------------------------
-- Großbuchstaben (Labels laut Designsystem). string.upper kennt keine Umlaute, deshalb werden
-- die UTF-8-Kleinbuchstaben U+00E0–U+00FE (ohne ÷) zusätzlich umgesetzt. Ergebnis zwischengespeichert.
------------------------------------------------------------------------

local function upperLatin1(c)
	local b = string.byte(c)
	if b == 0xB7 then return nil end -- ÷ ist kein Buchstabe
	return "\195" .. string.char(b - 32)
end

local upperCache, upperCount = {}, 0

---
-- @param string str
-- @return string
-- @realm client
function HUDELEMENT:Upper(str)
	str = tostring(str)

	local u = upperCache[str]
	if u then return u end

	u = (string.gsub(string.upper(str), "\195([\160-\190])", upperLatin1))

	if upperCount >= 512 then
		upperCache, upperCount = {}, 0
	end
	upperCache[str] = u
	upperCount = upperCount + 1

	return u
end

------------------------------------------------------------------------
-- Flächen
------------------------------------------------------------------------

local function setColor(c, a)
	surface.SetDrawColor(c.r, c.g, c.b, a or c.a or 255)
end

---
-- Gefülltes Rechteck
-- @realm client
function HUDELEMENT:Rect(x, y, w, h, color, a)
	setColor(color, a)
	surface.DrawRect(x, y, w, h)
end

---
-- 1-px-Rahmen in der Linienfarbe (rgba 255,255,255,.14)
-- @realm client
function HUDELEMENT:Outline(x, y, w, h, a)
	setColor(C.line, a)
	surface.DrawOutlinedRect(x, y, w, h, 1)
end

---
-- Fläche mit Rahmen (Ink-Fläche, Farbe = HUD-Grundfarbe)
-- @realm client
function HUDELEMENT:Panel(x, y, w, h, fill)
	self:Rect(x, y, w, h, fill)
	self:Outline(x, y, w, h)
end

---
-- Roter Akzentbalken oben (wie die Kopfzeile von LMNT.UI.Frame)
-- @return number Höhe des Balkens
-- @realm client
function HUDELEMENT:Accent(x, y, w, scale, color)
	local h = math.max(2, math.Round(3 * (scale or 1)))
	self:Rect(x, y, w, h, color or C.acid)
	return h
end

---
-- Fortschrittsbalken: leerer Teil in track, gefüllter Teil in color
-- @param number frac 0..1
-- @param[opt] number a Alpha des gefüllten Teils (z. B. Pulsieren)
-- @realm client
function HUDELEMENT:Bar(x, y, w, h, color, frac, a)
	self:Rect(x, y, w, h, C.track)

	local fw = math.Round(w * math.Clamp(frac or 0, 0, 1))
	if fw > 0 then
		self:Rect(x, y, fw, h, color, a)
	end
end

------------------------------------------------------------------------
-- Texte der LMNT-Elemente (Labels in Großbuchstaben). TTT2 erlaubt Ergänzungen außerhalb der
-- Sprachdateien (cl_lang.lua: LANG.GetLanguageTableReference), so nutzen es auch lmnt_ttt/lang.
------------------------------------------------------------------------

local strings = {
	en = {
		lmnt_hud_role = "ROLE",
		lmnt_hud_watching = "SPECTATING",
		lmnt_hud_status = "STATUS",
		lmnt_hud_health = "HEALTH",
		lmnt_hud_credits = "CREDITS",
		lmnt_hud_weapon = "WEAPON",
		lmnt_hud_ammo = "AMMO",
	},
	de = {
		lmnt_hud_role = "ROLLE",
		lmnt_hud_watching = "BEOBACHTET",
		lmnt_hud_status = "STATUS",
		lmnt_hud_health = "LEBEN",
		lmnt_hud_credits = "CREDITS",
		lmnt_hud_weapon = "WAFFE",
		lmnt_hud_ammo = "MUNITION",
	},
}

for lang, tbl in pairs(strings) do
	local L = LANG.GetLanguageTableReference(lang)
	for key, text in pairs(tbl) do
		L[key] = text
	end
end
