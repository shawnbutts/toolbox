Toolbox: installing
===================

Toolbox is a Shroud of the Avatar add-on. Its headline is the Toolbelt: your buffs and debuffs,
health, focus and Vigor, food and potions, gear needing repair and your target in one strip you can
put anywhere. Around it: XP windows, today's loot, crafting and gathering, a combat stats HUD and
notifications.

You need a game client with Lua add-on API 25 or newer (the game update of 2026-09-30; older clients
skip Toolbox with a chat line saying it needs a newer client).


The official way: the add-on store
----------------------------------

Install Toolbox from the game's add-on store (the Community Addons window): find Toolbox, install
it, and switch it on in the add-on manager. Store updates arrive the same way. That is all most
players need; the rest of this file is for installing by hand.


Installing by hand (beta testers)
---------------------------------

A hand install is for beta testers trying a version before it reaches the store. If you have the
store version, remove it first: two copies of Toolbox tangle each other.

1. Find your Lua folder. In game, type  /lua path  in chat, or open the add-on manager and press
   "Open Folder". It usually contains a "SavedVariables" folder.
2. Extract the zip. It holds a folder called "toolbox" and this file.
3. Copy the whole "toolbox" folder into your Lua folder.
   Check: you should now have  <Lua folder>/toolbox/manifest.json
   (not toolbox/toolbox/manifest.json, and not the files loose in the Lua folder).
4. In game, type  /lua reload
5. Open the add-on manager and switch Toolbox ON. New add-ons always start switched off.
6. Type  /lua check toolbox  to confirm nothing is wrong with the folder.
7. Optional: for estimated item values, also switch Internet on for Toolbox in the add-on manager.

On the first run Toolbox prints "Toolbox is ready..." in chat and opens its settings window.

Updating by hand: delete the old "toolbox" folder, copy the new one in, and /lua reload. Your
settings are kept: they live in the SavedVariables folder, not in "toolbox".

Keep only one copy (no old folder, renamed copy or loose toolbox.lua in the Lua folder).
/tbx version says "copies loaded: 1" when all is well.

Testers: TESTING.txt (in the zip) says what to try in this version and lists the known issues.


Getting started
---------------

  /tbx            open or close the settings window (tick what you want on screen)
  /tbx help       open the Docs window: a guide to every feature, option and command
  /tbx version    the version and build you have (please include it in reports)

/toolbox works everywhere /tbx does. Ctrl+; also opens the settings (change the key in the add-on
manager, on Toolbox's row under "Keys").


Your settings
-------------

They are in your Lua folder's SavedVariables folder: toolbox.<character>.character.json for each
character and toolbox.account.json shared by all. To back up a setup, press Save now under Backup &
reset in the settings window, then copy those files. To restore it, or to move to another computer,
quit the game and copy them back.


Reporting a problem
-------------------

Please include:
  1. The line  /tbx version  prints.
  2. What you did, what you expected, and what happened.
  3. Any chat lines starting with "[Add-on: Toolbox]", especially errors.
  4. A screenshot if it's about how something looks.

Report at https://github.com/shawnbutts/toolbox/issues


Uninstalling
------------

From the store: remove it in the add-on manager. By hand: delete the "toolbox" folder from your Lua
folder and /lua reload. To also remove your settings, delete the toolbox.*.json files in the
SavedVariables folder.
