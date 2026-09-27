Toolbox beta: install and testing guide
=======================================

Thanks for testing Toolbox! It's a Shroud of the Avatar add-on with XP windows, daily stats, a buff
bar, health & focus bars and a combat stats HUD. This is a beta: please tell us what breaks.

You need a game client with Lua add-on API 14 or newer (older clients skip Toolbox with a chat line
saying it needs a newer client).


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
  5. Type  /lua check toolbox  to confirm nothing is wrong with the folder. Messages about the sound
     files being there are expected for a hand install.

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

The settings window has a checkbox for each part:
  * XP: session time, pools, XP in the last hour. Hover it for XP Detailed.
  * Today: gold picked up, kills and XP since midnight. Hover it for every item gained today.
  * Buff bar, Health & focus bars and Combat stats: HUD strips.

Moving the HUD strips: drag the small grip at a strip's top-left corner. If you can't see the grip,
untick Options > Interface > Nameplates & Chat Bubbles > "Lock Status Movement". Or use the
Position buttons in settings, or e.g.  /tbx buffs move 600 40

Shortcut: Ctrl+Shift+; opens the settings. You can change it in the add-on manager, on Toolbox's
row under "Keys".


4. What to try
--------------

Anything you like, but especially:
  * New in this beta: the XP and Today windows as HUD strips. Tick "As a HUD strip" in settings
    (or /tbx xp hud, /tbx daily hud). Does hovering the strip still pop up XP Detailed / Today
    Detailed? Do long numbers fit?
  * /tbx version opens a window with what changed in each version.
  * The settings window and the Docs window: is anything unclear or missing?
  * XP and XP Detailed while you fight or craft: do the numbers look right?
  * Today: kills, gold and items. Does it reset at your local midnight?
  * The buff bar: does each sweep match the game's own buff bar? Does it turn red before a buff
    runs out?
  * Health & focus bars while you take damage: do "current / max" match the game?
  * Combat stats in a fight: do DPS and damage taken look believable? Try adding a stat:
      /tbx stats resist      (finds stat names; any word works: absorb, dodge, crit, regen)
      /tbx combat stat add CombatHealthRegen
  * Moving, resizing and glueing the HUD strips (/tbx vitals glue on), then /lua reload: does
    everything come back where you left it?


5. Known issues
---------------

  * Alert sounds don't play. The current client doesn't load add-on sound files; the buff sweep
    still turns red before a buff runs out. Nothing for you to fix.
  * The Ctrl+Shift+; shortcut may not take on some setups. If it does nothing, set a key for
    Toolbox in the add-on manager under "Keys".
  * A buff that was already running when you installed Toolbox shows no sweep until you recast it
    (the game doesn't tell add-ons how long a buff lasts, so Toolbox learns it from a cast).
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
  5. A screenshot if it's about how something looks.


7. Uninstalling
---------------

Delete the "toolbox" folder from your Lua folder and /lua reload. To also remove your Toolbox
settings, delete Toolbox's files in the SavedVariables folder (they're named after the add-on).
