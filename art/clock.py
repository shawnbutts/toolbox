#!/usr/bin/env python3
"""Generate toolbox/clock.png: the buff bar's "time elapsed" overlay as a sprite sheet.

    python3 art/clock.py

FRAMES frames of FRAME x FRAME px in a COLS x ROWS grid. Frame k darkens the elapsed
fraction k / FRAMES of the icon as a wedge sweeping clockwise from 12 o'clock, with a thin
light "hand" on its leading edge; frame 0 is fully transparent. The wedge's radius covers
the corners, so the whole square icon darkens, as a cooldown sweep does.

The Lua side (toolbox/buffbar.lua) must use the same FRAMES / COLS / ROWS.
Writes an SVG to art/clock.svg and renders it with rsvg-convert (as for the icon).
"""

from __future__ import annotations

import math
import subprocess
from pathlib import Path

FRAMES, COLS, ROWS, FRAME = 24, 6, 4, 64
SHADE = "#000000"
SHADE_OPACITY = 0.62
HAND = "#f3d38a"
HAND_OPACITY = 0.85


def wedge(elapsed: float) -> str:
    """SVG for one frame (its own 0..FRAME coordinate space)."""
    if elapsed <= 0:
        return ""
    c = FRAME / 2
    r = FRAME * 0.75            # past the corners (half-diagonal is ~0.707 * FRAME)
    a = 2 * math.pi * elapsed
    x, y = c + r * math.sin(a), c - r * math.cos(a)
    large = 1 if elapsed > 0.5 else 0
    hx, hy = c + c * math.sin(a), c - c * math.cos(a)
    return (f'<path d="M{c},{c} L{c},{c - r} A{r},{r} 0 {large} 1 {x:.3f},{y:.3f} Z" '
            f'fill="{SHADE}" fill-opacity="{SHADE_OPACITY}"/>'
            f'<line x1="{c}" y1="{c}" x2="{hx:.3f}" y2="{hy:.3f}" stroke="{HAND}" '
            f'stroke-opacity="{HAND_OPACITY}" stroke-width="2" stroke-linecap="round"/>')


def main() -> None:
    here = Path(__file__).resolve().parent
    w, h = COLS * FRAME, ROWS * FRAME
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">']
    for k in range(FRAMES):
        col, row = k % COLS, k // COLS
        # A nested <svg> clips each frame to its own square.
        parts.append(f'<svg x="{col * FRAME}" y="{row * FRAME}" width="{FRAME}" height="{FRAME}" '
                     f'viewBox="0 0 {FRAME} {FRAME}">{wedge(k / FRAMES)}</svg>')
    parts.append("</svg>")
    svg = here / "clock.svg"
    svg.write_text("\n".join(parts) + "\n")
    png = here.parent / "toolbox" / "clock.png"
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), str(svg), "-o", str(png)], check=True)
    print(f"wrote {svg.name} and toolbox/{png.name} ({w}x{h}, {FRAMES} frames)")


if __name__ == "__main__":
    main()
