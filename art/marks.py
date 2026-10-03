#!/usr/bin/env python3
"""Generate toolbox/skillmarks.png: the skill strip's training-mode markers, as a two-frame sprite.

    python3 art/marks.py

Frame 0 (left half): an arrow pointing up (train; turned 180 degrees in game for unlearn).
Frame 1 (right half): a square (maintain).
Each frame is 3:2 (the shape of a marker's click area: half the icon wide, a third of it high), white with a
dark edge, so the game's tint (SetTint: @green, @gold, @red) colours it and it reads over any skill icon.
skills.lua (SK.MARKS) picks a frame with SetUV. Writes art/skillmarks.svg and renders it with rsvg-convert, as
art/clock.py does.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

FW, FH = 60, 40           # one frame: 3:2
EDGE = "#1a1a1a"          # the dark edge
STROKE = 3


def frame_arrow(x0: float) -> str:
    # an up-pointing triangle, centred, with room for the edge
    cx, top, bottom, half = x0 + FW / 2, 6, FH - 6, 13
    pts = f"{cx},{top} {cx + half},{bottom} {cx - half},{bottom}"
    return (f'<polygon points="{pts}" fill="#ffffff" stroke="{EDGE}" stroke-width="{STROKE}" '
            'stroke-linejoin="round"/>')


def frame_square(x0: float) -> str:
    side = 22
    x, y = x0 + (FW - side) / 2, (FH - side) / 2
    return (f'<rect x="{x}" y="{y}" width="{side}" height="{side}" rx="2" fill="#ffffff" '
            f'stroke="{EDGE}" stroke-width="{STROKE}"/>')


def main() -> int:
    here = Path(__file__).resolve().parent
    w, h = 2 * FW, FH
    svg = here / "skillmarks.svg"
    svg.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
                   + frame_arrow(0) + frame_square(FW) + "</svg>\n")
    png = here.parent / "toolbox" / "skillmarks.png"
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), str(svg), "-o", str(png)], check=True)
    print(f"wrote {svg.name} and toolbox/{png.name} ({w}x{h}, 2 frames of {FW}x{FH})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
