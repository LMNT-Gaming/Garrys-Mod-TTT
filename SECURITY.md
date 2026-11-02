# Sicherheitsmeldungen

Bitte melde Sicherheitslücken **nicht** in öffentlichen Issues, sondern vertraulich über
[GitHub Security Advisories](https://github.com/LMNT-Gaming/Garrys-Mod-TTT/security/advisories/new).

Relevant sind vor allem:

- Netzwerk-Nachrichten, mit denen Clients Rechte, Punkte, Shop-Käufe oder Admin-Aktionen erschleichen können
- Umgehung des Rangsystems (`LMNT.Perms`, Immunität, Owner-Bootstrap)
- Lecks von Rolleninformationen an Clients (HUD, Scoreboard, Net-Nachrichten)
- Geheimnisse, die in Logs, Settings oder an Clients gelangen (`data/lmnt/secrets.json`)

## Geheimnisse

Passwörter, Tokens und Webhooks gehören ausschließlich in

- `server/settings.ini` (lokal, per `.gitignore` ausgeschlossen – Vorlage: `server/settings.example.ini`)
- `garrysmod/data/lmnt/secrets.json` auf dem Server (Vorlage: `secrets.example.json`)

Logs, Issues und Pull Requests dürfen keine RCON-Passwörter, GSLTs, Steam-API-Keys, Webhook-URLs oder IP-Adressen enthalten.
