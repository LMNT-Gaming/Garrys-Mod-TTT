--[[
	LMNT TTT – Level-Anzeige (Client)
	- Level-Tag im Chat:  [Lvl 12] Name: ...
	- Spalte "Lvl" im Scoreboard
	- XP-Leiste unten in der Mitte (während der Vorbereitung und für Tote)
	- Level-Up-Effekt mit Sound
]]

local col = LMNT.Config.Colors

hook.Add("LMNT.ChatPrefix", "LMNT.TTT.LevelTag", function(ply)
	return { col.muted, "[Lvl " .. ply:GetNWInt("lmnt_level", 1) .. "] " }
end)

hook.Add("TTTScoreboardColumns", "LMNT.TTT.LevelColumn", function(panel)
	panel:AddColumn("Lvl", function(ply) return ply:GetNWInt("lmnt_level", 1) end, 45)
end)

local levelUp

net.Receive("lmnt_levelup", function()
	levelUp = { level = net.ReadUInt(16), start = CurTime() }
	surface.PlaySound("lmnt/levelup.wav")
end)

hook.Add("HUDPaint", "LMNT.TTT.XPBar", function()
	local lp = LocalPlayer()
	if not IsValid(lp) then return end

	if levelUp then
		local t = CurTime() - levelUp.start
		if t > 4 then
			levelUp = nil
		else
			local S, A = LMNT.UI.Scale, LMNT.UI.Alpha
			local a = math.Clamp(math.min(t * 4, (4 - t) * 2), 0, 1)
			local scale = 1 + math.max(0, 0.4 - t) * 1.5
			LMNT.UI.PaintGlow(ScrW() / 2, ScrH() * 0.32, S(520), 70 * a)
			local m = Matrix()
			m:Translate(Vector(ScrW() / 2, ScrH() * 0.32, 0))
			m:Scale(Vector(scale, scale, 1))
			cam.PushModelMatrix(m)
				draw.SimpleText("LEVEL UP", "LMNT.Label", 0, -S(44), A(col.primary, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText(tostring(levelUp.level), "LMNT.Huge", 0, 0, A(col.white, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				draw.SimpleText("Neues Level erreicht", "LMNT.Body", 0, S(40), A(col.text, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			cam.PopModelMatrix()
		end
	end

	-- XP-Leiste nur, wenn sie nicht im Weg ist
	if GetRoundState() == ROUND_ACTIVE and lp:Alive() and not lp:IsSpec() then return end

	local S = LMNT.UI.Scale
	local level = lp:GetNWInt("lmnt_level", 1)
	local xp, nextXP = lp:GetNWInt("lmnt_xp", 0), math.max(lp:GetNWInt("lmnt_xp_next", 100), 1)
	local w, h = S(360), S(6)
	local x, y = ScrW() / 2 - w / 2, ScrH() - S(34)

	draw.RoundedBox(S(3), x, y, w, h, LMNT.UI.Alpha(col.bg, 200))
	draw.RoundedBox(S(3), x, y, w * math.Clamp(xp / nextXP, 0, 1), h, col.primary)
	draw.SimpleText("LVL " .. level, "LMNT.Label", x, y - S(12), col.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(xp .. " / " .. nextXP .. " XP   ·   " .. string.Comma(lp:GetNWInt("lmnt_points", 0)) .. " PUNKTE",
		"LMNT.Label", x + w, y - S(12), col.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end)
