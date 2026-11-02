-- LMNT-Metadaten für die sechs neuen Waffen (Implementierung: lua/weapons, lua/entities) · Doku: docs/inhalte/waffen.md
local R = LMNT.Weapons.Register

------------------------------------------------------------------------
-- Traitor
------------------------------------------------------------------------

R("weapon_lmnt_naeherungsmine", {
	displayName = "Näherungsmine", category = "Gerät", sourceAddon = "lmnt_ttt", balanceProfile = "falle",
	description = "Bodenmine: 3 s Scharfschaltzeit, Warnton, 0,9 s später 125 Schaden (Radius 260). Traitor-Shop.",
	shop = { maxPerRound = 1, lockSeconds = 45 },
	notes = {
		"Sperrzeit: keine Minen an den Spawnpunkten direkt nach Rundenbeginn",
		"Konter: geduckt schleichen löst nicht aus, geduckt mit E oder Entschärfer entschärfen, 40 HP zum Zerschießen, DNA-Spuren",
		"Informationsschutz: löst für alle gleich aus (auch Traitor/Leger); der Leger wird nicht an Clients übertragen",
	},
})

R("weapon_lmnt_giftgas", {
	displayName = "Giftgasgranate", category = "Granate", sourceAddon = "lmnt_ttt", balanceProfile = "flächenverbot",
	description = "Giftwolke 12 s, 5 Schaden/s im Radius 190, nicht durch Wände. Traitor-Shop.",
	shop = { maxPerRound = 1, lockSeconds = 30 },
	notes = {
		"Höchstens 60 Schaden, wenn man die ganze Zeit in der Wolke bleibt – hinauslaufen ist der Konter",
		"Trifft jeden gleich, auch den Werfer (kein Rollen-Leck); als WEAPON_EQUIP2, blockiert keine Boden-Granate",
	},
})

R("weapon_lmnt_wurfmesser", {
	displayName = "Wurfmesser", category = "Nahkampf", sourceAddon = "lmnt_ttt", balanceProfile = "lautlos",
	description = "3 lautlose Wurfmesser, 34 Schaden, Kopftreffer 51, kein Sofort-Kill. Traitor-Shop.",
	shop = { maxPerRound = 1 },
	notes = {
		"Volle Lebenspunkte brauchen 3 Körper- oder 2 Kopftreffer",
		"Geworfene Messer bleiben 20 s als Spur liegen",
	},
})

------------------------------------------------------------------------
-- Detektiv
------------------------------------------------------------------------

R("weapon_lmnt_schutzbarriere", {
	displayName = "Schutzbarriere", category = "Gerät", sourceAddon = "lmnt_ttt", balanceProfile = "deckung",
	description = "Aufstellbare Barrikade, fängt Kugeln ab: 300 HP, 60 s. Detektiv-Shop.",
	shop = { maxPerRound = 1 },
	notes = {
		"Spieler können hindurchgehen – sie sperrt keine Türen oder Gänge",
		"Blockiert auch die Schüsse des Detektivs; Färbung zeigt allen die Resthaltbarkeit",
	},
})

R("weapon_lmnt_bewegungsmelder", {
	displayName = "Bewegungsmelder", category = "Gerät", sourceAddon = "lmnt_ttt", balanceProfile = "information",
	description = "2 Sensoren, melden Detektiven \"Bewegung erkannt\" + Sensorstandort (Radius 320, Sichtlinie). Detektiv-Shop.",
	shop = { maxPerRound = 1 },
	notes = {
		"Informationsschutz: gesendet werden nur Sensornummer und Sensorposition – keine Identität, Rolle, Anzahl, Richtung oder Spielerposition",
		"Höchstens eine Meldung alle 10 s pro Sensor; Schleichen (< 120 u/s) wird nicht erkannt",
		"Konter: Sensor ist sichtbar (LED), 30 HP",
	},
})

------------------------------------------------------------------------
-- Boden-Spawn
------------------------------------------------------------------------

R("weapon_lmnt_pumpgun", {
	displayName = "Pumpgun", category = "Schrot", sourceAddon = "lmnt_ttt", balanceProfile = "standard",
	description = "Bodenwaffe: 10 x 9 Schaden, Streuung 0.06, 6 Patronen, Buckshot (item_box_buckshot_ttt).",
	notes = { "Mehr Reichweite als die TTT-Schrotflinte (0.082), dafür langsamer (1,05 s) und kleineres Magazin" },
})
