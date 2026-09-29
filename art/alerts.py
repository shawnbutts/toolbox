#!/usr/bin/env python3
"""Generate Toolbox's alert sounds.

    python3 art/alerts.py                    # every alert
    python3 art/alerts.py debuff_landed      # just one

Each alert is written as toolbox/<name>.ogg, shipped in the package (API 15 allows sounds), with
an intermediate art/<name>.wav (git-ignored).
Standard library for the synthesis; ffmpeg (built-in Vorbis encoder) for the .ogg.

Alerts:
  buff_expiring   two soft bell chimes falling a fourth (A5 -> E5), 0.9 s: "winding down"
  debuff_landed   three hollow notes stepping down from high to low (E6 -> B5 -> E5), each bending
                  down as it sounds, 0.8 s: a falling "uh-oh" that starts high
  notify          two soft bell chimes rising a fifth (E5 -> B5), 0.8 s: "something new" (the
                  opposite way to buff_expiring's fall)
Tweak the constants in each render_* function and re-run.
"""

from __future__ import annotations

import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

RATE = 44100
PEAK = 10 ** (-3 / 20)   # -3 dBFS
HERE = Path(__file__).resolve().parent


# ---------------------------------------------------------------------------
# Shared building blocks
# ---------------------------------------------------------------------------

def attack(t: float, seconds: float) -> float:
    """Linear fade-in; long enough to avoid a click."""
    return min(1.0, t / seconds)


def add_echoes(dry: list[float], echoes: list[tuple[float, float]]) -> list[float]:
    """(delay s, gain) copies of the dry signal: a little space, not a reverb wash."""
    out = dry[:]
    for delay, gain in echoes:
        k = int(delay * RATE)
        for i in range(k, len(dry)):
            out[i] += gain * dry[i - k]
    return out


def fade_out(samples: list[float], seconds: float) -> list[float]:
    n, fade = len(samples), int(seconds * RATE)
    for i in range(n - fade, n):
        samples[i] *= (n - i) / fade
    return samples


def normalize(samples: list[float]) -> list[float]:
    peak = max(abs(x) for x in samples) or 1.0
    return [x * PEAK / peak for x in samples]


# ---------------------------------------------------------------------------
# buff_expiring: two soft bell chimes, falling
# ---------------------------------------------------------------------------

def render_chimes(duration: float, notes: list[tuple[float, float, float]]) -> list[float]:
    """Soft bell chimes: notes = (start s, Hz, loudness)."""
    # Bell partials: (ratio, amplitude, decay 1/s). Higher partials are slightly inharmonic
    # and die away faster, which is what makes it sound like a chime.
    partials = [(1.0, 1.00, 5.0), (2.0, 0.35, 8.0), (2.76, 0.22, 11.0), (5.4, 0.08, 18.0)]

    def chime(t: float, freq: float) -> float:
        if t < 0:
            return 0.0
        return attack(t, 0.006) * sum(
            a * math.exp(-d * t) * math.sin(2 * math.pi * freq * r * t) for r, a, d in partials)

    n = int(RATE * duration)
    dry = [sum(loud * chime(i / RATE - start, f) for start, f, loud in notes) for i in range(n)]
    out = add_echoes(dry, [(0.075, 0.22), (0.15, 0.10)])
    return normalize(fade_out(out, 0.08))


def render_buff_expiring() -> list[float]:
    return render_chimes(0.9, [(0.00, 880.00, 1.0), (0.17, 659.25, 0.9)])   # A5 then E5: falling


def render_notify() -> list[float]:
    return render_chimes(0.8, [(0.00, 659.25, 0.85), (0.14, 987.77, 1.0)])   # E5 then B5: rising


# ---------------------------------------------------------------------------
# debuff_landed: three hollow notes stepping down, high to low
# ---------------------------------------------------------------------------

# Starts high and falls (owner, 2026-09-28: "a little longer, higher to lower"): E6 -> B5 -> E5,
# each note bending down a step while it sounds, cut off when the next starts; the last one
# rings out. No thump (it would start the sound low) and no echo. Was: A4 -> F4 -> D4 over a
# low thump, 0.38 s.
DEBUFF = dict(
    duration=0.8,
    notes=[(0.00, 1318.51, 1174.66, 0.85),        # (start s, from Hz, to Hz, loudness): E6 -> D6
           (0.16, 987.77, 880.00, 0.95),          # B5 -> A5
           (0.32, 659.26, 523.25, 1.0)],          # E5 -> C5
    glide=0.18,                                   # seconds each note takes to bend down
    decay=5.0,                                    # 1/s: slower than before, so it carries
    harmonics=[(1, 1.0), (3, 0.30), (5, 0.10)],   # odd harmonics: hollow, not a bell
    thump=(110.0, 60.0, 0.09, 24.0, 0.0),         # (from Hz, to Hz, glide s, decay 1/s, level): off
    echoes=[],
    fade=0.12,
    choke=0.02,           # each note fades out over this many seconds as the next one starts
)


def render_debuff(p: dict) -> list[float]:
    def glide_phase(t: float, f0: float, f1: float, span: float) -> float:
        """Phase (cycles) of an exponential glide f0 -> f1 over `span` seconds, then steady at f1."""
        k = math.log(f1 / f0) / span
        if t < span:
            return f0 * (math.exp(k * t) - 1) / k
        return f0 * (math.exp(k * span) - 1) / k + f1 * (t - span)

    starts = [note[0] for note in p["notes"]]

    def choke(t_abs: float, start: float) -> float:
        """1, or a short fade once the next note starts (so notes don't ring into each other)."""
        if not p.get("choke"):
            return 1.0
        later = [s for s in starts if s > start]
        if not later or t_abs < later[0]:
            return 1.0
        return max(0.0, 1.0 - (t_abs - later[0]) / p["choke"])

    def bent_note(t: float, f0: float, f1: float, start: float = 0.0) -> float:
        if t < 0:
            return 0.0
        phase = glide_phase(t, f0, f1, p["glide"])
        env = attack(t, 0.004) * math.exp(-p["decay"] * t) * choke(start + t, start)
        return env * sum(a * math.sin(2 * math.pi * h * phase) for h, a in p["harmonics"])

    def thump(t: float) -> float:
        f0, f1, span, decay, level = p["thump"]
        return level * attack(t, 0.003) * math.exp(-decay * t) * math.sin(2 * math.pi * glide_phase(t, f0, f1, span))

    n = int(RATE * p["duration"])
    dry = [thump(i / RATE) + sum(loud * bent_note(i / RATE - s, f0, f1, s) for s, f0, f1, loud in p["notes"])
           for i in range(n)]
    out = add_echoes(dry, p["echoes"])
    return normalize(fade_out(out, p["fade"]))


# ---------------------------------------------------------------------------

ALERTS = {
    "buff_expiring": render_buff_expiring,
    "debuff_landed": lambda: render_debuff(DEBUFF),
    "notify": render_notify,
}


def write(name: str, samples: list[float]) -> None:
    wav, ogg = HERE / f"{name}.wav", HERE.parent / "toolbox" / f"{name}.ogg"
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
    print(f"wrote {ogg.name}")


def main(names: list[str]) -> int:
    unknown = [n for n in names if n not in ALERTS]
    if unknown:
        print(f"unknown alert(s): {', '.join(unknown)}; known: {', '.join(ALERTS)}")
        return 1
    for name in names or list(ALERTS):
        write(name, ALERTS[name]())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
