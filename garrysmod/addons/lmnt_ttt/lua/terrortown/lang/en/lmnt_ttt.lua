-- LMNT TTT – English role texts (keys: see de/lmnt_ttt.lua)
local L = LANG.GetLanguageTableReference("en")

L["narr"] = "Jester"
L["info_popup_narr"] = [[You are the JESTER!
You cannot deal damage. If another player kills you, you win the round alone.
Act suspicious – but beware: the traitors know who you are.]]
L["ttt2_desc_narr"] = [[The Jester cannot deal damage. If killed by another player, the Jester wins alone. Traitors can see the Jester.]]
L["body_found_nar"] = "They were a Jester."
L["hilite_win_narrs"] = "THE JESTER WINS"
L["win_narrs"] = "The Jester fooled everyone!"

L["sanitaeter"] = "Medic"
L["info_popup_sanitaeter"] = [[You are a MEDIC (Team Innocent)!
Your medigun heals others (left click) or yourself (right click) and cures poison.
Look at players to see their health.]]
L["ttt2_desc_sanitaeter"] = [[The Medic is an innocent. The medigun heals and cures poison. The Medic can see the health of other players.]]
L["body_found_san"] = "They were a Medic."

L["hacker"] = "Hacker"
L["info_popup_hacker"] = [[You are a HACKER (Team Traitor)!
Your tablet reveals all players through walls to your team for 6 seconds (60 s cooldown).
Beware: everyone else hears the interference. Press {menukey} to open the traitor shop.]]
L["ttt2_desc_hacker"] = [[The Hacker is a traitor. The tablet briefly reveals all players through walls but gives itself away with interference. Has access to the traitor shop.]]
L["body_found_hck"] = "They were a Hacker."
