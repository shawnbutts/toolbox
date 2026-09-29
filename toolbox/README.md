# Toolbox

**Everything you watch in a fight, in one strip you can put anywhere.** Toolbox's **Toolbelt** joins
your buffs and debuffs (with clock sweeps and a warning before they run out), your health, focus and
Vigor, your food and potions, and any gear that needs repair into one movable HUD strip that can
appear only in combat. Around it: XP per hour and time to your next level, everything you looted,
crafted and gathered today with its market value, DPS and combat stats, and notifications.

**Highlights**

- **The Toolbelt:** buffs, debuffs, health, focus, Vigor, food, potions and worn-out gear in one strip, moved as one.
- **Never let a buff drop:** a sound and a red flash before a buff runs out, and a sound when a debuff lands.
- **A tidier buff bar:** long buffs and blessings fold into one icon with a count; it can replace the game's own bar.
- **Food and potions on their own bar,** combat items too, with the same sweeps and warnings.
- **Gear repair warnings** before an item breaks, and again when it does.
- **XP tracking:** XP per hour, time to next level and a last-hour chart, for adventurer and producer XP.
- **Today:** gold, kills, XP, and every item looted, crafted or gathered, with optional values from shroudoftheavatar.net.
- **Combat stats:** DPS, damage taken, healing, crits, each skill's share, per-target damage and a fight timeline.
- **Notifications:** guild message, mail, rewards and gear needing repair, in a window or on the HUD.
- **All set up in one settings window,** with a guide to every feature in the game. No files to edit.

**Getting started:** type `/toolbox` (or `/tbx`, or press **Ctrl+;**) to open the settings window and
tick what you want on screen. Its **Docs** button opens a guide to every feature, option and command.
Change the key in the add-on manager, on Toolbox's row under **Keys**.

## The Toolbelt

Your buff bar with your health, focus and Vigor bars beside it and your consumables and equipment bars
under it: one strip, moved as one, with everything you watch in a fight. Pick what joins it in the
settings window (**Toolbelt**) or with `/toolbox toolbelt`, and tick **Only during combat** to have it
appear only when you're fighting. Each bar also works on its own strip.

## Buff bar

Your buffs and debuffs as their skill icons, with a clock-style sweep for the time left and, if you
like, the seconds counting down at the end. It can sound an alert a set number of seconds before a buff
runs out (the icon flashes red) and when a debuff lands. Buffs lasting longer than you choose, and whole
kinds such as blessings, fold into one icon with a count; hover it for the list. It can replace the
game's own buff bar, and a click can dismiss a buff. To use your own sounds, put
`toolbox_buff_expiring.ogg` / `toolbox_debuff_landed.ogg` (or `.wav`) in your Lua folder, beside the
`toolbox` folder, or choose any file in the settings.

## Consumables bar

Food, potions and combat items such as caltrops move to their own bar, soonest to run
out first, with the same sweep, flash and alert. Pick the kinds in the settings, cap the number of icons,
and add or leave out buffs by name.

## Gear repair

An equipment bar shows worn items below the repair threshold (20% by default), with a sweep for the
durability they have lost, and a **Gear needs repair** notification tells you when an item drops below
it, and again when it breaks.

## XP

The **XP** window shows the session time, your adventurer and producer pools, and the XP you earned in
the last hour. Rest the pointer on it and **XP Detailed** pops up with XP this session, XP per hour
(session and last 10 minutes), your level and progress, the time to your next level, and a chart of the
last hour. Sessions survive `/lua reload`.

## Today

Gold picked up, kills, and adventurer and producer XP gained today (resets at local midnight). Rest the
pointer on it and **Today Detailed** lists every item you gained today, as **Looted**, **Crafted** (with
crafts per recipe, exceptional and failed, and materials used) or **Gathered** (nodes and harvests).

**Estimated values (optional, uses the internet):** turn on **Estimated values (SotANET)** in the
settings and Today Detailed adds each item's value (its count times its 90-day average sale price at
shroudoftheavatar.net, built from receipts players upload) and a total for the day. It is off by
default and needs **Internet** switched on for Toolbox in the add-on manager too. Toolbox then sends only
item names to shroudoftheavatar.net, remembers each price for 24 hours, and contacts no other site. Like
any website, that site can see your IP address. **Test connection** in the settings checks it works.

## Combat stats

A small HUD with your fight timer, DPS, damage taken and healing per second, crit and avoid rates, and up
to 8 character stats you choose (such as magic resistance). **Combat Detailed** adds each skill's damage,
per-target damage, damage types, a timeline and your recent fights. `/toolbox combat help` lists every
option.

## Notifications

Your guild's message of the day, unread and expiring mail, ransoms, new rewards, guild applications and
gear needing repair, in a Notifications window or a small HUD list. Each one can be turned off.

## Commands

`/toolbox` and `/tbx` do the same thing; `/toolbox commands` lists them all in chat.

- `/toolbox`: open the settings window
- `/toolbox help`: open the Docs window, a guide to everything
- `/toolbox toolbelt`: what's in your Toolbelt (`vitals|consumables|gear on|off`, `combat on|off`)
- `/toolbox buffs`: show or hide the buff bar
- `/toolbox consumables`: the consumables bar and what goes on it
- `/toolbox gear`: your worn items' durability, lowest first
- `/toolbox vitals`: show or hide the health, focus and Vigor bars
- `/toolbox xp` / `xpdetailed`: the XP windows (`/toolbox reset` starts a new session)
- `/toolbox daily` / `dailydetailed`: the Today windows
- `/toolbox combat`: the combat stats HUD
- `/toolbox notify`: notification settings

Settings are saved per character.
