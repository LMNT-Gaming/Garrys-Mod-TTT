--- @ignore
--[[
	LMNT-HUD – Status-Icons und Ausrüstung (Typ tttsidebar), links mittig

	Erbt von pure_skin_sidebar: Initialize, PerformLayout (globale Skalierung, Abstand), GetDefaults,
	IsResizable (nur verschiebbar) und ShouldDraw. Draw und DrawIcon sind ersetzt: gleiche Anordnung
	(Status unten, Trenner, Items darüber, um basepos zentriert), aber ohne neue Color() pro Frame und
	ohne item.hud_color/status.hud_color zu überschreiben.

	Sichtbarkeit: nur eigene Daten (STATUS.active des Clients, client:GetEquipmentItems()).
	Beschreibung neben dem Symbol nur bei offenem Scoreboard und ttt2_hud_enable_description (wie pure_skin).
]]

local base = "pure_skin_sidebar"

DEFINE_BASECLASS(base)

HUDELEMENT.Base = base

HUDELEMENT.disabledUnlessForced = true

if not CLIENT then return end

local D -- Zeichner (lmnt_element)
local TryT = LANG.TryTranslation
local cvDescription

local GROUP_GAP = 14 -- Abstand zwischen Status und Items, mit Trennlinie

-- letzte 5 Sekunden blinken (Formel aus pure_skin_sidebar)
local function blinkFactor(item)
	if not item.displaytime then return 1 end

	local timeLeft = item.displaytime - CurTime()
	if timeLeft >= 5 then return 1 end

	return 0.5 * (math.sin(0.5 * math.pi + (-1.4 * timeLeft + 7) * math.pi) + 1)
end

-- Statusfarbe nach STATUS-Typ, eigene Farbe eines Addons nur bei Status ohne Typ
local function statusColor(status, C)
	if status.type == "bad" then return C.deep end
	if status.type == "good" then return C.success end
	if status.type == nil and istable(status.hud_color) and status.hud_color.r then return status.hud_color end

	return C.raised
end

function HUDELEMENT:DrawIcon(x, top, item, bg)
	local C = D:Colors()
	local size, s = self.size.w, self.scale
	local factor = blinkFactor(item)
	local fontColor = util.GetDefaultColor(bg)

	D:Rect(x, top, size, size, bg, math.Round(factor * (bg.a or 255)))
	D:Outline(x, top, size, size, math.Round(factor * C.line.a))

	local mat = item.hud.GetTexture and item.hud or item.hud[item.active_icon]
	if mat then
		draw.FilteredTexture(x, top, size, size, mat, fontColor.r > 60 and 200 or 250, fontColor)
	end

	-- Zusatzinfo unten rechts (z. B. Restanzahl)
	if isfunction(item.DrawInfo) then
		local info = item:DrawInfo()

		if info then
			info = TryT(tostring(info))

			local tw, th = D:TextSize(info, "label", s)
			local pad = 4 * s
			local bw, bh = tw + pad * 2, th + 2 * s
			local bx, by = x + size - bw + 2 * s, top + size - bh * 0.5

			D:Panel(bx, by, bw, bh, C.ink)
			D:Text(info, "label", bx + bw * 0.5, by + bh * 0.5, C.paper, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, s)
		end
	end

	-- Name und Beschreibung bei offenem Scoreboard
	cvDescription = cvDescription or GetConVar("ttt2_hud_enable_description")

	if GAMEMODE.ShowScoreboard and cvDescription and cvDescription:GetBool() then
		local name = item.EquipMenuData and item.EquipMenuData.name or (item.name or "")

		-- Status mit wechselnden Namen
		if istable(name) then
			name = name[item.active_icon]
		end

		local tx = x + size + self.padding

		D:Text(TryT(name or ""), "bold", tx, top - 2 * s, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, s, true)

		local desc = TryT((item.sidebarDescription or item.EquipMenuData and item.EquipMenuData.desc) or "")
		local lines = draw.GetWrappedText(desc, 285 * s, D:Font("small"), D:TextScale("small", s))
		local lineCount = #lines

		for i = 1, math.min(2, lineCount) do
			local line = lines[i]

			-- gekürzt? Dann anzeigen
			if i == 2 and lineCount > 2 then
				line = line .. " [...]"
			end

			D:Text(line, "small", tx, top + (18 + (i - 1) * 15) * s, C.paper, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, s, true)
		end
	end
end

function HUDELEMENT:Draw()
	D = D or hudelements.GetStored("lmnt_element")

	local C = D:Colors()
	local client = LocalPlayer()
	local basepos = self:GetBasePos()
	local x = basepos.x
	local size, pad = self.size.w, self.padding
	local itms = client:GetEquipmentItems()

	local numItems = 0
	for i = 1, #itms do
		local item = items.GetStored(itms[i])
		if item and item.hud then
			numItems = numItems + 1
		end
	end

	local numStatus = table.Count(STATUS.active)
	local numIcons = numItems + numStatus
	local both = numStatus > 0 and numItems > 0
	local gap = GROUP_GAP * self.scale

	local height = size
	if numIcons > 0 then
		height = numIcons * size + (numIcons - 1) * pad
		if both then
			height = height - pad + gap
		end
	end

	-- um basepos zentriert, gestapelt von unten nach oben (wie pure_skin)
	local startY = basepos.y + 0.5 * size + 0.5 * height
	local curY = startY

	for _, status in pairs(STATUS.active) do
		curY = curY - size
		self:DrawIcon(x, curY, status, statusColor(status, C))
		curY = curY - pad
	end

	if both then
		curY = curY + pad - gap
		D:Rect(x, curY + gap * 0.5 - 1, size, 2, C.line)
	end

	for i = 1, #itms do
		local item = items.GetStored(itms[i])

		if item and item.hud then
			curY = curY - size
			self:DrawIcon(x, curY, item, C.raised)
			curY = curY - pad
		end
	end

	self:SetSize(self.size.w, -math.max(height, self.minsize.h))
	self:SetPos(basepos.x, startY - height)
end
