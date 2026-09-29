# AGENTS.md

Guidance for AI coding agents (and humans) working on Toolbox, a Shroud of the Avatar Lua add-on.

## Hard rules

- **Clean-room.** Do not copy or adapt code from OCX Tools or any other existing add-on. Work only
  from the official docs:
  - https://catnipgames.net/lua/agent.html (dense API map; read first)
  - https://catnipgames.net/lua/reference.html (full reference)
  - https://catnipgames.net/lua/guide.html (packaging, sandbox, store)
- **Target Lua API 23 on MoonSharp (Lua 5.2 semantics)** (`min_api_version` 23 since 0.5.0, 2026-09-29: the
  live client's version; was 15, for package sounds; newer functions are still feature-detected). No 5.3+ features: no integer division
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
  `name = ... or nil` table entries. Setting a field to nil does NOT remove it either: an IconButton
  spec with `spec.width, spec.height = nil, nil` was refused in game ("IconButton has no field 'height'",
  2026-09-28). Build a new table instead; `tools/build.py` refuses `spec.x = nil` / `style.x = nil`.
- **No lazy `.-` patterns on text that can be long.** MoonSharp raises "pattern too complex" where
  standard Lua copes: the trim `"^%s*(.-)%s*$"` on a long buff description stopped the buff bar's
  timer and got Toolbox disabled (2026-09-28). Use `Toolbox.Trim` / `Toolbox.ParseArgs` or plain
  `find`/`sub`. `tools/build.py` refuses a `(.-)` capture anchored with `$`; the harness raises the
  same error for any `.-` pattern on text over 120 characters.
- **Game data may be userdata, not tables.** `ShroudGetPlayerBuff()` entries are C# objects in game
  (2026-09-28), despite the docs; `type(x) == "table"` checks silently skipped them. Read fields by name
  through a pcall'd accessor (see `BB.ReadRunes`), never `pairs` over game objects. The harness can
  return such objects (`H.S.buffObjects`; real userdata on LuaJIT).
- **The price site is "SotANET" (its name) or "shroudoftheavatar.net" (its domain), never "SOTA.net"**: that
  is a different domain (owner, 2026-09-29). `tools/build.py` refuses "sota.net" in package files.
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
- **Be cheap per tick; leave room for other add-ons.** Garbage lands on the heap every add-on (and the
  game) shares, and every UI call crosses into the game's UI. In anything that runs every tick: set UI
  through `Toolbox.SetText` / `SetTooltip` / `SetVisible` / `SetValue` / `SetStyle` (they skip calls that
  change nothing; don't mix them with direct calls for the same element and property), reuse tables
  instead of building new ones, keep sort comparators and closures out of loops, and rebuild derived
  data (charts, tooltips) only when its inputs change. `tests/test_perf.lua` holds the budgets (a
  minute with every window open, idle and in combat); after the 2026-09-28 pass: idle ~4 UI calls/s and
  ~6 KB/s of garbage, combat ~28 and ~31 KB/s.
- Constructors (`Shroud.UI.*`, `Shroud.Command`) raise at file top level. Call them from
  `ShroudOnStart` or later. Reading `Shroud.UI` at top level is fine.

## Commands

```sh
python3 tools/check.py     # all of the below, on any OS (tests under every Lua found); --container too
luacheck .                 # must be clean
lua tests/run.lua          # must pass (also: luajit tests/run.lua; filter: lua tests/run.lua reload)
python3 tools/build.py     # must succeed; --check validates only
make check                 # = tools/check.py
python3 tools/install.py --lua-dir "<game Lua folder>"   # local in-game testing
```

Run `tools/check.py` (or all three) before calling a change done. Contributor setup per OS, and the
dev container (`tools/container/Containerfile`), are in CONTRIBUTING.md; keep it current.

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
  - `ui.lua` also draws the last-hour chart per track (`W.CHART_*`, pure `XP.Series` over the samples,
    bottom-aligned columns like Combat Detailed's timeline).
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
  - `dailydetail.lua`: `Toolbox.DailyDetail`, the Today Detailed window. `DD.Refresh` redraws the list, counts and values
    only when `Daily.itemsVersion`, `Prices.version`, the values setting or the day changed, the window opened,
    or `DD.FULL_EVERY` passed (the catch-all also re-queues prices past their age); otherwise just the value
    line. Item rows are never rebuilt on a
    timer (element-creation cap; no reorder API): new names are appended, and a sorted rebuild happens
    only when the window is shown, the rows are out of order, and `RESORT_SECONDS` have passed.
    Rows have no ids (item names aren't valid ids); handles are kept in a Lua table.
    Also `Toolbox.Prices` (bottom of the file): optional estimated values (`daily_detail.values`) from
    SotANET's `GET /api/v1/receipts/prices?item=..` (<= 50 names, `avg90d` null = no sales) via
    `ShroudHttpGet` (manifest `permissions: ["network"]`, `network_hosts: ["shroudoftheavatar.net"]`;
    the player must also switch Internet on in the add-on manager). Names are queued by `RefreshValues`
    (only while the window shows), sent one request at a time `P.GAP` apart from `P.Tick` (core Tick),
    answered in core's `ShroudOnHttpResponse` -> `P.OnResponse`; cached per account for `P.MAX_AGE` (24 h)
    by `Toolbox.Clock()` (os.time, feature-detected; without it, until local midnight), `P.Fresh`;
    `/toolbox dd values refresh` = `P.Forget`. Harness: `H.S.clock` / `H.S.noClock` drive os.time.
    JSON via `Toolbox.JsonDecode` (core.lua; the sandbox has none), URLs via `Toolbox.UrlEncode`.
    `/toolbox dd values test [item]` (`P.Test`/`P.Report`): one lookup regardless of the setting, each step
    (refusal reason, HTTP error, price) printed in chat; the first thing to run in game.
  - `sounds.lua`: `Toolbox.Sounds`. `Play(key)` for `buff_expiring` / `debuff_landed`. Loading walks
    candidate paths (custom, `toolbox_<file>` loose in Lua/ (.ogg, .wav), the shipped `toolbox/<file>`); each gets
    `LOAD_TIMEOUT` s to appear in `ShroudListSound()` (loads are async and "accepted" isn't "found").
    Clips are found by *name* at play time (ids are list positions; `ShroudListSoundReset` clears it).
    Never name a Lua function `load`: the loader/reviewer scan source text for `load(`.
  - `buffbar.lua`: `Toolbox.BuffBar`. Model functions (`Track`, `Frame`, `FrameUV`, `NewNames`) are pure.
    `OnBuffsChanged` reads `ShroudGetPlayerBuff()` (debuff flags, icons) and raises the debuff alert;
    its own 0.5 s periodic reads the flat effect list, runs the expiry alert and fills a fixed slot pool
    (never create elements per change). Each row is sorted by time left every tick (`SortByExpiry`: soonest
    left, permanent ones last, ties by name; the group slot always after them). A buff goes into one extra
    "group" slot (count label over the first one's icon, list + time left in the tooltip) when it has more
    than `BB.GroupAfter()` left (`groupAfter`, default 900 s; permanent effects never) or its rune or
    displayed name contains a `prefs.group` part (power-user extra, empty by default; saved lists equal
    to an earlier default, `GROUP_OLD_DEFAULTS`, are cleared). Grouped buffs still get expiry alerts.
    `BB.GroupAfter()` is the one place to read the game's own buff bar setting once add-ons can read
    game settings (requested 2026-09-28; function name unknown); the player's choice then applies only
    when the game's can't be read.
    CONFIRMED in game 2026-09-27 (build bca2d21): the seven potions collapse into one slot with the count,
    and the hover list shows. The count's dark outline is faked (no outline/shadow style exists): four
    `#000000` copies nudged 1 px by padding (`BB.COUNT_OUTLINE`), the bright label last so it draws on top.
    `IsEnabled()` is the "Show buff bar" setting; `IsShown()` (what Hud asks) adds `combatOnly`: shown in
    combat (`OnCombatMode` from core's `ShroudOnCombatModeChanged`), `COMBAT_LINGER` s after, or while the
    settings window is open (to place it). `Tick` refreshes the HUD when `IsShown()` changes.
    `OnBuffsChanged(from)` runs from core's `ShroudOnBuffsChanged` ("event") AND from `Tick` whenever a
    name comes or goes ("tick"): the debuff alert didn't sound in game (2026-09-28), so it no longer
    depends on the callback. `BB.changes` counts both for `/toolbox buffs debug`. The callback DOES
    arrive (debug, 2026-09-28: 83 from the event, 15 from the tick), so the suspect is `IsDebuff` not
    set on debuffs. FOUND 2026-09-28: a live debuff (`WolfSpecialAttack2`, "-0.1 Move Speed") showed NO
    "(debuff)" marker. Together with "no effects" on every trace, suspect `ShroudGetPlayerBuff()` RuneNames
    not matching `ShroudGetBuffName` (every lookup by name missing). `/toolbox buffs raw` dumps that list
    and the match count. ROOT CAUSE (2026-09-28, `/toolbox buffs raw`): the entries are USERDATA
    ("LuaManager+RuneEffects"), not the documented tables, and every `type(x) == "table"` check skipped
    them: 15 entries, 0 read. `BB.ReadRunes` now copies the documented fields through a pcall'd
    accessor (`Effects` may be a game-side list: `Count`, 0- or 1-based). CONFIRMED in game 2026-09-28
    (build 954a6a5, `/toolbox buffs raw`): 14 of 14 read and matched; `IsDebuff=true` on the wolf's
    MoveSpeed debuff; `TotalDuration` = full seconds, `CurrentDuration` = seconds LEFT (e.g. 601984.5 of
    604800), `TotalTick` = total; the moon timer reports `TotalDuration=0` (falls back to learning).
    Display names (`BB.PlainLabel`): colour codes stripped, first line only, at most `LABEL_MAX` (60).
    `HidesGlued()` (an optional Hud module method): hiding out of combat hides the whole glued strip,
    health & focus bars included (owner, 2026-09-28).
    API 16 (feature-detected, `CanReplace`/`CanDismiss`): `replaceStock` hides the game's bar only while ours
    is shown and built (`applyStock`, end of every tick; the game releases a hide on reload), and restores it
    otherwise. `clickDismiss`: a slot's icon `onClick` re-finds the index by name, then `ShroudDismissBuff`;
    refusals go to chat; dismissable buffs get a "Click to dismiss" tooltip line. The clock overlay is a holder
    `Row` over the icon via a negative left margin (`BB.SweepHolder`), holding one `Image` of `clock.png` (`CLOCK`
    must match `art/clock.py`) that is REPLACED for every new frame, with `uv` in its spec: this client draws an
    Image's UV only at creation (item 48). `fill` only records the wanted frame; `drawSweeps` then draws the
    pending ones most urgent first (turning red, then the most frames behind), at most `BB.SWEEP_RATE` (8; was 4, raised by the owner: rarely 12+ icons at once) new
    Images a second for all sweeps (a token bucket, `BB.SWEEP_BURST` deep; owner 2026-09-28) (`BB.ShowFrame` /
    `BB.HideFrame`, shared with the equipment bar, which retries on `G.Tick`). `/toolbox buffs frame <k> [red]`
    holds one frame on every icon; `/toolbox buffs uvtest` shows six ways of stepping frames side by side.
    The file also holds `Toolbox.Consumables` (K; bottom of the file): food (`RuneFood_...`) and Obsidian potions
    (`BlessingOf...`) by rune name (`BB.ConsumableKind`, pure; `POT_Blessing_*` / `Rune_Reward_Blessing_Shrine_*`
    are shrine blessings, NOT potions, owner 2026-09-28), plus player-added name parts (`extra`). `BB.Tick` routes
    them (`K.Takes`) to `K.Fill` instead of the buff rows (owner: move them off the buff bar); they use the same
    `fill` (sweep, warn, flash) and `slots.consumables` pool, so size, frame test and dismiss apply. Own strip
    ("consumables", after "buffs" in `Hud.ORDER`; `K.Wanted` = on and not glued) or, glued, a row built by
    `BB.BuildContent` under the debuffs and above the equipment row (`K.GluedCount` in `fitFrame`).
    The file also holds `Toolbox.Gear` (in it to reuse the clock sweep and not spend the 16th Lua file):
    the equipment bar (HUD module "gear", `G.SLOTS` fixed slots; worn items below `threshold`, lowest
    first, all while settings are open) and the model for the "durability" notification source
    (`G.Read`, `G.Stage`, `G.Notice` are pure). No event fires on wear, so `G.Tick` reads
    `ShroudGetEquipmentItems()` every `G.POLL` s (and whenever settings open or close). The notification
    source uses that reading (`G.Latest`), never a new one; a stage change in a reading calls
    `Toolbox.Notify.Check()` at once. Icons use the
    buff bar's `size()`; `BB.SetSize` calls `G.ApplySize`. `glue` (owner, 2026-09-28): while the buff bar
    is on, `BB.BuildContent` adds `G.BuildRow()` as a third row under the debuffs, `fitFrame` counts it
    (`G.GluedCount`), and the gear strip isn't built (`G.Wanted`, an optional Hud module method checked by
    `present()`). Changing glue, or the buff bar's on/off while glued, rebuilds the HUD (`Hud.Build`).
  - `vitals.lua`: `Toolbox.Vitals`, the health & focus bars (HUD). `V.Format` is pure. Every size comes
    from `V.Metrics()` (one scale factor; Shroud.UI has no zoom), applied at build and by `applySize`. Reads the
    per-frame globals directly (never through a name built at runtime: review treats that like code
    loading) and the `Health` / `Focus` stats as maximums.
    A third bar, Vigor (API 20, built 2026-09-28; `V.BARS` entry with `vigor = true`, `@gold`): `ShroudGetVigor()`
    read in `V.Init`, kept from core's `ShroudOnVigorChanged` (`V.OnVigorChanged`) and re-read every
    `V.VIGOR_POLL` s; `V.ReadVigor` / `V.FormatVigor` are pure, formatted once per reading (not per 0.2 s tick).
    Its row (`vigor_row`) hides while there is no reading (below Vigor's level; nil) or `prefs.vigor` is off,
    and `V.Metrics` counts only shown rows. Vigor never flashes. Feature-detected: `V.HasVigor()`.
  - `combat.lua`: `Toolbox.Combat`, the combat stats HUD. Fight model (`NewFight`, `Add`, `Rates`, `CritPct`,
    `AvoidPct`, and `NewSession`, `TopRunes`, `Timeline`, `OverhealPct`, `SessionDuration`) is pure: each fight
    and the session (every fight since start/reset) keep per-skill stats (`runes`, by runeId), overheal, and
    the session a `C.SLICE`-second damage timeline. `Toolbox.Combat.Detail` (bottom of the file) is the
    Combat Detailed window: fixed pools of skill rows (`Bar`) and timeline columns (heights via `SetStyle`),
    a hover pop-up of the HUD (`T.Hover`, keys "t:hud"/"t:row<i>") or pinned. Also per target (`targets`,
    keyed `C.TargetKey(targetKey, name)` since keys restart per scene; a "death" line marks the kill,
    `TopTargets`) and per damage type (`types.out` / `types.taken`, `Types`; fixed colours
    `CD.TYPE_COLORS`, as the theme has none). The session's `history`: the last `C.HISTORY` finished fights
    (`C.Summary` / `C.Remember` in `endFight`), shown as DPS bars. Fed by `ShroudOnCombatEvents` and `ShroudOnCombatModeChanged` (both in core.lua).
    A fixed pool of label rows is built once; `Rows()` decides what they show.
  - `hud.lua`: `Toolbox.Hud` owns every HUD strip. A HUD module registers (`Hud.Register(key, module)`)
    and implements `FRAME_ID`, `HOME`, `BuildContent()`, `ContentSize()`, `IsShown()`,
    `GetSavedPosition()` / `SavePosition(x, y)`; it never creates a HudFrame itself. `Hud.Build()` makes
    one strip per module, or one shared "toolbox_hud" strip in `Hud.ORDER` when glued (rebuilt on
    `Hud.SetGlued`); only modules in `Hud.GLUE` share it, others (combat) keep their own strip. Call `Hud.Refresh()` when a module's content size or shown state changes; `Hud.Tick()`
    (1 s) remembers positions (per module unglued, `hud.x/y` glued). Movers: `Hud.MoverFor(key, home)`.
    HUD FRAMES: at most 8 per add-on (docs; the harness enforces `H.MAX_HUD_FRAMES`). Strips: vitals, buffs,
    consumables, combat, gear, xp, daily, notify = 8 with all on; a module's optional `Wanted()` keeps a strip
    unbuilt when not in use (the XP / Today strips only in their HUD form, consumables / gear when glued or off),
    and `Hud.Build(true)` builds what is missing and destroys what is no longer wanted. A new strip needs a slot.
    `Unbuilt()` (optional, but every module holding elements must have it): called when its content is
    destroyed (a full rebuild, a strip no longer wanted, a build that failed part way); the module drops
    every element it holds and its updates skip until `BuildContent` runs again. Missing it meant "this Row
    was destroyed" (2026-09-29: the consumables bar switched off). The buff bar drops the consumables /
    equipment rows it built itself (`K.inBuffBar` / `G.inBuffBar`), whatever the glue settings are by then.
    The harness destroys whole element trees (Destroy, container Clear) and raises on any call to a
    destroyed element, as the game does.
    `Hud.TextStrip(spec)` is the HUD form of the XP and Today windows (`prefs.hud`, `/toolbox xp hud`):
    a module registered from `Compact.Init` / `Daily.InitWindow` (they load before hud.lua, so never at
    top level), with labels under the window's ids; those modules write to `active()`, whichever form is in use.
  - HUD strips share `Toolbox.Window.HudMover(getFrame, home, homeFn)` (Get/MoveTo/Nudge/Reset),
    `Toolbox.Config.PositionRows(prefix, module)` and `Toolbox.MoveCommand(module, cmd, name, args)`.
  - `changelog.lua`: GENERATED by `tools/build.py` from CHANGELOG.md (`Toolbox.CHANGELOG`, `{ kind, text }`
    rows). Never edit it; edit CHANGELOG.md and run `make check`. CHANGELOG text lands in a package file, so
    the source checks apply to it: don't quote refused patterns there (runtime loading, "or nil" entries).
    The package allows 16 Lua files and has 15: prefer adding code to an existing file.
  - `docs.lua`: `Toolbox.Docs`, the Docs window (one topic at a time from the `docs_pick` dropdown: each
    `D.SECTIONS` heading, then `D.COMMANDS_TOPIC`; built when first picked, `D.ShowTopic`), and the version window (`/toolbox version`, `OpenVersion`:
    one version's changes at a time from the `version_pick` dropdown, each built when first picked;
    `D.ChangelogVersions` splits `Toolbox.CHANGELOG` per version, pure),
    and `Toolbox.Notify`, notifications (`/toolbox notify`, `/toolbox motd`), built to grow in three parts:
    `N.SOURCES` (key, label, tip, default, `Check(seen, ctx)` -> notice `{ title?, text, seen }` or nil, plus
    an optional quiet value; `countCheck` / `flagCheck` build the common kinds), `N.DELIVERY` (by name: "window", one "Notifications" window with a fixed section per source; "hud"; "chat",
    a chat line each; plus a per-source `sound` flag: the "notify" sound once per check that delivered one of
    its notices. The settings dropdown shows `N.Choices()`: each via, and each "+ sound"), and `N.Check` (tick,
    `ShroudOnStart`, `ShroudOnSocialChanged`, `ShroudOnNotificationsChanged`), which remembers a notice
    as seen only once delivered. Off sources are tracked quietly; `N.SETTLE` s after start or a character
    change, counts going down aren't remembered (they read 0 while loading). Settings: `C.NotifySection`
    builds a toggle + delivery dropdown per source (ids `notify_<key>`, `notify_<key>_via`).
    Delivery "hud" = `Toolbox.Notify.Hud` (NH), a `Toolbox.Hud` module (key "notify", own strip): a fixed
    pool of `KEEP` nowrap labels (ids `nh_<i>`) in a Scroll `LINES` lines high, refilled from `history`
    (newest first; saved `notify_history`) on every change. `NH.IsShown`: something routed there or in
    history, and (settings open, hovered, `hideAfter` = 0, or within `hideAfter` s of the last notice);
    `NH.Tick` (end of `N.Check`) refreshes the HUD when that changes.
    `D.SECTIONS` is the player guide (update it with every
    user-facing change); the Commands part comes from `Toolbox.CommandList()`. Built on first open.
  - THE TOOLBELT (owner's name, 2026-09-29; "the main selling point"): the user-facing name for the buff bar
    with the health bars glued beside it (`Hud.SetGlued`) and the consumables / equipment bars glued under it
    (`K.SetGlue`, `G.SetGlue`). Player-facing text says "Toolbelt" ("in the Toolbelt"), never "glue"; code
    and saved vars keep the glue names. Settings category `toolbelt`, the FIRST one (`C.ToolbeltSection`,
    2026-09-29 after the second review): Show the Toolbelt (= the buff bar's `show`), only during combat (= its
    `combatOnly`), and per part (`C.TOOLBELT_PARTS`: vitals, consumables, gear) an Off / Own strip / In Toolbelt
    dropdown (`C.PlaceOf` / `C.SetPlace`; In Toolbelt also shows the part and the Toolbelt; Off keeps the glue
    choice), then the summary; `/toolbox toolbelt`. The buff bar is
    its base: with the buff bar off, the other bars fall back to their own strips.
  - `config.lua`: `Toolbox.Config`, the settings window. Controls call the owning module's setters; the
    setters call `Toolbox.Config.Sync()` so the controls follow chat commands and the close button.
    Categories (`C.CATEGORIES`, picked by the "Show" dropdown) are built the first time they are shown
    (`C.ShowCategory`), so a control may not exist yet: `Sync` uses `setValue` / `setText` / `setEnabled`,
    which skip missing ones, and every looked-up id must be in `ALL_IDS`. Controls whose feature is off are
    greyed out in `Sync` (`setEnabled`; never the ones that work regardless, like the buff alerts or the icon
    size). XP / Today: one Hidden / Window / HUD strip dropdown (`C.ModeOf` / `C.SetMode`). HUD layout holds
    the glue toggles, every strip's `PositionRows` and `C.HudSummary()`.
    To add a setting: a setter + getter on the owning module (persisted there), a control in its category,
    its id in `ALL_IDS`, a line in `Sync()` (and `setEnabled` if it depends on something), and tests in
    `tests/test_config.lua`. Harness: `H.config()` / `H.change` / `H.click` build every category first
    (`C.BuildAll`); `H.configRaw()` is the window as the player sees it; a disabled control can't be
    changed or clicked (as in game).
- `tmp/`: a local working area (scratch files, captured logs, screenshots); git-ignored and skipped by
  luacheck. Never reference it from the package, tests or tools.
- `tests/test_stress.lua`: a veteran character (every saved list at its cap), full bars (30 buffs and
  debuffs, consumables, 12 worn items to repair), heavy combat (50 lines/s, full fight history), and
  maximum saved data with corrupted entries. Budgets for UI calls, garbage (standard Lua only: LuaJIT's
  count is noisy) and elements created. `STRESS_PRINT=1 lua tests/run.lua stress` prints the numbers.
  The harness's buff getters allocate on every call, which the game doesn't on the Lua side: the full-bars
  test swaps in allocation-free ones (`quietBuffGetters`) to measure Toolbox's own garbage.
- `tests/`: `harness.lua` is a fake host (see below); `test_*.lua` suites; `run.lua` the runner.
- `art/icon.svg`: source of `toolbox/icon.png`. Re-render with
  `rsvg-convert -w 256 -h 256 art/icon.svg -o toolbox/icon.png` (keep it 256x256, well under 256 KiB).
- `art/clock.py` renders `toolbox/clock.png` (the buff bar's clock overlay sprite sheet; shipped as a
  package picture, API 13+) and `art/clock.svg`: a normal set and a red "alert fired" set of 120 frames (3 degrees each; 24 made long buffs look frozen).
  Keep its FRAMES/COLS/ROWS/SETS in sync with `BuffBar.CLOCK`.
- `toolbox/*.ogg` alert sounds (shipped in the package: API 15, so `min_api_version` is 15), generated
  by `python3 art/alerts.py [name ...]` (stdlib synthesis + ffmpeg's built-in Vorbis encoder, which plays
  fine in game; intermediate `art/*.wav`, git-ignored): `buff_expiring` (two falling bell chimes, 0.9 s)
  and `debuff_landed` (three hollow notes stepping down from high to low, E6 -> B5 -> E5, 0.8 s), and
  `notify` (two chimes rising E5 -> B5, 0.8 s: notifications with "+ sound"). Re-encoding changes the .ogg bytes (random
  stream serial) even when the audio is identical, so `git checkout` an .ogg you didn't mean to change.
  `tools/build.py` checks the documented sound rules (<= 32, <= 2 MiB, lower-case .ogg/.wav, OggS /
  RIFF....WAVE header). DEFAULTS live in the package folder (path "toolbox/<name>"); a player's
  REPLACEMENTS go in the Lua folder beside it (`Lua/toolbox_<name>`) and win (owner, 2026-09-27).
- `tools/build.py` stamps `build = "<git short commit>[+]"` into dist's core.lua (the source keeps "dev");
  `/toolbox version` shows it, to tell exactly which build is installed.
- `tools/build.py`: validates the store packaging rules and writes `dist/toolbox/` + zip. It also checks
  that the root README's opening states the manifest's `min_api_version` ("needs Lua API 15") and that
  CHANGELOG.md has a section for the manifest version. Keep the root README's feature list, the store
  description (manifest) and BETA.md's intro in step with features (they drifted; review 2026-09-29).
- `tools/install.py`: copies `dist/toolbox/` into a client's Lua folder.
- `tools/beta.py` (`make beta`): builds, then zips `toolbox/` (+ default sounds) and `INSTALL.txt`
  (= `BETA.md`, the tester guide) as `dist/toolbox-<version>-beta.zip`. Update BETA.md's known issues
  and "what to try" for every beta.
- `.luacheckrc`: std `lua52` plus the documented globals (API 14 in `api_functions`; newer ones, used
  feature-detected, in `api_probed`; callbacks in `api_callbacks`). If the docs add a function, add it
  here; never add a name that isn't in the docs.

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
  `H.setGear{ { name, durability, maxDurability }, ... }` (worn items; no callback, as in game), `H.gearFrame()`,
  `H.gearSlots()`; the harness's `SetUV` records `uvSet` but doesn't change `uv` (what is drawn), as in game:
  read a sweep through the test's `sweep(slot)`; `H.setVigor{ vigor = 64, ... }` / `H.setVigor(nil)` (+ `ShroudOnVigorChanged`; `H.S.vigor` without
  the callback); `H.setGuild(name, motd)` (no callback; the next tick sees it), `H.setMotd(text)` (+ `ShroudOnSocialChanged`),
  `H.setNotes{ unreadMail = 2, ... }` (+ `ShroudOnNotificationsChanged`), `H.notify()` (the window),
  `H.notice(key)` -> `{ shown, title, text }`; `H.nhud()` (the notification HUD), `H.nhudRow(i)` -> text,
  tooltip (nil when hidden), `H.nhudHover(over)`;
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
| `window` | `{ open = bool, x = number, y = number, font = 9..32, spacing = 0..12, net = bool }` (net: subtract XP lost) |
| `compact` | `{ open = bool, x = number, y = number, hover = bool, hud = bool, hx, hy }` (hx/hy: the HUD strip) |
| `daily` | see the header comment of `daily.lua` (format `v = 1`) |
| `daily_window` | `{ open = bool, x = number, y = number, hover = bool, hud = bool, hx, hy }` |
| `daily_detail` | `{ open = bool, x = number, y = number, values = bool, view = "looted"/"crafted"/"gathered", include = bool }` |
| `buffbar` | `{ show, size = 20..48, expire, expireSeconds = 1..60, debuff, flash, groupAfter = seconds (a GROUP_AFTER_CHOICES value, 0 = off), groupCats = { [category] = true } (always grouped), countdown = bool, countdownSecs = 5..120, group = { name parts }, replaceStock, clickDismiss, combatOnly, x, y }` |
| `sounds` | `{ volume = 0..100, paths = { buff_expiring = "...", debuff_landed = "..." } }` |
| `buff_timers` | `{ v = 3, timers = { [rune name] = { total, remaining, at = T.Now() } } }`: trusted totals, for a reload (v1/v2 ignored) |
| `vitals` | `{ show, width = 20..400 (bar length at 100%), scale = 75..250 (%), showText, showBars, bg = "None"/"Dark"/"Light", flash, flashBelow = 1..95, vigor = bool (the Vigor row), x, y }` |
| `hud` | `{ glued = bool, x, y }` (the glued strip's position) |
| `combat_detail` | `{ open = bool (pinned), x, y, scope = "fight"/"session", hover = bool }` |
| `combat` | `{ show, scale = 75..250, pet, stats = { "MagicResistance", ... }, bg = None/Dark/Light, bgOpacity = 10..100, x, y }` |
| `prices` (ACCOUNT scope) | `{ v = 1, items = { [lower item name] = { avg = n or false (no sales), sold, last = ISO date, day = Toolbox.Today() key, at = Toolbox.Clock() when known } } }`, at most `P.MAX_KEEP` |
| `notify` | `{ v = 1, sources = { [key] = { on = bool, seen = last value delivered, via = "window"/"hud"/"chat", sound = bool } } }` (keys: motd, mail, expiring, ransoms, rewards, applications, durability; durability's `seen` is a table `{ [item key] = "low"/"broken" }`, read back as string keys and values only); the older `guild_motd` `{ show, seen }` is read once to take over |
| `notify_hud` | `{ hideAfter = seconds (0 never, 5..60), x, y }` |
| `notify_history` | `{ v = 1, list = { { when = "HH:MM", title, text } } }`, newest first, at most `Notify.Hud.KEEP` (20) |
| `consumables` | `{ show = bool (default true), glue = bool, extra = { name parts, <= 20 }, cats = { [category] = true } (absent: defaults), exclude = { name parts } (absent: Scroll, Torch, Bait), max = 1..10 (icons before grouping), combatOnly = bool, x, y }` |
| `gear` | `{ show = bool, threshold = 5/10/15/20/25/30/50 (percent), glue = bool, x, y }` (the equipment bar) |
| `buff_durations` | `{ v = 2, durations = { [rune name] = seconds } }`: full durations learned from casts (unversioned ignored) |

Keys must be <= 128 chars with no `/` or `\`. A table's JSON must stay under 256 KB. Always validate what
you read back (`Toolbox.XP.IsValid`) and fall back to defaults.

## Releasing

Bump `version` in `toolbox/manifest.json` **and** `Toolbox.version` in `core.lua` (the build checks they
match), move `[Unreleased]` notes under the new version in `CHANGELOG.md`, `make check`, test in game.
Version numbers are single-use in the store, including rejected ones.

THE STORE PAGE (addons.catnipgames.net, looked at 2026-09-29) is where most players first meet Toolbox:
- The list is a grid of cards (>= 300 px wide, 3 across on a desktop): icon, **name** (shown in full), author,
  then a description clamped to 3 lines at 0.9rem (about 100-120 characters on a desktop), version, installs.
- The manifest `name` is "Toolbox: Toolbelt, HUDs, Trackers and more." (owner, 2026-09-29): the card's only text
  always shown in full, so it sells too (<= 60 characters; wraps to two lines on a desktop card). The add-on is
  still called Toolbox everywhere else; the slug stays `toolbox`. The author shown is taken from the
  submitting account (owner), not from the manifest's `author`.
- `support_url` = https://github.com/shawnbutts/toolbox (owner): a "Support" line in the Community Addons window.
  The submit dialog has its own field for it (empty there removes it). `tools/build.py` checks the documented
  form (https, lower-case host, no user/port, <= 300).
- `min_api_version`: raise it at a release to what the LIVE client reports (`/toolbox api`), never just to what
  the docs describe (the docs have run ahead of the client). Keep feature detection either way.
- That description is NOT ours: "the reviewer writes the one-paragraph description you see on each entry"
  (guide), in its own words ("This addon lets you..."), apparently from the package (README, manifest, code),
  and it mentions what an update fixed. So `toolbox/README.md` opens with the pitch in its first sentence,
  for the reviewer to echo; the manifest `description` says the same. The submission's release note shows
  under "Approved versions".
- The detail page: icon, name, author, meta, Download, the reviewer's paragraph, the file list, then our README
  under "Readme". Package pictures are NOT shown (BMS ships 11, none appear), so screenshots can't go there.
- The README renderer is simple: a list item's wrapped line becomes a new paragraph, `##` shows a level down,
  tables and `[links](...)` show as raw text, and a byte-order mark hides the title. `tools/build.py`
  (`check_store_readme`) refuses those.

Then commit ("Beta N (x.y.z)" for a beta), build from that clean commit (`make beta` for testers; the
stamp must be the commit, not `...+`), and tag it: an annotated `vX.Y.Z` tag on the release commit
(`git tag -a v0.3.0 -m "Beta 3 (0.3.0)"`), pushed with the branch (`git push origin main vX.Y.Z`),
only when the owner asks to push. Tags so far: v0.2.0 (a52051c), v0.2.1 (ae2fa1f), v0.3.0 (607dcb3), v0.3.1 (7db2a15), v0.4.0 (4b4d5a5), v0.5.0 (820df19).

## Planned for newer APIs

DOCS CHECK 2026-09-28: the docs describe **Lua API 22** and document the API 18 group again (crafting,
gathering, friends, guild), so everything below is documented now; still feature-detect each function.
What each version added (from the reference's "Added in API N" notes):
- **API 18**: `ShroudOnCraftResults`, `ShroudOnGatherResults`, `ShroudOnCraftingStateChanged`, `ShroudGetRecipe`,
  `ShroudGetCraftingState` (read only; results <= 20 per call + `dropped`); `ShroudGetFriends` ({ name, online }),
  `ShroudGetGuildMembers` ({ name, online, role }), `ShroudGetGuildMotd()` (string, "" outside a guild),
  `ShroudOnGuildMotdChanged(motd)` (checked twice a second), `ShroudOnFriendStatusChanged` /
  `ShroudOnGuildMemberStatusChanged` ({ name, online } changes, <= 50 + `dropped`; login and the list loading
  are not changes). Candidates: the guild MOTD notification could use `ShroudGetGuildMotd` +
  `ShroudOnGuildMotdChanged` instead of `ShroudGetSocialSummary().guildMotd` polling; friend / guild member
  online as notification sources.
- **API 19**: `compact = true` windows (title bar hidden until hovered ~0.7 s, laid over the content; NO
  TextField/Dropdown in them). A candidate look for the XP / Today windows (an option; check the version).
- **API 20**: `ShroudGetVigor()` / `ShroudOnVigorChanged` -> the Vigor bar (built 2026-09-28, vitals.lua).
- **API 21**: packages may ship .mp3/.aif/.aiff/.mod/.it/.s3m/.xm sounds (needs `min_api_version` 21; bytes checked
  against the extension). Toolbox ships .ogg only: nothing to do. A player's own replacement may be any format.
- **API 22**: package data files: `data_files` in the manifest (<= 16 .json, <= 256 KiB each, needs
  `min_api_version` 22), read with `ShroudLoadData(name)` (works at file top level; JSON null reads as `json.null`,
  whose library is otherwise undocumented, so `Toolbox.JsonDecode` stays). Nothing to use it for yet.
- **API 23**: buff categories (`RuneEffects.Category`, `ShroudGetBuffCategory`, `ShroudBuffCategories`); used.
- **API 24** (docs check 2026-09-29): `ShroudOnCraftResults` fixed and extended: `recipeName` = the recipe's name
  (was "Recipe: ..."), `item` = the product (was the recipe's name; our report), `made` = items produced
  (crafted = 1, made = 4 for a 4-binding craft; 0 for a failure / salvage), and `items` = everything a CRAFT put
  out too (products plus leftovers, e.g. an empty vial; was salvage only). `ShroudGetRecipe(id).results` = one
  successful craft's fixed yield `{ { name, quantity } }` (empty for a rolled result; `result` when exactly one).
  Products sit on the table until taken, so the result is "the one place to count them" (reference).
- Also in the docs now: `ShroudFlushSavedVars()` returns false when a write failed or a table passed 256 KB
  (`T.Flush` reports it in chat, at most every `T.FLUSH_WARN_EVERY` s; harness `H.S.flushFails`); an optional manifest `support_url` (a store "Support" link, any API
  version; for when the repo is public). The equipment example uses `durability / maxDurability < 0.2`, as
  `Toolbox.Gear` does; `primaryDurability` is still undefined. "Shift is not a modifier" is still written
  (item 38 found it works in game).

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

**API 15: sounds** (`sounds.lua`, item 23). ALL DONE 2026-09-28:

1. DONE 2026-09-28: sounds work in game after a client fix (item 23).
2. From API 15, `ShroudLoadSound` checks the file first and returns false for a missing or empty file,
   one over 8 MB, or one whose header isn't the `AudioType` passed. So on false, try the next candidate
   at once. Keep `LOAD_TIMEOUT` for true, because decode errors are still only logged.
3. DONE 2026-09-28 (all clients are on API 15+): ship the default sounds in the package. That allows up to 32 .ogg/.wav files, 2 MiB each, flat, with
   lower-case names, and no `files` entry. Bytes must start with `OggS` / `RIFF....WAVE`. To do it: move
   `art/*.ogg` into `toolbox/`, extend `build.py`'s whitelist with those limits and the header check, and
   drop the manual-install steps from README/BETA. The load path stays `"toolbox/<name>"`.
   Catch: shipping sounds needs `"min_api_version": 15`, which locks out API 14 clients. Do it only once
   the live client is on 15.
   If the experimental-encoder .ogg doesn't play (item 24), ship the .wav instead (well under 2 MiB).
4. DONE 2026-09-28: once sound works, remove the diagnostics: the table-entry guessing in `listSounds` (if the list is
   plain strings), `/toolbox sounds try`, and settled notes 23b to 23h.
5. Never call `ShroudListSoundReset`: the clip list is shared, and it clears every add-on's clips. A
   reload or scene change frees clips anyway, and `ShroudOnStart` loads them again.
6. Memory isn't a concern. All add-ons share a 256 MB decoded-sound budget, and our two short alerts
   use a few hundred KB. A refused load is logged, so the loader just moves to the next candidate.

**API 16: replacing the game's buff bar** (`buffbar.lua`). BUILT 2026-09-27 (items 1-3); 5 is still open. The point: ours can be moved anywhere, while
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
4. Buff durations: not missing after all (item 22 correction, 2026-09-28). Learning stays as a fallback.
5. Ideas, not agreed yet: a "lock position" setting (only if a strip's grip can be turned off), and snap
   presets next to Reset.
6. Game settings (requested from the devs 2026-09-28, not in any docs yet): if a read-only settings API
   appears (e.g. a list of settings + a getter), first use: the game's buff bar "stack buffs lasting
   longer than" option feeds `BB.GroupAfter()`, and the settings dropdown shows it as the game's value.

**Waiting on the developers (2026-09-29):**

1. **SetUV redraw bug + cooldown sweep feature request**, posted to the devs on Discord (the text is in the
   owner's `tmp/sweep-report.md`, repro `tmp/uvbug.lua`; item 48). When a client fixes SetUV (uvtest way 1
   sweeps), go back to one overlay Image per slot stepped with SetUV (`BB.ShowFrame`). If a radial fill
   (`SetFill`) or a client-run sweep (`SetSweep(start, duration)`) appears, feature-detect it in
   `BB.ShowFrame` / `BB.HideFrame` and keep the new-Image path as the fallback.
2. **Buff category metadata**: ARRIVED in API 23 (2026-09-29) and USED for the consumables bar
   (`BB.TakesConsumable`, pure; `K.Categories`, `K.HasCategories`; checkboxes `cons_cat_<Key>`; defaults Food,
   Potion, Poison, Consumable, owner: "combat focused"; `exclude` name parts Scroll/Torch/Bait because the
   Consumable category also holds scrolls, torches and bait). Unconfirmed in game: the rune names of those
   (the exclude parts are guesses; `/toolbox buffs raw` shows names and categories), and that a weapon poison
   shows as a Poison buff that isn't IsDebuff. Not used yet for the buff bar's grouping.
   CONFIRMED in game 2026-09-29 (`/toolbox buffs raw`, API 23): Category=Food (RuneFood_Pie_WolfSurprise),
   Potion (all seven Obsidian BlessingOf...), Blessing (POT_Blessing_*, Rune_Reward_Blessing_Shrine_*), Other
   (Stillness, MoonlightWatch). The docs version is `T.DOCS_API` in core.lua (and `CLIENT_API_VERSION` in
   build.py): update both with each docs check. Was: (the owner expects it). Use it to replace the name guesses: consumables
   (`BB.ConsumableKind`: food, potions, and weapon poisons, which aren't visible by name at all yet) and
   the buff bar's grouping. Keep the name rules as the fallback for older clients, and read the new field
   through `BB.ReadRunes`' userdata-safe accessor. Don't guess the field's name or values: wait for the docs.

**API 18: crafting and gathering** (`daily.lua`, `dailydetail.lua`). BUILT 2026-09-29, as views of Today
Detailed (owner: a Show dropdown Looted / Crafted / Gathered, no new windows), not separate windows. The
craft result doesn't say what was made (item = the recipe's name, `crafted` = crafts; item 50), so Crafted's
rows are the items gained while a crafting window is open (`day.crafted`), with crafts per recipe in the
view's note. The day gained `crafted`, `gathered`, `recipes`, `craft`, `gather` (filled in by
`D.Upgrade`; still `v = 1`). Looted = `items` minus `crafted` and `gathered` (`D.Looted`) unless
`include`. `D.HasResults()` (the crafting getter exists) gates the views.
REPORTED by the owner 2026-09-29: materials taken back off a station showed as made. Now an item gained at
a station is made only when `D.IsProduct` (named like a recipe crafted today, or like a craft result's
`item` once the client names the product there: `day.products`); the rest goes to `day.station` (listed
apart, not loot). `D.Reclassify` fixes days saved before that. Materials used: `day.used`, from
`ShroudGetRecipe(recipeId).ingredients` (not tools / optional) x the result's `quantity` (attempts).
Unconfirmed: that failed crafts use materials (counted as used), and the fixed `item` (the devs expected a
fix 2026-09-29). The original plan follows.
API 24 (built 2026-09-29, `addMade` / `place` in daily.lua): when a craft result has a numeric `made`, it is the
authority: `item` x `made` (or the `items` entries named by `item` or the recipe's `results`) go to `crafted` at
once, other `items` (leftovers) to `station`, and all of it to `pending` until taken off the station, where
`D.AddItems` uses `pending` up before the name rule (so nothing counts twice). `D.Looted` adds `pending` back
(counted, not yet in the bags). Items counted by name at a station BEFORE their result (`early`) are used up by
the result instead. Without `made` (clients before 24) everything works as before. `craft.dropped` /
`gather.dropped` count results the game didn't deliver (shown in the view notes). Unconfirmed in game: all of
it (the owner's client reported API 23 on 2026-09-29); `/toolbox api` shows `made` and the recipe's yield. The API map says v15 for the
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

**Other ideas, not agreed yet** (discussed with the owner 2026-09-27/28, recorded so they aren't lost).
All but the undocumented-getter ones use documented API 13/14 calls; check the docs again before
building, and remember the per-add-on budgets (8 windows, the element-creation cap, test_perf.lua).

1. **Target HUD**: your target's health (and focus) plus your debuffs on it, reusing the buff bar's
   icons and sweep. `ShroudHasTarget`, `ShroudGetTargetName`, `ShroudIsTargetDead`,
   `ShroudIsTargetHealthHidden`, `ShroudGetTargetCurrentHealth` / `MaxHealth` (and Focus),
   `ShroudGetTargetBuff*` (may be userdata like the player's list: read through `T.Field`),
   `ShroudOnTargetChanged`.
2. **Skills gained and deaths** in the XP and Today windows: skill levels gained this session / today
   (`ShroudGetSkills`, `ShroudOnSkillsChanged`) and deaths (`ShroudOnDeathChanged(isDead)`).
3. **Gear durability alert**: BUILT 2026-09-28 (`Toolbox.Gear` in buffbar.lua), with an equipment
   bar. Owner's choices: warn below 20% (setting), warn again when broken, the bar shows only items
   below the threshold.
4. **More notification deliveries**: a sound per notification source, and a chat line, as new
   `N.DELIVERY` entries plus a choice in the per-source dropdown (the system was built for this).
5. **Crafting skill tracker** (documented): crafting and gathering skills with level, effective level
   (with gear), progress to the next level, and what moved this session (`ShroudGetSkills`:
   trainedLevel / effectiveLevel / progress).
6. **Recipe book lookup** (documented): search known recipes by name or skill, sorted by required
   level, marking the ones your effective level allows; favourites filter; open the game's recipe book
   (`ShroudGetKnownRecipes`, `ShroudOnRecipesChanged`, the stock-windows API's "recipes").
7. **Crafting shopping list** (undocumented getter, present in the client): pinned recipes' ingredients
   as have / need with "can make N" (`ShroudGetRecipe`; bags and an open table only). Feature-detect it
   and grey out cleanly if it disappears. See also the crafting-station panel above.
8. **Result-event probe**: BUILT 2026-09-29. `ShroudOnCraftResults` / `ShroudOnGatherResults` /
   `ShroudOnCraftingStateChanged` (core.lua) feed `T.ProbeEvent`; `/toolbox api` (`T.ProbeLines`) reports
   counts, the first and last result's fields (userdata-safe, `T.DescribeResult`), the last items gained
   (`T.ProbeItems`) and whether the last craft's item name is among them. Pending: the owner's run in game
   (craft, harvest, open a station). Replace the probe with the real feature once the events are confirmed.
9. **Combat stat picker in settings** (AGREED for a future release, owner 2026-09-29; a nice-to-have, after the
   first public release): today choosing the combat HUD's stats is chat-only (`/toolbox stats <word>`, then
   `/toolbox combat stat add <Name>`). In the Combat category: the chosen stats listed, a text field for part
   of a stat name, a dropdown of matching stats (the `/toolbox stats` search), Add and Remove (like
   `C.NameList`). Keep the chat commands.
10. **CI**: BUILT 2026-09-29, `.github/workflows/check.yml` (GitHub Actions): `tools/check.py` on ubuntu, macOS
   and Windows (Lua + LuaJIT from apt / brew / Scoop, luacheck.exe pinned at v1.2.0 on Windows) for every
   push and pull request, plus a check that `toolbox/changelog.lua` was committed. Unverified until the
   first push (the Windows job most of all).

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
9. Whether total XP can ever go down. CONFIRMED 2026-09-28: YES. The adventurer total fell 943,678 (most
   likely XP lost on death), and since every lower reading was ignored, on both tracks, all XP tracking
   froze for 1.5 h (`/toolbox xp debug`: 1 sample, 51 ignored readings). Now each track stands alone, a
   lower reading is ignored only until it has held `XP.DROP_CONFIRM` (5 s; `XP.ConfirmDrop`, also used by
   the daily stats), and a believed loss goes into `session.offset` so it counts as no gain. Samples carry
   the losses so far (`la`/`lp`) and the day `la`/`lp`, for the "net" option (`Toolbox.Window.GetNet`):
   `XP.Gained/SessionRate/WindowGain/WindowRate/LastHour(..., net)` subtract losses in the window.
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
20. The element-creation cap (~500 burst, ~200/s) is REAL: 2026-09-28 Combat Detailed, pinned open, was
    built at start-up with everything else (714 elements) and raised "elements are being created too
    fast" in game. The harness now enforces it (token bucket `H.CREATE_BURST` / `H.CREATE_RATE`; player
    actions - chat, click, change, key press, /lua reload - refill it, as they happen at human speed).
    Budget: a plain start-up is ~370 elements (XP Detailed ~80, buff bar 100, combat HUD 75, HUD strips
    38, notification HUD 24...). Keep big windows lazy (built on first show), open pinned big windows
    after a delay (`CD.OPEN_DELAY`), open the first-run settings after `T.WELCOME_DELAY`, and draw charts
    with one element per column. XP Detailed is built on first show now (was at start-up, ~80).
    OTHER DOCUMENTED LIMITS (per add-on): 8 windows, 8 HUD frames covering <= 35% of the screen, 2,000
    elements, 64 KiB of text, nesting 24 deep. Toolbox has 7 lasting windows (XP, XP Detailed, Today,
    Today Detailed, settings, Notifications, Combat Detailed); Docs and version share the 8th (opening one
    destroys the other). The harness enforces the 8 windows (`H.MAX_WINDOWS`). A new window needs a slot.
    STILL HIT at login 2026-09-28 (the notification HUD, last in `Hud.ORDER`): the game counts more than the
    harness models, or a login builds more. So `Hud.Build` retries strips that failed with "too fast"
    quietly after `Hud.RETRY_DELAY` (up to `RETRY_MAX` times; a retry builds only the strips that are
    missing, so it costs what failed), and `ShroudOnStart` runs each module's init
    through `step()` so one failure can't stop the rest.
    HUD strip builds are atomic (`Hud.TextStrip` fills `strip.el` only once built): a half-built XP strip
    crashed its refresh every tick in game (2026-09-28). Container `Add`/`Clear` and the element-creation rate cap: the Today Detailed
    list keeps rebuilds to at most 3 x `MAX_ROWS` elements and one per `RESORT_SECONDS`. If a rebuild
    ever raises, lower `MAX_ROWS`.
21. Buff bar layout. CONFIRMED in game 2026-09-27: an `Image` overlapping another via
    `marginLeft = -size` draws on top of it (there is no absolute positioning), and an `Image` with an
    `onClick` shows its tooltip on hover (docs: it "takes the pointer only while it has a click handler").
22. Buff timers. CONFIRMED in game 2026-09-27 (`/toolbox buffs trace light`): permanent effects report
    0 left (no sweep, no alert); `ShroudGetBuffTimeRemaining` counts down smoothly (fractional seconds);
    and the grouped `Effects` entries have NO `TotalDuration`/`CurrentDuration` (nil), despite the docs.
    CORRECTION 2026-09-28: they were there all along. The entries are userdata and our table checks
    skipped them (see `BB.ReadRunes`); read properly, `TotalDuration` is the full length and
    `CurrentDuration` the time left, so sweeps come "from the game". Learning stays as the fallback
    (effects with `TotalDuration = 0`, like the moon timer). The paragraph below is history.
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
    FOUND in game 2026-09-28 ("sweep doesn't match the game's"): buffs that load in after login were taken
    for casts (the start-up snapshot was empty, the scene quiet window only 3 s), so time left at login was
    learned as the full duration: seven potions "learned" 300418..300435 s, each exactly 2416 s more than
    its time left. Fix: newly seen buffs are never `fresh` within `BB.SETTLE` (15 s) of start, a scene
    change or a player-name change, nor when 2+ names are new in one tick (`lastSeen`). Old learned data
    is dropped by versioning: `buff_durations` v2 and `buff_timers` v3.
    Vanished buffs keep their timer for `GRACE` seconds.
    2026-09-28: `TotalFromEffects` now reads only that confirmed shape (seconds; CurrentDuration = time left)
    and takes the effect whose time left matches the rune's, not the longest total that fitted any guess
    (ms, elapsed): another effect of the same rune could set the sweep's length (a candidate cause of the
    sweep being out of step with the game's bar). Still unknown: which effect's time the GAME's bar shows for
    a rune with several (ours: the longest-running, `readEffects`). `/toolbox buffs trace <name>` shows both.
    FOUND in game 2026-09-28 (trace of Light: our total 127.2 = the game's 127.171, time left within a tick):
    the timing was right; the DRAWING lagged ("lines up after /lua reload, then lags"). `BB.Frame` rounded
    down (up to a frame behind: 1/120 of the buff) and a frame stays up a whole tick. Now the nearest frame,
    for `BB.SWEEP_LEAD` (half a tick) ahead. Pending: the owner's check in game. If long buffs still look
    steppy, the next step is a finer clock sheet (e.g. 360 frames at 32 px: 1024 px/side and 256 KiB limits).
23. Sounds. SETTLED 2026-09-28. Paths are relative to the Lua root (`ShroudLuaPath`; a package's own
    sounds are "toolbox/<name>.ogg"). `ShroudLoadSound` answers false for a missing / empty / wrong-format
    file (API 15) and true when the load starts (async; failures only in Player.log). `ShroudListSound()`
    is a list of plain strings, the file's base name, in load order (the clip id is the position). The
    ffmpeg-encoded .ogg plays. History: until a client fix on 2026-09-28, every macOS load failed in the
    client (`Curl error 7 ... localhost port 443` / "Cannot connect to destination host" in
    `~/Library/Logs/Catnip Games/Shroud of the Avatar(DEV)/Player.log`: a local path sent to UnityWebRequest
    without `file://`). If sounds ever go silent again, look in Player.log first.
24. (Merged into 23.)
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
    2026-09-28: Vigor is readable after all, through its own API 20 getter (`ShroudGetVigor`), not a stat:
    the Vigor bar is built on that. Unconfirmed in game: the look, that `percent` matches the game's bar, and
    that the bonuses read as whole percent (shown as given).
28. Other per-frame globals in use: `ShroudTime` works (sessions, buff sweeps). `ShroudPlayerGold` (daily
    "gold picked up") is in the same documented group as the nil vitals globals; if it is nil too, daily
    gold never counts. Asked the owner 2026-09-27 to check and run `/toolbox stats gold` for a fallback.
    `ShroudServerTime` is only the daily reset's fallback clock (os.date is used first).
    CONFIRMED 2026-09-29: `ShroudPlayerGold` works (Today's gold rose 0 -> 8 when the owner looted 8 gold);
    only `ShroudPlayerCurrentHealth` / `ShroudPlayerCurrentFocus` are nil (reported, tmp/client-issues.md).
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
33. Combat events are read through `Toolbox.ReadEvents` (core.lua) into plain tables before anything
    uses them: game data may be userdata (see the buff list, item 22), and `Combat.OnEvents` /
    `Daily.OnCombat` skipped anything not a table. `/toolbox combat events [n]` prints the next events'
    fields (API 17 adds rune, runeId, damageType, dot, overheal, time, sourceKey, targetKey); pending in
    game. Combat events: damage out = `fromYou` (or `fromYourPet`, optional) lines of kind hit / critical /
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
    owner setting Ctrl+Shift+; in the add-on manager works (see the correction below: it is recorded as Ctrl+;). Suggestions
    are now tried in order `T.KEY_SUGGESTIONS` = Ctrl+Shift+Semicolon, Ctrl+Semicolon. Pending: the exact
    key string the game reports for the player-set binding (`/toolbox key`), to use as the suggestion.
    CORRECTED 2026-09-29 (owner): the player-set binding is recorded as "Ctrl + ;": Shift ISN'T a modifier
    (the docs are right; it was dropped). `T.KEY_SUGGESTIONS` = { "Ctrl+Semicolon" } only. Still unexplained:
    the earlier 0 presses for the suggested Ctrl+Semicolon (perhaps Ctrl+Shift+; was pressed, or another
    binding had it); re-test with `/toolbox key`. Player-facing text says "Ctrl+;".
    CONFIRMED 2026-09-29: the suggested Ctrl+Semicolon works (`/toolbox key`: 6 presses), and the game refuses
    "Ctrl+Shift+Semicolon" ("key must be a letter, digit, F-key, keypad, punctuation or navigation key,
    optionally after Ctrl+ or Alt+"). Not a client bug.
39. Label side margins: labels carry side margins from the theme unless set. FOUND in game 2026-09-27
    (`/toolbox combat debug`): a combat row laid out ~8 px wider than name + value + padding, so the values
    sat on the panel's right edge. Set `marginLeft`/`marginRight` = 0 on labels whose widths must add up.
    CONFIRMED 2026-09-27 (build 7dd58a5): with both at 0 the combat values sit inside the panel.
40. Hover on HUD strips: the docs list `onHover` for every element and say a HudFrame's empty parts pass
    clicks through, but not whether hover reaches a strip's panel and rows. The XP / Today strips report
    hover on their panel and each row (`t:hud`, `t:hud_<id>`). Unconfirmed in game: if the pop-up never
    appears over a strip, this is the place to look.
41. Guild message of the day. Since 2026-09-29 read from `ShroudGetGuildMotd()` (API 18, feature-detected; docs
    `context()`, a reused table) and re-checked on `ShroudOnGuildMotdChanged`; the social summary is the
    fallback. Harness: `H.guildMotdChanged(text)` (getter + event only), `H.S.noGuildMotd`. Originally
    (`ShroudGetSocialSummary().guildMotd`, API 14): Unconfirmed in game: whether it
    is "" (or the summary nil / `inGuild` false) until the guild data loads after login; an empty message is
    never treated as new, so a late load just shows on a later tick. Also whether the text carries markup
    (shown as plain text) and whether `ShroudOnSocialChanged` fires when the data first loads (the 1 s tick
    checks too, so it doesn't matter).
42. Replacing the game's buff bar and click to dismiss (API 16, built 2026-09-27). Unconfirmed in game:
    that `ShroudSetBuffBarVisible(false)` from the 0.5 s tick holds (we re-assert it when
    `ShroudIsBuffBarVisible()` says showing), and that a click on a HUD strip's `Image` counts as the
    gesture `ShroudDismissBuff` needs (the docs list "clickable images"). If dismissing says "it needs a
    click", that's the place to look.
    CONFIRMED in game 2026-09-27 (build 7fe0014): both work as built.
43. Web requests (`ShroudHttpGet`, built 2026-09-28 for estimated values): unconfirmed in game that the
    shard has it switched on, how the add-on manager's Internet switch appears, and whether looted item
    names (`ShroudOnItemsGained`, localized) match SotANET's (English, matched whole, any case). The API
    asks for a descriptive User-Agent; the client allows no headers. The store guide says to declare only
    hosts you control; shroudoftheavatar.net publishes this API for tools, but a reviewer may ask.
44. Notifications (`ShroudGetNotifications`, API 14; built 2026-09-28). Unconfirmed in game: that the
    counts read 0 (or nil) until loaded after login (hence `N.SETTLE`), what "ransoms" and "newRewards"
    look like in practice, and `guildApplications` for a recruiter. Check with `/toolbox notify show`.
45. Notification HUD (built 2026-09-28). REPORTED 2026-09-28: in settings it showed empty with a HORIZONTAL
    scrollbar: rows as wide as the Scroll overflow once its vertical bar takes room. Rows are now
    `NH.WIDTH - NH.SCROLLBAR` (16 px, an estimate), and an empty list shows `nh_empty` instead of the
    Scroll. Also: a `Scroll` inside a HudFrame (scrolls with the wheel?), `whiteSpace
    = "nowrap"` labels ending in "..." when too long (the docs say labels do), and hover on a HUD strip
    (item 40) keeping it shown. Unconfirmed in game.
46. Combat Detailed (built 2026-09-28). CONFIRMED in game 2026-09-28 (`/toolbox combat events`): events are
    plain tables with every API 17 field: rune + runeId on every line (auto-attacks as "Bladed Combat" 222;
    creature specials too, e.g. "Bear Special Attack 2" 328, even on a block), damageType ("blade",
    "handToHand"), time on ShroudTime's clock, sourceKey/targetKey (you = 1). The window, its charts, bars,
    targets and damage types WORK in game (owner, 2026-09-28, build 32a3e88). Pending: the fields of a
    "death" line (kill times assume it names the creature as target or source). Was unconfirmed: column charts built from `Column`s whose height is set with `SetStyle` inside a
    parent with `justifyContent = "end"` (bottom-aligned) / `"start"`; `Bar` `SetValue` for the skill bars;
    `backgroundColor` with the theme tokens `@green` / `@red` / `@text`; and hover on HUD rows (item 40).
47. Equipment durability (`ShroudGetEquipmentItems()`, API 13; built 2026-09-28). Unconfirmed in game: the
    fields' shape (read through `T.Field`, so tables or game objects both work), whether `durability` counts
    down to 0 or stops above it, what `primaryDurability` means (shown only by `/toolbox gear`), whether
    items without durability report `maxDurability` 0 (they're skipped), and whether `icon` is a usable
    texture id (-1 leaves the slot's placeholder). An empty list is taken as "not loaded" and changes
    nothing. If the percentages look wrong, `/toolbox gear` prints the raw numbers.
    FOUND in game 2026-09-28 (`/toolbox gear`, 29 items): numbers, not userdata problems; `durability` and
    `maxDurability` whole numbers, `primaryDurability` fractional, and on EVERY item
    durability <= primaryDurability <= maxDurability (e.g. a sword 10 / 20.5 / 50; new tools 100 / 100 / 100).
    Reading: `primaryDurability` is the current maximum a repair restores to (it decays for good), and
    `maxDurability` the item's original maximum. Unconfirmed until checked against the game's item tooltip.
    Crafting tools (worn in tool slots) and "Fluffy" are in the list too, so a set can exceed `G.SLOTS` (12).
    CONFIRMED in game 2026-09-28 (build 21f745e, `/toolbox gear debug`): glued under the debuffs, a gear slot,
    its icon and sweep lay out at exactly the buff slot's size (30.09 for size 30: UI scale), and the rows share
    one width (a Column stretches its rows). Gear slots now set `borderWidth = 0` like the buff slots; the
    "gear icons look larger / start further left" report went away with that build.
48. Sprite-sheet frames (`Image` `uv` / `SetUV`, API 13). FOUND in game 2026-09-28 (`/toolbox buffs uvtest`, owner):
    only an Image created with `uv` in its spec showed the right frame. `SetUV` on an existing Image changed
    nothing on screen, nor with `SetTexture` first, a hide / `SetUV` / show at once, the show 0.1 s later, or
    an `IconButton`; the docs say "step x to animate a sprite strip". So a sweep stayed at the frame it first
    showed (why it "lined up after /lua reload, then lagged"). Fix: a new Image per frame (item 20's creation
    cap, and the owner's wish for a light load: `BB.SWEEP_RATE` 8 a second, most behind first). Report it to the devs; if a client update fixes SetUV
    (uvtest way 1 sweeps), the holder could go back to one Image stepped with `SetUV`.
    Also seen in the same session: `/toolbox buffs frame 30` "didn't show on the first icon", consistent with
    this (its overlay was already showing).
    RE-TESTED 2026-09-29 on the latest client (API 23): still broken, only uvtest way 5 (a new Image) moves.
49. Consumables (built 2026-09-28). Weapon poisons: not seen in `/toolbox buffs raw` yet; unknown whether a
    weapon coating shows as a buff on the player at all (if not, the API can't see it). Other potions
    (healing etc.): names not seen yet; `/toolbox consumables add <part>` covers them. Bag counts ("x12 left")
    were left out: no reliable link from a rune name (RuneFood_Stew_Dragon) to the bag item's name.
50. API 18 result events. CONFIRMED in game 2026-09-29 (`/toolbox api` probe, API 22 client): all three fire.
    `ShroudOnCraftingStateChanged` on open / close and a craft starting / stopping (`station` = "Milling
    Station +5"; "" when closed). `ShroudOnGatherResults`: `node=Rabbit; failed=false; experience=20; items:
    Rabbit Carcass x1`. `ShroudOnCraftResults` DIFFERS FROM THE DOCS: `item` is the recipe's name
    ("Recipe: Crimson Pine Binding (Milling)", = `recipeName`), not what was made, and `crafted` counts crafts,
    not items (one craft gave "Crimson Pine Binding x4"). `ShroudGetRecipe` has no product or yield either.
    The product reached the bags (`ShroudOnItemsGained`) 23 s later, when taken off the station, so pairing by
    time doesn't work. Plan: crafted rows by recipe (crafts, exceptional, failed, XP); products counted as the
    items gained while a crafting window is open (`T.probe.stationItems`); report the `item` field to the devs.
    CONFIRMED 2026-09-29 (second probe run): gathered names match the items gained exactly (Raw Cotton,
    Beetle Carapace, Hopper (Bait) from a Cotton Plant), and items gained while a crafting window was open
    caught the product ("Crimson Pine Board x2"; the result said `crafted=1`, `item=Recipe: Crimson Pine
    Board`). Recipe names don't always carry a station suffix, and item names can have brackets ("Hopper
    (Bait)"): don't derive product names from recipe names beyond dropping "Recipe: ". Salvage: not seen yet.

