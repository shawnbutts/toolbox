#!/usr/bin/env python3
"""Generate toolbox/launcher.png: the launcher strip's button pictures, as an eight-frame sprite.

    python3 art/launcher.py

Frames, left to right (hud.lua's LN.BUTTONS uses the same order): settings (a gear), docs (an open book), XP (a
star), XP Detailed (a star over a bar chart), Today (a sun), Loot Tracker (a bag), Combat Detailed (crossed
swords), Notifications (a bell). White line art with a dark edge, so the game's tint (@gold) colours it and it
reads on any skin. Each frame is FRAME px square, drawn on a 64-unit grid. Writes art/launcher.svg and renders it
with rsvg-convert, as art/marks.py does.
"""

from __future__ import annotations

import math
import subprocess
from pathlib import Path

FRAME = 96                # px per frame: sharp up to the largest button (64 px)
EDGE = "#1a1a1a"          # the dark edge
EDGE_W, LINE_W = 9, 5     # stroke widths on the 64-unit grid


def rays(r0: float, r1: float, turn: float = 0.0) -> str:
    out = []
    for i in range(8):
        a = i * math.pi / 4 + turn
        c, s = math.cos(a), math.sin(a)
        out.append(f'<line x1="{32 + r0 * c:.1f}" y1="{32 + r0 * s:.1f}" x2="{32 + r1 * c:.1f}" '
                   f'y2="{32 + r1 * s:.1f}"/>')
    return "".join(out)


def gear() -> str:
    pts = []
    for i in range(8):
        a = i * 2 * math.pi / 8
        for da, r in ((-0.30, 17), (-0.20, 24), (0.20, 24), (0.30, 17)):
            pts.append(f"{32 + r * math.cos(a + da):.1f},{32 + r * math.sin(a + da):.1f}")
    return f'<polygon points="{" ".join(pts)}" stroke-linejoin="round"/><circle cx="32" cy="32" r="7"/>'


FRAMES = [
    ("settings", gear()),
    ("docs", '<path d="M32 19 C25 14 15 14 8 17 V50 C15 47 25 47 32 52 C39 47 49 47 56 50 V17 C49 14 39 14 32 19 Z"/>'
             '<line x1="32" y1="19" x2="32" y2="52"/><line x1="15" y1="26" x2="25" y2="26"/>'
             '<line x1="15" y1="34" x2="25" y2="34"/><line x1="39" y1="26" x2="49" y2="26"/>'
             '<line x1="39" y1="34" x2="49" y2="34"/>'),
    ("xp", '<polygon points="32,8 38.5,24 55,25 42,36 46.5,53 32,43.5 17.5,53 22,36 9,25 25.5,24" '
           'stroke-linejoin="round"/>'),
    ("xpdetail", '<polygon points="18,7 21.5,15.5 30,16 23.5,22 26,31 18,26 10,31 12.5,22 6,16 14.5,15.5" '
                 'stroke-linejoin="round"/><line x1="8" y1="56" x2="58" y2="56"/>'
                 '<line x1="24" y1="56" x2="24" y2="44"/><line x1="36" y1="56" x2="36" y2="36"/>'
                 '<line x1="48" y1="56" x2="48" y2="22"/>'),
    ("today", '<circle cx="32" cy="32" r="11"/>' + rays(17, 25, 0.39)),
    ("loot", '<path d="M24 24 C9 33 11 55 32 55 C53 55 55 33 40 24 Z"/>'
             '<path d="M24 24 L19 12 C27 15 37 15 45 12 L40 24"/><line x1="23" y1="24" x2="41" y2="24"/>'),
    ("combat", '<line x1="20" y1="44" x2="51" y2="13"/><line x1="44" y1="44" x2="13" y2="13"/>'
               '<line x1="13" y1="37" x2="27" y2="51"/><line x1="51" y1="37" x2="37" y2="51"/>'
               '<line x1="20" y1="44" x2="13" y2="51"/><line x1="44" y1="44" x2="51" y2="51"/>'
               '<circle cx="11" cy="53" r="2.5"/><circle cx="53" cy="53" r="2.5"/>'),
    ("notify", '<path d="M17 44 C21 40 19 22 32 20 C45 22 43 40 47 44 Z" stroke-linejoin="round"/>'
               '<line x1="13" y1="45" x2="51" y2="45"/><circle cx="32" cy="52" r="3.5"/>'
               '<circle cx="32" cy="15" r="3"/>'),
]


def frame(i: int, shapes: str) -> str:
    return (f'<g transform="translate({i * 64},0)" fill="none" stroke-linecap="round">'
            f'<g stroke="{EDGE}" stroke-width="{EDGE_W}">{shapes}</g>'
            f'<g stroke="#ffffff" stroke-width="{LINE_W}">{shapes}</g></g>')


def main() -> int:
    here = Path(__file__).resolve().parent
    n = len(FRAMES)
    svg = here / "launcher.svg"
    svg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{n * 64}" height="64" '
                   f'viewBox="0 0 {n * 64} 64">' + "".join(frame(i, s) for i, (_, s) in enumerate(FRAMES))
                   + "</svg>\n")
    png = here.parent / "toolbox" / "launcher.png"
    w, h = n * FRAME, FRAME
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), str(svg), "-o", str(png)], check=True)
    print(f"wrote {svg.name} and toolbox/{png.name} ({w}x{h}, {n} frames of {FRAME}x{FRAME})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
