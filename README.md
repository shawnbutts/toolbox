# Toolbox

A Shroud of the Avatar Lua add-on (API 14). The first feature is **Session XP**: adventurer and
producer XP gained this session, XP/hour, level progress and time to the next level.

- Store slug and package folder: `toolbox`
- Author: shawn butts
- License: MIT

Built clean-room from the official docs only:
[agent reference](https://catnipgames.net/lua/agent.html),
[API reference](https://catnipgames.net/lua/reference.html),
[authoring guide](https://catnipgames.net/lua/guide.html).

## Commands

`/toolbox` and `/tbx` go to the same dispatcher.

| Command | What it does |
| --- | --- |
| `/toolbox help` (or no argument) | list commands |
| `/toolbox xp` | show or hide the Session XP window |
| `/toolbox reset` | start a new XP session |
| `/toolbox font <9-32>` | set the window text size (no number: show the current size; default 12) |

If the game refuses a command name (another add-on has it, or it is too close to a chat
command), the add-on says why in chat, e.g. `Could not register /tbx: taken`.

## Session XP

The "Session XP" window shows elapsed time and, for adventurer and producer:

- XP gained this session
- XP/hour over the whole session and over the last 10 minutes
- level and % through it (from `ShroudGetLevelProgress()`)
- XP still needed for the next level, and the estimated time at the **session** rate (steadier
  than the 10-minute rate). With no XP gained yet on a track it says so instead of guessing;
  at the level cap it shows "max level"

**Source of truth.** Gains are the difference between `ShroudGetTotal{Adventurer,Producer}Experience()`
now and at the session start. `ShroudOnExperienceGain` is used only as a prompt to re-read the
totals: the docs say it fires on an increase with a positive amount, but not whether that amount
tracks pooled or total XP, so its amount is never summed. A 1-second periodic also re-reads the
totals, so nothing depends on the callback.

**Sessions.**

- A session starts when the add-on starts for a character (login, or enabling it) and on
  `/toolbox reset` or the window's Reset button.
- It survives `/lua reload`: the start time, baseline and last 10 minutes of samples are kept in
  character-scope saved vars and resumed.
- A new login starts a new session. At logout (`ShroudOnLogOut`) the session is marked ended;
  if the client crashed instead, the engine clock (`ShroudTime`) restarting from zero shows it
  is a new client run. The reasoning: "session" should mean one play sitting, and a login is the
  natural boundary; carrying XP/hour across hours offline would make the rates meaningless.
- Switching character without restarting the client starts a new session for that character.
- A reading lower than the previous one (for example a 0 while a scene loads) is ignored.

**Cost.** Nothing runs in `ShroudOnUpdate`. A 1-second periodic reads two totals, updates the
window only while it is open, and flushes saved vars at most every 30 seconds when something
changed.

The window remembers whether it is open, where it is and its text size (character-scope saved var
`window`). Drag its corner to resize it. The game remembers the size you drag it to, so the
size set in code only applies the first time the window opens. Content scrolls when the window
is smaller than it.

## Development

Requirements: Lua 5.2+ or LuaJIT, [luacheck](https://github.com/lunarmodules/luacheck), Python 3.9+.

```sh
luacheck .                 # lint (std lua52 + the documented API 14 globals)
lua tests/run.lua          # headless tests (luajit tests/run.lua works too)
python3 tools/build.py     # validate + write dist/toolbox/ and dist/toolbox-<version>.zip
make check                 # all three
```

`tools/build.py --check` validates without writing anything. The build enforces the store rules
from the docs: manifest fields, slug and version format, files list, flat whitelisted zip entries,
image limits, size caps, and no runtime code loading or `io`/`os` use in package files.

### Layout

```
toolbox/            the package (what ships)
  manifest.json     files load in this order: core.lua, xp.lua, ui.lua
  core.lua          Toolbox namespace, commands, saved-var helpers, session lifecycle, callbacks
  xp.lua            pure session XP model (rates, rolling window, time to level)
  ui.lua            the Session XP window (Shroud.UI)
  README.md         player-facing store readme
tests/              headless tests with a stubbed host (harness.lua)
tools/build.py      validator + packager
tools/install.py    copies dist/toolbox/ into a game client's Lua folder
```

## Testing in game

1. Build: `python3 tools/build.py`.
2. Find your Lua folder: in game type `/lua path`, or use the add-on manager's **Open Folder**.
   It is usually (confirm with `/lua path`):
   - Windows: `%APPDATA%\Portalarium\Shroud of the Avatar\Lua`
   - macOS: `~/Library/Application Support/Portalarium/Shroud of the Avatar/Lua`
3. Copy `dist/toolbox/` into it so you have `Lua/toolbox/manifest.json`, either by hand or:
   ```sh
   python3 tools/install.py --lua-dir "/path/to/Lua"
   # or: export SOTA_LUA_DIR="/path/to/Lua"; make install
   ```
   The folder name must be exactly `toolbox`, and there must be no loose `toolbox.lua` in the Lua
   folder (it would block the package). Re-installing replaces `Lua/toolbox/` only; saved vars in
   `Lua/SavedVariables/` are kept.
4. In game: `/lua reload`.
5. Enable **Toolbox** in the add-on manager (new add-ons load disabled).
6. `/lua check toolbox` should report nothing blocking.
7. `/toolbox xp` opens the window. Try `/tbx help`, `/tbx reset`, `/lua reload` (the session should
   carry on), and closing/moving the window then reloading.

## Releasing

1. Bump `version` in `toolbox/manifest.json` and `Toolbox.version` in `toolbox/core.lua`.
2. Add a `CHANGELOG.md` entry for it.
3. `make check`, then test in game.
4. Submit from the in-game Community Addons window (select the installed package,
   **Submit to Community**). Version numbers are single-use, even for rejected submissions.
