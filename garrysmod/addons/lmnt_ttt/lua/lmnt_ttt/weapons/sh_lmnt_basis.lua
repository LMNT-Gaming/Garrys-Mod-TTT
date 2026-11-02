-- LMNT-Metadaten für die mitgelieferte Ausrüstung (Implementierung: lua/weapons, lua/terrortown/entities/items)
local R = LMNT.Weapons.Register

R("weapon_lmnt_taser", {
	displayName = "Taser", category = "Gerät", sourceAddon = "lmnt_ttt", balanceProfile = "kontrolle",
	description = "Lähmt 4 s und entwaffnet, ein Schuss, lädt in 30 s nach (Detektiv-Shop).",
	shop = { maxPerRound = 1 },
})

R("weapon_lmnt_giftpfeil", {
	displayName = "Giftpfeil", category = "Präzision", sourceAddon = "lmnt_ttt", balanceProfile = "schaden-über-zeit",
	description = "Lautlos, 10 + 6/s für 10 s, 2 Schuss, durch Sanitäter heilbar (Traitor-Shop).",
	shop = { maxPerRound = 1, lockSeconds = 30 },
	notes = { "Sperrzeit verhindert Vergiftungen direkt beim Rundenstart" },
})

R("weapon_lmnt_revolver", {
	displayName = "Revolver", category = "Pistole", sourceAddon = "lmnt_ttt", balanceProfile = "standard",
	description = "Bodenwaffe: 40 Schaden, x3 Kopftreffer, 6 Schuss.",
})

R("weapon_lmnt_medigun", {
	displayName = "Medigun", category = "Gerät", sourceAddon = "lmnt_ttt", balanceProfile = "unterstützung",
	description = "Rollenwaffe des Sanitäters (nicht kaufbar).",
})

R("weapon_lmnt_hacktablet", {
	displayName = "Hacker-Tablet", category = "Gerät", sourceAddon = "lmnt_ttt", balanceProfile = "information",
	description = "Rollenwaffe des Hackers (nicht kaufbar).",
	notes = { "Informationsschutz: Durchsicht nur für das eigene Team, Gegner hören ein Störsignal" },
})

R("item_lmnt_turbo", { displayName = "Turbo-Schuhe", category = "Passiv", kind = "item", sourceAddon = "lmnt_ttt", description = "+25 % Laufgeschwindigkeit." })
R("item_lmnt_fallschutz", { displayName = "Fallschutz", category = "Passiv", kind = "item", sourceAddon = "lmnt_ttt", description = "Kein Fallschaden." })
R("item_lmnt_regeneration", { displayName = "Regeneration", category = "Passiv", kind = "item", sourceAddon = "lmnt_ttt", description = "+1 HP alle 2 s." })
