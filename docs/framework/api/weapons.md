# API: LMNT.Weapons & LMNT.Shop (seit 1.2.0, Modul `ttt.shop`)

Dateien: `lmnt_ttt/lua/lmnt_ttt/sh_weapons.lua` (Registry, shared), `sv_shoprules.lua` (Kaufregeln, Server), Erweiterungsordner `lmnt_ttt/lua/lmnt_ttt/weapons/` (Metadaten-Dateien werden automatisch geladen).

## Aufgabenteilung mit TTT2

| Zuständig | Was |
|---|---|
| **TTT2** (`gamemode/shared/sh_shop.lua`) | Kaufabwicklung: Credits prüfen und abbuchen, Ausgabe, `limited`, `teamLimited`, `globalLimited`, `minPlayers`, Rollen (`CanBuy`), Zufallsshop, Shop-Editor (F1) für Preise und Verfügbarkeit |
| **SWEP/ITEM** | Schaden, Munition, Schussverhalten, Wirkung |
| **LMNT.Weapons** | Metadaten (Kategorie, Beschreibung, Quelle, Balance-Etikett, Hinweise), Erkennung und Kompatibilitätsprüfung, Übersicht `!weapons` / `!weapon` |
| **LMNT.Shop** | zusätzliche Regeln über den offiziellen Hook `TTT2CanOrderEquipment`: Sperre per Einstellung, Sperrliste (pro Map über Map-Profile), Sperrzeit ab Rundenbeginn, Limit pro Spieler und Runde, eigene Regeln. Verständliche Begründung an den Spieler |

LMNT verändert **keine** fremden SWEP-Tabellen. Preise ändert man im TTT2-Shop-Editor.

## LMNT.Weapons

| Funktion | Rückgabe | Hinweise |
|---|---|---|
| `Register(class, meta)` | Eintrag oder `nil, fehler` | Felder: `displayName, description, category, kind ("weapon"/"item"), sourceAddon, balanceProfile, shop = { maxPerRound, lockSeconds }, notes`. Eine zweite Registrierung derselben Klasse aus einer **anderen** Quelle wird abgelehnt und protokolliert. Legt `shop.<class>.enabled/max_per_round/lock_seconds` an |
| `Check(class)` | Status, Prüfliste | `ttt2` · `unvollständig` (z. B. Modell fehlt) · `nicht TTT-tauglich` (keine `weapon_tttbase`-Basis bzw. kein `Kind`) · `nicht geladen`. Icons sind nur auf dem Client prüfbar |
| `Discover()` | Anzahl | alle kaufbaren oder auf dem Boden spawnbaren Waffen und alle kaufbaren TTT2-Items. Läuft automatisch bei `InitPostEntity` |
| `Get(class)` | Sicht | Metadaten, Status, Prüfungen, Live-Werte aus TTT2 (Credits, Limits, Rollen, Boden-Spawn; nur lesend), LMNT-Regeln |
| `List(filter)` | Liste | |

Kategorien: Pistole, Gewehr, Präzision, Schrot, Nahkampf, Granate, Gerät, Passiv, Sonstiges.

## LMNT.Shop

| Funktion | Hinweise |
|---|---|
| `Evaluate(ctx)` → `erlaubt, grund` | reine Funktion (testbar). Reihenfolge: Sperrliste → (registrierte Klassen) aktiviert → Sperrzeit → Limit pro Runde → eigene Regeln. Eine fehlerhafte eigene Regel **sperrt** zur Sicherheit |
| `AddRule(id, fn(ctx), priorität)` | `fn` gibt `false, grund` zurück, um zu sperren. Gleiche ID ersetzt die alte Regel. Wird beim Deaktivieren des Moduls entfernt |
| `BuildContext(ply, class, isItem)` | Kontext aus Einstellungen und Rundenstatus |

Gezählt werden nur **tatsächlich ausgeführte** Käufe (`lmnt.shop.purchase`), zurückgesetzt bei `lmnt.round.prepare`. Bei erlaubtem Kauf gibt der Hook nichts zurück, damit die `TTT2CanOrderEquipment`-Hooks anderer Addons weiterlaufen.

## Einstellungen

| Key | Bedeutung |
|---|---|
| `ttt.shop.blocked` | Komma-Liste gesperrter Klassen. Im Map-Profil als Override sinnvoll, zum Beispiel C4 auf kleinen Maps |
| `shop.<class>.enabled` | LMNT-Sperre einzelner Ausrüstung |
| `shop.<class>.max_per_round` | Limit pro Spieler und Runde (0 = unbegrenzt) |
| `shop.<class>.lock_seconds` | Sperrzeit ab Rundenbeginn |

## Befehle (Recht `config`)
`!weapons [filter]` · `!weapon <klasse>` · `!shopstats`

## Neue Ausrüstung hinzufügen
1. SWEP nach `lua/weapons/` bzw. ITEM nach `lua/terrortown/entities/items/<id>/shared.lua`. TTT2 lädt sie selbst.
2. Metadaten-Datei nach `lua/lmnt_ttt/weapons/sh_<name>.lua` mit `LMNT.Weapons.Register(...)`.
3. Wirkung von Items nach `lua/lmnt_ttt/items/` (Modul `ttt.items`).
4. Test nach `lua/lmnt/tests/sv_<name>.lua`: `LMNT.Weapons.Check(class) == "ttt2"`.
