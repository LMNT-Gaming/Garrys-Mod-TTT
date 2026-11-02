-- LMNT-Metadaten für die Items der zweiten Welle (Definition: lua/terrortown/entities/items, Wirkung: lua/lmnt_ttt/items)
-- Doku: docs/inhalte/items.md
local R = LMNT.Weapons.Register

R("item_lmnt_leisetreter", {
	displayName = "Leisetreter", category = "Passiv", kind = "item", sourceAddon = "lmnt_ttt", balanceProfile = "tarnung",
	description = "Andere hören deine Schritte nicht (Traitor-Shop, 1 Credit).",
	shop = { maxPerRound = 1 },
	notes = { "Gegenspiel: Sichtkontakt – wer lautlos rennt, fällt auf. Sprünge, Landungen und Schüsse bleiben hörbar" },
})

R("item_lmnt_adrenalin", {
	displayName = "Adrenalin", category = "Passiv", kind = "item", sourceAddon = "lmnt_ttt", balanceProfile = "überleben",
	description = "Einmal pro Leben bei <= 30 HP: +30 HP und 6 s +30 % Tempo (Traitor- und Detektiv-Shop, 1 Credit).",
	shop = { maxPerRound = 1 },
	notes = { "Rettet nicht vor tödlichem Schaden; Auslösung ist hörbar (Medkit-Geräusch)" },
})

R("item_lmnt_explosionsschutz", {
	displayName = "Explosionsschutz", category = "Passiv", kind = "item", sourceAddon = "lmnt_ttt", balanceProfile = "schutz",
	description = "Halbiert Explosions- und Feuerschaden (Traitor- und Detektiv-Shop, 1 Credit).",
	shop = { maxPerRound = 1 },
	notes = { "Überschneidet sich mit den TTT2-Items item_ttt_noexplosiondmg/nofiredmg (je 100 %), Faktoren multiplizieren sich" },
})

R("item_lmnt_energieschild", {
	displayName = "Energieschild", category = "Passiv", kind = "item", sourceAddon = "lmnt_ttt", balanceProfile = "überleben",
	description = "Fängt einmalig 40 Schaden ab, danach verbraucht (Traitor- und Detektiv-Shop, 1 Credit).",
	shop = { maxPerRound = 1, lockSeconds = 20 },
	notes = { "Sperrzeit: kein Schild-Vorteil im ersten Gefecht direkt nach Rundenstart", "Bruch des Schilds ist hörbar" },
})

R("item_lmnt_lebenszeichen", {
	displayName = "Lebenszeichen-Monitor", category = "Passiv", kind = "item", sourceAddon = "lmnt_ttt", balanceProfile = "information",
	description = "Meldet Tode im Umkreis von ~45 m mit Entfernung und Zeit (Detektiv-Shop, 1 Credit).",
	shop = { maxPerRound = 1 },
	notes = { "Informationsschutz: kein Name, keine Rolle, kein Täter, keine Richtung – nur gerundete Entfernung" },
})
