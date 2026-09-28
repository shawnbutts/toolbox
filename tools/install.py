#!/usr/bin/env python3
"""Copy the built package into a local game client's Lua folder for testing.

    python3 tools/build.py
    python3 tools/install.py --lua-dir "/path/to/Lua"
    SOTA_LUA_DIR="/path/to/Lua" python3 tools/install.py

Find the Lua folder in game with `/lua path` or the add-on manager's Open Folder
button. This replaces <Lua>/toolbox/ only; saved variables live in
<Lua>/SavedVariables/ and are left alone. The default alert sounds from art/ go into
<Lua>/toolbox/ with it (audio files can't ship in a store package yet); nothing is
written to <Lua> itself, where a player's replacement sounds go. Standard library only.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lua-dir", default=os.environ.get("SOTA_LUA_DIR"),
                        help="the game's Lua folder (default: $SOTA_LUA_DIR)")
    args = parser.parse_args()

    manifest = json.loads((ROOT / "toolbox" / "manifest.json").read_text(encoding="utf-8"))
    slug = manifest["slug"]
    src = ROOT / "dist" / slug
    if not (src / "manifest.json").is_file():
        print("dist/%s/ not found; run python3 tools/build.py first." % slug)
        return 1
    if not args.lua_dir:
        print("Pass --lua-dir or set SOTA_LUA_DIR (find it in game with /lua path).")
        return 1
    lua_dir = Path(args.lua_dir).expanduser()
    if not lua_dir.is_dir():
        print(f"{lua_dir} is not a folder.")
        return 1
    # The game's data folder (ChatLogs, Settings, ...) holds the Lua folder: an easy one to pass
    # by mistake, and the copy would land where the game never looks.
    if lua_dir.name != "Lua" and (lua_dir / "Lua").is_dir():
        print(f"{lua_dir} looks like the game's data folder; the Lua folder is inside it:")
        print(f"  --lua-dir '{lua_dir / 'Lua'}'")
        return 1

    # A loose <slug>.lua (any case) makes the game skip the package folder.
    for entry in lua_dir.iterdir():
        if entry.is_file() and entry.name.lower() == f"{slug}.lua":
            print(f"warning: {entry} will block the {slug}/ package folder; move it out of the Lua folder.")

    dest = lua_dir / slug
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest)
    print(f"Installed {len(list(dest.iterdir()))} files to {dest}")
    # The default alert sounds ship in the package (API 15), so they came with it. The Lua folder
    # itself is where a player's replacements go (Lua/toolbox_<name>.ogg): nothing is written there.
    old = [p for p in lua_dir.glob(f"{slug}_*") if p.suffix in (".ogg", ".wav")]
    if old:
        print("Note: these in the Lua folder act as REPLACEMENTS for the default sounds in the package"
              " (earlier installs put them there); delete them unless you want them:")
        for p in old:
            print(f"  {p}")
    print("In game: /lua reload, enable Toolbox in the add-on manager, /lua check toolbox, then /toolbox xp")
    return 0


if __name__ == "__main__":
    sys.exit(main())
