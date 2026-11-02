--[[
	LMNT – Befehle für den Integration Manager (Recht "integrations")
	!integrations                      Übersicht (Zustand, Nachweisstufe, Version)
	!integration <id>                  Details: Belege, Prüfungen, Warnungen, Einschränkungen
	!integration <id> an|aus|pruefen|test
	!conflicts                         erkannte Konflikte
]]

local A = LMNT.Admin
local col = LMNT.Config.Colors

local stateColors = {
	ACTIVE = col.good, DEGRADED = col.warn, COMPATIBLE = col.info, DETECTED = col.info,
	NOT_INSTALLED = col.muted, DISABLED = col.muted, INITIALIZING = col.muted,
	INCOMPATIBLE = col.bad, MISSING_DEPENDENCY = col.bad, FAILED = col.bad,
}

local levelNames = {
	unknown = "unbekannt", detected = "erkannt", interface = "Schnittstelle geprüft",
	partial = "teilweise getestet", basic_test = "Grundtest bestanden", verified = "vollständig nachgewiesen",
}

A.AddCommand("integrations", {
	perm = "integrations", log = false,
	help = "Übersicht aller Integrationen mit Zustand und Nachweisstufe",
	run = function(caller)
		for _, st in ipairs(LMNT.Integrations.List()) do
			LMNT.Reply(caller, stateColors[st.state] or color_white, string.format("%-18s", st.state), color_white, " " .. st.id .. " ",
				col.muted, (st.detectedVersion and ("v" .. st.detectedVersion .. " · ") or "") .. levelNames[st.level] ..
				(st.pendingRestart and " · Neustart vorgemerkt" or "") .. (st.reason and (" · " .. st.reason) or ""))
		end
	end,
})

A.AddCommand("integration", {
	perm = "integrations",
	help = "Details oder Aktion: !integration <id> [an|aus|pruefen|test]",
	args = {
		{ type = "string", name = "id" },
		{ type = "string", name = "an|aus|pruefen|test", optional = true },
	},
	run = function(caller, id, action)
		local st = LMNT.Integrations.GetStatus(id)
		if not st then
			LMNT.Reply(caller, col.bad, "Unbekannte Integration: " .. id .. " (Liste: !integrations)")
			return
		end

		action = action and string.lower(action) or nil

		if action == "pruefen" or action == "prüfen" then
			LMNT.Integrations.Evaluate(id)
			st = LMNT.Integrations.GetStatus(id)
		elseif action == "test" then
			local passed, failed, messages = LMNT.Integrations.RunTests(id)
			LMNT.Reply(caller, failed == 0 and col.good or col.bad, "Integrationstests " .. id .. ": " .. passed .. " bestanden, " .. failed .. " fehlgeschlagen")
			for _, m in ipairs(messages) do LMNT.Reply(caller, col.muted, "  " .. m) end
			st = LMNT.Integrations.GetStatus(id)
		elseif action == "an" or action == "aus" then
			if st.detectOnly then
				LMNT.Reply(caller, col.warn, id .. " ist nur eine Erkennung und lässt sich nicht schalten.")
				return
			end
			local ok, err = LMNT.Settings.Set("integration." .. id .. ".enabled", action == "an", caller)
			if not ok then LMNT.Reply(caller, col.bad, "Fehler: " .. tostring(err)) return end
			st = LMNT.Integrations.GetStatus(id)
		elseif action then
			LMNT.Reply(caller, col.warn, "Benutzung: !integration <id> [an|aus|pruefen|test]")
			return
		end

		LMNT.Reply(caller, col.primary, st.name .. " (" .. id .. ")", col.muted, "  Adapter v" .. st.version .. (st.vendor and (" · " .. st.vendor) or ""))
		LMNT.Reply(caller, stateColors[st.state] or color_white, "Zustand: " .. st.state, col.muted, st.reason and ("  – " .. st.reason) or "")
		LMNT.Reply(caller, color_white, "Nachweis: " .. levelNames[st.level] .. (st.lastTest and ("  (letzter Test " .. os.date("%d.%m. %H:%M", st.lastTest.time) ..
			": " .. st.lastTest.passed .. " ok / " .. st.lastTest.failed .. " fehlgeschlagen)") or "  (noch kein Test ausgeführt)"))
		if st.detectedVersion or st.testedVersions then
			LMNT.Reply(caller, color_white, "Version erkannt: " .. (st.detectedVersion or "unbekannt") ..
				(st.testedVersions and ("  · getestet mit: " .. table.concat(st.testedVersions, ", ")) or ""))
		end
		for _, ev in ipairs(st.evidence or {}) do LMNT.Reply(caller, col.muted, "  Beleg: " .. ev) end
		for _, c in ipairs(st.checks or {}) do
			LMNT.Reply(caller, c.ok and col.good or (c.optional and col.warn or col.bad), "  " .. (c.ok and "✓ " or "✗ ") .. c.name .. (c.optional and " (optional)" or ""))
		end
		for _, w in ipairs(st.warnings or {}) do LMNT.Reply(caller, col.warn, "  Hinweis: " .. w) end
		for _, l in ipairs(st.limitations or {}) do LMNT.Reply(caller, col.muted, "  Einschränkung: " .. l) end
		if st.pendingRestart then LMNT.Reply(caller, col.warn, "  Änderung wird nach dem nächsten Neustart wirksam.") end
	end,
})

-- Kompatibilitätsmatrix (T-104): automatisch aus dem aktuellen Status; Angaben aus den Definitionen
-- (getestete Versionen, Einschränkungen) sind als „manuell gepflegt“ gekennzeichnet.
local function buildMatrix()
	local lines = {
		"# LMNT-Kompatibilitätsmatrix",
		"",
		"Erzeugt: " .. os.date("%d.%m.%Y %H:%M") .. " · LMNT " .. LMNT.Version .. " · Map " .. game.GetMap() ..
			" · TTT2 " .. ((GAMEMODE and GAMEMODE.Version) or "nicht aktiv"),
		"",
		"Spalten mit (A) werden automatisch auf diesem Server ermittelt, Spalten mit (M) sind manuell gepflegte Angaben aus der Integrationsdefinition.",
		"",
		"| Integration | Adapter | Zustand (A) | Erkannte Version (A) | Getestet mit (M) | Nachweis (A) | Letzter Test (A) | Einschränkungen (M) |",
		"|---|---|---|---|---|---|---|---|",
	}

	local function cell(v)
		return (string.gsub(tostring(v or "–"), "|", "/"))
	end

	for _, st in ipairs(LMNT.Integrations.List()) do
		lines[#lines + 1] = "| " .. table.concat({
			cell(st.name .. " (`" .. st.id .. "`)"),
			cell(st.detectOnly and "nur Erkennung" or ("v" .. st.version)),
			cell(st.state .. (st.reason and (": " .. st.reason) or "")),
			cell(st.detectedVersion or "unbekannt"),
			cell(st.testedVersions and table.concat(st.testedVersions, ", ") or "–"),
			cell(levelNames[st.level]),
			cell(st.lastTest and (os.date("%d.%m.%Y %H:%M", st.lastTest.time) .. ": " .. st.lastTest.passed .. " ok / " .. st.lastTest.failed .. " fehlgeschlagen") or "nicht ausgeführt"),
			cell(#(st.limitations or {}) > 0 and table.concat(st.limitations, "; ") or "–"),
		}, " | ") .. " |"
	end
	return table.concat(lines, "\n") .. "\n"
end

A.AddCommand("compatmatrix", {
	perm = "integrations",
	help = "Erzeugt die Kompatibilitätsmatrix nach data/lmnt/compat_matrix.md (vorher !integration <id> test ausführen)",
	run = function(caller)
		if not SERVER then return end
		file.CreateDir("lmnt")
		file.Write("lmnt/compat_matrix.md", buildMatrix())
		LMNT.Reply(caller, col.good, "Kompatibilitätsmatrix geschrieben: garrysmod/data/lmnt/compat_matrix.md")
	end,
})

A.AddCommand("conflicts", {
	perm = "integrations", log = false,
	help = "Zeigt erkannte Konflikte zwischen Integrationen bzw. mit LMNT",
	run = function(caller)
		local list = LMNT.Integrations.Conflicts()
		if #list == 0 then
			LMNT.Reply(caller, col.good, "Keine Konflikte erkannt.")
			return
		end
		for _, c in ipairs(list) do
			LMNT.Reply(caller, col.warn, "[" .. c.kind .. "] ", color_white, c.description)
		end
	end,
})
