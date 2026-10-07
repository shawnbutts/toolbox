# Toolbox

[![check](https://github.com/shawnbutts/toolbox/actions/workflows/check.yml/badge.svg)](https://github.com/shawnbutts/toolbox/actions/workflows/check.yml)

A Shroud of the Avatar Lua add-on. It needs Lua API 25 (`min_api_version` in the manifest). Features:

- **Toolbelt**: your buffs and debuffs, health, focus and Vigor, consumables, gear repair and target in
  one movable strip, optionally only during combat (the buff bar with the other bars joined to it).
- **XP**: a small window (or a compact window, API 19, or a HUD strip) with session time, your adventurer and producer pools, and XP
  earned in the last hour. Hover it for **XP Detailed**: levels, progress bars, XP/hour, time to the
  next level, and the last hour as a chart.
- **Today**: gold picked up, kills, and XP gained since midnight. Hover it for the **Loot Tracker** (its
  **Reset** button counts one run from now, keeping the day underneath):
  every item gained today, with counts and optional estimated values from shroudoftheavatar.net.
- **Buff bar**: your buffs and debuffs as their skill icons with a clock-style sweep, long-lasting
  buffs grouped into one slot, sound alerts and a red flash before a buff runs out, a sound when a
  debuff lands, an only-in-combat option, and (API 16) replacing the game's own buff bar and
  click-to-dismiss.
- **Buff block**: every buff and debuff on a strip of its own, soonest to run out first, in rows as many
  icons wide as you choose, nothing grouped (`/toolbox buffs block`).
- **Consumables bar**: food, potions, weapon poisons and combat items in effect, by the game's buff
  categories, long-lasting ones grouped (on its own strip or in the Toolbelt).
- **Target HUD**: your target's health and focus (bars, numbers or both, with the health bars' options), and
  its effects with the time left on each; its own strip or the Toolbelt's last row (`/toolbox target`).
- **Health, focus & Vigor bars**: your own health, focus and (API 20) Vigor on a movable HUD strip.
- **Combat stats**: DPS, damage taken and healing per second, crit and avoid rates, a fight timer and
  chosen character stats; hover it for **Combat Detailed** (damage by skill, the last minute as a
  chart, healing, targets, damage types, recent fights).
- **Block, parry & dodge**: the word pops up over the Toolbelt when you avoid an attack, each with its own
  colour and sound (`/toolbox combat shout`).
- **Equipment bar and repair alerts**: worn items that need repair, with a durability sweep.
- **Notifications**: guild message of the day, new mail, expiring mail, ransoms, rewards, guild
  applications and gear needing repair, in a window or on a scrolling notification HUD.
- **Skill activity**: your skills' icons pop up on a strip of their own as they level, with the level,
  progress and training mode (`/toolbox skills`), and one-click train / maintain / unlearn markers on each icon
  (Lua API 27); skill level changes (up or down) can go to the notification HUD too.

## Install

The official way to install Toolbox is the game's add-on store (the in-game Community Addons window): find
Toolbox, install it and switch it on; updates come from the store too.

Each [GitHub release](https://github.com/shawnbutts/toolbox/releases) carries two files:

- `toolbox-<version>-beta.zip`: for installing by hand, for beta testers trying a version before it reaches
  the store. It holds a `toolbox` folder to copy into your game's Lua folder, `INSTALL.txt` (the steps) and
  `TESTING.txt` (what to try, known issues).
- `toolbox-<version>.zip`: the store package, with the files at the top level as the store takes them. It
  isn't for installing by hand (unzipped into the Lua folder, its files would sit loose).

## About

- Store slug and package folder: `toolbox`
- Author: shawn butts (shawn)
- License: MIT

Built clean-room from the official docs only:
[agent reference](https://catnipgames.net/lua/agent.html),
[API reference](https://catnipgames.net/lua/reference.html),
[authoring guide](https://catnipgames.net/lua/guide.html).

## Commands

The settings window has a search box: type a word (sound, size, target...) and pick a result to open its page
with that setting's section at the top and the setting blinking.

`/tbx` is the short form of `/toolbox`: every command below works with either (`/tbx help`, `/tbx target`...).

| Command | What it does |
| --- | --- |
| `/toolbox` (no argument) | open or close the settings window, the hub for everything |
| `/toolbox help` / `/toolbox docs` | open the Docs window: a guide to every feature and option, and every command |
| `/toolbox commands` | list every command in chat |
| `/toolbox key` | show the shortcut that opens the settings (Ctrl+; by default) and its state |
| `/toolbox xp` | show or hide the XP window |
| `/toolbox xpdetailed` (or `xpd`) | show or hide the XP Detailed window |
| `/toolbox reset` | start a new XP session |
| `/toolbox daily` | show or hide today's stats (gold, kills, XP) |
| `/toolbox loot` (or `dd`, `dailydetailed`) (`values on\|off\|test\|refresh`) | show or hide the Loot Tracker (every item gained today); estimated values |
| `/toolbox recipe <name>` | a recipe you know as the game reports it, and what it takes from raw materials through your other known recipes |
| `/toolbox buffs move [x y]` | place the buff bar (no numbers: say where it is) |
| `/toolbox buffs` (`group` / `quiet` / `combat` / `flash` / `replace` / `dismiss` / `debug` / `raw` / `trace [name]`) | show or hide the buff bar; its options; diagnostics (`debug`: each buff's timing; `trace light`: log buffs matching "light" once a second for 10 s) |
| `/toolbox consumables` (`bar` / `glue` / `add\|remove <name>` / `move`) | list food and potions in effect; the consumables bar's options |
| `/toolbox gear` (`bar` / `glue` / `repair <%>` / `move` / `debug`) | worn items' durability; the equipment bar's options |
| `/toolbox notify` (`<name> on\|off` / `via window\|hud\|chat` / `sound on\|off` / `show` / `hud ...`) and `/toolbox motd` | notifications; the guild message of the day |
| `/toolbox buffalert <1-60>` / `on` / `off` | alert this many seconds before a buff runs out (default 10) |
| `/toolbox debuffalert on` / `off` | alert when a debuff lands |
| `/toolbox sounds [0-100]` | show which sound files the alerts use; with a number, set the volume |
| `/toolbox vitals` (`size <75-250>` / `text on\|off` / `bars on\|off` / `bg none\|dark\|light` / `flash <1-95>\|on\|off\|test` / `replace on\|off` / `glue on\|off` / `move [x y]` / `debug`) | show or hide the health & focus bars (or place them) |
| `/toolbox combat` (`reset` / `size <n>` / `bg dark\|light\|none [%]` / `pet on\|off` / `stat add\|remove <Name>` / `stats` / `detail` / `events [n]` / `move [x y]`) | show or hide the combat stats HUD, Combat Detailed, and its options |
| `/toolbox api` | which newer API functions this game client has |
| `/toolbox welcome` (`reset`) | show the first-run welcome again: the line and the settings window (`reset`: at the next reload, as on a first run) |
| `/toolbox version` | the installed version and build (git commit), and whether more than one copy is loaded |
| `/toolbox stats [word]` | list character stats whose name contains the word (for finding stat names) |
| `/toolbox config` | open or close the settings window |
| `/toolbox settings` (`save` / `reset` / `cancel` / `setups` / `import` / `export` / `delete`) | where the settings files are (`Lua/SavedVariables/toolbox.<character>.character.json` and `toolbox.account.json`) and how to back them up (copy them; to restore, quit the game and copy them back); `save` writes them now; `reset` puts every setting and position back to its default at the next `/lua reload`; `setups` lists the setups you can import (named ones, and the characters on this computer that list theirs: `share on`, off at first), `import <name>` copies one into this character now, `export <name>` saves yours under a name, `delete <name>` removes one |
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
Skill levels               3
Deaths                     1
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

### Loot Tracker

Rest the pointer on **Today** and the **Loot Tracker** pops up (same rules as XP Detailed: it stays
while the pointer is over either window, and `/toolbox loot` or `dd` pins it). It shows
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
- Hover can be turned off with "Show Loot Tracker on hover" in `/toolbox config`.
- **Reset** (top right, or `/toolbox loot reset`) counts from now, for one run: gold, kills, items, crafts and
  gathering since that moment, with "Since 14:32" at the top. Nothing is lost: the Today window keeps the
  whole day, and **Show all of today** (or `/toolbox loot today`) brings the day back here too. A run ends at
  midnight with the day.
- **Runs** (the Show dropdown, or `/toolbox loot view runs`): each run is kept when it ends (Reset again, Show
  all of today, midnight; at least a minute of play), the last 10 per character, newest first: start time, the
  scene you played most in, length, gold per hour and, with estimated values on, loot value per hour (from the
  prices when the run ended). Hover one for kills, items and nodes gathered.

## Buff bar

`/toolbox buffs` shows a HUD strip with
your buffs on the top row and debuffs, outlined in red, below. Each icon is the skill's real icon
with the game's own tooltip. Time left is shown as the game's own cooldown wedge (the one on its buff
and hotbar icons), sweeping clockwise from 12 o'clock and run by the game (API 25), not as text;
permanent effects have no sweep.

**Moving it.** Drag the small grip at its top-left corner. The game hides the grip while the HUD
is locked: untick **Lock Status Movement** under **Nameplates & Chat Bubbles** on the game's
**Interface** options page to see it. Or use the Position buttons in `/toolbox config`
(10 px nudges and Reset), or type `/toolbox buffs move 600 40`. The bar remembers where it is.

The strip is sized to the icons showing and grows to the right as buffs arrive; the game keeps
it on screen, so a bar parked at the far right is pushed left as it grows.

**Replacing the game's bar** (API 16, opt-in): "Replace the game's buff bar" hides the game's own
bar while this one is showing (the game restores it on reload, so it is applied at every start), and
"Click a buff to dismiss it" dismisses the buffs the game lets you dismiss. Icons are a fixed pool
(20 buffs, 10 debuffs) built once. Toolbox sets each wedge once per cast; the game draws it smoothly.

**Alerts** (they work with the bar hidden):

- **Buff about to run out**: plays once when a buff's remaining time crosses your setting (1 to
  60 s, default 10). A buff that starts with less time than that never alerts, and a recast buff
  re-arms. Debuffs don't trigger it.
- **Debuff landed**: plays when a debuff you didn't have appears, at most once a second. The API
  doesn't say who applied an effect, so this is any new debuff. It stays quiet for 3 s after you
  log in or change scene, when the game rebuilds the buff list.
- **Muted effects**: no sound for the effects you pick, for the combat staples that come so often their
  sound is noise (their icons still flash). Settings, Buffs: pick one from the dropdown (recent alerts first,
  then what's on you, then every effect you've been seen to cast) and press Mute; the second dropdown and
  Unmute bring one back. In chat, `/toolbox buffs quiet` lists the muted ones and recent alerts, and
  `/toolbox buffs quiet add <name>` / `remove <name>` change the list.

**Sounds.** The default sounds live in the add-on's folder (`Lua/toolbox/buff_expiring.ogg`,
`Lua/toolbox/debuff_landed.ogg`, `notify.ogg`, `ping.ogg`, `tap.ogg` for notifications, and `skill_up.ogg`,
`skill_down.ogg` for the skill activity strip); to use your own, put a replacement in the folder above it. Each
alert takes the first that loads of:

1. a custom path you set in `/toolbox config` (any `.ogg`/`.wav`/`.mp3` inside your Lua folder);
2. a replacement beside the add-on: `Lua/toolbox_buff_expiring.ogg` / `Lua/toolbox_debuff_landed.ogg` /
   `Lua/toolbox_notify.ogg` (or `.wav`), which store updates don't touch;
3. the default in the add-on's folder, `Lua/toolbox/<name>.ogg`.

The defaults ship in the package (API 15 allows sounds; the package needs `min_api_version` 25
anyway); paths are relative to the Lua folder (`ShroudLuaPath`).

Missing files are fine: that alert is just silent. `/toolbox sounds` says which file each alert
uses; `/toolbox sounds test` (or the Test buttons in settings) plays them and reports whether the
game is really playing them; `/toolbox sounds debug` lists every path tried. `art/alerts.py`
generates `toolbox/*.ogg`. (Older macOS clients failed every sound load; fixed in the client
2026-09-28.)

When a buff's expiry alert fires, its sweep turns from dark to red for the rest of that run.

The sweep needs each buff's full duration: the game reports it (`TotalDuration` in
`ShroudGetPlayerBuff()`). For effects without one (the
moon timer) the bar learns it: a buff that appears while the add-on is running shows its full
duration as its first time left, remembered per character. Without either there is **no sweep**
rather than a wrong one; the expiry alert only needs the time left. `/toolbox buffs debug` says
where each buff's duration came from.

**Consumables bar.** Food (`RuneFood_...`) and Obsidian potions (`BlessingOf...`) move to their own
bar, with the same sweep, flash and alert (`/toolbox consumables`; add
more names in settings or with `/toolbox consumables add <name>`), or put it in the Toolbelt. Shrine blessings
stay on the buff bar.

**Equipment bar.** Worn items below the repair threshold (20% by default) show with a red sweep for
the durability they've lost, lowest first. Durability counts against what a repair restores
(`primaryDurability`); when that has worn below 95% of new, the tooltip says a crafting station repair
is needed; a "Gear needs repair" notification comes when one drops
below it and again when it breaks (`/toolbox gear`). It can go in the Toolbelt too.

## Health & focus bars

`/toolbox vitals` shows a red health bar and a blue focus bar with "current / max" on a HUD
strip, moved like the buff bar (grip, Position buttons in `/toolbox config`, or
`/toolbox vitals move x y`). Its **Size** (75-250%, `/toolbox vitals size 150` or the slider in
settings) scales the text, bars, gap and strip together; **Bar length** sets the bars' length at
100%. The numbers sit just after the bars. The strip has its own size, so the global text size
doesn't change it. The bars or the numbers can be hidden (not both; the numbers take the bars'
red and blue when the bars are off), and the numbers can sit on a **Dark** or **Light** panel from
your UI theme, so they follow your skin: Dark is the theme's `inset` look, Light a panel in the
theme's text colour with dark numbers on it.

**In the Toolbelt**: "In Toolbelt" for the health bars on the settings' Toolbelt page (or
`/toolbox toolbelt vitals on`) puts the health, focus and Vigor bars and the buffs in a single HUD strip
(health bars on the left, buffs on the right) with one grip and one position; either part's Position
buttons or `move` command move it. The Toolbelt's position and the bars' own strip are remembered
separately.

**Flash when low**: while health or focus is below a threshold (default 20%, 1-95%), its bar and
number swap to the theme's bright text colour every 0.4 s. On by default; a checkbox and slider
in settings, or `/toolbox vitals flash 30` / `off`. **Test flash** (in settings) or
`/toolbox vitals flash test` flashes both bars for 5 s so you can see it. Current values and maximums
come from `ShroudGetPlayerVitals()` (API 25), read once per update; the maximum is never shown below the
current value (it is fractional: 950.36 with 951 current). `/toolbox vitals debug` shows what it gave.

**Vigor** (API 20): a gold third bar with the percentage, from `ShroudGetVigor()` /
`ShroudOnVigorChanged`; hover it for the regen and crit bonuses. It shows once you are past the level
where Vigor applies; "Show Vigor" in settings or `/toolbox vitals vigor off` hides it.

**Replacing the game's bars** (API 28, opt-in): "Replace the game's health bars" (or
`/toolbox vitals replace on`) hides the health, focus and Vigor bars on the game's own player frame while
these show, with `ShroudSetPlayerVitalBarsVisible`; the frame's name and buffs stay. The game gives the bars
back when Toolbox reloads or stops, so Toolbox hides them again each update while the option is on.

## Combat stats

`/toolbox combat` shows a HUD strip with:

| Row | What |
| --- | --- |
| Fight | how long the current fight has run, or the last one ("ended") |
| DPS | your damage per second over the last 5 s, and averaged over the fight (pet included; `/toolbox combat pet off` to leave it out) |
| Taken /s | damage taken per second, the same two ways |
| Healing /s | healing you did per second |
| Crit | your critical hits as a share of your damaging hits this fight |
| Avoided | attacks on you that were dodged, parried or blocked |
| stats | character stats you choose: `MagicResistance` by default |

The numbers come from your combat chat lines (`ShroudOnCombatEvents`), so they cover what your
combat chat shows. A fight starts when you enter combat or the first damage line arrives, and
ends when combat ends (or after 12 quiet seconds); its numbers stay until the next fight.
`/toolbox combat reset` (or the settings button) clears them.

**Choosing the stats, on the fly.** The docs name few stats, so the list is the player's, and it can
be changed at any time, mid-fight included, without a reload (up to 8, saved per character):

1. Find a name: `/toolbox stats resist` (any word: `absorb`, `dodge`, `block`, `crit`, `regen`,
   `speed` ...). Each line is `index Name (Display name) = value`; the name is the word after the index.
2. Add it: `/toolbox combat stat add CombatHealthRegen`.
3. Remove it: `/toolbox combat stat remove CombatHealthRegen`; list: `/toolbox combat stats`.

Unreadable stats show "n/a". The settings window's Combat page does the same with a stat picker: a
search field, a results dropdown (label, internal name and your value now; suggestions when the search
is empty), Add, and a Remove dropdown of the shown stats. `/toolbox combat help` prints the chat way. The store readme
(`toolbox/README.md`) has the player-facing version. The strip has its own Size and
position, and stays separate from the Toolbelt.

**Background.** A panel behind the whole strip: Dark (the UI theme's `inset` look, the default) or
Light (the theme's text colour, with dark text), or None, with its own opacity (10-100%, default
70%) that doesn't fade the text. `/toolbox combat bg dark 70`, or the dropdown and slider in
settings. The docs don't name a theme background colour, so these are the closest themed looks.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for setting up on macOS, Windows or Linux (or in a container).
Requirements: Lua 5.2+ and/or LuaJIT, [luacheck](https://github.com/lunarmodules/luacheck), Python 3.9+.

```sh
python3 tools/check.py     # lint + tests (every Lua found) + build; Windows: py tools/check.py
python3 tools/check.py --container   # the same in the dev container (Docker or Podman)
luacheck .                 # lint (std lua52 + the documented API globals)
lua tests/run.lua          # headless tests (luajit tests/run.lua works too)
python3 tools/build.py     # validate + write dist/toolbox/ and dist/toolbox-<version>.zip
```

`tools/build.py --check` validates without writing anything. The build enforces the store rules
from the docs: manifest fields, slug and version format, files list, flat whitelisted zip entries,
image limits, size caps, no runtime code loading, and no `io`/`os` use in package files except
`os.date`/`os.time`.

### Layout

```
toolbox/            the package (what ships)
  manifest.json     files load in this order: core.lua, xp.lua, hover.lua, ui.lua, compact.lua, daily.lua,
                    dailydetail.lua, sounds.lua, hud.lua, buffbar.lua, vitals.lua, combat.lua, changelog.lua,
                    docs.lua, skills.lua, config.lua
  core.lua          Toolbox namespace, commands, saved-var helpers, session lifecycle, callbacks
  xp.lua            pure session XP model (rates, rolling window, time to level)
  ui.lua            the XP Detailed window (/toolbox xpdetailed; Toolbox.Window, id toolbox_xp)
  compact.lua       the XP window (/toolbox xp; Toolbox.Compact, id toolbox_compact)
  hover.lua         shared hover pop-up controller (XP -> XP Detailed, Today -> Loot Tracker)
  daily.lua         daily stats and the Today window (/toolbox daily)
  dailydetail.lua   the Loot Tracker window (/toolbox loot, dd)
  sounds.lua        alert sound loading (custom path, then defaults) and playback
  hud.lua           the HUD strips: one per module, or one shared strip for the Toolbelt
  buffbar.lua       the buff bar HUD, its sweeps, expiry and debuff alerts
  vitals.lua        the health & focus bars HUD
  combat.lua        the combat stats HUD
  docs.lua          the Docs window (/toolbox docs, Docs button in settings)
  skills.lua        the skill activity strip (/toolbox skills); self-contained, easy to remove
  clock.png         the equipment bar's wear picture (2 x 120 frames, from art/clock.py)
  config.lua        the Toolbox Settings window (/toolbox config)
  README.md         player-facing store readme
  icon.png          store / add-on manager icon (256x256)
art/icon.svg        editable source of the icon (not shipped)
art/clock.py        generates toolbox/clock.png (and art/clock.svg)
art/alerts.py       generates the alert sounds toolbox/*.ogg (shipped in the package)
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
   The default alert sounds come with the package. (Earlier installs put them in
   `Lua/toolbox_*.ogg`; those count as your replacements, so delete them unless wanted: the
   installer lists any it finds.) The folder name must be
   exactly `toolbox`, and there must be no loose `toolbox.lua` in the Lua
   folder (it would block the package). Re-installing replaces `Lua/toolbox/` only; saved vars in
   `Lua/SavedVariables/` are kept.
4. In game: `/lua reload`.
5. Enable **Toolbox** in the add-on manager (new add-ons load disabled).
6. `/lua check toolbox` should report nothing blocking.
7. The first run prints "Toolbox is ready: type /toolbox ..." and opens the settings window, where
   each feature has a checkbox (`/toolbox welcome reset` + `/lua reload` replays it). `/toolbox xp` opens the XP window; hover it for XP Detailed. Try `/tbx help`, `/tbx reset`, `/lua reload` (the session should
   carry on), and closing/moving the window then reloading.

## Beta testing (hand installs)

1. Commit everything (the build is stamped with the commit; testers' `/toolbox version` shows it).
2. `make beta` runs lint, tests and the build, then writes `dist/toolbox-<version>-beta.zip`:
   a ready-to-copy `toolbox/` folder (the add-on, default alert sounds included), `INSTALL.txt`
   (`INSTALL.md`: the store is the official way; installing by hand) and `TESTING.txt` (`BETA.md`: what to
   try, known issues, how to report).
3. Send testers the zip. Keep `BETA.md`'s known issues and "what to try" current for each beta. Pushing a
   version tag publishes both zips as a GitHub release (`.github/workflows/release.yml`).

## Releasing

1. Bump `version` in `toolbox/manifest.json` and `Toolbox.version` in `toolbox/core.lua`.
2. Add a `CHANGELOG.md` entry for it.
3. `make check`, then test in game.
4. Submit from the in-game Community Addons window (select the installed package,
   **Submit to Community**). Version numbers are single-use, even for rejected submissions.
