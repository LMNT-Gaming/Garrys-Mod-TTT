--[[
	LMNT TTT – Spezialrunden-Anzeige
	Großes Banner beim Start, danach ein kleiner Hinweis oben in der Mitte.
]]

local col = LMNT.Config.Colors
local bannerStart = 0
local BANNER_TIME = 7

net.Receive("lmnt_special", function()
	bannerStart = CurTime()
	surface.PlaySound("lmnt/special.wav")

	local special = LMNT.TTT.Specials[net.ReadString()]
	if special then
		chat.AddText(special.color, "[SPEZIALRUNDE] " .. special.name .. ": ", color_white, special.desc)
	end
end)

hook.Add("HUDPaint", "LMNT.Special.HUD", function()
	local special = LMNT.TTT.GetSpecial()
	if not special then return end

	local S, A = LMNT.UI.Scale, LMNT.UI.Alpha
	local t = CurTime() - bannerStart

	if t < BANNER_TIME then
		local a = math.Clamp(math.min(t * 3, (BANNER_TIME - t) * 2), 0, 1)
		surface.SetFont("LMNT.Huge")
		local nameW = surface.GetTextSize(string.upper(special.name))
		surface.SetFont("LMNT.Body")
		local descW = surface.GetTextSize(special.desc)
		local w, h = math.max(S(560), nameW + S(80), descW + S(80)), S(132)
		local x, y = ScrW() / 2 - w / 2, ScrH() * 0.16 - (1 - a) * S(30)

		draw.RoundedBox(S(8), x, y, w, h, A(col.bg, 240 * a))
		LMNT.UI.PaintGlow(ScrW() / 2, y + h / 2, w * 0.9, 50 * a)
		surface.SetDrawColor(col.primary.r, col.primary.g, col.primary.b, 255 * a)
		surface.DrawRect(x, y, w, S(3))

		draw.SimpleText("SPEZIALRUNDE", "LMNT.Label", ScrW() / 2, y + S(22), A(col.primary, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(string.upper(special.name), "LMNT.Huge", ScrW() / 2, y + S(62), A(col.white, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(special.desc, "LMNT.Body", ScrW() / 2, y + S(104), A(col.text, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return
	end

	-- Dauerhinweis unterhalb des TTT2-Rundentimers (der oben mittig sitzt)
	local text = string.upper(special.name)
	surface.SetFont("LMNT.Label")
	local tw = surface.GetTextSize(text)
	local w, h = tw + S(34), S(24)
	local x, y = ScrW() / 2 - w / 2, S(86)
	draw.RoundedBox(S(4), x, y, w, h, A(col.bg, 220))
	surface.SetDrawColor(col.primary)
	surface.DrawRect(x, y, S(3), h)
	draw.SimpleText(text, "LMNT.Label", x + S(20), y + h / 2, col.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)
