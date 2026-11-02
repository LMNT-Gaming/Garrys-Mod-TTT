# LMNT Admin-System

Komplett eigenes Admin-System, ohne ULX. Ränge werden in `sv.db` (Tabelle `lmnt_users`) gespeichert und als GMod-Usergroup gesetzt. Dadurch erkennen TTT2 und andere Addons Admins über `IsAdmin()` und `IsSuperAdmin()`. Wenn ein Addon CAMI mitbringt, werden die Ränge dort ebenfalls registriert.

## Ränge

| Rang | Level | Bann max. | Wichtigste Rechte |
|---|---|---|---|
| Spieler (`user`) | 0 | – | !regeln, !stats, !top, !shop, !pm, @Meldung |
| VIP (`vip`) | 10 | – | ×1,5 XP und Punkte, VIP-Items im Shop |
| Supporter (`supporter`) | 30 | 1 Std | Menü, kick, slay, slaynr, mute/gag, warn, freeze, goto/bring, Logs, Team-Chat |
| Moderator (`moderator`) | 50 | 7 Tage | + noclip, hp, god, respawn, announce, roundrestart |
| Admin (`admin`) | 80 | permanent | + banid, unban, setrank, map, credits, karma, Spezialrunden, Punkte |
| Superadmin / Owner | 90 / 100 | permanent | alles (`*`) |

- **Immunität:** Du kannst nur Spieler mit *niedrigerem* Level anvisieren. Dich selbst kannst du immer anvisieren.
- **Ränge vergeben:** Du kannst nur Ränge *unterhalb* deines eigenen vergeben.
- **Erster Owner:** Trage deine SteamID64 in `server\settings.ini` unter `OWNERS=` ein (mehrere komma-getrennt) und führe `server\deploy.ps1` aus – das schreibt `data/lmnt/owners.txt`. Alternativ in der Serverkonsole `lmnt setrankid 7656119... owner`. `C.Owners` in `sh_config.lua` funktioniert weiterhin.
- Anpassen kannst du alles in `lmnt_core/lua/lmnt/admin/sh_ranks.lua`.

## Befehle eingeben

| Weg | Beispiel |
|---|---|
| Chat (sichtbar ausgeblendet) | `!kick Max Spammt` oder `/kick Max Spammt` |
| Konsole (Spieler oder Server) | `lmnt kick Max Spammt` |
| Admin-Menü | `!menu`, oder eine Taste binden: `bind F6 lmnt_menu` |
| Team-Chat / Meldung | `@Hilfe, RDM in der Halle!` (Spieler → Meldung an das Team, Team → Team-Chat) |

**Spieler angeben:** Teil des Namens · `^` dich selbst · `*` alle · `@` den Spieler, den du ansiehst · `#12` per UserID · `STEAM_0:1:…` oder `7656…`
**Zeiten:** `30m`, `2h`, `1d`, `1w`, `1d12h` · `0` bedeutet permanent
**Namen mit Leerzeichen:** in Anführungszeichen, z. B. `!ban "Max Mustermann" 1d Grund`

## Alle Befehle

| Befehl | Recht | Beschreibung |
|---|---|---|
| `!hilfe` | – | listet alle Befehle, die du nutzen darfst, in der Konsole |
| `!regeln`, `!discord` | – | Regeln und Discord-Link |
| `!pm <spieler> <text>` | – | private Nachricht |
| `!stats [spieler]`, `!top [level\|kills\|wins\|points\|playtime]` | – | Statistik und Bestenliste |
| `!shop` / F4 | – | Pointshop |
| `!menu` | menu | Admin-Menü |
| `!who` | who | Spielerliste mit Rang, SteamID und UserID |
| `!kick <spieler> [grund]` | kick | Kick |
| `!ban <spieler> <zeit> [grund]` | ban | Bann (begrenzt durch maxBan des Rangs) |
| `!banid <steamid> <zeit> [grund]` | banid | Offline-Bann |
| `!unban <steamid>` | unban | Bann aufheben |
| `!warn <spieler> <grund>` / `!warns` / `!clearwarns` | warn / clearwarns | Verwarnungen: Kick ab 3, 1-Tages-Bann ab 5 |
| `!mute` / `!unmute`, `!gag` / `!ungag` | mute / gag | Chat- bzw. Voice-Sperre |
| `!slay`, `!slaynr <spieler> [runden] [grund]`, `!unslaynr` | slay / slaynr | Slay sofort oder in den nächsten Runden (bleibt über Reconnects gespeichert) |
| `!freeze` / `!unfreeze` | freeze | Einfrieren |
| `!goto`, `!bring`, `!return` | goto / bring / return | Teleport und Rückkehr |
| `!noclip [spieler]`, `!god [spieler]`, `!hp <spieler> <hp>` | noclip / god / hp | Moderation |
| `!respawn <spieler>` | respawn | wiederbeleben (TTT) |
| `!announce <text>` | announce | große Einblendung bei allen |
| `!roundrestart`, `!cleardecals` | roundrestart / cleardecals | Runde neu starten, Decals entfernen |
| `!setrank <spieler> <rang>`, `!setrankid <steamid> <rang>` | setrank | Rang vergeben |
| `!map <map>` | map | Mapwechsel |
| `!credits <spieler> <n>`, `!karma <spieler> <wert>`, `!points <spieler> <n>` | credits / karma / points | TTT-Werte setzen |
| `!special [id]` | special | Spezialrunde für die nächste Runde festlegen, ohne ID: Liste |
| `!logs [anzahl] [kategorie]` | logs | Logs in der Konsole |

## Admin-Menü (`!menu`)

- **Spieler:** Spieler auswählen und Aktion anklicken. Weitere Angaben wie Grund oder Zeit werden nacheinander abgefragt.
- **Befehle:** freie Befehlszeile plus Übersicht. Ein Doppelklick führt den Befehl geführt aus.
- **Banns:** alle aktiven Banns, Entbannen per Knopf.
- **Logs:** Filter nach Kategorie (admin, ban, chat, connect, kill, asay, pm, round, shop) und Volltextsuche.

## Umstieg von ULX (einmalige Migration)

Das LMNT-Admin-System ist das **führende und einzige Rechtesystem** des Servers (Entscheidung vom 17.10.2026, ADR-011). Wer von ULX umsteigt:

1. LMNT und ULX zusammen laden. `!conflicts` meldet den Doppelbetrieb.
2. `!ulximport` startet einen **Probelauf**. Er zeigt, welche Ränge und Banns übernommen würden, mit Details in der Konsole.
3. `!ulximport ausfuehren` übernimmt alles in einer Transaktion. Jede Änderung landet im Log (Kategorie `migration`).
4. ULX entfernen.

Zuordnung der Gruppen (anpassbar über `LMNT.Config.ULXGroupMap`): `superadmin → superadmin`, `admin → admin`, `operator → moderator`, `user → user`. Unbekannte Gruppen und IP-Einträge werden übersprungen, ebenso abgelaufene oder bereits vorhandene Banns. Es wird **nie herabgestuft** und **nie Owner** vergeben. Ein zweiter Lauf hat keine Wirkung. Recht: `dev`.

## Logs

Alles landet doppelt: in der Datenbank (für das Menü, Standard 30 Tage) und in `garrysmod/data/lmnt/logs/JJJJ-MM-TT.txt`.
