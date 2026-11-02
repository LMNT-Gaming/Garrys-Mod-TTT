-- LMNT TTT – deutsche Texte für Rollen
-- Genutzte Schlüssel (TTT2 0.14.6b): <rolle>, info_popup_<rolle> (cl_popups.lua), ttt2_desc_<rolle>,
-- body_found_<abkürzung> (sv_corpse.lua), win_<team> (sv_main.lua), hilite_win_<team> (cl_scoring.lua)
local L = LANG.GetLanguageTableReference("de")

-- Narr
L["narr"] = "Narr"
L["info_popup_narr"] = [[Du bist der NARR!
Du kannst niemandem Schaden zufügen. Wirst du von einem anderen Spieler getötet, gewinnst du die Runde allein.
Sei verdächtig, provoziere – aber pass auf: Die Traitor wissen, wer du bist.]]
L["ttt2_desc_narr"] = [[Der Narr kann niemandem schaden. Wird er von einem anderen Spieler getötet, gewinnt er allein. Traitor erkennen ihn.]]
L["body_found_nar"] = "Er/Sie war ein Narr."
L["hilite_win_narrs"] = "DER NARR GEWINNT"
L["win_narrs"] = "Der Narr hat alle reingelegt!"

-- Sanitäter
L["sanitaeter"] = "Sanitäter"
L["info_popup_sanitaeter"] = [[Du bist SANITÄTER (Team Innocent)!
Mit deiner Medigun heilst du andere (Linksklick) oder dich selbst (Rechtsklick) und entfernst Gift.
Schau Spieler an, um ihre Gesundheit zu sehen.]]
L["ttt2_desc_sanitaeter"] = [[Der Sanitäter gehört zu den Innocents. Seine Medigun heilt und entfernt Gift. Er sieht die Gesundheit anderer Spieler.]]
L["body_found_san"] = "Er/Sie war Sanitäter."

-- Hacker
L["hacker"] = "Hacker"
L["info_popup_hacker"] = [[Du bist HACKER (Team Traitor)!
Dein Tablet zeigt deinem Team 6 Sekunden lang alle Spieler durch Wände (60 s Abklingzeit).
Achtung: Die anderen hören dabei ein Störsignal. Mit {menukey} öffnest du den Traitor-Shop.]]
L["ttt2_desc_hacker"] = [[Der Hacker gehört zu den Traitorn. Sein Tablet enthüllt kurz alle Spieler durch Wände, verrät sich aber durch ein Störsignal. Zugriff auf den Traitor-Shop.]]
L["body_found_hck"] = "Er/Sie war ein Hacker."
