# API: Pointshop 2.0 (Modul `ttt.pointshop`)

Dateien: `lmnt_ttt/lua/lmnt_ttt/sh_pointshop.lua` (Katalog + reine Logik, shared) · `sv_pointshop.lua` (Kauf, Verkauf, Ausrüsten, Anwenden) · `cl_pointshop.lua` (Menü, Hüte, Chat-Titel, Konfetti) · Tests: `lmnt_ttt/lua/lmnt/tests/sv_pointshop.lua` · hängt ab von `ttt.stats`

Öffnen: **F4**, `!shop` (`!pointshop`, `!ps`) oder Konsole `lmnt_shop`. Rechtsklick auf ein gekauftes Item = verkaufen.

## Grundsätze

- **Serverautorität:** Preise, Tagesangebot, Rabatt, Erstattung, Besitz und VIP-Recht entscheidet nur der Server. Der Client bekommt fertige Zahlen und zeigt sie an.
- **Keine Punkte ohne Gegenleistung:** Punkte und Inventar werden in **einer** `LMNT.DB.Transaction` geschrieben. Jeder SQL-Fehler (`LMNT.DB.QueryStrict`) oder ein nicht getroffener Datensatz (`changes() ~= 1`) bricht ab → Rollback, Meldung an den Spieler, `error`-Log (Kategorie `shop`). Erst nach dem Commit wird der Speicher (`ply.LMNTStats.points`, `ply.LMNTInventory`) angepasst.
- **Keine doppelten Käufe:** Besitzprüfung im Speicher, Primärschlüssel `(steamid, item)` in der Datenbank (ein Konflikt rollt auch den Punkteabzug zurück), In-Flight-Sperre pro SteamID64, Drossel 0,25 s pro Spieler, Paketgröße begrenzt.
- **Kein Gewinn durch Rabatt:** Erstattung = `floor(min(bezahlt, Basispreis) × ShopSellFactor)`. Der bezahlte Preis steht in der neuen Spalte `paid`.
- **Keine Rolleninfo:** Alle Kosmetik hängt nur am Item, nie an Rolle oder Team. Modell und Spur wechseln während einer laufenden Runde erst beim nächsten Spawn.

## Seltenheiten

| ID | Name | Farbe | Preisband |
|---|---|---|---|
| `common` | Gewöhnlich | `muted` #a5a1ac | 150–450 |
| `rare` | Selten | `info` #7fb4ff | 500–850 |
| `epic` | Episch | #ba80ff (ergänzt, Kontrast auf `ink` > 7:1) | 900–1450 |
| `legendary` | Legendär | `warn` #ffb020 | 1500–3000 |

`PS.ValidateCatalog()` prüft, dass jedes Item eine bekannte Seltenheit hat und sein Preis im Band liegt (Unit-Test).

## Kategorien und Katalog

| Kategorie | Wirkung | Sichtbar ab |
|---|---|---|
| `model` Spielermodelle | `SetModel` beim Spawn | nächster Spawn (in der Runde) bzw. sofort außerhalb |
| `hat` Hüte | Clientside-Modell am Attachment `eyes`, NWString `lmnt_hat` | sofort |
| `trail` Spuren | `util.SpriteTrail` | wie Modelle |
| `title` **Chat-Titel** (neu) | `[Titel]` vor dem Namen im Chat, Farbe = Seltenheit. NWString `lmnt_title` = **Item-ID**, der Text kommt clientseitig aus dem Katalog (keine Freitexte, max. 16 Zeichen) | sofort |
| `deathfx` **Todeseffekte** (neu) | beim eigenen Tod an `WorldSpaceCenter()` | beim Tod |

Neue Einträge:

| ID | Name | Seltenheit | Preis | Details |
|---|---|---|---|---|
| `title_rookie` | Frischling | gewöhnlich | 200 | |
| `title_regular` | Stammgast | gewöhnlich | 300 | |
| `title_lucky` | Glückspilz | selten | 600 | |
| `title_shadow` | Schattenläufer | selten | 750 | |
| `title_tactic` | Taktiker | episch | 1000 | |
| `title_legend` | Legende | legendär | 2000 | VIP |
| `fx_sparks` | Funkenregen | gewöhnlich | 300 | `util.Effect("Sparks")` |
| `fx_glass` | Scherben | gewöhnlich | 350 | `util.Effect("GlassImpact")` |
| `fx_dust` | Staubwolke | selten | 600 | `util.Effect("ThumperDust")` |
| `fx_energy` | Energieball | selten | 800 | `util.Effect("cball_explode")` |
| `fx_confetti` | Konfetti | episch | 1200 | Client-Partikel, bunt |
| `fx_gold` | Goldregen | legendär | 2000 | Client-Partikel, gold, VIP |

Preisänderungen am Bestand (wegen der Preisbänder): Alyx/Mossman 500 → 550, Breen 900 → 850, Combine-Soldat 800 → 950, G-Man 1500 → 1800, Herzen 800 → 950, LOL 900 → 1500. Bereits gekaufte Items ohne gespeicherten Preis (`paid = NULL`) werden zum halben **aktuellen** Basispreis erstattet.

Titel nennen bewusst keine Rollen oder Teams. Titel und Hut sind sofort sichtbar, verraten aber nichts über die Rolle.

### Todeseffekte

- Hook `PostPlayerDeath`, Abklingzeit 3 s pro Spieler. Kein Unterschied zwischen Rollen, Teams oder Todesursache.
- `kind = "engine"`: `util.Effect(name, EffectData)` auf dem Server mit `Origin`, `Normal` (oben), `Magnitude`, `Scale`, `Radius` aus dem Katalog. Die Engine entfernt diese Effekte selbst nach kurzer Zeit.
- `kind = "confetti"`: Nachricht `lmnt_ps_deathfx` (Item-ID + Position) per `net.SendPVS`. Der Client prüft die ID gegen den Katalog, ignoriert alles über 3000 Einheiten Entfernung, erzeugt 70 Partikel (`particles/balloon_bit`, Ersatz `effects/spark`, `sprites/light_glow02_add`) mit `DieTime` ≤ 2,5 s und gibt den Emitter sofort frei (`emitter:Finish()`). Nach spätestens 2,5 s ist nichts mehr sichtbar.
- VIP-Items wirken (wie alle VIP-Kosmetik) nur, solange der Spieler das Recht `vip` hat.

## Tagesangebot

- `PS.PickDaily(tag)` wählt deterministisch aus allen kaufbaren **Nicht-VIP**-Items (nach ID sortiert): `util.CRC("lmnt_ps_daily:" .. tag) % n`. Gleicher Tag + gleicher Katalog = gleiches Item, auch nach einem Neustart.
- Tag = `os.date("%Y-%m-%d")` in **Serverzeit**, Wechsel um Mitternacht. Ein Timer (30 s) erkennt Tageswechsel und Rabattänderungen und schickt allen den neuen Stand.
- Einstellung:

| Key | Typ | Standard | wirkt |
|---|---|---|---|
| `ttt.pointshop.daily_discount` | int 0–90 | 25 | live (0 = kein Tagesangebot) |

- Preis = `max(1, floor(Basispreis × (100 − Rabatt) / 100))`. Der Rabatt wird zusätzlich auf 0–90 begrenzt (`PS.ClampDiscount`), falls `config.json` Unsinn liefert.
- Der Client schickt beim Kauf den Preis mit, den er angezeigt hat. Weicht er vom Serverpreis ab (z. B. Tageswechsel zwischen Anzeige und Klick), lehnt der Server ab („Der Preis hat sich geändert …“) statt still einen anderen Betrag abzubuchen. Abgebucht wird immer der Serverpreis.

## Funktionen (`LMNT.TTT.Pointshop`, kurz `PS`)

### Rein (shared, ohne Spieler/Netzwerk/Datenbank)
| Funktion | Rückgabe |
|---|---|
| `GetRarity(item)` | Seltenheits-Eintrag (`id`, `name`, `rank`, `color`, `min`, `max`), Standard `common` |
| `BasePrice(item)` | ganze Zahl ≥ 1 oder `nil` (nicht kaufbar) |
| `ClampDiscount(d)` | 0–90, ganzzahlig, Unsinn = 0 |
| `ComputePrice(item, istTagesangebot, rabatt)` | Preis ≥ 1 oder `nil` |
| `ComputeRefund(item, bezahlt, faktor)` | Erstattung ≥ 0 |
| `DailyCandidates(katalog)` / `PickDaily(tag, katalog)` / `DayKey(zeit)` | siehe Tagesangebot |
| `CheckBuy(ctx)` | `true` \| `false, code, meldung`. `ctx = { item, owned, isVip, points, price, expected }`, Codes in Prüfreihenfolge: `unknown`, `owned`, `vip`, `price`, `changed`, `points` |
| `CheckSell(ctx)` | `true` \| `false, code, meldung` (`unknown`, `notowned`) |
| `ValidateCatalog(katalog)` | Liste von Problemen (leer = in Ordnung) |

### Server
| Funktion | Rückgabe |
|---|---|
| `CurrentDaily()` | `id\|nil, rabatt, tag` |
| `PriceFor(id)` | Serverpreis oder `nil` – **einzige** Stelle, an der ein Kaufpreis entsteht |
| `ExecuteBuy(sid, id, preis, punkteVorher, opts)` | `true, neuePunkte` \| `false, fehler` |
| `ExecuteSell(sid, id, erstattung, punkteVorher, opts)` | `true, neuePunkte` \| `false, fehler` |
| `ExecuteEquip(sid, id, an, vorher)` | `true` \| `false, fehler` |
| `LoadInventoryRows(sid)` | Zeilen `item, equipped, paid` |
| `WithLock(schlüssel, fn)` | `true, ergebnis` \| `false, "busy"` \| `false, "error", meldung` (Fehler in `fn` → `error`-Log, Sperre wird immer freigegeben) |
| `IsBusy(schlüssel)` | bool |
| `LMNT.TTT.LoadInventory(ply)`, `LMNT.TTT.OpenShop(ply)` | wie bisher |

`Execute*` arbeiten nur mit der SteamID64, schreiben `lmnt_ttt_stats.points` (Wert = Speicherstand ± Betrag, damit noch nicht gespeicherte Punkte erhalten bleiben) und `lmnt_ps_inventory`, und verweigern den Aufruf innerhalb einer fremden Transaktion (dort wäre kein Rollback möglich). `opts.failAfter = "points" | "inventory"` erzeugt nach dem Schritt einen künstlichen Fehler (nur für Tests).

Ablauf eines Kaufs (`lmnt_ps_action`, Aktion `buy`): Paketgröße → Drossel → Item/Aktion bekannt → Sperre → Statistik geladen → `PriceFor` → `CheckBuy` → `ExecuteBuy` (Transaktion) → Speicher anpassen → Meldung + `info`-Log → automatisch ausrüsten → Sync.

## Netzwerk

| Nachricht | Richtung | Inhalt |
|---|---|---|
| `lmnt_ps_open` | s2c | leer |
| `lmnt_ps_sync` | s2c | `UInt(10)` Anzahl, je Item `String id, Bool ausgerüstet, UInt(32) Erstattung`; danach `String tagesangebotId` (leer = keins), `UInt(32) Preis`, `UInt(7) Rabatt`, `String Tag` |
| `lmnt_ps_action` | c2s | `String aktion` (`buy`, `sell`, `equip`, `unequip`), `String id` (≤ 48), `UInt(32)` angezeigter Preis (nur `buy`, sonst 0). Höchstens 512 Bit, sonst verworfen |
| `lmnt_ps_deathfx` | s2c (PVS) | `String id`, `Vector pos` |

Noch nicht auf `LMNT.Net` umgestellt (siehe net.md › Migrationskandidaten). Die Größen- und Wertprüfung von `lmnt_ps_action` ist bis dahin im Handler.

## Menü

Werkzeugleiste mit Suche (Name, Titeltext, Seltenheit), Filter Seltenheit, Filter Besitz (alle / im Besitz / nicht im Besitz) und Sortierung (Preis auf-/absteigend, Name, Seltenheit). Die Karten zeigen Seltenheit (Leiste + Name in Seltenheitsfarbe), VIP- und Angebots-Badge, durchgestrichenen alten Preis im Angebot. Kopfbereich mit Punktestand und Tagesangebot.

Leistung: Karten werden beim Öffnen einmal gebaut. Suche und Filter schalten nur die Sichtbarkeit um (`DIconLayout` überspringt unsichtbare Kinder). Nur eine andere Sortierung baut die Karten einmal neu auf. Ein Sync aktualisiert nur Beschriftungen und Sichtbarkeit.

## Chat-Titel und `LMNT.ChatPrefix`

`cl_admin.lua` ruft `hook.Run("LMNT.ChatPrefix", ply)` auf, es zählt also nur das **erste** Ergebnis ungleich `nil`. Der Level-Tag aus `cl_stats.lua` liefert immer eines. Damit Level-Tag und Titel nicht von der zufälligen Hook-Reihenfolge abhängen, ersetzt `cl_pointshop.lua` nach dem Laden (Timer, `InitPostEntity`, danach alle 5 s) die übrigen `LMNT.ChatPrefix`-Hooks durch stumme Platzhalter und ruft die Originale selbst in fester Namensreihenfolge auf, gefolgt vom Titel. Entfernte Hooks (z. B. `ttt.stats` aus) werden nicht mehr aufgerufen, beim Deaktivieren des Pointshops werden die Originale zurückgegeben. **Empfehlung:** `cl_admin.lua` sammelt die Ergebnisse aller Hooks selbst. Dann entfällt dieser Block.

## Tests

`lmnt test` bzw. `!test`. Gruppen in `sv_pointshop.lua`:

| Gruppe | Fälle | Inhalt |
|---|---|---|
| `Pointshop.Preise` | 7 | Basispreis-Validierung, Tagesangebot-Rabatt (Rundung, ≥ 1, Begrenzung), Erstattung, kein Gewinn durch Angebot + Verkauf über alle Items und Rabatte |
| `Pointshop.Tagesangebot` | 6 | Determinismus, Unabhängigkeit von der Katalogreihenfolge, keine VIP-Items, leerer Katalog, Tagesschlüssel, `PriceFor` folgt der Einstellung |
| `Pointshop.Katalog` | 2 | echter Katalog fehlerfrei, fehlerhafte Einträge erkannt |
| `Pointshop.Kaufprüfung` | 9 | gültig, Doppelkauf, zu wenig Punkte, VIP, unbekannt, Preis ≤ 0/Komma, Preisänderung, Prüfreihenfolge, Verkauf |
| `Pointshop.Transaktion` | 11 | Kauf, Doppelkauf auf DB-Ebene mit Rollback, Fehler nach jedem Schritt, ungültige Eingaben, fehlende Statistikzeile, Verkauf inkl. Rollback, Ausrüsten, fremde Transaktion |
| `Pointshop.Sperre` | 3 | Wiedereintritt, andere Spieler, Freigabe nach Fehler |

Die Datenbank-Tests nutzen die erfundene SteamID64 `76561190000000201` (`…202` ohne Statistikzeile) und räumen vor und nach jedem Fall auf.

## Nur ingame prüfbar

- Aussehen von Menü, Karten, Werkzeugleiste, Combo-Boxen und Leerzustand; Suche und Filter beim Tippen
- Chat-Titel zusammen mit dem Level-Tag (Reihenfolge `[Rang] [Lvl n] [Titel] Name`)
- Engine-Todeseffekte (`Sparks`, `GlassImpact`, `ThumperDust`, `cball_explode`): Sichtbarkeit, Größe, Dauer, ggf. Geräusch
- Konfetti: Material, Farben, Dauer ≤ 2,5 s, Sichtbarkeit nur in der Nähe
- Tageswechsel um Mitternacht (Resync), Rabattänderung mit `!config ttt.pointshop.daily_discount 50`
