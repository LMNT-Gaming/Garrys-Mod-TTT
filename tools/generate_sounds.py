"""
LMNT | TTT2 – erzeugt die eigenen Sounds synthetisch (keine fremden Rechte nötig).

Ausgabe: garrysmod/addons/lmnt_core/sound/lmnt/*.wav  (44,1 kHz, 16 Bit, Mono – Source-kompatibel)
Aufruf:  python tools/generate_sounds.py
"""

import math
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "garrysmod" / "addons" / "lmnt_core" / "sound" / "lmnt"


def tone(freq, length, volume=0.5, shape="sine", attack=0.01, release=0.08, vibrato=0.0):
    samples = []
    total = int(RATE * length)
    for i in range(total):
        t = i / RATE
        f = freq * (1 + vibrato * math.sin(2 * math.pi * 6 * t))
        phase = 2 * math.pi * f * t
        if shape == "square":
            v = 1.0 if math.sin(phase) >= 0 else -1.0
            v *= 0.45
        elif shape == "saw":
            v = 2 * ((f * t) % 1) - 1
            v *= 0.5
        else:
            v = math.sin(phase) + 0.25 * math.sin(2 * phase)
        env = min(1.0, t / attack) if attack > 0 else 1.0
        tail = (length - t)
        if tail < release:
            env *= max(0.0, tail / release)
        samples.append(v * env * volume)
    return samples


def silence(length):
    return [0.0] * int(RATE * length)


def mix(*tracks):
    size = max(len(t) for t in tracks)
    out = [0.0] * size
    for track in tracks:
        for i, v in enumerate(track):
            out[i] += v
    return out


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.9 / peak if peak > 0.9 else 1.0
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    print("  geschrieben:", OUT / name)


def levelup():
    # Aufsteigendes Arpeggio C-E-G-C mit Schimmer
    notes = [523.25, 659.25, 783.99, 1046.5]
    out = []
    for n in notes:
        out += tone(n, 0.11, 0.45, attack=0.005, release=0.05)
    out += mix(tone(1046.5, 0.5, 0.4, release=0.4), tone(1318.5, 0.5, 0.2, release=0.4))
    return out


def special():
    # Zweimaliges Signal + tiefer Akzent
    out = []
    for _ in range(2):
        out += mix(tone(880, 0.14, 0.35, "square"), tone(440, 0.14, 0.25))
        out += silence(0.05)
    out += mix(tone(330, 0.6, 0.5, "saw", release=0.5), tone(495, 0.6, 0.25, release=0.5))
    return out


def narr_win():
    # Schräge "Tröte": absteigend mit Vibrato
    out = []
    for n in [392, 370, 349.2, 329.6]:
        out += tone(n, 0.22, 0.5, "saw", vibrato=0.02, release=0.04)
    out += tone(293.7, 0.7, 0.5, "saw", vibrato=0.04, release=0.5)
    return out


if __name__ == "__main__":
    write("levelup.wav", levelup())
    write("special.wav", special())
    write("narr_win.wav", narr_win())
