--- @ignore
--[[
	LMNT-HUD – Spielerbox (Typ tttinfopanel = Ordnername): Rolle, Team, Leben, Rüstung, Ausdauer, Credits

	Erbt von pure_skin_playerinfo: Initialize, PerformLayout (Skalierung = min(Breite/Mindestbreite,
	Höhe/Mindesthöhe)), GetSavingKeys (Lebensleiste pulsieren, Teamname anzeigen),
	SetSecondaryRoleInfoFunction und IsResizable. Ersetzt werden nur Darstellung und Standardposition.
	Munition steht in der eigenen Box lmnt_weaponinfo.

	Sichtbarkeit (wie pure_skin_playerinfo):
	  - Rolle, Rollenfarbe und Team nur von sich selbst und nur bei client:IsActive()
	  - beim Zuschauen nur der Name des beobachteten Spielers, nie dessen Rolle
	  - Credits nur für Shop-Rollen (client:IsShopper(), nur aktiv)
]]

local base = "pure_skin_playerinfo"

DEFINE_BASECLASS(base)

HUDELEMENT.Base = base

-- Nur im HUD lmnt nutzbar, andere HUDs greifen sonst per Fallback zu (hud_base CanUseElement)
HUDELEMENT.disabledUnlessForced = true

if not CLIENT then return end

local D -- Zeichner (lmnt_element), beim ersten Zeichnen aufgelöst
local TryT = LANG.TryTranslation

-- Maße in px bei Skalierung 1
local LPW = 48      -- Rollenspalte
local PAD = 12
local HEADER = 48   -- Akzentbalken + Kopfzeile
local ICON = 30
local BAR_H = 10
local SPRINT_H = 4

local watching_icon = Material("vgui/ttt/watching_icon")
local icon_armor = Material("vgui/ttt/hud_armor.vmt")
local icon_armor_rei = Material("vgui/ttt/hud_armor_reinforced.vmt")

local const_defaults = {
	basepos = { x = 0, y = 0 },
	size = { w = 330, h = 104 },
	minsize = { w = 250, h = 104 },
}

---
-- Standardposition unten links. Wird vom HUD-Editor beim Zurücksetzen genutzt
-- (hud_element_base Reset, scalable_hud ApplyScale), deshalb aus aktueller Größe und Skalierung.
-- @realm client
function HUDELEMENT:GetDefaults()
	const_defaults.basepos = {
		x = 10 * self.scale,
		y = ScrH() - (10 * self.scale + self.size.h),
	}

	return const_defaults
end

-- Zusatzinfo von Rollen-Addons. Die meisten registrieren sie direkt an pure_skin_playerinfo,
-- deshalb wird dort nachgesehen, wenn an diesem Element keine gesetzt ist.
local function secondaryInfoFunc(self)
	if isfunction(self.secondaryRoleInformationFunc) then
		return self.secondaryRoleInformationFunc
	end

	local ps = hudelements.GetStored("pure_skin_playerinfo")
	if ps and isfunction(ps.secondaryRoleInformationFunc) then
		return ps.secondaryRoleInformationFunc
	end
end

function HUDELEMENT:Draw()
	D = D or hudelements.GetStored("lmnt_element")

	local C = D:Colors()
	local client = LocalPlayer()
	local calive = client:Alive() and client:IsTerror()
	local cactive = client:IsActive()

	local s = self.scale
	local x, y, w, h = self.pos.x, self.pos.y, self.size.w, self.size.h
	local bg = self.basecolor
	local textCol, mutedCol = D:TextColors(bg)
	local lpw, pad, header = LPW * s, PAD * s, HEADER * s

	-- Tot oder Zuschauer: nur die Kopfzeile, am unteren Rand (wie pure_skin)
	if not calive then
		y = y + h - header
		h = header
	end

	D:Panel(x, y, w, h, bg)

	-- Rollenspalte: Rollenfarbe bleibt spielrelevant. Ohne aktive Rolle die TTT2-Zuschauerfarbe.
	local roleColor = cactive and client:GetRoleColor() or COLOR_SPEC
	D:Rect(x, y, lpw, h, roleColor)

	local accentH = D:Accent(x, y, w, s)

	local rd = client:GetSubRoleData()
	local tgt = client:GetObserverTarget()
	local watching = not cactive and IsValid(tgt) and tgt:IsPlayer()

	local icon
	if cactive and rd then
		icon = rd.iconMaterial
	elseif watching then
		icon = watching_icon
	end

	if icon then
		local is = ICON * s
		draw.FilteredTexture(
			x + (lpw - is) * 0.5,
			y + accentH + (header - accentH - is) * 0.5,
			is,
			is,
			icon,
			255,
			util.GetDefaultColor(roleColor)
		)
	end

	-- Kopfzeile: Label + Titel
	local label, title

	if cactive and rd then
		label = TryT("lmnt_hud_role")
		if self.showTeamName then
			label = label .. " / " .. D:Upper(TryT(client:GetTeam()))
		end
		title = D:Upper(TryT(rd.name))
	elseif watching then
		label = TryT("lmnt_hud_watching")
		title = tgt:Nick()
	else
		label = TryT("lmnt_hud_status")
		title = D:Upper(TryT(self.roundstate_string[gameloop.GetRoundState()] or ""))
	end

	local right = x + w - pad

	-- Credits nur für Shop-Rollen
	if cactive and client:IsShopper() then
		local credits = client:GetCredits()
		local creditsLabel = TryT("lmnt_hud_credits")

		D:Text(creditsLabel, "label", right, y + 17 * s, mutedCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, s)
		D:Text(tostring(credits), "title", right, y + 34 * s, credits > 0 and C.acid or mutedCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, s)

		right = right - math.max(D:TextSize(creditsLabel, "label", s), 24 * s) - pad
	end

	-- Zusatzinfo der Rolle (Schnittstelle von pure_skin_playerinfo: { text, color } oder nil)
	local sriFn = cactive and secondaryInfoFunc(self)
	local sri = sriFn and sriFn()

	if sri and sri.text and sri.color then
		local text = D:Upper(sri.text)
		local cw = D:TextSize(text, "label", s) + 12 * s
		local ch = 20 * s
		local cx = right - cw
		local cy = y + accentH + (header - accentH - ch) * 0.5

		D:Rect(cx, cy, cw, ch, sri.color)
		D:Text(text, "label", cx + cw * 0.5, cy + ch * 0.5, util.GetDefaultColor(sri.color), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, s)

		right = cx - pad
	end

	local nx = x + lpw + pad
	local maxW = right - nx

	D:Text(label, "label", nx, y + 17 * s, mutedCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, D:FitScale(label, "label", maxW, s))
	D:Text(title, "title", nx, y + 34 * s, textCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, D:FitScale(title, "title", maxW, s))

	if not calive then return end

	-- Trennlinie unter der Kopfzeile
	D:Rect(x + lpw, y + header, w - lpw, 1, C.line)

	local bw = x + w - pad - nx

	-- Leben (Pulsieren unter 25 % wie pure_skin, schaltbar über GetSavingKeys)
	local health = math.max(0, client:Health())
	local maxHealth = math.max(1, client:GetMaxHealth())
	local low = health <= maxHealth * 0.25
	local alpha = 255

	if low and self.healthPulsate then
		local frequency = util.TransformToRange(health, 1, maxHealth * 0.25 + 1, 1, 6)
		alpha = math.Round(math.abs(math.sin(CurTime() * (7 - frequency))) * 255)
	end

	local rowY = y + header + 14 * s
	local hpText = tostring(health)
	local hpW = D:TextSize(hpText, "bold", s)

	D:Text(TryT("lmnt_hud_health"), "label", nx, rowY, mutedCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, s)
	D:Text(hpText, "bold", nx + bw, rowY, low and C.acid or textCol, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, s)

	-- Rüstung nur mit dynamischer Rüstung (wie pure_skin)
	local armor = client:GetArmor()

	if GetGlobalBool("ttt_armor_dynamic", false) and armor > 0 then
		local armorText = tostring(armor)
		local ax = nx + bw - hpW - 14 * s
		local aw = D:TextSize(armorText, "bold", s)
		local is = 14 * s

		D:Text(armorText, "bold", ax, rowY, C.info, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, s)
		draw.FilteredTexture(
			ax - aw - 4 * s - is,
			rowY - is * 0.5,
			is,
			is,
			client:ArmorIsReinforced() and icon_armor_rei or icon_armor,
			255,
			C.info
		)
	end

	local barY = y + header + 24 * s
	D:Bar(nx, barY, bw, BAR_H * s, C.acid, health / maxHealth, alpha)

	-- Ausdauer nur, wenn Sprinten auf dem Server aktiv ist
	if SPRINT and SPRINT.convars.enabled:GetBool() then
		D:Bar(nx, barY + (BAR_H + 6) * s, bw, SPRINT_H * s, C.info, client:GetSprintStamina())
	end
end
