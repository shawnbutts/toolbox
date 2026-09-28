#!/usr/bin/env python3
"""Run every check the project requires, the same way on macOS, Windows and Linux.

    python3 tools/check.py              # lint, tests (under every Lua found), build
    python3 tools/check.py --lua luajit # tests under one interpreter only
    python3 tools/check.py --container  # the same inside the dev container (docker or podman)

On Windows use `py tools/check.py` (or `python`). Steps, in order, stopping at the first failure:
  1. refresh toolbox/changelog.lua from CHANGELOG.md (tools/build.py --changelog)
  2. luacheck .
  3. tests/run.lua under each interpreter found: lua (or lua5.4 ... lua5.2) and luajit
  4. tools/build.py (package checks, dist/)

--container needs Docker or Podman and nothing else: the image (tools/container/Containerfile)
brings Lua 5.4, LuaJIT, luacheck, Python, git, ffmpeg and rsvg-convert. It is built on first use
(or with --rebuild-image). Standard library only.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IMAGE = "toolbox-dev"
CONTAINERFILE = ROOT / "tools" / "container" / "Containerfile"
LUA_NAMES = ["lua", "lua5.4", "lua5.3", "lua5.2"]      # the first found is "lua"; plus luajit


def run(label: str, cmd: list[str]) -> bool:
    print(f"\n== {label}: {' '.join(cmd)}", flush=True)
    try:
        return subprocess.run(cmd, cwd=ROOT).returncode == 0
    except FileNotFoundError:
        print(f"{cmd[0]} not found")
        return False


def interpreters(only: str | None) -> list[str]:
    if only:
        return [only]
    found = []
    lua = next((n for n in LUA_NAMES if shutil.which(n)), None)
    if lua:
        found.append(lua)
    if shutil.which("luajit"):
        found.append("luajit")
    return found


def local_checks(args: argparse.Namespace) -> int:
    py = sys.executable
    if not run("changelog", [py, "tools/build.py", "--changelog"]):
        return 1
    if not args.no_lint:
        if not shutil.which("luacheck"):
            print("\nluacheck not found. Install it (see CONTRIBUTING.md), or run with --container.")
            return 1
        if not run("lint", ["luacheck", "."]):
            return 1
    luas = interpreters(args.lua)
    if not luas:
        print("\nNo Lua interpreter found (lua, lua5.x or luajit). Install one (see CONTRIBUTING.md), or run"
              " with --container.")
        return 1
    for lua in luas:
        if not run(f"tests ({lua})", [lua, "tests/run.lua"]):
            return 1
    if not run("build", [py, "tools/build.py"]):
        return 1
    print("\nAll checks passed.")
    return 0


def engine(name: str | None) -> str | None:
    for candidate in ([name] if name else ["docker", "podman"]):
        if candidate and shutil.which(candidate):
            return candidate
    return None


def container_checks(args: argparse.Namespace, passthrough: list[str]) -> int:
    eng = engine(args.engine)
    if not eng:
        print("Neither docker nor podman was found.")
        return 1
    have = subprocess.run([eng, "image", "inspect", IMAGE], capture_output=True).returncode == 0
    if args.rebuild_image or not have:
        if not run("image", [eng, "build", "-t", IMAGE, "-f", str(CONTAINERFILE), str(CONTAINERFILE.parent)]):
            print(f"\nCouldn't build the image. Is {eng} running? (On macOS and Windows, Podman needs"
                  " `podman machine start`, Docker needs Docker Desktop.)")
            return 1
    # Podman on SELinux hosts (Fedora...) needs the mount relabelled; Docker doesn't take :Z everywhere.
    mount = f"{ROOT}:/src" + (":Z" if Path(eng).name == "podman" else "")
    return 0 if run("container", [eng, "run", "--rm", "-v", mount, "-w", "/src", IMAGE, "python3",
                                  "tools/check.py", *passthrough]) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Lint, test and build Toolbox.")
    parser.add_argument("--lua", help="run the tests under this interpreter only (e.g. luajit)")
    parser.add_argument("--no-lint", action="store_true", help="skip luacheck")
    parser.add_argument("--container", action="store_true", help="run inside the dev container")
    parser.add_argument("--engine", choices=["docker", "podman"], help="container engine (default: whichever is found)")
    parser.add_argument("--rebuild-image", action="store_true", help="rebuild the dev container image first")
    args = parser.parse_args()
    if args.container:
        passthrough = [a for a in sys.argv[1:] if a not in ("--container", "--rebuild-image")
                       and not a.startswith("--engine")]
        if args.engine and "--engine" in sys.argv:
            i = sys.argv.index("--engine")
            passthrough = [a for a in passthrough if a != sys.argv[i + 1]]
        return container_checks(args, passthrough)
    return local_checks(args)


if __name__ == "__main__":
    sys.exit(main())
