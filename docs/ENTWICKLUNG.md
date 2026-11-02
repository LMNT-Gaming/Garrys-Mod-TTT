# LMNT-Framework – Entwickler-Referenz

## Aufbau und Ladereihenfolge

1. `lmnt_core/lua/autorun/lmnt_core_init.lua` lädt core und admin über `LMNT.LoadModule`. Der Dateipräfix bestimmt den Realm: `sv_` nur Server, `cl_` nur Client, `sh_` beides.
2. `lmnt_ttt/lua/autorun/lmnt_ttt_init.lua` wartet auf `PostGamemodeLoaded` und lädt die TTT-Module nur, wenn `terrortown` läuft.
3. Rollen, Items und Waffen lädt TTT2 selbst aus `lua/terrortown/entities/…` und `lua/weapons/`.

Hooks des Frameworks: `LMNT.Loaded`, `LMNT.TTT.Loaded`, `LMNT.AdminMenu.Build(tabs)` und `LMNT.ChatPrefix(ply)` (Rückgabe: Tabelle mit Farben und Texten).

## Core-API

```lua
LMNT.Notify(nil, Color(0,190,255), "An alle")       -- nil = alle, Spieler oder Tabelle
LMNT.Notify(ply, "Hallo ", otherPly, "!")            -- Spieler werden in Rangfarbe dargestellt
LMNT.Reply(caller, "Antwort")                        -- funktioniert auch für die Serverkonsole
LMNT.Announce("Großer Text", Color(255,80,170), 6)   -- Bildschirm-Einblendung
LMNT.Log("kategorie", "Text")                        -- DB + data/lmnt/logs/
LMNT.DB.Query("SELECT * FROM t WHERE id = ?", id)    -- sichere Platzhalter
LMNT.HasPerm(ply, "kick"), LMNT.CanTarget(a, b)
LMNT.FindPlayers(caller, "max"), LMNT.ParseTime("1d"), LMNT.FormatMinutes(90)
LMNT.UI.Frame / Button / Tabs / StyleList            -- Client-UI im LMNT-Look
```

## Eigener Befehl

In einer `sh_`-Datei:

```lua
LMNT.Admin.AddCommand("heilen", {
	perm = "hp",                        -- Recht aus sh_ranks.lua (nil = alle)
	help = "Heilt Spieler vollständig",
	args = { { type = "players", name = "spieler" } },
	run = function(caller, targets)
		for _, t in ipairs(targets) do t:SetHealth(t:GetMaxHealth()) end
		LMNT.Admin.Broadcast(caller, "hat", targets, " geheilt")
	end,
})
```

Der Befehl funktioniert danach sofort im Chat, in der Konsole und im Admin-Menü. Argumenttypen: `player`, `players`, `steamid`, `number` (`min`, `max`), `string` (`rest = true` nimmt den Rest der Zeile), `time`, `rank`, `map`. Optionen: `optional`, `default` (Wert oder Funktion), `ignoreImmunity`.

## Eigene Spezialrunde

```lua
LMNT.TTT.AddSpecial({
	id = "einhand", name = "Einhändig", color = Color(200, 120, 255),
	desc = "Nur Pistolen erlaubt!", weight = 8,
	start = function() end, stop = function() end,
	speed = 1.0,
})
-- eigene Hooks prüfen mit: if LMNT.TTT.IsSpecial("einhand") then … end
```

## Eigenes Shop-Item

In `sh_pointshop.lua`:

```lua
add("mdl_monk", { category = "model", name = "Pater Grigori", price = 900, model = "models/player/monk.mdl" })
```

## Neue Rolle

Lege den Ordner `lua/terrortown/entities/roles/<name>/shared.lua` an und orientiere dich an `sanitaeter` (Unterrolle) oder `narr` (eigenes Team). Die Texte gehören in `lua/terrortown/lang/de/lmnt_ttt.lua`. TTT2 legt die ConVars `ttt_<name>_enabled` usw. automatisch an.

## Datenbank-Tabellen (sv.db)

`lmnt_users`, `lmnt_bans`, `lmnt_warns`, `lmnt_logs`, `lmnt_slaynr`, `lmnt_ttt_stats`, `lmnt_ps_inventory`
