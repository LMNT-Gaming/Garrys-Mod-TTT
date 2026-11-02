# API: LMNT.Net – Netzwerk-Dienst (T-030, T-092)

Datei: `lmnt_core/lua/lmnt/services/sh_netapi.lua` · Realm: **shared** (Server prüft, Client vertraut nur dem Server) · Tests: `lmnt_core/lua/lmnt/tests/sv_netapi.lua`

## Grundsatz

Clientdaten sind nie vertrauenswürdig. Jede Nachricht hat ein **Schema** mit festen Grenzen. Der Server prüft jedes eingehende Paket, bevor der Handler läuft, und verwirft es bei jedem Fehler **ohne Antwort an den Client**. Geld, XP, Rollen und Rechte entscheidet der Handler auf dem Server, nie das Paket.

Prüfkette (Server, eingehend), jeder Schritt bricht beim ersten Fehler ab:

| # | Prüfung | Verstoß-Code | Punkte |
|---|---|---|---|
| 1 | Richtung: Client schickt eine `s2c`-Nachricht | `direction` | 10 |
| 2 | Größe: `len` (Bit) außerhalb `minBits`–`maxBits`, **vor dem Lesen** | `size` | 5 |
| 3 | Rate-Limit pro Spieler **und** Nachricht (Token-Bucket) | `rate` | 1 |
| 4 | Recht über `LMNT.HasPerm(ply, perm)`, **Deny-by-default** | `perm` | 2 |
| 5 | Schema: Typen, Längen, Bereiche, gültige Entities/Spieler, exakte Paketlänge | `schema` | 5 |

Gewichte stehen in `LMNT.Net.Weights`. Ein kurzer Flood kann bei Lag auch von einem normalen Client kommen und zählt deshalb wenig. Falsche Richtung oder kaputte Pakete schickt ein unveränderter Client nie.

Bei einem Verstoß:
- Paket verworfen, Zähler `dropped`, `violations` und `reasons[code]` der Nachricht erhöht
- `LMNT.Log.Security("net", …)` mit Spieler (Name + SteamID64), Nachricht, Grund, Punktestand. **Ohne Paketinhalt.** Gründe nennen nur Feldnamen und Grenzen, nie Werte. Gedrosselt auf **einen Eintrag pro Spieler, Nachricht und Grund je 10 s**, unterdrückte Verstöße werden im nächsten Eintrag bzw. beim Aufräumen (alle 60 s) nachgezählt. Ein Flood kann so weder Datenbank noch Logdatei, Team-Chat oder Discord-Weiterleitung überlasten
- Event `lmnt.net.violation` (ply, name, grund) bei **jedem** Verstoß
- Verstoßpunkte pro Spieler (SteamID64) mit linearem Zeitverfall. Ab `lmnt.net.kick_threshold` Kick über `game.KickID` mit der neutralen Meldung „Die Verbindung wurde vom Server getrennt (Netzwerkfehler).“ (keine internen Details), plus `security`-Log. Weitere Pakete bis zum Verbindungsende werden ohne neue Punkte verworfen. Punkte bleiben über einen Reconnect erhalten und verfallen normal. Der Host eines Listen-Servers wird nie gekickt

## Funktionen

| Funktion | Realm | Rückgabe | Fehler |
|---|---|---|---|
| `Register(name, def)` | shared | – | `error` (Ebene des Aufrufers) bei ungültiger Definition oder anderem Schema/anderer Richtung unter demselben Namen |
| `Receive(name, fn)` | shared | – | `error`, wenn nicht registriert oder die Richtung im Realm nicht empfangen wird |
| `Send(name, data, ziel)` | server | `true` / `false` (kein gültiger Empfänger mehr) | `error` bei ungültigen Daten, falscher Richtung, unbekannter Nachricht, ungültigem Zieltyp |
| `SendToServer(name, data)` | client | `true` / `false` (clientseitig zurückgehalten: Rate-Limit oder fehlendes Recht) | wie `Send`, zusätzlich wenn der Server den Namen nicht kennt |
| `Stats()` | shared | `{ [name] = { direction, received, bytesIn, dropped, violations, reasons, errors, sent, bytesOut, throttled } }` | – |
| `Get(name)` | shared | Kopie der Definition (`direction`, `perm`, `rateLimit`, `minBits`, `maxBits`, `hasHandler`, …) oder `nil` | – |
| `List()` | shared | sortierte Namen | – |
| `GetViolationScore(ply)` | server | aktuelle Punkte (mit Verfall) | – |

`Register` muss **geteilt** laufen (sh_-Datei oder geteilter Teil eines Moduls). Nur dann kennen beide Seiten das Schema, und nur der Server legt den Netzwerkstring an (`util.AddNetworkString`, Wiki: mehrfacher Aufruf ist unschädlich). Den Handler setzt man entweder in `def.handler` oder realm-spezifisch mit `Receive` (z. B. Server-Logik in einer sv_-Datei, Anzeige in einer cl_-Datei).

Erneute Registrierung mit **gleichem Schema und gleicher Richtung** (Lua-Reload) ist erlaubt: Recht, Rate-Limit, `maxBits`, `desc` werden übernommen, ein neuer `handler` ersetzt den alten, Statistik bleibt. Jede Änderung am Schema (auch nur eine Grenze) oder an der Richtung ist ein Fehler, denn das Protokoll muss auf Server und Client gleich sein. Dafür ist ein Neustart nötig.

Wird ein Handler beim Laden eines Moduls gesetzt, nimmt `LMNT.Modules` ihn beim Deaktivieren zurück. Pakete werden dann als „kein Handler“ verworfen (Warnung einmal je Nachricht, **kein** Verstoß).

### Definition

| Feld | Pflicht | Bedeutung |
|---|---|---|
| `direction` | ja | `c2s` (Client → Server), `s2c` (Server → Client) oder `both` |
| `schema` | – | Liste von Feldern (siehe unten). Leer = Nachricht ohne Inhalt |
| `perm` | bei `c2s`/`both` | Rechtename für `LMNT.HasPerm`. `false` = ausdrücklich jeder verbundene Spieler. Fehlt `perm`, ist das ein Registrierungsfehler (Deny-by-default). Bei `s2c` nicht erlaubt |
| `rateLimit` | – | `{ count = 1–1000, perSeconds = >0–3600 }`, Standard `{ count = 10, perSeconds = 1 }`. Spitzen bis `count` sind sofort erlaubt. Nur `c2s`/`both` |
| `maxBits` | – | Gesamtgrenze in Bit. Standard und Obergrenze: größtes gültiges Paket laut Schema, höchstens 65.530 Byte |
| `handler(ply, data)` | – | Server: `ply` = Absender (von der Engine, nicht aus dem Paket). Client: `ply = nil`. Fehler im Handler werden mit Traceback als `error` (Kategorie `net`) protokolliert und in `errors` gezählt |
| `unreliable` | – | `net.Start(name, true)`: Zustellung nicht garantiert |
| `desc` | – | Beschreibung für Diagnose |

Unbekannte Schlüssel (z. B. `ratelimit`) sind ein Fehler, damit Tippfehler nicht still die Standardwerte aktivieren.

### Feldtypen

| Typ | Pflicht-Angaben | Optionale Angaben | Bits auf der Leitung |
|---|---|---|---|
| `string` | `max` (Byte, 1–65.529) | `min`, `utf8` (Standard `true`: vom Client nur gültiges UTF-8), `pattern` (Lua-Muster) | 8 × (Länge + 1) |
| `uint` | `bits` (1–32) **oder** `max` | `min` (≥ 0), `max` (≤ 2^bits − 1) | `bits` |
| `int` | `bits` (2–32) **oder** `min` und `max` | `min`, `max` | `bits` |
| `bool` | – | – | 1 |
| `float` | `min`, `max` (endlich) | – | 32 |
| `entity` | – | `allowNull`, `class` (Name oder Liste) | `MAX_EDICT_BITS` |
| `player` | – | `allowNull` | `MAX_PLAYER_BITS` |
| `list` | `max` (1–65.535), `of` (Feldtyp ohne Namen) | `min` | Zähler (`bits` aus `max`) + Einträge |
| `record` | `fields` (Liste von Feldern) | – | Summe der Felder |

Für alle Felder: `name` (Pflicht, `^[%a_][%w_]*$`, eindeutig), `optional = true` (1 Bit „vorhanden“, Wert `nil` erlaubt; nicht für Listeneinträge), `desc`.

Hinweise:
- Einen freien `table`-Typ gibt es bewusst nicht. Tabellen gehen nur als `list` (feste Höchstlänge, lückenlos) oder `record` (feste Felder). Verschachtelung: höchstens zwei Ebenen `list`/`record` unterhalb des Schemas (z. B. Liste von Records)
- `float` ist auf der Leitung float32. Werte, die nur durch die Rundung minimal (≤ 10⁻⁶ relativ) außerhalb der Grenze landen, werden auf die Grenze gezogen. NaN und ±∞ werden immer abgelehnt
- `entity`/`player`: auf dem Server muss die Entity gültig sein (`IsValid`, Welt und `NULL` sind ungültig), `player` zusätzlich `IsPlayer()`. Mit `allowNull` kommt `NULL` an (beim Senden darf das Feld dann fehlen). Auf dem **Client** werden ungültige Entities als `NULL` durchgereicht, weil Entities außerhalb des PVS dort nicht existieren
- Strings mit Nullbyte sind beim Senden ein Fehler (`net.WriteString` bricht dort ab). Binärdaten gehören nicht in `string`
- Eingehende Pakete müssen genau so lang sein wie die gelesenen Daten (Rest unter 8 Bit gilt als Auffüllung). Zu kurze Pakete werden **vor** dem jeweiligen Lesen erkannt, überzählige Daten danach

### Senden

Daten sind eine Tabelle mit den Feldnamen. `Send`/`SendToServer` prüfen **vor** `net.Start` vollständig (Schema, `maxBits`, Ziel). Ungültige Werte, unbekannte Felder oder fehlende Pflichtfelder sind ein `error` für den Entwickler mit Feldpfad, z. B. `LMNT.Net: 'lmnt_shop_buy': Feld 'anzahl': außerhalb 1–200`.

Ziele für `Send`: Spieler, Liste von Spielern (ungültige werden herausgefiltert), `RecipientFilter` oder `nil` = alle (`net.Broadcast`). Ist niemand (mehr) da, kommt `false` zurück, ohne zu senden.

`SendToServer` hält sich vorab an das Rate-Limit (10 % strenger als der Server) und an `perm` (über die replizierte Rangzuordnung). Das ist reine Bequemlichkeit, damit normale Spieler durch schnelles Klicken keine Verstoßpunkte sammeln. Entscheidend bleibt der Server.

## Beispiel

```lua
-- lmnt_ttt/lua/lmnt_ttt/sh_shop.lua (geteilt)
LMNT.Net.Register("lmnt_shop_buy", {
	direction = "c2s",
	perm = false,                               -- jeder Spieler darf kaufen, der Handler prüft Geld und Item
	rateLimit = { count = 4, perSeconds = 1 },
	schema = {
		{ name = "id", type = "string", max = 48, pattern = "^[%w_]+$" },
		{ name = "anzahl", type = "uint", min = 1, max = 10 },
	},
})

LMNT.Net.Register("lmnt_shop_inventory", {
	direction = "s2c",
	schema = {
		{ name = "punkte", type = "uint", bits = 32 },
		{ name = "items", type = "list", max = 200, of = { type = "record", fields = {
			{ name = "id", type = "string", max = 48 },
			{ name = "an", type = "bool" },
		} } },
	},
})

-- sv_shop.lua
LMNT.Net.Receive("lmnt_shop_buy", function(ply, data)
	-- data.id und data.anzahl sind geprüft. Preis, Guthaben und Verfügbarkeit entscheidet der Server
	LMNT.Shop.Buy(ply, data.id, data.anzahl)
	LMNT.Net.Send("lmnt_shop_inventory", { punkte = ply.LMNTPoints, items = LMNT.Shop.ItemsOf(ply) }, ply)
end)

-- cl_shop.lua
LMNT.Net.SendToServer("lmnt_shop_buy", { id = "hat_crown", anzahl = 1 })
LMNT.Net.Receive("lmnt_shop_inventory", function(_, data) shopPanel:SetItems(data.items) end)
```

## Einstellungen und Event

| Key | Typ | Standard | wirkt |
|---|---|---|---|
| `lmnt.net.kick_threshold` | int 0–100000 | 60 (0 = nie kicken) | live |
| `lmnt.net.decay_per_minute` | number 0–600 | 6 (1 Punkt je 10 s) | live |

Beide nur auf dem Server, Kategorie „Netzwerk“, Recht zum Ändern `config`. Mit den Standardwerten wird ein Flood nach ungefähr 60 Paketen über dem Limit getrennt, eine Folge kaputter Pakete nach 12, ein Client, der `s2c`-Nachrichten schickt, nach 6. Ein einzelner Ausrutscher verfällt in Sekunden.

| Event | Argumente | Realm |
|---|---|---|
| `lmnt.net.violation` | ply, name, grund (`direction` · `size` · `rate` · `perm` · `schema`) | server |

## Diagnose

- `!netstats` (Recht `dev`): je Nachricht Richtung, empfangene/gesendete Pakete und Bytes, verworfene Pakete, Verstöße nach Grund, Handler-Fehler. Sortiert nach Verstößen, dann Datenmenge, höchstens 25 Zeilen. Danach die Verstoßpunkte der Online-Spieler und die aktuelle Schwelle
- `LMNT.Net.Stats()`: dieselben Zahlen als Tabelle. `bytesOut` zählt Nutzdaten × Empfänger. `throttled` (nur Client) = vom eigenen Limit zurückgehaltene Sendungen
- **Selbsttest** für die Abnahme von T-092 mit echten Paketen: Client-Konsole `lmnt_net_selftest ok|flood|oversize|badvalue|short` (nur mit Recht `dev`). Nutzt die Nachricht `lmnt_net_selftest` (c2s, Recht `dev`, 5 pro Sekunde, ein `uint` bis 100). Die fehlerhaften Varianten schreiben absichtlich an `LMNT.Net` vorbei, so wie ein veränderter Client:

| Variante | erwartet |
|---|---|
| `ok` | Chat „gültiges Paket angekommen (n = 42)“ |
| `flood` | 20 Pakete: 5 angenommen, 15 × `rate`, **ein** `security`-Log (Rest gedrosselt) |
| `oversize` | 8008 Bit statt 8 → `size` |
| `badvalue` | 250 bei max 100 → `schema` („Feld 'n': außerhalb 0–100“) |
| `short` | 0 Bit → `size` |

Kick prüfen: `!config lmnt.net.kick_threshold 10`, dann `lmnt_net_selftest flood` → Trennung mit neutraler Meldung, danach zurücksetzen mit `!config lmnt.net.kick_threshold reset`.

## Testbare Bausteine (ohne Netzwerk)

| Funktion | Zweck |
|---|---|
| `CompileSchema(schema)` → spec | Schema prüfen und kompilieren (`error` bei ungültigem Schema). `spec.minBits`, `spec.maxBits` |
| `Validate(spec, data)` → `true, bits` / `false, grund, pfad` | Sendeseite |
| `Encode(spec, data, writer)` → bits | prüfen und schreiben |
| `Decode(spec, reader, len, mode)` → `data` / `nil, grund, pfad` | Empfangsseite, `mode` `"server"` (streng) oder `"client"` |
| `NewBuffer()` | Ersatz für `net` in Tests: gleiche `Write*`/`Read*`-Methoden, zählt Bits wie `net`, speichert Werte **ohne** Bitmaske (damit lassen sich manipulierte Pakete nachbilden), `:Bits()`, `:Rewind()` |
| `NewLimiter(count, perSeconds)` | `:Allow(key, jetzt)`, `:Reset(key)`, `:Prune(jetzt)` |
| `NewViolationCounter(verfallProMinute)` | `:Add(key, punkte, jetzt)`, `:Get(key, jetzt)`, `:Reset(key)`, `:Prune(jetzt)`. Verfall als Zahl oder Funktion (live gelesen) |
| `NewRegistry()` | `:Register(name, def)` → msg, neu (wirft), `:TryRegister` (gibt `nil, fehler` zurück), `:Get(name)`. Ohne Netzwerkstring |
| `NewGuard(env)` | Prüfkette `:Incoming(msg, ply, len, reader)` mit eigener Umgebung `env` = { now, key, name, hasPerm, threshold, decay, log, emit, kick } |

Der laufende Dienst nutzt intern genau diese Bausteine (eine Registry, ein Guard mit Server-Umgebung). Zustand und Statistik überstehen einen Lua-Reload, die Empfänger werden neu gebunden.

## Geprüfte GMod-Grundlagen (Wiki, 17./18.10.2026)

| Quelle | Verwendung |
|---|---|
| [net.Receive](https://wiki.facepunch.com/gmod/net.Receive) | Callback `(len, ply)`, `len` in **Bit**, `ply` nur serverseitig. [net.lua](https://github.com/Facepunch/garrysmod/blob/master/garrysmod/lua/includes/extensions/net.lua): `net.Incoming` zieht den 16-Bit-Kopf ab, Namen sind nicht case-sensitiv |
| [net.Start](https://wiki.facepunch.com/gmod/net.Start) | Grenze 65.533 Byte je Nachricht, Name muss mit `util.AddNetworkString` angelegt sein, optional `unreliable` |
| [net.BytesWritten](https://wiki.facepunch.com/gmod/net.BytesWritten) | zählt 3 Byte Verwaltung mit → Nutzgrenze hier 65.530 Byte |
| [net.WriteString](https://wiki.facepunch.com/gmod/net.WriteString) / [ReadString](https://wiki.facepunch.com/gmod/net.ReadString) | 8 Bit je Byte + Nullterminator, bricht am Nullbyte ab, liefert `""` wenn nichts lesbar |
| [net.WriteUInt](https://wiki.facepunch.com/gmod/net.WriteUInt) / [WriteInt](https://wiki.facepunch.com/gmod/net.WriteInt) | 1–32 Bit, Wertebereiche je Bitzahl |
| [Net_Library_Usage](https://wiki.facepunch.com/gmod/Net_Library_Usage) | `WriteFloat` 32 Bit, Empfehlungen: nie Clientdaten vertrauen, Absender aus `net.Receive`, Rechte und Rate prüfen |
| [net.WriteEntity](https://wiki.facepunch.com/gmod/net.WriteEntity) / [WritePlayer](https://wiki.facepunch.com/gmod/net.WritePlayer), [Globale Variablen](https://wiki.facepunch.com/gmod/Global_Variables) | Index mit `MAX_EDICT_BITS` bzw. `MAX_PLAYER_BITS`, ungültig → 0. `ReadPlayer` liefert `Entity(i)`, deshalb zusätzlich `IsPlayer()` |
| [Entity:IsValid](https://wiki.facepunch.com/gmod/Entity:IsValid) | `NULL` und die Welt sind ungültig |
| [net.Send](https://wiki.facepunch.com/gmod/net.Send) | Spieler, Spielerliste oder `CRecipientFilter` ([RecipientFilter](https://wiki.facepunch.com/gmod/Global.RecipientFilter), `:GetCount()`) |
| [util.AddNetworkString](https://wiki.facepunch.com/gmod/util.AddNetworkString) / [NetworkStringToID](https://wiki.facepunch.com/gmod/util.NetworkStringToID) | nur Server, 4095 Plätze (geteilt mit `SetNW*`/`SetGlobal*`), mehrfacher Aufruf unschädlich. `NetworkStringToID` liefert 0 für unbekannte Namen (shared) |
| [game.KickID](https://wiki.facepunch.com/gmod/game.KickID) | wirkt auch vor dem vollständigen Beitritt (`Player:Kick` nicht), Grund kurz halten (< ~480 Zeichen) |
| [utf8.len](https://wiki.facepunch.com/gmod/utf8.len) | `false, position` bei ungültigem UTF-8 |

Nicht Teil dieses Dienstes: Deduplizierung gleicher Pakete (in `02_ZIELARCHITEKTUR.md` erwähnt) und Kompression. Beides lässt sich bei Bedarf als Option ergänzen, ohne das Schema-Format zu ändern.

## Migrationskandidaten

Bestehende `net`-Nachrichten (Suche nach `util.AddNetworkString`, Stand 18.10.2026), **noch nicht umgestellt**. Die Umstellung macht die Haupt-Session zentral. Je Nachricht: alten `util.AddNetworkString`/`net.Receive`-Code entfernen, Name bleibt gleich (Namen erfüllen schon `^[a-z0-9_.]+$`), `LMNT.Net.Register` geteilt anlegen.

| Nachricht | Richtung | Ort (Sender → Empfänger) | Heute | Hinweis für das Schema |
|---|---|---|---|---|
| `lmnt_chat` | s2c | `core/sh_net.lua` (`LMNT.Notify`) | – | variable Folge Text/Farbe/Spieler: `list` von `record { kind uint 2, text string optional, r/g/b/a uint 8 optional, ply player optional }` oder Farbe als 4 × `uint 8` |
| `lmnt_announce` | s2c | `core/sh_net.lua` → `core/cl_ui.lua` | – | `text string`, Farbe 4 × `uint 8`, `sekunden float` |
| `lmnt_settings` | s2c | `core/sh_settings.lua` | – | `list` max 4096 von `record { key string, kind uint 2, b bool?, i int 32?, n float?, s string? }`. Achtung: heute `WriteDouble`, `float` ist nur 32 Bit (ggf. Zahl als Text übertragen) |
| `lmnt_settings_req` | c2s | `core/sh_settings.lua` | eigene 5-s-Drossel, kein Recht | `perm = false`, `rateLimit { count = 1, perSeconds = 5 }`, leeres Schema |
| `lmnt_admin_open` | s2c | `admin/sh_commands.lua` → `admin/cl_admin.lua` | – | leer bzw. wie heute |
| `lmnt_admin_run` | c2s | `admin/cl_admin.lua` → `admin/sv_admin.lua` | 0,3-s-Drossel, **keine** Größenprüfung, Recht erst in `Admin.Run` | `perm = false` (Recht je Befehl in `Admin.Run`), `name string max 32`, `tokens list max 8 of string max 200` |
| `lmnt_admin_bans` | both | `admin/sv_bans.lua` ↔ `admin/cl_admin.lua` | Recht `ban`, 1-s-Drossel | c2s leer mit `perm = "ban"`. Antwort bis 500 Einträge à 4 Strings: auf die 64-KB-Grenze achten (`maxBits`, ggf. eigene s2c-Nachricht) |
| `lmnt_admin_logs` | both | `admin/sv_bans.lua` ↔ `admin/cl_admin.lua` | Recht `logs`, 1-s-Drossel, kürzt Texte | c2s `kategorie string max 32`, `suche string max 64`, `perm = "logs"`. Antwort bis 300 × (Zeit, Kategorie, Text ≤ 250) |
| `lmnt_admin_cfg_modules` | both | `services/sv_settingsmenu.lua` ↔ `admin/cl_admin.lua` | Recht `modules`, Größe, Drossel | c2s leer, `perm = "modules"` |
| `lmnt_admin_cfg_settings` | both | `services/sv_settingsmenu.lua` ↔ `admin/cl_admin.lua` | Recht `config`, Größe, Drossel | c2s leer, `perm = "config"`. Antwort nutzt eigene Kürzung auf 60.000 Byte |
| `lmnt_admin_cfg_set` | c2s | `admin/cl_admin.lua` → `services/sv_settingsmenu.lua` | Recht `config` + `def.perm`, Größe, Drossel | `key string max 128`, `reset bool`, `wert string max 4096 optional`, `perm = "config"` |
| `lmnt_admin_cfg_module` | c2s | `admin/cl_admin.lua` → `services/sv_settingsmenu.lua` | Recht `modules`, Größe, Drossel | `id string max 64`, `an bool`, `perm = "modules"` |
| `lmnt_admin_cfg_result` | s2c | `services/sv_settingsmenu.lua` → `admin/cl_admin.lua` | – | `ok bool`, `meldung string`, `key string optional`, Wert optional |
| `lmnt_ps_open` | s2c | `lmnt_ttt/sv_pointshop.lua` → `cl_pointshop.lua` | – | leer |
| `lmnt_ps_sync` | s2c | `lmnt_ttt/sv_pointshop.lua` → `cl_pointshop.lua` | – | Punkte + Inventarliste (`list` von `record`) |
| `lmnt_ps_action` | c2s | `lmnt_ttt/cl_pointshop.lua` → `sv_pointshop.lua` | 0,25-s-Drossel, **keine** Größenprüfung, prüft Aktion/Item | `action string max 16 pattern ^%l+$`, `id string max 48`, `perm = false`, `rateLimit { count = 4, perSeconds = 1 }` |
| `lmnt_special` | s2c | `lmnt_ttt/sv_specialrounds.lua` → `cl_specialrounds.lua` | – | Spezialrunden-Daten |
| `lmnt_levelup` | s2c | `lmnt_ttt/sv_stats.lua` → `cl_stats.lua` | – | Level/Anzeige |
| `lmnt_hack_pulse` | s2c | `lmnt_ttt/weapons/weapon_lmnt_hacktablet.lua` | – | Effekt-Daten (ggf. `unreliable`) |
| `lmnt_stun` | s2c | `lmnt_ttt/weapons/weapon_lmnt_taser.lua` | – | Effekt-Daten |

Die drei c2s-Nachrichten **ohne Größenprüfung** (`lmnt_admin_run`, `lmnt_ps_action`, implizit `lmnt_settings_req`) sollten zuerst umgestellt werden.

## Tests

`lmnt test` (Server-Konsole) bzw. `!test`. Gruppen in `sv_netapi.lua`:

| Gruppe | Fälle | Inhalt |
|---|---|---|
| `Net.Schema` | 9 | ungültige Schemas, Bitgrößen, Sendeprüfung, Roundtrip mit `list`/`record`/`optional`, Listen-Lücken, manipulierte Werte (Bereich, Länge, Muster, UTF-8), float (NaN, Rundung), Entities/Spieler, Paketlänge |
| `Net.RateLimiter` | 5 | Kontingent, Zeitverfall, unabhängige Schlüssel, Zeitsprung rückwärts, Reset/Prune, je Nachricht |
| `Net.Verstöße` | 11 | Punkte-Verfall, gültiges Paket, Übergröße vor dem Lesen, Flood mit gedrosseltem Log, Recht (Deny-by-default), falsche Richtung, Log ohne Paketinhalt, Schwelle und Kick, Schwelle 0 und Verfall, Nachmeldung unterdrückter Verstöße |
| `Net.Registrierung` | 6 | Reload mit gleichem Schema, anderes Schema/andere Richtung = Fehler, Übernahme von Recht/Rate-Limit, `perm`-Pflicht, ungültige Namen/Schlüssel, `maxBits` |
| `Net.Dienst` | 3 | Einstellungen, Event, `!netstats`, Selbsttest-Nachricht, Fehlbedienung = Entwicklerfehler |

Echte Übertragung prüft der Selbsttest (siehe Diagnose).
