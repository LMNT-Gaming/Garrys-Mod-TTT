# API: LMNT.Events (seit 1.1.0)

Datei: `lmnt_core/lua/lmnt/core/sh_events.lua` · Realm: shared (eigener Bus pro Realm)

## Zwei Event-Arten

| Art | Auslösen | Verhalten |
|---|---|---|
| **Beobachter** | `Emit(name, ...)` | Alle Listener laufen. Rückgaben werden ignoriert. Ein Listener kann die anderen weder stoppen noch beeinflussen |
| **Entscheidung** | `Ask(name, ...) → wert, listenerId` | Listener laufen nach `priority` (hoch zuerst). Der erste Rückgabewert `~= nil` entscheidet, danach läuft keiner mehr. Nur für Events mit `Define{ decision = true }` |

Fehler in Listenern werden mit `pcall` isoliert, als `error` protokolliert (Kategorie `events`) und in der Statistik gezählt. Sie werden **nicht verschluckt**.

## Funktionen

| Funktion | Rückgabe | Hinweise |
|---|---|---|
| `Define(name, { desc, args, decision })` | def | dokumentiert ein Event. Undokumentierte Events erzeugen mit `lmnt_events_debug 1` einen Hinweis |
| `On(name, id, fn, { owner, priority })` | id | gleiche `id` ersetzt den alten Listener (kein Doppel). Wird während eines Modul-Ladevorgangs automatisch dem Modul zugeordnet |
| `Off(name, id)` | bool | |
| `RemoveOwner(owner)` | Anzahl | entfernt alle Listener eines Eigentümers |
| `Emit(name, ...)` | – | |
| `Ask(name, ...)` | wert, id | Fehler, wenn das Event nicht als Entscheidung definiert ist |
| `Stats()` | `{ [name] = { calls, errors, time, listeners } }` | Laufzeit in Sekunden (SysTime) |
| `ListenerCount(name)` | Zahl | |
| `New()` | Bus | unabhängige Instanz mit `:`-Methoden (Tests) |

## Namensräume

`lmnt.<bereich>.<ereignis>`. Definiert sind:

| Event | Argumente | Realm |
|---|---|---|
| `lmnt.core.phase` | phase | shared |
| `lmnt.module.enabled` / `.disabled` | id | shared |
| `lmnt.module.failed` | id, fehler | shared |
| `lmnt.settings.changed` | key, neu, alt, actor | shared |
| `lmnt.log.written` | level, kategorie, text | server |

### TTT2-Events (Adapter der Integration `ttt2`, seit 1.2.0)

| Event | Argumente | Quelle (TTT2 0.14.6b) | Realm |
|---|---|---|---|
| `lmnt.round.prepare` | – | `TTTPrepareRound` | shared |
| `lmnt.round.begin` | – | `TTTBeginRound` | shared |
| `lmnt.round.end` | result (Gewinnerteam, **nur Server**, auf dem Client `nil`) | `TTTEndRound` | shared |
| `lmnt.player.death` | victim, attacker, inflictor | `TTT2PostPlayerDeath` (nach der TTT2-Verarbeitung, Leiche existiert) | server |
| `lmnt.player.role` | ply, alteUnterrolle, neueUnterrolle | `TTT2UpdateSubrole`, **nur bei echter Änderung** | shared |
| `lmnt.player.team` | ply, altesTeam, neuesTeam | `TTT2UpdateTeam`, **nur bei echter Änderung** | shared |
| `lmnt.player.ready` | ply | `TTT2PlayerReady` | shared |
| `lmnt.shop.purchase` | ply, klasse, istItem, credits | `TTT2OrderedEquipment`. Der Legacy-Hook `TTTOrderedEquipment` wird bewusst **nicht** angebunden, weil sonst jeder Kauf doppelt gezählt würde | server |

Bestehende LMNT-Module nutzen teils noch die TTT2-Hooks direkt und werden schrittweise umgestellt. Neue Module sollen die LMNT-Events verwenden.

## Beispiel

```lua
LMNT.Events.Define("mein.bonus", { desc = "Darf ein Spieler Bonus-XP bekommen?", args = { "ply" }, decision = true })

LMNT.Events.On("mein.bonus", "Mein.NurAktive", function(ply)
	if ply:IsSpec() then return false end
end, { priority = 10 })

local erlaubt = LMNT.Events.Ask("mein.bonus", ply) ~= false
```

Debug: `lmnt_events_debug 1` gibt jede Listener-Ausführung mit Dauer aus. `!events` zeigt die Statistik.
