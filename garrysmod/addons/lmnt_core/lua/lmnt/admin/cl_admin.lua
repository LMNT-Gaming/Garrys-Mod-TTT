--[[
	LMNT Admin – Menü (Client)
	Öffnen: !menu, Konsole "lmnt_menu" oder eigene Taste: bind F6 lmnt_menu
	Alle Aktionen laufen über dieselben Server-Befehle (Rechte werden dort geprüft).
]]

local A = LMNT.Admin
local col = LMNT.Config.Colors
local frame

local function sendCommand(name, tokens)
	net.Start("lmnt_admin_run")
	net.WriteString(name)
	net.WriteUInt(#tokens, 4)
	for _, t in ipairs(tokens) do net.WriteString(t) end
	net.SendToServer()
end

-- Fragt nacheinander die restlichen Argumente ab
local function promptArgs(cmd, index, tokens)
	local spec = cmd.args[index]
	if not spec then
		sendCommand(cmd.name, tokens)
		return
	end

	local label = (spec.name or spec.type) .. (spec.optional and " (optional)" or "")
	if spec.type == "time" then label = label .. "  –  z. B. 30m, 2h, 1d, 0 = permanent" end

	LMNT.UI.Prompt("!" .. cmd.name, label, spec.default and not isfunction(spec.default) and tostring(spec.default) or "", function(text)
		tokens[#tokens + 1] = text
		promptArgs(cmd, index + 1, tokens)
	end)
end

local S = LMNT.UI.Scale

local function sortedCommands(filter)
	local list = {}
	for _, cmd in pairs(A.Commands) do
		if cmd.perm and LMNT.HasPerm(LocalPlayer(), cmd.perm) and (not filter or filter(cmd)) then
			list[#list + 1] = cmd
		end
	end
	table.SortByMember(list, "name", true)
	return list
end

------------------------------------------------------------------------
-- Tab: Spieler
------------------------------------------------------------------------

local function buildPlayersTab()
	local panel = vgui.Create("DPanel")
	panel.Paint = nil

	local list = vgui.Create("DListView", panel)
	list:Dock(FILL)
	list:SetMultiSelect(false)
	list:AddColumn("Name")
	list:AddColumn("Rang"):SetFixedWidth(S(120))
	list:AddColumn("SteamID"):SetFixedWidth(S(170))
	list:AddColumn("Ping"):SetFixedWidth(S(56))
	LMNT.UI.StyleList(list)

	local function refresh()
		list:Clear()
		for _, ply in ipairs(player.GetAll()) do
			local line = list:AddLine(ply:Nick(), LMNT.GetRank(ply:GetUserGroup()).name, ply:SteamID(), ply:Ping())
			line.Player = ply
		end
	end
	refresh()

	local actions = LMNT.UI.StyleScroll(vgui.Create("DScrollPanel", panel))
	actions:Dock(RIGHT)
	actions:SetWide(S(200))
	actions:DockMargin(S(12), 0, 0, 0)

	local refreshBtn = LMNT.UI.Button(actions, "Aktualisieren", refresh)
	refreshBtn:Dock(TOP)
	refreshBtn:DockMargin(0, 0, S(8), S(12))

	LMNT.UI.Section(actions, 1, "Aktionen")

	local playerCmds = sortedCommands(function(cmd)
		local first = cmd.args[1]
		return first and (first.type == "player" or first.type == "players")
	end)

	for _, cmd in ipairs(playerCmds) do
		local btn = LMNT.UI.Button(actions, "!" .. cmd.name, function()
			local line = list:GetSelectedLine() and list:GetLine(list:GetSelectedLine())
			if not line or not IsValid(line.Player) then
				LMNT.UI.Alert("Kein Spieler gewählt", "Bitte zuerst links einen Spieler auswählen.")
				return
			end
			promptArgs(cmd, 2, { "#" .. line.Player:UserID() })
		end, "ghost")
		btn:Dock(TOP)
		btn:SetTall(S(30))
		btn:DockMargin(0, 0, S(8), S(4))
		btn:SetTooltip(cmd.help or "")
	end

	return panel
end

------------------------------------------------------------------------
-- Tab: Befehle (freie Eingabe + Übersicht)
------------------------------------------------------------------------

local function buildCommandsTab()
	local panel = vgui.Create("DPanel")
	panel.Paint = nil

	local entry = LMNT.UI.TextEntry(panel, "Befehl eingeben, z. B.:  ban Max 1d Grund   (Enter)")
	entry:Dock(TOP)
	entry.OnEnter = function(self)
		local tokens = A.Tokenize(self:GetValue())
		local name = table.remove(tokens, 1)
		if name then sendCommand(name, tokens) end
		self:SetText("")
	end

	local list = vgui.Create("DListView", panel)
	list:Dock(FILL)
	list:DockMargin(0, S(12), 0, 0)
	list:AddColumn("Benutzung"):SetFixedWidth(S(320))
	list:AddColumn("Beschreibung")
	LMNT.UI.StyleList(list)

	for _, cmd in ipairs(sortedCommands()) do
		local line = list:AddLine(A.Usage(cmd), cmd.help or "")
		line.Command = cmd
	end

	list.DoDoubleClick = function(_, _, line)
		promptArgs(line.Command, 1, {})
	end

	return panel
end

------------------------------------------------------------------------
-- Tab: Banns
------------------------------------------------------------------------

local banList

local function buildBansTab()
	local panel = vgui.Create("DPanel")
	panel.Paint = nil

	banList = vgui.Create("DListView", panel)
	banList:Dock(FILL)
	banList:AddColumn("Name")
	banList:AddColumn("SteamID64"):SetFixedWidth(S(160))
	banList:AddColumn("Grund")
	banList:AddColumn("Admin"):SetFixedWidth(S(120))
	banList:AddColumn("Endet"):SetFixedWidth(S(130))
	LMNT.UI.StyleList(banList)

	local bar = vgui.Create("DPanel", panel)
	bar:Dock(BOTTOM)
	bar:SetTall(S(34))
	bar:DockMargin(0, S(10), 0, 0)
	bar.Paint = nil

	local reload = LMNT.UI.Button(bar, "Neu laden", function()
		net.Start("lmnt_admin_bans")
		net.SendToServer()
	end, "ghost")
	reload:Dock(LEFT)
	reload:SetWide(S(150))

	local unban = LMNT.UI.Button(bar, "Entbannen", function()
		local id = banList:GetSelectedLine()
		if not id then return end
		local line = banList:GetLine(id)
		LMNT.UI.Confirm("Entbannen", line:GetColumnText(1) .. " (" .. line:GetColumnText(2) .. ") wirklich entbannen?", "Entbannen", function()
			sendCommand("unban", { line:GetColumnText(2) })
			timer.Simple(0.5, function() net.Start("lmnt_admin_bans") net.SendToServer() end)
		end)
	end)
	unban:Dock(RIGHT)
	unban:SetWide(S(150))

	net.Start("lmnt_admin_bans")
	net.SendToServer()

	return panel
end

net.Receive("lmnt_admin_bans", function()
	if not IsValid(banList) then return end
	banList:Clear()

	for _ = 1, net.ReadUInt(10) do
		local sid, name, reason, admin = net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString()
		net.ReadUInt(32) -- erstellt
		local expires = net.ReadUInt(32)
		banList:AddLine(name, sid, reason, admin, expires == 0 and "permanent" or os.date("%d.%m.%y %H:%M", expires))
	end
end)

------------------------------------------------------------------------
-- Tab: Logs
------------------------------------------------------------------------

local logList

local function buildLogsTab()
	local panel = vgui.Create("DPanel")
	panel.Paint = nil

	local bar = vgui.Create("DPanel", panel)
	bar:Dock(TOP)
	bar:SetTall(S(34))
	bar.Paint = nil

	local category = LMNT.UI.StyleCombo(vgui.Create("DComboBox", bar))
	category:Dock(LEFT)
	category:SetWide(S(150))
	category:SetValue("Alle")
	for _, c in ipairs({ "Alle", "admin", "ban", "chat", "connect", "kill", "asay", "pm", "round", "shop" }) do
		category:AddChoice(c)
	end

	local search = LMNT.UI.TextEntry(bar, "Suche (Name, SteamID, Text …)")
	search:Dock(FILL)
	search:DockMargin(S(8), 0, S(8), 0)

	local function load()
		local c = category:GetValue()
		net.Start("lmnt_admin_logs")
		net.WriteString(c == "Alle" and "" or c)
		net.WriteString(search:GetValue())
		net.SendToServer()
	end

	search.OnEnter = load
	category.OnSelect = load

	local go = LMNT.UI.Button(bar, "Suchen", load)
	go:Dock(RIGHT)
	go:SetWide(S(110))

	logList = vgui.Create("DListView", panel)
	logList:Dock(FILL)
	logList:DockMargin(0, S(10), 0, 0)
	logList:AddColumn("Zeit"):SetFixedWidth(S(120))
	logList:AddColumn("Typ"):SetFixedWidth(S(80))
	logList:AddColumn("Eintrag")
	LMNT.UI.StyleList(logList)

	load()
	return panel
end

net.Receive("lmnt_admin_logs", function()
	if not IsValid(logList) then return end
	logList:Clear()

	for _ = 1, net.ReadUInt(10) do
		local time, cat, msg = net.ReadUInt(32), net.ReadString(), net.ReadString()
		logList:AddLine(os.date("%d.%m %H:%M:%S", time), cat, msg)
	end
end)

------------------------------------------------------------------------
-- Configurator (Tabs „Module“ und „Einstellungen“)
-- Daten und Schreibaktionen kommen vom Server: lmnt/services/sv_settingsmenu.lua
-- Der Client prüft nur vor (Rechte, Validate); entscheidend ist immer der Server.
------------------------------------------------------------------------

local STATE_TEXT = { enabled = "aktiv", disabled = "aus", blocked = "blockiert", failed = "fehlerhaft", registered = "registriert" }
local STATE_COLOR = { enabled = col.good, disabled = col.muted, blocked = col.warn, failed = col.bad, registered = col.info }
local APPLIES_TEXT = { live = "wirkt sofort", nextround = "wirkt ab nächster Runde", restart = "wirkt nach Neustart" }
local APPLIES_COLOR = { live = col.good, nextround = col.warn, restart = col.bad }

-- Gegenstück zu writeValue in sv_settingsmenu.lua
local function readSettingValue(kind)
	if kind == "bool" then return net.ReadBool() end
	if kind == "int" or kind == "number" then return net.ReadDouble() end
	return net.ReadString()
end

local function formatSettingValue(def, value)
	if def.type == "bool" then return value and "an" or "aus" end
	if def.type == "string" and value == "" then return "(leer)" end
	return tostring(value)
end

local function statusLabel(parent)
	local lbl = vgui.Create("DLabel", parent)
	lbl:Dock(FILL)
	lbl:DockMargin(S(12), 0, S(12), 0)
	lbl:SetFont("LMNT.Small")
	lbl:SetTextColor(col.muted)
	lbl:SetText("")
	return lbl
end

------------------------------------------------------------------------
-- Tab: Module
------------------------------------------------------------------------

local moduleList, moduleStatus

local function requestModules()
	net.Start("lmnt_admin_cfg_modules")
	net.SendToServer()
end

local function sendModuleToggle(id, enable)
	net.Start("lmnt_admin_cfg_module")
	net.WriteString(id)
	net.WriteBool(enable)
	net.SendToServer()
end

local function buildModulesTab()
	local panel = vgui.Create("DPanel")
	panel.Paint = nil

	local bar = vgui.Create("DPanel", panel)
	bar:Dock(BOTTOM)
	bar:SetTall(S(34))
	bar:DockMargin(0, S(10), 0, 0)
	bar.Paint = nil

	moduleList = vgui.Create("DListView", panel)
	moduleList:Dock(FILL)
	moduleList:SetMultiSelect(false)
	moduleList:AddColumn("Modul")
	moduleList:AddColumn("Version"):SetFixedWidth(S(80))
	moduleList:AddColumn("Zustand"):SetFixedWidth(S(100))
	moduleList:AddColumn("Reg."):SetFixedWidth(S(56))
	moduleList:AddColumn("Grund / Abhängigkeiten")
	LMNT.UI.StyleList(moduleList)

	local function selected()
		local id = moduleList:GetSelectedLine()
		return id and moduleList:GetLine(id).Module or nil
	end

	local reload = LMNT.UI.Button(bar, "Neu laden", requestModules, "ghost")
	reload:Dock(LEFT)
	reload:SetWide(S(130))

	local disable = LMNT.UI.Button(bar, "Deaktivieren", function()
		local m = selected()
		if not m or m.required then return end
		LMNT.UI.Confirm("Modul deaktivieren", "Modul „" .. m.name .. "“ (" .. m.id .. ") wirklich deaktivieren? " ..
			"Module, die davon abhängen, werden ebenfalls gestoppt.", "Deaktivieren", function()
			sendModuleToggle(m.id, false)
		end, "danger")
	end, "danger")
	disable:Dock(RIGHT)
	disable:SetWide(S(150))

	local enable = LMNT.UI.Button(bar, "Aktivieren", function()
		local m = selected()
		if not m or m.required or m.state == "enabled" then return end
		sendModuleToggle(m.id, true)
	end, "success")
	enable:Dock(RIGHT)
	enable:SetWide(S(150))
	enable:DockMargin(0, 0, S(8), 0)

	moduleStatus = statusLabel(bar)

	-- Erforderliche Module sind nicht umschaltbar; ein eingeschaltetes, aber blockiertes Modul lässt
	-- sich erneut starten oder ausschalten
	function moduleList:UpdateButtons()
		local m = selected()
		local switchable = m ~= nil and not m.required
		enable:SetEnabled(switchable and m.state ~= "enabled")
		enable.Label = (switchable and m.wanted and m.state ~= "enabled") and "Erneut starten" or "Aktivieren"
		disable:SetEnabled(switchable and (m.state == "enabled" or m.wanted))
	end
	moduleList.OnRowSelected = function(self) self:UpdateButtons() end
	moduleList:UpdateButtons()

	requestModules()
	return panel
end

net.Receive("lmnt_admin_cfg_modules", function()
	local mods = {}
	while net.ReadBool() and #mods < 4096 do
		mods[#mods + 1] = {
			id = net.ReadString(), name = net.ReadString(), version = net.ReadString(),
			state = net.ReadString(), error = net.ReadString(),
			required = net.ReadBool(), wanted = net.ReadBool(),
			registrations = net.ReadUInt(16), depends = net.ReadString(),
		}
	end
	local truncated = net.ReadBool()
	if not IsValid(moduleList) then return end

	local selectedLine = moduleList:GetSelectedLine() and moduleList:GetLine(moduleList:GetSelectedLine())
	local selectedId = selectedLine and selectedLine.Module and selectedLine.Module.id
	moduleList:Clear()

	local counts = {}
	for _, m in ipairs(mods) do
		counts[m.state] = (counts[m.state] or 0) + 1

		local reason = m.error
		if reason == "" and m.depends ~= "" then reason = "benötigt " .. m.depends end
		if m.required then reason = "erforderlich" .. (reason ~= "" and (" · " .. reason) or "") end

		local line = moduleList:AddLine(m.name .. "  (" .. m.id .. ")", m.version, STATE_TEXT[m.state] or m.state, m.registrations, reason)
		line.Module = m
		line.Columns[3]:SetTextColor(STATE_COLOR[m.state] or col.text)
		if m.error ~= "" then line.Columns[5]:SetTextColor(col.bad) end
		line:SetTooltip(m.error ~= "" and m.error or nil)

		if m.id == selectedId then moduleList:SelectItem(line) end
	end
	moduleList:UpdateButtons()

	if IsValid(moduleStatus) then
		local parts = { #mods .. " Module" }
		for _, state in ipairs({ "enabled", "disabled", "blocked", "failed" }) do
			if counts[state] then parts[#parts + 1] = counts[state] .. " " .. STATE_TEXT[state] end
		end
		if truncated then parts[#parts + 1] = "Liste gekürzt" end
		moduleStatus:SetText(table.concat(parts, " · "))
		moduleStatus:SetTextColor((counts.failed or counts.blocked) and col.warn or col.muted)
	end
end)

------------------------------------------------------------------------
-- Tab: Einstellungen
------------------------------------------------------------------------

local settingsPanel                -- Tab-Panel (Filter, Liste, Status)
local settingDefs = {}             -- Definitionen vom Server, sortiert nach Kategorie und Key
local settingByKey = {}
local settingRows = {}             -- key -> Zeile (zum Aktualisieren nach dem Speichern)
local settingsTruncated = false

local function requestSettings()
	net.Start("lmnt_admin_cfg_settings")
	net.SendToServer()
end

local function sendSetting(key, reset, raw)
	net.Start("lmnt_admin_cfg_set")
	net.WriteString(key)
	net.WriteBool(reset)
	if not reset then net.WriteString(raw) end
	net.SendToServer()
end

local function setSettingsStatus(text, color)
	if IsValid(settingsPanel) and IsValid(settingsPanel.Status) then
		settingsPanel.Status:SetText(text)
		settingsPanel.Status:SetTextColor(color or col.muted)
	end
end

local function settingRow(parent, def)
	local row = vgui.Create("DPanel", parent)
	row:Dock(TOP)
	row:SetTall(S(92))
	row:DockMargin(0, 0, S(8), S(8))
	row:DockPadding(S(14), S(10), S(12), S(10))
	row.Paint = function(self, w, h)
		draw.RoundedBox(S(6), 0, 0, w, h, col.panel)
		-- Ungespeicherte Änderung: Markierung am linken Rand
		if self.Dirty then
			surface.SetDrawColor(col.warn)
			surface.DrawRect(0, 0, S(3), h)
		end
	end

	-- Rechts: Eingabe, Speichern, Zurücksetzen
	local controls = vgui.Create("DPanel", row)
	controls:Dock(RIGHT)
	controls:SetWide(S(430))
	controls:DockPadding(0, S(19), 0, S(19))
	controls.Paint = nil

	local getPending, setInput

	if def.type == "bool" then
		local toggle = LMNT.UI.Button(controls, "", function()
			row.Pending = not row.Pending
			setInput(row.Pending)
			row.Dirty = row.Pending ~= def.value
		end, "ghost")
		local basePaint = toggle.Paint
		toggle.Paint = function(self, w, h)
			basePaint(self, w, h)
			draw.RoundedBox(S(4), S(12), h / 2 - S(4), S(8), S(8), row.Pending and col.good or col.muted)
		end
		toggle:Dock(FILL)
		getPending = function() return row.Pending end
		setInput = function(value)
			row.Pending = value == true
			toggle.Label = row.Pending and "An" or "Aus"
		end
	elseif def.type == "enum" then
		local combo = LMNT.UI.StyleCombo(vgui.Create("DComboBox", controls))
		combo:Dock(FILL)
		combo:SetSortItems(false)
		for _, c in ipairs(def.choices) do combo:AddChoice(c) end
		combo.OnSelect = function(_, _, value) row.Dirty = value ~= def.value end
		getPending = function() return combo:GetValue() end
		setInput = function(value) combo:SetValue(value) end
	else
		local hint
		if def.type == "string" then
			hint = def.maxLength and ("max. " .. def.maxLength .. " Zeichen") or "Text"
		else
			hint = (def.min and def.max) and (def.min .. " – " .. def.max) or (def.type == "int" and "ganze Zahl" or "Zahl")
		end
		local entry = LMNT.UI.TextEntry(controls, hint)
		entry:Dock(FILL)
		if def.type ~= "string" then entry:SetNumeric(true) end
		entry.OnChange = function(self) row.Dirty = self:GetValue() ~= formatSettingValue(def, def.value) end
		getPending = function() return entry:GetValue() end
		setInput = function(value) entry:SetValue(def.type == "string" and value or tostring(value)) end
	end

	local reset = LMNT.UI.Button(controls, "Zurücksetzen", function()
		LMNT.UI.Confirm("Zurücksetzen", def.key .. " auf den Standard (" .. formatSettingValue(def, def.default) ..
			") bzw. den Wert aus data/lmnt/config.json zurücksetzen?", "Zurücksetzen", function()
			sendSetting(def.key, true)
		end, "danger")
	end, "ghost")
	reset:Dock(RIGHT)
	reset:SetWide(S(120))
	reset:DockMargin(S(8), 0, 0, 0)

	local save = LMNT.UI.Button(controls, "Speichern", function()
		-- Vorprüfung mit derselben Funktion wie der Server; der Server validiert trotzdem erneut
		local ok, normalized = LMNT.Settings.Validate(def, getPending())
		if not ok then
			LMNT.UI.Toast(def.key .. ": " .. normalized, col.bad)
			setSettingsStatus(def.key .. ": " .. normalized, col.bad)
			return
		end
		if normalized == def.value then
			setSettingsStatus(def.key .. ": keine Änderung")
			row.Dirty = false
			return
		end
		local raw = def.type == "bool" and (normalized and "1" or "0") or tostring(normalized)
		sendSetting(def.key, false, raw)
	end)
	save:Dock(RIGHT)
	save:SetWide(S(120))
	save:DockMargin(S(8), 0, 0, 0)

	-- Links: Key, Beschreibung, aktueller Wert / Standard / Grenzen / Wirkung
	local info = vgui.Create("DPanel", row)
	info:Dock(FILL)
	info:DockMargin(0, 0, S(12), 0)
	info:SetTooltip(def.desc ~= "" and def.desc or nil)
	info.Paint = function(_, w)
		draw.SimpleText(def.key, "LMNT.BodyBold", 0, 0, col.text)
		draw.SimpleText(def.desc ~= "" and def.desc or "Keine Beschreibung", "LMNT.Small", 0, S(25), col.muted)

		local facts = "Aktuell: " .. formatSettingValue(def, def.value) .. "   ·   Standard: " .. formatSettingValue(def, def.default)
		if def.min or def.max then
			facts = facts .. "   ·   Bereich: " .. (def.min and tostring(def.min) or "–") .. " bis " .. (def.max and tostring(def.max) or "–")
		end
		if def.maxLength then facts = facts .. "   ·   max. " .. def.maxLength .. " Zeichen" end
		facts = facts .. "   ·   "

		surface.SetFont("LMNT.Small")
		local fw = surface.GetTextSize(facts)
		draw.SimpleText(facts, "LMNT.Small", 0, S(48), def.value ~= def.default and col.warn or col.text)
		if fw < w then
			draw.SimpleText(APPLIES_TEXT[def.applies] or def.applies, "LMNT.Small", fw, S(48), APPLIES_COLOR[def.applies] or col.muted)
		end
	end

	function row:SetCurrent(value)
		def.value = value
		setInput(value)
		self.Dirty = false
	end
	row:SetCurrent(def.value)

	return row
end

local function rebuildSettings()
	if not IsValid(settingsPanel) then return end
	local scroll = settingsPanel.Scroll
	scroll:Clear()
	settingRows = {}

	local filter = string.lower(string.Trim(settingsPanel.Filter:GetValue()))
	local section, category, shown = 0, nil, 0

	for _, def in ipairs(settingDefs) do
		local match = filter == "" or string.find(string.lower(def.key .. " " .. def.desc .. " " .. def.category), filter, 1, true)
		if match then
			if def.category ~= category then
				category = def.category
				section = section + 1
				LMNT.UI.Section(scroll, section, category)
			end
			settingRows[def.key] = settingRow(scroll, def)
			shown = shown + 1
		end
	end

	if shown == 0 then
		local empty = vgui.Create("DLabel", scroll)
		empty:Dock(TOP)
		empty:SetFont("LMNT.Body")
		empty:SetTextColor(col.muted)
		empty:SetText(#settingDefs == 0 and "Keine Einstellungen verfügbar." or "Keine Einstellung passt zum Filter.")
		empty:SizeToContentsY()
	end

	setSettingsStatus(shown .. " von " .. #settingDefs .. " Einstellungen" ..
		(settingsTruncated and " · Liste gekürzt" or ""), settingsTruncated and col.warn or col.muted)
end

local function buildSettingsTab()
	local panel = vgui.Create("DPanel")
	panel.Paint = nil
	settingsPanel = panel

	local top = vgui.Create("DPanel", panel)
	top:Dock(TOP)
	top:SetTall(S(34))
	top:DockMargin(0, 0, 0, S(10))
	top.Paint = nil

	local reload = LMNT.UI.Button(top, "Neu laden", requestSettings, "ghost")
	reload:Dock(RIGHT)
	reload:SetWide(S(130))

	panel.Filter = LMNT.UI.TextEntry(top, "Filter (Key, Beschreibung, Kategorie …)")
	panel.Filter:Dock(FILL)
	panel.Filter:DockMargin(0, 0, S(8), 0)
	panel.Filter.OnChange = rebuildSettings

	local bar = vgui.Create("DPanel", panel)
	bar:Dock(BOTTOM)
	bar:SetTall(S(24))
	bar:DockMargin(0, S(8), 0, 0)
	bar.Paint = nil
	panel.Status = statusLabel(bar)
	panel.Status:DockMargin(0, 0, 0, 0)

	panel.Scroll = LMNT.UI.StyleScroll(vgui.Create("DScrollPanel", panel))
	panel.Scroll:Dock(FILL)

	setSettingsStatus("Lade Einstellungen …")
	requestSettings()
	return panel
end

net.Receive("lmnt_admin_cfg_settings", function()
	local defs, byKey = {}, {}
	while net.ReadBool() and #defs < 4096 do
		local def = {
			key = net.ReadString(), type = net.ReadString(), category = net.ReadString(),
			desc = net.ReadString(), applies = net.ReadString(),
		}
		def.default = readSettingValue(def.type)
		def.value = readSettingValue(def.type)
		if net.ReadBool() then def.min = net.ReadDouble() end
		if net.ReadBool() then def.max = net.ReadDouble() end
		local maxLength = net.ReadUInt(16)
		def.maxLength = maxLength > 0 and maxLength or nil
		def.choices = {}
		for i = 1, net.ReadUInt(8) do def.choices[i] = net.ReadString() end

		defs[#defs + 1] = def
		byKey[def.key] = def
	end

	settingsTruncated = net.ReadBool()
	settingDefs, settingByKey = defs, byKey
	rebuildSettings()
end)

-- Ergebnis jeder Schreibaktion (beide Tabs): Meldung anzeigen und den neuen Wert übernehmen
net.Receive("lmnt_admin_cfg_result", function()
	local ok, text = net.ReadBool(), net.ReadString()

	if net.ReadBool() then
		local key = net.ReadString()
		local def = settingByKey[key]
		-- Ohne bekannte Definition lässt sich der Wert nicht typgerecht lesen; der Rest wird ignoriert
		if def then
			local value = readSettingValue(def.type)
			if IsValid(settingRows[key]) then settingRows[key]:SetCurrent(value) else def.value = value end
		end
	end

	LMNT.UI.Toast(text, ok and col.good or col.bad)
	setSettingsStatus(text, ok and col.good or col.bad)
	if IsValid(moduleStatus) and not ok then
		moduleStatus:SetText(text)
		moduleStatus:SetTextColor(col.bad)
	end
end)

------------------------------------------------------------------------
-- Öffnen
------------------------------------------------------------------------

local function openMenu()
	if IsValid(frame) then frame:Remove() end
	if not LMNT.HasPerm(LocalPlayer(), "menu") then
		chat.AddText(col.bad, "[LMNT] Du hast keinen Zugriff auf das Admin-Menü.")
		return
	end

	frame = LMNT.UI.Frame("Admin", 1000, 640)
	local tabs = LMNT.UI.Tabs(frame)

	tabs:AddTab("Spieler", buildPlayersTab())
	tabs:AddTab("Befehle", buildCommandsTab())
	if LMNT.HasPerm(LocalPlayer(), "ban") then tabs:AddTab("Banns", buildBansTab()) end
	if LMNT.HasPerm(LocalPlayer(), "logs") then tabs:AddTab("Logs", buildLogsTab()) end
	if LMNT.HasPerm(LocalPlayer(), "modules") then tabs:AddTab("Module", buildModulesTab()) end
	if LMNT.HasPerm(LocalPlayer(), "config") then tabs:AddTab("Einstellungen", buildSettingsTab()) end

	hook.Run("LMNT.AdminMenu.Build", tabs)
end

net.Receive("lmnt_admin_open", openMenu)
concommand.Add("lmnt_menu", openMenu)

-- Rang-Tag im Chat: [Admin] Name: Text
-- Übernimmt die Sonderregeln aus TTT2 (gamemode/client/cl_chat.lua, GM:OnPlayerChat), da ein Hook mit
-- Rückgabewert die Gamemode-Funktion ersetzt:
--   * öffentliche Polizei-Rollen (Detektiv) -> TTT2 formatiert selbst, wir greifen nicht ein
--   * Zuschauer gelten als tot, Team-Chat wird bei Zuschauern und unknownTeam-Rollen nicht markiert
hook.Add("OnPlayerChat", "LMNT.ChatTags", function(ply, text, teamChat, isDead)
	if not IsValid(ply) then return end

	if TTT2 and ply.GetSubRoleData then
		local roleData = ply:GetSubRoleData()
		if ply:IsActive() and roleData.isPolicingRole and roleData.isPublicRole then return end

		local isSpectator = ply:Team() == TEAM_SPEC
		if isSpectator then isDead = true end
		if teamChat and (isSpectator or roleData.unknownTeam) then teamChat = false end
	end

	local rank = LMNT.GetRank(ply:GetUserGroup())
	local out = {}

	if isDead then
		out[#out + 1] = Color(255, 60, 60)
		out[#out + 1] = "*TOT* "
	end
	if teamChat then
		out[#out + 1] = Color(30, 200, 120)
		out[#out + 1] = "(TEAM) "
	end
	if ply:GetUserGroup() ~= "user" then
		out[#out + 1] = rank.color
		out[#out + 1] = "[" .. rank.name .. "] "
	end

	local extra = hook.Run("LMNT.ChatPrefix", ply)
	if istable(extra) then
		for _, v in ipairs(extra) do out[#out + 1] = v end
	end

	out[#out + 1] = rank.color
	out[#out + 1] = ply:Nick()
	out[#out + 1] = color_white
	out[#out + 1] = ": " .. text

	chat.AddText(unpack(out))
	return true
end)
