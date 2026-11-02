# API: LMNT-HUD für TTT2 (T-150, WP-07)

Addon: `lmnt_ttt` · Realm: Client (Elementdateien laufen auch auf dem Server, siehe unten) · Grundlage: TTT2 0.14.6b · Entscheidung: ADR-004 (TTT2-HUD-System erweitern statt ersetzen)

Das HUD `lmnt` ist ein normales TTT2-HUD. Verschieben, Skalieren, Speichern, Zurücksetzen, Grundfarbe und Element-Einstellungen kommen aus TTT2 (`hud_base`, `scalable_hud`, HUD-Editor). Die LMNT-Elemente übernehmen die Spiellogik der pure_skin-Elemente und ersetzen nur die Darstellung.

## Ladepfade (im TTT2-Quellcode belegt)

`G` = `gamemodes/terrortown/gamemode`, `L` = `lua/ttt2/libraries`

| Was | TTT2-Fundstelle | Wirkung |
|---|---|---|
| HUDs | `G/shared/sh_hud_module.lua:77` `pathBase = "terrortown/gamemode/shared/huds/"`, `file.Find(…, "LUA")` | jeder Unterordner ist ein HUD, ID = Ordnername (`:105-123`, `huds.Register(HUD, folder)`) |
| HUD-Dateien | `sh_hud_module.lua:3-20` | Server: `AddCSLuaFile` für jede Datei. Client: `include` nur `cl_init.lua` |
| abstrakte HUDs | `sh_hud_module.lua:1`, `:108` | `huds/base_huds/` wird übersprungen |
| Elemente | `G/shared/sh_hudelement_module.lua:27` `pathBase = "terrortown/gamemode/shared/hud_elements/"` | jeder Unterordner ist ein **Typ**, jede `.lua` darin ein Element mit ID = Dateiname (`:31-57`) |
| Element-Realm | `sh_hudelement_module.lua:42-46` | `AddCSLuaFile` und `include` auf Server **und** Client, Zeichencode daher hinter `if not CLIENT then return end` |
| abstrakte Elemente | `sh_hudelement_module.lua:2`, `:50` | Dateien in `base_elements/` bekommen keinen Typ |
| Reihenfolge | `G/shared/sh_init.lua:607-611` | Sprachen, dann HUDs, dann Elemente |
| Vererbung | `L/huds.lua:100-138`, `L/hudelements.lua:106-144` | `Base`, fehlende Felder werden vom Basiselement kopiert, `baseclass.Set` in `OnLoaded` |
| Initialisierung | `G/client/cl_main.lua:253-259` | `huds.OnLoaded`, `hudelements.OnLoaded` (ruft `PreInitialize`), `HUDManager.LoadAllHUDS`, `HUDManager.SetHUD()` |

Der Suchpfad `"LUA"` umfasst die `lua/`-Ordner aller Addons und den `gamemodes/`-Ordner. Deshalb findet TTT2 die Dateien unter `lmnt_ttt/lua/terrortown/gamemode/shared/…` im selben virtuellen Ordner wie seine eigenen. Ingame nachweisbar mit `developer 1`: Konsole zeigt `[TTT2][Huds] Registered HUD lmnt` (`sh_hud_module.lua:121`).

## Dateien

```
lmnt_ttt/lua/terrortown/gamemode/shared/
  huds/lmnt/cl_init.lua                              HUD "lmnt" (Base pure_skin)
  hud_elements/base_elements/lmnt_element.lua        abstrakt: Farben, Schriften, Texte, Zeichenhelfer
  hud_elements/tttinfopanel/lmnt_playerinfo.lua
  hud_elements/tttroundinfo/lmnt_roundinfo.lua
  hud_elements/tttteamindicator/lmnt_teamindicator.lua
  hud_elements/tttminiscoreboard/lmnt_miniscoreboard.lua
  hud_elements/lmntweaponinfo/lmnt_weaponinfo.lua    eigener Typ "lmntweaponinfo"
  hud_elements/tttwswitch/lmnt_wswitch.lua
  hud_elements/tttsidebar/lmnt_sidebar.lua
lmnt_ttt/lua/lmnt_ttt/cl_theme.lua                   einmalige Auswahl (Modul ttt.theme)
```

## HUD `lmnt`

- `HUD.Base = "pure_skin"`, `HUD.defaultcolor = Color(8, 7, 12, 235)` (Ink). Die Grundfarbe ist wie bei pure_skin im HUD-Menü änderbar (`scalable_hud`, Speicher-Key `basecolor`). Die LMNT-Elemente wählen die Textfarbe passend dazu (hell auf dunkel, dunkel auf hell).
- `HUD:Initialize` erzwingt die sieben LMNT-Elemente und ruft danach `pure_skin:Initialize`. `ForceElement` belegt einen Typ nur, solange er frei ist (`hud_base/cl_init.lua:34-40`). So kommen die übrigen Typen von pure_skin: Nachrichten (`tttmstack`), Ziel-ID (`ttttarget`), Aufheben (`tttpickup`), Ertrinken, Faustschlag, Wiederbelebung. DNA-Scanner, Ereignis-Popup und Sprachchat wählt `hud_base` automatisch (wie bei pure_skin). Diese Elemente zeichnen auf der Ink-Grundfarbe, behalten aber ihr pure_skin-Layout.
- Alle LMNT-Elemente haben `disabledUnlessForced = true`. Ohne das würde `hud_base:GetElementByType` (`:249-262`) sie als Fallback in anderen HUDs (z. B. old_ttt) verwenden.

## Elemente

| Element (Typ) | Basis | Datenquelle | Sichtbarkeitsregel |
|---|---|---|---|
| `lmnt_playerinfo` (`tttinfopanel`), unten links | `pure_skin_playerinfo` | `client:GetSubRoleData()`, `GetRoleColor()`, `GetTeam()`, `Health()`, `GetMaxHealth()`, `GetArmor()`, `ArmorIsReinforced()`, `GetSprintStamina()`, `GetCredits()`, `GetObserverTarget()` | Rolle, Rollenfarbe und Team nur von sich selbst und nur bei `client:IsActive()`. Zuschauer sehen nur den **Namen** des beobachteten Spielers, nie dessen Rolle. Credits nur bei `IsActive() and IsShopper()`. Rüstung nur mit `ttt_armor_dynamic`, Ausdauer nur mit aktivem Sprint. Tot: nur Kopfzeile |
| `lmnt_roundinfo` (`tttroundinfo`), oben mittig | `pure_skin_roundinfo` | `gameloop.GetRoundState()`, `GetPhaseEnd()`, `IsHasteMode()`, `GetHasteEnd()` | Haste-Logik 1:1 aus pure_skin: Die echte Restzeit sehen nur allwissende Rollen (`isOmniscientRole`) und Nicht-Aktive, rot und im Wechsel. Abschaltbar für Admins (`ttt2_elem_toggled_lmnt_roundinfo`) |
| `lmnt_teamindicator` (`tttteamindicator`), Kind von roundinfo | `pure_skin_teamindicator` | `TEAMS[client:GetTeam()]` | nur eigenes Team und nur lebend im Spiel, sonst Zuschauer-Symbol. Nur `ROUND_ACTIVE`. Abschaltbar |
| `lmnt_miniscoreboard` (`tttminiscoreboard`), Kind von roundinfo | `pure_skin_element` (Logik aus `pure_skin_miniscoreboard`) | `util.GetFilteredPlayers(WasActiveInRound)`, `OnceFound()`, `HasRole()`, `GetRoleColor()`, `RoleKnown()`, `WasRevivedAndConfirmed()` | Rollenfarbe nur bei gefundener Leiche mit bekannter Rolle, sonst „indirekt bestätigt“ (hellgrau) oder neutral. Hook `TTT2ModifyMiniscoreboardColor` bleibt wirksam. Nur `ROUND_ACTIVE`. Abschaltbar |
| `lmnt_weaponinfo` (`lmntweaponinfo`, neu), unten rechts | `lmnt_element` | `client:GetActiveWeapon()`: `GetPrintName`, `Clip1`, `Ammo1`, `Primary.ClipSize` (wie `pure_skin_playerinfo:GetAmmo`) | nur eigene aktive Waffe, nur lebend. Nahkampfwaffen ohne Munition. Im HUD-Editor immer als Platzhalter |
| `lmnt_wswitch` (`tttwswitch`), über weaponinfo | `pure_skin_wswitch` | `WSWITCH.WeaponCache`, `WSWITCH.Selected`, `WSWITCH.Show` | nur eigenes Inventar, nur beim Waffenwechsel (oder im Editor). Farbstreifen = eigene Rollenfarbe, ohne Rolle Zuschauerfarbe |
| `lmnt_sidebar` (`tttsidebar`), links mittig | `pure_skin_sidebar` | `STATUS.active`, `client:GetEquipmentItems()`, `items.GetStored` | nur eigene Status und Ausrüstung. Beschreibung nur bei offenem Scoreboard und `ttt2_hud_enable_description` |

`lmnt_element` (abstrakt, `base_elements/`) stellt zustandslose Helfer bereit: `Colors()`, `TextColors(bg)`, `Font(key)`, `TextScale(key, scale)`, `Text(…)`, `TextSize(…)`, `FitScale(…)`, `Limit(…)`, `Upper(str)` (mit Umlauten), `Rect`, `Outline`, `Panel`, `Accent`, `Bar`. Elemente, die von einem pure_skin-Element erben, holen es über `hudelements.GetStored("lmnt_element")` (gleiches Muster wie `pure_skin_wswitch.drawer`).

### Zusatzinfo von Rollen-Addons
Die Schnittstelle `SetSecondaryRoleInfoFunction(fn)` von `pure_skin_playerinfo` gilt auch hier. Ist am LMNT-Element keine Funktion gesetzt, wird die von `pure_skin_playerinfo` verwendet, weil Rollen-Addons sie meist dort registrieren.

## Design

- Flächen: HUD-Grundfarbe (Ink), 1-px-Rahmen in `line`, roter Akzentbalken (`acid`, 3 px skaliert) oben an Spielerbox, Waffenbox und Rundenleiste. Aktive Zeile im Waffenwechsel: `acid`-Markierung.
- Labels in Großbuchstaben (`LEBEN`, `CREDITS`, `WAFFE`, Rundenstatus). `Upper` setzt auch Umlaute um, was `string.upper` nicht kann.
- Farben aus `LMNT.Config.Colors`, bei fehlendem lmnt_core die Werte aus `05_DESIGNSYSTEM.md`.
- Rollen-, Team- und Zuschauerfarben bleiben die TTT2-Farben (`GetRoleColor`, `GetRoleDkColor`, `TEAMS[…].color`, `COLOR_SPEC`).
- Schriften: `LMNT.Display`, `LMNT.Title`, `LMNT.BodyBold`, `LMNT.Small`, `LMNT.Label` aus `lmnt_core/lua/lmnt/core/cl_ui.lua`. Fehlt lmnt_core, legt `lmnt_element` beim ersten Zeichnen einmalig Roboto-Ersatzschriften (`LMNT.HUD.*`) in 1080p-Größe an.
- Texte: Schlüssel `lmnt_hud_*` (de, en) werden in `lmnt_element.lua` über `LANG.GetLanguageTableReference` ergänzt. TTT2-Texte (Rundenstatus, `hastemode`, `overtime`, Rollen- und Teamnamen) kommen aus TTT2.

## Skalierung und Editor

- Element-Skalierung wie in pure_skin: Spielerbox, Rundenleiste und Waffenbox `min(Breite/Mindestbreite, Höhe/Mindesthöhe)`, Waffenwechsel und Sidebar `appearance.GetGlobalScale()`, Kinder `Höhe Eltern / Standardhöhe Eltern`.
- Text skaliert mit: `TextScale = Elementskalierung / (tatsächliche Schriftgröße / 1080p-Größe)`. Die LMNT-Schriften sind über `LMNT.UI.Scale` schon an die Bildschirmhöhe angepasst. Abweichungen unter 3 % werden nicht per Matrix skaliert (bleibt scharf).
- Editor-Anforderungen (`G/client/cl_hud_editor.lua`, `hud_element_base/cl_init.lua`): Jedes Element hat `GetDefaults` mit `basepos`, `size`, `minsize`. `basepos` wird aus der aktuellen Größe und Skalierung berechnet, weil `scalable_hud:ApplyScale` es nach `SetSize` neu abfragt. Dazu kommen `IsResizable`, `PerformLayout` mit Aufruf der Basis (Kinder folgen dem Elternelement) und `Reset`/`SaveData`/`LoadData` aus `hud_element_base`. Gespeichert wird pro Element-ID (Tabelle `ttt2_hudelements`), Positionen von pure_skin bleiben also unberührt.
- Kinder (`lmnt_teamindicator`, `lmnt_miniscoreboard`) hängen an `lmnt_roundinfo` (`hudelements.RegisterChildRelation` in `PreInitialize`). Ohne diese Kopien würden Teamanzeige und Mini-Scoreboard im HUD lmnt fehlen: Ihre pure_skin-Versionen hängen an `pure_skin_roundinfo`, und `hud_base:CanUseElement` (`:178-206`) verlangt ein nutzbares Elternelement. `lmnt_teamindicator` ruft `BaseClass.PreInitialize` deshalb bewusst nicht auf.
- `ShouldDraw` liefert im Editor `true` (`lmnt_weaponinfo`, `lmnt_wswitch`), sonst ließen sich die Elemente nicht verschieben (`TryMoveLocalHUD` prüft `ShouldDraw`).
- Statisch geprüft (Skript im Session-Scratchpad `check_hud.js`, liest die TTT2-Quelle und die LMNT-Dateien mit luaparse): Vererbungsketten auflösbar, alle Editor-Methoden vorhanden, Defaults vollständig, alle erzwungenen IDs existieren mit eindeutigem Typ, Elternelement erzwungen, kein geerbtes `PreInitialize` mit fremdem Elternteil, kein pure_skin-Kindtyp geht verloren. Ergebnis: 0 Fehler.

## Erstauswahl (`cl_theme.lua`, Modul `ttt.theme`)

- TTT2 speichert die Wahl in der Client-ConVar `ttt2_current_hud` (`G/client/cl_hud_manager.lua:6`, `FCVAR_ARCHIVE`). Gewechselt wird über `HUDManager.SetHUD(name)` (`:193`). Der Server prüft Sperren und ein erzwungenes HUD (`G/server/sv_hud_manager.lua:146-193`) und bestätigt mit `TTT2ReceiveHUD`, danach läuft `TTT2HUDUpdated(name)` (`cl_hud_manager.lua:170`).
- Hook `PostInitPostEntity`: läuft in `GM:InitPostEntity` nach dem Standard-Request (`cl_main.lua:259` vor `:293`), die LMNT-Anfrage wird also zuletzt bestätigt. Ist `ttt2_current_hud` schon `lmnt`, wird nur markiert.
- Cookie `lmnt_hud_applied` wird erst gesetzt, wenn `TTT2HUDUpdated("lmnt")` kommt. Wählt der Spieler danach ein anderes HUD, bleibt es dabei. Hat ein Admin `lmnt` gesperrt oder ein anderes HUD erzwungen, entscheidet der Server, und der Versuch wird beim nächsten Besuch wiederholt (eine Netzwerknachricht).
- Admins können `lmnt` auch serverweit als Standard setzen (F1 → Administration → HUD, `TTT2DefaultHUDRequest`).

## Aktualisierungsstrategie

- Keine eigenen Netzwerknachrichten, Hooks oder Timer im HUD. Alle Daten sind clientseitig vorhanden (Spielerfelder, `gameloop`, `WSWITCH`, `STATUS`).
- Gezeichnet wird in `HUDPaint` über `HUDManager.DrawHUD` (`cl_hud_manager.lua:56-58`). Layoutwerte entstehen in `Initialize`/`PerformLayout`, nicht pro Frame.
- Keine `surface.CreateFont`-Aufrufe zur Laufzeit (Ersatzschriften einmalig), keine Panels.
- Pro Frame vermieden: neue `Color()` (Rollenfarben im Mini-Scoreboard und Spektatorfarbe zwischengespeichert, Pulsieren über Alpha-Parameter), neue Tabellen im Waffenwechsel (Zeilen wiederverwendet), Neuberechnung des gekürzten Waffennamens (nur bei Wechsel von Waffe, Breite oder Skalierung), Großschreibung (Cache).
- Mini-Scoreboard: Spielerliste alle 0,1 s geprüft, sortiert nur bei geänderter Anzahl oder bei ttt2net-Änderungen an Fundstatus (wie pure_skin, Callback nur einmal registriert).

## Bekannte Grenzen

- Nur ingame mit Client prüfbar: Aussehen, Schriftgrößen und Abstände, Lesbarkeit über hellen Karten, Verhalten im Editor, Erstauswahl. Ein Gameserver wurde in T-150 nicht gestartet.
- Nachrichten, Ziel-ID, Aufheben, Ertrinken, Faustschlag, Wiederbelebung, DNA-Scanner, Ereignis-Popup und Sprachchat sind pure_skin-Elemente auf Ink-Grund, nicht im LMNT-Stil umgezeichnet. Auch das Rollen-Popup zu Rundenbeginn nutzt `pure_skin.PopupPaint`.
- Die pure_skin-Elemente teilen Position und Größe zwischen den HUDs pure_skin und lmnt (TTT2 speichert pro Element-ID).
- `lmntweaponinfo` ist ein neuer Typ. Andere Addons, die über `HUDShouldDraw` Typen ausblenden, kennen ihn nicht.
- Die Munitionsleiste steht nicht mehr in der Spielerbox, sondern in `lmnt_weaponinfo`. Wer sie ausblenden will, muss das Element im Editor verschieben (nicht abschaltbar, da TTT2 nur `togglable`-Elemente serverseitig schaltet).
- Matrix-skalierter Text (Elementskalierung deutlich ≠ 1) ist leicht weicher als nativ gerenderter, wie bei pure_skin.
- `string.upper`-Ersatz deckt nur UTF-8 U+00E0–U+00FE ab (deutsche Umlaute, é usw.), nicht `ß`.
- Die Beschreibung des Moduls `ttt.theme` in `lmnt_ttt_init.lua` nennt nur den Skin (Datei gehört einer anderen Session).

## Ingame-Prüfliste (Haupt-Session)

1. `developer 1`, Map laden: `[TTT2][Huds] Registered HUD lmnt`. Keine Lua-Fehler zu `lmnt_*`.
2. Neuer Client (Cookie leer): nach dem Join ist `ttt2_current_hud` = `lmnt`. Auf `pure_skin` wechseln, neu verbinden: bleibt `pure_skin`.
3. F1 → Aussehen → HUD: Editor öffnen, alle LMNT-Elemente verschieben, Spielerbox, Rundenleiste und Waffenbox skalieren, Rechtsklick → Zurücksetzen, Grundfarbe ändern.
4. Runde als Innocent, Traitor (Credits sichtbar), Detective, mit Haste-Modus: Timer, Rollenfarbe, Credits nur bei Shop-Rolle. Als Zuschauer: nur Name des Beobachteten, keine Rolle.
5. Mini-Scoreboard: Leiche finden → Rollenfarbe erscheint erst dann. Waffenwechsel und Status-Icons (z. B. Rüstung, Items).
6. Ohne lmnt_core (nur zur Probe): Ersatzschriften, keine Fehler.
