"""
LMNT | TTT2 – minimaler Source-RCON-Client (Valve RCON-Protokoll über TCP)

Aufruf:  python tools/rcon.py "status"
         python tools/rcon.py "lmnt who" "bot"
Host, Port und Passwort kommen aus server/settings.ini (RCON_HOST optional, Standard 127.0.0.1).
"""

import socket
import struct
import sys
from pathlib import Path

SERVERDATA_AUTH = 3
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0


def read_settings():
    settings = {}
    path = Path(__file__).resolve().parent.parent / "server" / "settings.ini"
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith(";") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        settings[key.strip()] = value.strip()
    return settings


def packet(req_id, kind, body):
    payload = struct.pack("<ii", req_id, kind) + body.encode("utf-8") + b"\x00\x00"
    return struct.pack("<i", len(payload)) + payload


def recv_packet(sock):
    raw = b""
    while len(raw) < 4:
        chunk = sock.recv(4 - len(raw))
        if not chunk:
            raise ConnectionError("Verbindung geschlossen")
        raw += chunk
    size = struct.unpack("<i", raw)[0]
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ConnectionError("Verbindung geschlossen")
        data += chunk
    req_id, kind = struct.unpack("<ii", data[:8])
    body = data[8:-2]
    # Die Serverkonsole gibt Text in der Windows-Codepage aus, nicht in UTF-8
    try:
        return req_id, kind, body.decode("utf-8")
    except UnicodeDecodeError:
        return req_id, kind, body.decode("cp1252", "replace")


def run_one(cmd, host, port, password, timeout):
    """Der GMod-Server schließt die RCON-Verbindung nach jeder Antwort – daher eine Verbindung pro Befehl.
    Die Antwort gilt als vollständig, wenn der Server schließt oder 0,4 s lang nichts mehr sendet."""
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.sendall(packet(1, SERVERDATA_AUTH, password))
        while True:
            req_id, kind, _ = recv_packet(sock)
            if kind == 2:  # SERVERDATA_AUTH_RESPONSE
                if req_id == -1:
                    raise PermissionError("RCON-Passwort falsch")
                break

        # Engine-Fehler (GMod 2026.04.29, Version 10175): Befehle mit genau 12 Byte werden kommentarlos
        # verworfen (alle Längen 1–40 getestet, nur 12 betroffen). Ein Leerzeichen ist für die Konsole bedeutungslos.
        if len(cmd.encode("utf-8")) == 12:
            cmd += " "
        sock.sendall(packet(10, SERVERDATA_EXECCOMMAND, cmd))
        out = []
        try:
            while True:
                req_id, kind, body = recv_packet(sock)
                if req_id == 10 and kind == SERVERDATA_RESPONSE_VALUE:
                    out.append(body)
                    sock.settimeout(0.4)
        except (socket.timeout, ConnectionError):
            pass
        return "".join(out)


def run(commands, host, port, password, timeout=5.0):
    return [run_one(cmd, host, port, password, timeout) for cmd in commands]


if __name__ == "__main__":
    # Windows-Konsolen (cp1252) können Zeichen wie ✓ nicht darstellen – ersetzen statt abstürzen
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    s = read_settings()
    try:
        for cmd, out in zip(sys.argv[1:], run(sys.argv[1:], s.get("RCON_HOST", "127.0.0.1"), int(s.get("PORT", "27015")), s["RCON_PASSWORD"])):
            print("> " + cmd)
            print(out.rstrip())
    except Exception as exc:
        print("RCON-Fehler:", exc)
        sys.exit(2)
