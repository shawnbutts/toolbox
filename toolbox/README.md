# Toolbox

A small toolbox of quality-of-life features: XP tracking, daily stats, a buff bar, health &
focus bars and combat stats.

**Getting started:** type `/toolbox` (or `/tbx`) to open the settings window and tick what you
want on screen. Its **Docs** button (or `/toolbox docs`) opens a guide to every feature, option and
command (`/toolbox help` opens it too); `/toolbox commands` lists the commands in chat.

## Commands

`/toolbox` and `/tbx` do the same thing.

- `/toolbox`: open the settings window (tick what you want on screen)
- `/toolbox help` (or `/toolbox docs`): open the Docs window, a guide to everything
- `/toolbox commands`: list every command in chat
- `/toolbox xp`: show or hide the XP window (session time, pools, XP in the last hour)
- `/toolbox xpdetailed` (or `xpd`): show or hide the XP Detailed window (levels, progress, XP per hour, Reset)
- `/toolbox reset`: start a new XP session
- `/toolbox daily`: show or hide today's stats: gold picked up, kills, adventurer and producer XP (resets at midnight)
- `/toolbox dailydetailed` (or `dd`): show or hide Today Detailed: every item gained today, with counts
- `/toolbox buffs`: show or hide the buff bar
- `/toolbox buffalert <1-60>` (or `on` / `off`): sound this many seconds before a buff runs out
- `/toolbox debuffalert on` / `off`: sound when a debuff lands
- `/toolbox sounds`: show which sound files the alerts use (`/toolbox sounds 50` sets the volume)
- `/toolbox vitals`: show or hide health & focus bars (`/toolbox vitals size 150` scales them,
  `/toolbox vitals move 40 300` places them, `/toolbox vitals glue on` joins them to the buff bar)
- `/toolbox combat`: show or hide the combat stats HUD (DPS, damage taken, healing, crit and avoid rates, fight timer, chosen stats)
- `/toolbox config`: open the settings window (text size, line spacing, which windows to show)
- `/toolbox spacing <0-12>`: set the space between lines (default 2)
- `/toolbox font <9-32>`: set the window text size (default 12)

## XP

The **XP** window shows the session time, your adventurer and producer pools, and the XP you
earned on each in the last hour. Rest the pointer on it and **XP Detailed** pops up with, for
adventurer and producer XP:

- XP gained this session
- XP per hour over the whole session and over the last 10 minutes
- your level, how far through it you are, the XP still needed and an estimate of the time to the
  next level at your session rate

A session starts when you log in (or turn the add-on on) and when you press **Reset**.
It survives `/lua reload`. Windows can be resized by dragging their corner. Settings, text size
and which windows are open are saved per character.

## Today

`/toolbox daily` shows gold picked up, kills by you or your pet, and adventurer and producer XP
gained today. It resets at local midnight. Rest the pointer on it and **Today Detailed** pops up
with every item that arrived in your bags today and how many.

## Buff bar

`/toolbox buffs` shows your buffs and debuffs as their skill icons, with a clock-style sweep for
the time left. It can sound an alert a set number of seconds before a buff runs out, and when a
debuff lands. The default sounds are in the add-on's folder; to use your own, put
`toolbox_buff_expiring.ogg` / `toolbox_debuff_landed.ogg` (or `.wav`) in your Lua folder, beside
the `toolbox` folder, or choose any file in `/toolbox config`.

## Combat stats

`/toolbox combat` shows a small HUD with your fight timer, DPS (last few seconds and fight
average), damage taken and healing per second, crit % and the share of attacks you avoided, plus
any **character stats you choose**. `/toolbox combat help` lists every option.

### Choosing your stats (you can do this mid-fight)

The HUD can show up to 8 of your character's stats, such as magic resistance, and you can change
them at any time without reloading:

1. **Find the stat's name.** Type `/toolbox stats` and a word, for example:
   - `/toolbox stats resist`
   - `/toolbox stats absorb`
   - `/toolbox stats dodge` (or `block`, `parry`, `crit`, `regen`, `speed`)

   Each line shows a stat's name and its current value, e.g. `11 CombatHealthRegen (Combat Health
   Regen) = 0.1`. The name is the word right after the number: `CombatHealthRegen`.
2. **Add it:** `/toolbox combat stat add CombatHealthRegen`. It appears on the HUD straight away.
3. **Remove it:** `/toolbox combat stat remove CombatHealthRegen`.
4. **See what's shown:** `/toolbox combat stats`.

Good ones to start with: `MagicResistance` (shown by default), `CombatHealthRegen`,
`CombatFocusRegen`, and whatever `/toolbox stats resist`, `absorb`, `dodge` and `crit` turn up
for you. Your choices are saved per character. A stat the game doesn't let add-ons read shows
"n/a"; remove it and pick another.
