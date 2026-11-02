# LMNT-Designsystem (abgeleitet aus lmnt-gaming.net)

Quelle: `https://lmnt-gaming.net/assets/css/app.css?v=2`, gelesen am 17.10.2026. Die Werte sind wörtlich aus den CSS-Variablen übernommen.

## Markenidentität

- **Wortmarke:** „**LMNT** GAMING COLLECTIVE“, LMNT fett.
- **Tonalität:** knapp, laut, technisch. Nummerierte Abschnitte („01 / WHO WE ARE“), Labels in Großbuchstaben mit weiter Laufweite, Ticker-Bänder mit `✦`-Trennern.
- **Atmosphäre:** fast schwarzer Grund, Akzente in Signalrot, feines Raster im Hintergrund, rote radiale Glows.

## Tokens

| Token | Web-Wert | Rolle im Spiel |
|---|---|---|
| `ink` | `#08070c` | Hintergrund von Fenstern und HUD-Flächen |
| `inkSoft` | `#111018` | Panels, Karten |
| `line` | `rgba(255,255,255,.14)` | Trennlinien, Rahmen |
| `paper` | `#f2efe8` | Primärtext |
| `white` | `#fffdf8` | hervorgehobener Text |
| `muted` | `#a5a1ac` | Sekundärtext, Labels |
| `acid` | `#ff3131` | Primärakzent: aktive Zustände, Fokus, Fortschritt |
| `coral` | `#e10f22` | Buttons, Warnungen mit Markenbezug |
| `violet` (Dunkelrot) | `#a80016` | Pressed-Zustand, Verlaufsende |
| `online` | `#37e66b` | Erfolg und positive Werte (auf der Website: Online-Status) |
| `radius` | `22px` | große Karten. **Im Spiel skaliert:** 8 px (Fenster), 6 px (Buttons) |
| Verlauf | `145deg, #ff3131 → #9b0014 58% → #260008` | Hero-Elemente, Level-up, Spezialrunden-Banner |

Für das Spiel ergänzte Zustandsfarben (nicht von der Website, kontrastgeprüft auf `ink`): `warn #ffb020`, `info #7fb4ff`. Teamfarben bleiben die TTT2-Rollenfarben und werden **nicht** durch Markenfarben ersetzt, sonst gehen spielrelevante Informationen verloren.

## Typografie

| Verwendung | Web | Spiel |
|---|---|---|
| Display (Titel, Zahlen, Banner) | Archivo Black | Archivo Black (TTF per FastDL), Fallback: Roboto Black |
| Text | DM Sans 400/500/700 | DM Sans (TTF per FastDL, Variable-Font-Test offen → R-04), Fallback: Roboto |
| Labels | Großbuchstaben, Laufweite .17–.18em | Großbuchstaben. GMod kennt keine Laufweite, deshalb Label-Schrift eine Stufe kleiner und fett |

Schriftgrößen werden über `LMNT.UI.Scale()` an die Bildschirmhöhe (Basis 1080p) und die TTT2-Skalierung (`appearance`) gekoppelt.

## Komponenten (Phase 5)

Für jede Komponente gibt es die Zustände default, hover, focus, active, disabled und error sowie die Größen sm, md und lg: Button, IconButton, Tabs/Navigation, Liste/Tabelle, Suchfeld, Dropdown, Checkbox, Slider, Fortschrittsbalken, Tooltip, Dialog/Bestätigung, Toast, Lade- und Fehlerzustand, Rollenkarte, Itemkarte, Konfigurationsfeld (typbasiert aus dem Config-Schema), Stat-Kachel und Balkendiagramm.

Gestaltungsregeln:
- Fokus und Aktiv sind immer `acid`. Hover hebt die Fläche an (`inkSoft` → +6 % Helligkeit), es wird nichts verschoben.
- Abschnittstitel im Web-Stil: kleine Nummer in `acid` + Label, zum Beispiel `01 / ROLLEN`.
- Hintergrund großer Fenster: `ink` mit Raster aus 1-px-Linien (`line`, 4,5 % Deckkraft), einmal in eine RenderTarget-Textur gezeichnet, nicht in jedem Frame.
- Zeichenbudget: keine `surface.CreateFont`-Aufrufe zur Laufzeit, keine Panel-Neuerstellung pro Frame, `draw.RoundedBox` statt Masken.
