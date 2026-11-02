# API: LMNT.HTTP und Discord-Weiterleitung (T-131)

Datei: `lmnt_core/lua/lmnt/services/sv_http.lua` · Realm: **nur Server** · Tests: `lmnt_core/lua/lmnt/tests/sv_http.lua`

## Grundsatz

Externe Kommunikation läuft ausschließlich über **registrierte Endpunkte**. Module rufen nie selbst `HTTP()`, `http.Fetch` oder `http.Post` auf und kennen keine URLs mit Geheimnissen. Der Dienst bündelt dafür:

- **nicht blockierend**: `Send` reiht nur ein. Gesendet wird asynchron über die GMod-Funktion [`HTTP`](https://wiki.facepunch.com/gmod/Global.HTTP) ([`HTTPRequest`](https://wiki.facepunch.com/gmod/Structures/HTTPRequest)), höchstens **eine Anfrage pro Endpunkt gleichzeitig**
- **Timeout** pro Anfrage (`timeout` von `HTTPRequest`) und zusätzlich ein **Wächter**: Eine Anfrage, die nach `timeout + 5 s` noch offen ist, gilt als fehlgeschlagen. Eine spätere Antwort wird ignoriert
- **Wiederholungen** mit Backoff (2 s, 4 s, 8 s … höchstens 60 s, bei `429` nach `Retry-After`)
- **Rate-Limit** pro Endpunkt (gleitendes Fenster). Überzählige Nachrichten warten, werden mit `merge` zusammengefasst oder bei voller Warteschlange **verworfen und gezählt**
- **Payload-Grenze** auf den kodierten Body
- **Protokollierung** in der Kategorie `http`: Statuswechsel als `info`, Störungen als `warn`, höchstens einmal pro Minute und Endpunkt. Die Kategorie `http` wird nie an Discord weitergeleitet, damit eine Störung keine Rückkopplung auslöst

## Funktionen

| Funktion | Rückgabe | Hinweise |
|---|---|---|
| `RegisterEndpoint(id, def)` | `aktiv, grund` | gleiche `id` ersetzt die Definition, Warteschlange und Statistik bleiben (Lua-Reload). Innerhalb eines Modul-Ladevorgangs wird der Endpunkt beim Deaktivieren automatisch entfernt. Ungültige Definition = `error` (Programmierfehler) |
| `Send(id, body, callback)` | `true` / `false, grund` | `body`: String, Tabelle (→ JSON über `EncodeJSON`) oder `nil` |
| `Unregister(id)` | bool | laufende und wartende Nachrichten enden mit `error = "unregistered"` |
| `IsEnabled(id)` | bool | |
| `ReloadSecrets()` | Anzahl aktiver Endpunkte | liest `secrets.json` neu, z. B. nach dem Eintragen eines Webhooks: `lua_run LMNT.HTTP.ReloadSecrets()` |
| `Stats()` | `{ [id] = {…} }` | siehe unten. Enthält **nie** URL oder Header |
| `Pump()` | – | ein Durchlauf der Warteschlange. Läuft automatisch alle 0,25 s |
| `EncodeJSON(wert)` | String | ganze Zahlen ohne Nachkommastellen, leere Tabelle = `[]`, Schlüssel sortiert, Fehler bei Zyklen |
| `New(opts)` | Instanz | unabhängiger Dienst mit `:`-Methoden für Tests: `transport(request) → bool`, `clock() → s`, `secrets` (Tabelle statt Datei), `quiet`, `started` |

### Endpunkt-Definition

| Feld | Standard | Bedeutung |
|---|---|---|
| `url` | – | feste URL ohne Geheimnis. Entweder `url` oder `urlSecret` |
| `urlSecret` | – | Schlüssel in `data/lmnt/secrets.json`, dessen Wert die URL ist |
| `urlPattern` | – | Lua-Muster oder Liste. Passt die URL nicht, bleibt der Endpunkt deaktiviert |
| `method` | `POST` | `GET` `POST` `HEAD` `PUT` `DELETE` `PATCH` `OPTIONS` (laut Wiki) |
| `type` | `application/json` | Content-Type des Bodys (Feld `type` von `HTTPRequest`) |
| `headers` | – | feste Header. Laut Wiki (`http.Fetch`) gesperrt: `host`, `content-length`, `connection`, `origin` u. a. |
| `headerSecrets` | – | `{ Header = "schlüssel" }`, Wert kommt aus `secrets.json` |
| `timeout` | 10 | Sekunden, 1–60 |
| `maxPayload` | 8192 | Bytes, 1–1 MiB |
| `rateLimit` | `{ count = 10, perSeconds = 60 }` | Anfragen pro Zeitfenster (Wiederholungen zählen mit) |
| `retries` | 2 | 0–5, nur bei Netzfehler, `408`, `429`, `5xx` |
| `queueSize` | 50 | wartende Nachrichten, danach `queue_full` |
| `merge(bodies) → body` | – | fasst wartende Nachrichten zu einer Anfrage zusammen (Liste der Original-Bodys). Es wird nur zusammengefasst, solange das Ergebnis `maxPayload` einhält |
| `mergeMax` | 10 | höchstens so viele Nachrichten pro Anfrage |

### Ergebnis

`callback(ok, info)` mit `info = { code, body, headers, error, attempts, latency }`. Liefert `Send` **true**, läuft der Callback **genau einmal**: bei Erfolg (`2xx`), nach dem endgültigen Fehler oder beim Verwerfen (Deaktivieren, `Unregister`). Fehler im Callback werden als `warn` protokolliert und stören nichts.

| Grund (`Send` → false) | Bedeutung |
|---|---|
| `unknown_endpoint` | nicht registriert (einmalige Warnung pro ID) |
| `disabled` | Geheimnis fehlt, URL ungültig oder falsches Format |
| `invalid_body` | weder String noch kodierbare Tabelle |
| `payload_too_large` | Body > `maxPayload` (zählt als verworfen) |
| `queue_full` | Warteschlange voll (zählt als verworfen) |

| Fehler (`info.error`) | Bedeutung |
|---|---|
| Text aus `failed(reason)` | Netz-/DNS-/TLS-Fehler laut GMod, z. B. `unsuccessful` |
| `HTTP <code>` | Antwort außerhalb von `2xx` |
| `watchdog_timeout` | keine Antwort nach `timeout + 5 s` |
| `not_queued` | `HTTP()` lieferte `false` (z. B. Start mit `-disablehttp`) |
| `disabled` / `unregistered` | Endpunkt wurde abgeschaltet bzw. entfernt |

### Statistik (`Stats()[id]`)

`enabled`, `reason` (warum deaktiviert), `sent` (zugestellte Nachrichten), `failed` (endgültig fehlgeschlagene Nachrichten), `dropped` (verworfene Nachrichten), `merged` (in eine andere Anfrage zusammengefasste Nachrichten), `retries`, `requests` (HTTP-Anfragen inkl. Wiederholungen), `queued`, `inflight`, `lastLatency` (s), `lastCode`, `lastError`, `lastSuccess` (Unix-Zeit).

## Geheimnisse

Geheimnisse (Webhook-URLs, Tokens) stehen **nur** in `garrysmod/data/lmnt/secrets.json` der Server-Installation. Vorlage: `garrysmod/data/lmnt/secrets.example.json`.

```json
{
	"_hinweis": "Schlüssel mit _ am Anfang sind Kommentare",
	"discord_webhook_security": "https://discord.com/api/webhooks/<id>/<token>"
}
```

- **Nicht** über `LMNT.Settings`, denn deren Werte erscheinen in `!config`, in `lmnt_config` und ggf. bei Clients.
- Fehlt die Datei, ein Schlüssel oder ist ein Wert leer, bleibt der Endpunkt **deaktiviert**. Das ist ein `info`-Eintrag (`http`), kein Fehler. Ungültiges JSON ergibt eine Warnung.
- Der `data`-Ordner wird nicht an Clients ausgeliefert. `server/deploy.ps1` kopiert nur `workshop.json`, `secrets.json` wird also nie überschrieben oder verteilt. Die Datei gehört nicht ins Repository (`.gitignore`, T-001).
- **Grenze (ADR-010):** Anderes serverseitiges Lua kann die Datei ebenfalls lesen. Der Dienst verhindert nur, dass Geheimnisse über LMNT-Wege (Settings, Logs, Stats, Netzwerk) nach außen gelangen.

## Discord-Weiterleitung (`LMNT.Discord`)

Der Listener auf `lmnt.log.written` sammelt Einträge ab der eingestellten Stufe und sendet alle **5 s** ein gebündeltes Embed in LMNT-Rot (`#ff3131`) an den Endpunkt `discord.security`.

| Einstellung | Typ | Standard | wirkt |
|---|---|---|---|
| `lmnt.discord.enabled` | bool | true | live. Ohne Webhook in `secrets.json` passiert trotzdem nichts |
| `lmnt.discord.min_level` | enum `security` · `error` | `security` | live. `error` schließt `security` ein |
| `lmnt.discord.redact_ids` | bool | true | live. SteamIDs werden zu `[SteamID]` |

Endpunkt `discord.security`: `urlSecret = "discord_webhook_security"`, nur Discord-Webhook-URLs (`discord.com`, `discordapp.com`, `canary.`/`ptb.discord.com`), Timeout 10 s, 3 Wiederholungen, höchstens 10 Anfragen pro Minute, 20 wartende Bündel, `maxPayload` 6000 Bytes. Wartende Bündel werden zu einer Nachricht mit bis zu 10 Embeds zusammengefasst.

**Spam- und Datenschutz:**
- höchstens 50 Einträge pro Bündel, weitere werden nur gezählt („… und N weitere Einträge“), Text pro Eintrag höchstens 300 Bytes, Beschreibung höchstens 3500 Bytes
- `allowed_mentions.parse = []`: Log-Texte können niemanden anpingen (`@everyone`, Rollen, Nutzer)
- IP-Adressen werden **immer** entfernt (`[IP]`), SteamIDs je nach `lmnt.discord.redact_ids`. Spielernamen bleiben, weil sie für die Einordnung nötig sind. Vollständige Daten stehen nur im Server-Log
- Discord-Markdown in Log-Texten wird entschärft
- Kategorien `http` und `discord` werden nie weitergeleitet (keine Rückkopplung bei Störungen)

| Funktion | Hinweise |
|---|---|
| `LMNT.Discord.ShouldForward(stufe, kategorie, minStufe)` | reine Filterfunktion |
| `LMNT.Discord.BuildPayload(einträge, zusätzlich, steamIdsEntfernen)` | Webhook-Body als Tabelle |
| `LMNT.Discord.Merge(bodies)` | fasst Bodys zusammen (Embeds hintereinander) |
| `LMNT.Discord.Flush()` | sendet das aktuelle Bündel sofort |
| `LMNT.Discord.Pending()` | gesammelte Einträge, gezählte Überzählige |

**Einrichtung:** In Discord unter Kanal → Integrationen → Webhooks einen Webhook anlegen und die URL als `discord_webhook_security` in `secrets.json` eintragen. Danach den Server neu starten oder `lua_run LMNT.HTTP.ReloadSecrets()` ausführen. `lua_run PrintTable(LMNT.HTTP.Stats())` zeigt den Zustand.

## Beispiel

```lua
LMNT.HTTP.RegisterEndpoint("stats.export", {
	urlSecret = "stats_api_url",
	headerSecrets = { Authorization = "stats_api_token" },
	rateLimit = { count = 4, perSeconds = 60 },
	maxPayload = 4096,
})

local ok, grund = LMNT.HTTP.Send("stats.export", { runde = 12, spieler = 9 }, function(erfolg, info)
	if not erfolg then LMNT.Log.Warn("stats", "Export fehlgeschlagen: " .. tostring(info.error)) end
end)
```

## Grenzen (ehrlich dokumentiert)

- **Hibernation:** Ist der Server leer, laufen in GMod standardmäßig keine Timer (`sv_hibernate_think 0`). Gesammelte Discord-Bündel, Wiederholungen und der Wächter laufen dann erst weiter, wenn wieder jemand verbunden ist. Wer Meldungen auch bei leerem Server sofort braucht, setzt `sv_hibernate_think 1`.
- Laut Wiki erreicht `HTTP()` keine privaten Netze (`127.0.0.1`, `192.168.x.x`), außer mit `-allowlocalhttp` (nur Dedicated Server).
- Laut Wiki sind keine doppelten Header-Namen möglich, und sehr große Antworten können als `unsuccessful` enden.
- Der Dienst sendet nie während des Ladens, sondern frühestens im ersten Timer-Takt.
- Geht nur die Antwort verloren (Wächter), kann die Wiederholung eine Nachricht doppelt zustellen.
