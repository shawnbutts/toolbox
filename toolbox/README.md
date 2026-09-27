# Toolbox

A small toolbox of quality-of-life features: XP tracking and daily stats.

## Commands

`/toolbox` and `/tbx` do the same thing.

- `/toolbox help`: list commands
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
  `/toolbox vitals move 40 300` places them)
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
debuff lands. For the sounds, put `toolbox_buff_expiring.ogg` and `toolbox_debuff_landed.ogg` in
your Lua folder, or choose your own files in `/toolbox config`.
