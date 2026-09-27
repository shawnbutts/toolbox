# Changelog

All notable changes to Toolbox are recorded here. Versions follow `N.N.N`; every
store submission needs a higher version than any submitted before (rejected ones included).

## [Unreleased]

### Added
- Docs window (`/toolbox docs`, or the Docs button that replaces "Chat commands" in settings):
  getting started, a short guide to each feature and its options, tips (moving HUD strips, the
  Lock Status Movement setting, adding combat stats on the fly, sounds), and every command, listed
  from the command registry so it stays current. The first-run welcome points to it.
- `/toolbox version`: version, build (the git commit, stamped into `dist/` by `tools/build.py`,
  with `+` for uncommitted changes), API version, and how many copies of Toolbox are loaded (a
  second copy left in the Lua folder would share and tangle the global `Toolbox` table).
- Documentation for adding combat HUD stats on the fly: `/toolbox combat help` (every combat
  option, with the find / add / remove steps and examples), a clearer `/toolbox combat stats`, a
  visible hint in settings, and a step-by-step section in the store readme.
- Combat stats background: a Dark (theme `inset`) or Light (theme `@text`) panel behind the whole
  strip, or None, with its own opacity (default Dark at 70%) that doesn't fade the text
  (`/toolbox combat bg`, settings). Row names use normal text instead of dim, values bright.
- Combat stats HUD (`/toolbox combat`): fight timer, DPS (last 5 s and fight average, pet
  optional), damage taken and healing per second, crit % and avoided % from your combat chat
  lines, plus character stats you choose (`MagicResistance` by default; `/toolbox combat stat
  add <Name>`). Own Size and position; reset from chat or settings.
- Glue the health & focus bars to the buff bar (`/toolbox vitals glue on` or the settings
  checkbox): one HUD strip with health & focus on the left and buffs on the right, one grip and
  one remembered position, sized to what's showing. Unglued positions are kept for switching back.
- Health & focus bars flash when low: below a threshold (default 20%, `/toolbox vitals flash <n>`
  or the settings slider; can be turned off) the bar and its number swap to the theme's bright
  text colour every 0.4 s. A Test flash button (and `/toolbox vitals flash test`) flashes both
  bars for 5 s to preview it.
- Health & focus bars: show or hide the bars and the numbers separately (not both), and a
  None / Dark / Light background behind the numbers from the UI theme (`inset` / `card`
  classes). Settings has checkboxes and a dropdown; `/toolbox vitals text|bars on|off` and
  `/toolbox vitals bg none|dark|light`.
- Health & focus bars: a Size setting (75-250%, `/toolbox vitals size <n>` and a slider) that
  scales the text, bars, gap and strip together. The numbers now sit just after the bars
  (left-aligned, small gap) in a fixed-width box so both bars line up. The strip has its own size
  and no longer follows the global text size.
- Health & focus bars (`/toolbox vitals`): a movable HUD strip with health (red) and focus (blue)
  bars and "current / max", with width and position settings. Maximums come from the `Health` /
  `Focus` stats found with `/toolbox stats`; vigor isn't exposed to add-ons.
- `/toolbox stats [word]`: lists character stats matching a word (index, internal and displayed
  name, value) and how many matching ones are hidden from add-ons. For finding the stats behind
  own health / focus / vigor bars, which the docs don't name.
- Buff bar position controls: 10 px nudge buttons, Reset and a position readout in settings, and
  `/toolbox buffs move <x> <y>`. (Its drag grip is hidden while the game's HUD is locked.) The
  position is also remembered by the add-on, in case the game's own memory doesn't survive a reload.
- Buff bar (`/toolbox buffs`): buffs and debuffs as their skill icons on a HUD strip, debuffs
  outlined in red, with a clock-style sweep over each icon (`toolbox/clock.png`) instead of a
  countdown. Built from a fixed pool of slots.
- Alerts: a sound when a buff is about to run out (`/toolbox buffalert <1-60>`, default 10 s,
  fires once as the threshold is crossed) and when a new debuff lands (`/toolbox debuffalert`).
  Sounds are found at a custom path, then `Lua/toolbox_<name>.ogg`, then the package; missing
  files are silent. `/toolbox sounds` reports them and sets the volume. All in settings, with
  Test buttons.
- `tools/install.py` copies the alert sounds to `Lua/toolbox_<name>.ogg` (and `.wav` copies, when
  generated, to try as a custom path).
- The sweep now shows a buff's real progress when it was already running as the add-on started or
  reloaded (it used to treat every such buff as brand new). The full duration comes from the
  game's `TotalDuration`/`CurrentDuration` when they agree with the time remaining, otherwise from
  the add-on's own record kept across `/lua reload`. `/toolbox buffs debug` lists the timing data.
- Buff sweeps were wrong for buffs already running when the add-on started (a Light spell half
  used showed 13%): the game's `TotalDuration`/`CurrentDuration` are empty, so the first time
  left seen was taken as the full duration. Durations are now learned from casts seen while the
  add-on runs (saved per character as `buff_durations`); a buff with no known duration shows no
  sweep until it is cast again. Old saved reload timers (which could hold such wrong totals) are
  ignored, and a buff that briefly vanishes during a scene load keeps its timer.
- Buff timers count down on the add-on's own clock and follow the game's time remaining only
  when that value actually changes (a value jumping up is a recast). In game the sweep stalled
  and then jumped, which is what a value refreshed only now and then produces; the expiry alert
  was late for the same reason. `/toolbox buffs trace [name]` logs the game's raw values for 10 s, for the buffs whose rune or
  displayed name contains `name` (up to 8 without one); `debug` and `trace` show both names.
- The sweep has 120 steps (3 degrees each) instead of 24: with 24, a long buff such as a
  20-minute Light spell moved only every 50 s and looked frozen. `clock.png` is now 960 x 576
  (48 px frames, 88 KiB).
- The sweep turns red the moment a buff's expiry alert fires (a second, red set of frames in
  `clock.png`); a recast turns it back. The normal sweep is darker (82% instead of 62%).
- Sound Test buttons and `/toolbox sounds test` report the clip, channel and volume, then check
  whether the game is actually playing it, which tells a file that didn't decode apart from a
  volume problem.
- Alert sounds, generated by `art/alerts.py`: "buff about to run out" (`art/buff_expiring.ogg`,
  two soft falling chimes) and "enemy debuff landed" (`art/debuff_landed.ogg`, two quick hollow
  notes drooping down a minor triad over a low thump). Not in the package yet: the published
  packaging rules don't allow audio files, so they move into `toolbox/` once they do.
- Store icon: a carpenter's tool tote on a leather tile with a bronze frame (`toolbox/icon.png`,
  source in `art/icon.svg`).
- Today Detailed window (`/toolbox dailydetailed`, alias `dd`; pops up when hovering Today): the
  day's gold and kills plus every item gained today with its count. Settings has checkboxes to
  show it and to turn its hover pop-up off.
- Daily stats window (`/toolbox daily`, also in settings): gold picked up, kills by you or your
  pet, and adventurer / producer XP gained today. Resets at local midnight (midnight UTC if the
  local clock is unavailable); kept per character across reloads and relogs.
- Line spacing setting (`/toolbox spacing <0-12>` and a slider in settings). Text lines now have
  a fixed height that follows the text size, so smaller text makes the windows shorter.
- Hovering the compact XP window pops up the Session XP window after a short delay; it stays
  while the pointer is over either window. Can be turned off in settings.
- Compact XP window (`/toolbox compact`, also in settings): session time, current adventurer
  and producer pools, and XP earned on each in the last hour.
- `/toolbox config` opens a Toolbox Settings window: a text-size slider for the Session XP
  window and a checkbox to show or hide it.
- `/toolbox font <9-32>` sets the Session XP window's text size (saved per character).

### Fixed
- In game no alert sound loaded from any path (all timed out). The sound docs say paths are relative
  to "the addon's Lua folder", which for a package may be `Lua/toolbox/`: each alert now also tries
  `.ogg` and `.wav` inside the package folder, `tools/install.py` copies them there for local testing
  (not part of the store package), the per-path wait is 2 s, and `/toolbox sounds debug` lists each
  path tried with what `ShroudLoadSound` answered.
- Alert sounds claimed "ready" while the game's sound list was empty, with a table (the same one
  for both) as their clip. A bare `local found` in the load loop apparently kept an old value in
  the game's Lua (MoonSharp), where standard Lua resets it to nil. Every local now starts with an
  explicit `= nil` (`tools/build.py` refuses bare declarations), and only a real clip name counts.
- The empty list also means the .ogg files never decoded in game. Each alert now tries
  `Lua/toolbox_<name>.wav` right after the .ogg; `tools/install.py` copies the .wav versions.
- Alert sounds never played in game: `ShroudListSound()` entries came back as tables, not the
  documented name strings, so the add-on recorded a table as the clip (the same one for both
  sounds) and could never find it again. Clip names are now read from strings, from a table's
  name field, or from a list wrapped in one more table; `/toolbox sounds debug` shows what the
  game returns, one level deep.
- Sound Test reported "the game's sound list was cleared" in game: the clip recorded at load time
  wasn't found by its exact name at play time. Playing now also matches any clip whose name contains
  the file's base name (as loading does). `/toolbox sounds debug` prints the game's raw sound list
  and what each alert recorded.
- The combat stats strip failed to build in game ("style color takes a number or a string"): a
  label style had `color = ... or nil`, and the game's Lua (MoonSharp) passes a nil table entry on
  to the UI, unlike standard Lua. Labels now always get a theme colour. The same kind of nil was
  removed from buff icon textures, window positions and a Today row's tooltip, and the build now
  refuses `name = ... or nil` table entries.
- A HUD strip that fails to build no longer stops the others from building and showing; the error
  is reported in chat. `/toolbox combat debug` describes the combat strip (shown setting, build
  error, strip visibility, size, position). The combat rows no longer repeat an element id.
- The combat stats strip disappeared once it got a background: its rows were laid over the panel
  with a margin of minus the strip's width, but the game clamps margins to -64..256, so the rows
  were pushed out of the strip. The panel is now per-row slabs one line tall, with each row pulled
  up by its line height (well inside the limit). The test harness now clamps margins and paddings
  like the game.
- The buff bar couldn't be dragged past about two-thirds of the screen: its strip was always 20
  icon slots wide (invisible when empty), and the game keeps HUD frames on screen. The strip is
  now sized to the icons showing (one row without debuffs) and re-fits as buffs come and go.
- The Light number background showed nothing in game (the theme's `card` class draws no panel
  behind a label). Light is now a panel in the theme colour `@text` with dark numbers, on a
  wrapper so switching back to Dark still shows the `inset` panel.
- The drag grip at a HUD strip's top-left corner covered the first number (health & focus bars)
  or icon (buff bar): both strips now keep ~14 px free for it (`Toolbox.Window.GRIP`).
- Health & focus bars showed "--" and stayed empty in game: when the per-frame current value
  isn't a number they now read the `CurrentHealth` / `CurrentFocus` stats. `/toolbox vitals debug`
  shows each source.
- README: the "Development" heading had been dropped when the Buff bar section was added.
- Line spacing had no visible effect: label heights are now pinned with `minHeight`/`maxHeight`
  as well as `height`, so a theme class's minimum height can't override them. `/toolbox spacing`
  with no number now measures the laid-out line height.
- The "Show daily stats window" checkbox in settings now follows `/toolbox daily` and the
  window's close button (it only worked in one direction).

### Changed
- The first run also opens the settings window, after the welcome line (`/toolbox welcome` does both).
- `/toolbox help` opens the Docs window; the chat list of commands moved to `/toolbox commands`.
- `/toolbox` (or `/tbx`) with no argument opens the settings window instead of printing help;
  a one-time welcome line on first run says so, and the settings window opens with a short intro
  and a "Chat commands" button.
- Alert sounds: the defaults live in the add-on's folder (`Lua/toolbox/<name>.ogg`/`.wav`); a
  replacement in the Lua folder beside it (`Lua/toolbox_<name>`) wins. The package-relative guesses
  are gone (paths are Lua-root relative), and `tools/install.py` no longer writes to the Lua folder.
- HUD strips are owned by `hud.lua` (`Toolbox.Hud`): the buff bar and the health & focus bars build
  only their content, and the HUD puts it in one strip each or a shared glued strip, sizes it and
  remembers its position.
- HUD position controls (settings rows and the `move` command) are shared by the buff bar and the
  health & focus bars (`Toolbox.Window.HudMover`, `Toolbox.Config.PositionRows`, `Toolbox.MoveCommand`).
- The hover pop-up logic is shared (`hover.lua`) between XP / XP Detailed and Today / Today Detailed.
- Window names and commands: the compact window is now **XP** (`/toolbox xp`), and the old
  Session XP window is **XP Detailed** (`/toolbox xpdetailed`, alias `xpd`). `/toolbox compact`
  is gone. Window positions and settings carry over.
- The build allows `os.date` / `os.time` (for the daily reset); other `os` and all `io` use is
  still refused.
- Lower minimum window heights (Session XP 60, compact 50) now that lines can be tighter.
- "Next level" and "Last hour" lines use the normal text colour instead of the dimmed one.
- Sample history now covers the last hour (was 10 minutes); the session is stored in saved
  vars once per tick instead of on every XP event.
- More compact Session XP window: level and % share the track heading, gains and rates share
  one line, and elapsed time sits beside Reset. Smaller default text (12), a smaller default
  size, and a lower minimum size (160x100). Content scrolls when the window is made smaller.
- The "Next level" line always shows the XP still needed, and says why there is no time
  estimate ("no XP gained yet", "max level") instead of a bare `--`.
- 10px left/right gutter in the Session XP window so the progress bars no longer touch the edge.

## [0.1.0] - 2026-09-27

### Added
- `/toolbox` and `/tbx` slash commands with `help`, `xp` and `reset`.
- Session XP tracking for adventurer and producer XP from the total XP values:
  elapsed time, XP gained, XP/hour for the session and the last 10 minutes,
  level, % through the level and estimated time to the next level.
- "Session XP" window (Shroud.UI) with a Reset button; remembers whether it is
  open and where it is.
- Sessions survive `/lua reload`; a new login starts a new session.
