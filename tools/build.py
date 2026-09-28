#!/usr/bin/env python3
"""Validate and package the Toolbox add-on.

    python3 tools/build.py            # validate, then write dist/toolbox/ and dist/toolbox-<version>.zip
    python3 tools/build.py --check    # validate only

Also regenerates toolbox/changelog.lua from CHANGELOG.md (the add-on can't read files, so the
in-game changelog is baked in); --check fails when it is out of date.

The rules come from the SotA Lua docs (agent reference, "Packaging" and "Sandbox";
authoring guide, "Packages vs. flat files"), API version 14. Where the docs leave a
limit open, this script takes the stricter reading and says so in a comment.
Standard library only.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "toolbox"
DIST = ROOT / "dist"

CLIENT_API_VERSION = 22  # newest API the docs describe; min_api_version above this cannot load

SLUG_RE = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
# The docs list these "among" the reserved slugs; the full list is not published.
RESERVED_SLUGS = {"test", "addon", "addons", "lua", "shroud", "sota", "store", "system"}
VERSION_RE = re.compile(r"^(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})$")
LUA_NAME_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}\.lua$")
ART_NAME_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}\.(png|jpg|jpeg)$")
SOUND_NAME_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}\.(ogg|wav)$")
HOST_RE = re.compile(r"^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")

MANIFEST_KEYS = {
    "manifest_version", "slug", "name", "version", "description", "author", "readme", "icon",
    "files", "min_api_version", "permissions", "network_hosts", "dependencies",
}
FIXED_ENTRIES = {"manifest.json", "icon.png", "README.md"}

MAX_LUA_FILES = 16
MAX_ART = 12
MAX_ART_BYTES = 256 * 1024
MAX_ART_SIDE = 1024
MAX_SOUNDS = 32          # API 15 package sounds
MAX_SOUND_BYTES = 2 * 1024 * 1024
MAX_ENTRIES = 80         # the guide: "under 24 MB, zipped or unpacked, and at most 80 files"
MAX_ZIPPED = 24 * 1024 * 1024
MAX_UNPACKED = 24 * 1024 * 1024

# A lazy capture with the match anchored at the end: MoonSharp raised "pattern too complex" on
# the trim pattern over a long buff description (2026-09-28), killing the add-on.
LAZY_PATTERN_RE = re.compile(r"\(\.-\)[^\"'\n]*\$")

# Runtime code loading. The client scans source text (comments included) for these,
# and review flags them, so they are refused anywhere in a package file.
DYNAMIC_CODE_RE = re.compile(
    r"\b(load|loadstring|loadfile|dofile|require|loadsafe)\s*[(\"'\[{]"
    r"|\bdynamic\.eval\b|\b_G\s*\[|\b_ENV\s*\["
)
# The game's Lua (MoonSharp) passes a nil table entry on to the UI, which rejects it: a
# "color = ... or nil" in a style table hid a whole HUD strip in game. Refuse the pattern.
NIL_ENTRY_RE = re.compile(r"\b\w+\s*=\s*[^=\n]*\bor\s+nil\s*[,}]")
# The same through assignment: `spec.key = nil` does not remove the key in the game's Lua either,
# so an IconButton spec with `width, height = nil, nil` was refused ("IconButton has no field
# 'height'", 2026-09-28). Refuse nil assignments to fields of spec / style tables; build a new table.
SPEC_NIL_RE = re.compile(r"\b\w*(spec|style|Spec|Style)\.\w+(\s*,\s*[\w.]+)*\s*=\s*nil\b")

# A local declared without a value. Standard Lua sets it to nil; in game (MoonSharp) one seemed
# to keep an old value from its slot (alert sounds recorded a table as their clip). Always
# write `local x = nil`.
BARE_LOCAL_RE = re.compile(r"^\s*local\s+[A-Za-z_]\w*(\s*,\s*[A-Za-z_]\w*)*\s*(--.*)?$")

# Project rule: persistence goes through saved vars only; no file or OS access. The one
# exception is reading the local clock (os.date / os.time) for the daily reset.
FORBIDDEN_LIB_RE = re.compile(r"\bio\s*\.|\bos\s*\.(?!(date|time)\b)")


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)


def image_size(data: bytes, ext: str) -> tuple[int, int] | None:
    """Width and height from a PNG or JPEG header; None when the bytes do not match ext."""
    if ext == "png":
        if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
            return None
        return struct.unpack(">II", data[16:24])
    if data[:2] != b"\xff\xd8":
        return None
    i = 2
    while i + 9 < len(data):
        if data[i] != 0xFF:
            return None
        marker = data[i + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        length = struct.unpack(">H", data[i + 2:i + 4])[0]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h
        i += 2 + length
    return None


def check_manifest(report: Report) -> dict | None:
    path = PACKAGE / "manifest.json"
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        report.error("toolbox/manifest.json is missing")
        return None
    except json.JSONDecodeError as exc:
        report.error(f"manifest.json is not valid JSON: {exc}")
        return None
    if not isinstance(manifest, dict):
        report.error("manifest.json must be an object")
        return None

    for key in sorted(set(manifest) - MANIFEST_KEYS):
        report.error(f"manifest: unknown key '{key}'")

    if manifest.get("manifest_version") != 1:
        report.error("manifest: manifest_version must be 1")

    slug = manifest.get("slug")
    if not isinstance(slug, str) or not (3 <= len(slug) <= 40) or not SLUG_RE.match(slug):
        report.error("manifest: slug must be 3-40 chars matching ^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
    elif slug in RESERVED_SLUGS:
        report.error(f"manifest: slug '{slug}' is reserved")
    elif slug != PACKAGE.name:
        report.error(f"manifest: slug '{slug}' must equal the folder name '{PACKAGE.name}'")

    name = manifest.get("name")
    if not isinstance(name, str) or not (3 <= len(name) <= 60):
        report.error("manifest: name must be a 3-60 character string")

    version = manifest.get("version")
    if not isinstance(version, str) or not VERSION_RE.match(version):
        report.error("manifest: version must be N.N.N (0-9999 each, no leading zeros)")

    for key in ("description", "author"):
        value = manifest.get(key)
        if not isinstance(value, str) or not value.strip():
            # Optional for loading, but the store needs a description; keep both filled in.
            report.error(f"manifest: {key} must be a non-empty string")

    api = manifest.get("min_api_version")
    if type(api) is not int or api < 1:
        report.error("manifest: min_api_version must be a positive integer")
    elif api > CLIENT_API_VERSION:
        report.error(f"manifest: min_api_version {api} is newer than the documented API {CLIENT_API_VERSION}")

    files = manifest.get("files")
    if not isinstance(files, list) or not (1 <= len(files) <= MAX_LUA_FILES):
        report.error(f"manifest: files must list 1-{MAX_LUA_FILES} .lua files")
        files = []
    stems: set[str] = set()
    for f in files:
        if not isinstance(f, str) or not LUA_NAME_RE.match(f):
            report.error(f"manifest: bad files entry {f!r} (flat name, letters/digits/_/-, .lua)")
            continue
        stem = f[:-4].lower()
        if stem in stems:
            report.error(f"manifest: duplicate file stem '{stem}'")
        stems.add(stem)
        if not (PACKAGE / f).is_file():
            report.error(f"manifest: listed file {f} does not exist")

    perms = manifest.get("permissions", [])
    hosts = manifest.get("network_hosts")
    if not isinstance(perms, list) or any(p != "network" for p in perms):
        report.error('manifest: permissions may only contain "network"')
        perms = []
    if "network" in perms:
        if not isinstance(hosts, list) or not (1 <= len(hosts) <= 8):
            report.error("manifest: network needs 1-8 network_hosts")
        else:
            for h in hosts:
                if not isinstance(h, str) or not HOST_RE.match(h):
                    report.error(f"manifest: bad network host {h!r} (lowercase public FQDN)")
    elif hosts is not None:
        report.error("manifest: network_hosts without the network permission")

    deps = manifest.get("dependencies")
    if deps is not None:
        if not isinstance(deps, list) or len(deps) > 8 or len(set(map(str, deps))) != len(deps):
            report.error("manifest: dependencies must be at most 8 unique slugs")
        else:
            for d in deps:
                if not isinstance(d, str) or not SLUG_RE.match(d) or d in RESERVED_SLUGS or d == slug:
                    report.error(f"manifest: bad dependency {d!r}")
        if type(api) is int and api < 14:
            report.error("manifest: dependencies require min_api_version >= 14")

    icon = manifest.get("icon")
    if icon is not None:
        if icon != "icon.png":
            report.error('manifest: icon must be "icon.png"')
        elif not (PACKAGE / "icon.png").is_file():
            report.error("manifest: icon.png is declared but missing")
    elif (PACKAGE / "icon.png").is_file():
        report.warn('icon.png exists but manifest has no "icon" field')

    return manifest


def check_entries(report: Report, manifest: dict) -> list[Path]:
    """Checks every file in the package folder; returns them in canonical zip order."""
    files = [f for f in manifest.get("files", []) if isinstance(f, str)]
    api = manifest.get("min_api_version") if type(manifest.get("min_api_version")) is int else 0
    art: list[Path] = []
    sounds: list[Path] = []
    total = 0

    for path in sorted(PACKAGE.iterdir()):
        name = path.name
        if path.is_dir():
            report.error(f"{name}/: subfolders are not allowed in a package")
            continue
        if name.startswith("."):
            report.error(f"{name}: hidden files are not allowed in a package")
            continue
        total += path.stat().st_size
        if name in FIXED_ENTRIES:
            continue
        if name.endswith(".lua"):
            if name not in files:
                report.error(f"{name}: .lua file not listed in manifest files (it would never load)")
            continue
        if ART_NAME_RE.match(name) and Path(name).stem.lower() != "icon":
            art.append(path)
            continue
        if SOUND_NAME_RE.match(name) and Path(name).stem.lower() != "icon":
            sounds.append(path)
            continue
        report.error(f"{name}: not an allowed package entry (manifest.json, icon.png, README.md, *.lua, "
                     "pictures, .ogg/.wav sounds)")

    if art and api < 13:
        report.error("package pictures need min_api_version >= 13")
    if len(art) > MAX_ART:
        report.error(f"at most {MAX_ART} pictures allowed, found {len(art)}")
    images = art + ([PACKAGE / "icon.png"] if (PACKAGE / "icon.png").is_file() else [])
    for path in images:
        data = path.read_bytes()
        ext = path.suffix[1:]
        if len(data) > MAX_ART_BYTES:
            report.error(f"{path.name}: {len(data)} bytes, limit {MAX_ART_BYTES}")
        size = image_size(data, "png" if ext == "png" else "jpeg")
        if size is None:
            report.error(f"{path.name}: contents do not match the .{ext} extension")
        elif max(size) > MAX_ART_SIDE:
            report.error(f"{path.name}: {size[0]}x{size[1]}, limit {MAX_ART_SIDE}px per side")

    # API 15 sounds: bytes must match the extension (the store checks the header), <= 2 MiB each.
    if sounds and api < 15:
        report.error("package sounds need min_api_version >= 15")
    if len(sounds) > MAX_SOUNDS:
        report.error(f"at most {MAX_SOUNDS} sounds allowed, found {len(sounds)}")
    for path in sounds:
        data = path.read_bytes()
        if len(data) > MAX_SOUND_BYTES:
            report.error(f"{path.name}: {len(data)} bytes, limit {MAX_SOUND_BYTES}")
        if path.suffix == ".ogg" and not data.startswith(b"OggS"):
            report.error(f"{path.name}: not an Ogg file (no OggS header)")
        if path.suffix == ".wav" and not (data[:4] == b"RIFF" and data[8:12] == b"WAVE"):
            report.error(f"{path.name}: not a WAV file (no RIFF....WAVE header)")

    if total > MAX_UNPACKED:
        report.error(f"package is {total} bytes unpacked, limit {MAX_UNPACKED}")

    ordered = [PACKAGE / "manifest.json"] + [PACKAGE / f for f in files if (PACKAGE / f).is_file()]
    for extra in ("icon.png", "README.md"):
        if (PACKAGE / extra).is_file():
            ordered.append(PACKAGE / extra)
    ordered += sorted(art, key=lambda p: p.name)
    ordered += sorted(sounds, key=lambda p: p.name)     # canonical order: sounds after pictures
    if len(ordered) > MAX_ENTRIES:
        report.error(f"{len(ordered)} entries, limit {MAX_ENTRIES}")
    return ordered


def check_sources(report: Report, manifest: dict) -> None:
    for f in manifest.get("files", []):
        path = PACKAGE / f if isinstance(f, str) else None
        if not path or not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), 1):
            m = DYNAMIC_CODE_RE.search(line)
            if m:
                report.error(f"{f}:{lineno}: runtime code loading '{m.group(0).strip()}' is not allowed")
            if BARE_LOCAL_RE.match(line):
                report.error(f"{f}:{lineno}: a local without a value; write '= nil' (the game's Lua may not"
                             " reset it)")
            m = NIL_ENTRY_RE.search(line)
            if m and not line.lstrip().startswith("--"):
                report.error(f"{f}:{lineno}: a table entry that can be nil ('{m.group(0).strip()}'); the game's"
                             " Lua passes nil entries to the UI, which rejects them - use a real default")
            m = SPEC_NIL_RE.search(line)
            if m and not line.lstrip().startswith("--"):
                report.error(f"{f}:{lineno}: '{m.group(0).strip()}': setting a UI spec/style field to nil keeps the"
                             " key in the game's Lua, and the UI rejects it - build the table without it")
            m = LAZY_PATTERN_RE.search(line)
            if m:
                report.error(f"{f}:{lineno}: pattern '{m.group(0)}': the game's Lua gives up on a lazy (.-) match"
                             " anchored at the end over long text ('pattern too complex'); use Toolbox.Trim or"
                             " plain find/sub")
            m = FORBIDDEN_LIB_RE.search(line)
            if m:
                report.error(f"{f}:{lineno}: '{m.group(0)}' - use saved vars, not io/os (only os.date/os.time allowed)")


def check_changelog(report: Report, manifest: dict) -> None:
    changelog = ROOT / "CHANGELOG.md"
    version = manifest.get("version")
    if not changelog.is_file():
        report.warn("CHANGELOG.md is missing")
    elif isinstance(version, str) and f"[{version}]" not in changelog.read_text(encoding="utf-8"):
        report.warn(f"CHANGELOG.md has no [{version}] entry")


def check_version_constant(report: Report, manifest: dict) -> None:
    core = PACKAGE / "core.lua"
    if not core.is_file():
        return
    m = re.search(r'^\s*version\s*=\s*"([^"]*)"', core.read_text(encoding="utf-8"), re.M)
    if not m:
        report.error('core.lua: no Toolbox version = "N.N.N" field')
    elif m.group(1) != manifest.get("version"):
        report.error(f"core.lua version {m.group(1)} does not match manifest version {manifest.get('version')}")


CHANGELOG_LUA = PACKAGE / "changelog.lua"


def _plain(text: str) -> str:
    """Markdown to plain text for the game (no markup is ever interpreted there)."""
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)      # [text](url) -> text
    return text.replace("`", "").replace("**", "")


def _lua_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def changelog_entries() -> list[tuple[str, str]]:
    """CHANGELOG.md as (kind, text): version / section / item / para, newest first."""
    lines = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8").splitlines()
    out: list[tuple[str, str]] = []
    started = False
    for raw in lines:
        line = raw.rstrip()
        m = re.match(r"^## \[([^\]]+)\](.*)$", line)
        if m:
            started = True
            out.append(("version", (m.group(1) + m.group(2)).strip()))
            continue
        if not started:
            continue
        if line.startswith("### "):
            out.append(("section", line[4:].strip()))
        elif line.startswith("- "):
            out.append(("item", line[2:].strip()))
        elif not line.strip():
            out.append(("gap", ""))
        elif out and out[-1][0] in ("item", "para"):
            out[-1] = (out[-1][0], out[-1][1] + " " + line.strip())   # a wrapped line continues
        else:
            out.append(("para", line.strip()))
    return [(k, _plain(t)) for k, t in out if k != "gap"]


def render_changelog_lua() -> str:
    rows = [f"  {{ {_lua_string(kind)}, {_lua_string(text)} }}," for kind, text in changelog_entries()]
    return ("-- Toolbox: changelog.lua\n"
            "-- GENERATED by tools/build.py from CHANGELOG.md; edit CHANGELOG.md instead (make check\n"
            "-- regenerates it; --check fails when it is stale). Shown by /toolbox version.\n"
            "-- { kind, text }: kind is version / section / item / para, newest version first.\n\n"
            "Toolbox.CHANGELOG = {\n" + "\n".join(rows) + "\n}\n")


def sync_changelog(report: Report, check_only: bool) -> None:
    wanted = render_changelog_lua()
    current = CHANGELOG_LUA.read_text(encoding="utf-8") if CHANGELOG_LUA.is_file() else None
    if current == wanted:
        return
    if check_only:
        report.error("toolbox/changelog.lua is out of date with CHANGELOG.md; run python3 tools/build.py")
    else:
        CHANGELOG_LUA.write_text(wanted, encoding="utf-8")
        print("Regenerated toolbox/changelog.lua from CHANGELOG.md")


def build_stamp() -> str:
    """Short git commit, "+" when there are uncommitted changes; "dev" outside git."""
    import subprocess
    try:
        commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True,
                                text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True,
                               text=True, check=True).stdout.strip()
        return commit + ("+" if dirty else "")
    except (OSError, subprocess.CalledProcessError):
        return "dev"


def build(manifest: dict, entries: list[Path], report: Report) -> Path:
    slug = manifest["slug"]
    out_dir = DIST / slug
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    stamp = build_stamp()
    for path in entries:
        if path.name == "core.lua":
            # Stamp the build (git commit) so /toolbox version shows exactly what's installed.
            text = path.read_text(encoding="utf-8").replace('build = "dev",', f'build = "{stamp}",', 1)
            (out_dir / path.name).write_text(text, encoding="utf-8")
        else:
            shutil.copy2(path, out_dir / path.name)

    zip_path = DIST / f"{slug}-{manifest['version']}.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in entries:
            info = zipfile.ZipInfo(path.name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, (out_dir / path.name).read_bytes())   # the stamped copy
    if zip_path.stat().st_size > MAX_ZIPPED:
        report.error(f"{zip_path.name} is {zip_path.stat().st_size} bytes, limit {MAX_ZIPPED}")
    return zip_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="validate only; write nothing")
    parser.add_argument("--changelog", action="store_true",
                        help="only regenerate toolbox/changelog.lua (make runs this before lint and tests)")
    args = parser.parse_args()
    if args.changelog:
        report = Report()
        sync_changelog(report, check_only=False)
        return 0

    report = Report()
    sync_changelog(report, args.check)
    manifest = check_manifest(report)
    entries: list[Path] = []
    if manifest is not None:
        entries = check_entries(report, manifest)
        check_sources(report, manifest)
        check_changelog(report, manifest)
        check_version_constant(report, manifest)

    zip_path = None
    if manifest is not None and not report.errors and not args.check:
        zip_path = build(manifest, entries, report)

    for w in report.warnings:
        print(f"warning: {w}")
    for e in report.errors:
        print(f"error: {e}")
    if report.errors:
        print(f"\n{len(report.errors)} error(s); package rejected.")
        return 1
    names = ", ".join(p.name for p in entries)
    if zip_path:
        print(f"Built {DIST.relative_to(ROOT)}/{manifest['slug']}/ and {zip_path.relative_to(ROOT)}")
    else:
        print("Package is valid.")
    print(f"Entries: {names}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
