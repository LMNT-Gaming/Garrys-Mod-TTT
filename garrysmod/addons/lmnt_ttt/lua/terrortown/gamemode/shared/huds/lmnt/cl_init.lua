---
-- LMNT-HUD für TTT2 (HUD-ID "lmnt" = Ordnername, sh_hud_module.lua:117-119 in TTT2 0.14.6b)
-- TTT2 lädt terrortown/gamemode/shared/huds/<ordner>/: Server AddCSLuaFile für jede Datei,
-- Client include nur cl_init.lua (sh_hud_module.lua:3-20). Auf dem Server ist das HUD dadurch
-- ein leerer, aber gültiger Eintrag (sv_hud_manager.lua prüft huds.GetStored beim Wechsel).
--
-- Baut auf pure_skin auf (ADR-004): Editor, Speichern, Zurücksetzen und Skalierung kommen aus
-- hud_base/scalable_hud, die Spiellogik aus den pure_skin-Elementen. Die LMNT-Elemente ersetzen
-- nur die Darstellung. Doku: docs/framework/api/hud.md

local base = "pure_skin"

DEFINE_BASECLASS(base)

HUD.Base = base

-- Grundfarbe aller Flächen: Ink #08070c, leicht transparent. Spieler können sie im HUD-Menü ändern
-- (Speicher-Key basecolor aus scalable_hud). Die übernommenen pure_skin-Elemente nutzen sie ebenfalls.
HUD.defaultcolor = Color(8, 7, 12, 235)

-- In 0.14.6b nirgends angezeigt. Gesetzt, damit nicht das Vorschaubild von pure_skin geerbt wird.
HUD.previewImage = Material("vgui/ttt/score_logo_2")

---
-- Erzwingt die LMNT-Elemente. ForceElement belegt einen Typ nur, wenn er noch frei ist
-- (hud_base/cl_init.lua:34-40), deshalb stehen sie vor BaseClass.Initialize. pure_skin erzwingt
-- danach seine Elemente für die übrigen Typen (Nachrichten, Ziel-ID, Aufheben, Ertrinken,
-- Faustschlag, Wiederbelebung). Typen ohne Erzwingung (DNA-Scanner, Ereignis-Popup, Sprachchat)
-- wählt hud_base wie bisher automatisch.
-- @realm client
function HUD:Initialize()
	self:ForceElement("lmnt_playerinfo")
	self:ForceElement("lmnt_roundinfo")
	self:ForceElement("lmnt_teamindicator")
	self:ForceElement("lmnt_miniscoreboard")
	self:ForceElement("lmnt_weaponinfo")
	self:ForceElement("lmnt_wswitch")
	self:ForceElement("lmnt_sidebar")

	BaseClass.Initialize(self)
end
