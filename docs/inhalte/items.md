# Shop-Items (zweite Welle)

Fünf passive TTT2-Items aus `lmnt_ttt`. Pro Item gibt es drei Teile:

| Teil | Ort |
|---|---|
| TTT2-Definition (Name, Shop, Credits, Icon) | `garrysmod/addons/lmnt_ttt/lua/terrortown/entities/items/item_lmnt_<name>/shared.lua` |
| Wirkung (Modul `ttt.items`, abschaltbar) | `garrysmod/addons/lmnt_ttt/lua/lmnt_ttt/items/<realm>_<name>.lua` |
| LMNT-Metadaten und Kaufregeln (Modul `ttt.shop`) | `garrysmod/addons/lmnt_ttt/lua/lmnt_ttt/weapons/sh_neue_items.lua` |

Tests: `garrysmod/addons/lmnt_ttt/lua/lmnt/tests/sv_neue_items.lua` (`lmnt test`).

## Übersicht

| Item | Klasse | Shop | Credits | LMNT-Regel |
|---|---|---|---|---|
| Leisetreter | `item_lmnt_leisetreter` | Traitor | 1 | 1× pro Runde |
| Adrenalin | `item_lmnt_adrenalin` | Traitor, Detektiv | 1 | 1× pro Runde |
| Explosionsschutz | `item_lmnt_explosionsschutz` | Traitor, Detektiv | 1 | 1× pro Runde |
| Energieschild | `item_lmnt_energieschild` | Traitor, Detektiv | 1 | 1× pro Runde, ab 20 s nach Rundenstart |
| Lebenszeichen-Monitor | `item_lmnt_lebenszeichen` | Detektiv | 1 | 1× pro Runde |

Alle Items sind `limited` (TTT2: kein zweites Exemplar, solange man eins hat). Credits, Rollen und
`limited` lassen sich zusätzlich im TTT2-Shop-Editor ändern. Die LMNT-Regeln stehen als Einstellungen
`shop.<klasse>.enabled | max_per_round | lock_seconds` bereit (`!weapon <klasse>`).

Alle Wirkungen entscheidet nur der Server. Zustände am Spieler werden bei Tod, Spawn, Rundenvorbereitung
und beim Abschalten des Moduls `ttt.items` zurückgesetzt. TTT2 entfernt die Items selbst bei Tod
(`DoPlayerDeath → StripAll → ResetEquipment`) und beim Spawn (`ResetRoundFlags`).

## Leisetreter

- **Wirkung:** Andere Spieler hören deine Schrittgeräusche nicht. Du hörst sie selbst weiter.
- **Technik:** Ein serverseitiger `PlayerFootstep`-Hook gibt `true` zurück und unterdrückt damit das Geräusch,
  das der Server an die anderen Spieler schickt. So arbeitet auch TTT2 beim Schleichen (`GM:PlayerFootstep`
  in `sh_main.lua`). Andere Clients bekommen keine Information, wer das Item trägt.
- **Gegenspiel:** Sichtkontakt. Wer lautlos sprintet, fällt auf. Sprünge, Landungen, Schüsse und Türen bleiben hörbar.
- **Grenzen:** Nur Schrittgeräusche. Mods, die eigene Schrittgeräusche abspielen, werden nicht erfasst.

## Adrenalin

- **Wirkung:** Fällt deine Gesundheit durch Schaden auf 30 HP oder weniger und du überlebst, bekommst du
  einmal pro Leben sofort +30 HP (höchstens bis zur Maximalgesundheit) und läufst 6 Sekunden lang 30 % schneller.
  Ein TTT2-Status-Icon mit Restzeit erscheint (`STATUS:AddTimedStatus`).
- **Gegenspiel:** Die Auslösung ist für Umstehende hörbar (Medkit-Geräusch). Wer nachsetzt, kann den Träger noch
  erwischen, denn ein tödlicher Treffer wird nicht abgefangen.
- **Grenzen:** Nur in der aktiven Runde. Wirkt einmal pro Leben, ein Neukauf in derselben Runde ist durch die
  LMNT-Regel ausgeschlossen. Andere Spieler sehen kein Icon.

## Explosionsschutz

- **Wirkung:** Explosionsschaden (`DMG_BLAST`) und Feuerschaden (`DMG_BURN`, `DMG_SLOWBURN`) werden halbiert.
- **Gegenspiel:** Normale Waffen wirken voll. Zwei Granaten oder eine Explosion plus Beschuss reichen weiterhin.
- **Grenzen:** TTT2 bringt eigene Items mit 100 % Schutz mit (`item_ttt_noexplosiondmg`, `item_ttt_nofiredmg`).
  Wer beide Arten trägt, bekommt das Produkt der Faktoren (0 bleibt 0). Soll nur eine Variante im Shop sein,
  das jeweils andere Item im TTT2-Shop-Editor oder über `shop.item_lmnt_explosionsschutz.enabled` abschalten.

## Energieschild

- **Wirkung:** Ein Schild mit 40 Punkten fängt Schaden ab, bevor die Gesundheit sinkt. Ist er leer, bricht er
  hörbar und das Item wird entfernt. Der Restwert steht am Symbol in der Seitenleiste (nur für den Träger sichtbar).
- **Gegenspiel:** 40 zusätzliche Schadenspunkte, also etwa ein bis zwei Treffer mehr. Der Bruch ist hörbar.
  Kaufbar erst 20 s nach Rundenstart.
- **Grenzen:** Kein Schutz vor Fall- und Ertrinkungsschaden. Der Schild wirkt vor der TTT2-Rüstung.
  Die Reihenfolge zu anderen `EntityTakeDamage`-Hooks (z. B. Explosionsschutz) legt GMod nicht fest.

## Lebenszeichen-Monitor

- **Wirkung:** Stirbt ein Spieler in bis zu 2400 Einheiten (etwa 45 m) Entfernung, bekommt der Träger eine
  Meldung „Lebenszeichen erloschen – ca. X m entfernt“ (auf 5 m gerundet) und einen Signalton.
  Am Symbol in der Seitenleiste steht, wie viele Sekunden das her ist.
- **Informationsschutz:** Übertragen wird nur die gerundete Entfernung. Kein Name, keine Rolle, kein Team,
  kein Täter, keine Waffe, keine Richtung. Damit weiß der Detektiv nur, dass in der Nähe jemand gestorben ist.
- **Gegenspiel:** Traitor töten außerhalb der Reichweite oder schalten zuerst den Detektiv aus.
  Die Meldung zeigt nicht, wo genau die Leiche liegt.
- **Grenzen:** Nur in der aktiven Runde, nur für lebende Träger. Die Entfernung wird ohne Rücksicht auf Wände gemessen.

## Nur im Spiel prüfbar

- Leisetreter: mit zwei Spielern prüfen, dass der andere keine Schritte hört und der Träger seine eigenen schon.
- Adrenalin: Schwellwert, Heilung, Tempo-Schub, Status-Icon mit Restzeit und Geräusch.
- Explosionsschutz: halber Schaden durch Granate, Brandgranate und explodierendes Fass.
- Energieschild: Restanzeige am Symbol, Bruchgeräusch, Item nach dem Bruch weg, neuer Schild nach Tod oder Rundenwechsel.
- Lebenszeichen-Monitor: Meldung und Sekundenanzeige, keine Meldung über 45 m, Anzeige nach eigenem Tod leer.
- Icons im Shop und in der Seitenleiste (LMNT-HUD und TTT2-Standard-HUD).
