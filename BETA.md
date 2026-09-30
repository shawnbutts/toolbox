Toolbox beta: testing guide
===========================

Thanks for testing Toolbox! It's a Shroud of the Avatar add-on. Its headline is the Toolbelt: your
buffs and debuffs, health, focus and Vigor, food and potions, gear needing repair and your target in one
strip you can put anywhere. Around it: XP windows, today's loot, crafting and gathering, a combat stats HUD and
notifications. This is a beta: please tell us what breaks.

To install it, follow INSTALL.txt (in the same zip): the "Installing by hand" part.

You need a game client with Lua add-on API 25 or newer (the game update of 2026-09-30; older clients
skip Toolbox with a chat line saying it needs a newer client).


1. Getting started
------------------

  /tbx            open or close the settings window (tick what you want on screen)
  /tbx help       open the Docs window: a guide to every feature, option and command
  /tbx commands   list every command in chat
  /tbx version    the version and build you have (please include it in reports), plus what changed

/toolbox works everywhere /tbx does.

The settings window's "Settings" dropdown picks a part to set up. It opens on the first:
  * Toolbelt: show it, and put the health bars, consumables bar and equipment bar Off, on their own
    strip, or In Toolbelt. The quickest way to get started.
  * XP & Today: session time, pools, XP in the last hour; gold, kills and XP since midnight. Each
    can be hidden, a window or a HUD strip. Hover them for XP Detailed / Today Detailed.
  * Buffs, Consumables & gear, Health bars, Combat: the HUD strips.
  * Notifications: what's new since you last looked (guild message, mail, rewards, gear to repair...).
  * Sounds: alert volume and sound files.
  * HUD layout: every strip's position.
  * Backup & reset: where your settings files are, to copy them; and Reset all settings.
Options that do nothing while their part is off are greyed out.

Moving the HUD strips: drag the small grip at a strip's top-left corner. If you can't see the grip,
untick Options > Interface > Nameplates & Chat Bubbles > "Lock Status Movement". Or use the
Position buttons in settings (HUD layout), or e.g.  /tbx buffs move 600 40

Shortcut: Ctrl+; opens the settings. You can change it in the add-on manager, on Toolbox's
row under "Keys".


2. What to try
--------------

Anything you like, but especially what's new in this beta (/tbx version lists it all):
  * This beta needs the game update of 2026-09-30 (add-on API 25), which fixed the problems we reported.
  * Sweeps on buffs, consumables and target effects are now the game's own cooldown wedge, run by the
    game: smooth and level with the game's buff bar. Compare them for a minute, including buffs cast
    before you logged in. Does a buff's wedge turn red when its expiry alert sounds, and back after a
    recast?
  * Health and focus bars read the game's own values and maximums: do they match the game's bars while
    you take damage?
  * Equipment bar: durability now counts against what a repair brings the item back to (as the game's
    tooltip shows it), and the tooltip says when an item needs a crafting station repair. /tbx gear
    lists everything: do the numbers match the game's tooltips?
  * Target names: creatures like stags should show their plain name now.
  * Backup & reset (settings): Save now, then copy toolbox.<character>.character.json and
    toolbox.account.json from Lua/SavedVariables (the page shows where). To restore, quit the game and
    copy them back. Try Reset all settings once (a second click, then /lua reload): everything back to
    the defaults, your stats kept?
  * XP, Today and Notifications can be compact windows (settings: Compact window): the title bar shows
    only while the pointer is on it.
  * Combat HUD stats: pick them in settings (Combat: Character stats on the HUD): search, pick, Add.
  * Target HUD options (Toolbelt page): which effects to show (All, Debuffs only, None) and how many icons.
  * A sound per notification (settings, Notifications): Chime, Ping, Tap, Bell or Low notes.
From beta 8:
  * Target HUD fixes: one "Mirrored" checkbox now (settings, Toolbelt page) instead of a third
    "Target row" choice. In the Toolbelt it puts the target left of your health bars; on its own strip it
    mirrors the strip. Mirrored now survives /lua reload (in beta 7 it went back to the top). The target's
    own strip has no name or percent any more (hover for them) and its bars are the size of yours.
From beta 7:
  * Target HUD (settings, Toolbelt: Target "In Toolbelt", or /tbx target on): your target's health,
    focus and effects. Try both "Target row" places, Above the buffs (the default) and Under everything,
    and the "Mirrored" checkbox. Do its bars line up with yours? Mirrored, do its bars fill from the
    right? Mirrored and above keep their space with no target (so nothing jumps); mirrored that is a
    blank area between the grip and your bars, labelled "Target" while settings are open.
    /tbx target debug shows what the game reports (odd creature names especially).
  * Skill levels gained and deaths: two new lines in Today, one in XP Detailed. Train a skill, die once:
    do they count?
  * Notifications: friends coming online (a chat line), guild members (off by default), and a chat or
    "+ sound" choice for every notification (settings, Notifications). /tbx sounds test plays the new
    chime. A new guild message of the day should show at once.
From beta 6:
  * The Toolbelt page (the first page of settings): turn on the Toolbelt and put each bar In Toolbelt.
    Does it come together as one strip you can move by its grip? Try "Only during combat".
  * Crafting and gathering: Today Detailed's "Show" dropdown switches between Looted, Crafted and
    Gathered (/tbx crafted, /tbx gathered). Craft something, take it off the table, harvest a node:
    do the counts look right? Materials you take back off a station should NOT show as made.
  * Consumables bar: long-lasting ones share one icon with a count, and "Most icons" caps the icons.
    Pick which kinds go on it (settings, Consumables & gear). Food, potions and combat items like
    caltrops by default; scrolls, torches and bait stay off.
  * Name lists in settings: "Always group by name" (Buffs) and the consumables' "Always on it" and
    "Left out" names now have a text box with Add and Remove.
  * "Show seconds left near the end" (Buffs): whole seconds over icons about to run out.
  * "Always group these kinds" (Buffs): e.g. every Blessing in the group slot.
  * Health, focus and Vigor bars are thinner, with more space between them.
  * Estimated values: the new "Test connection" button in settings (XP & Today).
From beta 5:
  * Buff sweeps: they should now keep pace with the game's own buff bar all the way down (before,
    they froze at the step they first showed). Compare a buff's sweep on both bars for a minute.
  * Consumables bar: food and Obsidian potions get their own bar (and leave the buff bar). It flashes
    red with the buff alert when one is about to run out. If you use weapon poisons: do they show as a
    buff at all? (/tbx buffs raw)
  * Equipment bar: worn items below 20% durability show with a sweep for what they've lost, and a
    "Gear needs repair" notification comes when one drops below it and again when it breaks.
    /tbx gear lists your gear. Do the percentages match the game's tooltips?
  * Vigor: a gold third bar under health and focus (past the level where Vigor applies). Hover it
    for the regen and crit bonuses. Does the percentage match the game's Vigor bar?
  * The settings window: one part at a time from the "Settings" dropdown, a Hidden / Window / HUD strip
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
  * Moving and resizing the HUD strips, then /lua reload: does everything come back where you left it?


3. Known issues
---------------

  * Alert sounds need a recent game client: older macOS clients failed to load add-on sound files
    (a game bug, now fixed). If /tbx sounds test is silent, update the game, and check for old
    toolbox_buff_expiring.ogg or toolbox_debuff_landed.ogg loose in your Lua folder: earlier betas put
    them there, and they override the sounds that now come with the add-on. Delete them.
  * The settings window is wider now; if the game remembered its old width, drag it wider once.
  * Target HUD: the game doesn't say who applied an effect, so it lists every effect on your target,
    not only yours.
  * Toolbox can show 8 HUD strips at once (a game limit). With everything on its own strip, the last
    one says so in chat: put some bars in the Toolbelt.
  * Weapon poisons: unknown whether the game shows them to add-ons. If one shows as a buff,
    /tbx consumables add <part of its name> puts it on the consumables bar.
  * The Ctrl+; shortcut may not take on some setups. If it does nothing, set a key for
    Toolbox in the add-on manager under "Keys".
  * Buffs with no fixed length (like the moon indicator) have no sweep until Toolbox sees them
    start.
  * Reset all settings and restoring copied files both need a restart of Toolbox (/lua reload, or for
    copied files, quit the game first): the game writes the settings files as it closes.
  * "Gold picked up" counts every gold increase, including vendor sales and trades.
  * Kills come from your combat chat lines; if Kills stays at 0 while you're clearly killing
    things, please report it.


4. Reporting a problem
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
