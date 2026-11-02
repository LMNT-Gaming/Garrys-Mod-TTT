# LMNT-Waffen: Erweiterung „Neue Waffen“

Sechs neue Waffen für das LMNT-TTT2 (TTT2 0.14.6b): drei für Traitor, zwei für Detektive und eine Bodenwaffe.
Die Metadaten stehen in `lua/lmnt_ttt/weapons/sh_neue_waffen.lua` (LMNT.Weapons.Register), die Tests in
`lua/lmnt/tests/sv_neue_waffen.lua` (`!test`). Die Kaufregeln (Sperrzeit, Käufe pro Runde) lassen sich ingame
über die Einstellungen `shop.<klasse>.*` ändern. Credits und Rollen stellt man im TTT2-Shop-Editor ein.

Alle Modelle, Sounds und Icons kommen mit GMod, HL2 oder CS:S mit (geprüft gegen die VPK-Verzeichnisse
des Servers). Schaden entsteht nur auf dem Server über `DamageInfo` mit Angreifer = Besitzer bzw. Werfer und
Inflictor = Waffe oder Entity. Karma und Schadenslog greifen also wie bei TTT2-Waffen.

## Übersicht

| Waffe | Rolle / Shop | Credits | Werte | Gegenspiel / Konter | Informationsschutz |
|---|---|---|---|---|---|
| **Näherungsmine** `weapon_lmnt_naeherungsmine` | Traitor, 1× pro Runde, **ab 45 s** nach Rundenbeginn | 1 | Nur auf dem Boden. 3 s Scharfschaltzeit, Auslöseradius 110 (mit Sichtlinie), Warnton, 0,9 s später Explosion mit 125 Schaden im Zentrum, Radius 260 (fällt nach außen ab). 40 HP | Geduckt schleichen löst nicht aus. Geduckt mit **E** oder mit dem Detektiv-Entschärfer entschärfen. Zerschießen (verpufft ohne Explosion). Rotes Blinklicht, sobald scharf. DNA des Legers auf der Mine | Löst für **alle** aus, auch für Traitor und den Leger: Wer unbeschadet darüber läuft, ist dadurch nicht als Traitor erkennbar. Der Leger wird nicht an die Clients übertragen (kein vernetztes Originator-Feld) |
| **Giftgasgranate** `weapon_lmnt_giftgas` | Traitor, 1× pro Runde, ab 30 s | 1 | 3 s Zündzeit, Wolke 12 s, 5 Schaden/s im Radius 190, höchstens 60 Schaden. Ausrüstungsplatz (EQUIP2), kein Granatenplatz | Wolke verlassen. Wirkt nicht durch Wände. Grüne Wolke und Zischen sind gut sichtbar bzw. hörbar | Trifft jeden gleich, auch den Werfer und andere Traitor |
| **Wurfmesser** `weapon_lmnt_wurfmesser` | Traitor, 1× pro Runde | 1 | 3 Messer, lautlos, 34 Schaden, Kopftreffer 51, Bogenflug, 0,8 s zwischen Würfen. Kein Sofort-Kill | Volle Lebenspunkte brauchen 3 Körper- oder 2 Kopftreffer. Messer bleiben 20 s als Spur liegen. Gegenüber dem TTT-Messer schwächer, dafür auf Distanz | Keine Rollenlogik. Schaden für alle gleich |
| **Schutzbarriere** `weapon_lmnt_schutzbarriere` | Detektiv, 1× pro Runde | 1 | Barrikade vor dem Detektiv, fängt Kugeln ab, 300 HP, hält 60 s. Spieler können hindurchgehen | Zerschießen, umgehen, Granaten darüber werfen, 60 s abwarten. Sie blockiert auch die Schüsse des Detektivs. Ihre Färbung zeigt allen die Resthaltbarkeit | Gehört einer öffentlichen Rolle, daher nichts zu schützen. Sperrt keine Türen oder Gänge |
| **Bewegungsmelder** `weapon_lmnt_bewegungsmelder` | Detektiv, 1× pro Runde | 1 | 2 Sensoren für Wand oder Boden, 2 s Aktivierung. Erkennt Bewegung > 120 u/s im Radius 320 bei Sichtlinie. Meldung an alle lebenden Detektive, höchstens alle 10 s pro Sensor. Marker 6 s. 30 HP. Mit **E** (nur der Aufsteller) wieder einsammelbar | Schleichen oder geduckt gehen, Sichtlinie meiden, Sensor zerschießen (grüne LED blinkt) | Gesendet werden **nur** die Sensornummer und die **Sensorposition**. Keine Identität, Rolle, Anzahl, Richtung oder Spielerposition. Der Cooldown verhindert, dass man Personen mitverfolgt. Der Sensor reagiert auf alle Spieler gleich, nur der Aufsteller selbst wird ignoriert (seine Rolle ist ohnehin öffentlich) |
| **Pumpgun** `weapon_lmnt_pumpgun` | Boden-Spawn (Schrot) | – | 10 × 9 Schaden, Streuung 0.06, 1,05 s zwischen Schüssen, 6 Patronen (max. 24), Buckshot / `item_box_buckshot_ttt`. Kopfschuss-Multiplikator abhängig von der Entfernung (aus `weapon_zm_shotgun`). Kein Visier | Langsamer und kleineres Magazin als die TTT-Schrotflinte (11 × 8, 0.8 s, 8 Schuss), dafür etwas mehr Reichweite | – |

## Technik

| Waffe | SWEP-Basis | Entity | Kind / Slot | Icon | Modell |
|---|---|---|---|---|---|
| Näherungsmine | `weapon_tttbase` | `lmnt_naeherungsmine` (Basis `ttt_base_placeable`, `Defusable`/`Disarm`) | WEAPON_EQUIP1 / 6 | `vgui/ttt/icon_splode` | `props_combine/combine_mine01.mdl` |
| Giftgasgranate | `weapon_tttbasegrenade` | `lmnt_giftgas_proj` (Basis `ttt_basegrenade_proj`) | WEAPON_EQUIP2 / 7 | `vgui/ttt/icon_smokegrenade` | CS:S-Rauchgranate |
| Wurfmesser | `weapon_tttbase` | `lmnt_wurfmesser_proj` (nach dem Vorbild von `ttt_knife_proj`) | WEAPON_EQUIP1 / 6 | `vgui/ttt/icon_knife` | `w_knife_ct.mdl` |
| Schutzbarriere | `weapon_tttbase` | `lmnt_schutzbarriere` (Basis `ttt_base_placeable`) | WEAPON_EQUIP2 / 7 | `vgui/ttt/icon_armor` | `props_combine/combine_barricade_short01a.mdl` |
| Bewegungsmelder | `weapon_tttbase` | `lmnt_bewegungsmelder` (Basis `ttt_base_placeable`), Netzwerknachricht `lmnt_bewegungsmelder` | WEAPON_EQUIP2 / 7 | `vgui/ttt/icon_beacon` | `maxofs2d/motion_sensor.mdl` |
| Pumpgun | `weapon_zm_shotgun` | – | WEAPON_HEAVY / 2, `WEAPON_TYPE_SHOTGUN` | `vgui/ttt/icon_shotgun` | `c_shotgun.mdl` / `w_shotgun.mdl` |

**Aufräumen:** Alle Entities werden bei `TTTEndRound` und `TTTPrepareRound` entfernt (das Wurfmesser bei
`TTTPrepareRound`, damit es als Spur bis zur Nachrunde liegen bleibt). Ihre Logik läuft in `ENT:Think`,
es gibt keine Timer, die übrig bleiben könnten. Die Bewegungsmelder-Marker auf dem Client werden zum Rundenende geleert.

**Hinweis Slots:** In TTT2 sind WEAPON_EQUIP1 und WEAPON_EQUIP2 beide `WEAPON_SPECIAL`. Wie viele
Ausrüstungen jemand gleichzeitig tragen kann, legt `ttt2_max_special_slots` fest.

## Nur ingame prüfbar

- Ausrichtung der Modelle beim Platzieren: Mine aufrecht, Sensor an Wand und Boden, Barrikade mit der Vorderseite zum Gegner und nicht im Boden versunken
- Ob Kugeln die Barrikade treffen (Kollisionsgruppe der Basis) und ob Spieler wirklich hindurchgehen können
- Sprengwirkung der Mine (Abfall über den Radius, Schadenslog, Karma beim Teamschaden)
- Größe der Giftwolke im Vergleich zum Schadensradius, Hustgeräusche
- Flugbahn und Treffererkennung der Wurfmesser, Kopftreffer
- Pumpgun: Nachladeanimationen des HL2-Viewmodels (`ACT_SHOTGUN_RELOAD_START/FINISH`), Rückstoß, Klang
- Meldung und Marker des Bewegungsmelders bei mehreren Detektiven, Einsammeln mit E
- Shop-Icons auf dem Client (`!weapon <klasse>` im Client-Kontext)
