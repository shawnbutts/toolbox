#!/usr/bin/env python3
"""Generate the "a buff is about to run out" alert: two soft bell chimes, falling.

    python3 art/buff_expiring.py            # writes art/buff_expiring.wav and art/buff_expiring.ogg

Standard library for the synthesis; ffmpeg (built-in Vorbis encoder) for the .ogg.
Tweak NOTES, DURATION or PARTIALS below and re-run.
"""

from __future__ import annotations

import math
import struct
import subprocess
import wave
from pathlib import Path

RATE = 44100
DURATION = 0.9           # seconds, including the tail
PEAK = 10 ** (-3 / 20)   # -3 dBFS

# (start time s, frequency Hz, loudness) - a falling fourth, A5 then E5.
NOTES = [(0.00, 880.00, 1.0), (0.17, 659.25, 0.9)]

# Bell partials: (frequency ratio, amplitude, decay rate 1/s). Higher partials are
# slightly inharmonic and die away faster, which is what makes it sound like a chime.
PARTIALS = [(1.0, 1.00, 5.0), (2.0, 0.35, 8.0), (2.76, 0.22, 11.0), (5.4, 0.08, 18.0)]

ATTACK = 0.006           # seconds; long enough to avoid a click
ECHOES = [(0.075, 0.22), (0.15, 0.10)]   # (delay s, gain): a little space, not a reverb wash
FADE_OUT = 0.08          # seconds at the very end


def chime(t: float, freq: float) -> float:
    if t < 0:
        return 0.0
    attack = min(1.0, t / ATTACK)
    return attack * sum(a * math.exp(-d * t) * math.sin(2 * math.pi * freq * r * t) for r, a, d in PARTIALS)


def render() -> list[float]:
    n = int(RATE * DURATION)
    dry = [sum(loud * chime(i / RATE - start, f) for start, f, loud in NOTES) for i in range(n)]
    out = dry[:]
    for delay, gain in ECHOES:
        k = int(delay * RATE)
        for i in range(k, n):
            out[i] += gain * dry[i - k]
    fade = int(FADE_OUT * RATE)
    for i in range(n - fade, n):
        out[i] *= (n - i) / fade
    peak = max(abs(x) for x in out) or 1.0
    return [x * PEAK / peak for x in out]


def main() -> None:
    here = Path(__file__).resolve().parent
    wav, ogg = here / "buff_expiring.wav", here / "buff_expiring.ogg"
    samples = render()
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
         "-af", "pan=stereo|c0=c0|c1=c0",   # the Vorbis encoder needs stereo; copy, don't -3 dB upmix
         "-c:a", "vorbis", "-strict", "-2", "-q:a", "6", str(ogg)],
        check=True,
    )
    print(f"wrote {wav.name} and {ogg.name}")


if __name__ == "__main__":
    main()
