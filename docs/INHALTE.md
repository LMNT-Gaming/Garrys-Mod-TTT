# Spielinhalte

## Rollen (TTT2)

| Rolle | Team | Ab Spielern | Fähigkeit |
|---|---|---|---|
| **Narr** | eigenes Team | 6 | Kann keinen Schaden austeilen. Wird er von einem Spieler getötet, gewinnt er allein (mit Sound und Einblendung). Traitor erkennen ihn. |
| **Sanitäter** | Innocent | 5 | Startet mit der **Medigun**. Sieht die HP und eine Vergiftung von Spielern, die er ansieht. |
| **Hacker** | Traitor | 7 | Startet mit dem **Hacker-Tablet** und 3 Credits, hat Zugriff auf den Traitor-Shop. |

Verteilung, Mindestspieler und Ein/Aus stellst du im TTT2-Menü (F1 → Rollen) oder per ConVar ein (`ttt_narr_enabled`, `ttt_narr_pct`, `ttt_narr_min_players` …).
Die Rollen-Icons sind vorerst **Platzhalter** und nutzen die Innocent- bzw. Traitor-Textur von TTT2. Eigene Icons legst du als `materials/vgui/ttt/dynamic/roles/icon_nar.vtf` (bzw. `icon_san`, `icon_hck`) ab und trägst sie in der passenden `.vmt` ein.

## Waffen

| Waffe | Erhältlich | Wirkung |
|---|---|---|
| **Medigun** | Sanitäter (Start) | Links: andere heilen (2 HP / 0,15 s, 120 Einheiten Reichweite). Rechts: selbst heilen (halbe Rate). Entfernt Gift. 100 Ladung, lädt sich wieder auf. |
| **Hacker-Tablet** | Hacker (Start) | Alle Spieler sind für dein Team 6 s durch Wände sichtbar. Alle anderen hören ein Störsignal. 60 s Abklingzeit. |
| **Taser** | Detektiv-Shop | Lähmt das Ziel 4 s und lässt es seine Waffe fallen. Ein Schuss, lädt sich nach 30 s wieder auf. |
| **Giftpfeil** | Traitor-Shop | Lautlos. 10 Schaden sofort, danach 6 Schaden pro Sekunde für 10 s. 2 Schuss. |
| **Revolver** | Boden-Spawn | 40 Schaden, ×3 bei Kopftreffern, 6 Schuss, nutzt Deagle-Munition. |
| **Näherungsmine** | Traitor-Shop (ab 45 s) | Bodenmine, löst bei Annäherung für alle aus, 125 Schaden. Geduckt entschärfbar. |
| **Giftgasgranate** | Traitor-Shop (ab 30 s) | Giftwolke 12 s, 5 Schaden/s, höchstens 60 Schaden. |
| **Wurfmesser** | Traitor-Shop | 3 lautlose Messer, 34 Schaden (Kopf 51), kein Sofort-Kill. |
| **Schutzbarriere** | Detektiv-Shop | Kugelfeste Barrikade, 300 HP, 60 s, begehbar. |
| **Bewegungsmelder** | Detektiv-Shop | 2 Sensoren, melden Bewegung an Detektive – ohne Identität oder Rolle. |
| **Pumpgun** | Boden-Spawn | 10 × 9 Schaden, 6 Schuss, etwas mehr Reichweite als die TTT-Schrotflinte. |

Werte, Konter und Technik der sechs neuen Waffen: [inhalte/waffen.md](inhalte/waffen.md). Kaufregeln (Sperrzeit, Käufe pro Runde) sind ingame über die Einstellungen `shop.<klasse>.*` änderbar (`!weapons`, `!weapon <klasse>`).

## Shop-Items (passiv)

| Item | Shop | Wirkung |
|---|---|---|
| Turbo-Schuhe | Traitor, Detektiv | +25 % Laufgeschwindigkeit |
| Fallschutz | Traitor, Detektiv | kein Fallschaden |
| Regeneration | Detektiv | +1 HP alle 2 s |
| Leisetreter | Traitor | andere hören deine Schritte nicht |
| Adrenalin | Traitor, Detektiv | bei ≤ 30 HP einmal pro Leben +30 HP und 6 s lang 30 % schneller |
| Explosionsschutz | Traitor, Detektiv | Explosions- und Feuerschaden halbiert |
| Energieschild | Traitor, Detektiv | Schild mit 40 Punkten vor der Gesundheit (ab 20 s nach Rundenstart) |
| Lebenszeichen-Monitor | Detektiv | meldet Tode im Umkreis von ca. 45 m mit gerundeter Entfernung |

Details zu den fünf neuen Items: [inhalte/items.md](inhalte/items.md).

Im TTT2-Shop-Editor (F1 → Shop-Editor) kannst du jede Waffe und jedes Item beliebigen Rollen zuweisen.

## Spezialrunden

Eine Spezialrunde startet mit 20 % Wahrscheinlichkeit, ab 4 Spielern und mit mindestens 2 normalen Runden Abstand. Einstellbar in `lmnt_ttt/sh_config.lua`. Admins setzen die nächste Runde mit `!special <id>` fest.

| ID | Name | Effekt |
|---|---|---|
| `mond` | Mondlandung | niedrige Schwerkraft |
| `turbo` | Turbo-Runde | alle sind 40 % schneller |
| `kopfjaeger` | Kopfjäger | Kopftreffer ×1,5, alles andere ×0,4 |
| `vampir` | Vampirnacht | 30 % des verursachten Schadens heilen |
| `schwarzmarkt` | Schwarzmarkt | Traitor und Detektive erhalten +2 Credits |
| `kettenreaktion` | Kettenreaktion | Leichen explodieren nach 3 s (45 Schaden, Radius 220) |
| `wackelkopf` | Wackelköpfe | riesige Köpfe (nur optisch) |

## Level und Statistik

- **XP pro Runde:** Kill +15, Teamkill −30, Sieg +30, Überleben +10, Teilnahme +5. Einen Narren zu töten zählt weder positiv noch negativ.
- **Benötigte XP für das nächste Level:** `100 · Level^1,35`. Beim Level-up gibt es Effekt und Sound, und alle erfahren es im Chat.
- **MVP:** Wer in einer Runde die meisten Kills hat (mindestens 2), bekommt +10 Punkte.
- Gezählt wird erst ab 4 Spielern (`StatsMinPlayers`), um Farming zu verhindern.
- Sichtbar ist das Level als `[Lvl X]` im Chat, als Spalte „Lvl“ im Scoreboard und in der XP-Leiste. Die Leiste erscheint während der Vorbereitung und wenn du tot bist.

## Pointshop (`F4` oder `!shop`)

- **Punkte:** Kill +5, Sieg +15, Überleben +5, Teilnahme +2. Neue Spieler starten mit 100 Punkten, VIPs bekommen ×1,5.
- **Kategorien:** 10 Spielermodelle, 5 Hüte, 6 Spuren. Alles stammt aus den Inhalten von GMod und HL2, es ist also **kein Download** nötig.
- Ein Rechtsklick auf ein gekauftes Item verkauft es für 50 % des Preises. VIP-Items sind markiert.
- Modell und Spur ändern sich während einer laufenden Runde erst beim nächsten Spawn. So verrät ein Wechsel niemanden.
- Den Katalog bearbeitest du in `lmnt_ttt/sh_pointshop.lua`. Bei Hüten lassen sich die Werte `up`, `forward`, `scale` und `ang` feinjustieren.

## LMNT-HUD und Menü-Skin

- Das HUD **`lmnt`** ist ein normales TTT2-HUD auf Basis von `pure_skin` mit sieben eigenen Elementen (Spielerinfo, Rundeninfo, Waffeninfo, Waffenwechsel, Mini-Scoreboard, Seitenleiste, Team-Anzeige) im LMNT-Design.
- Beim ersten Besuch wird es zusammen mit dem F1-Menü-Skin `lmnt_ttt2` einmalig ausgewählt. Spieler können jederzeit im TTT2-Menü (F1 → HUD) zurückwechseln.
- Verschieben, Skalieren und Grundfarbe funktionieren über den TTT2-HUD-Editor.
- Technik und bekannte Grenzen: [framework/api/hud.md](framework/api/hud.md).
