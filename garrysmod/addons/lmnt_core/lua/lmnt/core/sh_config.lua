--[[
	LMNT Framework – Grundkonfiguration
	Alles, was Servername, Farben, Regeln und Admin-Verhalten betrifft.
]]

LMNT.Config = LMNT.Config or {}
local C = LMNT.Config

C.ServerName = "LMNT | TTT2"
C.Prefix     = "LMNT"
C.Discord    = "discord.gg/DEIN-INVITE"
C.Website    = "https://example.com"

-- Owner-Bootstrap: diese SteamID64s erhalten beim Join automatisch den Rang "owner".
-- Empfohlen: OWNERS in server\settings.ini setzen – deploy.ps1 schreibt daraus data/lmnt/owners.txt.
-- Deine SteamID64 findest du z. B. auf steamid.io.
C.Owners = {
}

-- Chat-Präfixe für Befehle (!kick, /kick). "/" blendet den Befehl immer aus.
C.ChatPrefixes = { "!", "/" }

-- Verwarnungen: ab X Warns automatischer Kick bzw. Bann (Minuten)
C.WarnKickAt     = 3
C.WarnBanAt      = 5
C.WarnBanMinutes = 1440

-- Logs älter als X Tage werden beim Serverstart entfernt
C.LogRetentionDays = 30

C.Rules = {
	"1. Kein RDM (Random Deathmatch) – töte nur mit Grund.",
	"2. Kein Ghosting – Tote verraten nichts an Lebende.",
	"3. Respektvoller Umgang in Chat und Voice.",
	"4. Kein Cheaten, kein Ausnutzen von Bugs.",
	"5. Den Anweisungen des Teams ist Folge zu leisten.",
}

C.Colors = {
	-- Marken-Tokens aus lmnt-gaming.net (assets/css/app.css, :root) – siehe docs/framework/05_DESIGNSYSTEM.md
	primary = Color(255, 49, 49),     -- --acid   #ff3131
	accent  = Color(225, 15, 34),     -- --coral  #e10f22
	deep    = Color(168, 0, 22),      -- --violet #a80016 (Dunkelrot)
	text    = Color(242, 239, 232),   -- --paper  #f2efe8
	white   = Color(255, 253, 248),   -- --white  #fffdf8
	muted   = Color(165, 161, 172),   -- --muted  #a5a1ac
	good    = Color(55, 230, 107),    -- #37e66b (Online-Status der Website)
	-- Für das Spiel ergänzt (kontrastgeprüft auf ink)
	bad     = Color(255, 110, 110),
	warn    = Color(255, 176, 32),
	info    = Color(127, 180, 255),
	-- Flächen
	bg      = Color(8, 7, 12, 248),   -- --ink      #08070c
	panel   = Color(17, 16, 24),      -- --ink-soft #111018
	panel2  = Color(28, 26, 37),      -- Hover/erhöhte Fläche
	line    = Color(255, 255, 255, 36), -- --line rgba(255,255,255,.14)
}

-- Marken-Schriften (resource/fonts, per FastDL verteilt, OFL-lizenziert). Namen = interne Familiennamen der TTF.
C.Fonts = {
	display = "Archivo Black",
	body    = "DM Sans",
	medium  = "DM Sans Medium",
	files   = { "ArchivoBlack-Regular.ttf", "DMSans-Regular.ttf", "DMSans-Medium.ttf", "DMSans-Bold.ttf" },
}
