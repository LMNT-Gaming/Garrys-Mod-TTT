--[[
	LMNT Framework – Unit-Test-Runner (Server)
	Ausführen: !test  bzw. RCON/Konsole: lmnt test
	Testdateien: lua/lmnt/tests/sv_*.lua (jedes Addon kann eigene beisteuern)

	LMNT.Test.Describe("Gruppe", function(t)
		t:It("macht etwas", function(e)
			e:Equal(1 + 1, 2)
			e:True(x)
			e:Error(function() error("x") end)
		end)
	end)

	Ausgabe endet immer mit:  "LMNT-TESTS: <n> bestanden, <m> fehlgeschlagen"
	(tools/test_server.ps1 wertet diese Zeile aus)
]]

LMNT.Test = LMNT.Test or {}

local Expect = {}
Expect.__index = Expect

local function fail(msg)
	error({ lmntTestFailure = true, message = msg }, 0)
end

function Expect:Equal(actual, expected, label)
	if actual ~= expected then
		fail((label and (label .. ": ") or "") .. "erwartet " .. tostring(expected) .. ", erhalten " .. tostring(actual))
	end
end

function Expect:True(value, label)
	if not value then fail((label or "Bedingung") .. " ist nicht wahr") end
end

function Expect:False(value, label)
	if value then fail((label or "Bedingung") .. " ist nicht falsch") end
end

function Expect:Error(fn, label)
	local ok = pcall(fn)
	if ok then fail((label or "Funktion") .. " hätte einen Fehler werfen müssen") end
end

function Expect:NoError(fn, label)
	local ok, err = pcall(fn)
	if not ok then fail((label or "Funktion") .. " warf einen Fehler: " .. tostring(err)) end
end

-- Für Integrationstests (LMNT.Integrations.RunTests) und eigene Prüfwerkzeuge
function LMNT.Test.NewExpect()
	return setmetatable({}, Expect)
end

local groups = {}

function LMNT.Test.Describe(name, fn)
	table.insert(groups, { name = name, fn = fn })
end

function LMNT.Test.RunAll(caller)
	groups = {}
	local files = file.Find("lmnt/tests/sv_*.lua", "LUA")
	table.sort(files)
	for _, f in ipairs(files) do
		local ok, err = pcall(include, "lmnt/tests/" .. f)
		if not ok then LMNT.Reply(caller, LMNT.Config.Colors.bad, "Testdatei " .. f .. " fehlerhaft: " .. tostring(err)) end
	end

	local passed, failed = 0, 0
	local col = LMNT.Config.Colors

	for _, group in ipairs(groups) do
		local cases = {}
		local ctx = { It = function(_, title, fn) cases[#cases + 1] = { title = title, fn = fn } end }
		local ok, err = pcall(group.fn, ctx)
		if not ok then
			failed = failed + 1
			LMNT.Reply(caller, col.bad, "[FAIL] " .. group.name .. " (Aufbau): " .. tostring(err))
		end

		for _, case in ipairs(cases) do
			local e = setmetatable({}, Expect)
			local cOk, cErr = pcall(case.fn, e)
			if cOk then
				passed = passed + 1
			else
				failed = failed + 1
				local msg = istable(cErr) and cErr.lmntTestFailure and cErr.message or tostring(cErr)
				LMNT.Reply(caller, col.bad, "[FAIL] " .. group.name .. " › " .. case.title .. ": " .. msg)
			end
		end
	end

	LMNT.Reply(caller, failed == 0 and col.good or col.bad, "LMNT-TESTS: " .. passed .. " bestanden, " .. failed .. " fehlgeschlagen")
	LMNT.Log.Info("test", passed .. " bestanden, " .. failed .. " fehlgeschlagen")
	return passed, failed
end
