--- @ignore
--[[
	LMNT-HUD – Rundenstatus und Timer (Typ tttroundinfo), oben mittig

	Erbt von pure_skin_roundinfo: Initialize, PerformLayout (Skalierung, ruft die Kinder auf),
	IsResizable. Eltern von lmnt_teamindicator (links) und lmnt_miniscoreboard (rechts), beide
	erben den Rahmen (InheritParentBorder), deshalb zeichnet dieses Element Rahmen und Akzentbalken
	über die ganze Leiste.

	Sichtbarkeit: Zeitlogik 1:1 aus pure_skin_roundinfo. Im Haste-Modus sehen nur allwissende Rollen
	(ROLE.isOmniscientRole) und Nicht-Aktive die echte Restzeit, im Wechsel und rot markiert.
]]

local base = "pure_skin_roundinfo"

DEFINE_BASECLASS(base)

HUDELEMENT.Base = base

-- Wie pure_skin_roundinfo: Admin kann es abschalten (ConVar ttt2_elem_toggled_lmnt_roundinfo,
-- angelegt in sv_main.lua:378-398), und es ist nur im erzwingenden HUD nutzbar.
HUDELEMENT.togglable = true
HUDELEMENT.disabledUnlessForced = true

if not CLIENT then return end

local D -- Zeichner (lmnt_element)
local TryT = LANG.TryTranslation

local const_defaults = {
	basepos = { x = 0, y = 0 },
	size = { w = 128, h = 60 },
	minsize = { w = 128, h = 60 },
}

function HUDELEMENT:GetDefaults()
	const_defaults.basepos = {
		x = math.Round(ScrW() * 0.5 - self.size.w * 0.5),
		y = 8 * self.scale,
	}

	return const_defaults
end

function HUDELEMENT:Draw()
	D = D or hudelements.GetStored("lmnt_element")

	local C = D:Colors()
	local client = LocalPlayer()
	local x, y, w, h = self.pos.x, self.pos.y, self.size.w, self.size.h
	local s = self.scale
	local textCol, mutedCol = D:TextColors(self.basecolor)
	local roundState = gameloop.GetRoundState()

	D:Panel(x, y, w, h, self.basecolor)

	local isHaste = gameloop.IsHasteMode() and roundState == ROUND_ACTIVE
	local rd = client:GetSubRoleData()
	local isOmniscient = not client:IsActive() or (rd and rd.isOmniscientRole)
	local endtime = gameloop.GetPhaseEnd() - CurTime()
	local text
	local font = "display"
	local color = textCol

	if isHaste then
		local hastetime = gameloop.GetHasteEnd() - CurTime()

		if hastetime < 0 then
			if not isOmniscient or math.ceil(CurTime()) % 7 <= 2 then
				-- Unschuldige oder Blinkphase: "Verlängerung"
				text = D:Upper(TryT("overtime"))
				font = "title"
			else
				-- allwissende Rolle: echte Restzeit
				text = util.SimpleTime(math.max(0, endtime), "%02i:%02i")
				color = C.acid
			end
		else
			-- Startphase des Haste-Modus
			local t = hastetime

			if isOmniscient and math.ceil(CurTime()) % 6 < 2 then
				t = endtime
				color = C.acid
			end

			text = util.SimpleTime(math.max(0, t), "%02i:%02i")
		end
	else
		text = util.SimpleTime(math.max(0, endtime), "%02i:%02i")
	end

	local label = D:Upper(isHaste and TryT("hastemode") or TryT(self.roundstate_string[roundState] or ""))
	local cx = x + w * 0.5
	local maxW = w - 16 * s

	D:Text(label, "label", cx, y + 18 * s, mutedCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, D:FitScale(label, "label", maxW, s))
	D:Text(text, font, cx, y + 39 * s, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, D:FitScale(text, font, maxW, s))

	-- Rahmen und Akzentbalken über Rundeninfo samt Kindern. Die Kinder sind zu diesem Zeitpunkt
	-- schon gezeichnet (hud_base DrawElemAndChildren: erst Kinder, dann Eltern).
	local bpos, bsize = self:GetBorderParams()

	D:Outline(bpos.x, bpos.y, bsize.w, bsize.h)
	D:Accent(bpos.x, bpos.y, bsize.w, s)
end
