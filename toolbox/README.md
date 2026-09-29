# Toolbox

A small toolbox of quality-of-life features. The headline is the **Toolbelt**: your buffs and
debuffs, health, focus and Vigor, food and potions, and gear that needs repair, in one movable strip
that can show only in combat. Plus XP tracking, daily loot, crafting and gathering stats, combat
stats and notifications.

**Getting started:** type `/toolbox` (or `/tbx`) to open the settings window and tick what you
want on screen. Its **Docs** button (or `/toolbox docs`) opens a guide to every feature, option and
command (`/toolbox help` opens it too); `/toolbox commands` lists the commands in chat.
**Ctrl+Shift+;** opens the settings too; change or set the key in the add-on manager, on Toolbox's row
under **Keys**.

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
- `/toolbox dd values on` / `off`: estimated values in Today Detailed, from SOTA.net (see below)
- `/toolbox buffs`: show or hide the buff bar
- `/toolbox buffalert <1-60>` (or `on` / `off`): sound this many seconds before a buff runs out
- `/toolbox debuffalert on` / `off`: sound when a debuff lands
- `/toolbox sounds`: show which sound files the alerts use (`/toolbox sounds 50` sets the volume)
- `/toolbox toolbelt`: what's in your Toolbelt (`vitals|consumables|gear on|off` adds or removes a bar,
  `combat on` shows it only in combat, `move 600 40` places it)
- `/toolbox vitals`: show or hide health, focus & Vigor bars (`/toolbox vitals size 150` scales them,
  `/toolbox vitals move 40 300` places them)
- `/toolbox combat`: show or hide the combat stats HUD (DPS, damage taken, healing, crit and avoid rates, fight timer, chosen stats)
- `/toolbox consumables`: food, potions and combat items in effect, on their own bar (`cat <Kind> on|off`
  picks the kinds; `max 6` caps the icons; `add <name>` tracks more)
- `/toolbox gear`: list your worn items' durability, lowest first (`/toolbox gear repair 30` sets when
  to warn, `/toolbox gear bar off` hides the equipment bar)
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

Today Detailed's **Show** dropdown switches between **Looted** (what you picked up; crafted and
gathered items are left out unless you include them in settings), **Crafted** (`/toolbox crafted`:
items you took off crafting stations, crafts per recipe with exceptional and failed, crafting XP) and
**Gathered** (`/toolbox gathered`: what you harvested, nodes, failed harvests, gathering XP).

### Estimated values (optional, uses the internet)

Turn on **Estimated values (SOTA.net)** in settings (or `/toolbox dd values on`) and Today Detailed
adds each item's estimated value: its count times its average sale price over the last 90 days,
from the public price list at shroudoftheavatar.net (built from receipts players upload), plus a
total for the day. Hover a value for the price per unit and how many sold. Items that haven't
sold in 90 days stay blank.

It is off by default and needs two switches: this setting, and **Internet** for Toolbox in the
add-on manager (off until you turn it on). When on, Toolbox sends only the names of the items in
Today Detailed to shroudoftheavatar.net, at most one request every few seconds, and remembers each
price for 24 hours (across reloads and restarts), so an item is looked up at most once a day.
`/toolbox dd values refresh` forgets them and looks them up again. Like any website, that site can
see your IP address. Toolbox contacts no other site.

## Toolbelt

The **Toolbelt** is your buff bar with your health, focus and Vigor bars beside it and your
consumables bar and equipment bar under it: one strip, moved as one, with everything you watch in a
fight. Pick what joins it in the settings window (**Toolbelt**) or with `/toolbox toolbelt`, and tick
**Only during combat** to have it appear only when you're fighting.

## Buff bar

`/toolbox buffs` shows your buffs and debuffs as their skill icons, with a clock-style sweep for
the time left. It can sound an alert a set number of seconds before a buff runs out, and when a
debuff lands. The default sounds are in the add-on's folder; to use your own, put
`toolbox_buff_expiring.ogg` / `toolbox_debuff_landed.ogg` (or `.wav`) in your Lua folder, beside
the `toolbox` folder, or choose any file in `/toolbox config`.

## Gear repair

An equipment bar shows worn items below the repair threshold (20% by default), with a red sweep
for the durability they have lost, and a **Gear needs repair** notification tells you when an item
drops below it, and again when it breaks. Both are in the settings window.

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
