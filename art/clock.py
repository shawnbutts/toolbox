#!/usr/bin/env python3
"""Generate toolbox/clock.png: the buff bar's "time elapsed" overlay as a sprite sheet.

    python3 art/clock.py

FRAMES frames of FRAME x FRAME px in a COLS x ROWS grid, once per colour SET: first the
normal (dark) set, then below it the warning (red) set, shown once a buff's expiry alert
has fired. Frame k shades the elapsed fraction k / FRAMES of the icon as a wedge sweeping
clockwise from 12 o'clock, with a thin light "hand" on its leading edge; frame 0 is fully
transparent. The wedge's radius covers the corners, so the whole square icon is shaded, as
a cooldown sweep does. (A red version can't be made with a tint: tints multiply, and black
times red is still black.)

The Lua side (toolbox/buffbar.lua, BuffBar.CLOCK) must use the same FRAMES / COLS / ROWS / SETS.
Writes an SVG to art/clock.svg and renders it with rsvg-convert (as for the icon).
"""

from __future__ import annotations

import math
import subprocess
from pathlib import Path

FRAMES, COLS, ROWS, FRAME = 24, 6, 4, 64
# (shade colour, shade opacity, hand colour, hand opacity) per set, top to bottom.
SETS = [
    ("#000000", 0.82, "#f3d38a", 0.9),     # normal
    ("#7a0a05", 0.80, "#ffb4a0", 0.95),    # warning: the expiry alert has fired
]


def wedge(elapsed: float, shade: str, shade_opacity: float, hand: str, hand_opacity: float) -> str:
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
            f'fill="{shade}" fill-opacity="{shade_opacity}"/>'
            f'<line x1="{c}" y1="{c}" x2="{hx:.3f}" y2="{hy:.3f}" stroke="{hand}" '
            f'stroke-opacity="{hand_opacity}" stroke-width="2" stroke-linecap="round"/>')


def main() -> None:
    here = Path(__file__).resolve().parent
    w, h = COLS * FRAME, ROWS * FRAME * len(SETS)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">']
    for set_index, colours in enumerate(SETS):
        for k in range(FRAMES):
            col, row = k % COLS, set_index * ROWS + k // COLS
            # A nested <svg> clips each frame to its own square.
            parts.append(f'<svg x="{col * FRAME}" y="{row * FRAME}" width="{FRAME}" height="{FRAME}" '
                         f'viewBox="0 0 {FRAME} {FRAME}">{wedge(k / FRAMES, *colours)}</svg>')
    parts.append("</svg>")
    svg = here / "clock.svg"
    svg.write_text("\n".join(parts) + "\n")
    png = here.parent / "toolbox" / "clock.png"
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), str(svg), "-o", str(png)], check=True)
    print(f"wrote {svg.name} and toolbox/{png.name} ({w}x{h}, {len(SETS)} x {FRAMES} frames)")


if __name__ == "__main__":
    main()
