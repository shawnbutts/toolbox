#!/usr/bin/env python3
"""Print one version's CHANGELOG.md section, for a GitHub release's notes.

    python3 tools/release_notes.py 1.0.0                # the section's text (without its heading)
    python3 tools/release_notes.py 1.0.0 --prerelease   # "true" when its heading says "(beta N)"

Exits 1 when CHANGELOG.md has no "## [<version>]" section. Standard library only.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def section(text: str, version: str) -> tuple[str, str] | None:
    """The heading line and body of `version`'s section, or None."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^## \[" + re.escape(version) + r"\]", line):
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break
    return lines[start], "\n".join(lines[start + 1:end]).strip() + "\n"


def main(argv: list[str]) -> int:
    if not argv or argv[0].startswith("-"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    version = argv[0].lstrip("v")
    found = section((ROOT / "CHANGELOG.md").read_text(encoding="utf-8"), version)
    if found is None:
        print(f"CHANGELOG.md has no '## [{version}]' section", file=sys.stderr)
        return 1
    heading, body = found
    if "--prerelease" in argv[1:]:
        print("true" if re.search(r"\(beta\s*\d*\)", heading, re.IGNORECASE) else "false")
    else:
        sys.stdout.write(body)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
