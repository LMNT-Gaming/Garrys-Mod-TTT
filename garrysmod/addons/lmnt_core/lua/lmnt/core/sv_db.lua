--[[
	LMNT Framework – Datenbank (SQLite, garrysmod/sv.db)

	LMNT.DB.Query("SELECT * FROM t WHERE id = ?", id)   -> Zeilen (Tabelle) oder nil
	LMNT.DB.Row(...)                                      -> erste Zeile oder nil
	LMNT.DB.Value(...)                                    -> erster Wert der ersten Zeile

	"?" wird sicher ersetzt (Strings werden escaped, Zahlen direkt eingesetzt).
]]

LMNT.DB = LMNT.DB or {}

local function bind(query, args)
	local i = 0

	return (string.gsub(query, "%?", function()
		i = i + 1
		local v = args[i]

		if v == nil then return "NULL" end
		if isnumber(v) then return tostring(v) end
		if isbool(v) then return v and "1" or "0" end

		return sql.SQLStr(tostring(v))
	end))
end

function LMNT.DB.Query(query, ...)
	local q = bind(query, { ... })
	local result = sql.Query(q)

	if result == false then
		ErrorNoHalt("[LMNT][DB] " .. tostring(sql.LastError()) .. "\n    Query: " .. q .. "\n")
		return nil
	end

	return result
end

function LMNT.DB.Row(query, ...)
	local rows = LMNT.DB.Query(query, ...)
	return rows and rows[1] or nil
end

function LMNT.DB.Value(query, ...)
	local row = LMNT.DB.Row(query, ...)
	if not row then return nil end

	for _, v in pairs(row) do return v end
end

-- Führt fn innerhalb einer Transaktion aus. Wirft fn einen Fehler, wird zurückgerollt.
-- Rückgabe: true, Ergebnis  |  false, Fehlermeldung
-- Hinweis: SQLite in GMod ist synchron, verschachtelte Transaktionen werden nicht unterstützt.
function LMNT.DB.Transaction(fn)
	if LMNT.DB._inTransaction then
		return pcall(fn)
	end

	sql.Begin()
	LMNT.DB._inTransaction = true
	local ok, result = pcall(fn)
	LMNT.DB._inTransaction = false

	if ok then
		sql.Commit()
		return true, result
	end

	sql.Query("ROLLBACK")
	-- Behandelter Fehler: der Aufrufer erhält false + Meldung; daher Warnung statt Lua-Fehler
	if LMNT.Log and LMNT.Log.Warn then
		LMNT.Log.Warn("db", "Transaktion zurückgerollt: " .. tostring(result))
	else
		MsgC(Color(255, 176, 32), "[LMNT][DB] Transaktion zurückgerollt: " .. tostring(result) .. "\n")
	end
	return false, result
end

function LMNT.DB.ColumnExists(tableName, column)
	for _, col in ipairs(LMNT.DB.Query("PRAGMA table_info(" .. sql.SQLStr(tableName) .. ")") or {}) do
		if col.name == column then return true end
	end
	return false
end

-- Ergänzt eine Spalte, falls sie fehlt (einfache, idempotente Migration)
function LMNT.DB.EnsureColumn(tableName, column, definition)
	if LMNT.DB.ColumnExists(tableName, column) then return false end
	LMNT.DB.Query("ALTER TABLE " .. tableName .. " ADD COLUMN " .. column .. " " .. definition)
	return true
end
