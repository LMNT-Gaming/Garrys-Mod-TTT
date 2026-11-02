# API: LMNT.Modules (seit 1.1.0)

Datei: `lmnt_core/lua/lmnt/core/sh_modules.lua` · Realm: shared

## Konzept

Ein Modul ist ein einzeln abschaltbares Feature mit festen Dateien, Abhängigkeiten und einem Lebenszyklus. Alles, was ein Modul **beim Laden** registriert, wird automatisch erfasst und beim Deaktivieren entfernt: Hooks, Timer, Netzwerk-Empfänger, Konsolenbefehle, Admin-Befehle, Event-Listener und TTT-Geschwindigkeitsmodifikatoren.

| Zustand | Bedeutung |
|---|---|
| `enabled` | läuft |
| `disabled` | vom Admin abgeschaltet |
| `blocked` | eine Abhängigkeit fehlt oder ist aus, oder ein Konflikt besteht. Startet automatisch, sobald die Abhängigkeit wieder läuft |
| `failed` | Fehler beim Start (alle Registrierungen wurden zurückgenommen) oder zyklische Abhängigkeit |

## Funktionen

### `LMNT.Modules.Register(def) → M`
| Feld | Typ | Pflicht | Bedeutung |
|---|---|---|---|
| `id` | string `[a-z0-9._-]` | ja | eindeutige ID, z. B. `ttt.stats` |
| `name`, `description` | string | – | Anzeige |
| `version` | SemVer | – | Standard `1.0.0` |
| `framework` | SemVer | – | benötigte LMNT-Mindestversion, sonst `failed` |
| `files` | Liste | – | relativ zu `lua/`. Präfix `sv_`/`cl_`/`sh_` bestimmt den Realm |
| `depends`, `conflicts` | Liste von IDs | – | |
| `required` | bool | – | nicht abschaltbar |
| `default` | bool | – | Zustand, solange nie umgeschaltet (Standard `true`) |
| `init(M)` | function | – | nach dem Laden der Dateien, läuft unter Erfassung |
| `shutdown(M)` | function | – | vor der Bereinigung |

**Fehler:** ungültige oder doppelte aktive ID → `error`. **Seiteneffekte:** Auf dem Server werden `sh_`/`cl_`-Dateien sofort an Clients verteilt. Für nicht erforderliche Module wird die Einstellung `module.<id>.enabled` angelegt (persistiert und repliziert).

### `LMNT.Modules.StartAll() → gestartet, gesamt`
Startet alle gewünschten Module in topologischer Reihenfolge. Wird vom Framework in `PostGamemodeLoaded` aufgerufen. Eigene Module registriert man über den Hook `LMNT.RegisterModules`.

### `Enable(id)` / `Disable(id, grund)` / `Reload(id)` → `ok, fehler|kaskade`
`Disable` stoppt abhängige Module zuerst (sie werden `blocked`) und gibt deren IDs zurück. Persistente Daten werden **nie** gelöscht. `Reload` = Disable + Enable mit erneutem Laden der Dateien. Für dauerhafte Umschaltung immer die Einstellung nutzen (`!module <id> an|aus`), denn nur sie wirkt auch auf Clients und übersteht einen Neustart.

### `Get(id)`, `Status()`, `Order()`, `New({ persist = false })`
`Status()` liefert `{ id, name, version, state, error, required, depends, registrations }`. `New` erzeugt eine unabhängige Registry (für Tests).

### Modul-Kontext `M` (in `init`/`shutdown`)
| Methode | Zweck |
|---|---|
| `M:Hook(event, fn)` | Hook, der auch **zur Laufzeit** sicher bereinigt wird |
| `M:Timer(name, delay, reps, fn)` | dto. für Timer |
| `M:On(event, fn, opts)` | LMNT-Event-Listener mit Eigentümer |
| `M:Setting(key)` | = `LMNT.Settings.Get` |
| `M:LogInfo/LogWarn/LogError(text)` | Log mit dem Modul als Kategorie (Server) |

### `LMNT.Modules.TrackUndo(fn)`
Für eigene Registries: Wenn gerade ein Modul lädt, wird `fn` beim Deaktivieren ausgeführt. Beispiel siehe `LMNT.TTT.AddSpeedModifier`.

## Grenzen (bewusst dokumentiert)
- Registrierungen, die erst **später** in Callbacks entstehen, erfasst das System nicht. Dafür `M:Hook`/`M:Timer`/`M:On` nutzen.
- `timer.Simple` lässt sich in GMod nicht entfernen. Ein schon geplanter Aufruf läuft nach dem Deaktivieren noch einmal.
- `util.AddNetworkString` ist nicht rückgängig zu machen. Nur der Empfänger wird entfernt.
- `Reload` lädt die Dateien nur auf dem Server neu. Clients erhalten geänderte Dateien beim nächsten Verbinden.

## Beispiel: eigenes Modul in einem Addon

```lua
-- lua/autorun/mein_addon.lua
hook.Add("LMNT.RegisterModules", "MeinAddon", function()
	LMNT.Modules.Register({
		id = "mein.willkommen", name = "Willkommensnachricht", framework = "1.1.0",
		files = { "mein_addon/sv_willkommen.lua" },
	})
end)

-- lua/mein_addon/sv_willkommen.lua  (wird automatisch erfasst und bereinigt)
LMNT.Settings.Define("mein.willkommen.text", { type = "string", default = "Willkommen!", maxLength = 120, category = "Mein Addon" })
hook.Add("PlayerInitialSpawn", "Mein.Willkommen", function(ply)
	LMNT.Notify(ply, LMNT.Settings.Get("mein.willkommen.text"))
end)
```
