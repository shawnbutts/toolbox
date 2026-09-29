Toolbox beta: install and testing guide
=======================================

Thanks for testing Toolbox! It's a Shroud of the Avatar add-on with XP windows, daily stats, a buff
bar, a consumables bar, health, focus & Vigor bars, a combat stats HUD, an equipment repair bar and
notifications. This is a beta: please tell us what breaks.

You need a game client with Lua add-on API 15 or newer (older clients skip Toolbox with a chat line
saying it needs a newer client). Some options need a newer one still; settings greys them out.


1. Find your Lua folder
-----------------------

In game, either:
  * type  /lua path  in chat, or
  * open the add-on manager and press "Open Folder".

That folder is your "Lua folder". It usually contains a "SavedVariables" folder.


2. Install
----------

The zip holds a folder called "toolbox" and this file.

  1. Extract the zip.
  2. Copy the whole "toolbox" folder into your Lua folder.
     Check: you should now have  <Lua folder>/toolbox/manifest.json
     (not toolbox/toolbox/manifest.json, and not the files loose in the Lua folder).
  3. In game, type  /lua reload
  4. Open the add-on manager and switch Toolbox ON. New add-ons always start switched off.
  5. Type  /lua check toolbox  to confirm nothing is wrong with the folder.
  6. Optional: for estimated item values, also switch Internet on for Toolbox in the add-on
     manager (see "What to try").

If you had an earlier beta: delete any  toolbox_buff_expiring.ogg  or  toolbox_debuff_landed.ogg
lying loose in your Lua folder (earlier versions put them there). They override the sounds that now
come with the add-on.

On the first run Toolbox prints "Toolbox is ready..." in chat and opens its settings window.

Updating to a newer beta: delete the old "toolbox" folder first, then copy the new one in and
/lua reload. Your settings are kept (they live in the SavedVariables folder, not in "toolbox").

Please don't keep a second copy (an old folder, a renamed copy or a loose toolbox.lua) in the Lua
folder: two copies tangle each other. /tbx version says "copies loaded: 1" when all is well.


3. Getting started
------------------

  /tbx            open or close the settings window (tick what you want on screen)
  /tbx help       open the Docs window: a guide to every feature, option and command
  /tbx commands   list every command in chat
  /tbx version    the version and build you have (please include it in reports), plus what changed

/toolbox works everywhere /tbx does.

The settings window's "Show" dropdown picks a part to set up:
  * XP & Today: session time, pools, XP in the last hour; gold, kills and XP since midnight. Each
    can be hidden, a window or a HUD strip. Hover them for XP Detailed / Today Detailed.
  * Buffs, Consumables & gear, Health bars, Combat: the HUD strips.
  * Notifications: what's new since you last looked (guild message, mail, rewards, gear to repair...).
  * Sounds: alert volume and sound files.
  * HUD layout: which strips share one strip, and every strip's position.
Options that do nothing while their part is off are greyed out.

Moving the HUD strips: drag the small grip at a strip's top-left corner. If you can't see the grip,
untick Options > Interface > Nameplates & Chat Bubbles > "Lock Status Movement". Or use the
Position buttons in settings (HUD layout), or e.g.  /tbx buffs move 600 40

Shortcut: Ctrl+; opens the settings. You can change it in the add-on manager, on Toolbox's
row under "Keys".


4. What to try
--------------

Anything you like, but especially what's new in this beta (/tbx version lists it all):
  * Buff sweeps: they should now keep pace with the game's own buff bar all the way down (before,
    they froze at the step they first showed). Compare a buff's sweep on both bars for a minute.
  * Consumables bar: food and Obsidian potions get their own bar (and leave the buff bar). It flashes
    red with the buff alert when one is about to run out. Try gluing it under the buffs (settings,
    HUD layout). If you use weapon poisons: do they show as a buff at all? (/tbx buffs raw)
  * Equipment bar: worn items below 20% durability show with a sweep for what they've lost, and a
    "Gear needs repair" notification comes when one drops below it and again when it breaks.
    /tbx gear lists your gear. Do the percentages match the game's tooltips?
  * Vigor: a gold third bar under health and focus (past the level where Vigor applies). Hover it
    for the regen and crit bonuses. Does the percentage match the game's Vigor bar?
  * The settings window: one part at a time from the "Show" dropdown, a Hidden / Window / HUD strip
    choice for XP and Today, greyed-out options, and a HUD layout part. Is anything hard to find?
  * The Docs (/tbx help) and version (/tbx version) windows: pick a topic or version from the dropdown.
From beta 4:
  * Combat Detailed: rest the pointer on the combat stats HUD (or /tbx combat detail). Damage by
    skill, the last minute as a chart, healing, targets with kill times, damage types, last fights.
  * XP Detailed: the last hour as small columns under each track.
From beta 3:
  * Notifications: a window with what's new since you last looked: your guild's message of the
    day, new mail, mail about to expire, ransoms, rewards, guild applications. Each can go to the
    window or to a notification HUD strip (dropdown in settings, or /tbx notify via hud). Does
    anything show twice, or not at all? /tbx notify show shows everything current.
  * The buff bar:
      - Does each sweep match the game's own buff bar, including buffs cast before you logged in?
      - Buffs with more than 15 minutes left share one slot at the end with a count (hover it).
        Change the time in settings ("Group buffs lasting longer than").
      - Icons are sorted by time left, soonest on the left.
      - A buff about to run out flashes a red border (and plays a sound).
      - Getting a debuff plays a sound and shows it in the red second row.
      - Settings: "Replace the game's buff bar", "Click a buff to dismiss it", "Only during combat".
  * Estimated values: switch on "Estimated values (SotANET)" in settings and Internet for Toolbox in
    the add-on manager. Today Detailed then shows each item's value from SotANET's price list.
    Test connection in settings (or /tbx dd values test) checks the connection.
  * Sounds: /tbx sounds test plays both alerts; the "Alert volume" slider sets how loud.
  * XP after you die: "last hour" and XP/hour should keep counting. "Subtract XP lost" in settings
    shows the net change instead.
  * The settings window and the Docs window: is anything unclear or missing?
  * XP and XP Detailed while you fight or craft: do the numbers look right?
  * Today: kills, gold and items. Does it reset at your local midnight?
  * Health & focus bars while you take damage: do "current / max" match the game?
  * Combat stats in a fight: do DPS and damage taken look believable? Try adding a stat:
      /tbx stats resist      (finds stat names; any word works: absorb, dodge, crit, regen)
      /tbx combat stat add CombatHealthRegen
  * Moving, resizing and glueing the HUD strips (/tbx vitals glue on), then /lua reload: does
    everything come back where you left it?


5. Known issues
---------------

  * Alert sounds need a recent game client: older macOS clients failed to load add-on sound files
    (a game bug, now fixed). If /tbx sounds test is silent, update the game, and check for old
    toolbox_*.ogg files loose in your Lua folder (see Install).
  * The game only draws a sweep step when a new picture is made, so Toolbox makes a new one for each
    step, at most 8 a second for all sweeps together. With many short buffs at once some sweeps may
    step a little later than others. (Reported to the game's developers.)
  * The settings window is wider now; if the game remembered its old width, drag it wider once.
  * Weapon poisons: unknown whether the game shows them to add-ons. If one shows as a buff,
    /tbx consumables add <part of its name> puts it on the consumables bar.
  * The Ctrl+; shortcut may not take on some setups. If it does nothing, set a key for
    Toolbox in the add-on manager under "Keys".
  * Buffs with no fixed length (like the moon indicator) have no sweep until Toolbox sees them
    start.
  * "Gold picked up" counts every gold increase, including vendor sales and trades.
  * Kills come from your combat chat lines; if Kills stays at 0 while you're clearly killing
    things, please report it.


6. Reporting a problem
----------------------

Please include:
  1. The line  /tbx version  prints.
  2. What you did, what you expected, and what happened.
  3. Any chat lines starting with "[Add-on: Toolbox]", especially errors.
  4. For a specific part, its debug command's output:
       /tbx buffs debug     /tbx vitals debug     /tbx combat debug     /tbx sounds debug
       /tbx xp debug        /tbx notify show      /tbx dd values test   /tbx combat events 5
       /tbx gear            /tbx consumables      /tbx buffs trace <name>
  5. A screenshot if it's about how something looks.


7. Uninstalling
---------------

Delete the "toolbox" folder from your Lua folder and /lua reload. To also remove your Toolbox
settings, delete Toolbox's files in the SavedVariables folder (they're named after the add-on).
