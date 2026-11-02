--- @ignore
--[[
	LMNT-HUD – Waffenwechsel-Liste (Typ tttwswitch), unten rechts über lmnt_weaponinfo

	Erbt von pure_skin_wswitch: PreInitialize, Initialize (WSWITCH:UpdateWeaponCache), ShouldDraw
	(nur beim Wechseln oder im Editor), IsResizable (nur Breite) und DrawElement, das die hier
	ersetzten DrawBarBg/DrawWeapon aufruft. Gestapelt wird von base_stacking_element (wächst nach oben).

	Sichtbarkeit: nur das eigene Inventar (WSWITCH.WeaponCache). Der Farbstreifen ist die eigene
	Rollenfarbe, ohne aktive Rolle die TTT2-Zuschauerfarbe (wie pure_skin).
]]

local base = "pure_skin_wswitch"

DEFINE_BASECLASS(base)

HUDELEMENT.Base = base

HUDELEMENT.disabledUnlessForced = true

if not CLIENT then return end

local D -- Zeichner (lmnt_element)
local TryT = LANG.TryTranslation

local ELEMENT_HEIGHT = 30
local MARGIN = 4
local LPW = 30 -- Farbstreifen mit Slot-Nummer
local WEAPONINFO_H = 70 -- Standardhöhe von lmnt_weaponinfo, die Liste endet knapp darüber

local const_defaults = {
	basepos = { x = 0, y = 0 },
	size = { w = 260, h = 30 },
	minsize = { w = 200, h = 30 },
}

-- Zeichenfunktion des Stapel-Elements direkt, weil pure_skin_wswitch:Draw jeden Frame eine neue
-- Tabelle anlegt. baseclass.Get liefert dieselbe Tabelle wie DEFINE_BASECLASS.
local stackingBase = baseclass.Get("base_stacking_element")
local rows = {}
local specDark

function HUDELEMENT:GetDefaults()
	const_defaults.basepos = {
		x = ScrW() - (self.size.w + 10 * self.scale),
		y = ScrH() - (10 + WEAPONINFO_H + 8) * self.scale,
	}

	return const_defaults
end

function HUDELEMENT:PerformLayout()
	-- pure_skin_wswitch: Skalierung = appearance.GetGlobalScale(), Grundfarbe
	BaseClass.PerformLayout(self)

	self.element_height = ELEMENT_HEIGHT * self.scale
	self.margin = MARGIN * self.scale
	self.lpw = LPW * self.scale
end

function HUDELEMENT:DrawBarBg(x, y, w, h, selected)
	D = D or hudelements.GetStored("lmnt_element")

	local C = D:Colors()
	local client = LocalPlayer()
	local c

	if client:IsActive() then
		c = selected and client:GetRoleColor() or client:GetRoleDkColor()
	else
		specDark = specDark or util.ColorDarken(COLOR_SPEC, 30)
		c = selected and COLOR_SPEC or specDark
	end

	D:Panel(x, y, w, h, selected and C.raised or self.basecolor)
	D:Rect(x, y, self.lpw, h, c)

	-- aktive Zeile: Akzent in acid (Designsystem: aktiv = acid)
	if selected then
		D:Rect(x + self.lpw, y, math.max(2, math.Round(2 * self.scale)), h, C.acid)
	end

	return c
end

function HUDELEMENT:DrawWeapon(x, y, selected, wep, tip_color)
	if not IsValid(wep) or not IsValid(wep.Owner) or not isfunction(wep.Owner.GetAmmoCount) then
		return false
	end

	local C = D:Colors()
	local s = self.scale
	local cy = y + self.element_height * 0.5
	local textCol, mutedCol = D:TextColors(selected and C.raised or self.basecolor)
	local nameCol = selected and textCol or mutedCol

	-- Slot
	D:Text(tostring(MakeKindValid(wep.Kind)), "bold", x + self.lpw * 0.5, cy, util.GetDefaultColor(tip_color), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, s)

	-- Name
	D:Text(D:Upper(TryT(wep:GetPrintName() or wep.PrintName or "...")), "bold", x + self.lpw + 10 * s, cy, nameCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, s)

	-- Munition: Clip1 ist -1 bei Nahkampfwaffen, Ammo1 false ohne Besitzer (wie pure_skin)
	local cl1, am1 = wep:Clip1(), (wep.Ammo1 and wep:Ammo1() or false)

	if cl1 ~= -1 and am1 ~= false then
		local empty = cl1 == 0 and am1 == 0

		D:Text(Format("%i / %i", cl1, am1), "bold", x + self.size.w - 10 * s, cy, empty and C.acid or nameCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, s)
	end

	return true
end

function HUDELEMENT:Draw()
	D = D or hudelements.GetStored("lmnt_element")

	local count = #WSWITCH.WeaponCache

	for i = 1, count do
		local row = rows[i]
		if not row then
			row = {}
			rows[i] = row
		end
		row.h = self.element_height
	end

	for i = #rows, count + 1, -1 do
		rows[i] = nil
	end

	self:SetElements(rows)
	self:SetElementMargin(self.margin)

	stackingBase.Draw(self)
end
