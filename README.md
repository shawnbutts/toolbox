# Toolbox

A Shroud of the Avatar Lua add-on (API 14). Features so far:

- **XP**: a small window with session time, your adventurer and producer pools, and XP earned in
  the last hour. Hover it for **XP Detailed**: levels, progress bars, XP/hour, time to next level.
- **Today**: gold picked up, kills, and XP gained since midnight. Hover it for **Today Detailed**:
  every item gained today, with counts.

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
| `/toolbox xp` | show or hide the XP window |
| `/toolbox xpdetailed` (or `xpd`) | show or hide the XP Detailed window |
| `/toolbox reset` | start a new XP session |
| `/toolbox daily` | show or hide today's stats (gold, kills, XP) |
| `/toolbox dailydetailed` (or `dd`) | show or hide Today Detailed (every item gained today) |
| `/toolbox config` | open or close the settings window |
| `/toolbox spacing <0-12>` | set the extra space between lines in pixels (no number: show and measure it; default 2) |
| `/toolbox font <9-32>` | set the window text size (no number: show the current size; default 12) |

If the game refuses a command name (another add-on has it, or it is too close to a chat
command), the add-on says why in chat, e.g. `Could not register /tbx: taken`.

## XP Detailed window

`/toolbox xpdetailed` (or `/toolbox xpd`) opens **XP Detailed**, which also pops up when you hover
the XP window (below). It shows the session time, a Reset button and, for adventurer and producer:

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
- It survives `/lua reload`: the start time, baseline and last hour of samples are kept in
  character-scope saved vars and resumed.
- A new login starts a new session. At logout (`ShroudOnLogOut`) the session is marked ended;
  if the client crashed instead, the engine clock (`ShroudTime`) restarting from zero shows it
  is a new client run. The reasoning: "session" should mean one play sitting, and a login is the
  natural boundary; carrying XP/hour across hours offline would make the rates meaningless.
- Switching character without restarting the client starts a new session for that character.
- A reading lower than the previous one (for example a 0 while a scene loads) is ignored.

**Cost.** Nothing runs in `ShroudOnUpdate`. A 1-second periodic reads two totals, updates the
windows only while they are open, stores a changed session in saved vars once a tick (not per XP
event: it holds up to an hour of samples) and flushes to disk at most every 30 seconds.

## XP window

`/toolbox xp` opens **XP**, a small window to keep on screen:

```
Session 1h 02m 03s
Adv pool          37,000
  Last hour      +12,000
Prod pool          4,300
  Last hour         +300
```

- **Adv pool / Prod pool**: your current unspent pooled XP, exactly as the game reports it
  (`ShroudGetPooled{Adventurer,Producer}Experience()`); it drops when you train skills with it.
- **Last hour**: XP earned on that track in the past 60 minutes, from the totals (so spending pool
  doesn't reduce it). While the session is younger than an hour it is the whole session.

It uses the same text size as XP Detailed and remembers its own open state and position.

**Hover for details.** Rest the pointer on the XP window for half a second and XP Detailed pops up
(with the progress bars and Reset). It stays while the pointer is over either window and closes
about ¾ s after it leaves both, so you can move over and click Reset. Passing over the XP window
quickly does nothing. A popped-up window isn't remembered as open; use `/toolbox xpdetailed` to
pin it (running it while the window is popped up keeps it open). Turn hover off with
"Show XP Detailed on hover" in `/toolbox config`.

`/toolbox config` opens a **Toolbox Settings** window with a text-size slider (applied as you
drag), a line-spacing slider, and checkboxes to show each window and to turn each hover pop-up on or off.

Shroud.UI has no line-height style, so every text line gets a fixed height of about
1.15 × the text size plus the line spacing (pinned with `minHeight`/`maxHeight` so a theme's own
minimum can't override it), with no margins above or below. `/toolbox spacing` with no number
reports the height lines should be and the height the game actually laid them out at. Shrinking the text
therefore shrinks the lines too, and both windows can then be dragged smaller. It writes the same settings as the chat commands.

The window remembers whether it is open, where it is and its text size (character-scope saved var
`window`). Drag its corner to resize it. The game remembers the size you drag it to, so the
size set in code only applies the first time the window opens. Content scrolls when the window
is smaller than it.

## Daily stats

`/toolbox daily` opens a **Today** window:

```
Today 2026-09-27
Gold picked up         1,500
Kills                     87
Adventurer XP        123,456
Producer XP            4,567
```

- **Resets at local midnight.** The local clock comes from `os.date`, which the SotA docs don't
  mention, so it is checked at runtime. Without it, the reset falls back to midnight UTC using the
  date in `ShroudServerTime`, and the date line's tooltip says so.
- **Gold picked up** is every increase in your gold. The API has no loot-gold event, so vendor
  sales, trades and mail count too. Spending doesn't subtract, and gold that changes while you are
  logged out isn't counted.
- **Kills** are combat-chat `death` lines dealt by you or your pet (`ShroudOnCombatEvents`).
  Party members' kills don't count. Lines past 50 in a single frame are dropped by the game.
- **XP** is the rise in your total adventurer / producer XP today.
- Per character, and kept across `/lua reload`, relogs and client restarts on the same day.

### Today Detailed

Rest the pointer on **Today** and **Today Detailed** pops up (same rules as XP Detailed: it stays
while the pointer is over either window, and `/toolbox dailydetailed` or `dd` pins it). It shows
the day's gold and kills and a list of every item gained today with its count, highest first.

- Items come from `ShroudOnItemsGained`: anything that arrives in your bags from outside them.
  That is loot, but also purchases, crafting results, harvests, mail and trades, and items taken
  from your bank or a chest, so the list is "items gained", not strictly "looted".
- The game reports at most 20 kinds of item per event; kinds past that are counted as
  "kinds the game didn't itemise".
- The list shows up to 60 rows. Shroud.UI can't reorder rows and caps how fast elements are
  created, so new items are appended as they arrive and the list is re-sorted only when the window
  opens (at most every 10 seconds). Up to 250 item names are kept per day; the rest are counted
  under "(other items)".
- Hover can be turned off with "Show Today Detailed on hover" in `/toolbox config`.

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
image limits, size caps, no runtime code loading, and no `io`/`os` use in package files except
`os.date`/`os.time`.

### Layout

```
toolbox/            the package (what ships)
  manifest.json     files load in this order: core.lua, xp.lua, hover.lua, ui.lua, compact.lua, daily.lua,
                    dailydetail.lua, config.lua
  core.lua          Toolbox namespace, commands, saved-var helpers, session lifecycle, callbacks
  xp.lua            pure session XP model (rates, rolling window, time to level)
  ui.lua            the XP Detailed window (/toolbox xpdetailed; Toolbox.Window, id toolbox_xp)
  compact.lua       the XP window (/toolbox xp; Toolbox.Compact, id toolbox_compact)
  hover.lua         shared hover pop-up controller (XP -> XP Detailed, Today -> Today Detailed)
  daily.lua         daily stats and the Today window (/toolbox daily)
  dailydetail.lua   the Today Detailed window (/toolbox dailydetailed, dd)
  config.lua        the Toolbox Settings window (/toolbox config)
  README.md         player-facing store readme
  icon.png          store / add-on manager icon (256x256)
art/icon.svg        editable source of the icon (not shipped)
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
7. `/toolbox xp` opens the XP window; hover it for XP Detailed. Try `/tbx help`, `/tbx reset`, `/lua reload` (the session should
   carry on), and closing/moving the window then reloading.

## Releasing

1. Bump `version` in `toolbox/manifest.json` and `Toolbox.version` in `toolbox/core.lua`.
2. Add a `CHANGELOG.md` entry for it.
3. `make check`, then test in game.
4. Submit from the in-game Community Addons window (select the installed package,
   **Submit to Community**). Version numbers are single-use, even for rejected submissions.
