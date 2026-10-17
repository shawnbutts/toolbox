# Toolbox

**Everything you watch in a fight, in one strip you can put anywhere.** Toolbox's **Toolbelt** joins
your buffs and debuffs (with clock sweeps and a warning before they run out), your health, focus and
Vigor, your food and potions, any gear that needs repair, and your target's health and effects into one
movable HUD strip that can appear only in combat. Around it: XP per hour and time to your next level, everything you looted,
crafted and gathered today with its market value, a crafting planner, map overlays, DPS and combat stats, and
notifications.

**Highlights**

- **The Toolbelt:** buffs, debuffs, health, focus, Vigor, food, potions, worn-out gear and your target in one strip, moved as one.
- **Target HUD:** your target's health and focus, and its effects with the time left on each.
- **Never let a buff drop:** a sound and a red flash before a buff runs out, and a sound when a debuff lands.
- **A tidier buff bar:** long buffs and blessings fold into one icon with a count; it can replace the game's own bar.
- **Food and potions on their own bar,** combat items too, with the same sweeps and warnings.
- **Gear repair warnings** before an item breaks, and again when it does.
- **XP tracking:** XP per hour, time to next level and a last-hour chart, for adventurer and producer XP.
- **Today:** gold, kills, XP, and every item looted, crafted or gathered, with optional values from shroudoftheavatar.net.
- **Combat stats:** DPS, damage taken, healing, crits, each skill's share, per-target damage and a fight timeline.
- **Crafting planner:** a recipe's materials, what you're short of and what to craft from scratch, with a shopping list and a build order by station.
- **Map overlays:** mark places on your map, or let the auto map mark every resource node you gather; your last death shows there too.
- **Notifications:** guild message, mail, rewards, gear needing repair and friends coming online, in a window, on the HUD or in chat, with an optional sound.
- **A one-click menu:** a column of gold buttons that opens any Toolbox window, lit while it's open.
- **All set up in one settings window,** with a search to find any setting and a guide to every feature in the game. No files to edit.
- **Back up your setup** by copying its settings files (the settings window shows where), or reset everything to the defaults.

**Getting started:** type `/toolbox` (or `/tbx`, or press **Ctrl+;**) to open the settings window and
tick what you want on screen. Its **Docs** button opens a guide to every feature, option and command.
Change the key in the add-on manager, on Toolbox's row under **Keys**. The **menu**, a column of gold
buttons at the top left, opens any Toolbox window with one click (change it or switch it off under **Menu,
setups, backup & reset** in the settings).

## The Toolbelt

Your buff bar with your health, focus and Vigor bars beside it and your consumables bar, equipment bar
and target under it: one strip, moved as one, with everything you watch in a fight. Pick what joins it in the
settings window (**Toolbelt**) or with `/toolbox toolbelt`, and tick **Only during combat** to have it
appear only when you're fighting. Each bar also works on its own strip, and the game's own buff bar and
health bars can be hidden while Toolbox's show.

## Buff bar

Your buffs and debuffs as their skill icons, with a clock-style sweep for the time left and, if you
like, the seconds counting down at the end. It can sound an alert a set number of seconds before a buff
runs out (the icon flashes red) and when a debuff lands; effects that come so often their sound is noise can be
muted, picked from your recent alerts, or kept from repeating within a time you choose, and any buff or debuff can play
your own sound file when you get it or when it's about to run out (record yourself saying its name, put it in
your Lua folder, then Settings, Buffs, or `/toolbox buffs sound get|end <name> = <file>`). Buffs lasting longer than you choose, and whole
kinds such as blessings, fold into one icon with a count; hover it for the list. It can replace the
game's own buff bar, and a click can dismiss a buff. To use your own sounds, put
`toolbox_buff_expiring.ogg` / `toolbox_debuff_landed.ogg` / `toolbox_notify.ogg` / `toolbox_ping.ogg` /
`toolbox_tap.ogg` / `toolbox_mail.ogg` (or `.wav`) in your Lua folder, beside the
`toolbox` folder, or choose any file in the settings.

The **buff block** shows every buff and debuff on a strip of its own instead, soonest to run out first, in
rows as many icons wide as you choose, nothing grouped (`/toolbox buffs block`).

## Consumables bar

Food, potions and combat items such as caltrops move to their own bar, soonest to run
out first, with the same sweep, flash and alert. Pick the kinds in the settings, cap the number of icons,
and add or leave out buffs by name.

## Target HUD

Your target's health (and focus) as bars, then its effects as icons with a sweep for the time left,
debuffs first; hover the bars for its name and the exact numbers. It shows what the game's own target frame shows, so a creature hiding its health
shows a full bar, and it lists every effect on the target (the game doesn't say who applied them). It joins
the Toolbelt above your buffs, under everything, or mirrored to the left of your health bars (its bars
fill from the right, level with yours), with bars sized like yours, or has its own strip. Like your health
bars, it can show numbers beside its bars, a background behind them, and flash when low, or just its effect
icons (settings, Toolbelt, Target bars). "Leave out your pet" keeps it empty when the game targets your pet
after a fight. Above the buffs and on the left its space is always kept, so nothing jumps when you pick up a
target; on the left that leaves a transparent blank area between the Toolbelt's grip and your bars
(labelled "Target" while settings are open, to help you place it). Its own strip can be mirrored too.

## Gear repair

An equipment bar shows worn items below the repair threshold (20% by default), with a sweep for the
durability they have lost, and a **Gear needs repair** notification tells you when an item drops below
it, and again when it breaks.

## XP

The **XP** window shows the session time, your adventurer and producer pools, and the XP you earned in
the last hour. Rest the pointer on it and **XP Detailed** pops up with skill levels gained and deaths this
session, XP this session, XP per hour
(session and last 10 minutes), your level and progress, the time to your next level, and a chart of the
last hour. Sessions survive `/lua reload`. The XP and Today windows can also be compact windows (the title
bar shows only on hover) or HUD strips.

## Today

Gold picked up, kills, adventurer and producer XP, skill levels gained and deaths today (resets at local
midnight). Rest the
pointer on it and the **Loot Tracker** lists every item you gained today, as **Looted**, **Crafted** (with
crafts per recipe, exceptional and failed, and materials used) or **Gathered** (nodes and harvests).
Its **Reset** button counts from now, for one hunt or run, with gold, kills and loot value per hour of play
("Since 14:32 (47m)"); the Today window keeps the whole day, and **Show all of today** brings it back. Finished
runs are kept: the **Runs** view lists your last 10 with where, how long and gold and loot value per hour, to
compare farming spots. A run's **Compass** button points your compass at where you played most, and on a newer game client
each run shows as a flag on your map.

**Estimated values (optional, uses the internet):** turn on **Estimated values (SotANET)** in the
settings and the Loot Tracker adds each item's value (its count times its 90-day average sale price at
shroudoftheavatar.net, built from receipts players upload) and a total for the day. It is off by
default and needs **Internet** switched on for Toolbox in the add-on manager too. Toolbox then sends only
item names to shroudoftheavatar.net, remembers each price for 24 hours, and contacts no other site. Like
any website, that site can see your IP address. **Test connection** in the settings checks it works.
SotANET lists items by their English names, so with the game in another language most items show "--";
Toolbox says so.

## Combat stats

A small HUD with your fight timer, DPS, damage taken and healing per second, crit and avoid rates, and up
to 8 character stats you choose in settings (search, pick, Add), such as magic resistance. **Combat Detailed** adds each skill's damage,
per-target damage, damage types, a timeline and your recent fights. `/toolbox combat help` lists every
option.

**Block, parry & dodge:** when you block, parry or dodge an attack, the word pops up over the middle of the
Toolbelt for a moment, with its own sound. You choose the text size and each word's colour, and switch each
word and sound on or off; your own `toolbox_block.ogg` / `toolbox_parry.ogg` / `toolbox_dodge.ogg` replace the
sounds.

## Notifications

Your guild's message of the day, unread and expiring mail, ransoms, new rewards, guild applications and
gear needing repair, friends or guild members coming online, and (on a newer game client) Calls to Arms and
official events from the game's calendar 15 minutes before they start, in a Notifications window, a small HUD
list or a chat line, each with an optional sound of its own (chime, ping, tap, doorbell, bell or low notes; mail rings the doorbell). Each one
can be turned off.

## Skill activity

Like the game's own skill bar: your skills' icons pop up on a strip of their own as they level, with the
level on the icon, a bar of the progress to the next (green rising, red falling) and the training mode as
the frame's colour. On newer game clients the right half of each icon sets the skill to train, maintain or
unlearn with one click, and a Pause skills tile at the start of the strip sets every skill to Off (or Maintain, your
choice) at once, so your experience pool keeps what you earn while farming; click it
again to put each skill back as it was. Vertical or horizontal; click
one to open the Skills window. A short celebration plays when a skill gains a level and a sad one when it
loses one (each can be switched off; your own `toolbox_skill_up.ogg` / `toolbox_skill_down.ogg` in the Lua
folder replaces them). Skill level changes (gained or lost) can also be listed on the notification HUD (`/toolbox skills`).

## Menu

A column of gold buttons on a shaded panel, at the top left at first: one click opens XP, XP Detailed, Today,
the Loot Tracker, the crafting planner, Combat Detailed, Notifications, the Docs or the settings, and a second click closes it. A
button is bright while its window is open. Move it by its grip. Under **Menu, setups, backup & reset** in the
settings make it a row, change its icon size and shade (every HUD strip has a Background shade slider too), hide it during combat, pick its buttons, or switch it
off to open windows from the settings as before (`/toolbox menu`).

## Location

A small strip showing where you are: the scene, your position (as `/loc` gives it, in whole numbers) and
which way you face, and on a newer game client the kinds of water you can fish in this scene ("Fishable water:
salt, fresh"). Hover it for the whole `/loc` line. Off by default: switch it on with the menu's Location button, under
**Map & location** in the settings, or type `/toolbox location`.

## Map overlays

Sets of places you mark in a scene, shown on its map one set at a time: one for loot, one for gathering, one for
vendors. Each scene has its own overlays and remembers which one it shows. Each place is a mark on the region map and
minimap (a newer game client), in a shape and color of its own, and Compass points the game's compass at one; on the
newest client the full map's corner names what Toolbox shows there ("Toolbox: Gathering, loot runs"). Up to 10
overlays a scene, with room for thousands of places in all. Mark as you go in the
small **Map overlays** window, where you also make, rename and delete them: the pin on the location strip opens it
(or **Map & location** in the settings, or `/toolbox overlay window`); `/toolbox mark <name>` marks where you stand.
Auto map, turned on in a scene, marks every resource node you gather there: in an overlay of its kind and in
Gathering, which shows them all. Nodes don't move, so one visit maps a scene. Kinds you don't want go on an
ignore list: `/toolbox overlay auto ignore <kind or word>`, or Ignore kind in the window. Your last death shows on
the map too, beside any overlay, and `/toolbox death compass` points you back to it; it clears itself once you're
back there, or after an hour in another scene.

## Crafting planner

Plan a craft from the recipes you know: `/toolbox plan` (or `/toolbox plan plate chest`). Every ingredient shows what
you need, have and are short of. A slot that takes a choice of material, like Metal Sheet, lists them with how many
you have, starting on the first you have enough of; a line under it shows what the picked one adds to the item, for
crafting a build. A material you pick yourself stays picked. The result line shows the item's stats with your picks.
With From scratch on, tick I'll craft to plan the crafts for what you're short of, as deep as your recipes go. The Shopping list adds up what to buy or gather, and the Build order lists the crafts by
station, materials first, ticked off as you craft. The Crafting Planner HUD follows the plan with the planner closed: the shopping list (what you have against what's needed) while you gather, then the build order, with a fanfare when every craft is done. Settings, Crafting holds it all, including when your recipe book is read (it can stutter the game): when the planner needs it, at login, or only when you ask.

## Commands

`/toolbox` and `/tbx` do the same thing; `/toolbox commands` lists them all in chat.

- `/toolbox`: open the settings window
- `/toolbox help`: open the Docs window, a guide to everything
- `/toolbox toolbelt`: what's in your Toolbelt (`vitals|consumables|gear|target on|off`, `combat on|off`)
- `/toolbox target`: the target HUD (`on|off`, `toolbelt on|off`)
- `/toolbox buffs`: show or hide the buff bar
- `/toolbox consumables`: the consumables bar and what goes on it
- `/toolbox gear`: your worn items' durability, lowest first
- `/toolbox vitals`: show or hide the health, focus and Vigor bars
- `/toolbox xp` / `xpdetailed`: the XP windows (`/toolbox reset` starts a new session)
- `/toolbox daily` / `dailydetailed`: the Today windows
- `/toolbox combat`: the combat stats HUD
- `/toolbox notify`: notification settings
- `/toolbox location`: the location strip (`on|off`, `facing on|off`, `water on|off`)
- `/toolbox overlay`: this scene's map overlays (`<name>`, `off`, `new`, `rename`, `delete`, `places`, `icon`, `color`, `auto`, `scenes`, `forget`)
- `/toolbox plan`: the crafting planner (`/toolbox plan <recipe>` finds one; `/toolbox plan hud`: the Crafting Planner HUD; `/toolbox plan book read`: read your recipe book now)
- `/toolbox mark`: mark where you stand in the shown overlay (`<name>`, `remove`, `compass`, `look`)
- `/toolbox menu`: the menu (`on|off`, `vertical|horizontal`, `size <n>`, `shade <n>`, `combat hide|show`)
- `/toolbox settings`: settings files and setups (`save`, `reset`, `cancel`, `setups`, `import`, `export`)

Settings are saved per character. To copy another character's setup, yours or someone else's on the same
computer, pick it under **Setups** in the settings window and press **Import**. A character's setup is listed
once its player ticks **List this character's setup for other characters** (off at first); **Export** saves
yours under a name. An import is a copy, so later changes stay each character's own.

The files are the game's saved-variable files in `Lua/SavedVariables`: `toolbox.<character>.character.json`
for each character, and `toolbox.account.json` shared by all (it holds the setups). To back up, press
**Save now** under **Menu, setups, backup & reset** in the settings window and copy those files; to restore it (or move to
another computer), quit the game and copy them back. **Reset all settings** there puts everything back to
the defaults at the next `/lua reload`. On the newest game client (Lua API 39) the game also keeps dated copies:
**Back up now** makes one, and Toolbox has one made before a reset, an import and the first start of a new version.
To go back, pick a copy and press **Restore** twice: this character's settings and positions come back at once.

Toolbox also keeps a copy of each character's settings, positions and run history in `toolbox.account.json`.
If the game ever can't read a character's file, Toolbox puts them back from that copy and says so in chat.
