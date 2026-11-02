# API: Admin-Configurator (Tabs „Module“ und „Einstellungen“, T-027)

Dateien:
- Server: `lmnt_core/lua/lmnt/services/sv_settingsmenu.lua` (wird über `lua/lmnt/services/` automatisch geladen)
- Client: `lmnt_core/lua/lmnt/admin/cl_admin.lua` (Tabs im Admin-Menü `!menu` / `lmnt_menu`)

Der Configurator ist eine grafische Oberfläche über `LMNT.Settings` und `LMNT.Modules`. Er führt **keine eigene Logik** für Werte oder Modulzustände ein: Jede Änderung läuft über `LMNT.Settings.Set` / `LMNT.Settings.Reset` mit dem Spieler als `actor`. Validierung, Speicherung, Log-Eintrag (`config`), Replikation, `onChange` und das Event `lmnt.settings.changed` kommen damit unverändert aus `sh_settings.lua` (siehe [settings.md](settings.md)).

## Warum ein Server-Dienst?
Beim Client liegen nur **replizierte** Werte und nur Definitionen aus geteilten Dateien. Definitionen aus `sv_`-Dateien und nicht replizierte Werte kennt nur der Server, ebenso den echten Modulzustand. Der Dienst schickt deshalb Definitionen, Standard- und aktuelle Werte – **nur an Berechtigte**.

## Tabs

| Tab | sichtbar mit Recht | Inhalt |
|---|---|---|
| Module | `modules` | alle Module aus `LMNT.Modules.Status()` (Server): Name/ID, Version, Zustand farbig (aktiv grün, aus grau, blockiert gelb, fehlerhaft rot), Anzahl erfasster Registrierungen, Fehlergrund bzw. Abhängigkeiten. Buttons *Aktivieren* / *Erneut starten* / *Deaktivieren* (mit Bestätigung), bei `required` gesperrt |
| Einstellungen | `config` | alle Definitionen aus `LMNT.Settings.List()`, für die der Spieler `def.perm` hat, gruppiert nach `category`. Pro Eintrag: Key, Beschreibung, aktueller Wert, Standard, Grenzen, Wirkung (`applies`), typgerechte Eingabe, *Speichern*, *Zurücksetzen* (mit Bestätigung). Filterfeld oben |

Eingaben je Typ: `bool` = Umschalter (An/Aus), `int`/`number` = Zahlenfeld mit Bereich als Platzhalter, `enum` = Dropdown, `string` = Textfeld (max. Länge als Hinweis). Vor dem Senden prüft der Client mit `LMNT.Settings.Validate` vor; maßgeblich ist die erneute Prüfung auf dem Server. Ungespeicherte Änderungen markiert ein gelber Rand, vom Standard abweichende Werte sind gelb.

Wirkung (`applies`): `live` → „wirkt sofort“ (grün), `nextround` → „wirkt ab nächster Runde“ (gelb), `restart` → „wirkt nach Neustart“ (rot).

## Netzwerknachrichten

| Nachricht | Richtung | Inhalt | Prüfungen auf dem Server |
|---|---|---|---|
| `lmnt_admin_cfg_modules` | C→S | leer | max. 64 Bit · 1 Anfrage/s pro Spieler · Recht `modules` |
| | S→C | Modulliste (id, name, version, state, error, required, wanted, registrations, depends) | – |
| `lmnt_admin_cfg_settings` | C→S | leer | max. 64 Bit · 1 Anfrage/s · Recht `config` |
| | S→C | Definitionen (key, type, category, desc, applies, default, wert, min, max, maxLength, choices) | nur Einträge mit `LMNT.HasPerm(ply, def.perm)` |
| `lmnt_admin_cfg_set` | C→S | key, reset (bool), wert als Text | max. 4096 Byte (sonst `security`-Log) · 0,3 s Abstand · Recht `config` · Key muss definiert sein · Recht `def.perm` · danach `Settings.Set/Reset(key, wert, ply)` (prüft erneut und validiert) |
| `lmnt_admin_cfg_module` | C→S | id, an (bool) | max. 256 Byte · 0,3 s Abstand (gemeinsam mit `cfg_set`) · Recht `modules` · Modul registriert · nicht `required` · Schalter `module.<id>.enabled` existiert · danach `Settings.Set("module.<id>.enabled", an, ply)` |
| `lmnt_admin_cfg_result` | S→C | ok, Meldung, optional key + neuer Wert | neuer Wert nur, wenn der Spieler `def.perm` hat |

Fehlende Rechte erzeugen einen Eintrag `security` (Kategorie `config`) und die Antwort „Keine Berechtigung“. Zu schnelle Anfragen werden still verworfen (wie bei den übrigen Admin-Menü-Nachrichten). Ausgehende Listen stoppen bei ca. 60 KB (`net.BytesWritten`) und melden dann „Liste gekürzt“; lange Texte werden gekürzt (Beschreibungen/Fehler 400 Zeichen, Textwerte 1024, max. 64 enum-Auswahlen).

Der Client zeigt jede Antwort als `LMNT.UI.Toast` (grün/rot) und zusätzlich in der Statuszeile des Tabs, weil Toasts unter dem Menü-Fenster liegen können.

## Modulzustand ehrlich melden
`Settings.Set` gelingt auch dann, wenn der anschließende Start an einer Abhängigkeit oder einem Fehler scheitert. Der Dienst liest deshalb nach dem Umschalten den echten Zustand (`LMNT.Modules.Get(id).state`) und meldet z. B. „Modul x ist blocked: Abhängigkeit nicht aktiv: y“ als Fehler. Beim Deaktivieren werden mitgestoppte abhängige Module genannt.

**Erneut starten:** Steht `module.<id>.enabled` bereits auf `true`, das Modul ist aber `blocked`/`failed`, würde `Settings.Set` mit gleichem Wert nichts auslösen. In diesem Fall ruft der Dienst nach der Rechteprüfung `LMNT.Modules.Enable(id)` direkt auf (Log `modules`).

Modul-Schalter erscheinen auch im Tab „Einstellungen“ (Kategorie „Module“), wenn der Spieler `config` **und** `modules` hat.

## Grenzen
- Keine Live-Aktualisierung: Ändert ein anderer Admin etwas, zeigt *Neu laden* den aktuellen Stand.
- *Neu laden* in „Einstellungen“ verwirft ungespeicherte Eingaben.
- Nach einem Fehler beim Speichern setzt der Client die Eingabe auf den aktuellen Serverwert zurück.

## Nur ingame prüfbar
- Darstellung und Skalierung der Tabs (Zeilenhöhen, Texte, Farben, Toast-Lage)
- Umschalten eines Moduls inkl. Kaskade und Rückmeldung, Sperre bei `required`
- Speichern/Zurücksetzen aller Typen, Fehlermeldungen bei ungültigen Werten
- Rechte: Tabs bei Rängen ohne `modules`/`config` unsichtbar, Ablehnung bei manipulierten Nachrichten
