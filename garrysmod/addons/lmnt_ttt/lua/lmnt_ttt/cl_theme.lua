--[[
	LMNT TTT – TTT2-Menüs und HUD im LMNT-Look
	Wählt beim ersten Besuch einmalig den Skin "lmnt_ttt2" (lua/terrortown/vskin/lmnt.lua)
	und das HUD "lmnt" (lua/terrortown/gamemode/shared/huds/lmnt/, Doku: docs/framework/api/hud.md).
	Danach gilt die Wahl des Spielers (F1 → Aussehen), sie wird nicht überschrieben.
]]

hook.Add("InitPostEntity", "LMNT.TTT.Theme", function()
	if not vskin or not vskin.SelectVSkin then return end
	if cookie.GetNumber("lmnt_vskin_applied", 0) == 1 then return end

	if vskin.SelectVSkin("lmnt_ttt2") then
		cookie.Set("lmnt_vskin_applied", "1")
	end
end)

--[[
	HUD: TTT2 merkt sich die Wahl in der Client-ConVar ttt2_current_hud (cl_hud_manager.lua:6) und
	wechselt über HUDManager.SetHUD(name) (cl_hud_manager.lua:193). Der Server prüft dabei Sperren und
	ein erzwungenes HUD (sv_hud_manager.lua:146-193) und bestätigt mit TTT2ReceiveHUD, danach läuft
	der Hook TTT2HUDUpdated(name) (cl_hud_manager.lua:170).

	Zeitpunkt: GM:InitPostEntity schickt zuerst die bisherige Wahl (cl_main.lua:259) und ruft danach
	PostInitPostEntity auf (cl_main.lua:293). Die Anfrage hier kommt also danach an und wird zuletzt
	bestätigt. Als erledigt gilt die Auswahl erst, wenn der Server "lmnt" bestätigt hat. Ist das HUD
	gesperrt oder ein anderes erzwungen, wird es beim nächsten Besuch erneut versucht.
]]
local HUD_ID = "lmnt"

hook.Add("PostInitPostEntity", "LMNT.TTT.Theme.HUD", function()
	if not HUDManager or not HUDManager.SetHUD or not huds or not huds.GetStored(HUD_ID) then return end
	if cookie.GetNumber("lmnt_hud_applied", 0) == 1 then return end

	if HUDManager.GetHUD() == HUD_ID then
		cookie.Set("lmnt_hud_applied", "1")
		return
	end

	HUDManager.SetHUD(HUD_ID)
end)

hook.Add("TTT2HUDUpdated", "LMNT.TTT.Theme.HUD", function(name)
	if name ~= HUD_ID then return end
	if cookie.GetNumber("lmnt_hud_applied", 0) == 1 then return end

	cookie.Set("lmnt_hud_applied", "1")
end)
