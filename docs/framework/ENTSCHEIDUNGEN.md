# Architekturentscheidungen (ADR-Log)

## ADR-001 – TTT2 0.14.6b als Basis, Adapter-Schicht für alle TTT2-Zugriffe
**Kontext:** TTT2 ändert APIs zwischen Versionen (Beispiel: `SHOP_FALLBACK_TRAITOR` existiert nicht mehr).
**Entscheidung:** LMNT-Module greifen nur über `LMNT.TTT2` auf TTT2 zu. Die getestete Version steht in `KOMPATIBILITAET.md`.
**Folge:** Bei TTT2-Updates wird ein einziges Modul angepasst und neu getestet.

## ADR-002 – Eigenes Rangsystem bleibt, wird aber CAMI-konform
**Kontext:** Der Auftrag verlangt, kein konkurrierendes Rechtesystem einzuführen. Auf dem Server existiert kein anderes. Das LMNT-Admin-System ist das Rechtesystem des Servers (Entscheidung des Betreibers).
**Entscheidung:** LMNT registriert Ränge **und Privilegien** bei CAMI. Andere Addons, auch TTT2, fragen Rechte also über den Standardweg ab.

## ADR-003 – SQLite synchron, mit Cache und gebündeltem Schreiben; MySQL nur als optionaler Adapter
**Kontext:** In GMod ist SQLite (`sql.*`) synchron. `mysqloo` ist ein Binärmodul und nicht installiert.
**Entscheidung:** Es gibt keine vorgetäuschte Asynchronität. Lesen geschieht beim Join (eine Abfrage pro Tabelle), Schreiben als Transaktion bei Rundenende und Disconnect. Die Adapter-Schnittstelle erlaubt später einen echten asynchronen `mysqloo`-Adapter (Frage F-01).

## ADR-004 – TTT2-HUD-System erweitern statt eigenes HUD-Framework
**Kontext:** TTT2 bringt mit `hudelements` bereits HUD-Elemente mit Editiermodus, Verschieben, Skalieren, Speichern und Zurücksetzen mit (geprüft: `cl_hud_editor.lua:268` `HUDEditor.EditHUD`, `:313` `SaveData`, `hud:Reset()`, `HUDELEMENT:IsResizable`, `scalable_hud`).
**Entscheidung:** LMNT-HUD-Elemente werden als TTT2-HUD-Elemente mit LMNT-Skin umgesetzt. Damit sind alle Anforderungen aus 5.3 erfüllbar, ohne die Mechanik doppelt zu implementieren.

## ADR-006 – Modul-Bereinigung durch Erfassung beim Laden
**Kontext:** Module sollen sich zur Laufzeit abschalten lassen, ohne dass Hooks, Timer oder Befehle zurückbleiben (Auftrag 3.4). Die bestehenden Feature-Dateien nutzen direkt `hook.Add` usw.
**Entscheidung:** Während ein Modul lädt, werden `hook.Add`, `timer.Create`, `net.Receive` und `concommand.Add` vorübergehend umhüllt. Framework-Registries (Admin-Befehle, Events, Speed-Modifikatoren) melden sich über `LMNT.Modules.TrackUndo`. Beim Deaktivieren und bei Startfehlern wird alles in umgekehrter Reihenfolge zurückgenommen.
**Folgen:** Bestehender Code bleibt unverändert, und das Bereinigen lässt sich nicht vergessen. Registrierungen, die erst später zur Laufzeit entstehen, werden nicht erfasst (dafür `M:Hook`/`M:Timer`/`M:On`). `timer.Simple` und Netzwerkstrings sind technisch nicht entfernbar. Das ist dokumentiert in `api/modules.md`.
**Nachweis:** Unit-Tests „Deaktivieren entfernt Hooks, Timer, Events und kaskadiert“ und „Fehler beim Start nimmt alle Registrierungen zurück“, Integrationstest `ttt.stats` aus/an auf dem Server.

## ADR-007 – `LMNT.Settings` neben `LMNT.Config`
**Entscheidung:** `LMNT.Config` bleibt die statische Grundkonfiguration. Ingame änderbare Werte sind `LMNT.Settings` mit Schema. Werte, die in Settings gewandert sind, wurden aus `LMNT.TTT.Config` entfernt, damit es keine doppelte Wahrheit gibt.

## ADR-008 – Unit-Tests laufen auf dem echten Server
**Kontext:** Eine nachgebaute GLua-Umgebung (Mocks für `hook`, `net`, `sql` …) würde von GMod abweichen.
**Entscheidung:** Die Tests laufen per `lmnt test` im echten srcds und werden automatisch von `tools/test_server.ps1` ausgeführt. Unabhängige Instanzen (`LMNT.Events.New`, `LMNT.Modules.New`) verhindern Seiteneffekte auf den laufenden Server.

## ADR-009 – Integrationen sind Module mit Erkennung
**Entscheidung:** `LMNT.Integrations` legt für jede Integration intern ein Modul `int.<id>` an (mit `persist = false`, Zustand über eine eigene Einstellung). Erkennung, Validierung, Kompatibilitäts- und Nachweisstatus kommen hinzu. Lebenszyklus und Bereinigung werden nicht doppelt implementiert.

## ADR-010 – Kein Sandbox-Versprechen
**Kontext:** GMod-Addons laufen mit vollem Lua-Zugriff. Eine echte Isolation ist in GLua nicht möglich.
**Entscheidung:** Das SDK begrenzt nur die Risiken, die LMNT kontrolliert (minimale API, serverseitige Rechte, Validierung, kontrollierte Deaktivierung). Diese Grenze steht in der SDK-Doku und in `SICHERHEIT.md`.

## ADR-011 – LMNT-Admin ist dauerhaft das führende Rechtesystem (Entscheidung F-07, 17.10.2026)
**Kontext:** Der Auftrag verlangt, kein konkurrierendes Rechtesystem einzuführen. Gefragt war, ob LMNT-Admin führend bleibt oder ein Fremdsystem (ULX/SAM) per Adapter genutzt wird.
**Entscheidung (Betreiber):** LMNT-Admin bleibt führend und einziges Rechtesystem des Servers.
**Folgen:**
- Andere Addons fragen Rechte über CAMI ab, LMNT antwortet (Integration `cami`).
- Fremde Admin-Mods werden erkannt und als Konflikt gemeldet (Integration `ulx`). Empfohlen wird, sie zu entfernen.
- Für den Umstieg gibt es eine **einmalige Migration** von Rängen und Banns aus ULib nach LMNT (`!ulximport`, Probelauf als Standard). Danach gibt es keinen laufenden Abgleich in beide Richtungen.
- Adapter, die Fremdsysteme zur Rechtequelle machen, werden nicht gebaut.

## ADR-005 – Zwei Addons statt Monolith
**Entscheidung:** `lmnt_core` bleibt gamemode-unabhängig (wiederverwendbar für andere LMNT-Server), `lmnt_ttt` enthält die TTT2-Integration. Eine Neustrukturierung brächte keinen Nutzen (Auftrag Abschnitt 12).
