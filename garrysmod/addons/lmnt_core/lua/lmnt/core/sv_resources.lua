--[[
	LMNT Framework – Downloads für Clients

	1) Workshop: liest data/lmnt/workshop.json (dieselbe Datei nutzen die Tools/Skripte).
	   - "content"-Einträge lädt jeder Client (z. B. TTT2).
	   - "maps"-Einträge: nur die gerade laufende Map wird an Clients geschickt.
	2) FastDL: alle eigenen Dateien unter sound/lmnt, materials/lmnt und models/lmnt
	   werden automatisch per resource.AddFile registriert (werden über sv_downloadurl geladen).
]]

local function addWorkshop()
	local raw = file.Read("lmnt/workshop.json", "DATA")
	if not raw then
		MsgC(LMNT.Config.Colors.warn, "[LMNT] data/lmnt/workshop.json fehlt – keine Workshop-Downloads registriert.\n")
		return
	end

	local data = util.JSONToTable(raw)
	if not data then
		ErrorNoHalt("[LMNT] workshop.json ist kein gültiges JSON.\n")
		return
	end

	local count = 0

	for _, item in ipairs(data.content or {}) do
		if item.clientDownload ~= false then
			resource.AddWorkshop(tostring(item.id))
			count = count + 1
		end
	end

	local map = game.GetMap()
	for _, item in ipairs(data.maps or {}) do
		if item.map == map then
			resource.AddWorkshop(tostring(item.id))
			count = count + 1
		end
	end

	MsgC(LMNT.Config.Colors.primary, "[LMNT] ", color_white, count .. " Workshop-Downloads registriert (Map: " .. map .. ")\n")
end

local function addFolder(path)
	local files, folders = file.Find(path .. "/*", "GAME")
	local count = 0

	for _, f in ipairs(files or {}) do
		resource.AddFile(path .. "/" .. f)
		count = count + 1
	end

	for _, dir in ipairs(folders or {}) do
		count = count + addFolder(path .. "/" .. dir)
	end

	return count
end

hook.Add("Initialize", "LMNT.Resources", function()
	addWorkshop()

	local count = 0
	for _, dir in ipairs({ "sound/lmnt", "materials/lmnt", "models/lmnt" }) do
		count = count + addFolder(dir)
	end

	-- Marken-Schriften gezielt (resource/fonts enthält auch Schriften anderer Addons und des Spiels)
	for _, f in ipairs(LMNT.Config.Fonts.files) do
		resource.AddFile("resource/fonts/" .. f)
		count = count + 1
	end

	MsgC(LMNT.Config.Colors.primary, "[LMNT] ", color_white, count .. " FastDL-Dateien registriert\n")
end)
