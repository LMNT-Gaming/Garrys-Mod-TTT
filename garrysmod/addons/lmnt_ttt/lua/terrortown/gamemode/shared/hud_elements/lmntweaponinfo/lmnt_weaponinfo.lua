--- @ignore
--[[
	LMNT-HUD – aktive Waffe und Munition, unten rechts

	Eigener Elementtyp "lmntweaponinfo" (= Ordnername). TTT2 behandelt jeden Unterordner von
	hud_elements/ als Typ (sh_hudelement_module.lua:31-52). Andere HUDs zeigen ihn nicht, weil das
	Element nur erzwungen nutzbar ist (disabledUnlessForced).
	Logik wie die Munitionsleiste in pure_skin_playerinfo (GetAmmo): Clip1, Ammo1, Primary.ClipSize,
	Nahkampfwaffen (Clip1 == -1) ohne Munitionsanzeige.

	Sichtbarkeit: nur die eigene aktive Waffe, nur lebend. Im HUD-Editor immer (Platzhalter), damit
	sich das Element verschieben lässt (cl_hud_editor.lua TryMoveLocalHUD prüft ShouldDraw).
]]

local base = "lmnt_element"

DEFINE_BASECLASS(base)

HUDELEMENT.Base = base

HUDELEMENT.disabledUnlessForced = true

if not CLIENT then return end

local TryT = LANG.TryTranslation

local PAD = 12

local const_defaults = {
	basepos = { x = 0, y = 0 },
	size = { w = 260, h = 70 },
	minsize = { w = 200, h = 70 },
}

-- gekürzter Anzeigename, neu berechnet nur bei anderer Waffe, Breite oder Skalierung
local nameCache = { wep = nil, maxW = -1, scale = -1, text = "" }

function HUDELEMENT:Initialize()
	self.scale = 1.0
	self.basecolor = self:GetHUDBasecolor()

	BaseClass.Initialize(self)
end

function HUDELEMENT:IsResizable()
	return true, true
end

function HUDELEMENT:GetDefaults()
	const_defaults.basepos = {
		x = ScrW() - (10 * self.scale + self.size.w),
		y = ScrH() - (10 * self.scale + self.size.h),
	}

	return const_defaults
end

---
-- Skalierung wie pure_skin_playerinfo: min(Breite/Mindestbreite, Höhe/Mindesthöhe)
-- @realm client
function HUDELEMENT:PerformLayout()
	local defaults = self:GetDefaults()

	self.basecolor = self:GetHUDBasecolor()
	self.scale = math.min(self.size.w / defaults.minsize.w, self.size.h / defaults.minsize.h)

	BaseClass.PerformLayout(self)
end

function HUDELEMENT:ShouldDraw()
	if HUDEditor.IsEditing then
		return true
	end

	local client = LocalPlayer()

	return client:Alive() and client:IsTerror() and IsValid(client:GetActiveWeapon())
end

local function weaponName(self, wep, maxW, s)
	if nameCache.wep ~= wep or nameCache.maxW ~= maxW or nameCache.scale ~= s then
		local name = self:Upper(TryT(wep:GetPrintName() or wep.PrintName or "..."))

		nameCache.wep = wep
		nameCache.maxW = maxW
		nameCache.scale = s
		nameCache.text = self:Limit(name, "title", maxW, s)
	end

	return nameCache.text
end

function HUDELEMENT:Draw()
	local C = self:Colors()
	local client = LocalPlayer()
	local x, y, w, h = self.pos.x, self.pos.y, self.size.w, self.size.h
	local s = self.scale
	local pad = PAD * s
	local textCol, mutedCol = self:TextColors(self.basecolor)
	local left, right = x + pad, x + w - pad

	self:Panel(x, y, w, h, self.basecolor)
	self:Accent(x, y, w, s)
	self:Text(TryT("lmnt_hud_weapon"), "label", left, y + 17 * s, mutedCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, s)

	local wep = client:GetActiveWeapon()

	if not IsValid(wep) or not client:Alive() then
		-- nur im HUD-Editor erreichbar (siehe ShouldDraw)
		self:Text("-", "title", left, y + 40 * s, mutedCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, s)

		return
	end

	local clip = wep:Clip1() or -1
	local ammoW = 0

	if clip ~= -1 then
		local reserve = wep.Ammo1 and wep:Ammo1() or 0
		local maxClip = wep.Primary and wep.Primary.ClipSize or 0
		local empty = clip == 0 and reserve == 0

		local reserveText = "/ " .. reserve
		local clipText = tostring(clip)
		local rw = self:TextSize(reserveText, "bold", s)
		local cw = self:TextSize(clipText, "display", s)

		self:Text(TryT("lmnt_hud_ammo"), "label", right, y + 17 * s, mutedCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, s)
		self:Text(reserveText, "bold", right, y + 42 * s, mutedCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, s)
		self:Text(clipText, "display", right - rw - 6 * s, y + 40 * s, clip == 0 and C.acid or textCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, s)

		self:Bar(left, y + h - pad - 4 * s, right - left, 4 * s, empty and C.acid or C.warn, maxClip > 0 and clip / maxClip or 0)

		ammoW = rw + 6 * s + cw + pad
	end

	self:Text(weaponName(self, wep, right - left - ammoW, s), "title", left, y + 40 * s, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, s)
end
