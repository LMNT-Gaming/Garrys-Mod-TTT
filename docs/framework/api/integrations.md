# API: LMNT.Integrations (seit 1.2.0)

Datei: `lmnt_core/lua/lmnt/core/sh_integrations.lua` · Realm: shared (Erkennung läuft in jedem Realm getrennt) · Konzept: [06_INTEGRATIONEN.md](../06_INTEGRATIONEN.md)

## Ablauf beim Start
`PostGamemodeLoaded` → Module starten → Dateien aus `lua/lmnt/integrations/` (aller Addons) laden → Hook `LMNT.RegisterIntegrations` → `LMNT.Integrations.StartAll()` → Phase `ready`.
`StartAll` läuft für jede Integration: **Erkennung → Abhängigkeiten → Schnittstellenprüfung → Versionsabgleich → Aktivierung** (nur wenn `COMPATIBLE` und per Einstellung gewünscht). Fehlende optionale Addons verhindern den Start nie.

## Funktionen

| Funktion | Rückgabe | Hinweise |
|---|---|---|
| `Register(id, def)` | def | Pflicht: `detect`. Legt die Einstellung `integration.<id>.enabled` an (nicht bei `detectOnly`) |
| `StartAll()` | – | einmal beim Start, mehrere Durchläufe für Abhängigkeiten zwischen Integrationen |
| `Evaluate(id)` | Status | erkennt und prüft neu. Aktive Integrationen bleiben unverändert |
| `Enable(id)` / `Disable(id)` | `ok, meldung` | `Disable` bei `live = false` → `false` + Vormerkung für den Neustart |
| `RunTests(id)` | bestanden, fehlgeschlagen, meldungen | hebt die Nachweisstufe nur bei Erfolg (`testLevel`, Standard `basic_test`). Teilweise erfolgreich → `partial` |
| `GetStatus(id)` / `List()` | Status-Kopie(n) | `state, reason, level, evidence, checks, warnings, detectedVersion, lastTest, pendingRestart, registrations` + Metadaten |
| `Conflicts()` | Liste `{ a, b, kind, description }` | `declared` (beide installiert) und `core` (`conflictsWithCore`) |
| `New({ persist = false })` | Instanz | für Tests |

## Regeln für `detect()`
Rückgabe `gefunden, { belege }, version`. **Mindestens zwei unabhängige Belege**, sonst `DETECTED` mit „schwach belegt“ und keine automatische Aktivierung. Es reicht also kein Dateiname und keine einzelne globale Variable.

## Regeln für `validate()`
Rückgabe `{ { name, ok, optional } }`. Fehlt eine Pflicht-Schnittstelle → `INCOMPATIBLE`. Fehlt eine optionale → Warnung → bei Aktivierung `DEGRADED`.

## Mitgelieferte Integrationen

| ID | Addon | Art | Zustand auf dem LMNT-Server (Stand 17.10.2026) |
|---|---|---|---|
| `ttt2` | lmnt_ttt | Versions- und Schnittstellenprüfung, 4 Integrationstests | wird im Integrationstest ermittelt |
| `cami` | lmnt_core | Adapter: Ränge und Rechte → CAMI, beantwortet `CAMI.PlayerHasAccess` | `NOT_INSTALLED` erwartet (kein CAMI-Addon installiert) |
| `ulx` | lmnt_core | nur Erkennung, Konfliktmeldung mit LMNT-Admin. Umstieg per einmaliger Migration `!ulximport` (`lmnt/services/sh_ulximport.lua`, ADR-011) | `NOT_INSTALLED` erwartet |

## Befehle (Recht `integrations`)
`!integrations` · `!integration <id>` (Details mit Belegen, Prüfungen, Warnungen, Einschränkungen) · `!integration <id> an|aus|pruefen|test` · `!conflicts`

## Eigene Integration (ladbares Minimalbeispiel)

```lua
-- lua/lmnt/integrations/sh_meinaddon.lua in deinem Addon – wird automatisch geladen
LMNT.Integrations.Register("meinaddon", {
	name = "Mein Addon", version = "1.0.0", lmnt = "1.2.0",
	detect = function()
		local ev = {}
		if istable(MeinAddon) then ev[#ev + 1] = "Global MeinAddon" end
		if istable(MeinAddon) and isfunction(MeinAddon.GetVersion) then ev[#ev + 1] = "MeinAddon.GetVersion" end
		return istable(MeinAddon), ev, istable(MeinAddon) and MeinAddon.GetVersion and MeinAddon.GetVersion()
	end,
	validate = function()
		return { { name = "MeinAddon.DoSomething", ok = isfunction(MeinAddon.DoSomething) } }
	end,
	init = function(M)
		hook.Add("MeinAddon.Event", "LMNT.MeinAddon", function(...) LMNT.Events.Emit("meinaddon.event", ...) end)
	end,
})
```
