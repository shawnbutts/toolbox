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
- **Make text fields with `T.TextField{...}`** (config's `UI` stand-in does it for its pages): the spec's `onSubmit`
  alone did nothing on Enter in game (owner, 2026-10-15, the planner's search), so the handler also goes through the
  `OnSubmit` method, run once a press (harness `H.S.specSubmitIgnored`; two presses in one test frame are one). Even
  so one Enter did nothing there (owner, same day: only a quick second Enter reaches the field's submit, request 27
  submitted 2026-10-16): the planner's search fills as you type (`onChange`, which works in game,
  as the settings search's does); `/toolbox plan debug` says in chat what the box gets. Don't rely on Enter alone.
  Request 27 is fixed (the developers, 2026-10-18: build 2da431775a, not on chaos or live yet): one Enter calls the
  handler, the spec field's and `OnSubmit`'s alike, with the typed text; the box keeps the keyboard and chat doesn't
  open. `T.TextField` needs no change (if both ways fire for one press, `once` runs it once); check a single Enter in
  the planner's search once the build is out, then the "Don't rely on Enter alone" note can go.
- **Read a UI element's state with its getters** (`GetText`, `GetValue`, `IsVisible`, `IsEnabled`...), never its
  fields: in game an element is a game object ("cannot access field text of userdata<Shroud.UI.Label>",
  2026-09-30). The harness's elements are plain tables, so tests can't catch it; `tools/build.py` refuses a field
  read straight off `Find(...)`.
- **Read game data through `T.Field` / `T.List`** (pcall'd). Buff lists were userdata before API 25 (plain
  tables now); other results may still be C# objects (a MoonSharp `EnumerableWrapper` for
  `ShroudGetPartyMemberNamesInScene()`: only `for x in list do` walks it).
- **The price site is "SotANET" or "shroudoftheavatar.net", never "SOTA.net"** (a different domain).
  `tools/build.py` refuses "sota.net" in package files.
- **Read the player's name with `T.PlayerName()`**, never `ShroudGetPlayerName()` (`tools/build.py` refuses it
  outside core.lua): the game's display name carries tags ("shawn[PVP]", "shawn[404040][AFK][-]", seen 2026-10-07/08)
  and Toolbox took each for another character (a new XP session and every strip rebuilt on going AFK; setup copies
  per tag). `T.PlainName` drops every `[...]`; `B.TidyTagged` folds 1.7.0's tagged setup / recovery copies into the
  plain name once a run, at start (harness: `H.S.char.tags`).
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
- **Save only through `T.Save` / `T.ReadSaved`, or `T.SetSavedVar`, and delete through `T.DeleteSaved`** (each
  file's 256 KB, below; `tools/build.py` refuses a direct `ShroudDeleteSavedVar` too) (owner, 2026-10-07 and 2026-10-08: twice a value
  the game's loader refused lost a character's WHOLE file: the game starts the add-on with defaults and the next save
  overwrites it). The loader looks like MoonSharp's JSON reader on the Lua lexer: it refused "\/" (the saver's "/",
  "invalid escape sequence near '\/'") and a negative number ("Unexpected token : '-'"). So (core.lua):
  - text keeps only printable ASCII other than `" \ / %` (`T.SAFE_CHARS`); anything else is written `%XX` (`%uXXXX`
    past 255: MoonSharp strings are UTF-16), keys too, and read back. `T.ForSaving` / `T.FromSaved` around a direct
    write; `T.Resaved` puts a raw saved value (perhaps from before the escaping) in today's form for a copy;
  - upgrades from 1.3.0 on read their files as they were (owner, 2026-10-08): `T.ForSaving` marks each table it writes
    (`T.SAVE_FORMAT_KEY`, "%E"); `T.FromSaved` decodes only a marked table with the escapes, an unmarked one (1.6.0 or
    before) as 1.6.0 did ("%2F", "%25" only; 1.3.0 wrote text as typed). Decode a copy or file before mixing it with
    another (`importValues`); `T.Resaved` = `ForSaving(FromSaved(v))`; a list saved whole goes in a marked
    wrapper (`T.SAVE_LIST_KEY`, review 24);
  - a number below 0, under `T.SAVE_TINY` or from `T.SAVE_HUGE` (the saver may write an exponent) is saved as text
    `%N<number>` and read back as the number; NaN and infinities aren't saved;
  - `T.SetSavedVar` (every write; never call `ShroudSetSavedVar` elsewhere) checks the value with `T.CheckSaved`
    (types, the text and numbers above, positive whole list keys, no cycles, an estimate under 256 KB) and refuses one
    that fails: that key isn't written, chat says so once (`T.saveRefused`). `tests/run.lua` fails any test that
    leaves a refusal, and the harness raises for unescaped text, a "/" or such a number reaching
    `ShroudSetSavedVar` (dev reports 19, 21);
  - recovery (`B.Recover` / `B.KeepRecovery`): a copy of each character's `B.RecoverList()` keys in the account
    file, numbered (`save_mark` in the character's file); a file back without its number is put back at start.
    Only on a client without the game's backups (`B.UsesRecovery()`; owner, 2026-10-16): from API 39 the game keeps
    an unreadable file beside the new one and copies a file before a reset, an import or a new version, so no copy
    is written or put back, and `B.DropRecovery` (from `B.Recover`) deletes the old ones once the account file has
    a game backup holding them (the index stays, emptied, `dropped`, with its `legacy` and `ceiling`). Harness:
    `H.OlderClient(fn)` runs a test as a client without backups (the recovery copies' tests).
- **MoonSharp is slow** (the owner's timed `/toolbox perf`, 2026-10-14): Lua work measured at 0.3 ms in the harness took
  about 23 ms in game (saving the day: copy and check), and the game's `ShroudGetNearestWaterType` up to 28 ms. Keep big
  walks (`T.ForSaving`, `T.CheckSaved`) out of frequent paths: the session and the day are stored only with the
  flush (`D.SaveIfChanged`, also at a scene unload, logout and shutdown), the buff timers every `BB.TIMER_SAVE` (30) s.
  The flush's work is spread over `T.FLUSH_STEPS` ticks (`T.flushStep`: session, day, setup copy, recovery copy, then
  the game's write, flushSeconds after the last; in one tick it took up to 44 ms).
- **No `io.*` / `os.*`**, except feature-detected `os.date`/`os.time` for the local clock (`Toolbox.Today`,
  `Toolbox.Clock`), and feature-detected `os.clock` for `/toolbox perf`'s timing only (owner, 2026-10-14: `T.PerfT`
  / `T.PerfAdd`, nil and free unless perf is measuring). Persist with `ShroudSetSavedVar`/`ShroudGetSavedVar`, character scope.
- **UI is `Shroud.UI` only.** No retained widgets (`ShroudUI*`), no immediate-mode GUI (`ShroudOnGUI`).
- **No per-frame work.** Don't define `ShroudOnUpdate`. Use events and periodics.
- **Be cheap per tick.** Set UI through `Toolbox.SetText` / `SetTooltip` / `SetVisible` / `SetValue` /
  `SetStyle` (they skip calls that change nothing; don't mix them with direct calls for the same element and
  property), reuse tables, keep comparators and closures out of loops, rebuild derived data only when its
  inputs change. `tests/test_perf.lua` and `tests/test_stress.lua` hold the budgets. Garbage is what hitches
  (the 1.8.0 pass, owner 2026-10-14): no closure per call on a hot path (`pcall(fn, args)` with a shared function,
  not `pcall(function() ... end)`), and nothing big stored per event (the XP session is stored only as it is
  flushed, at once only for XP lost, a death or a skill level). Register every periodic with
  `T.RegisterPeriodic` and stop a repeating one with `T.RemovePeriodic` (so a perf report doesn't start it again,
  review 48) (marks it for `/toolbox perf`: `T.Ran`, also in every core callback, the command dispatcher,
  `Hud.Build` and a settings page; the sampler reads `ShroudRealDeltaTime` at most every 0.01 s, so not every frame
  above 100 a second, and counts a slow frame's sample as Toolbox's when a mark (`T.PERF_RING`) falls in its
  interval: "near", a correlation (review 46); harness `H.S.nextDelta`, or a long `H.advance` step). The live
  client refused a 0.01 s periodic (owner, 2026-10-14; the docs give 0.01 as the minimum): `T.PERF_PERIODS` tries
  longer ones in turn (harness `H.S.periodMin`). `perf quiet` removes every repeating Toolbox periodic
  listed (`periodicRuns`, kept by `T.RegisterPeriodic`) for the measurement and registers them again at the report:
  the A/B for "is it Toolbox?" (the owner's run, 2026-10-14: 0 hitches paused against 25-32 a minute running, so
  they ARE Toolbox's timers); `perf only <name parts>` keeps those running, to find which. Phases: a repeating periodic under a second starts `T.PHASE_STEP` after
  the one registered before it (a one-shot of its name, then the repeating one), so the half-second ones don't all
  land in one frame (the owner's first perf run, 2026-10-14: Toolbox near 24 of 28 hitches, each naming them all),
  and each stays `T.PHASE_EDGE` off the tick's whole seconds (the second run: three in each slow frame). The tick's
  once-a-second work is in four periodics: `T.Tick` (XP, the day, flush), `T.PollTick` (`toolbox_poll`: sounds,
  prices, gear, notifications), `T.TrackTick` (`toolbox_track`: window and strip positions) and `T.ViewsTick` (`toolbox_views`: map markers, the
  settings page, the windows' text, the notification HUD), each calling `T.FollowCharacter` first. The scene's name and
  id come from `T.SceneName` / `T.SceneRaw` (kept `T.SCENE_EVERY` s, dropped on `ShroudOnSceneLoaded` / `Unloaded`:
  tests that change `H.S.scene` fire `ShroudOnSceneLoaded`, as the game does).
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
  The recipe book (`D.ReadRecipeBook`, for `/toolbox recipe` and the planner): `D.BOOK_STEP` (1) recipe by id a
  `D.BOOK_PERIOD` (0.05 s) step, about 90 s for a big book (the whole book at once ran past the game's time limit,
  2026-10-05; paused in a fight and `BB.COMBAT_LINGER` s after it, and while the planner is closed unless the read is
  `anywhere` (`/toolbox recipe`, "login"), `D.BookPaused` ("combat" / "closed"; review 67, owner 2026-10-23: the reads
  were 1.9.0's hitching); only what each recipe makes is kept (`indexRecipe`; `/toolbox recipe` reads its chain's
  makers itself); EVERY read asks first in a confirmation window, OK / Cancel, nothing read without OK (owner,
  2026-10-23: "a completely new popup window ... clear and obvious ... not do the load unless the user hits ok";
  a panel in the planner went unseen): `PL.Confirm(background, ok)` (`PL.ASK_ID` "toolbox_book_confirm", `PL.ASK_*`
  texts; its own window from API 41, `PL.OwnNoticeWindow`, Toolbox's 9th of the 30 allowed; before, the shared 8th,
  `T.TakeSharedWindow`, the planner reopened on Cancel; also when the game refuses the own window: `plAskBuild`, Show
  taken as shown unless it answers false, chat naming why when neither shows, `/toolbox plan debug` printing each try;
  owner, 2026-10-23: in game the button did nothing), centred by `Hud.screen`; Cancel, Esc or a close (`onClose`) =
  `plBookStopped` (nothing asks again on its own); the planner's buttons, Settings'
  `pl_book_read` and `plan book read` go through `PL.AskBook` (OK opens the planner, where the book is read); "need"
  asks from `PL.Tick` (`plNeedAsk`: not mid-refresh, the shared window would close the planner); "login" and
  `/toolbox recipe` ask too, then read in the background (harness `H.apiVersion`, 30 windows from 41); API 37's `ShroudGetRecipeBook`, one station a step, hitched in game, owner 2026-10-15: not used;
  `D.BookProgress` for the planner's bar, with a once-a-login note, `PL.BOOK_NOTE`; meanwhile the planner's
  controls are greyed out, `plLock` from `PL.ShowProgress`: owner, 2026-10-16); kept for the session in
  `D.recipeIndex` (`byResult` by name,
  `count`; when it's read is the player's, owner 2026-10-17 (default `PL.BOOK_WHEN_DEFAULT` "manual", a player's
  request 2026-10-23; "need" before 1.9.1; Only when I ask: From scratch asks nothing, the planner's button does): `PL.BOOK_WHEN` "need" (`PL.NeedBook`), "login"
  (`PL.BOOK_LOGIN_DELAY` s after `PL.Init` and a recipe learned) or "manual" (`PL.ReadBook` only: Settings' `pl_book_read`,
  the planner's `pl_book`, `/toolbox plan book read`; a recipe learned keeps the book, `D.ForgetRecipes(keep)`,
  `D.bookStale`); `PL.StopBook` (`plBookStopped`: nothing auto until read); a read again keeps the old one in use,
  the planner not greyed;
  `byKey` by item key), dropped on `ShroudOnRecipesChanged` and by `PL.Init` (a login or another character). Not saved: 1,764 recipes'
  makers would take a large share of a 256 KB file. At the end, `Toolbox.Planner` (PL; owner, 2026-10-15,
  the 1.9.0 feature; header comment): the crafting planner, `/toolbox plan [recipe]`, the shared 8th window's fourth
  user (`T.TakeSharedWindow("planner")`). Pure model: `PL.Expand(rootId, crafts, ctx)` (rows, shopping list, build
  order; your bags shared across the plan, a tool not used up and a craft's surplus left for the next rows, reviews
  49-50; no recipe inside itself), `PL.PickChoice` (the player's pick, else the first you
  have enough of; the "Use what I have" / "Stats I care about" modes and watched stats were dropped the same day,
  owner: the counts and the "Adds ..." line under each slot, `PL.AddsText`, show it; `PL.Reset` clears the plan, not
  the book), `PL.PickMaker`, `PL.Preview` (base + the
  root's picks, weight left out). Refreshed on `ShroudOnInventoryChanged` / craft results / the crafting state at most
  every `PL.Gap` s while shown (`PL.REFRESH_GAP`, or `PL.HUD_GAP` with only the HUD, plus `PL.GAP_PER_READ` for
  each recipe the last refresh read, to `PL.GAP_MAX`; with only the HUD, not in a fight: review 67) (`PL.Tick` from `T.ViewsTick`), the plan's recipes read fresh; before the
  book is read, the makers are the known recipes named like the item (`plQuickMakers`, a few calls, over
  `D.KnownRecipes`: the game's list once a session, 4.5 ms, indexed by first word `D.KNOWN_STEP` a step from the
  planner opening, `D.PrepareKnown`, since one frame took 24 ms; a search finishes it at once); the shortfall's
  control is an "I'll craft" Toggle (owner: "Make it" read as if it would craft); the Shopping list is the first and
  default view (owner); the Plan view's
  rows are rebuilt only when their structure changes (`plRowSig`), counts and choices set in place. The plan is for
  `PL.Remaining()` crafts (the plan's less those made since it was set, `plMade`, memory only). The Crafting Planner
  HUD (owner, 2026-10-17; header comment; `PL.Strip`, Hud key `shopping`, `toolbox_shopping`, the window's bottom
  `pl_hud` button, `/toolbox plan hud [close <s>]`): the shopping list (have / need for each item the plan was short
  of, `PL.Expand`'s `gather`; a line stays, ticked and faded, once listed: `got`, cleared with a new recipe), then the
  build order once all is gathered (`hudStage`; its `sh_switch` button goes either way, back to the list staying
  there, `hudStay`; a step below the recipe stays done once its crafts were, `plDone`, since crafting the recipe uses
  it up, owner 2026-10-17; `sh_again`, Start over, `PL.StartOver`: the same recipe, nothing made, the shopping list), then at the end the `craft_done` sound (sounds.lua's `S.DEFS`, art/alerts.py) and a close after
  `hudClose` s (`PL.HUD_CLOSE`, default 30, settings `pl_hud_close`); what it opens on and Start over goes back to
  (`hudStart`), the move on once gathered (`hudAuto`), its shade and Position row (`plhud`, POSITIONED's "crafting"
  page); planned again every `PL.Gap` s on a change
  with the window closed, counts in place, rebuilt when lines come or go. Text budget (the
  stress test's four 30-choice slots: 46,703 at the peak): `PL.CHOICES_SHOWN` (10) choices a slot.
- `dailydetail.lua`: `Toolbox.DailyDetail`, **Loot Tracker** (views Looted / Crafted / Gathered). Refreshes
  on change only (`Daily.itemsVersion`, `Prices.version`, `DD.FULL_EVERY` catch-up). Reset (owner,
  2026-10-04): `day.since` = a copy of the counts at that moment (`D.StartRun`); the tracker reads `DD.Day()` =
  the day minus it (`D.RunOf`, remade only when a count changes); the Today window keeps the day; midnight
  (`D.Roll`) drops it. Run rates: `since.played` = seconds of play (`D.Tick` adds tick gaps up to
  `D.PLAY_GAP` while a character is in; saved every `D.PLAY_SAVE` s); `D.PerHour` after `D.RATE_AFTER`; the header
  and rates move once a minute. Run history (owner, 2026-10-07): a run is filed as it ends (`D.FileRun` from
  `D.ResetRun`, `D.EndRun`, and `D.RollDay` before midnight's `D.Roll`) into `loot_runs` (`/toolbox loot log`
  prints the last `D.ITEM_LOG_MAX` item events as the game sent them, `D.itemLog`, memory only; owner, 2026-10-08:
  2 sharks counted as 4); `since.scenes` = play
  seconds per scene (`ShroudGetCurrentSceneName`), the run's place the most played; the value comes from
  `DD.RunValue` (prices at that moment). Where (owner, 2026-10-08): `since.spots` = play seconds per
  `D.SPOT_CELL` square (keyed by `ShroudGetCurrentSceneNameRaw` and the square, with the time-weighted position
  sum; at most `D.SPOTS_MAX`, a new square replacing the least-played and starting from its time), filed as the
  run's `spot` (`D.MainSpot`: the middle of the most-played square in its scene); a run row's Compass button
  (Beacon before 1.8.0; `DD.MarkRun`, a click only: it replaces the player's beacon) calls `ShroudSetBeacon` there when you're in that
  scene (the beacon marks the scene you're in); `DD.LocText` writes it with `ShroudFormatLocation` (API 29). Run markers (API 30, `DD.SyncMarkers` from `T.Tick`, acting only when the scene,
  character, `D.runsVersion` or the `markers` setting change; a refusal retried after `DD.MARKER_RETRY` s): a flag per
  run whose spot is in this scene, id from its date and time (`DD.MarkerId`: filing a run moves none), note
  `DD.MarkerNote`; ours no longer wanted ("run-" ids) are removed. Harness: `H.S.markers[raw][id]`,
  `H.S.markerRefuse`, `H.S.noMarkers`, `H.S.markerSets`. The "Runs" view (`fillRuns`) reuses the item rows (`addRow(key, text)`), under a bar chart (`fillRunsChart`:
  one Column per run, made the first time the view shows, `ensureRunCols`: built with the window, its elements
  pushed a character switch's rebuild past the creation rate). Rows are appended,
  never rebuilt on a timer (element cap; no reorder API); a sorted rebuild at most every `RESORT_SECONDS`
  while shown. `Toolbox.Prices` (bottom): estimated values from SotANET's
  `GET /api/v1/receipts/prices?item=..` (<= 50 names) via `ShroudHttpGet`, one request `P.GAP` apart,
  cached per account for `P.MAX_AGE`; `P.Test` backs the Test connection button. SotANET matches English names only;
  `P.OtherLanguage` (`ShroudGetClientInfo().languageCode` not "en*", read once) adds `P.LanguageNote` where
  prices are missing (header, row tooltips, settings, switching on, the test).
- `sounds.lua`: `Toolbox.Sounds`, six sounds (`S.DEFS`: buff_expiring, debuff_landed, and notify, ping, tap,
  mail for notifications: each source picks one; from API 34 loaded by handle, `S.Handles()`: the id at the call,
  `ShroudGetSoundState` for ready / failed, no name clash, a missing file refused at once; the name matching stays for
  older clients, `H.S.noSoundHandles`, and `H.S.failSounds[path]` fails a load; `N.SOUNDS` / `soundKey`; mail and expiring default to "mail", the
  "Doorbell", and a saved "notify" with the sound off reads as the source's default), plus skill_up and skill_down, which
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
  makes the next login, the same character's too, read every module's settings again (`T.FollowCharacter`). `Hud.FitScreen()` (API 31, from
  `ShroudOnScreenChanged`): every built strip past the right or bottom edge of `ShroudGetScreenInfo`'s uiWidth /
  uiHeight is moved inside and saved through its owner (`Hud.FitBuilt`; a shown one measured where it is by its laid-out
  size, a hidden one by its saved place and last set size); `Hud.Build` fits the strips it builds too, and `Hud.Refresh` one it first shows or resizes, by the cached `Hud.screen`
  (review 31: built hidden, it had no size yet) (harness `H.S.screen`, `H.screenChanged{...}`, `H.S.noScreen`).
  `Hud.SetOverlay(provider)`:
  one overlay drawn over the Toolbelt (the combat shout). `Hud.Rebuild(key)` rebuilds one
  module's own strip (a setting that changes its elements); a full `Hud.Build()` makes every strip's elements
  again at once, past the creation cap with a big strip (the buff block's 40 slots). At the end of the file,
  `Toolbox.Location` (LOC; owner, 2026-10-08): the location strip (scene, position rounded, compass heading from
  `ShroudGetPlayerCompassHeading`; hover = `ShroudGetLocationText`), its own `LOC.TICK` periodic setting text only
  on change, its width from the scene name's length (refit on a scene change); fishable water (API 32, `water`: a
  line naming the scene's kinds, "Fishable water: salt, fresh", hidden when none, `LOC.UpdateWater`; owner,
  2026-10-15: what a player who fishes can expect; the strip as wide as the line; read at a scene change, every
  `LOC.WATER_EMPTY_EVERY` s while empty for `LOC.WATER_SETTLE` s, then every `LOC.WATER_EVERY` s (30: a town's water
  decoration changes them, review 32); the nearest water, `ShroudGetNearestWaterType`, isn't asked: it took up to 28
  ms a call in game, 2026-10-14; harness `H.S.water`, `H.S.sceneWater`, `H.S.noWater`); controls (and its Position rows: `POSITIONED`'s
  page field) on the "Map & location" page (`C.MapSection`, key "map", with the run markers' toggle; owner, 2026-10-13:
  the home for map features to come).
  The shown overlay's line (owner, 2026-10-18; setting `overlay`, `LOC.UpdateOverlay` on an `OV.version` / scene /
  character change; "Map: no overlays here" without the arrows in a scene with none, owner 2026-10-18: hidden, it
  looked missing): `<` / `>` buttons (`loc_ov_prev`, `loc_ov_next`, before the text so
  they stay put, like the pin before the scene name) and "Map: <name> (N places)", as wide as the scene's longest name (`LOC.OverlayChars`: stepping moves
  nothing; owner, 2026-10-18), calling `OV.Step` through `OV.StepOrder` (yours, Gathering, its kinds, Fights, its creatures, then
  none); `/toolbox overlay next|prev`. A step isn't saved at once (it joins `ovPending` with the selection it replaced, once a scene a
  batch, put back by `autoUndo` if the batch is refused, review 62; saved with the next batch or `T.SavePrefs`) and the markers and title wait `OV.STEP_SETTLE` s after the last click (`ovMarks.holdUntil`).
  Then `Toolbox.Overlays` (OV; owner, 2026-10-13): map overlays, named sets of places (`/toolbox mark`, `/toolbox
  overlay`), each BELONGING TO ONE SCENE (owner: a place is only good on its own map; 1,000+ scenes): a scene lists only
  its own (`OV.List(raw)`, `OV.MAX` 10 a scene), shows STRICTLY ONE (the 50 markers a scene; `OV.SCENE_MAX` 39 places an
  overlay, beside the run flags' 10 and the last death) and remembers its own shown one; per character; each place its own icon and color
  (owner: the overlay's look restyled every mark), the overlay's `icon` / `color` being the next marks' ("Set look",
  `OV.SetPlaceLook`, `/toolbox mark look`). Room (owner, 2026-10-13): the game's 256 KB is a whole FILE's, so the
  overlays of all scenes share `OV.BUDGET` (150,000 estimated) of the character file: places are packed into text
  (`packPlaces`: "id|name|x|y|z|shape|color;...", whole metres), a scene's read (`OV.Places`, `unpackPlaces`) only when
  needed, and a change that wouldn't fit (`ovSave`: `T.SavedSize` of the form AS SAVED, `T.ForSaving`'s escapes
  included (review 37), unless it frees room; or the file full,
  T.Save's "full") is undone and refused by name (owner: a failed mark must say it was the mark: `OV.MarkFailed`,
  `OV.RoomNote` past `OV.WARN`; a first mark makes its "Places" overlay in the same save, review 38); `/toolbox overlay scenes` (`OV.Scenes`) and `forget <scene>` (typed twice in
  `OV.FORGET_CONFIRM` s, `OV.Forget`) make room. Every change is undone in memory when its save fails (`ovSnapshot` /
  `ovSave(snap)`, review 34), and every command and button says so. Marking happens in the Map overlays window (owner:
  not the whole settings page; id `toolbox_marks`, the 8th window's third user, `T.TakeSharedWindow`), opened by the
  location strip's pin (`loc_pin`, launcher.png's map-pin frame; setting `pin`), `/toolbox overlay window` or the
  Map & location page's button (all the page keeps): shown overlay, New / Rename / Delete (`OV.CONFIRM`), next look,
  Mark here, the shown overlay's places (Compass, Set look, Remove), "Map storage: N% used" (`OV.StorageText`). `OV.Sync`
  (T.Tick, after each change) mirrors `DD.SyncMarkers`: ids "ov<overlay>-<place>" (a switch moves none), ours unwanted
  ("ov") come down, one already up as wanted isn't sent again (its note, the overlay's name, compared too, review 35; a
  "rate" refusal after a big switch retries after `OV.RETRY` s, sending only what's missing). The run flags stay their
  own toggle (owner); later ideas: a death flag and sharing one as a text
  string (no clipboard API; a TextField takes 1,024 characters). The auto map (owner, 2026-10-14; `OV.OnGathered` from
  core's `ShroudOnGatherResults`, `OV.AutoMark`): on per scene (`sc.auto`: true / false as switched there, absent =
  the default, `OV.AutoByDefault`: on in an adventure area, off in a town, owner 2026-10-18, crafting in a town marked
  its trunks and stations; `OV.SceneKind`: `ShroudGetSceneInfo`'s isPot / isBasement / isOverworld (read by `T.Field`: a game
  object too, review 63; harness `H.S.sceneInfoObject`), else the scene id's
  words, `OV.TOWN_WORDS`; the `location.autoNew` setting, `ov_auto_new`; `OV.AutoText` says which, and the window's `mw_autoline`, `OV.AutoSceneLine`, over the switches, owner: "make it
  clear they're scene specific"; harness
  `H.S.sceneInfo`; window toggle `mw_auto`, `/toolbox overlay
  auto`), each node finished is marked where you stand in its kind's overlay (`OV.NodeKind`: the node's name as sent)
  and in "Gathering" (`OV.AUTO_ALL`, every kind in its kind's look), unless one of its kind is within `OV.AUTO_NEAR` m
  there; `OV.AUTO_MAX` automatic overlays a scene (one kept for Gathering), counted apart from the player's `OV.MAX`
  (`OV.OwnCount`); a kind named like one of the player's gets " (auto)", then " (auto 2)"... (review 44). Fights (owner, 2026-10-18; `sc.fights`, window toggle `mw_fights`, `/toolbox overlay auto fights`):
  `OV.OnCombat` from core's `ShroudOnCombatEvents` marks each kill (`D.IsKill`) where you stand (no creature position
  in the API) in "!" + its name's overlay and in "Fights" (`OV.AUTO_FIGHTS`), unless within `OV.FIGHT_NEAR` m; their
  own `OV.AUTO_MAX` (`OV.AutoFight`, `OV.AutoKind`). The auto map's marks aren't saved one by one (a save walks every
  scene's overlays: 20 ms in the harness at 87% of the budget, far more in game): `ovPending` keeps them (their room
  estimated against `OV.BUDGET`, `autoUndo` to take them back), `OV.SavePending` writes them `OV.SAVE_AFTER` s after the
  first and out of combat (`OV.Tick`), and at once from `T.SavePrefs` (scene unload, shutdown, `B.SaveNow`); a refused
  batch is taken off the map. Each scene is its own saved key (`map_scene:<n>`, the index `map_overlays`; Saved vars
  below), so a save writes only the scenes changed: about 1 ms in the harness at any fill. Only overlays whose places changed are packed again (`ov.dirty`: set it wherever places
  change). Ignore list (owner, 2026-10-14: dozens of kinds a scene):
  `ignore`, name parts matched as whole words (`OV.IgnoredBy`), for every scene, at most `OV.IGNORE_MAX`; `OV.Ignore`
  also drops this scene's matching kind overlays and Gathering places (`OV.PlaceKind`: "Iron Ore 3" -> "Iron Ore");
  window button `mw_ignore` (two clicks: the shown kind, or Gathering's picked place's), `/toolbox overlay auto ignore
  [part]` / `unignore <part>`. Your last death (owner, 2026-10-14: only the last): `OV.OnDeath` from core's
  `ShroudOnDeathChanged(true)` keeps where you stand (`death`, one per character), drawn by `OV.Sync` as `OV.DEATH_ID`
  in its scene beside any overlay while `location.death` is on (Settings `ov_death`); `/toolbox death [compass|clear]`
  and the window's `mw_death` (the compass, in its scene only). It clears itself (`OV.DeathTick` from T.Tick, every
  `OV.DEATH_EVERY` s): back within `OV.DEATH_NEAR` m once `away` (`OV.DEATH_AWAY` m off or another scene; saved), or
  `OV.DEATH_KEEP` s old (`clock`) while in another scene. Look: a diamond in `OV.DEATH_HEX`, a color no place can have
  (the game's six shapes have nothing body-like; a death-like shape in `ShroudListMapMarkerIcons`, `OV.DEATH_SHAPES`, is
  used when one comes; harness `H.S.markerIcons`). So `OV.SCENE_MAX` is 39: 39 + 10 run flags + 1 = the
  game's 50. Harness: `H.S.markerAllow` (n sets, then "rate").
  Then `Toolbox.Launcher` (LN; owner, 2026-10-10; "the menu" to players, `/toolbox menu`, alias `launcher`): one button a window (`LN.BUTTONS`: its
  `open()` and `toggle()`; the pop-up windows count as open when pinned; Notifications = `N.ToggleWindow`, the news
  now in the window; Location shows or hides the location strip, `strip = true`: "show or hide" in its tooltip), pictures from `toolbox/launcher.png` (`art/launcher.py`, frames in `LN.BUTTONS` order) tinted
  `LN.COLOR` (@gold) or the player's pick (`LN.COLORS`, `LN.SetColor`: `SetTint` in place), `LN.LIT` / `LN.DIM` opacity as its window is open or not (its own `LN.TICK` periodic), text
  buttons without the picture. On by default, vertical, `HOME` = 0, 0; the first start without a saved
  `launcher` says so in chat once (per character). Settings last, Docs above it; a black shade behind (`shade` %,
  `LN.ShadeColor`, set in place), hide during combat (`BB.InCombatWindow`, `LN.Update` refits on a change), and
  which buttons show (`hide`; never all). Controls lead the "Menu, setups, backup & reset" page (`C.MenuRows`).
- `buffbar.lua`: `Toolbox.BuffBar` (BB), plus `Toolbox.Consumables` (K), `Toolbox.Gear` (G) and
  `Toolbox.BuffBlock` (MB, end of the file; owner, 2026-10-03).
  - Buff block: its own strip (never in the Toolbelt), every effect sorted by expiry (`BB.Tick` collects them
    when `MB.Collecting()`, `MB.Fill`), no group slot, debuffs outlined (`fill`'s `outline`), a fixed pool of
    `MB.SLOTS` (40; 60 in 1.2.0, lowered for the element budget) in rows of `MB.GetWidth()` (a width change rebuilds only its strip: `Hud.Rebuild`), its own
    size (in place) and combat-only. Short tooltips (`fill`'s `short`: name, debuff, `BB.CoarseLeft` to the
    minute), not the game's full ones: 60 full ones beside the buff bar's would break the text budget.
    No option for full ones either (owner, 2026-10-08, review 18 declined): 40 measured 55,068 characters at the
    worst against the 48,000 budget, and a cap that fits (about 100 each) shows little more than the short one;
    the buff bar has the full tooltips.
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
  topic shown is built, switching destroys the previous one, like the settings pages; each topic at most
  `D.TOPIC_MAX` (3,500) characters (the longest set the add-on's text peak, 2026-10-13: split a long one into topics;
  the commands, `D.CommandPages`, and a version's notes in the version window, `splitVersion`, split themselves into
  "(1 of 2)" parts), each label < 4,096 (the game's cut-off); update it with every user-facing change), the version window, and `Toolbox.Notify` (N): `N.SOURCES` (each with
  `Check(seen, ctx)` -> notice or nil, plus an optional quiet value; motd, mail, expiring, ransoms, rewards,
  applications, durability, friends, guild, and skills from skills.lua; a source's `vias` limits where it can
  go: `N.Allows`, `N.Choices(key)`), `N.DELIVERY` ("window", "hud" = `Toolbox.Notify.Hud`, "chat")
  plus a per-source `sound` (the notify chime once per check), and `N.Check` (tick, start, the social /
  notification / guild / friend events), which marks a notice seen only once delivered. `events` (API 35, the world
  calendar, read only): `N.EventsCheck` over `ShroudGetCalendarSummary().happeningNow` and the dates starting within
  `N.EVENT_LEAD` min (`T.Clock` for now), read at most every `N.EVENT_READ` s or after `ShroudOnCalendarChanged`
  (`N.CalendarChanged`). The social summary, guild message and notification counts are kept (`context`) and read
  again on a change callback (`N.Check(true)`), in the first minute's polling, or after `N.CONTEXT_EVERY` s (the 1.8.0
  perf runs: the 5-second poll was near 12 hitches a minute); `seen` = { [occurrence] = start as text }, dropped after `N.EVENT_KEEP` s unless still listed;
  `/toolbox events` (`N.EventsLines`). Harness `H.S.calendar = { status, rows, stronghold }`, `H.S.noCalendar`. The guild message
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
  Pause skills (owner, 2026-10-12, a player's request): a tile first on the strip (`sk_pause`, skillmarks.png frames 3
  and 4, cropped: a play triangle while skills run, gold pause bars while paused; a thin tile, `SK.PauseSize`; setting `pause`, shown always while paused; its own mode changes are `SK.Expect`ed, so they pop nothing up) and `/toolbox
  skills pause|resume` (a command is a gesture). `SK.Pause` sets EVERY skill (unlearning ones too; owner) to Off
  or Maintain (`pauseHow`) in ONE list call; `SK.PauseRecord` keeps `{ key, from, to }` in `skills_paused` (saved as asked BEFORE the call, no pause if that
  save is refused, then the game's answer read by `T.Field`; reviews 28, 29);
  `SK.Resume` sets back, one call per mode (at most three: a click's limit; `SK.ResumeGroups`: only skills still in
  `to`; a gone one would refuse the whole list), keeping every group the game didn't confirm (any reason, or an error; review 30). Harness: lists in `ShroudSetSkillMode`
  (`H.S.modeLists`), three actions a gesture (`gestureSpent`), `H.S.modeRefuse`, `H.S.modeThrow`, `H.S.modeObjects`, `H.chat` is a gesture, `H.skillPause()`, `H.clickSkillPause()`.
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
  "General" first, owner 2026-10-17: the text size and line spacing everything uses, `C.GeneralSection`; then Toolbelt;
  "Crafting", same day: the planner, its recipe book and its HUD; skills.lua's page goes after Combat, found by key):
  only the one shown is built; switching destroys the previous one first (every page kept
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
  debuff_landed steps down, notify rises; ping, tap and mail (a doorbell, D6 A5 D6) are the other notification sounds; craft_done (a
  fanfare, three G5s into a C chord) is the Crafting Planner HUD's; skill_up, a rising
  arpeggio into a ringing chord, and skill_down, sinking "wah wah" notes, and skill_train / skill_maintain /
  skill_unlearn, two quick notes up, even and down, belong to skills.lua; block, parry and
  dodge, a thud, a clash and a whoosh, to combat.lua's shout), `launcher.py` (-> `toolbox/launcher.png`: the
  menu's ten button pictures (in `LN.BUTTONS` order), white line art with a dark edge, tinted in game). Re-encoding changes the bytes even when the audio is the same:
  `git checkout` an .ogg you didn't mean to change. A player's own `Lua/toolbox_<name>` sounds win.
  Effect sounds (owner, 2026-10-08): a player's file per buff / debuff, for when you get it ("get": a debuff's
  landing, or a buff appearing outside the settling, `timers` empty) and / or when it's about to run out ("end": the
  expiry `fire`, debuffs too) (`BB.EffectSound(name, when)`, `BB.PlayAlert(when, names, usual)`: each one's own file
  once, the usual sound for the rest; an own sound plays with the general alert off; muted / Don't repeat apply;
  clips matched by their exact name first, "heal" not "heal on"), loaded by path (`S.UseFile`, keys "file:<path>", at most
  `S.FILES_MAX` a session: clips can't be unloaded; a missing file doesn't count, review 27) at the alert's volume (`S.PlayFile(path, kind)`); a file that
  won't load plays the usual sound and chat says so once; it holds no clip name, so its corrected path is taken (review 26),
  and a saved path refused for its name (saved before the check) is told in chat once a session (`BB.refusedTold`). Picked in Muted effects' dropdown (one list on screen: the
  text budget; the Sounds page's "Go to effect sounds" opens it, `C.GoToControl`), `/toolbox buffs sound [get|end]
  <name> = <file>`.
- `tools/`: `check.py` (all checks), `build.py` (packaging rules, the source checks, the store README
  renderer's rules, the support URL's form, the root README's API line, the changelog section, the docs API
  constants; stamps `build = "<commit>[+]"` into dist), `beta.py` (`make beta`), `install.py`,
  `release_notes.py` (a version's CHANGELOG section, for the release workflow), `recipes_from_chatlog.py` (not shipped; owner, 2026-10-19: the
  recipe book exported through chat, `TBXR1` lines in the game's chat logs, into one JSON file for comparing with the
  wiki; its docstring is the line format, `--self-test` in the check). The in-game exporter, a hidden
  `/toolbox recipe export`, was built and removed the same day (owner: it waits on client and wiki work; it is
  commit ba1e037, to bring back with `git revert` of its removal).
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
  in a saved var (a whole saved-variable file is capped at 256 KB; owner, 2026-09-30).
- **A feature:** pure logic over plain data, API calls at the edges, hooked into `ShroudOnStart` /
  `Toolbox.Tick` / core's callbacks; a `Toolbox.Foo` table; tests; a CHANGELOG `[Unreleased]` entry; the
  guide (`D.SECTIONS`) and both READMEs if players see it.
- **A HUD strip:** a Hud module (above). There are 14 strips already (location and launcher included) (25 frames, if the 2026-10-01 raise holds in
  game; 8 before): still prefer a Toolbelt row.
- **A window:** there is no slot (see Limits). Use a view of an existing window.

## The test harness

`tests/harness.lua` models the documented host: constructors and `Shroud.Command` raise outside a callback
and reject unknown fields; saved vars have a memory cache and a "disk" copy updated on flush; destroyed
element trees raise on use and leave their parent; margins / paddings are clamped; a style property the reference
doesn't list raises (the game refused a whole settings page over `flexBasis`, 2026-10-10: it showed blank); the element-creation cap,
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
  `H.S.httpRefuse`, `H.S.saveRefused` / `H.S.refuseKeys` (every saved-var write, or those keys), `H.S.language = { "German", "de" }` / `H.S.noLanguage`
  (the client's language; read at load: set it, then `H.reload()`), `H.S.pos = { x, y, z }` (where you stand,
  `ShroudPlayerX/Y/Z`), `H.S.sceneRaw`, `H.S.beacon` (`ShroudSetBeacon`'s), `H.S.noMap` (the beacon refused),
  `H.S.noApi29`, `H.S.heading` (the compass heading), `H.S.char.tags` (added to the display name, same file), `H.S.recipes` (API 37 fields as given; `ShroudGetRecipeBook` from them, `H.S.noRecipeBook`, `H.S.bookCalls`), `H.inventoryChanged()`, `H.S.showRefused`; `element.laidOut = { w, h }` sets what GetSize reports.
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
| `compact` | `{ shade = 0..90 (% black behind the HUD strip; default T.SHADE_DEFAULT, 60, every strip alike), open = bool, x = number, y = number, hover = bool, hud = bool, compact = bool, hx, hy }` (hx/hy: the HUD strip; compact: an API 19 compact window) |
| `daily` | see the header comment of `daily.lua` (format `v = 1`) |
| `daily_window` | `{ shade = 0..90 (% black behind the HUD strip; default T.SHADE_DEFAULT, 60, every strip alike), open = bool, x = number, y = number, hover = bool, hud = bool, compact = bool, hx, hy }` |
| `daily_detail` | `{ open = bool, x = number, y = number, values = bool, each = bool (the price each in the count: "40 x 5g"; default true), view = "looted"/"crafted"/"gathered", include = bool, markers = bool (runs on the map, API 30; default true) }` |
| `buffblock` | `{ show = bool (default false), width = 1..30 (icons a row, default 10), size = 20..64, combatOnly = bool, x, y }` |
| `buffbar` | `{ show, size = 20..64, expire, expireSeconds = 1..60, debuff, flash, groupAfter = seconds (a GROUP_AFTER_CHOICES value, 0 = off), groupCats = { [category] = true }, countdown = bool, countdownSecs = 5..120, group = { name parts }, quiet = { exact effect names, <= BB.QUIET_MAX } (muted: no expiry / debuff sound), quietNames = { [muted rune name] = its shown name } (for the lists when it isn't on you), effectSounds = { [rune name] = { shown, get = path, ["end"] = path } } (paths in the Lua folder, `S.CleanPath`;
<= BB.SOUNDS_MAX: the effect's own sounds, `BB.PlayAlert`), repeatQuiet = a BB.REPEAT_CHOICES value (seconds, 0 = off: an alert within that long of the same effect's last one, counted per alert kind, is quiet: `BB.Repeats`), replaceStock, clickDismiss, combatOnly, x, y }` |
| `sounds` | `{ v = 3, volume = 0..100, paths = { [sound key] = "..." }, levels = { [sound key] = 0..100 } (unset: `base`), base = 0 / 100 }`: `base` decided once a character, 0 (`S.LEVEL_NEW`) for a new one (owner, 2026-10-23: sounds off by default), 100 for one that ran Toolbox before (`T.knownCharacter`, `T.KNOWN_KEYS` read before any module saves) or a v = 2 file; a player's effect file plays at 100 until its alert's level is set (`S.EffectiveVolume`); a volume without `v` (before 2026-10-07's louder sounds) is halved once (`S.Init`). Harness: `H.boot` seeds a returning character's `sounds` (base 100) unless `H.newCharacter`. Played at volume x level / 100, twice that for a player's own file (`S.EffectiveVolume`), at most 100 |
| `buff_timers` | `{ v = 3, timers = { [rune name] = { total, remaining, at = T.Now() } } }`: trusted totals, for a reload |
| `buff_durations` | `{ v = 2, durations = { [rune name] = seconds } }`: full durations learned from casts |
| `vitals` | `{ shade = 0..90 (the Dark panel's %, default 60), show, width = 20..400 (bar length at 100%), scale = 75..250 (%), showText, showBars, bg = "None"/"Dark"/"Light", flash, flashBelow = 1..95, vigor = bool, replaceStock = bool (API 28: hide the game's player-frame bars), x, y }` |
| `hud` | `{ glued = bool, x, y }` (the glued strip's position) |
| `combat` | `{ show, scale = 75..250 (% of the General text size, `T.Window.GetFont`; rows follow `T.Window.GetSpacing` too), pet, stats = { "MagicResistance", ... }, bg = None/Dark/Light, bgOpacity = 10..100, x, y }` |
| `combat_detail` | `{ open = bool (pinned), x, y, scope = "fight"/"session", hover = bool }` |
| `combat_shout` | `{ on = bool (default false), size = 12..32, kinds = { block/parry/dodge = { text = bool, sound = bool, color = a CS.COLORS token } } }` |
| `consumables` | `{ show = bool (default true), glue = bool, extra = { name parts, <= 20 }, cats = { [category] = true } (absent: defaults), exclude = { name parts } (absent: Scroll, Torch, Bait), max = 1..10, combatOnly = bool, x, y }` |
| `gear` | `{ show = bool, threshold = 5/10/15/20/25/30/50 (percent), glue = bool, x, y }` |
| `target` | `{ shade = 0..90 (the Dark panel's %, default 60), show = bool (default false), glue = bool (default true), place = "top" (default) / "bottom", mirror = bool, effects = "all"/"debuffs"/"none", icons = 1..8 (unset: 8, or 5 mirrored), bars = bool (default true), numbers = bool (default false), bg = "None"/"Dark"/"Light", flash = bool (default false), flashBelow = 1..95, name = bool (the target's name above its bars; mirrored, a right-aligned line over the whole block, the Toolbelt's columns
lowered by `TG.TopRoom` in `Hud.Refresh`; shown with the bars or numbers; default false;
owner 2026-10-19, a player's request), x, y }` (a saved place "left", from beta 7, reads as mirror; bars and numbers both off = just the effect icons, refused with effects "none" too; hidePet = bool (default true): your pet as the target reads as no target, `TG.IsPet`) |
| `loot_runs` | `{ v = 1, list = { { at = "HH:MM", date = "YYYY-MM-DD", scene, played = s, gold, kills, items, kinds, nodes, value = estimated gold or nil, spot = { scene, raw, x, y, z } or nil } } }`, newest first, at most `D.RUNS_KEEP` (10); stats: a reset keeps it |
| `location` | `{ shade = 0..90 (% black behind the HUD strip; default T.SHADE_DEFAULT, 60, every strip alike), show = bool (default false), facing = bool (default true), water = bool (default true; API 32), pin = bool (the Map overlays pin, default true), overlay = bool (the shown overlay's line, default true), autoNew = bool (the auto map on by default in adventure areas, default true), death = bool (your last death on the map, default true), x, y }` (the location strip, hud.lua) |
| `launcher` | `{ show = bool (default true), vertical = bool (default true), size = 20..64 (default 32), color = an `LN.COLORS` token (default "@gold"; owner, 2026-10-16), shade = 0..90 (% black behind, default T.SHADE_DEFAULT, 60), combat = bool (hide during combat), hide = { [button key] = true } (never all), x, y }` (the menu, hud.lua; absent = never started: the chat line) |
| `map_overlays` | the index: `{ v = 3, nextId, nextKey, scenes = { [scene id] = n }, ignore, death }` (below); each scene in its own key (owner, 2026-10-18) |
| `map_scene:<n>` | `{ raw = scene id, scene = its name, shown = overlay id or 0, auto = bool (the auto map switched on / off there; absent: the scene kind's default), fights = bool (the same for fights), list = { { id, name (<= 24, unique in the scene), icon = an OV.ICONS shape, color = an OV.COLORS name (the next marks'), nextPlace, places = "id|name|x|y|z|shape n|color n;...", auto = a node kind, "*" for Gathering, "!" + a creature's name, or "!" for Fights (made by the auto map) } } }`. The index's ignore = { name parts the auto map skips }, death = { raw, scene, x, y, z, at = "HH:MM", date, clock = T.Clock() at death, away = true once you've left it } (your last death) (hud.lua; at most OV.MAX a scene, OV.SCENE_MAX places each, OV.BUDGET in all, every key together). v = 2 (1.8.0: every scene in `map_overlays`) and v = 1 (one list, places with raw / scene; development only) are converted at the first read: the index written over the old key first (both at once could pass 256 KB), the old value put back if a scene key is refused. A write (`ovWrite`) writes only the scenes whose form changed (`ovSaved`), deletes gone scenes' keys, then writes the index if it changed; refused at any step (a delete too, review 61), everything done is undone newest first, a conversion's new scene keys out before the old value goes back (review 60). `T.DeleteSaved` keeps a key measured until the game deletes it (harness `H.S.deleteRefuse`). The scene keys are measured at start through `B.KEY_LISTS`. Kept by a reset; NOT in the recovery copy (`B.OTHER_KEYS`: the account file's 256 KB) |
| `skill_levels` | `{ v = 1, high = { [skill key] = highest trainedLevel seen } }` |
| `planner` | `{ v = 1, scratch = bool, crafts = n, recipe = id, view = a PL.VIEWS name, makes = { [row path "p.1.2"] = true }, makers = { [item key] = recipe id }, picks = { ["r" .. id] = { at = n, ["s" .. slot] = item key } } (<= PL.PICKS_MAX), pickAt = n, hud = bool (the Crafting Planner HUD), hudStage = "shop"/"build", hudStay = bool, hudClose = seconds (PL.HUD_CLOSE), hudStart = "shop"/"build", hudAuto = bool (default true), shade = 0..90, book = a PL.BOOK_WHEN key (default "manual" from 1.9.1, "need" before; absent reads as the default), hx, hy, got = { [item key] = true } (the strip's shopping lines) }` (daily.lua's crafting planner; kept by a reset, not in the recovery copy: `B.OTHER_KEYS`) |
| `skills_paused` | `{ v = 1, how = "off"/"maintain", when = "HH:MM", list = { { key = skill key or name, from = mode, to = mode } } }`: the pause's record (skills.lua; empty list = not paused); kept by a reset, copied for recovery |
| `notify` | `{ v = 1, compact = bool (the window), font = 9..32 (the window; unset: the theme's), sources = { [key] = { on = bool, seen = last value delivered, via = "window"/"hud"/"chat", sound = bool, soundKey = one of N.SOUNDS (default "notify") } } }`; durability's `seen` is `{ [item key] = "low"/"broken" }`, events' `{ [occurrence] = start (UTC seconds, as text) }`; friends / guild don't keep `seen`; the older `guild_motd` `{ show, seen }` is read once to take over |
| `notify_hud` | `{ shade = 0..90 (% black behind the HUD strip; default T.SHADE_DEFAULT, 60, every strip alike), hideAfter = seconds (0 never, 5..60), font = 9..32, spacing = 0..12 (each unset: the XP windows'), x, y }` |
| `notify_history` | `{ v = 1, list = { { when = "HH:MM", title, text } } }`, newest first, at most 20 (which are new, `fresh`, is kept in memory only) |
| `prices` (ACCOUNT scope) | `{ v = 1, items = { [lower item name] = { avg = n or false (no sales), sold, last, day, at } } }`, at most `P.MAX_KEEP` (600, about 70 KB; 2,000 before 1.8.0, cut at start by `P.KeepSize`) |
| `welcomed` (ACCOUNT scope) | set after the first-run welcome |
| `version_seen` (ACCOUNT scope) | the last `T.version` started on this install: another one opens the version window once (`T.WhatsNew`, after the welcome's delay; a new install only notes it; absent = 1.7.0 or before) |
| `skills` | `{ show = bool (default false), vertical = bool (default true), slots = 1..12, stay = seconds (SK.STAY_CHOICES; 0 = always), trigger = "levels"/"xp", size = 20..64, number = bool (the level on the icon, default true), marks = bool (the API 27 training controls, default true), soundUp = bool, soundDown = bool (both default true), pause = bool (the Pause skills tile, default true), pauseHow = "off"/"maintain" (default "off"), x, y }` (skills.lua) |
| `ceiling_due` | `{ v = 1, ceiling, by }`: a learned account ceiling (`recovery_index`) not yet in the account file (core.lua, review 42); dropped once it is |
| `save_mark` | the number of the recovery copy last written (core.lua, `B.KeepRecovery`); a file without it while its copy exists is put back at start (`B.Recover`) |
| `recovery:<lower name>` (ACCOUNT scope) | `{ v = 1, n, when = "YYYY-MM-DD HH:MM", keys = { [a B.RecoverList() key] = its saved table } }`: settings (`B.KEYS`), `loot_runs`, `skill_levels`, `buff_durations`, written at the flush after one changed |
| `recovery_index` (ACCOUNT scope) | `{ v = 1, names = { lower name, ... }, legacy = bool, ceiling = n, by = lower name, dropped = true (API 39+: the copies deleted, `B.DropRecovery`) }`: the characters with a recovery copy, written BEFORE the copy (`B.IndexRecovery`), so `B.MeasureFiles` counts every copy; `legacy` = 1.7.0 ran on this install (its copies aren't listed until their character next plays, and the game can't list keys): `B.LEGACY_RESERVE` of the account file stays free for them (`T.ReserveFile`; review 36), a first guess (a 1.7.0 copy's learned buff durations have no cap). A flush the game refuses there (`B.FlushFailed`, from `T.Flush`, once a session; the game gives no reason) is first tried again unchanged (review 39: a passing refusal changes nothing); then room is made a step at a time (the price cache, this character's copy, the account changes since the last good flush: `T.accountUndo`, never the index itself, which only gains names, and a copy kept is listed: review 40), and if a step works everything is put back and flushed: only if that is refused is the size taken as why, the steps redone (the copy kept when the undo is room enough), and `ceiling` = the measure THEN less a margin (`B.CEILING_MARGIN`, at most a tenth) caps the file (`B.pendingCeiling` until a flush writes it: `B.KeepCeiling` before every flush, review 41; noted meanwhile in the learning character's own file, `ceiling_due`, read back at start, review 42; both refused: `T.Docs.Warn`'s window tells the player, and a restart before the next flush loses the bound, an accepted risk (owner, 2026-10-14, review 43: blocking all growth on every 1.7.0 install would cost far more)); `T.Flush` returns false, "full" when changes were undone (chat names them). `by` = whose session learned it: a copy listed later by another character was unmeasured then, so the ceiling rises by its old size (harness: `H.S.fileLimitAsGame` = the game's answer, not a raise) |
| `settings_pending` | `{ kind = "reset", backup = the game's copy made as it was asked (API 39) }`: done and deleted at the next start |
| `setup_share` | `true` = this character's copy is listed for the others (default off; a setting, but never copied into a setup or imported) |
| `setups` (ACCOUNT scope) | `{ v = 1, list = { { name, character = bool, when = "YYYY-MM-DD" } } }`: the setups' index, at most `B.SETUP_MAX` |
| `setup:<lower name>` / `setup_character:<lower name>` (ACCOUNT scope; the name in saved form, `%XX`; 1.6.0's plain-name key still read, moved at the next export) | `{ v = 1, name, keys = { [a B.KEYS key] = its saved table } }` (notify without `seen`): a named setup / a character's copy, kept by `B.KeepCopy` from `T.Flush` when a setting changed and `setup_share` is on |

Keys must be <= 128 chars with no `/` or `\`. **A whole FILE's JSON must stay under 256 KB** (every key of the
character scope together, and every key of the account scope together: confirmed 2026-10-13, below), not just one
key's. Always validate what
you read back and fall back to defaults.

## Releasing

**Last release: 1.9.0** (2026-10-20, the owner's go; the hold for requests 26, 28 and 29 moved to 1.9.1).
**Next: 1.9.1** (owner, 2026-10-18): 26 and 29 (the recipe calls) and 28 (API 43's `ShroudOnBeforeLogOut`, the plan
under "Waiting on the developers") once they reach the live client: use the new calls (feature-detected), check them
in game, then release. The map title's long name is fixed in build 323 (catnipgames.net, 2026-10-16), 27 (one Enter)
in build 2da431775a (2026-10-18): check both when they're live.

**After it: 1.10.0, the party manager** (owner, 2026-10-18; 1.9.x waits on client fixes meanwhile). In scope: (1) the
Party Toolbelt, its own strip, never joined to the player's Toolbelt (the idea below): a row per member, health and
focus bars, their debuffs, members elsewhere dimmed, the lowest flagged, sort by party order (default) or lowest health,
combat-only, yourself hidden by default (owner, 2026-10-18); effects: every debuff, plus the buffs the player names (a
watched list, whoever cast them: the API doesn't say who applied an effect; "only mine" waits on request 31); sized for 12 members (the game's party today) and able to take 16 (the owner expects a raise); (2) comings
and goings, a notification source (joins, leaves, leaving and coming back to your scene: `ShroudOnPartyChanged`, the
slot names against `ShroudGetPartyMemberNamesInScene`, names by `T.PlainName`, quiet for a few seconds after your own
scene change; offline shown only for a friend or guild member, from their lists); (3) watch alerts (a member below a
health level, a chosen debuff landing on one); (4) a Party view in Combat Detailed (damage, healing, damage taken per
member from the combat events' `party` flag; the last hits before a member reached 0). Maybe: a party buff check
(who lacks a chosen buff) and a "who's here" line. Not possible with today's API: targeting a member, positions or
range, others' cooldowns, add-on messages, a member's death or online state; asked as requests 30-32
(`tmp/client-issues.md`, submitted by 2026-10-20): a whole-party read with online / scene / dead / leader, who applied an
effect, and in range. Not asked: setting the target (owner, 2026-10-18: the developers could read it as automation).

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
v0.5.0 (820df19), v0.6.0 (03fdeef), v0.6.1 (6322846), v0.7.0 (2d07df7), v0.8.0 (9672d11), v1.0.0 (438a80d), v1.0.1 (1cfef96), v1.0.2 (fedf1ba), v1.0.3 (50bff65), v1.1.0 (26166ce), v1.2.0 (9077b9f), v1.3.0 (98e666e), v1.4.0 (7479419; withdrawn from the store before release), v1.4.1 (ad52e3f; never released in the store either: 1.5.0 followed it), v1.5.0 (84db2df; withdrawn from the store before release: the saved "/" data loss), v1.5.1 (073fe53), v1.6.0 (285e965), v1.7.0 (216b5ff), v1.8.0 (7d8d3f3), v1.9.0 (d7aaf6f).

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
  chat turns into a link; nil unless three finite numbers; used for a run's spot, `DD.LocText`). The area in the
  location text is the scene's English name (`Area: Ardoris (Novia_R4_City_Ardoris) Loc: (...)`), nothing finer, so
  runs use the coordinates. `/toolbox api` probes them. Requests 18 and 19 are
  not in it.
- **API 30-36** (docs 2026-10-12; `T.DOCS_API` = 36, `min_api_version` stays 25; `/toolbox api` probes each group):
  map markers (30: `ShroudSetMapMarker` etc., our request 20: per add-on and scene, session-only, 50 a scene, 10 s
  between moves of one id, 20/min after a burst of 50, hidden in PvP), `ShroudGetScreenInfo` / `ShroudOnScreenChanged`
  (31), fishable water (32: `ShroudGetSceneWaterTypes`, `ShroudGetNearestWaterType` within 30 m; request 25),
  `ShroudPickFile` (33, a gesture; request 23), sound handles (34: `ShroudLoadSoundHandle`, `ShroudListSoundPaths`,
  `ShroudGetSoundState`, the path on `ShroudOnPlaySound`; request 22), the world calendar (35, read only:
  `ShroudGetCalendarEvents/Event/Summary/Reminders/Tags`, `ShroudOnCalendarChanged`; at most one fetch of each kind
  per 10 s, all add-ons together), spoken expiry warnings (36: `ShroudPlayWarningSound`; not used, owner 2026-10-12:
  the game's own Announce Expiring Buffs option covers it). Requests 18, 19, 21 and 24 are not in it.
  The owner's live client has all of them (`/toolbox api`, 2026-10-13: every group present through API 35).
- **API 37-38** (docs 2026-10-14; `T.DOCS_API` = 38, `min_api_version` stays 25; the owner's live client reports API 38
  with every group present, `/toolbox api` 2026-10-14, and 1,764 known recipes): 37 is our request 18 as the developers described it (below): `ShroudGetRecipe` gains `station`,
  `stationKey`, `locations`, `favorite`; ingredients `group`, `carried` (every bag, nested, worn, locked: `have` stays
  the card's count), `key`, `stats`; a group slot `groupKey`, `chosenKey`, `choosable`, `choices` (<= 30: `name`, `key`,
  `have` when choosable, `carried`, `stats`), `choiceCount`; results `key`, `carried`, `stats`; keys "item:" + 32 hex,
  the same in every language, on `ShroudGetInventoryItems` / `ShroudGetEquipmentItems` rows too; stats rows `{ key,
  value[, name] }`; `ShroudGetRecipeBook([categoryKey])` = the known book in one call (the planner's read; until it's
  built `/toolbox recipe` prints the fields, `D.RecipeLines`). 38: `ShroudOnCalendarNowChanged()` (a date started /
  ended or the UTC day rolled; not on the first frame: core.lua -> `N.CalendarChanged`), Window `OnShow` / `OnHide`
  (and spec `onShow` / `onHide`; unused: the menu's open check is cheap), Image / IconButton `FollowHeading(on |
  { offset, reverse })` (the game turns it with the compass heading; unused: an idea for a needle on the location
  strip). `ShroudOnItemsGained` now documents dev report 24's fix: own-bag drags and pick-ups net zero, and the call
  waits while a bag item is on the cursor. `/toolbox api`: a "Recipe book (API 37)" group and an API 38 line told by
  `ShroudLuaApiVersion` (callbacks and element methods can't be probed). Seen in game 2026-10-14 (`/toolbox recipe
  plate chest armor`): every field as documented; the result's stats are base values ("weight 10, durability 220,
  resistance 9, avoidance 7, Magic Fizzle Chance 32": the fixed keys unnamed, a `stat:` row named); "Metal Sheet" is
  group:33 with 6 choices (Copper ... White Iron Sheet), each with a key and stats ("Iron Sheet: weight 2, Armor
  Damage Resistance 0.2"); no `chosenKey` until one is picked. A choice's values are for the recipe's quantity, as the
  reference says (Copper Sheet's Base Weapon Damage 0.05 for 10 sheets, 0.035 for the Augmented chest's 7; a binding's
  Focus 5 for 1, 10 for 2). At a station, `have` can exceed `carried` (7 Copper Sheets "have" with 0 carried):
  `have` counts what the craft can reach, the lot's trunks set "use this container for crafting" and the table
  (double-clicking a recipe moves its materials from those trunks onto the table: the game's "Took 7 Copper Sheet
  from Trunk" / "added to inventory" lines), while `carried` is only your bags, so it stays 0 for those and the choices come in the game's order, the ones you have first.
  Unclear: a sheet's stats list Base Weapon Damage on a chest armor recipe (the material's bonuses whether or not
  this item uses them?); `chosenKey` not seen yet (selecting a recipe isn't picking a slot's material). The guide's new "Keeping an add-on light"
  matches the house rules.
- **API 39-40** (docs 2026-10-15, with a new live client; `T.DOCS_API` = 40, `min_api_version` stays 25; `/toolbox api`
  probes both groups): 39, saved-file backups: `ShroudBackupSavedVars(scope)` copies the file AS ON DISK (flush first
  for the current values) to `<file>.<yyyyMMdd-HHmmss>` beside it (newest 5 kept, one a minute a file, an unchanged
  file returns the newest's name; noAddon / noFile / rateLimited / diskError), `ShroudListSavedVarBackups(scope)`
  ({ name, time = os.time seconds, size }, newest first), `ShroudRestoreSavedVarBackup(scope, name)` (keeps the
  replaced file as a backup, drops the cached values: read again; unflushed changes lost; badName / notFound / tooBig /
  unreadable / rateLimited / diskError). Used (owner, same day): `B.KeepBackup(scope)` before a reset
  (`B.RequestReset`: the settings flushed and copied BEFORE the request is stored, its name in the request for
  `B.ApplyPending`'s line, Codex review 51), an import (`B.Import`, `B.lastBackup`; it, Back up now and Restore
  first need `B.SaveNow` to succeed, else they do nothing: the game copies the file on disk, Codex reviews 52-53) and
  the first start of a new version (`B.UpdateBackup`,
  first in ShroudOnStart after the measure: the account file and that character's, on an install with `welcomed`;
  named in `T.WhatsNew`'s line); chat names each (`B.BackupNote`). Back up now and Restore (owner, 2026-10-16): `B.BackupNow`,
  `B.BackupList` (this character's file only: the account file holds every character's setups), `B.Restore` (flush
  first, so the replaced file's copy is current; a waiting reset in the copy, which the reset's own backup has, is
  dropped; then `T.FollowCharacter` with `settingsFor` cleared: every module reads again, the day and session carry
  on from memory), config's `bk_now` / `bk_pick` / `bk_restore` (two clicks; the list read at a page build, another
  character, an import and our actions: `C.restoreDirty`), `/toolbox settings backup|backups|restore <n>`; the
  recovery copies only for older clients (above). Harness `ShroudRestoreSavedVarBackup` (`H.S.restoreRefuse`, one a
  minute), names as the game's (`H.BackupName`). Harness `H.S.backups[file]` (with the disk
  copy), `H.S.noBackups`. 40, the map title (requested by the owner, #13082): `ShroudSetMapTitle(text |
  nil)` puts one line per add-on per scene in the full map's top-left corner, as "Toolbox: text" (<= 60 characters,
  cleaned like a marker label; at most three add-ons; rate 10 then 20 a minute, the same text free; nil / "" takes it
  down; bad_title / rate / pvp / no_scene; session-only like markers, so set again on a scene load), and
  `ShroudGetMapTitle()`. The title is used: `OV.SyncTitle` (from `T.ViewsTick` after the markers; `OV.TitleText`: the
  shown overlay with places, "loot runs" when `DD.MarkersIn(raw)` > 0, "last death"; set only when the text or the
  scene changes, a refusal retried after `OV.RETRY` s; harness `H.S.mapTitles[raw]`, `H.S.titleRefuse`,
  `H.S.titleSets`, `H.S.noMapTitle`). Seen in game (owner, 2026-10-16): the game prefixes the manifest `name` cut short,
  "Toolbox: Toolbelt, HUDs, Trackers, and mo: <text>", not "Toolbox: <text>"; a client bug, reported to the developers
  (nothing to change on our side). The location strip no longer asks `ShroudGetNearestWaterType` (owner, same day: the
  scene's kinds instead).
- **API 41-44** (docs 2026-10-18; the live client reports API 44, owner 2026-10-23; `T.DOCS_API` = 44, `min_api_version` stays 25; `/toolbox api` tells each, by version
  where there's no function to look up): 41, **30 windows per add-on** (8 before; the owner asked for 12): the shared
  8th window's users (Docs, version, Map overlays, the crafting planner) can have their own, planned with 1.10.0, and
  `T.TakeSharedWindow` kept for older clients; `ShroudGetInventoryItems` / `ShroudGetEquipmentItems` `weight` and
  `value` are one item's, with `totalWeight` / `totalValue` the stack's (before: the stack's; Toolbox reads neither); a
  window's right-click "Remember Size and Position" makes its `SetSize` / `SetPosition` change nothing and return false
  (Toolbox calls neither on a window). 42, the helmet: `ShroudIsHelmetVisible`, `ShroudSetHelmetVisible(b)`,
  `ShroudToggleHelmet` (a gesture; saved, seen by others; unused). 43, request 28: `ShroudOnBeforeLogOut` and
  character-scope writes refused with no character (above; used from 1.9.1). 44, item names as plain text (#13710:
  `[u]...[/u]` and color tags stripped; inventory and equipment names). Not in them: request 27's fix (client only),
  26 and 29.

**Waiting on the developers:** **33** (submitted by 2026-10-20; `tmp/client-issues.md`): files an add-on
writes itself (`ShroudWriteDataFile` / `ReadDataFile` / `DeleteDataFile` / `ListDataFiles`, JSON), in a folder beside the
package (an update installs only the manifest's files), kept through updates, confined, written safely; for exports
(runs, overlays, setups) and data past the 256 KB saved files (a recipe cache, long history). Until then there is no
file write: saved vars only. **34** (submitted by 2026-10-20): open the Skills window at a skill (a third
`ShroudToggleWindow` argument or `ShroudShowSkill(keyOrId)`, on a gesture); until then the skill strip's click opens
the window wherever the game left it (the owner asked, same day). **35** (submitted by 2026-10-20; a player's request): the target's
difficulty as the game shows it, its "con" tier and color (`ShroudGetTargetDifficulty()`); until then the target HUD
shows its name only (`target.name`), no guessed color. **36** (submitted by 2026-10-20; a player's request):
`ShroudCanDismissPetBuff` / `ShroudDismissPetBuff(runeIdOrName)` on a click, as the pet window's right-click; a pet
strip (the pet's health and its effects at Toolbox's icon size, `ShroudGetPetBuff`, `ShroudGetPetInfo`) waits for it,
since removing a pet buff is what players want the bigger icons for. A read-only game settings API (first use: the game's "stack buffs lasting
longer than" option feeding `BB.GroupAfter()`). Submitted 2026-10-07 (`tmp/client-issues.md`): **18**, for the
crafting planner (ingredient choices for slot categories, item stats, language-independent item keys, a `have`
that counts containers, the recipe book in one call, the station a recipe needs), and **19**, the saved "/" data
loss (Toolbox is protected: never saves a "/"). **20** (submitted 2026-10-08): add-on markers on the region map and minimap (an
icon, a label and a hover note per marker, scene-scoped, display only, rate-limited, local); until then a run's spot
uses the shared beacon on a click (`DD.MarkRun`). **21** (submitted 2026-10-08): a negative number in saved vars
makes the loader refuse the whole file ("Unexpected token : '-'"), which the next save then overwrites, like 19
(Toolbox is protected: `T.SetSavedVar` and the "%N" numbers above). **22** (submitted 2026-10-08): sound handles (the
clip's path beside its name in `ShroudListSound`, a handle from `ShroudLoadSound`, or a list per add-on); until then
an effect file named like another sound's is refused (`S.UseFile`). **23** (submitted 2026-10-08): a file picker
(`ShroudPickFile(kind, callback)` from a click: an in-game browser of the Lua folder, or the system dialog copying
into `Lua/<slug>_files/`); until then players paste a path (`S.CleanPath`). Landed in API 33: `S.Pick(title, done)` (Choose... on the Sounds page,
`C.ChooseSound`; Choose a file... for effect sounds, `C.ChooseEffectSound`, the effect and when taken as the list
opens), built only when `S.CanPick()`; the picked path still goes through `S.CleanPath`. Harness: `H.S.pick`,
`H.pickFile(path)`, `H.S.noPicker`; `H.click` is a gesture. **24** (submitted 2026-10-08): one caught
fish arrives as two `ShroudOnItemsGained` calls about 4 s apart, each x1 (`/toolbox loot log`), so the Loot Tracker
counts fish twice; no workaround (owner, 2026-10-08: wait for the fix). **25** (submitted 2026-10-08): the kind of fishable water at a position
(`ShroudGetWaterType(x, y, z)`) or a scene's list in `ShroudGetSceneInfo()`, for the location strip; nothing in the API
describes water today (a caught fish's name, "(Saltwater Fish)", is the only hint); no stopgap (owner: wait for the API); landed in API 32, used by the location strip. **28** (submitted 2026-10-16): a callback before
the logout while the character is still in (`ShroudOnBeforeLogOut`), and a character-scope write with no character
refused instead of stored in a "nochar" file; until then Toolbox saves at `ShroudOnSceneUnloaded` while a character
is named and skips character writes without one (`T.NoCharacter`). Done (the developers, 2026-10-18: build
094495886b, API 43; on the live client by 2026-10-23, API 44): `ShroudOnBeforeLogOut` runs once on
Exit to Menu / Quit with the character still in, the saved vars flushed right after; a logout not chosen (lost
connection, kick, idle) runs it late at the login screen, before the logout flush, still keyed to that character, but
`ShroudGetPlayerName` and such may be nil there. With no character, character-scope `ShroudSetSavedVar` /
`ShroudDeleteSavedVar` return false (one console line an add-on) and `ShroudGetSavedVar` nil. In the reference since
2026-10-23 and BUILT for 1.9.1: `ShroudOnBeforeLogOut` (core.lua) saves the session, the day, the timers and
`T.SavePrefs` (only `OV.SavePending` when the name reads nil: the late case, places would be the corners), `T.leaving`
naming whose file it is meanwhile, `T.logoutSaved` so `ShroudOnSceneUnloaded` doesn't save it all again (cleared at the
next login); older clients keep `ShroudOnSceneUnloaded`'s. A game refusal of a character write with no character in
the world is `T.SetSavedVar`'s "no character" too, and `T.Save` says nothing for that why (a player's "Could not save
'daily'", 2026-10-22), nor `OV.SavePending` (the batch kept, no `autoUndo`); `LN.Init` neither prints the menu's line nor
saves at the login screen. Harness: `H.S.api43` (set after `H.boot`: the refusals and `ShroudOnBeforeLogOut` in
`H.logout`), `H.lostConnection(stay)` (the late call, `S.char.leaving`). Check a logout, a lost connection and a
character switch in game. **26** (submitted): the known recipes that make an item
(`ShroudGetRecipesMaking(itemKey)`, or a light recipe book), so the planner needn't read the whole book (`D.ReadRecipeBook`,
about 90 s a login; near 22 of 23 hitches in the owner's perf run, 2026-10-16, single `ShroudGetRecipe` calls of 260 and
519 ms). **29** (submitted 2026-10-16, after 26): item counts without reading recipes
(`ShroudGetItemCounts`), a lighter `ShroudGetRecipe(id, { choices, stats, counts = false })`, and a cheaper full read;
until then the planner re-reads its recipes for the counts (`PL.REFRESH_GAP`). Everything reported is fixed: the API 25 client issues, and
(work log 2026-09-30, `ac63e8c01b`, **API 26**, in the next client build, not yet in the owner's) the party
ones (`tmp/client-issues.md` 14, 15): the slot getters reach the whole party (slot 0 = you, then party-frame
order, so `for slot = 0, count - 1` finds everyone, buffs included), `ShroudGetPartyMemberNamesInScene()`
returns a plain list of real names, and `for v in list do` over a table walks its values.

**The developers' answer** (2026-10-13, to the owner; nothing rejected):
- **18** is built as **API 37** (in the reference and on the owner's live client since 2026-10-14, above).
  - `ShroudGetRecipe` gains `station`, `stationKey` and `locations`.
  - A slot ingredient ("Metal Sheet") gains `group`, `groupKey`, `choosable` and `choices`: each with `name`, `key`,
    `have`, `carried` and `stats`, at most 30, the total in `choiceCount`.
  - Ingredients and results gain `key`, `carried` and `stats`. `carried` counts every bag (nested too), locked items and
    bags kept from crafting; `have` stays the recipe card's count.
  - Keys are `item:<guid>`, the same whatever the client's language, and `ShroudGetInventoryItems` rows carry them too.
  - Stats rows are `{ key, value }` plus a translated name; results give base values (material bonuses and exceptional
    crafts add on top).
  - `ShroudGetRecipeBook([categoryKey])` gives the whole known book in one call.

  This unblocks the crafting planner, and perhaps prices on other-language clients (the keys).
- **19 and 21** (the saved "/" and the negative number) are fixed since chaos build 318 (2026-10-12). A file an older
  build couldn't read is kept beside it as `<file>.unreadable-<date>`: renaming it back restores the values (worth
  telling players who lost settings). Keep Toolbox's escaping and "%N" numbers: players on older builds still need
  them (`min_api_version` 25), and the 1.6.0 and earlier saves must still read.
- **24**: not the server. Picking an item up with the cursor takes it out of the bag, and putting it down counted as a new
  gain: a fish dragged into a bag right after the catch, and ANY drag between your own bags, reached
  `ShroudOnItemsGained` twice. Fixed for the next build (the API 38 reference documents it); the Loot Tracker keeps counting as it is (until then, a drag
  between bags counts as loot).
- Not covered by their answer: 16 (the reference not mentioning `SetSweepTimer`'s one-day limit), 17 (a clipped wedge), and
  the read-only game settings API, never sent as a numbered request.

**Ideas, not agreed** (more in FUTURE.md, the owner's list for later: a farmer's helper): a **Party Toolbelt** (owner, 2026-09-29): a dedicated party strip, separate from the
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
Iron Ingot -> ore and coal). BUILT (2026-10-15: `Toolbox.Planner`, daily.lua, above). Decided (owner, 2026-10-15, the 1.9.0 feature): its own window, the SHARED 8th
(`T.TakeSharedWindow`, beside Docs, version and Map overlays), not a Loot Tracker view. Slot choices serve both kinds
of crafter (owner: "some just use what they have, others craft for stat combos for their builds"): "Use what I have"
(default: each slot's first choice you have enough of, in the game's order) and "Stats I care about" (a stat picker;
each choice shows those stats, sorted by the first; a preview totals base + the picks; the player picks each slot;
remembered per recipe kind); no automatic best-combination pick yet. "From scratch" on: a choice you lack gets "Make it" (built as an "I'll craft" tick, owner 2026-10-15)
(the shortfall crafted, its recipe expanded into the shopping list and build order; an unknown recipe = "buy"; nested
slots get their own pick); off: the plan stops at the slot. To check in game: whether a material's stats that don't
fit the item (Base Weapon Damage on a chest) apply. Also a gathering session HUD; lock-position / snap presets for strips
(only if a strip's grip can be hidden).

## Game behaviour (confirmed in game)

Rules learned the hard way; keep to them.

- **Saved-variable size** (confirmed 2026-10-13, `tmp/savelimit.lua`): the 256 KB cap is per FILE (the add-on, the
  scope and the character: "saved variables for 'savelimit|character|shawn' exceed the size limit; not written"), not
  per key. Two 150 KB keys: each `ShroudSetSavedVar` returned true, the flush returned false and NOTHING of that file
  was written (the old file stays on disk). So `T.SetSavedVar` keeps each file's estimate (`T.fileUse`, measured whole
  at start and for another character by `B.MeasureFiles`: `B.RecoverList()`, `B.OTHER_KEYS` (a module's own keys
  appended), the account's prices, setups and recovery copies; kept by every write and `T.DeleteSaved`) and refuses a
  write that would take its file past `T.FILE_MAX` (third result "full", chat names the key once); one that shrinks
  it is always taken. The account file holds the prices, every setup and every character's recovery copy; a full one
  (600 prices, 20 setups, nine characters) measures about 98 KB estimated (`test_stress.lua`). The harness raises at a
  flush for a file past 256 KB (`H.JsonSize`).
- **Limits** (per add-on): 8 windows, 30 from API 41 (Toolbox has 7 lasting ones; Docs, version and Map overlays share the 8th: `T.TakeSharedWindow`; the planner's book notice is a 9th from API 41), HUD
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
  `justifyContent` takes "start", "center", "end", "space-between" or "space-around", not CSS's "flex-end" (the game
  refused a window over it, 2026-10-23; the harness checks it). Labels carry theme side margins: set `marginLeft`/`marginRight` = 0 where widths must add up. Before API
  25 `height` alone didn't size a label (a theme minimum won), so labels and bars pin `minHeight`/`maxHeight`
  (`Toolbox.Window.LineStyle` / `TextStyle`); harmless now. Rows can lay out taller than asked: measure with `GetSize` when
  things must line up. Hidden elements take no space. A colour's alpha doesn't fade children (`opacity`
  does). An `Image` with an `onClick` shows its tooltip. `rotate = 180` mirrors a Bar's fill.
- **Theme:** `inset` is a dark panel with shaded edges (the Dark backgrounds use `#000000` + alpha instead: every HUD
  strip's panel is black at its own `shade` %, `T.ShadeColor` / `T.ShadeOf`, all `T.SHADE_DEFAULT` (60) at first, owner
  2026-10-15; the game has no opacity for HUD frames);
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
- **Several effects, one rune** (confirmed 2026-10-08, Blessing of Atos: +5 Health and +5 Focus for 72 h, +12.5%
  crit damage reduction for 24 h): each effect takes its own place in the flat list, and each place's
  `ShroudGetBuffTooltip` names only its own benefit ("Blessing of Atos / You / +5 Focus / 71:58:42"). One icon per
  rune, so `BB.EffectTooltip` merges them (the target's too); `/toolbox buffs tips [name]` prints each place.
  `ShroudGetBuffDescription` is the first place's benefit ("+5 Health"), so the name shown (`plainLabel`) is the
  tooltip's first line, the description only as a fallback; players' name parts match both (`matchFor`); muted
  effects stay keyed by rune name, shown by name (`BB.ShownName`, the rune name in brackets for two alike).
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
- **1.6.0 work** (confirmed 2026-10-08): the Loot Tracker's Runs view and chart, the game's health bars back while a
  combat-only Toolbelt hides, don't repeat, the merged several-effect tooltips, effect names from the tooltip's first
  line, and the setups' confirmations and sharing.
- **Window positions** (confirmed 2026-10-08): XP Detailed dragged partly past the left edge saved no negative number
  (`window` in the character file), so 1.6.0 doesn't save a negative position; no 1.6.1 (owner). Today's saves
  encode one anyway.
- **The menu** (confirmed 2026-10-10): the gold-tinted launcher.png buttons, lit / dimmed by opacity, the black
  shade behind them, and the panel pinned to its size with `alignItems = "center"` (unsized, a vertical one was as
  wide as its frame and its buttons sat to the left).
- **64 px icons** (confirmed 2026-10-09): the Icon size maximum (`BB.SIZE_MAX`, `SK.SIZE_MAX`) draws fine: the overlays
  pulled back by the icon's size (wedge, count, skill level and marks) stay on it. Past 64 they'd need another way
  (margins clamp at -64).
- **Skill level click and save protection** (confirmed 2026-10-10): a click on the skill strip's level number (the
  labels over the icon, markers off) still reaches the icon and opens the Skills window; the saved-value escaping and
  recovery work in game.
- **1.7.0 work** (confirmed 2026-10-13, the owner's manual test on the live client, API 30-35 present): run flags on
  the map (across a reload too), World events and `/toolbox events`, fishable water on the location strip, Choose...
  (the file picker), sound handles across a reload, strips fitted after the window shrinks, Pause / Resume skills,
  the Map & location page and the menu's Location button, effect sounds, the mail doorbell and a run's Beacon.
- **Last death** (confirmed 2026-10-14, the owner in game): the magenta diamond on the map and its clearing (back at
  the spot after going away, or old in another scene).
- **`/lua reload` keeps what's only in memory** (confirmed 2026-10-14, the owner): items looted just before a reload
  were still in the Loot Tracker after it, with the day stored only at the flush and in `ShroudOnDisableScript`, so a
  reload runs the shutdown save.
- **1.8.0 work** (confirmed 2026-10-14, the owner in game): map overlays and the Map overlays window, the auto map
  ("working great") and its ignore list, your last death (look and clearing), and the performance pass measured by
  `/toolbox perf`: crafting at a station, 25-32 hitches a minute before, 2 after (quiet: 0 with Toolbox's timers paused).
- **Background shade sliders** (confirmed 2026-10-16, the owner in game): every HUD strip's own shade works.
- **No character after a logout** (confirmed 2026-10-16, and the reference's `ShroudOnLogOut` gotcha): by
  `ShroudOnLogOut` the character has left and the game has flushed; a character-scope write then lands in
  `toolbox.nochar.character.json` (Toolbox's logout save did: the ended session, the day, the timers, the windows'
  places). So `T.SetSavedVar` / `T.DeleteSaved` skip character-scope writes while `T.NoCharacter()` (after a logout
  until `T.FollowCharacter` reads a character again, or a start with none), quietly; the last save with the character
  in is `ShroudOnSceneUnloaded`'s (session, timers, places, the day); the logout only ends the session in memory.
  Confirmed in game the same day after the fix: a logout writes the character's file and no nochar file.
  A `nochar` file still appeared on 2026-10-18 (05:32, the day and the strips' places at 0, 0, around a switch to
  another character): a known client issue, fixed in a coming client update (owner, same day); nothing to change here.
  Harness: `H.logout(stay)` does the game's order (scene unload, flush, the scope becomes "character:nochar" while
  `H.S.char.present` is false, then the callback).
- **Backups (API 39)** (confirmed 2026-10-16, `tmp/backuptest.lua` and `/toolbox settings backup`): a copy is made from
  ShroudOnStart, a command, a click and a periodic alike; `rateLimited` within the minute (a reload doesn't reset it);
  a restore puts the values back at once. Toolbox's own call works (`toolbox.shawn.character.json.<date>`), and the
  reset's copy and its chat line too (the owner's test, same day). Back up now and Restore (the settings page, the
  settings re-read at once, no reload) confirmed by the owner the same day.
- **The planner while the book is read** (confirmed 2026-10-16, the owner in game): every control greyed out until the
  read finishes, then usable again.
- **The menu's icon color** (confirmed 2026-10-16, the owner in game): the theme tokens tint launcher.png, changed in
  place by `SetTint`.
- **The recipe reads hitch** (confirmed 2026-10-23, the owner in game): the hitching in 1.9.0 was the recipe loading
  (`ShroudGetRecipe`: the book's read, one a `D.BOOK_PERIOD` step, and the planner's re-reads of its recipes), gone
  with 1.9.1's `95837d5` (the read paused in a fight, the HUD not planned in one, `PL.Gap`). One recipe each 0.05 s
  does NOT run without hitching: keep recipe calls out of fights and few; requests 26 and 29 are the real fix.
- **1.9.0 work** (confirmed 2026-10-18, the owner in game): 1.8.0's map overlays converted to one key a scene (the
  counts and storage as before, places drawn, a mark kept across a reload, Forget), the auto map's fights (overlays by
  creature name and Fights, the window row), the Crafting Planner HUD (the shopping list, the build order and its "(N
  made)", Start over, the fanfare and close), the General and Crafting settings pages, and `/toolbox perf` (no hitches
  in 60 s; it showed `buff_durations` saved on every recast, fixed by `BB.LEARN_SLACK`).
- **Louder sounds** (confirmed 2026-10-07): the +7.5 dB .ogg files, the halved saved volume and the per-sound
  volume sliders work in game.
- Confirmed working as built: replace / dismiss the game's buff bar, grouping, the Toolbelt, the mirrored
  target, skill levels and deaths, friends online, the notification chime, Combat Detailed, the game's wedge
  fitted and centred inside the icons, and the 0.7.0 + unreleased work on the dev client (2026-09-30: the
  still wedge on 7-day potions, red at the alert, vitals from ShroudGetPlayerVitals, gear against the repair
  ceiling, Backup & reset).

## Unconfirmed

Things the docs don't settle and the game hasn't shown yet. Check before depending on them more:

- When `ShroudOnStart` runs relative to login (we wait for `ShroudGetLevelProgress()`).
- `ShroudTime` continuing across `/lua reload` and relogs (assumed), restarting on relaunch.
- `Window{ x, y }` versus the host's own position memory (we pass x/y, never call `SetPosition`); whether a
  window's width/height apply once the host remembers a size (assumed not); `GetPosition` returning numbers.
- The level-cap shape of `ShroudGetLevelProgress()` (`percent == 0` with `intoLevel > 0` = capped).
- `onHover` on containers and HUD strips (entering a child, the title bar): the pop-up delays absorb flicker.
- Combat `death` lines: which side is the killer, and `fromYou` on your kills.
- `os.date` in the sandbox (feature-detected; fallback: the date part of `ShroudServerTime`).
- `ShroudOnItemsGained` names as stable keys (localized; same-named items merge); whether they match
  SotANET's names (English) for prices.
- Which values the saved-variable loader refuses: "\/" and a negative number for certain; exponent forms ("1E-05"),
  escaped quotes, newlines and non-ASCII text assumed (escaped anyway). On MoonSharp: `c:byte()` of a character past
  255 (written `%uXXXX`) and `string.char` of it reading back.
- Recovery: that a character's own saved vars are loaded when `B.Recover` runs (ShroudOnStart with a character, and
  `T.FollowCharacter`): read too early, a missing `save_mark` would put the copy back needlessly (same data, a chat line).
- The crafting planner on the live client: `ShroudOnInventoryChanged` firing for the crafting table and trunks
  (`have`); a material's stats applying as the result line adds them (the owner's two-sheet test).
- The auto map's town test (`OV.SceneKind`): `isPot` for a player town (Crossroads' id starts "POT_"), and every NPC
  town's scene id holding "City", "Town" or "Village" (only Ardoris's, `Novia_R4_City_Ardoris`, seen);
  `/toolbox overlay auto` names what a scene counts as.
- `ShroudGetClientInfo().languageCode` on a non-English client (assumed "de", "fr"...; the docs' example is "en").
- The run Beacon (`ShroudSetBeacon`, API 9): the marker at the recorded spot on the compass and map, its "Loot run
  HH:MM" label, and `ShroudGetCurrentSceneNameRaw` matching across visits to a scene (instanced scenes may differ).
- `ShroudHttpGet`: whether every shard allows it; the reviewer may question declaring a host we don't own.
- Notification counts reading 0 until loaded (hence `N.SETTLE`); ransoms / rewards / applications in practice.
- The notification HUD's Scroll inside a HudFrame, nowrap labels ending in "...".
- Weapon poisons: whether a weapon coating shows as a buff at all.
- Effect sounds: the clip name the game gives a player's file (assumed its base name without the extension, as for
  the shipped ones; a second file of a name another sound has is refused, review 25), a path with spaces, and dozens
  of extra clips loaded at once.
- API 30-35 details the owner's test (2026-10-13) didn't single out: the file picker's callback after a page switch;
  `os.time` being UTC seconds as the calendar's are (`N.EventsCheck`'s 15-minute lead).
- Pause skills: `ShroudSetSkillMode`'s list answer keyed by the skill's `key` (a missing one is taken as asked, and
  the resume's check leaves a skill that didn't move alone), skills set to Off decaying meanwhile (the
  setting's tooltip says they may), and the game's per-skill menu matching a list call for mastery skills.
- The skill strip's training markers: the click areas over the icon receiving clicks in game, the tinted
  and turned skillmarks.png, and the reasons ShroudSetSkillMode gives.
- The skill activity strip (skills.lua): how often `ShroudOnSkillsChanged(false)` fires in combat, whether
  `mode` reads as documented and changes with the game's triangle, a decaying skill's `experience` going down,
  `ShroudGetSkills().icon` drawing, `ShroudToggleWindow("skills")`. `/toolbox skills debug` prints the
  readings.
- The target getters' effect indices lining up with `ShroudGetTargetBuffIcon` / `Tooltip`, and
  `TotalDuration` on target effects (else no sweep); `/toolbox target debug` prints them.
- API 24 crafting in game (`/toolbox api` shows `made` and the recipe's yield once the client updates).
- The account file's name: `toolbox.account.json` by the docs' pattern (the character file,
  `toolbox.shawn.character.json` under `ShroudLuaPath` + `SavedVariables`, was confirmed 2026-09-30); and
  whether the character part is ever not the name `ShroudGetPlayerName` gives (case, spaces).
