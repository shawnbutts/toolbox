# Contributing to Toolbox

Thanks for helping! Toolbox is a Lua add-on for Shroud of the Avatar. This page gets you from a fresh
checkout to a passing check and a build running in the game, on macOS, Windows or Linux.
[AGENTS.md](AGENTS.md) is the in-depth guide to how the code is organised, the rules it follows, and
everything learned about the game's Lua API; read its "Hard rules" before your first change.

## Ground rules

- **Clean-room.** Work only from the official add-on docs (https://catnipgames.net/lua/). Don't copy or
  adapt code from other add-ons (including OCX Tools).
- **Everything passes `tools/check.py`** (lint, tests under every Lua you have, and the package build)
  before it's committed.
- **Add a test** for new behaviour (`tests/`, run headless against a fake game host) and a line under
  `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for anything a player would notice.

## Set up

You need **Python 3.9+**, **Lua** (5.2 or newer) and/or **LuaJIT**, and **luacheck**. Or skip all of
that and use the container (below): then you only need Docker or Podman.

**macOS** (Homebrew):

```sh
brew install lua luajit luacheck python
```

**Linux** (Debian/Ubuntu):

```sh
sudo apt install lua5.4 luajit lua-check python3
```

Other distributions: install Lua and LuaJIT from the package manager and luacheck with
`luarocks install luacheck`.

**Windows**:

- Python from https://www.python.org/ (it installs the `py` launcher).
- Lua and LuaJIT, for example with [Scoop](https://scoop.sh/): `scoop install lua luajit`.
- luacheck: the standalone `luacheck.exe` from the
  [luacheck releases](https://github.com/lunarmodules/luacheck/releases), somewhere on your `PATH`.

Line endings: the repo is LF everywhere (`.gitattributes` makes Git keep it that way on Windows too),
and [.editorconfig](.editorconfig) sets your editor to match the linter (2 spaces, 120 columns).

## Check

```sh
python3 tools/check.py              # Windows: py tools/check.py
```

It refreshes the generated `toolbox/changelog.lua`, runs `luacheck .`, runs the tests under each Lua
it finds (`lua` and `luajit`), and builds the package into `dist/`. Handy variations:

```sh
python3 tools/check.py --lua luajit # tests under one interpreter
lua tests/run.lua buffbar           # only the tests whose name contains "buffbar"
python3 tools/build.py --check      # package checks without writing dist/
make check                          # the same as tools/check.py, if you have make
```

### In a container (Docker or Podman)

```sh
python3 tools/check.py --container  # or: make container-check
```

The first run builds a small image ([tools/container/Containerfile](tools/container/Containerfile))
with Lua 5.4, LuaJIT, luacheck, Python, git, ffmpeg and rsvg-convert; your checkout is mounted into it,
nothing is copied. Add `--rebuild-image` after changing the Containerfile, or `--engine podman` to pick
the engine.

## Try it in the game

Find your game's Lua folder with `/lua path` in chat, then:

```sh
python3 tools/build.py
python3 tools/install.py --lua-dir "<your Lua folder>"
```

In game: `/lua reload`, switch Toolbox on in the add-on manager, and check `/toolbox version` shows
your build (the short commit, with `+` for uncommitted changes). Most features have a debug command
(`/toolbox buffs debug`, `/toolbox xp debug`, `/toolbox combat events 5`, ...); the game's own log
(`Player.log`) is the place to look when something fails silently.

## Regenerating art and sounds

Only needed when you change them: `art/clock.py` and the icon need `rsvg-convert`, `art/alerts.py`
needs `ffmpeg`. Both come with the container:

```sh
docker run --rm -v "$PWD:/src" -w /src toolbox-dev python3 art/alerts.py
```

## Reporting bugs

Use the bug report template. The most useful things to include: the line `/toolbox version` prints,
what you did and what happened, any chat lines starting with `[Add-on: Toolbox]`, and the output of
the debug command for the part that misbehaves.
