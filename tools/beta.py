#!/usr/bin/env python3
"""Package a beta for hand installs.

    python3 tools/beta.py            # or: make beta

Runs tools/build.py (every store check still applies), then writes
dist/toolbox-<version>-beta.zip holding:

    toolbox/        the add-on as built (dist/toolbox/), plus the default alert sounds
                    (art/*.ogg and art/*.wav; fine for a hand install, not allowed in a store
                    package yet)
    INSTALL.txt     BETA.md: install steps, what to test, known issues, how to report

Testers extract it and copy the "toolbox" folder into their Lua folder. The build is stamped
with the git commit (shown by /toolbox version), so build from a clean, committed tree.
Standard library only.
"""

from __future__ import annotations

import json
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    result = subprocess.run([sys.executable, str(ROOT / "tools" / "build.py")], cwd=ROOT)
    if result.returncode != 0:
        print("\nThe build failed; no beta was made.")
        return 1

    manifest = json.loads((ROOT / "toolbox" / "manifest.json").read_text(encoding="utf-8"))
    slug, version = manifest["slug"], manifest["version"]
    built = ROOT / "dist" / slug
    stamp_line = next((l for l in (built / "core.lua").read_text(encoding="utf-8").splitlines()
                       if l.strip().startswith("build = ")), "")
    if "+" in stamp_line or '"dev"' in stamp_line:
        print("warning: the build isn't from a clean commit (" + stamp_line.strip() + "); testers' "
              "/toolbox version won't map to an exact commit. Commit first for a real beta.")

    sounds = sorted((ROOT / "art").glob("*.ogg")) + sorted((ROOT / "art").glob("*.wav"))
    if not any(p.suffix == ".wav" for p in sounds):
        print("warning: no .wav sounds in art/ (python3 art/alerts.py makes them); only .ogg included.")

    out = ROOT / "dist" / f"{slug}-{version}-beta.zip"
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(built.iterdir()):
            zf.write(path, f"{slug}/{path.name}")
        for path in sounds:
            zf.write(path, f"{slug}/{path.name}")
        zf.writestr("INSTALL.txt", (ROOT / "BETA.md").read_text(encoding="utf-8"))

    print(f"\nBeta package: {out.relative_to(ROOT)}")
    with zipfile.ZipFile(out) as zf:
        for name in zf.namelist():
            print("  " + name)
    print("\nSend testers the zip; INSTALL.txt inside tells them what to do.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
