# Integrations-Ökosystem (Auftrag Abschnitte 9–22)

## Leitprinzipien

1. **Integrationen sind Module mit Erkennung.** `LMNT.Integrations` baut auf `LMNT.Modules` auf. Lebenszyklus, Registrierungs-Erfassung und Bereinigung werden geerbt (ADR-009). Neue Integrationen brauchen **keine Core-Änderung**.
2. **Erkennung ≠ Kompatibilität ≠ Nachweis.** Die drei Aussagen werden getrennt geführt und angezeigt.
3. **Mehrere Merkmale.** Eine Erkennung braucht mindestens zwei unabhängige Belege, zum Beispiel eine globale Tabelle *und* eine konkrete Funktion. Mit nur einem Beleg gilt sie als „schwach“ und wird nicht automatisch aktiviert.
4. **Adapter statt Überschreiben.** Adapter übersetzen fremde APIs in LMNT-Services. Fremde Tabellen werden nur über deren offizielle Schnittstellen verändert.
5. **Keine Sandbox-Versprechen.** Fremdes Lua hat vollen Laufzeitzugriff. LMNT begrenzt nur die Risiken, die es selbst kontrolliert (ADR-010).

## Zustände (`LMNT.Integrations.GetStatus(id).state`)

| Zustand | Bedeutung |
|---|---|
| `NOT_INSTALLED` | Zielsystem nicht gefunden |
| `DETECTED` | gefunden, Prüfung steht aus oder ist schwach belegt |
| `COMPATIBLE` | Schnittstellen geprüft, aktivierbar |
| `INCOMPATIBLE` | Schnittstelle fehlt oder Version passt nicht → wird nicht aktiviert |
| `MISSING_DEPENDENCY` | benötigte Integration/Modul fehlt |
| `DISABLED` | vom Admin deaktiviert |
| `INITIALIZING` | Aktivierung läuft |
| `ACTIVE` | läuft |
| `DEGRADED` | läuft eingeschränkt (z. B. ungetestete Version, optionale Teilfunktion fehlt) |
| `FAILED` | Fehler bei der Aktivierung, alle Registrierungen zurückgenommen |

## Nachweisstufen (getrennt vom Zustand)

`unknown` (unbekannt) · `detected` (Erkennung erfolgreich) · `interface` (Schnittstelle vorhanden) · `basic_test` (Grundtest erfolgreich) · `partial` (teilweise getestet) · `verified` (vollständig nachgewiesen).
`interface` setzt das Framework automatisch nach erfolgreicher Validierung. `basic_test` und `verified` gibt es **nur** mit einem hinterlegten, ausgeführten Test. Alles darüber hinaus wird in der Kompatibilitätsmatrix als **manuell gepflegt** gekennzeichnet.

## Definition einer Integration

```lua
LMNT.Integrations.Register("cami", {
	name = "CAMI", description = "Gemeinsame Admin-Mod-Schnittstelle",
	version = "1.0.0", vendor = "Community-Standard", lmnt = "1.2.0",
	ttt2 = { "0.14.6b" },                 -- getestete TTT2-Versionen (optional)
	depends = {}, optional = {},          -- Integrations- oder Modul-IDs
	conflicts = { "ulx" },
	live = true,                          -- Live-Umschaltung erlaubt? sonst Vormerkung für Neustart
	detect = function() return found, { "Beleg 1", "Beleg 2" }, erkannteVersion end,
	validate = function() return ok, { { name = "CAMI.RegisterPrivilege", ok = true }, ... } end,
	files = { ... }, init = function(M) end, shutdown = function(M) end,
	tests = { { name = "...", run = function(e) ... end } },  -- Integrationstests (laufen im Server)
	limitations = { "..." },              -- bekannte Einschränkungen (Matrix)
})
```

## Stufenplan (Abschnitt 21)

| Stufe | Inhalt | Arbeitspaket |
|---|---|---|
| A | Integration Manager, Metadaten, Abhängigkeiten, Lebenszyklus, Logging, Status, erste Integrationen (TTT2, CAMI, ULX-Erkennung) | WP-10 |
| B | TTT2-Adapter (Events `lmnt.round.*`, `lmnt.player.*`), Rollen- und Item-API, Weapon Registry, Legacy-Kompatibilität, UI/HUD-Regeln | WP-11 |
| C | Map-Registry und -Profile, Punkte-API, Entity-Integration, Gameplay-Event-Modell, Bewegung/Umwelt | WP-12 |
| D | Admin-System-Adapter, Moderation, externe Statistik, Monitoring, Webhooks (Discord) | WP-13 |
| E | SDK-Doku und 7 Vorlagen, automatisierte Integrationstests, Kompatibilitätsmatrix, Release-Prüfung | WP-14 |

## Konfliktmanagement (Abschnitt 10.3)

| Kategorie | Wie erkannt | Bewertung |
|---|---|---|
| gleiche Hook-Namen | `hook.GetTable()` | **erlaubte Mitnutzung**. Nur bei Hooks mit Rückgabewert (z. B. `PlayerSay`, `EntityTakeDamage`) → „mögliche Reihenfolgeabhängigkeit“ |
| gleiche Netzwerkkanäle | erfasste `net.Receive`-Namen je Integration | Konflikt, wenn zwei Integrationen denselben Kanal empfangen |
| gleiche Konsolen-/Admin-Befehle | erfasste Befehlsnamen | Konflikt |
| gleiche Rollen-/Item-/Waffen-IDs | Registry-Prüfung beim Registrieren | Konflikt, zweite Registrierung wird abgelehnt |
| deklarierte `conflicts` | Definition | Konflikt, Lösung über Priorität oder explizite Auswahl, **nie** über die Ladereihenfolge |

## Grenzen (ehrlich dokumentiert)

- Viele Workshop-Addons haben keine Versionsnummer. Dann ist die Version „unbekannt“, und es wird keine volle Kompatibilität behauptet.
- Das Admin-Menü installiert keine Workshop-Addons und ändert keine Dateien (Abschnitt 19).
- Externe Dienste (Stufe D) laufen nur über einen zentralen HTTP-Service mit Timeouts und Rate-Limits. Ein Ausfall blockiert nie das Spiel.
