--- @ignore
--[[
	LMNT-HUD – Teamanzeige (Typ tttteamindicator), Kind von lmnt_roundinfo, links daneben

	Erbt von pure_skin_teamindicator: Initialize, PerformLayout (Quadrat in Höhe des Elternelements),
	ShouldDraw (nur ROUND_ACTIVE), InheritParentBorder, GetDefaults.
	Muss neben lmnt_roundinfo existieren: pure_skin_teamindicator hängt an pure_skin_roundinfo und wäre
	im HUD lmnt nicht nutzbar (hud_base CanUseElement prüft das Elternelement).

	Sichtbarkeit: nur das eigene Team (client:GetTeam()), Tote und Zuschauer sehen das Zuschauer-Symbol.
]]

local base = "pure_skin_teamindicator"

DEFINE_BASECLASS(base)

HUDELEMENT.Base = base

HUDELEMENT.togglable = true
HUDELEMENT.disabledUnlessForced = true

if not CLIENT then return end

local D -- Zeichner (lmnt_element)
local PAD = 10

local material_watching = Material("vgui/ttt/watching_icon")

---
-- Eigenes Elternelement. BaseClass.PreInitialize wird bewusst nicht aufgerufen, sonst hinge sich
-- dieses Element zusätzlich an pure_skin_roundinfo.
-- @realm client
function HUDELEMENT:PreInitialize()
	hudelements.RegisterChildRelation(self.id, "lmnt_roundinfo", false)
end

function HUDELEMENT:Draw()
	D = D or hudelements.GetStored("lmnt_element")

	local client = LocalPlayer()
	local x, y, w, h = self.pos.x, self.pos.y, self.size.w, self.size.h
	local s = self.scale

	D:Panel(x, y, w, h, self.basecolor)

	local tm = TEAMS[client:GetTeam()]
	local icon, c

	if client:Alive() and client:IsTerror() and tm then
		icon = tm.iconMaterial
		c = tm.color or COLOR_BLACK
	else
		icon = material_watching
		c = COLOR_SPEC
	end

	local pad = PAD * s
	local size = h - pad * 2

	D:Rect(x + pad, y + pad, size, size, c)

	if icon then
		draw.FilteredTexture(x + pad, y + pad, size, size, icon, 255, util.GetDefaultColor(c))
	end
end
