--[[
	Integration "ulx": nur Erkennung (kein Adapter)
	LMNT-Admin ist das führende Rechtesystem (ADR-011). Läuft ULX/ULib zusätzlich, gibt es zwei
	Rechtesysteme mit eigenen Rängen und Befehlen – das wird als Konflikt gemeldet.
	Umstieg: einmalige Migration mit !ulximport (lua/lmnt/services/sh_ulximport.lua), danach ULX entfernen.
]]

LMNT.Integrations.Register("ulx", {
	name = "ULX / ULib",
	description = "Verbreitetes Admin-Mod – Erkennung zur Konfliktmeldung",
	version = "1.0.0",
	vendor = "Team Ulysses",
	lmnt = "1.2.0",
	detectOnly = true,

	detect = function()
		local evidence = {}
		if istable(ULib) then evidence[#evidence + 1] = "Global ULib-Tabelle" end
		if istable(ULib) and istable(ULib.ucl) then evidence[#evidence + 1] = "ULib.ucl (Rechteverwaltung) vorhanden" end
		if istable(ulx) then evidence[#evidence + 1] = "Global ulx-Tabelle" end
		local version = istable(ULib) and (ULib.VERSION or ULib.version) or nil
		return istable(ULib) and istable(ulx), evidence, version and tostring(version) or nil
	end,

	conflictsWithCore = {
		{ with = "lmnt.admin", description = "ULX ist neben dem führenden LMNT-Admin-System aktiv – Ränge und Befehle können sich widersprechen. Empfehlung: !ulximport (Probelauf), dann !ulximport ausfuehren und ULX entfernen (ADR-011)" },
	},

	limitations = {
		"Kein laufender Abgleich: ULX-Änderungen nach der Migration werden nicht übernommen (ADR-011)",
		"Migration nur mit ULib-Beispieldaten getestet, solange ULX nicht installiert ist",
	},
})
