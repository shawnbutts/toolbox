# AGENTS.md

Guidance for AI coding agents (and humans) working on Toolbox, a Shroud of the Avatar Lua add-on.

## Hard rules

- **Clean-room.** Do not copy or adapt code from OCX Tools or any other existing add-on. Work only
  from the official docs:
  - https://catnipgames.net/lua/agent.html (dense API map; read first)
  - https://catnipgames.net/lua/reference.html (full reference)
  - https://catnipgames.net/lua/guide.html (packaging, sandbox, store)
- **Target Lua API 14 on MoonSharp (Lua 5.2 semantics).** No 5.3+ features: no integer division
  `//`, no bitwise operators, no `utf8` library, no `math.tointeger`/`math.type`, no `<const>`/`<close>`.
  Also avoid `goto` and `table.unpack`/`unpack` so the tests run on LuaJIT too. Pass whole numbers to
  `%d` (use `math.floor`); `string.format("%d", 1.5)` errors on 5.3+.
- **The released client can lag the docs.** Twice now a documented value was missing in game (buff
  `TotalDuration`/`CurrentDuration` are nil; `ShroudPlayerCurrentHealth`/`Focus` aren't numbers). Read
  documented values defensively, keep a fallback that was confirmed in game, and add a `debug`
  subcommand that prints raw values so the owner can check without guessing.
- **Use the UI theme for colours** (owner's preference): theme classes (`inset`, `card`, `text`, ...) and
  `@` tokens follow the player's skin; avoid hard-coded `#rrggbb` except where the theme has nothing.
- **Always initialise locals: `local x = nil`, never a bare `local x`.** In game a bare `local found`
  inside a loop appeared to keep an old value (a table) instead of starting as nil, marking both alert
  sounds "ready" with the same table as their clip. `tools/build.py` refuses bare declarations; luacheck's
  311 ("value assigned is unused") is ignored because of these deliberate `= nil` defaults.
- **Never put a possibly-nil value in a table passed to the UI** (spec, style, `SetStyle`). Unlike
  standard Lua, the game's MoonSharp passes a nil entry on, and the UI rejects it ("style color takes a
  number or a string" hid the whole combat strip). Use a real default, or add the key only when set.
  The tests can't see this (a nil entry doesn't exist in standard Lua); `tools/build.py` refuses
  `name = ... or nil` table entries.
- **Avoid `a and b or c` when `b` can be false/nil**; it has already caused a bug (vitals "not both off").
- **Don't guess at API behaviour.** If the docs are unclear, pick the conservative option, write
  down the assumption (README or a comment), and add it to "Unconfirmed API behaviour" below.
- **One global.** Everything lives in the `Toolbox` table or is `local`. The only other globals are
  the `ShroudOn*` callbacks. All add-ons share one global environment.
- **No runtime code loading** (`load`, `loadstring`, `loadfile`, `dofile`, `require`, `_G[...]`,
  `_ENV[...]`) in package files, not even in comments: the client matches source text.
  `tools/build.py` refuses it.
- **No `io.*` / `os.*`**, except `os.date`/`os.time` to read the local clock (undocumented in the SotA
  docs, so always feature-detect them; see `Toolbox.Today`). Persist with
  `ShroudSetSavedVar`/`ShroudGetSavedVar`, character scope.
- **UI is `Shroud.UI` only.** No retained widgets (`ShroudUI*`), no immediate-mode GUI (`ShroudOnGUI`).
- **No per-frame work.** Don't define `ShroudOnUpdate`. Use events and the 1-second periodic.
- Constructors (`Shroud.UI.*`, `Shroud.Command`) raise at file top level. Call them from
  `ShroudOnStart` or later. Reading `Shroud.UI` at top level is fine.

## Commands

```sh
luacheck .                 # must be clean
lua tests/run.lua          # must pass (also: luajit tests/run.lua; filter: lua tests/run.lua reload)
python3 tools/build.py     # must succeed; --check validates only
make check                 # all of the above
python3 tools/install.py --lua-dir "<game Lua folder>"   # local in-game testing
```

Run all three before calling a change done.

## Layout

- `toolbox/`: the shipped package. Flat folder: `manifest.json`, `*.lua`, `README.md` (store readme),
  optional `icon.png` and pictures. Nothing else, or the build fails.
  - `manifest.json` `files` is the load order: `core.lua`, `xp.lua`, `hover.lua`, `ui.lua`, `compact.lua`, `daily.lua`, `dailydetail.lua`, `sounds.lua`, `hud.lua`, `buffbar.lua`, `vitals.lua`, `combat.lua`, `changelog.lua`, `docs.lua`, `config.lua`. A new `.lua` file must be
    added there. Later files may use globals from earlier ones at top level; earlier files may only use
    later ones inside functions (callbacks run after every file has loaded).
  - `core.lua`: `Toolbox` namespace, chat output (`Toolbox.Print`), saved-var helpers (`Load`/`Save`/`Flush`,
    which deep-copy), formatting, the command table and dispatcher, session lifecycle, all callbacks.
  - `xp.lua`: `Toolbox.XP`, a pure model over a plain-data session table. No API calls, so it is
    storable in saved vars and trivially testable. Time is always passed in.
  - `ui.lua`: `Toolbox.Window`, the **XP Detailed** window (`/toolbox xpdetailed`, `xpd`). Internal names
    (`Toolbox.Window`, id `toolbox_xp`, saved var `window`) predate the rename; keep them so players keep
    their positions and settings. Build every text label's style with
    `Toolbox.Window.TextStyle{...}` (font size + fixed line height, no vertical margins) so font and
    spacing changes reach it; `ApplyText()` re-applies both to both windows. `SetOpen`/`SetFont` are the only writers of its prefs.
  - `compact.lua`: `Toolbox.Compact`, the **XP** window (`/toolbox xp`; id `toolbox_compact`, saved var
    `compact`). Own open/position prefs; text style comes
    from `Toolbox.Window.TextStyle()` and is re-applied via `Toolbox.Compact.ApplyText()`. It also owns
    the hover pop-up: elements of both windows report hover keys to `PopupHover`, and one-shot
    periodics (`toolbox_hover_show`/`_hide`) apply the delays. XP Detailed distinguishes
    pinned (`IsOpen`, persisted) from popped up (`IsPopup`, never persisted).
  - `hover.lua`: `Toolbox.Hover.New{ name, enabled, trigger, popup }` returns a controller for one
    trigger window and one pop-up. Trigger elements report `hover:Report("t:<el>", over)`, pop-up
    elements `"p:<el>"`; `Clear(prefix)` when a window closes, `Cancel()` when hover is turned off.
    A pop-up window needs `IsShown`, `IsPopup`, `ShowPopup`, `HidePopup`, and must keep "pinned"
    (`IsOpen`, persisted) apart from "popped up" (never persisted). Copy `dailydetail.lua` for a new one.
  - `daily.lua`: `Toolbox.Daily`, daily stats (model functions at the top are pure and tested) and the
    Today window. Fed by `Toolbox.Sample` (XP totals), `Toolbox.Tick` (gold, day rollover, saving) and
    `ShroudOnCombatEvents` (kills). `OnLogin` is called for every new session except a reset, and
    re-bases gold/XP so offline changes don't count. The day key comes from `Toolbox.Today()`.
  - `dailydetail.lua`: `Toolbox.DailyDetail`, the Today Detailed window. Item rows are never rebuilt on a
    timer (element-creation cap; no reorder API): new names are appended, and a sorted rebuild happens
    only when the window is shown, the rows are out of order, and `RESORT_SECONDS` have passed.
    Rows have no ids (item names aren't valid ids); handles are kept in a Lua table.
  - `sounds.lua`: `Toolbox.Sounds`. `Play(key)` for `buff_expiring` / `debuff_landed`. Loading walks
    candidate paths (custom, `toolbox_<file>` loose in Lua/, `toolbox/<file>`, `<file>`); each gets
    `LOAD_TIMEOUT` s to appear in `ShroudListSound()` (loads are async and "accepted" isn't "found").
    Clips are found by *name* at play time (ids are list positions; `ShroudListSoundReset` clears it).
    Never name a Lua function `load`: the loader/reviewer scan source text for `load(`.
  - `buffbar.lua`: `Toolbox.BuffBar`. Model functions (`Track`, `Frame`, `FrameUV`, `NewNames`) are pure.
    `OnBuffsChanged` reads `ShroudGetPlayerBuff()` (debuff flags, icons) and raises the debuff alert;
    its own 0.5 s periodic reads the flat effect list, runs the expiry alert and fills a fixed slot pool
    (never create elements per change). Buffs whose rune or displayed name contains a `prefs.group` part
    (default: the 7 Obsidian potion runes, `BlessingOf...` by full name) go into one extra "group" slot:
    count label over the first one's icon, list + time left in the tooltip. By name because the API has
    no long-lasting flag and no full duration (owner's choice, 2026-09-27); they still get expiry alerts.
    CONFIRMED in game 2026-09-27 (build bca2d21): the seven potions collapse into one slot with the count,
    and the hover list shows. The clock overlay is a second `Image` over the icon via a
    negative left margin, showing one `SetUV` frame of `clock.png` (`CLOCK` must match `art/clock.py`).
  - `vitals.lua`: `Toolbox.Vitals`, the health & focus bars (HUD). `V.Format` is pure. Every size comes
    from `V.Metrics()` (one scale factor; Shroud.UI has no zoom), applied at build and by `applySize`. Reads the
    per-frame globals directly (never through a name built at runtime: review treats that like code
    loading) and the `Health` / `Focus` stats as maximums.
  - `combat.lua`: `Toolbox.Combat`, the combat stats HUD. Fight model (`NewFight`, `Add`, `Rates`, `CritPct`,
    `AvoidPct`) is pure. Fed by `ShroudOnCombatEvents` and `ShroudOnCombatModeChanged` (both in core.lua).
    A fixed pool of label rows is built once; `Rows()` decides what they show.
  - `hud.lua`: `Toolbox.Hud` owns every HUD strip. A HUD module registers (`Hud.Register(key, module)`)
    and implements `FRAME_ID`, `HOME`, `BuildContent()`, `ContentSize()`, `IsShown()`,
    `GetSavedPosition()` / `SavePosition(x, y)`; it never creates a HudFrame itself. `Hud.Build()` makes
    one strip per module, or one shared "toolbox_hud" strip in `Hud.ORDER` when glued (rebuilt on
    `Hud.SetGlued`); only modules in `Hud.GLUE` share it, others (combat) keep their own strip. Call `Hud.Refresh()` when a module's content size or shown state changes; `Hud.Tick()`
    (1 s) remembers positions (per module unglued, `hud.x/y` glued). Movers: `Hud.MoverFor(key, home)`.
    `Hud.TextStrip(spec)` is the HUD form of the XP and Today windows (`prefs.hud`, `/toolbox xp hud`):
    a module registered from `Compact.Init` / `Daily.InitWindow` (they load before hud.lua, so never at
    top level), with labels under the window's ids; those modules write to `active()`, whichever form is in use.
  - HUD strips share `Toolbox.Window.HudMover(getFrame, home, homeFn)` (Get/MoveTo/Nudge/Reset),
    `Toolbox.Config.PositionRows(prefix, module)` and `Toolbox.MoveCommand(module, cmd, name, args)`.
  - `changelog.lua`: GENERATED by `tools/build.py` from CHANGELOG.md (`Toolbox.CHANGELOG`, `{ kind, text }`
    rows). Never edit it; edit CHANGELOG.md and run `make check`. CHANGELOG text lands in a package file, so
    the source checks apply to it: don't quote refused patterns there (runtime loading, "or nil" entries).
    The package allows 16 Lua files and has 15: prefer adding code to an existing file.
  - `docs.lua`: `Toolbox.Docs`, the Docs window, and the version window (`/toolbox version`, `OpenVersion`),
    and `Toolbox.Motd`, the guild message of the day window (`/toolbox motd`): `Check()` runs from
    `ShroudOnStart`, every tick and `ShroudOnSocialChanged`, and opens it when the message differs from
    `guild_motd.seen`; a message counts as seen only once the window is really shown. `NewMessage` is pure.
    `D.SECTIONS` is the player guide (update it with every
    user-facing change); the Commands part comes from `Toolbox.CommandList()`. Built on first open.
  - `config.lua`: `Toolbox.Config`, the settings window. Controls call the owning module's setters; the
    setters call `Toolbox.Config.Sync()` so the controls follow chat commands and the close button.
    To add a setting: a setter + getter on the owning module (persisted there), a control here, a line
    in `Sync()`, and tests in `tests/test_config.lua`.
- `tests/`: `harness.lua` is a fake host (see below); `test_*.lua` suites; `run.lua` the runner.
- `art/icon.svg`: source of `toolbox/icon.png`. Re-render with
  `rsvg-convert -w 256 -h 256 art/icon.svg -o toolbox/icon.png` (keep it 256x256, well under 256 KiB).
- `art/clock.py` renders `toolbox/clock.png` (the buff bar's clock overlay sprite sheet; shipped as a
  package picture, API 13+) and `art/clock.svg`: a normal set and a red "alert fired" set of 120 frames (3 degrees each; 24 made long buffs look frozen).
  Keep its FRAMES/COLS/ROWS/SETS in sync with `BuffBar.CLOCK`.
- `art/*.ogg` alert sounds, all generated by `python3 art/alerts.py [name ...]` (stdlib synthesis +
  ffmpeg's built-in Vorbis encoder; each alert's settings are near the top of its section):
  `buff_expiring` (two falling bell chimes, 0.9 s) and `debuff_landed` (sad D-minor droop over a
  thump, no echo, 0.38 s). Re-encoding changes the .ogg bytes (random stream serial) even when the
  audio is identical, so `git checkout` an .ogg you didn't mean to change. NOT shipped: the documented package whitelist has no audio, and
  `tools/build.py` refuses it. When audio is allowed, re-read the packaging docs for formats and size
  limits, extend `build.py`'s whitelist, and move the files into `toolbox/` (`Toolbox.Sounds` already
  looks there). Owner's decision (2026-09-27): DEFAULTS live in the package folder (`Lua/toolbox/<name>`,
  path "toolbox/<name>"); a player's REPLACEMENTS go in the Lua folder beside it (`Lua/toolbox_<name>`)
  and win. `tools/install.py` puts the defaults in the package folder and never writes to the Lua root.
- `tools/build.py` stamps `build = "<git short commit>[+]"` into dist's core.lua (the source keeps "dev");
  `/toolbox version` shows it, to tell exactly which build is installed.
- `tools/build.py`: validates the store packaging rules and writes `dist/toolbox/` + zip.
- `tools/install.py`: copies `dist/toolbox/` into a client's Lua folder.
- `tools/beta.py` (`make beta`): builds, then zips `toolbox/` (+ default sounds) and `INSTALL.txt`
  (= `BETA.md`, the tester guide) as `dist/toolbox-<version>-beta.zip`. Update BETA.md's known issues
  and "what to try" for every beta.
- `.luacheckrc`: std `lua52` plus every global documented for API 14. If the docs add a function,
  add it here; never add a name that isn't in the docs.

## Adding a subcommand

In `core.lua`, call `add(name, help, fn)` next to the existing ones. `fn(rest)` receives the text after
the subcommand. Help text lists them in registration order. Add a test in `tests/test_commands.lua`.
Command limits: 8 per add-on; `Shroud.Command` returns `ok, reason`, and a refusal must be reported
in chat.

## Adding a feature module

1. New file in `toolbox/`, add it to `files` in `manifest.json` in the right order.
2. Hang it off `Toolbox` (`Toolbox.Foo = {}`), keep everything else `local`.
3. Pure logic in plain functions over plain data; API calls at the edges (core/ui).
4. Hook into `ShroudOnStart` / `Toolbox.Tick` in `core.lua` instead of defining a second copy of a
   callback (a later file's definition would silently replace the earlier one).
5. Tests in a new `tests/test_foo.lua`, registered in `tests/run.lua`'s `suites` list.
6. `CHANGELOG.md` entry under `[Unreleased]`.

## The test harness

`tests/harness.lua` models the documented host behaviour Toolbox relies on:

- constructors and `Shroud.Command` raise outside a callback; constructors reject unknown fields;
- saved vars have an in-memory cache and a "disk" copy updated on flush;
- `H.reload()` = `/lua reload`: flush, tear down UI/commands/timers, reload files, `ShroudTime` continues;
- `H.restart()` = client relaunch: only flushed data survives, `ShroudTime` restarts;
- `H.advance(n)` runs the periodics second by second; `H.gain(a, p)` adds XP (and fires the callback);
- `H.S.date = "2026-09-28"` changes what `os.date("%Y-%m-%d")` returns; `H.S.serverTime` sets
  `ShroudServerTime`; `H.goldChange(n)`; `H.combat{ { kind = "death", fromYou = true } }`;
  `H.items({ { "Iron Ore", 5 } }, dropped)`; `H.detailRows()`; `H.S.created` counts `Add` calls,
  `H.S.constructed` every constructor call; `H.addBuffs{...}` / `H.removeBuff(name)` (buffs count down
  in `H.advance`, expired ones fire `ShroudOnBuffsChanged`; `H.S.durationMode` = nil / "elapsed" /
  "remaining" / "ms" / "nonsense" / "absent" (as in game: no fields) sets what the grouped `TotalDuration`/`CurrentDuration` hold); `H.frame()`, `H.slots("buffs")`;
  `H.S.files[path] = true` makes a texture/sound exist; `H.S.acceptMissing` makes `ShroudLoadSound`
  accept paths it can't load; `H.S.played` / `H.playedNames()`; `H.frame()` / `H.vitals()` / `H.hud()` (the glued strip); `H.combatHud()`, `H.combatRows()`,
  `H.setCombat(on)` (combat mode + callback); `H.submit(win, id, text)`;
  `H.setGuild(name, motd)` (no callback; the next tick sees it), `H.setMotd(text)` (+ `ShroudOnSocialChanged`),
  `H.motd()`;
- The first run on an account prints a one-time welcome and opens the settings window (account-scope
  saved var `welcomed`; `T.Welcome()` runs last in `ShroudOnStart`). Test boots are returning players;
  use `H.firstBoot()` for a first run.
  `/toolbox` with no argument opens the settings window (`/toolbox help` lists commands).
- `H.chat("/tbx reset")`, `H.click(window, id)`, `H.change(window, id, value)` (player input on a
  slider/toggle), `H.closeWindow(id)`, `H.moveWindow(id, x, y)`.

If you rely on a new API function, stub it in `install_api()` with the documented return values,
including the "no character" sentinel.

## Saved vars (character scope)

| Key | Shape |
| --- | --- |
| `session` | see the header comment of `xp.lua` (format `v = 1`; bump and handle old data if it changes) |
| `window` | `{ open = bool, x = number, y = number, font = 9..32, spacing = 0..12 }` |
| `compact` | `{ open = bool, x = number, y = number, hover = bool, hud = bool, hx, hy }` (hx/hy: the HUD strip) |
| `daily` | see the header comment of `daily.lua` (format `v = 1`) |
| `daily_window` | `{ open = bool, x = number, y = number, hover = bool, hud = bool, hx, hy }` |
| `daily_detail` | `{ open = bool, x = number, y = number }` |
| `buffbar` | `{ show, size = 20..48, expire, expireSeconds = 1..60, debuff, group = { "BlessingOfStamina", ... }, x, y }` |
| `sounds` | `{ volume = 0..100, paths = { buff_expiring = "...", debuff_landed = "..." } }` |
| `buff_timers` | `{ v = 2, timers = { [rune name] = { total, remaining, at = T.Now() } } }`: trusted totals, for a reload |
| `vitals` | `{ show, width = 100..400 (bar length at 100%), scale = 75..250 (%), showText, showBars, bg = "None"/"Dark"/"Light", flash, flashBelow = 1..95, x, y }` |
| `hud` | `{ glued = bool, x, y }` (the glued strip's position) |
| `combat` | `{ show, scale = 75..250, pet, stats = { "MagicResistance", ... }, bg = None/Dark/Light, bgOpacity = 10..100, x, y }` |
| `guild_motd` | `{ show = bool, seen = "text" }`: the last guild message shown to this character |
| `buff_durations` | `{ [rune name] = seconds }`: full durations learned from casts |

Keys must be <= 128 chars with no `/` or `\`. A table's JSON must stay under 256 KB. Always validate what
you read back (`Toolbox.XP.IsValid`) and fall back to defaults.

## Releasing

Bump `version` in `toolbox/manifest.json` **and** `Toolbox.version` in `core.lua` (the build checks they
match), move `[Unreleased]` notes under the new version in `CHANGELOG.md`, `make check`, test in game.
Version numbers are single-use in the store, including rejected ones.

## Planned for newer APIs

The owner's agreed plans (2026-09-27). UPDATE, same day: the client now reports API 20, while the docs
went BACK to describing API 17 and dropped the whole crafting / gathering / friends / guild group (the
"API 18" part below). So the docs no longer say what 18-20 contain. `/toolbox api` probes whether each
planned function exists in the client; run it before building anything below, and treat a function
missing from the docs as unconfirmed even when the probe finds it.
PROBED in game 2026-09-27 (build 17884de, API 20): all 5 buff bar functions, both crafting getters
(`ShroudGetRecipe`, `ShroudGetCraftingState`) and all 3 friends/guild getters exist. The result callbacks
(`ShroudOnCraftResults`, `ShroudOnGatherResults`, ...) can't be probed by existence; only by defining them
and seeing whether they are called. Feature-detect each function (`type(ShroudX) == "function"`) and keep
`min_api_version` at 14 unless a step below says otherwise. Add the new names to `.luacheckrc` and stub
them in the harness with their documented behaviour.

**API 15: sounds** (`sounds.lua`, items 23 and 24):

1. First, re-test as-is: `/toolbox sounds test`, `try 1`, `debug`. The "no clip loads" problem (23h) may
   have been the client. Until clips load and play in game, nothing below is worth doing.
2. From API 15, `ShroudLoadSound` checks the file first and returns false for a missing or empty file,
   one over 8 MB, or one whose header isn't the `AudioType` passed. So on false, try the next candidate
   at once. Keep `LOAD_TIMEOUT` for true, because decode errors are still only logged.
3. Ship the default sounds in the package. That allows up to 32 .ogg/.wav files, 2 MiB each, flat, with
   lower-case names, and no `files` entry. Bytes must start with `OggS` / `RIFF....WAVE`. To do it: move
   `art/*.ogg` into `toolbox/`, extend `build.py`'s whitelist with those limits and the header check, and
   drop the manual-install steps from README/BETA. The load path stays `"toolbox/<name>"`.
   Catch: shipping sounds needs `"min_api_version": 15`, which locks out API 14 clients. Do it only once
   the live client is on 15.
   If the experimental-encoder .ogg doesn't play (item 24), ship the .wav instead (well under 2 MiB).
4. Once sound works, remove the diagnostics: the table-entry guessing in `listSounds` (if the list is
   plain strings), `/toolbox sounds try`, and settled notes 23b to 23h.
5. Never call `ShroudListSoundReset`: the clip list is shared, and it clears every add-on's clips. A
   reload or scene change frees clips anyway, and `ShroudOnStart` loads them again.
6. Memory isn't a concern. All add-ons share a 256 MB decoded-sound budget, and our two short alerts
   use a few hundred KB. A refused load is logged, so the loader just moves to the next candidate.

**API 16: replacing the game's buff bar** (`buffbar.lua`). The point: ours can be moved anywhere, while
the game's is tied to the player frame. Don't follow the game's bar position: no `ShroudGetBuffBarRect`
docking, no `ShroudOnBuffBarMoved`.

1. "Replace the game's buff bar" setting (opt-in): `ShroudSetBuffBarVisible(false)`. The game never
   saves it and releases it on reload, disable or error-stop, so apply it in `ShroudOnStart` every time.
   Leave the game's bar visible whenever ours isn't showing (turned off, or its strip failed in
   `Hud.Build`).
2. "Click to dismiss" setting (opt-in, since the game's own bar confirms through a right-click menu).
   The slots' no-op `onClick` becomes `ShroudDismissBuff(i)`. Re-resolve `i` by name at click time,
   because the slot's index can be 0.5 s stale and indices are 0-based. Mark dismissable buffs with
   `ShroudCanDismissBuff` (a tooltip line). Report a refusal (`notNow`, `tooOften`, `gestureSpent`, ...)
   in chat. A dismissal removes every effect of the rune; `OnBuffsChanged` re-reads.
3. Harness: hiding is counted per add-on and released on reload; dismiss works only on a gesture
   (`H.click`, never `H.advance`) and shifts indices. `/toolbox buffs debug` prints
   `ShroudIsBuffBarVisible()`. New `buffbar` keys: `replaceStock`, `clickDismiss`.
4. Still missing: buff durations (item 22). Keep the learning code.
5. Ideas, not agreed yet: a "lock position" setting (only if a strip's grip can be turned off), and snap
   presets next to Reset.

**API 18: crafting and gathering** (`daily.lua`, `dailydetail.lua`). The API map says v15 for the
crafting/social getters, but the reference says "Added in API 18" for all of them and for the result
events, so gate on the functions existing, never on the version number.

1. **Crafted Today** window (`/toolbox crafted`), fed by `ShroudOnCraftResults`.
   - Header: crafts, exceptional %, failures, producer XP from crafting (Quick Craft pays none).
   - Rows: item + count made, with exceptional ("Iron Ingot 40 (3 exc)").
   - A salvage section: items salvaged and what they returned (`items`; salvage has no `recipeId`).
   - Count by `crafted`/`exceptional`/`failed`, never 1 per result: a Quick Craft result is a group.
2. **Gathered Today** window (`/toolbox gathered`), fed by `ShroudOnGatherResults`.
   - Only gathered items; header: nodes, failed harvests, producer XP from gathering.
3. **Loot window option** "Include crafted and gathered items" in the Today Detailed list.
   Default OFF (excluded).
   - `ShroudOnItemsGained` already counts crafting results and harvests (and purchases, mail, bank
     withdrawals). Keep all three tallies in the day table (`items`, `crafted`, `gathered`) and
     subtract at display time, per name, clamped at 0. Summing over the day avoids depending on
     which event fires first.
   - Salvage returns count as crafted, so they're excluded too.
   - Without the API 18 events, hide the option and subtract nothing.
   - Unconfirmed: that the result events' item names match `ShroudOnItemsGained`'s. Check in game
     with a debug line before trusting the subtraction.
4. Shape and structure:
   - Both new windows work like Today Detailed: rows appended, never rebuilt on a timer (creation
     cap); hover pop-up from new "Crafted" / "Gathered" lines in the Today window; pin like XP
     Detailed.
   - Don't spend the 16th Lua file: turn Today Detailed's list code into a reusable list window and
     make Crafted and Gathered more instances of it.
   - Day format bump (`v = 2`, old days upgrade with empty tallies); per-day name caps like
     `D.MAX_KINDS`.
   - Add `dropped` to the counts.
   - Today first; "this session" (from the XP session start) can be a header toggle later.
5. Ideas, not agreed yet:
   - ingredient have/need checklist for pinned recipes (`ShroudGetRecipe`; bags only, no bank/lot);
   - a gathering session HUD (nodes/items/XP per hour, idle timeout);
   - a crafting-station strip shown while the window is open, plus a "craft finished" sound;
   - friends/guild online list, friend-online chat line or sound, guild MOTD change in chat.

## Unconfirmed API behaviour

Things the docs don't settle. Verify in game before depending on them more heavily:

1. Whether `ShroudOnExperienceGain`'s amount tracks total or pooled XP, and whether it fires for
   producer XP from every source. We only use it as a trigger to re-read totals.
2. Whether `/lua reload` calls `ShroudOnDisableScript`, and whether it keeps the in-memory saved-var
   cache or re-reads the files. We store a changed session once per tick (in memory), re-read the
   totals in `ShroudOnStart`, and don't end the session on disable, so either way no XP is lost.
3. When `ShroudOnStart` runs relative to character login (at client start before a character exists?
   again after each login?). We wait for `ShroudGetLevelProgress()` to return non-nil before starting,
   and start a new session on the next tick after a logout.
4. Which character's scope `ShroudSetSavedVar` writes to inside `ShroudOnLogOut` (the docs say it fires
   when the login scene loads).
5. `ShroudTime` is `Time.time`: assumed continuous across `/lua reload` and logout/login within one
   client run, and restarting near 0 on relaunch. `os.time` is not documented, so it is not used.
6. `Window{ x, y }` versus the host's own per-window position memory (docs: "position and size are
   saved per add-on and window id"). We pass the saved position as `x`/`y` and never call
   `SetPosition`, to avoid fighting the host.
7. `win:GetPosition()` returning two numbers (docs: "returns left and top as laid out"). Non-numbers
   are ignored.
8. The shape of `ShroudGetLevelProgress()` at the level cap (docs: `percent` reads 0). We treat
   `percent == 0` with `intoLevel > 0` as capped and show no ETA.
9. Whether total XP can ever go down. Lower readings are treated as bad reads and ignored.
10. Whether `fontSize` is inherited from a container. We set it on every label and button.
    Also whether a `Bar` honours a `height` style (we set it to half the font size, min 4).
11. Whether the window's `width`/`height` apply once the host has remembered a size. We assume
    they don't (docs: size is "saved per add-on and window id"), so the player resizes by dragging.
12. How often a `Slider`'s `onChange` fires during a drag, and whether its value arrives as a float.
    We round it and apply each change (cheap: a few `SetStyle` calls).
13. What exactly `ShroudGetPooled*Experience()` reports ("unspent pooled XP" per the docs): the
    compact window shows it as-is and never uses it for "earned" numbers, which come from totals.
14. `onHover` on containers: whether entering a child reports "left" on the parent, and whether a
    window's title bar counts as the window. We register hover on each window and its sections and
    treat "any over" as hovering; the show/hide delays absorb flicker. If the pop-up flickers or
    won't close, this is the place to look.
15. Line height: there is no line-height style, so labels get `height`, `minHeight` and `maxHeight`
    of `ceil(1.15 * fontSize) + spacing` (`Toolbox.Window.LineStyle()`). CONFIRMED in game 2026-09-27:
    `height` alone does nothing (a theme class minimum height wins); pinning `minHeight`/`maxHeight`
    works, including live on open windows. Always size text through `LineStyle`/`TextStyle`.
    `/toolbox spacing` (no number) compares the requested height with `GetSize()`.
    Still unconfirmed: whether a height below the glyph box clips text.
16. Combat `death` lines: which of `source`/`target` is the killer, and whether `fromYou` is set on a
    death line for a kill you made. Kills count `kind == "death"` with `fromYou` or `fromYourPet` and
    neither `toYou` nor `toYourPet`. If kills stay at 0 in game, log the death events to check.
17. `os.date` in the MoonSharp sandbox: undocumented. `Toolbox.Today` feature-detects it and falls back
    to the date part of `ShroudServerTime`, whose format is also undocumented (the time of day is
    stripped with a pattern and the rest used as the key).
18. `ShroudPlayerGold` before a character is loaded or during a scene change: a 0 from a positive
    balance is ignored as a bad read, so spending exactly down to 0 under-counts the next pickup.
19. `ShroudOnItemsGained` item names as keys: assumed stable, plain display names (localized). Two
    different items with the same display name are counted together.
20. Container `Add`/`Clear` and the element-creation rate cap (~500 burst, ~200/s): the Today Detailed
    list keeps rebuilds to at most 3 x `MAX_ROWS` elements and one per `RESORT_SECONDS`. If a rebuild
    ever raises, lower `MAX_ROWS`.
21. Buff bar layout. CONFIRMED in game 2026-09-27: an `Image` overlapping another via
    `marginLeft = -size` draws on top of it (there is no absolute positioning), and an `Image` with an
    `onClick` shows its tooltip on hover (docs: it "takes the pointer only while it has a click handler").
22. Buff timers. CONFIRMED in game 2026-09-27 (`/toolbox buffs trace light`): permanent effects report
    0 left (no sweep, no alert); `ShroudGetBuffTimeRemaining` counts down smoothly (fractional seconds);
    and the grouped `Effects` entries have NO `TotalDuration`/`CurrentDuration` (nil), despite the docs.
    So a buff's full duration is only known by seeing it start: `BuffBar.Track`'s `fresh` (appeared while
    running, not in the start-up snapshot, not during a scene load) or a recast; those runs are
    `trusted` and `BuffBar.Learn` saves the length (`buff_durations`) for next time it is already
    running. Untrusted runs get no sweep. `TotalFromEffects` stays in case the fields ever appear:
    the docs may be ahead of the released client. ON HOLD by the owner (2026-09-27): don't debug the
    missing fields further; re-check `/toolbox buffs trace` after a client update.
    RE-TESTED 2026-09-27 on API 20: still `Total nil, Current nil`, and the trace says "no effects".
    New: `MoonlightWatch` read a constant 9870 s left for 10 s (it counted down smoothly before). Maybe
    only that effect (an old doc said the moon indicator reports seconds to the next moon edge); pending
    a trace of an ordinary cast buff. The bar's own end-time clock covers a stale value either way.
    Second trace, 18 min later: 6270 (was 9870), constant again for 10 s. It dropped 3600 in ~1100 real
    seconds, so it moves in coarse steps and/or not in real seconds: a moon-phase timer, not a normal buff.
    `buff_timers` is `{ v = 2, timers = ... }` holding trusted totals only; unversioned (v1) saves are
    ignored because they could hold wrong totals. Vanished buffs keep their timer for `GRACE` seconds.
23. Sounds: `ShroudLoadSound`'s path base ("the addon's Lua folder" vs the Lua root) and what clip names
    `ShroudListSound` reports. `Toolbox.Sounds` tries both bases and matches the file stem, falling back
    to "the one new clip". `/toolbox sounds` shows what was found.
23h. CONCLUDED 2026-09-27 (build 53d793b): NO CLIP LOADS in the current (DEV) client. `ShroudLuaPath` is the
    Lua root (`.../Shroud of the Avatar(DEV)/Lua`), so `toolbox_<name>.ogg` is the right path and the file is
    there; 12 accepted loads (.ogg + plain 16-bit PCM .wav, every folder); `ShroudListSound()` empty; and
    `/toolbox sounds try 1|2` -> `ShroudPlaySoundChannel` = -1 (no such clip, per docs). Not the add-on.
    Suspect the client: the docs say sounds load via a web request, and the path has spaces and parentheses
    (pictures, read directly, load fine). Toolbox keeps trying and stays silent; re-test after a client
    update with `/toolbox sounds test` / `try 1`. ON HOLD until then.
    RE-TESTED 2026-09-27 on API 20 (build 9c0ea28): still no clip (`try 1` -> -1). Still on hold.
23g. FOUND 2026-09-27 (build ac17b29): `ShroudLoadSound` returned TRUE for every path, even ones that can't
    exist, so "true" only means "request accepted" (the docs say "path exists"). After 12 accepted loads
    (.ogg and .wav, Lua root and package folder) `ShroudListSound()` stayed empty (0 keys). Either every
    load fails or the list doesn't work in this client. `/toolbox sounds try <n>` plays clip id n directly
    (id > loaded count returns -1 per docs) to tell which; the debug shows ShroudLuaPath / ShroudDataPath.
23f. 2026-09-27, build 52094c3: nothing loaded from any candidate (.ogg or .wav in Lua/). Suspect the path
    base: for sounds, "relative to the addon's Lua folder" may mean Lua/toolbox/ for a package (textures
    are Lua-root-relative; clock.png loads as "toolbox/clock.png"). Candidates now include .ogg/.wav in
    the package folder; install.py copies sounds there; debug logs every `ShroudLoadSound` answer
    ("tried <path> -> true/false"). Pending: that log from the game.
23e. RESOLVED (probably) 2026-09-27: one copy, build 34dc37a, `ShroudListSound()` empty with 0 keys, yet
    both alerts "ready" with the same table as clip: impossible in standard Lua. Most likely MoonSharp does
    not reset a bare `local found` per loop iteration. Fixed by `= nil` everywhere + a string check. The
    empty list itself means the .ogg clips never loaded (decode failure, "logged, not returned"), so the
    loader now tries `toolbox_<name>.wav` after the .ogg. Pending: does the .wav play in game?
23d. The next in-game `/toolbox sounds debug` contradicted the code (an empty list, yet both alerts "ready"
    with a TABLE as the clip, which the new code can't record). Suspects: two Toolbox copies loaded (they
    share the global `Toolbox`), or a keyed (non-array) list. `/toolbox version` now reports the build and
    the copy count (`ToolboxCopies`), and the debug dumps every key of `ShroudListSound()`.
23c. FOUND in game 2026-09-27 (`/toolbox sounds debug`): `ShroudListSound()` entries are TABLES, not the
    documented strings; both alerts had recorded the same table as their clip. `Sounds` now reads names
    via `listSounds()` (strings, a table's name/Name/clip field, or a list wrapped in one table). The exact
    shape is still unknown (the first debug lines weren't captured); the harness covers both guesses
    (`H.S.soundListShape`). Clip ids are assumed to be positions in that flattened list.
23b. REPORTED 2026-09-27: both sounds reported "ready", but Test said "the game's sound list was cleared":
    the recorded clip name wasn't in `ShroudListSound()` at play time. Either the reported name changes
    after loading, or something (the game, or another add-on's `ShroudListSoundReset`) clears the list.
    `Sounds.Play` now falls back to a base-name match; pending: `/toolbox sounds debug` output.
24. The alert .ogg files come from ffmpeg's built-in (experimental) Vorbis encoder, since libvorbis isn't
    available here. First in-game report (2026-09-27): `/toolbox sounds` found both, but Test was silent.
    Test now reports channel and whether `ShroudIsChannelPlaying` still sees it; "already silent" points
    at decoding (try the .wav), "playing" at volume. Pending that result.
    2026-09-27: .wav defaults are no longer shipped or looked for (no clip loads in either format, so they
    told us nothing); only a player's replacement may be a .wav. `art/alerts.py` still writes them locally.
25. `ShroudGetBuffTimeRemaining` refresh rate: CONFIRMED smooth in game (the trace showed it dropping
    ~1 s per second). An earlier "stale value" theory for the lagging sweep was wrong; the cause was the
    unknown full duration (item 22). `BuffBar.Track`'s own end-time clock stays (harmless: it resyncs
    every tick when the value changes), and `H.S.staleEvery` still tests it.
26. HUD frame position: docs say a HudFrame is moved by a grip (hidden while the HUD is locked; in game
    the lock is Options > Interface > Nameplates & Chat Bubbles > "Lock Status Movement", found by the
    owner 2026-09-27), is
    "remembered where the player put it", and `SetPosition` "remembers the new spot as the player's". Not
    said: whether the constructor's x/y override that memory after a reload. So the buff bar also keeps
    `buffbar.x/y` (polled every tick) and builds at them; either way it comes back where it was.
27. Player vitals. FOUND in game 2026-09-27 (`/toolbox stats health|focus|vigor`): readable stats
    `CurrentHealth` 943 / `Health` 942.23 and `CurrentFocus` 700 / `Focus` 700 at full, so `Health` and
    `Focus` are taken as the maximums (unconfirmed while damaged: `CurrentHealth` should drop while `Health`
    stays). No stat matches "vigor" by name or label, so no vigor bar. REPORTED 2026-09-27: the bars
    showed "--" (seen as "~") and stayed empty, i.e. the per-frame globals weren't numbers; the bars now
    fall back to the `CurrentHealth` / `CurrentFocus` stats. CONFIRMED in game 2026-09-27: with the
    fallback the bars show; `/toolbox vitals debug` showed `ShroudPlayerCurrentHealth` and
    `ShroudPlayerCurrentFocus` are nil. Keep both sources: the globals are documented and may start
    working when the client catches up with the docs.
28. Other per-frame globals in use: `ShroudTime` works (sessions, buff sweeps). `ShroudPlayerGold` (daily
    "gold picked up") is in the same documented group as the nil vitals globals; if it is nil too, daily
    gold never counts. Asked the owner 2026-09-27 to check and run `/toolbox stats gold` for a fallback.
    `ShroudServerTime` is only the daily reset's fallback clock (os.date is used first).
29. Theme classes `inset` / `card`: the docs say they "apply the game's own look" but not which is darker.
    In game (2026-09-27) `inset` gives a dark panel behind a label, `card` shows NOTHING. So Light is a panel
    in the theme colour `@text` on a wrapper Row (a colour set on the label can't be unset and would cover
    the inset class), with `V.DARK_TEXT` numbers (the theme has no dark text token).
30. HUD drag grip size: not documented. REPORTED 2026-09-27: it covered the first number of the vitals
    strip. HUD strips now wrap their contents in a Column with `paddingLeft = Toolbox.Window.GRIP` (14 px,
    an estimate; adjust if the grip still overlaps or the gap looks too big). Add-ons can't tell whether
    the grip is shown (Lock Status Movement), so the room is always kept.
31. HUD frames are kept on screen by the game using their FULL size, including empty space. A buff strip
    sized for all 20 slots couldn't be dragged near the right edge (reported 2026-09-27). Size HUD strips
    to what they show (`fitFrame` in buffbar.lua) and re-fit when that changes.
32. Glued HUD. CONFIRMED in game 2026-09-27: destroying HUD frames and rebuilding them (same ids when
    unglued again) on `Hud.SetGlued` works, and the shared strip lays out and moves as one. Hiding a
    module's content inside it uses `SetVisible` (hidden elements take no space).
33. Combat events: damage out = `fromYou` (or `fromYourPet`, optional) lines of kind hit / critical /
    glancing / ultraslay; taken = `toYou` (not from you) damage kinds; avoided = `toYou` dodge / parry /
    block. Assumed: `amount` is the damage number for those kinds (docs: "the number the line prints").
    Player defensive stat names beyond `MagicResistance` aren't documented: the stat list is the player's
    (`/toolbox combat stat add`), found with `/toolbox stats`.
34. Theme backgrounds: no theme background colour is documented (`@name` tokens are the theme's
    `--sota-name` colours, but only text-type names are listed; `ShroudGetClientInfo().theme` is just a
    name). Panels use the `inset` class (dark) or `@text` (light). A panel's opacity must not fade the
    text, so it is built from per-row slabs under the content, and Dark/Light are separate slabs (an
    inline colour can't be unset). See combat.lua's `applyBackground`.
    REPORTED 2026-09-27: a line showed between every row of the Dark panel, still there with zero margins and
    `borderWidth = 0` (build d271fb2): the `inset` look has shaded edges of its own. Dark is now a flat
    `#000000` + alpha background on the rows' parent (a colour's alpha doesn't fade children, unlike
    `opacity`), so no slabs; Light keeps its `@text` slabs (a token has no alpha). CONFIRMED in game
    2026-09-27 (build 9c0ea28): the lines are gone.
35. MARGINS ARE CLAMPED to -64..256 and paddings to 0..256 (docs: "every value is clamped to a sensible
    range"). An overlap by negative margin only works up to 64 px: a whole-strip panel overlapped by
    -width pushed the combat rows out of view in game (2026-09-27). Overlap per line/icon instead. The
    harness clamps the same way (`clampStyle`), so such layouts fail the tests.
36. Element ids: the docs give the allowed characters but not whether ids must be unique within a window
    or frame. Don't repeat ids (the combat rows briefly used "line" 14 times while the strip was missing
    in game; unconfirmed whether that was a cause). `Hud.Build` builds each module in a pcall and reports
    failures, so one broken strip can't hide the others; `Hud.Debug(key)` backs `/toolbox combat debug`.
37. CONFIRMED in game 2026-09-27: MoonSharp passes explicit nil table entries to the host; `Shroud.UI`
    style validation rejects them. (Window x/y = nil happened to be accepted, but specs now use
    `Toolbox.Window.DEFAULT_X/Y`.) The earlier "combat strip missing" reports were this error, first
    after the background change; the -64 margin clamp (item 35) was a real but separate problem.
38. Key binding: `Shroud.Keybind{ id = "settings", ... key = "Ctrl+Semicolon" }` toggles the settings window.
    Shift is never a modifier (docs), so the owner's Ctrl+Shift+; became Ctrl+;. "Semicolon" isn't in the
    docs' examples ("Minus", "Comma", "Slash"...); an unusable key raises, so `T.RegisterKeybind` retries
    without a suggestion and `/toolbox key` explains. Unconfirmed in game: the name, and whether the game
    already uses Ctrl+;. The player changes keys in the add-on manager (Toolbox's row, "Keys").
    REPORTED 2026-09-27: shown as bound in the add-on manager, but Ctrl+; did nothing. `/toolbox key` now
    counts presses (0 = never delivered). RESULT: 0 presses for the suggested "Ctrl+Semicolon", but the
    owner setting Ctrl+Shift+; in the add-on manager WORKS, so Shift IS usable (docs wrong). Suggestions
    are now tried in order `T.KEY_SUGGESTIONS` = Ctrl+Shift+Semicolon, Ctrl+Semicolon. Pending: the exact
    key string the game reports for the player-set binding (`/toolbox key`), to use as the suggestion.
39. Label side margins: labels carry side margins from the theme unless set. FOUND in game 2026-09-27
    (`/toolbox combat debug`): a combat row laid out ~8 px wider than name + value + padding, so the values
    sat on the panel's right edge. Set `marginLeft`/`marginRight` = 0 on labels whose widths must add up.
    CONFIRMED 2026-09-27 (build 7dd58a5): with both at 0 the combat values sit inside the panel.
40. Hover on HUD strips: the docs list `onHover` for every element and say a HudFrame's empty parts pass
    clicks through, but not whether hover reaches a strip's panel and rows. The XP / Today strips report
    hover on their panel and each row (`t:hud`, `t:hud_<id>`). Unconfirmed in game: if the pop-up never
    appears over a strip, this is the place to look.
41. Guild message of the day (`ShroudGetSocialSummary().guildMotd`, API 14). Unconfirmed in game: whether it
    is "" (or the summary nil / `inGuild` false) until the guild data loads after login; an empty message is
    never treated as new, so a late load just shows on a later tick. Also whether the text carries markup
    (shown as plain text) and whether `ShroudOnSocialChanged` fires when the data first loads (the 1 s tick
    checks too, so it doesn't matter).
