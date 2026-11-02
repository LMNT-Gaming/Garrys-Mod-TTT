# Workshop-Collection, Downloads und FastDL

## Prinzip: eine Liste für alles

`garrysmod/data/lmnt/workshop.json` ist die einzige Liste, die du pflegst:

| Wer nutzt sie | Wofür |
|---|---|
| Gameserver (`sv_resources.lua`) | `resource.AddWorkshop`: Clients laden **TTT2 und nur die aktuelle Map**, nicht alle Maps |
| `tools/workshop.ps1` | prüft jede ID über die Steam-API, vergleicht sie mit deiner Collection und erzeugt `cfg/mapcycle.txt` |

Aktueller Inhalt (alle IDs per Steam-API geprüft, zusammen 91 MB):

| ID | Inhalt |
|---|---|
| 1357204556 | TTT2 (Base) |
| 159321088 | ttt_minecraft_b5 |
| 253328815 | ttt_skyscraper |
| 157420728 | ttt_waterworld |
| 183797802 | ttt_island_2013 |
| 131667838 | ttt_community_bowling |

Eigene Addons (lmnt_core, lmnt_ttt) gehören **nicht** in den Workshop. Ihr Lua-Code wird automatisch übertragen, ihre Sounds und Materialien kommen per FastDL.

## Collection anlegen (einmalig, im Steam-Client oder Browser)

1. Öffne den Steam-Workshop von Garry's Mod und wähle **Kollektionen → Kollektion erstellen**.
2. Gib einen Namen ein, z. B. „LMNT TTT2 Server“, und setze die Sichtbarkeit auf **Öffentlich** (sonst kann der Server sie nicht laden).
3. Füge alle Items aus der Tabelle oben hinzu. `tools\workshop.ps1` gibt dir die Links aus.
4. Trage die Zahl aus der Collection-URL (`...?id=XXXXXXXX`) in `server\settings.ini` unter `COLLECTION_ID=` ein.
5. Hole einen **Web-API-Key** unter https://steamcommunity.com/dev/apikey und trage ihn als `STEAM_AUTHKEY=` ein.
6. Hole einen **Game Server Login Token** (App-ID **4000**) unter https://steamcommunity.com/dev/managegameservers und trage ihn als `GSLT=` ein.
7. Prüfe alles: `tools\workshop.ps1` meldet fehlende oder überzählige Items.

**Neue Map hinzufügen:** Trage die Map in `workshop.json` unter `maps` ein (ID, Name und BSP-Name ohne `.bsp`), füge sie zur Collection hinzu, dann `tools\workshop.ps1` und `server\deploy.ps1` ausführen.
Den genauen BSP-Namen zeigt die Serverkonsole mit `maps ttt_` an, sobald die Collection geladen ist.

## CS:S-Texturen

Fast alle TTT-Maps nutzen Texturen aus Counter-Strike: Source. `install.ps1` installiert deshalb kostenlos den CS:S Dedicated Server (App 232330) und bindet ihn über `cfg/mount.cfg` ein. Spieler ohne CS:S sehen auf manchen Maps trotzdem Fehlertexturen. Das betrifft jeden TTT-Server und lässt sich nur mit Content-Packs aus dem Workshop beheben. Bei Bedarf ergänzen wir eines.

## FastDL

FastDL liefert eigene Dateien über HTTP statt über den langsamen Gameserver-Download aus.

```
tools\build_fastdl.ps1   → sammelt materials/models/sound/resource/maps aus allen Addons nach fastdl\www\
                           und packt jede Datei zusätzlich als .bz2 (7-Zip)
tools\serve_fastdl.bat   → startet einen Webserver auf FASTDL_PORT (Python, für Tests und kleine Server)
```

In `server.cfg` setzt `deploy.ps1` automatisch `sv_downloadurl` auf `FASTDL_URL`. `sv_allowdownload 0` sorgt dafür, dass Clients nur über FastDL laden.

**Für den Dauerbetrieb** empfiehlt sich ein richtiger Webserver, z. B. Caddy (eine Datei, kein Setup):

```bash
caddy file-server --root "fastdl\www" --listen :8080
```

**Wichtig:** `FASTDL_URL` muss für **Spieler** erreichbar sein, also deine öffentliche IP oder Domain, nicht `127.0.0.1` (das funktioniert nur für Tests am eigenen PC).

## Ladebildschirm

`fastdl/loading/index.html` wird mit nach `www/loading/` gebaut und über `sv_loadingurl` angezeigt. Er zeigt Servername, Map, Download-Fortschritt und wechselnde Tipps.

## Ports und Firewall

| Port | Protokoll | Zweck |
|---|---|---|
| 27015 | UDP | Spiel |
| 27015 | TCP | RCON |
| 8080 | TCP | FastDL und Ladebildschirm |

`tools\firewall.ps1` (als Administrator ausführen) legt die Windows-Regeln an. Im Router musst du diese Ports zusätzlich auf den Server-PC weiterleiten.
