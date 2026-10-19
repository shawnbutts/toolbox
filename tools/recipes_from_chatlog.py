#!/usr/bin/env python3
"""Turn a recipe-book export found in the game's chat logs into one JSON file.

Not part of the add-on: a helper for comparing the game's recipes with the wiki.

    python3 tools/recipes_from_chatlog.py <chat log files or folders> [-o recipes.json]
    python3 tools/recipes_from_chatlog.py ChatLogs/ --list          # the exports found, and whether each is whole
    python3 tools/recipes_from_chatlog.py ChatLogs/ --run 20261019-153200
    python3 tools/recipes_from_chatlog.py --self-test

A folder means every .txt file in it. Files are read in name order (the game names chat logs by date), and the
newest export is taken unless --run picks one. An export with pieces missing is refused unless --partial is given
(the missing recipe numbers are then listed in the output). Standard library only.

The line format (version 1; the add-on's exporter must write exactly this). Each piece is one chat line holding

    TBXR1 <run> <rec>/<recs> <part>/<parts> <payload>

anywhere in the line (the game's time stamp and "[Add-on: Toolbox]" before it are ignored):
  - run: the export's id, letters, digits and "-" (the exporter uses its local date and time, YYYYMMDD-HHMMSS);
  - rec: 0 is the header (an object: who, when, client build, API, language, Toolbox version...), 1..recs a recipe;
  - part / parts: a record's JSON text is split into pieces short enough for one chat line;
  - payload: that piece, escaped so chat can't change it: letters, digits and SAFE (below) stay as they are, any
    other character is %XX (its code, 00-FF) or %uXXXX (a UTF-16 unit, as MoonSharp strings hold them), spaces
    included (chat may trim them).
Nothing in a payload is "[" or "<", so the game's color tags after it ("[-]") are dropped, and "&" is escaped too,
so a log written with HTML entities reads back the same.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path

FORMAT = "toolbox-recipes-1"
SAFE = "{}\":,.-_+()*;=?!@/'"
LINE = re.compile(r"TBXR1 ([A-Za-z0-9-]+) (\d+)/(\d+) (\d+)/(\d+) (\S*)")
PIECE = re.compile(r"[A-Za-z0-9" + re.escape(SAFE) + r"]+|%u[0-9A-Fa-f]{4}|%[0-9A-Fa-f]{2}")
TAIL = re.compile(r"(\[[^\]]*\])+$")


def unescape(payload: str) -> str:
    """A payload's text, the escapes undone (UTF-16 units joined into characters)."""
    units = []
    pos = 0
    for m in PIECE.finditer(payload):
        if m.start() != pos:
            raise ValueError(f"unexpected text {payload[pos:m.start()]!r}")
        tok = m.group(0)
        if tok.startswith("%u"):
            units.append(int(tok[2:], 16))
        elif tok.startswith("%"):
            units.append(int(tok[1:], 16))
        else:
            units.extend(ord(c) for c in tok)
        pos = m.end()
    if pos != len(payload):
        raise ValueError(f"unexpected text {payload[pos:]!r}")
    raw = b"".join(u.to_bytes(2, "little") for u in units)
    return raw.decode("utf-16-le", errors="surrogatepass").encode("utf-16", "surrogatepass").decode("utf-16")


def escape(text: str) -> str:
    """The exporter's escaping, for the self-test."""
    out = []
    for unit in (int.from_bytes(b, "little") for b in _units(text)):
        c = chr(unit) if unit < 0x80 else ""
        if c and (c.isalnum() or c in SAFE):
            out.append(c)
        elif unit < 0x100:
            out.append(f"%{unit:02X}")
        else:
            out.append(f"%u{unit:04X}")
    return "".join(out)


def _units(text: str):
    raw = text.encode("utf-16-le", "surrogatepass")
    return (raw[i:i + 2] for i in range(0, len(raw), 2))


def read_text(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return data.decode("utf-16", errors="replace")
    return data.decode("utf-8-sig", errors="replace")


def log_files(paths: list[str]) -> list[Path]:
    files = []
    for p in map(Path, paths):
        if p.is_dir():
            files.extend(sorted(f for f in p.iterdir() if f.is_file() and f.suffix.lower() == ".txt"))
        elif p.is_file():
            files.append(p)
        else:
            raise FileNotFoundError(f"no such file or folder: {p}")
    return files


class Run:
    def __init__(self, run_id: str):
        self.id = run_id
        self.recs = None          # recipe count, from the pieces
        self.pieces = {}          # (rec, parts) -> { part: payload }
        self.order = 0            # the last line seen of it, for "newest"
        self.conflicts = 0

    def add(self, rec: int, recs: int, part: int, parts: int, payload: str, order: int):
        if self.recs is None or recs > self.recs:
            self.recs = recs
        got = self.pieces.setdefault((rec, parts), {})
        if part in got and got[part] != payload:
            self.conflicts += 1
        got[part] = payload
        self.order = order

    def records(self) -> tuple[dict[int, object], list[int], list[str]]:
        """Whole records by number, the missing numbers, and the problems found."""
        whole, problems = {}, []
        for (rec, parts), got in sorted(self.pieces.items()):
            if rec in whole or any(p not in got for p in range(1, parts + 1)):
                continue
            try:
                whole[rec] = json.loads("".join(unescape(got[p]) for p in range(1, parts + 1)))
            except ValueError as e:
                problems.append(f"record {rec}: {e}")
        missing = [n for n in range(0, (self.recs or 0) + 1) if n not in whole]
        return whole, missing, problems


def collect(files: list[Path]) -> dict[str, Run]:
    runs: dict[str, Run] = {}
    order = 0
    for f in files:
        for line in read_text(f).splitlines():
            m = LINE.search(line)
            if not m:
                continue
            order += 1
            run_id, rec, recs, part, parts, payload = m.groups()
            payload = TAIL.sub("", html.unescape(payload.rstrip()))
            rec, recs, part, parts = int(rec), int(recs), int(part), int(parts)
            if parts < 1 or not 1 <= part <= parts or rec > recs:
                continue
            runs.setdefault(run_id, Run(run_id)).add(rec, recs, part, parts, payload, order)
    return runs


def sort_key(r):
    if isinstance(r, dict):
        return (str(r.get("name", "")).lower(), str(r.get("id", "")))
    return ("", "")


def build(run: Run, files: list[Path]) -> tuple[dict, list[int], list[str]]:
    whole, missing, problems = run.records()
    recipes = sorted((v for k, v in whole.items() if k != 0), key=sort_key)
    header = whole.get(0) if isinstance(whole.get(0), dict) else {}
    out = {
        "format": FORMAT,
        "run": run.id,
        "export": header,
        "sources": [str(f) for f in files],
        "count": len(recipes),
        "expected": run.recs or 0,
        "recipes": recipes,
    }
    if missing:
        out["missing"] = missing
    return out, missing, problems


def describe(run: Run) -> str:
    whole, missing, problems = run.records()
    state = "whole" if not missing and not problems else f"{len(missing)} of {(run.recs or 0) + 1} records missing"
    return f"{run.id}: {len(whole)} records, {state}" + (f", {len(problems)} unreadable" if problems else "")


def self_test() -> int:
    import tempfile
    header = {"character": "shawn", "build": "2da431775a", "api": 44, "language": "en", "toolbox": "1.10.0"}
    recipes = [
        {"id": 7, "name": "Iron Ingot", "station": "Smelter",
         "ingredients": [{"name": "Iron Ore", "count": 2}], "results": [{"name": "Iron Ingot", "count": 1}]},
        {"id": 3, "name": "Café [Special] & <Stew> 100%", "note": "tilde ~ \\ | \U0001F600 中",
         "ingredients": [], "results": []},
    ]
    lines = []
    records = [header] + recipes
    for rec, value in enumerate(records):
        text = escape(json.dumps(value, ensure_ascii=False, separators=(",", ":")))
        chunks, buf = [], ""                    # 40-character pieces, an escape kept whole in one
        for m in PIECE.finditer(text):
            if len(buf) + len(m.group(0)) > 40 and buf:
                chunks.append(buf)
                buf = ""
            buf += m.group(0)
        chunks.append(buf)
        for part, chunk in enumerate(chunks, 1):
            lines.append(f"[10/19/2026 3:32:01 PM] [Add-on: Toolbox] TBXR1 20261019-153200 {rec}/{len(recipes)} "
                         f"{part}/{len(chunks)} {chunk}[-]")
    lines.insert(3, "[10/19/2026 3:32:01 PM] someone: hello [b]there[/b]")
    stale = "[10/18/2026 1:00:00 PM] [Add-on: Toolbox] TBXR1 20261018-130000 0/1 1/1 %7B%7D"
    with tempfile.TemporaryDirectory() as d:
        Path(d, "SotAChatLog_shawn_2026.10.18.txt").write_text(stale + "\n", encoding="utf-8")
        Path(d, "SotAChatLog_shawn_2026.10.19.txt").write_text(
            "\n".join(html.escape(l, quote=False) if i % 2 else l for i, l in enumerate(lines)) + "\n",
            encoding="utf-8")
        files = log_files([d])
        runs = collect(files)
        assert set(runs) == {"20261018-130000", "20261019-153200"}, runs
        newest = max(runs.values(), key=lambda r: r.order)
        out, missing, problems = build(newest, files)
        assert not missing and not problems, (missing, problems)
        assert out["export"] == header, out["export"]
        assert out["recipes"] == sorted(recipes, key=sort_key), out["recipes"]
        stale_out, stale_missing, _ = build(runs["20261018-130000"], files)
        assert stale_missing == [1], stale_missing
    print("self-test passed")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="*", help="chat log files, or folders of them")
    ap.add_argument("-o", "--output", default="recipes.json", help="the JSON file to write ('-' for the screen)")
    ap.add_argument("--run", help="the export to take (default: the newest)")
    ap.add_argument("--list", action="store_true", help="list the exports found and stop")
    ap.add_argument("--partial", action="store_true", help="write an export with pieces missing")
    ap.add_argument("--self-test", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.paths:
        ap.error("give the chat log files or the folder holding them")
    try:
        files = log_files(args.paths)
    except FileNotFoundError as e:
        print(e, file=sys.stderr)
        return 2
    runs = collect(files)
    if not runs:
        print(f"no recipe export found in {len(files)} file(s)", file=sys.stderr)
        return 1
    if args.list:
        for run in sorted(runs.values(), key=lambda r: r.order):
            print(describe(run))
        return 0
    if args.run:
        run = runs.get(args.run)
        if run is None:
            print(f"no export '{args.run}'; found: {', '.join(sorted(runs))}", file=sys.stderr)
            return 1
    else:
        run = max(runs.values(), key=lambda r: r.order)
    out, missing, problems = build(run, files)
    for p in problems:
        print(f"{run.id}: {p}", file=sys.stderr)
    if run.conflicts:
        print(f"{run.id}: {run.conflicts} piece(s) seen twice with different text; the last kept", file=sys.stderr)
    if missing and not args.partial:
        print(f"{describe(run)}; not written (--partial writes it anyway)", file=sys.stderr)
        return 1
    text = json.dumps(out, ensure_ascii=False, indent=2) + "\n"
    if args.output == "-":
        sys.stdout.write(text)
    else:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"{run.id}: {out['count']} recipes written to {args.output}"
              + (f" ({len(missing)} missing)" if missing else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
