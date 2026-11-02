"""
LMNT | TTT2 – entpackt Garry's-Mod-Addons (.gma) in einen Ordner.

Der Dedicated Server bindet in garrysmod/addons/ nur Ordner ein, keine losen .gma-Dateien.
Dieses Werkzeug ersetzt gmad.exe (das dem Dedicated Server fehlt).

Aufruf:  python -I tools/gma_extract.py <datei.gma> <zielordner>

Sicherheit: Pfade mit "..", absolute Pfade und Dateien außerhalb der von GMod erlaubten
Ordner werden übersprungen. Die Datei wird nur gelesen, nichts davon ausgeführt.
"""

import struct
import sys
from pathlib import Path, PurePosixPath

ALLOWED_TOP = {
    "maps", "materials", "models", "sound", "lua", "resource", "particles",
    "scenes", "gamemodes", "data_static", "scripts", "shaders",
}


def read_cstr(f):
    out = bytearray()
    while True:
        b = f.read(1)
        if not b or b == b"\x00":
            return out.decode("utf-8", "replace")
        out += b


def extract(gma_path, target_dir):
    target = Path(target_dir).resolve()
    with open(gma_path, "rb") as f:
        if f.read(4) != b"GMAD":
            raise ValueError("keine GMA-Datei (Header fehlt)")
        version = struct.unpack("<B", f.read(1))[0]
        f.read(8)  # SteamID
        f.read(8)  # Zeitstempel
        if version > 1:
            while read_cstr(f):  # benötigte Inhalte (Liste endet mit leerem String)
                pass
        name = read_cstr(f)
        read_cstr(f)  # Beschreibung (JSON)
        read_cstr(f)  # Autor
        f.read(4)     # Addon-Version

        entries = []
        while True:
            num = struct.unpack("<I", f.read(4))[0]
            if num == 0:
                break
            path = read_cstr(f)
            size = struct.unpack("<q", f.read(8))[0]
            f.read(4)  # CRC
            entries.append((path, size))

        written = skipped = 0
        for path, size in entries:
            data = f.read(size)
            rel = PurePosixPath(path.replace("\\", "/").lower())
            if rel.is_absolute() or ".." in rel.parts or not rel.parts or rel.parts[0] not in ALLOWED_TOP:
                skipped += 1
                continue
            out = (target / Path(*rel.parts)).resolve()
            if target not in out.parents:
                skipped += 1
                continue
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(data)
            written += 1

    print(f"{name}: {written} Dateien entpackt, {skipped} uebersprungen")
    return written


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    try:
        sys.exit(0 if extract(sys.argv[1], sys.argv[2]) > 0 else 3)
    except Exception as exc:
        print("Fehler:", exc)
        sys.exit(2)
