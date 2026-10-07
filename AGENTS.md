# AGENTS.md

Guidance for AI coding agents (and humans) working on Toolbox, a Shroud of the Avatar Lua add-on.
This file holds current facts and rules; the history behind them is in git (`git log -p AGENTS.md`).

## Hard rules

- **Clean-room.** Do not copy or adapt code from OCX Tools or any other existing add-on. Work only
  from the official docs:
  - https://catnipgames.net/lua/agent.html (dense API map; read first)
  - https://catnipgames.net/lua/reference.html (full reference)
  - https://catnipgames.net/lua/guide.html (packaging, sandbox, store)
- **Target Lua API 25 on MoonSharp (Lua 5.2 semantics)** (`min_api_version` 25, the owner's client since
  2026-09-30; no support for older clients). No 5.3+ features: no integer division `//`, no bitwise operators,
  no `utf8` library, no `math.tointeger`/`math.type`, no `<const>`/`<close>`. Also avoid `goto` and
  `table.unpack`/`unpack` so the tests run on LuaJIT too. Pass whole numbers to `%d` (use `math.floor`).
- **The released client can lag or differ from the docs.** Read documented values defensively, keep a
  fallback that was confirmed in game, and add a `debug` subcommand that prints raw values so the owner
  can check without guessing. Feature-detect every function newer than API 25 (`type(ShroudX) == "function"`).
- **Use the UI theme for colours** (owner's preference): theme classes and `@` tokens follow the player's
  skin; avoid hard-coded `#rrggbb` except where the theme has nothing.
- **Always initialise locals: `local x = nil`, never a bare `local x`.** In game a bare local inside a
  loop kept an old value. `tools/build.py` refuses bare declarations; luacheck's 311 is ignored for it.
- **Build UI tables whole; no nil entries** (spec, style, `SetStyle`). Before API 25 a nil entry reached the
  UI and was refused; API 25 treats it as absent, but the house style stays: `tools/build.py` refuses
  `name = ... or nil` entries and `spec.x = nil` / `style.x = nil`.
- **No lazy `.-` patterns on text that can be long.** Before API 25 MoonSharp raised "pattern too complex"
  (a trim on a long buff description got Toolbox disabled); fixed in API 25, but the house style stays: use
  `Toolbox.Trim` / `Toolbox.ParseArgs` or plain `find`/`sub`. `tools/build.py` refuses a `(.-)` capture
  anchored with `$`; the harness raises for any `.-` pattern on text over 120 characters.
- **Read a UI element's state with its getters** (`GetText`, `GetValue`, `IsVisible`, `IsEnabled`...), never its
  fields: in game an element is a game object ("cannot access field text of userdata<Shroud.UI.Label>",
  2026-09-30). The harness's elements are plain tables, so tests can't catch it; `tools/build.py` refuses a field
  read straight off `Find(...)`.
- **Read game data through `T.Field` / `T.List`** (pcall'd). Buff lists were userdata before API 25 (plain
  tables now); other results may still be C# objects (a MoonSharp `EnumerableWrapper` for
  `ShroudGetPartyMemberNamesInScene()`: only `for x in list do` walks it).
- **The price site is "SotANET" or "shroudoftheavatar.net", never "SOTA.net"** (a different domain).
  `tools/build.py` refuses "sota.net" in package files.
- **Avoid `a and b or c` when `b` can be false/nil.**
- **Don't guess at API behaviour.** If the docs are unclear, pick the conservative option, write down the
  assumption, and add it to "Unconfirmed" below.
- **One global.** Everything lives in `Toolbox` or is `local`; the only other globals are the `ShroudOn*`
  callbacks (all add-ons share one environment). Define each callback once, in core.lua.
- **No runtime code loading, and nothing that looks like it** (`load`, `loadstring`, `loadfile`, `dofile`,
  `require`, `_G[...]`, `_ENV[...]`, or reaching a global through a built name) in package files, not even in
  comments or strings: the client matches source TEXT and then refuses the add-on internet access ("loads Lua
  code at runtime"). Its match is cruder than Lua: 1.3.0 was refused over `T.Load(` (2026-10-04). So
  `tools/build.py` refuses those words followed by `(`, `"`, `'`, `[` or `{` in ANY case and with NO word
  boundary: no `T.Load(`, `startLoad(`, `reload(`, and no text like `reload (` or `reload"` either. Saved
  vars are read with `T.ReadSaved`. And no `_G` or `_ENV` at all, not even `rawget(_G, "os")` or in a
  comment: the grant was still refused after the renames, with only those left (read a global plainly:
  `os`, `ToolboxCopies`; nil when absent).
- **Never save a "/" in text** (owner, 2026-10-07: data loss). The game writes it as `\/` and its loader then
  refuses the WHOLE file ("invalid escape sequence near '\/'"), which the next save overwrites with defaults. Save
  through `T.Save` / `T.ReadSaved` (they encode "/" as "%2F", "%" as "%25", keys too), or `T.ForSaving` /
  `T.FromSaved` around a direct `ShroudSetSavedVar`. The harness raises for a "/" in any saved value (dev report 19).
- **No `io.*` / `os.*`**, except feature-detected `os.date`/`os.time` for the local clock (`Toolbox.Today`,
  `Toolbox.Clock`). Persist with `ShroudSetSavedVar`/`ShroudGetSavedVar`, character scope.
- **UI is `Shroud.UI` only.** No retained widgets (`ShroudUI*`), no immediate-mode GUI (`ShroudOnGUI`).
- **No per-frame work.** Don't define `ShroudOnUpdate`. Use events and periodics.
- **Be cheap per tick.** Set UI through `Toolbox.SetText` / `SetTooltip` / `SetVisible` / `SetValue` /
  `SetStyle` (they skip calls that change nothing; don't mix them with direct calls for the same element and
  property), reuse tables, keep comparators and closures out of loops, rebuild derived data only when its
  inputs change. `tests/test_perf.lua` and `tests/test_stress.lua` hold the budgets.
- Constructors (`Shroud.UI.*`, `Shroud.Command`) raise at file top level: call them from `ShroudOnStart`
  or later. Reading `Shroud.UI` at top level is fine.

## Commands

```sh
python3 tools/check.py     # everything below, on any OS (tests under every Lua found); --container too
luacheck .                 # must be clean
lua tests/run.lua          # must pass (also luajit; filter: lua tests/run.lua target)
python3 tools/build.py     # must succeed; --check validates only
make check                 # = tools/check.py
make beta                  # tester zip (see Releasing)
python3 tools/install.py --lua-dir "<game Lua folder>"   # local in-game testing
```

Run `tools/check.py` before calling a change done, and chain commits on its exit status. CI
(`.github/workflows/check.yml`) runs it on Linux, macOS and Windows for every push and pull request, and
fails if the generated `toolbox/changelog.lua` wasn't committed. Contributor setup per OS and the dev
container are in CONTRIBUTING.md.

## Layout

`toolbox/` is the shipped package: `manifest.json`, `*.lua`, `README.md` (the store readme), `icon.png`,
`clock.png` and the `.ogg` sounds, flat. Nothing else, or the build fails. `manifest.json` `files` is the
load order: core, xp, hover, ui, compact, daily, dailydetail, sounds, hud, buffbar, vitals, combat,
changelog, docs, skills, config. Later files may use earlier ones at top level; earlier ones only use later ones
inside functions. The package allows 16 Lua files and has 16: add code to an existing file (or fold skills.lua
into one if a new file is ever needed).

- `core.lua`: `Toolbox` (`T`), chat output (`T.Print`), saved-var helpers (`ReadSaved`/`Save` deep-copy; never name anything `...load(`: the client's code-loading
  scan matches source text, any case, and refused 1.3.0 internet access over `T.Load(` (2026-10-04); `Flush`
  reports a refused write in chat at most every `T.FLUSH_WARN_EVERY` s), formatting, `T.Field` / `T.List`,
  `T.ReadEvents`, JSON (`T.JsonDecode`) and URLs (`T.UrlEncode`), the command table and dispatcher, the
  XP session lifecycle, `Toolbox.Backup` (the settings files' location for the player to copy, `B.SaveNow`, and reset:
  `B.KEYS` are the settings keys a reset clears, applied by `B.ApplyPending` at the start of the next run,
  before any module reads its settings, because the windows write their positions at shutdown; `T.SavePrefs()`
  writes every window's and strip's position now), EVERY `ShroudOn*` callback, and `ShroudOnStart`, which runs each module's init
  through `step()` so one failure can't stop the rest. The module part (`startModules`) runs again when another
  character logs in without a reload (`T.FollowCharacter`, first thing in `T.Tick` and in `ShroudOnSceneLoaded`;
  the docs' advice): so every `Init` must be re-runnable (drop its old window first, re-register by name), and
  `Hud.Init(places)` keeps a strip the new character never placed where it was (`Hud.Places`). Setups
  (owner, 2026-10-04: settings stay per character, "managed individually, but easily copied"): the ACCOUNT
  file is per computer ("on this install"), so it is the exchange: every character's settings are copied there
  as it plays, named ones on Export, and `B.Import` copies one in and restarts the modules (`T.Restart`). `T.DOCS_API` = the API the docs describe (equal to
  build.py's `CLIENT_API_VERSION`; the build checks). `/toolbox api` probes newer functions and the result
  events (`T.ProbeEvent`, `T.ProbeLines`).
- `xp.lua`: `Toolbox.XP`, a pure model over a plain-data session (header comment). Time is passed in. A
  lower total is ignored until it has held `XP.DROP_CONFIRM` s (XP can be lost on death); losses go to
  `session.offset`, and the "net" views subtract them.
- `ui.lua`: `Toolbox.Window`, the **XP Detailed** window (internal names `Toolbox.Window`, id `toolbox_xp`,
  saved var `window` predate the rename; keep them). Session line (`session_extra`: skill levels, deaths),
  per track gain, rates, level, ETA and a last-hour chart (one element per column). Every text label's
  style comes from `Toolbox.Window.TextStyle{...}`; `ApplyText()` re-applies font and spacing.
  `Toolbox.Window.HudMover` is shared by every HUD strip's position commands.
- `compact.lua`: `Toolbox.Compact`, the **XP** window (id `toolbox_compact`, saved var `compact`), and the
  XP Detailed hover pop-up. XP Detailed keeps pinned (`IsOpen`, saved) apart from popped up (`IsPopup`).
- `hover.lua`: `Toolbox.Hover.New{...}`, a trigger window + pop-up controller (keys `t:<el>` / `p:<el>`).
  Copy dailydetail.lua's use for a new one.
- `daily.lua`: `Toolbox.Daily`, today's stats (pure model at the top) and the **Today** window. The day
  (header comment): gold, kills, XP, items, crafting and gathering, skill levels, deaths. Crafting: from API
  24 a craft result's `item` x `made` (and `items`, the recipe's `results`) counts at once (`addMade` /
  `place`), `pending` until taken off the station (so nothing counts twice), `early` for items taken before
  their result; without `made`, items gained at a station count as made by name (`D.IsProduct`), the rest
  as `station`. Looted = items - crafted - station - gathered + pending. Skill levels: `D.SkillGains` over
  the highest `trainedLevel` seen per skill (`skill_levels`); deaths from `ShroudOnDeathChanged(true)`.
- `dailydetail.lua`: `Toolbox.DailyDetail`, **Loot Tracker** (views Looted / Crafted / Gathered). Refreshes
  on change only (`Daily.itemsVersion`, `Prices.version`, `DD.FULL_EVERY` catch-up). Reset (owner,
  2026-10-04): `day.since` = a copy of the counts at that moment (`D.StartRun`); the tracker reads `DD.Day()` =
  the day minus it (`D.RunOf`, remade only when a count changes); the Today window keeps the day; midnight
  (`D.Roll`) drops it. Run rates: `since.played` = seconds of play (`D.Tick` adds tick gaps up to
  `D.PLAY_GAP` while a character is in; saved every `D.PLAY_SAVE` s); `D.PerHour` after `D.RATE_AFTER`; the header
  and rates move once a minute. Run history (owner, 2026-10-07): a run is filed as it ends (`D.FileRun` from
  `D.ResetRun`, `D.EndRun`, and `D.RollDay` before midnight's `D.Roll`) into `loot_runs`; `since.scenes` = play
  seconds per scene (`ShroudGetCurrentSceneName`), the run's place the most played; the value comes from
  `DD.RunValue` (prices at that moment). The "Runs" view (`fillRuns`) reuses the item rows (`addRow(key, text)`), under a bar chart (`fillRunsChart`:
  one Column per run, made the first time the view shows, `ensureRunCols`: built with the window, its elements
  pushed a character switch's rebuild past the creation rate). Rows are appended,
  never rebuilt on a timer (element cap; no reorder API); a sorted rebuild at most every `RESORT_SECONDS`
  while shown. `Toolbox.Prices` (bottom): estimated values from SotANET's
  `GET /api/v1/receipts/prices?item=..` (<= 50 names) via `ShroudHttpGet`, one request `P.GAP` apart,
  cached per account for `P.MAX_AGE`; `P.Test` backs the Test connection button.
- `sounds.lua`: `Toolbox.Sounds`, five sounds (`S.DEFS`: buff_expiring, debuff_landed, and notify, ping, tap
  for notifications: each source picks one, `N.SOUNDS` / `soundKey`), plus skill_up and skill_down, which
  skills.lua appends. Candidates in
  order: the custom path, `Lua/toolbox_<file>` (.ogg, .wav), the shipped `toolbox/<file>`. A load counts once
  its clip appears in `ShroudListSound()` (async); clips are found by name at play time. Never call
  `ShroudListSoundReset` (it clears every add-on's clips). If sounds go silent, look in the game's Player.log.
- `hud.lua`: `Toolbox.Hud` owns every HUD strip. A module registers (`Hud.Register`) and implements
  `FRAME_ID`, `HOME`, `BuildContent()`, `ContentSize()`, `IsShown()`, `GetSavedPosition()` /
  `SavePosition()`, optionally `Wanted()` (a strip only when in use), `HidesGlued()`, `Unbuilt()`,
  `Below()` / `Place()`. `Unbuilt()` is REQUIRED for any module holding elements: called whenever its
  content is destroyed; it drops every element and skips updates until rebuilt ("this Row was destroyed"
  otherwise). When glued (`Hud.SetGlued`), the modules in `Hud.GLUE` (vitals, buffs) share one strip,
  `toolbox_hud`, side by side; `Hud.BELOW` parts (target) go above, under or left of those columns per their
  `Place()`. At most `Hud.FrameCap()` strips (`Hud.MAX_FRAMES` = 25, or the limit learned when the game
  refused a frame for room, `Hud.OutOfRoom`: that strip's content is destroyed): past that a strip isn't built
  and chat says so once (`noRoom`; `Hud.ORDER` decides, target last). A strip failing with "too fast" is retried after
  `Hud.RETRY_DELAY`. `Hud.TextStrip` is the HUD form of the XP and Today windows. `Hud.Tick` saves a strip's position only
  while it is on screen (`IsVisible`) and a character is in the world (`T.CharacterName`): a hidden or never-shown
  strip, or one at the login screen, can report the top-left corner (owner, 2026-10-05). A logout (`T.loggedOut`)
  makes the next login, the same character's too, read every module's settings again (`T.FollowCharacter`). `Hud.SetOverlay(provider)`:
  one overlay drawn over the Toolbelt (the combat shout). `Hud.Rebuild(key)` rebuilds one
  module's own strip (a setting that changes its elements); a full `Hud.Build()` makes every strip's elements
  again at once, past the creation cap with a big strip (the buff block's 40 slots).
- `buffbar.lua`: `Toolbox.BuffBar` (BB), plus `Toolbox.Consumables` (K), `Toolbox.Gear` (G) and
  `Toolbox.BuffBlock` (MB, end of the file; owner, 2026-10-03).
  - Buff block: its own strip (never in the Toolbelt), every effect sorted by expiry (`BB.Tick` collects them
    when `MB.Collecting()`, `MB.Fill`), no group slot, debuffs outlined (`fill`'s `outline`), a fixed pool of
    `MB.SLOTS` (40; 60 in 1.2.0, lowered for the element budget) in rows of `MB.GetWidth()` (a width change rebuilds only its strip: `Hud.Rebuild`), its own
    size (in place) and combat-only. Short tooltips (`fill`'s `short`: name, debuff, `BB.CoarseLeft` to the
    minute), not the game's full ones: 60 full ones beside the buff bar's would break the text budget.
    Replace and click-to-dismiss use the buff bar's settings.
  - Buff bar: `OnBuffsChanged` (from the event AND from `Tick` when names change) reads
    `ShroudGetPlayerBuff()` through `BB.ReadRunes` (userdata-safe) for debuff flags, icons, categories and
    durations (`TotalDuration` = full seconds, `CurrentDuration` = seconds left); learned durations
    (`buff_durations`) are the fallback for effects with no total. A 0.5 s periodic fills a fixed slot pool,
    sorted by time left, and runs the expiry / debuff alerts. Grouping: longer than `BB.GroupAfter()` left,
    a chosen category (`groupCats`), or a name part (`group`) goes into one count slot. `combatOnly`,
    `replaceStock` (API 16), `clickDismiss` (re-finds the index by name at click time), the countdown label.
  - Sweeps: buff, consumable and target icons carry the game's cooldown wedge (API 25) on `slot.wedge`, an
    invisible picture (`BB.WedgeCarrier`, tint alpha 0) `BB.WEDGE_SHARE` (1/sqrt 2) of the icon, centred by
    negative margins: the game draws the wedge as a circle reaching its picture's corners, which on the icon
    hung over the square's edges, and nothing clips it (owner, 2026-09-30). `BB.SetTimer(slot,
    left, total, warn)` calls the icon's `SetSweepTimer(start, total[, { warnBelow, warnColor }])` once per
    run, again only when the start moves more than `BB.TIMER_SLACK`, the total changes or it turns red
    (`BB.WARN_COLOR`); the game draws it and clears it at the end. `slot.timer` is what was set;
    `BB.TimerText` describes it for the trace. The client refuses a timer over `BB.TIMER_MAX` (86400 s): longer
    runs (Obsidian potions, 7 days) get a still `SetSweep` wedge moved by `BB.STILL_STEP`; every sweep call is
    pcall'd, and a refused timer falls back to the still wedge (an error each tick gets the add-on disabled). The equipment bar's wear is still a clock picture:
    `BB.SweepHolder` (a holder Row + one Image) stepped with `SetUV` by `BB.ShowFrame` / `HideFrame`;
    `clock.png` must match `BB.CLOCK` (`art/clock.py`).
  - Consumables: food, potions, poisons and combat consumables by category (API 23; `BB.TakesConsumable`,
    `cats`, `exclude` Scroll/Torch/Bait, `extra`), name rules on older clients. Own strip or a Toolbelt row.
    Long-lasting ones and past `max` share a group slot.
  - Gear: worn items below `threshold` (and all while settings are open), polled every `G.POLL` s (no wear
    event); feeds the "durability" notification (`G.Latest`, `G.Notice`). Own strip or a Toolbelt row.
  - `fitFrame` sizes the strip to what shows (the game keeps HUD frames on screen by their FULL size) and
    counts the glued rows (`K.GluedCount`, `G.GluedCount`, `T.Target.GluedCount`). Empty strips show a
    placeholder name while settings are open.
- `vitals.lua`: `Toolbox.Vitals` (V), health / focus / Vigor bars. Current values and maximums from
  `ShroudGetPlayerVitals` (API 25; `V.Vitals()` reads it once per game time). Vigor from `ShroudGetVigor` (API 20). Every size from `V.Metrics()` (Size,
  Bar length; bars `V.BAR_THICKNESS` of the line). `V.RowHeights()` = the rows as laid out (GetSize).
  Also `Toolbox.Target` (TG, end of the file): the target HUD. One row: a bars block (`target_info`: health
  and focus `Bar`s the size of the player's; the name and exact numbers in its tooltip; the health bars' look
  options, its own: `bars`, `numbers` (`TG.NumberText`, shortened past 9,999), `bg`, `flash`/`flashBelow`, all
  elements built in every form and restyled in place by `styleInfo`; with neither bars nor numbers the block is
  hidden (`TG.InfoShown`), except under the columns where it stays a blank; the buff column adds `TG.ExtraHeight()`)
  and effect slots with the game's wedge, debuffs first (`TG.Collect`). Polled every `TG.POLL` s and on
  `ShroudOnTargetChanged`; the grouped `ShroudGetTargetBuff` only when the target or its effect count
  changes. The API doesn't say who applied an effect: all are listed. `TG.Name`: the game's name (API 25: the
  target frame's), or "Unnamed". Where it goes: its own strip, or the Toolbelt:
  `Place()` "top" (default; its row keeps its height with no target so nothing jumps: the strip is anchored
  at its top-left grip) or "bottom"; with the health bars glued too (`TG.Below`), Hud builds it across both
  columns, lined up with the health bars; else (`TG.InBuffColumn`) the buff bar builds it as its first or
  last row. Mirrored (`mirror`): bars rotated 180 (`rotate` style; confirmed to fill from the right),
  icons reversed, a fixed-width block (`LEFT_SLOTS` icons + the bar length); in the Toolbelt it goes LEFT
  of the health bars (`Place()` "left", space always kept: a blank area between the grip and the bars,
  labelled "Target" by `tHint` while settings are open), on its own strip the strip is mirrored. The
  mirrored rows copy the health rows' laid-out heights (`syncRows`, for `TG.SYNC_FOR` s after a build or
  resize, then every `TG.SYNC_EVERY` s): rows built to the asked-for height lay out taller. Sizes change in
  place (`TG.ApplySize`), never by rebuilding (sliders fire many changes; the element cap).
- `combat.lua`: `Toolbox.Combat`, the combat stats HUD (pure fight model: rates, crit, avoid, per skill,
  per target, per damage type, a timeline, fight history) and **Combat Detailed** (`C.Detail`, fixed pools).
  Fed by `ShroudOnCombatEvents` (through `T.ReadEvents`) and `ShroudOnCombatModeChanged`.
  Also `Toolbox.CombatShout` (`C.Shout`, end of the file; owner, 2026-10-03): your block / parry / dodge
  (`toYou`) pops the word over the Toolbelt for `CS.SHOW_SECONDS` and plays its sound (`S.DEFS` "block",
  "parry", "dodge", appended there; `CS.SOUND_GAP` per kind). The word is the Toolbelt frame's overlay
  (`Hud.SetOverlay`: the last child of the shared strip or of the buff bar's own; `OverlayFit(w, h, left)` from
  `Hud.Refresh`), centred by negative margins with a bottom margin giving the height back (margins clamp to
  -64), outlined by dark copies. Always built (hidden), so switching it on rebuilds nothing.
- `changelog.lua`: GENERATED by `tools/build.py` from CHANGELOG.md. Never edit it. The source checks apply to
  CHANGELOG text: don't quote refused patterns there.
- `docs.lua`: `Toolbox.Docs` (the Docs window: `D.SECTIONS` is the player guide, one topic at a time: only the
  topic shown is built, switching destroys the previous one, like the settings pages; each topic < 6,000
  characters, each label < 4,096 (the game's cut-off); update it with every user-facing change), the version window, and `Toolbox.Notify` (N): `N.SOURCES` (each with
  `Check(seen, ctx)` -> notice or nil, plus an optional quiet value; motd, mail, expiring, ransoms, rewards,
  applications, durability, friends, guild, and skills from skills.lua; a source's `vias` limits where it can
  go: `N.Allows`, `N.Choices(key)`), `N.DELIVERY` ("window", "hud" = `Toolbox.Notify.Hud`, "chat")
  plus a per-source `sound` (the notify chime once per check), and `N.Check` (tick, start, the social /
  notification / guild / friend events), which marks a notice seen only once delivered. The guild message
  comes from `ShroudGetGuildMotd` (API 18) when present. friends / guild are `transient` (their `seen` is an
  event number from `N.OnStatus`'s queue, never read back). `N.SETTLE` s after start, counts going down
  aren't remembered. The notification HUD's list and settings are per character: `NH.FollowCharacter` reloads
  them when the player changes without a reload (from `NH.Tick` and before a HUD delivery; review, 2026-10-03).
- `skills.lua`: `Toolbox.SkillBar` (SK), the **Skill activity** strip (owner, 2026-10-02, "not 100% sure": built
  to be removable). Self-contained: at top level it registers its Hud strip (inserted in `Hud.ORDER` before
  target), its saved-var key in `B.KEYS`, its "Skill level changes" notification source (levels up and down) (`vias = { "hud" }`: never a
  window), its guide topic and its command (`T.AddCommand`); core (`ShroudOnSkillsChanged`, the start-up
  step) and config (its page via `C.Helpers`, `SK.CONFIG_IDS`, `SK.ConfigSync`, its Position row) call it only
  `if T.SkillBar`. Levels are `trainedLevel` (`level` is the tile's, capped in some scenes: a capped scene must
  not read as levels lost; the tooltip names the cap). The change sequence and baseline are per character
  (the notification's `seen` is too), and its Check delivers nothing until a reading for the current character.
  Training markers (built 2026-10-03, API 27, `SK.HasModes`; setting `marks`): each icon's left half opens the
  Skills window, its right half has three click areas (`SK.MARKS`: train @green arrow, maintain @gold square,
  unlearn @red arrow turned 180; toolbox/skillmarks.png from art/marks.py, two 3:2 frames by `uv`), laid over
  the icon after the level labels. A click calls `ShroudSetSkillMode` (the gesture) for that mode, plays its
  sound (skill_train / skill_maintain / skill_unlearn) and says in chat when the game picks another
  (`SK.MODE_REASONS`); `ShroudCanSetSkillMode` (cached per skill and mode) fades one the game won't take
  (`SK.MARK_NO`). No click-to-cycle (Unlearn one click away) and no "off" marker (owner). The harness stubs both
  (skill fields `mastery`, `low`, `elixir`; `H.skillMarks`, `H.clickSkillPart`).
  Pure model: `SK.Read` / `SK.Update` (baseline first, a level / mode change, or experience
  with trigger "xp", puts a skill on top; one slot per skill) / `SK.Expire` / `SK.ChangesText`. Reads are throttled
  (an event only marks them; `SK.QUIET_EVERY` / `SK.XP_EVERY`). Its sounds (skill_up / skill_down,
  `S.DEFS` entries it appends) play only with the strip on, at most once per `SK.SOUND_GAP` s each, and not when
  the "Skill level changes" notification plays its own "+ sound" (its notice names "skill_down" when every level
  in it was lost and the source's sound is the celebration: `notice.soundKey` overrides the source's). It also appends them to `N.SOUNDS` ("Celebration",
  "Sad notes"), and its source's `soundKey = "skill_up"` (a source's default sound, else "notify"). Skills are read-only in the API: a click opens
  the game's Skills window (`ShroudToggleWindow`, on the gesture). Removal steps are in its header.
- `config.lua`: `Toolbox.Config`, the settings window. **Settings search** (owner, 2026-10-03): `C.SearchIndex()`
  runs every page's builder with `recording` on, so `UI` (a stand-in for `Shroud.UI`) returns plain
  `{ kind, spec }` records instead of elements, and walks them (a heading names the section, a label the
  control after it); `C.SearchMatches` / `C.Search` / `C.SearchGo` (shows the page built from its recording with the control's part at the top: `buildFocused`
  replays the recorded specs into real elements, the parts above it (from the nearest heading) built hidden
  under a "Show the whole page" line, `C.ShowWholePage`; then blinks the control's opacity
  `C.SEARCH_BLINKS` times, one control at a time with a generation guard: an outline couldn't be undone
  without a style getter; the UI can't scroll to it). So page builders must (1) create elements only through
  config's `UI` (another file's page: `h.UI` from `C.Helpers`), (2) not call element methods or change state
  while building, and (3) give each control an id; `tests/test_config.lua` fails for a control the search can't
  find. Categories (`C.CATEGORIES`, the "Settings" dropdown;
  Toolbelt first): only the one shown is built; switching destroys the previous one first (every page kept
  built took ~420 elements and hit the game's 2,000 cap in game, 2026-09-30). So `Sync` uses `setValue` /
  `setText` / `setEnabled`, which skip missing controls, every id it looks up must be in `ALL_IDS`, and state
  tied to a page's controls is reset when it is built (`C.statShownSig`, `C.backupSig`). `C.ShowControl(id)` (the page found from the recordings,
  `C.PageOf`, so only that page is built)
  shows the page holding a control (the tests use it). Controls whose feature is off are greyed
  out. `C.NameList` is the text box + Add / Remove editor. `C.TOOLBELT_PARTS` + `C.PlaceOf` / `C.SetPlace`
  give each bar Off / Own strip / In Toolbelt. The Toolbelt page also has Show the Toolbelt, Only during
  combat, the target's Target row and Mirrored, and `C.HudSummary()`.
  The Combat page's stat picker: `T.StatMatches` (core; readable stats by name or label) feeds
  `C.FindStats` (the `stat_results` dropdown via `SetChoices`, suggestions `C.STAT_SUGGESTIONS` when empty),
  `C.AddPickedStat` / `C.RemovePickedStat` (`Combat.AddStat` / `RemoveStat`), `stat_shown` follows the list.
- THE TOOLBELT: the player-facing name for the buff bar with the health bars glued beside it and the
  consumables / equipment / target rows joined to it; "the main selling point". Player text says
  "Toolbelt", never "glue"; code and saved vars keep the glue names. The buff bar is its base: with it off,
  the other bars use their own strips.
- `tests/`: `harness.lua` (a fake host), `test_*.lua` suites (listed in `tests/run.lua`), `run.lua`.
  `test_stress.lua`: a veteran character, full bars, heavy combat and maximal saved data, with budgets
  (garbage measured under standard Lua only, in `test_perf.lua` too: LuaJIT's count is noisy). `STRESS_PRINT=1 lua tests/run.lua stress` prints the numbers.
- `art/`: `icon.svg` (-> `toolbox/icon.png`, 256x256: `rsvg-convert -w 256 -h 256 art/icon.svg -o
  toolbox/icon.png`), `clock.py` (-> `toolbox/clock.png`: a normal and a red set of 120 frames; keep in sync
  with `BuffBar.CLOCK`), `marks.py` (-> `toolbox/skillmarks.png`: the skill strip's training markers), `alerts.py` (-> `toolbox/*.ogg` via ffmpeg's Vorbis encoder, +7.5 dB into a limiter at -1.5 dBFS since
  2026-10-07 (twice as loud as before): buff_expiring falls,
  debuff_landed steps down, notify rises; ping and tap are the other notification sounds; skill_up, a rising
  arpeggio into a ringing chord, and skill_down, sinking "wah wah" notes, and skill_train / skill_maintain /
  skill_unlearn, two quick notes up, even and down, belong to skills.lua; block, parry and
  dodge, a thud, a clash and a whoosh, to combat.lua's shout). Re-encoding changes the bytes even when the audio is the same:
  `git checkout` an .ogg you didn't mean to change. A player's own `Lua/toolbox_<name>` sounds win.
- `tools/`: `check.py` (all checks), `build.py` (packaging rules, the source checks, the store README
  renderer's rules, the support URL's form, the root README's API line, the changelog section, the docs API
  constants; stamps `build = "<commit>[+]"` into dist), `beta.py` (`make beta`), `install.py`,
  `release_notes.py` (a version's CHANGELOG section, for the release workflow).
- `.luacheckrc`: std `lua52` plus the documented globals (`api_functions`; newer ones in `api_probed`;
  callbacks in `api_callbacks`). Only names that are in the docs.
- `tmp/`: a local working area (git-ignored, skipped by luacheck). Never reference it from the package,
  tests or tools. It holds the owner's client-issue reports (`client-issues.md`, `sweep-report.md`, ...).

## Adding things

- **A subcommand:** `add(name, help, fn)` in core.lua; `fn(rest)` gets the text after it. Test it in
  `tests/test_commands.lua`. (`Shroud.Command` allows 8 per add-on and returns `ok, reason`: report refusals.)
- **A setting:** a setter + getter on the owning module (persisted there, calling `Toolbox.Config.Sync()`),
  a control in its category, its id in `ALL_IDS`, a line in `Sync()` (and `setEnabled` if it depends on
  something), tests in `tests/test_config.lua` or the module's suite. A NEW saved-var key goes in
  `Toolbox.Backup.KEYS` (a setting: reset clears it) or the `KEPT` list in `tests/test_backup.lua` (which
  fails for a key in neither). Backups are the player's copies of the saved-variable files: don't keep them
  in a saved var (each table is capped at 256 KB; owner, 2026-09-30).
- **A feature:** pure logic over plain data, API calls at the edges, hooked into `ShroudOnStart` /
  `Toolbox.Tick` / core's callbacks; a `Toolbox.Foo` table; tests; a CHANGELOG `[Unreleased]` entry; the
  guide (`D.SECTIONS`) and both READMEs if players see it.
- **A HUD strip:** a Hud module (above). There are 11 strips already (25 frames, if the 2026-10-01 raise holds in
  game; 8 before): still prefer a Toolbelt row.
- **A window:** there is no slot (see Limits). Use a view of an existing window.

## The test harness

`tests/harness.lua` models the documented host: constructors and `Shroud.Command` raise outside a callback
and reject unknown fields; saved vars have a memory cache and a "disk" copy updated on flush; destroyed
element trees raise on use and leave their parent; margins / paddings are clamped; the element-creation cap,
the 2,000 live elements (`H.S.live`; the game counts MORE than the harness: keep a wide margin), the
65,536 characters of on-screen text (`H.S.text`, `H.S.textPeak`: labels, buttons, toggles, tooltips,
placeholders, dropdown choices; raises past it; the worst case is in `test_stress.lua`, 40k measured 2026-10-02,
mostly buff tooltips), 8 windows and
8 HUD frames (`H.MAX_HUD_FRAMES`; the documented 8, a test raises it to 25) are enforced; `H.config():Find(id)` shows the settings page holding the control; a disabled control can't be changed or clicked; `SetUV` changes what is drawn; the
wedge (`SetSweep`, `SetSweepTimer`, refused as in game for a lone duration) reads back with
`element:SweepNow()` (fraction covered, red) and `element.timerCalls`.

- Lifecycle: `H.boot()` (a returning player), `H.firstBoot()`, `H.reload()` (= `/lua reload`: flush, tear
  down, reload, `ShroudTime` continues), `H.restart()` (relaunch: only flushed data survives),
  `H.advance(n)` (periodics second by second).
- Input: `H.chat("/tbx ...")`, `H.click(win, id)`, `H.change(win, id, value)`, `H.submit(win, id, text)`,
  `H.closeWindow(id)`, `H.moveWindow(id, x, y)`, `H.press(id)`.
- Game state: `H.gain(a, p)`, `H.goldChange(n)`, `H.items(list, dropped)`, `H.combat{...}`,
  `H.setCombat(on)`, `H.addBuffs{...}` / `H.removeBuff(name)` (`H.S.durationMode`, `H.S.buffObjects`),
  `H.setGear{...}`, `H.setVigor{...}`, `H.setTarget{ id, name, hp, maxHp, focus, maxFocus, dead, hidden,
  effects = {...} }` / `H.setTarget(nil)`, `H.setSkills(list, levelsChanged)`, `H.setDead(on)`,
  `H.setGuild(name, motd)`, `H.setMotd(text)`, `H.guildMotdChanged(text)`, `H.setNotes{...}`,
  `H.craftResults(list, dropped)`, `H.gatherResults(list, dropped)`, `H.craftingState{...}`,
  `H.httpRespond(n, ok, code, body, err)`, `H.callback(name, ...)`.
- Switches: `H.S.date`, `H.S.serverTime`, `H.S.clock` / `H.S.noClock`, `H.S.files[path] = true`,
  `H.S.acceptMissing`, `H.S.noCategories`, `H.S.noCrafting`, `H.S.noGuildMotd`, `H.S.flushFails`,
  `H.S.httpRefuse`, `H.S.saveRefused` / `H.S.refuseKeys` (every saved-var write, or those keys), `H.S.recipes`, `H.S.showRefused`; `element.laidOut = { w, h }` sets what GetSize reports.
- Reading: `H.logged(pattern)`, `H.logs()`, `H.lastLog()`, `H.saved(key, scope)`, `H.frame()` (buff strip),
  `H.hud()` (glued strip), `H.vitals()`, `H.config()` (all categories built) / `H.configRaw()`, `H.detail()`,
  `H.detailRows()`, `H.daily()`, `H.dailyText(id)`, `H.notify()`, `H.notice(key)`, `H.nhud()`,
  `H.gearFrame()`, `H.gearSlots()`, `H.targetFrame()`, `H.targetRow()`, `H.targetSlots()`,
  `H.combatHud()`, `H.combatRows()`, `H.S.frames.toolbox_buffblock` (the buff block), `H.skillsFrame()`, `H.skillSlots()`, `H.clickSkill(n)`, `H.playedNames()`, `H.S.created` / `H.S.constructed`.

Stub any new API function in `install_api()` with its documented return values, including the "no
character" sentinel.

## Saved vars (character scope)

| Key | Shape |
| --- | --- |
| `session` | see the header comment of `xp.lua` (format `v = 1`); also `skills`, `deaths` (counts) |
| `window` | `{ open = bool, x = number, y = number, font = 9..32, spacing = 0..12, net = bool }` (net: subtract XP lost) |
| `compact` | `{ open = bool, x = number, y = number, hover = bool, hud = bool, compact = bool, hx, hy }` (hx/hy: the HUD strip; compact: an API 19 compact window) |
| `daily` | see the header comment of `daily.lua` (format `v = 1`) |
| `daily_window` | `{ open = bool, x = number, y = number, hover = bool, hud = bool, compact = bool, hx, hy }` |
| `daily_detail` | `{ open = bool, x = number, y = number, values = bool, each = bool (the price each in the count: "40 x 5g"; default true), view = "looted"/"crafted"/"gathered", include = bool }` |
| `buffblock` | `{ show = bool (default false), width = 1..30 (icons a row, default 10), size = 20..48, combatOnly = bool, x, y }` |
| `buffbar` | `{ show, size = 20..48, expire, expireSeconds = 1..60, debuff, flash, groupAfter = seconds (a GROUP_AFTER_CHOICES value, 0 = off), groupCats = { [category] = true }, countdown = bool, countdownSecs = 5..120, group = { name parts }, quiet = { exact effect names, <= BB.QUIET_MAX } (muted: no expiry / debuff sound), replaceStock, clickDismiss, combatOnly, x, y }` |
| `sounds` | `{ v = 2, volume = 0..100, paths = { [sound key] = "..." }, levels = { [sound key] = 0..100 } (unset: 100) }`; a volume without `v = 2` is from before the louder sounds (2026-10-07) and is halved once (`S.Init`). Played at volume x level / 100, twice that for a player's own file (`S.EffectiveVolume`), at most 100 |
| `buff_timers` | `{ v = 3, timers = { [rune name] = { total, remaining, at = T.Now() } } }`: trusted totals, for a reload |
| `buff_durations` | `{ v = 2, durations = { [rune name] = seconds } }`: full durations learned from casts |
| `vitals` | `{ show, width = 20..400 (bar length at 100%), scale = 75..250 (%), showText, showBars, bg = "None"/"Dark"/"Light", flash, flashBelow = 1..95, vigor = bool, replaceStock = bool (API 28: hide the game's player-frame bars), x, y }` |
| `hud` | `{ glued = bool, x, y }` (the glued strip's position) |
| `combat` | `{ show, scale = 75..250, pet, stats = { "MagicResistance", ... }, bg = None/Dark/Light, bgOpacity = 10..100, x, y }` |
| `combat_detail` | `{ open = bool (pinned), x, y, scope = "fight"/"session", hover = bool }` |
| `combat_shout` | `{ on = bool (default false), size = 12..32, kinds = { block/parry/dodge = { text = bool, sound = bool, color = a CS.COLORS token } } }` |
| `consumables` | `{ show = bool (default true), glue = bool, extra = { name parts, <= 20 }, cats = { [category] = true } (absent: defaults), exclude = { name parts } (absent: Scroll, Torch, Bait), max = 1..10, combatOnly = bool, x, y }` |
| `gear` | `{ show = bool, threshold = 5/10/15/20/25/30/50 (percent), glue = bool, x, y }` |
| `target` | `{ show = bool (default false), glue = bool (default true), place = "top" (default) / "bottom", mirror = bool, effects = "all"/"debuffs"/"none", icons = 1..8 (unset: 8, or 5 mirrored), bars = bool (default true), numbers = bool (default false), bg = "None"/"Dark"/"Light", flash = bool (default false), flashBelow = 1..95, x, y }` (a saved place "left", from beta 7, reads as mirror; bars and numbers both off = just the effect icons, refused with effects "none" too; hidePet = bool (default true): your pet as the target reads as no target, `TG.IsPet`) |
| `loot_runs` | `{ v = 1, list = { { at = "HH:MM", date = "YYYY-MM-DD", scene, played = s, gold, kills, items, kinds, nodes, value = estimated gold or nil } } }`, newest first, at most `D.RUNS_KEEP` (10); stats: a reset keeps it |
| `skill_levels` | `{ v = 1, high = { [skill key] = highest trainedLevel seen } }` |
| `notify` | `{ v = 1, compact = bool (the window), font = 9..32 (the window; unset: the theme's), sources = { [key] = { on = bool, seen = last value delivered, via = "window"/"hud"/"chat", sound = bool, soundKey = one of N.SOUNDS (default "notify") } } }`; durability's `seen` is `{ [item key] = "low"/"broken" }`; friends / guild don't keep `seen`; the older `guild_motd` `{ show, seen }` is read once to take over |
| `notify_hud` | `{ hideAfter = seconds (0 never, 5..60), font = 9..32, spacing = 0..12 (each unset: the XP windows'), x, y }` |
| `notify_history` | `{ v = 1, list = { { when = "HH:MM", title, text } } }`, newest first, at most 20 (which are new, `fresh`, is kept in memory only) |
| `prices` (ACCOUNT scope) | `{ v = 1, items = { [lower item name] = { avg = n or false (no sales), sold, last, day, at } } }`, at most `P.MAX_KEEP` |
| `welcomed` (ACCOUNT scope) | set after the first-run welcome |
| `skills` | `{ show = bool (default false), vertical = bool (default true), slots = 1..12, stay = seconds (SK.STAY_CHOICES; 0 = always), trigger = "levels"/"xp", size = 20..48, number = bool (the level on the icon, default true), marks = bool (the API 27 training controls, default true), soundUp = bool, soundDown = bool (both default true), x, y }` (skills.lua) |
| `settings_pending` | `{ kind = "reset" }`: done and deleted at the next start |
| `setup_share` | `true` = this character's copy is listed for the others (default off; a setting, but never copied into a setup or imported) |
| `setups` (ACCOUNT scope) | `{ v = 1, list = { { name, character = bool, when = "YYYY-MM-DD" } } }`: the setups' index, at most `B.SETUP_MAX` |
| `setup:<lower name>` / `setup_character:<lower name>` (ACCOUNT scope) | `{ v = 1, name, keys = { [a B.KEYS key] = its saved table } }` (notify without `seen`): a named setup / a character's copy, kept by `B.KeepCopy` from `T.Flush` when a setting changed and `setup_share` is on |

Keys must be <= 128 chars with no `/` or `\`. A table's JSON must stay under 256 KB. Always validate what
you read back and fall back to defaults.

## Releasing

0. **Agree the version number with the owner first** (owner, 2026-10-02): before bumping anything, read the
   `[Unreleased]` notes, propose a number with the reason, and wait for the owner's answer. Versions follow
   [semver](https://semver.org) from 1.0.3 on, read from the player's side:
   - MAJOR: something players relied on goes or changes incompatibly: a feature or command removed, saved
     settings not carried over, `min_api_version` raised (players on an older client can't update).
   - MINOR: anything new, backwards compatible: a feature, a setting, a command, a new option on a HUD.
   - PATCH: fixes only (including wording and docs fixes), nothing new to learn.
   A mix takes the highest. How to number a tester beta under semver isn't decided yet: ask (the store needs
   a plain number higher than any submitted; the release workflow marks a "(beta N)" heading as a pre-release).
1. Bump `version` in `toolbox/manifest.json` **and** `Toolbox.version` in core.lua (the build checks they
   match); move `[Unreleased]` notes under the new version in CHANGELOG.md ("## [x.y.z] - date (beta N)").
   Version numbers are single-use in the store, including rejected ones.
2. `min_api_version`: raise it only to what the LIVE client reports (`/toolbox api`), never just to what the
   docs describe. The root README's opening must state it ("needs Lua API 25"; the build checks).
3. Update BETA.md (the tester guide, `TESTING.txt` in the zip; `INSTALL.md` is its `INSTALL.txt`: keep it
   plain, the store being the official way to install): the intro, "What to try" (this beta first,
   earlier betas under "From beta N") and "Known issues". Keep the root README, the store README and the
   manifest description in step with features.
4. `make check`, commit ("Beta N (x.y.z)"), then `make beta` from that clean commit (the stamp must be the
   commit, not `...+`), and tag it: `git tag -a vX.Y.Z -m "Beta N (x.y.z)" <commit>`. Push only when the
   owner asks, to BOTH remotes: `origin` (the owner's server) and `GitHub` (public; runs CI and releases):
   `git push origin main vX.Y.Z` and `git push GitHub main vX.Y.Z`. Record the tag here.
5. Pushing a `v*` tag runs `.github/workflows/release.yml`: every check, the tag must equal the manifest
   version and have a CHANGELOG section (`tools/release_notes.py`), then a GitHub release with
   `toolbox-<v>.zip` (store package) and `toolbox-<v>-beta.zip` (tester zip), notes from the changelog, a
   pre-release when the heading says "(beta N)". Public once pushed. First one planned: v1.0.0 (owner,
   2026-09-30; v0.7.0 and older tags predate the workflow and stay as they are).
6. When handing over the store submission (package, version, change list), remind the owner to check that the
   author / "by" fields read "shawn butts (shawn)" in the submit form and, once live, on the store page
   (owner, 2026-10-03: the player name was added after 1.2.0, so 1.2.0's package still says "shawn butts").

Tags: v0.2.0 (a52051c), v0.2.1 (ae2fa1f), v0.3.0 (607dcb3), v0.3.1 (7db2a15), v0.4.0 (4b4d5a5),
v0.5.0 (820df19), v0.6.0 (03fdeef), v0.6.1 (6322846), v0.7.0 (2d07df7), v0.8.0 (9672d11), v1.0.0 (438a80d), v1.0.1 (1cfef96), v1.0.2 (fedf1ba), v1.0.3 (50bff65), v1.1.0 (26166ce), v1.2.0 (9077b9f), v1.3.0 (98e666e), v1.4.0 (7479419; withdrawn from the store before release), v1.4.1 (ad52e3f; never released in the store either: 1.5.0 followed it), v1.5.0 (84db2df; withdrawn from the store before release: the saved "/" data loss), v1.5.1 (073fe53).

**The store page** (addons.catnipgames.net) is where most players first meet Toolbox:
- Cards show the icon, the **name** in full (manifest `name`: "Toolbox: Toolbelt, HUDs, Trackers and
  more.", <= 60 characters), the author (from the submitting account, not the manifest; every "by" / author
  field we fill in, the manifest's `author` included, reads "shawn butts (shawn)": the real name and the player
  name; owner, 2026-10-03), and a description
  clamped to 3 lines (about 100-120 characters).
- That description isn't ours: the store's reviewer writes it, apparently from the package. So
  `toolbox/README.md` opens with the pitch for it to echo, and the manifest `description` says the same.
- The detail page shows that paragraph, the file list and our README. Package pictures are NOT shown.
- The README renderer: a list item's wrapped line becomes a new paragraph, tables and `[links](...)` show as
  raw text, a byte-order mark hides the title. `tools/build.py` refuses those.
- `support_url` = https://github.com/shawnbutts/toolbox; the submit dialog has its own field for it (empty
  there removes it). The build checks its documented form.

## API notes

What each newer API added and what Toolbox does with it (all feature-detected):

- **API 16**: replace the game's buff bar (`ShroudSetBuffBarVisible`, released by the game on reload, so
  applied every tick while ours shows) and click to dismiss (needs a click gesture). Don't follow the game
  bar's position (`ShroudGetBuffBarRect` / `ShroudOnBuffBarMoved` unused).
- **API 17**: combat event fields (rune, runeId, damageType, dot, overheal, time, sourceKey, targetKey).
- **API 18**: crafting / gathering results (<= 20 per call + `dropped`), `ShroudGetRecipe`,
  `ShroudGetCraftingState`; friends / guild members and their online events (<= 50 + `dropped`; login isn't
  a change); `ShroudGetGuildMotd` / `ShroudOnGuildMotdChanged`. All used.
- **API 19**: `compact = true` windows (title bar only on hover; no TextField / Dropdown in them): the XP and
  Today windows' "Compact window" form (`SetCompact` rebuilds the window: its fields are fixed at creation;
  Esc doesn't close it). It frees HUD frames. The harness refuses fields in a compact window. Decided (owner,
  2026-09-29): XP, Today and the Notifications window (`N.SetCompact`, rebuilt keeping the notices it shows;
  `notify.compact`) get it. HUD strips can't (a window needs one of the 8 window slots, all in
  use); the detail windows stay normal windows (lots of info, their dropdowns work, rarely kept open).
- **API 20**: Vigor (`ShroudGetVigor`, `ShroudOnVigorChanged`). Used.
- **API 21 / 22**: more package sound formats; package `data_files` (`ShroudLoadData`). Unused.
- **API 23**: buff categories (player and target). Used.
- **API 24**: craft results name the product (`item`), count items made (`made`) and list everything a craft
  put out (`items`); `ShroudGetRecipe(id).results` = the fixed yield. Used (confirmed in game 2026-09-30:
  `item=Crimson Pine Binding made=4`).
- **API 25** (the minimum; checked in game 2026-09-30 with a stand-alone test, `tmp/api25check.lua`): SetUV
  redraws; `SetSweep` / `SetSweepTimer` and a `sweep` spec field on Image / IconButton (used, above);
  `ShroudGetPlayerVitals` (used); buff lists are plain tables; `ShroudGetTargetName` = the target frame's name;
  nil fields are absent; lazy patterns work on long text; a label's `height` is honoured; `card` draws (Air /
  Crucible skins); `ShroudGetPartyMemberBuffs(slotOrName)` and `ShroudOnPartyChanged()` (not used yet).

- **API 26** (docs 2026-10-01; `T.DOCS_API` = 26, `min_api_version` stays 25): the party slots run 0 (you) to
  count - 1 in party-frame order, and `ShroudGetPartyMemberNamesInScene()` is a plain list of real names (a bare
  `for v in list do` still works). Nothing Toolbox uses changed. Confirmed on the live client 2026-10-01
  (`tmp/partyrepro.lua`: slot 1 = the other member with health and buffs; names "shawn", "phil").
  Same day, not tied to a version: up to 25 HUD frames (the reference still says 8), and the Community Addons
  window's "Run" checkbox is now "Enabled". The reference still doesn't mention `SetSweepTimer`'s one-day
  limit (dev report item 16).
- **API 27**: skill training modes (`ShroudSetSkillMode`, `ShroudCanSetSkillMode`; used by skills.lua's markers),
  skill tracking (`ShroudGetTrackedSkills`, `ShroudSetSkillTracked`; unused).
- **API 28** (the owner's client, 2026-10-04; `min_api_version` stays 25): the player frame's
  health, focus and Vigor bars hidden by `ShroudSetPlayerVitalBarsVisible(false)` (released on reload, so
  re-applied every vitals tick while wanted, as the buff bar's): "Replace the game's health bars" (`V.SetReplace`),
  only while ours are on screen (`Hud.PartOnScreen("vitals")`: a combat-only Toolbelt hides its strip with the parts
  still built).
- **API 29** (docs 2026-10-07; `T.DOCS_API` = 29, `min_api_version` stays 25): `ShroudGetLocationText()` (the line `/loc`
  prints; English area name; "" while loading) and `ShroudFormatLocation(x, y, z)` (a position as `/loc` writes it, which
  chat turns into a link; nil unless three finite numbers). Unused; `/toolbox api` probes them. Requests 18 and 19 are
  not in it.

**Waiting on the developers:** a read-only game settings API (first use: the game's "stack buffs lasting
longer than" option feeding `BB.GroupAfter()`). Submitted 2026-10-07 (`tmp/client-issues.md`): **18**, for the
crafting planner (ingredient choices for slot categories, item stats, language-independent item keys, a `have`
that counts containers, the recipe book in one call, the station a recipe needs), and **19**, the saved "/" data
loss (Toolbox is protected: never saves a "/"). Everything reported is fixed: the API 25 client issues, and
(work log 2026-09-30, `ac63e8c01b`, **API 26**, in the next client build, not yet in the owner's) the party
ones (`tmp/client-issues.md` 14, 15): the slot getters reach the whole party (slot 0 = you, then party-frame
order, so `for slot = 0, count - 1` finds everyone, buffs included), `ShroudGetPartyMemberNamesInScene()`
returns a plain list of real names, and `for v in list do` over a table walks its values.

**Ideas, not agreed:** a **Party Toolbelt** (owner, 2026-09-29): a dedicated party strip, separate from the
player's own Toolbelt, so a healer keeps their Toolbelt for themselves and watches the party on its own
strip: a row per member (name, health and focus bars sized like the player's, members in another scene
dimmed, the lowest health flagged). Party API (base API; see the reference's "Party" section):
members by slot (API 26: slot 0 = you, then party-frame order; on API 25 only slot 0 answered) or by name
(`ShroudGetPartyMemberNamesInScene`: a plain list from API 26; on API 25 a wrapper only a bare `for` walks),
health and focus by name (`...InScene(name)`), buffs by name
(`ShroudGetPartyMemberBuffs`, API 25); only members in your scene have vitals and buffs (else -1 / nil);
`ShroudOnPartyChanged` (API 25) for joins, leaves and scene changes, no vitals event (poll); player targets
expose only vitals; combat events carry a `party` flag. It needs a HUD frame of its own: with 25 frames (the
2026-10-01 raise; confirm in game) there is room; on an 8-frame client the learned cap (`Hud.FrameCap`) leaves
it out with the "no room" line. Also:
a crafting skill tracker and a recipe lookup / shopping list (as Loot
Tracker views: no window slot left). **Crafting planner** (owner, 2026-10-05; probe: `/toolbox recipe`,
`D.RecipeLines`): pick a recipe, expand it "from scratch" through the known recipes' results, a combined
shopping list, and a build order grouped by station that ticks off from `ShroudOnCraftResults`; ingredient choices
and stats wait on dev request 18. Caching (owner): recipes change only with a client release, so keep the read
recipes "forever" (account scope, keyed by id; split across keys: a table must stay under 256 KB), with a "Reset
recipe cache" button, and clear it when the client build changes (`ShroudGetClientInfo().build`) or when a later
Toolbox release says so (a cache format number). Which recipes a character knows stays per character
(`ShroudGetKnownRecipes`, re-read on `ShroudOnRecipesChanged`), and "have" counts are always read fresh. Found with the probe on the live client (2026-10-05, 1,761 recipes): a
recipe's ingredients can be SLOT CATEGORIES ("Metal Sheet", "Metal Binding", "Cloth or Leather Strap": no recipe
makes an item by that name; the choices are e.g. the recipes whose result ends in "Sheet", "Glass Sheet" being a
false match), and several recipes can make one item ("Iron Ingot" and "Iron Ingot from Metal Scraps": default to
the one named like the item, let the player switch). Below a chosen item the chain expands exactly (Iron Sheet ->
Iron Ingot -> ore and coal); a gathering session HUD; lock-position / snap presets for strips
(only if a strip's grip can be hidden).

## Game behaviour (confirmed in game)

Rules learned the hard way; keep to them.

- **Limits** (per add-on): 8 windows (Toolbox has 7 lasting ones; Docs and version share the 8th), HUD
  frames covering <= 35% of the screen (8 by the reference; 25 by the work log of 2026-10-01, unconfirmed in
  game: `Hud.MAX_FRAMES` is 25 and `Hud.FrameCap()` learns the real limit from the game's refusal,
  `Hud.OutOfRoom`), 2,000 elements, 65,536 characters of text in all (one element's text is cut at 4,096, a
  tooltip at 512; measured worst case ~40k, `test_stress.lua`), nesting 24 deep, and an
  element-CREATION cap (~500 burst, ~200/s) that raises "elements are being created too fast". Keep big
  windows lazy (built on first show), open pinned big ones after a delay (`CD.OPEN_DELAY`,
  `T.WELCOME_DELAY`), never rebuild on a timer, and resize in place. A login can still hit the cap: Hud
  retries quietly, and HUD strip builds are atomic.
- **Layout:** there is no absolute positioning; an overlay is a negative left margin (an Image over another
  draws on top). Margins clamp to -64..256 and paddings to 0..256, so overlap per icon, not per strip.
  Labels carry theme side margins: set `marginLeft`/`marginRight` = 0 where widths must add up. Before API
  25 `height` alone didn't size a label (a theme minimum won), so labels and bars pin `minHeight`/`maxHeight`
  (`Toolbox.Window.LineStyle` / `TextStyle`); harmless now. Rows can lay out taller than asked: measure with `GetSize` when
  things must line up. Hidden elements take no space. A colour's alpha doesn't fade children (`opacity`
  does). An `Image` with an `onClick` shows its tooltip. `rotate = 180` mirrors a Bar's fill.
- **Theme:** `inset` is a dark panel with shaded edges (the Dark backgrounds use `#000000` + alpha instead);
  `card` draws only on some skins (Air, Crucible; nothing before API 25): don't rely on it; `@text` is the light panel colour; there is no dark text token (`V.DARK_TEXT`).
- **HUD frames:** moved by a grip at the top left (hidden while "Lock Status Movement" is on; strips keep
  `Toolbox.Window.GRIP` px of room for it), kept on screen by their FULL size (size strips to what shows),
  anchored at the top left (anything appearing above or left of content pushes it: keep that space).
  Destroying and rebuilding frames (gluing) works.
- **Sweeps (API 25):** `SetSweepTimer(start, duration)` refuses a duration over 86400 s ("duration is seconds,
  above 0 and at most 86400"; not in the docs; found 2026-09-30 when 7-day potions got Toolbox disabled).
- **Buffs:** the game corrects a long buff's time left now and then, up as well as down (a loop of expiry sounds
  near the end of one, reported on 0.8.0): `BB.Track` arms the alert once per run (`newRun`), takes a jump for a
  recast only past `BB.RECAST_SHARE` of the length, and `BB.SetTimer` ignores corrections under half a degree.
  `ShroudGetBuffTimeRemaining` counts down smoothly; permanent effects report 0 left; the moon
  timer reports `TotalDuration = 0`. Buffs loading in after login look new: nothing counts as freshly cast
  within `BB.SETTLE` s of start, a scene change or a player change, or when 2+ names appear at once.
- **Categories (API 23):** Food (`RuneFood_*`), Potion (Obsidian `BlessingOf*`), Blessing (`POT_Blessing_*`,
  `Rune_Reward_Blessing_Shrine_*`: shrine blessings, not potions), Other (Stillness, MoonlightWatch).
- **Vitals:** `ShroudGetPlayerVitals` gives health, focus and their maximums; `health` can read a hair above
  `maxHealth` (951 / 950.36; `V.Format` never shows the max below it). The per-frame globals read nil before
  API 25 (another add-on overwrote them; now restored each frame). `ShroudPlayerGold` and `ShroudTime` work.
- **XP:** totals can go down (death); see `XP.DROP_CONFIRM`.
- **Font:** the game's UI font has no `~` (it draws a box; screenshot 2026-10-04) and may lack other non-ASCII
  characters: write "about", plain ASCII. `tools/build.py` refuses `~` and non-ASCII in string literals.
- **Internet (SotANET prices):** works (confirmed 2026-10-04, build 9c74679: "connected. 'Iron Ore': ~5g").
  It had never worked: the client refused the grant ("loads Lua code at runtime") because of
  `rawget(_G, "os")` / `rawget(_G, "ToolboxCopies")`. Renaming `T.Load(` and friends alone did NOT clear it;
  removing every `_G` did (whether `T.Load(` also counted is unknown: the renames stay). The grant also needs
  Internet on for the add-on in the manager. The game prints the code-loading line once per load.
- **Sounds:** paths are relative to the Lua folder; `ShroudLoadSound` returns false for a missing / wrong
  file and true when an async load starts; `ShroudListSound()` is plain base names in load order; the
  ffmpeg-encoded .ogg plays.
- **Keys:** Shift is never a modifier; the game takes "Ctrl+Semicolon" (the suggested key, confirmed) and
  refuses "Ctrl+Shift+Semicolon". Players change keys in the add-on manager.
- **Combat events** are plain tables with the API 17 fields (auto-attacks as "Bladed Combat"; you = key 1).
- **Crafting:** the three result events fire; on API 23 `item` was the recipe's name (fixed in API 24,
  confirmed); `crafted` counts crafts; products reach the bags when taken off the table, much later; gathered
  names match the items gained. Recipe names don't always carry a station suffix and item names can have
  brackets ("Hopper (Bait)"): don't derive product names beyond dropping "Recipe: ".
- **Equipment:** `durability <= primaryDurability <= maxDurability` (numbers; the docs: primary = the most a
  repair restores, worn down with use, raised only at a crafting station; needs repair when durability <
  primary). `G.Read` measures against `primaryDurability` (owner, 2026-09-30); a ceiling below
  `G.STATION_BELOW` of new gets a "crafting station repair" tooltip note (`G.StationNote`). Tools and pets are worn items
  too, so a set can exceed `G.SLOTS`.
- **Target:** before API 25 some creatures' name was "Entity with no name (<internal name>)"; fixed.
- **Your pet:** `ShroudGetPetInfo().Name` and the target's name for it are both "kitty\n<shawn>" (the owner on a
  second line), max health equal (confirmed 2026-10-02). `TG.IsPet`: the name without the owner (`TG.BaseName`),
  the owner too when the target's name has one, and `MaxHealth` (no pet id in the API).
- **Party (API 25/26):** `ShroudGetPartyMemberBuffs(slot or name)` works (same shape as your buffs);
  `ShroudOnPartyChanged` fires with no arguments. From API 26 (confirmed 2026-10-01) slots run 0 (you) to
  count - 1 and the in-scene names are a plain list of real names.
- **Characters and setups** (confirmed 2026-10-04): logging in as another character without a restart brings
  up that character's own settings and places (`T.FollowCharacter`), and a setup listed by one character,
  imported by another, applies at once and leaves the first one's untouched.
- **1.5.0 work** (confirmed 2026-10-04): muted effects, the Loot Tracker's Reset and run rates, and "Replace the
  game's health bars" (API 28) work in game.
- **Louder sounds** (confirmed 2026-10-07): the +7.5 dB .ogg files, the halved saved volume and the per-sound
  volume sliders work in game.
- Confirmed working as built: replace / dismiss the game's buff bar, grouping, the Toolbelt, the mirrored
  target, skill levels and deaths, friends online, the notification chime, Combat Detailed, the game's wedge
  fitted and centred inside the icons, and the 0.7.0 + unreleased work on the dev client (2026-09-30: the
  still wedge on 7-day potions, red at the alert, vitals from ShroudGetPlayerVitals, gear against the repair
  ceiling, Backup & reset).

## Unconfirmed

Things the docs don't settle and the game hasn't shown yet. Check before depending on them more:

- Whether `/lua reload` calls `ShroudOnDisableScript` or re-reads saved vars (we save each tick and re-read
  totals at start, so either way nothing is lost); when `ShroudOnStart` runs relative to login (we wait for
  `ShroudGetLevelProgress()`); which scope `ShroudSetSavedVar` writes to inside `ShroudOnLogOut`.
- `ShroudTime` continuing across `/lua reload` and relogs (assumed), restarting on relaunch.
- `Window{ x, y }` versus the host's own position memory (we pass x/y, never call `SetPosition`); whether a
  window's width/height apply once the host remembers a size (assumed not); `GetPosition` returning numbers.
- The level-cap shape of `ShroudGetLevelProgress()` (`percent == 0` with `intoLevel > 0` = capped).
- `onHover` on containers and HUD strips (entering a child, the title bar): the pop-up delays absorb flicker.
- Combat `death` lines: which side is the killer, and `fromYou` on your kills.
- `os.date` in the sandbox (feature-detected; fallback: the date part of `ShroudServerTime`).
- `ShroudOnItemsGained` names as stable keys (localized; same-named items merge); whether they match
  SotANET's names (English) for prices.
- `ShroudHttpGet`: whether every shard allows it; the reviewer may question declaring a host we don't own.
- Notification counts reading 0 until loaded (hence `N.SETTLE`); ransoms / rewards / applications in practice.
- The notification HUD's Scroll inside a HudFrame, nowrap labels ending in "...".
- Weapon poisons: whether a weapon coating shows as a buff at all.
- The skill strip's training markers: the click areas over the icon receiving clicks in game, the tinted
  and turned skillmarks.png, and the reasons ShroudSetSkillMode gives.
- The skill activity strip (skills.lua): how often `ShroudOnSkillsChanged(false)` fires in combat, whether
  `mode` reads as documented and changes with the game's triangle, a decaying skill's `experience` going down,
  `ShroudGetSkills().icon` drawing, `ShroudToggleWindow("skills")`, and whether a click on the level over the
  icon (labels laid over it) still reaches the icon's onClick. `/toolbox skills debug` prints the
  readings.
- The target getters' effect indices lining up with `ShroudGetTargetBuffIcon` / `Tooltip`, and
  `TotalDuration` on target effects (else no sweep); `/toolbox target debug` prints them.
- API 24 crafting in game (`/toolbox api` shows `made` and the recipe's yield once the client updates).
- The account file's name: `toolbox.account.json` by the docs' pattern (the character file,
  `toolbox.shawn.character.json` under `ShroudLuaPath` + `SavedVariables`, was confirmed 2026-09-30); and
  whether the character part is ever not the name `ShroudGetPlayerName` gives (case, spaces).
