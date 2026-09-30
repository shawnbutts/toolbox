-- Toolbox: docs.lua
-- The Docs window (/toolbox docs, or the Docs button in settings): getting started, each
-- feature and its main options, tips, and every chat command (listed from the same table the
-- commands are registered from, so it can't go out of date). Built on first open.
--
-- Also the version window (/toolbox version): the version line and the changelog, which
-- tools/build.py bakes into changelog.lua (Toolbox.CHANGELOG) from CHANGELOG.md.
--
-- And notifications (Toolbox.Notify, at the end): the guild message of the day, new mail and
-- other game notices, in one window when there's something new.

local T = Toolbox
local D = {}
Toolbox.Docs = D

local UI = Shroud.UI
local WINDOW_ID = "toolbox_docs"
local GUTTER = 10
local win = nil
local vwin = nil         -- the version window (below)

-- The Docs and version windows share one of the add-on's 8 windows (docs: "8 windows" per
-- add-on; Toolbox has 7 others): opening one removes the other.
local function drop(which)
  local w = which == "docs" and win or vwin
  if not w then return end
  pcall(function() w:Destroy() end)
  if which == "docs" then win = nil else vwin = nil end
end

-- { heading, paragraph, paragraph, ... }. Plain text: markup is never interpreted.
D.SECTIONS = {
  { "Getting started",
    "Type /toolbox (or /tbx) to open the settings window and tick what you want on screen. Its Settings "
      .. "dropdown picks a category: Toolbelt (first, and the quickest start: your buffs, health bars, "
      .. "consumables and gear in one strip), XP & Today, Buffs, Consumables & gear, Health bars, Combat, "
      .. "Notifications, Sounds, and HUD layout (every strip's position). Options "
      .. "that do nothing while their feature is off are greyed out. Everything is saved per character. "
      .. "/toolbox help opens this guide; /toolbox commands lists the commands in chat.",
    "Shortcut: Ctrl+; opens the settings (if the game isn't using it). Change it, or pick one, in the "
      .. "add-on manager on Toolbox's row under Keys. /toolbox key shows the current one." },
  { "XP",
    "XP (/toolbox xp): session time, your adventurer and producer pools, and the XP you earned "
      .. "in the last hour. Rest the pointer on it and XP Detailed pops up.",
    "XP Detailed (/toolbox xpdetailed): skill levels gained and deaths this session, then per track, XP "
      .. "gained, XP per hour (session and last 10 minutes), level, progress, XP needed and time to the next "
      .. "level, and a Reset button. "
      .. "A session starts when you log in or press Reset, and survives /lua reload.",
    "Smaller: /toolbox xp hud (or XP window: HUD strip in settings) shows the XP window as a HUD strip, "
      .. "with no title bar or frame. Move it by its grip or /toolbox xp move <x> <y>; hovering still "
      .. "pops up XP Detailed. /toolbox xp window turns it back into a window.",
    "Or a compact window (XP window: Compact window in settings, or /toolbox xp compact): a window whose "
      .. "title bar only shows while the pointer is on it, over the top of the text, so it looks like a "
      .. "strip but can be resized and faded like any window (right-click it for opacity). Unlike a HUD "
      .. "strip it doesn't use one of Toolbox's 8 HUD strips." },
  { "XP over the last hour",
    "XP Detailed shows the last hour under each track as columns: XP gained in each 2-minute slice, "
      .. "tallest for your best stretch, with that best rate per hour beneath." },
  { "Today",
    "Today (/toolbox daily): gold picked up, kills by you or your pet, adventurer and producer XP, skill "
      .. "levels gained and deaths since midnight. A skill level counts when a skill's trained level passes "
      .. "the highest it has been (so unlearning and relearning doesn't count twice). Rest the pointer on "
      .. "it for Today Detailed: every item that arrived in your bags today, with counts.",
    "Today Detailed's Show dropdown: Looted (what you picked up; what you crafted or gathered is left "
      .. "out unless you tick Include crafted and gathered items in settings, or /toolbox dd include on), "
      .. "Crafted (/toolbox crafted: the items you took off crafting stations, your crafts per recipe with "
      .. "exceptional and failed, and crafting XP) and Gathered (/toolbox gathered: what the nodes you "
      .. "harvested held, the nodes, failed harvests and gathering XP). What you make is counted as it "
      .. "reaches your bags from a station and is named like a recipe you crafted; other things you take "
      .. "off a station (materials back, salvage returns) are listed apart. Crafted also lists the "
      .. "materials your crafts used (from each recipe's ingredients; tools and optional ones left out).",
    "Estimated values (optional): switch on Estimated values (SotANET) in settings, or /toolbox dd "
      .. "values on, and switch Internet on for Toolbox in the add-on manager. Today Detailed then shows "
      .. "each item's count times its 90-day average sale price from shroudoftheavatar.net (player-"
      .. "uploaded receipts) and a total; hover a value for the price each. Items with no recent sales "
      .. "stay blank. Only item names are sent, and each price is kept for 24 hours; /toolbox dd values "
      .. "refresh looks them up again, and Test connection in settings (or /toolbox dd values test "
      .. "[item]) checks the connection.",
    "Like XP, it can be a compact window or a HUD strip: /toolbox daily compact, daily hud (and daily "
      .. "window, daily move <x> <y>)." },
  { "Toolbelt",
    "The Toolbelt is your buff bar with your health, focus and Vigor bars beside it and your consumables, "
      .. "gear repair and target under it: one strip with everything you watch in a fight, moved as one. Build "
      .. "it on the settings window's Toolbelt page: Show the Toolbelt, then put each bar Off, on its Own "
      .. "strip or In Toolbelt. Or use /toolbox toolbelt vitals|consumables|gear|target on.",
    "Only during combat (settings, or /toolbox toolbelt combat on) shows the whole Toolbelt only in combat "
      .. "and a few seconds after, and while the settings window is open so you can place it. Move it by its "
      .. "grip, with HUD layout's Buff bar buttons, or /toolbox toolbelt move <x> <y>. The buff bar is its "
      .. "base: with the buff bar off, the other bars use their own strips. /toolbox toolbelt says what's in it." },
  { "Target",
    "/toolbox target on shows your target: its name and health (a thin red bar, and a blue one for focus "
      .. "when it has some), then its effects as icons with the time left as a sweep, debuffs (outlined) first. "
      .. "It shows what the game's target frame shows: a creature hiding its health reads \"health hidden\". "
      .. "The game doesn't say who applied an effect, so every effect on the target is listed. Hover for "
      .. "details.",
    "In the Toolbelt it has no text (hover for the name and numbers) and its bars match yours: the health "
      .. "bars' length and thickness (Health bars: Size and Bar length). With your health bars in the "
      .. "Toolbelt too, it runs across the whole Toolbelt: its bars start where yours do and its icons line "
      .. "up with your buffs. It goes above the buffs (the default; its space stays when you have no target, "
      .. "so nothing jumps) or under everything (hidden with no target): settings, Toolbelt, Target row, or "
      .. "/toolbox target place top|bottom.",
    "Mirrored (settings, Toolbelt, Mirrored; or /toolbox target mirror on): its bars fill from the right "
      .. "and up to 5 icons run to the left, most urgent nearest, at a fixed width. In the Toolbelt, with your "
      .. "health bars there too, it goes to the LEFT of your bars, each target bar level with yours (Target "
      .. "row doesn't apply then; without your health bars in the Toolbelt there's nothing to mirror against, "
      .. "so the checkbox is greyed out). On its own strip, the whole strip is mirrored.",
    "Target effects (settings, Toolbelt): All, Debuffs only, or None (just the bars); Most target icons "
      .. "sets how many show at once (8 by default, 5 mirrored). Or /toolbox target effects "
      .. "all|debuffs|none and /toolbox target icons <1-8>.",
    "The blank area: above the buffs and on the left, the target's space is always kept, even with no "
      .. "target, so your bars and buffs never jump when you pick one up (the Toolbelt is anchored at its "
      .. "grip, top left). On the left that leaves an empty area between the grip and your bars, as wide as "
      .. "5 icons plus a bar. It's transparent and clicks pass through it; while the settings window is open "
      .. "it says \"Target\" so you can see it when placing the Toolbelt. Drag by the grip as usual: your "
      .. "bars sit that far to the right of it.",
    "It joins the Toolbelt as its last row, or has its own strip (settings: Toolbelt, Target; or /toolbox "
      .. "target toolbelt on|off). With no target it hides, except while the settings window is open, so you "
      .. "can place it (/toolbox target move <x> <y>). /toolbox target debug shows what the game reports." },
  { "Buff bar",
    "/toolbox buffs: your buffs and debuffs (outlined red) as their skill icons, the one that runs out "
      .. "soonest on the left. A darkening "
      .. "sweep shows the time left; it turns red when a buff is about to run out. Hover an icon "
      .. "for its tooltip.",
    "Options: icon size; a sound before a buff runs out (/toolbox buffalert 10 = ten seconds "
      .. "before); a sound when a debuff lands (/toolbox debuffalert on/off).",
    "Without relying on colour: debuffs have their own row (the second); a buff about to run out blinks "
      .. "its border (Flash, on by default) and sounds its alert; Show seconds left near the end adds the "
      .. "number; and a sweep's size shows the time left whatever its colour. The same goes for the "
      .. "consumables and equipment bars (a broken item's sweep covers the whole icon).",
    "Buffs with more than 15 minutes left (Obsidian potions, for example) share one slot at the end of "
      .. "the row, showing how many there are; hover it for each one and its time left. A buff moves back "
      .. "onto the bar once it has less than that left. Change the time in settings (Group buffs lasting "
      .. "longer than) or with /toolbox buffs group after 30 (minutes; off turns it off). To always group "
      .. "a buff, add part of its name in settings (Buffs, Always group by name) or with /toolbox buffs "
      .. "group add <name> (remove <name> takes it off; "
      .. "/toolbox buffs debug shows buffs' names).",
    "Show seconds left near the end (settings, or /toolbox buffs countdown on) puts the whole seconds "
      .. "over an icon in its last 30 seconds (or what you choose, /toolbox buffs countdown 10), on the "
      .. "buff, debuff and consumable icons.",
    "Only during combat (settings, or /toolbox buffs combat on|off) shows the bar only while you're "
      .. "in combat and for a few seconds after, so it can sit in your line of sight without being in "
      .. "the way. It also shows while the settings window is open, so you can place it. It's the "
      .. "Toolbelt's base, so the whole Toolbelt hides and shows with it.",
    "Two settings on newer game clients: Replace the game's buff bar hides the game's own bar while "
      .. "this one is showing (it comes back whenever this one is off), and Click a buff to dismiss it "
      .. "works like the game's right-click Dismiss. Chat: /toolbox buffs replace on|off, "
      .. "/toolbox buffs dismiss on|off." },
  { "Health, focus & Vigor bars",
    "/toolbox vitals: your health and focus with \"current / max\", and a gold Vigor bar with its "
      .. "percentage (hover it for what Vigor adds to health regen, focus regen and critical chance). The "
      .. "Vigor bar shows once you are past the level where Vigor applies; Show Vigor in settings, or "
      .. "/toolbox vitals vigor off, hides it.",
    "Options: size (75-250%), bar length, show bars and/or numbers, a dark or light panel "
      .. "behind the numbers, and a flash when a value drops below a percentage (Test flash "
      .. "shows it). They can join the Toolbelt, beside the buffs (Toolbelt in settings)." },
  { "Combat stats",
    "/toolbox combat: fight timer, DPS (last 5 seconds and fight average), damage taken and "
      .. "healing per second, crit % and avoided %, plus character stats you choose.",
    "Choose the stats in settings (Combat: Character stats on the HUD): type part of a name (resist, "
      .. "dodge, crit, regen...) and Search, pick one from the list (it shows your value now) and Add; "
      .. "pick a shown one and Remove. With an empty search it suggests a few. Up to 8, changed at any "
      .. "time, mid-fight too. In chat: /toolbox stats resist finds names, /toolbox combat stat add "
      .. "CombatHealthRegen adds one, stat remove takes it off. /toolbox combat help has more.",
    "Combat Detailed (hover the combat HUD, or /toolbox combat detail): your damage by skill as "
      .. "bars, longest first (hover one for hits, crits and over-time ticks); the last minute as a "
      .. "chart, damage done up and damage taken down; and healing with how much was wasted as "
      .. "overheal; your targets (damage to each creature and how long each took to kill); and damage "
      .. "types, a bar split by element for damage done and one for damage taken. Switch between this "
      .. "fight and the whole session with the dropdown (or /toolbox combat detail session). /toolbox "
      .. "combat reset clears both." },
  { "Consumables bar",
    "Food, potions (Obsidian ones included), weapon poisons and combat consumables like caltrops get their "
      .. "own bar, by the kind the game gives each buff. Pick the kinds in settings (Consumables & gear, one "
      .. "checkbox each) or with /toolbox consumables cat <Kind> on|off; names containing Scroll, Torch or "
      .. "Bait are left out (settings: Left out by name, or /toolbox consumables exclude add|remove <name>).",
    "They show as icons with the sweep, soonest to run out first, and leave the buff bar. "
      .. "When one is about to run out it flashes red and the buff "
      .. "alert sounds (the buff bar's alert settings), and once it has run out it goes. Long-lasting ones "
      .. "(the buff bar's Group buffs lasting longer than) and any past Most icons share one slot with a "
      .. "count; hover it for the list. On its own strip it can show only during combat. It can join the "
      .. "Toolbelt as a row under the debuffs (/toolbox toolbelt consumables on).",
    "Other buffs can go on it too: add a name or part of one in settings (Always on it by name) or "
      .. "with /toolbox consumables add <name> (remove to undo). "
      .. "/toolbox consumables lists what is in effect; /toolbox consumables bar off puts food and potions "
      .. "back on the buff bar. On a game client without buff categories only food and potions are "
      .. "recognised (by name)." },
  { "Gear repair",
    "The equipment bar shows worn items that need repair: each item's icon with a red sweep for the "
      .. "durability it has lost, lowest first; hover one for its durability. Durability counts against what "
      .. "a repair brings the item back to, so 100% means an ordinary repair has nothing to fix; when that "
      .. "has worn well below new, the tooltip says it needs a crafting station repair. It shows only items "
      .. "below the repair threshold (20% unless you change it), and hides when nothing needs repair. While the "
      .. "settings window is open it shows every worn item, so you can place it. Its icons are the buff bar's "
      .. "size. It can join the Toolbelt as its last row (/toolbox toolbelt gear on); it then moves and hides "
      .. "with it.",
    "The Gear needs repair notification says when an item drops below the threshold, and again when "
      .. "it breaks; a repaired item warns again next time. Settings (Equipment bar) sets the threshold and "
      .. "switches the bar off; the notification has its own switch under Notifications. /toolbox gear "
      .. "lists your worn items and their durability; /toolbox gear repair 30 sets the threshold; "
      .. "/toolbox gear bar off hides the bar; /toolbox gear move <x> <y> places it." },
  { "Moving the HUD strips",
    "The buff bar, health & focus bars, combat stats, the consumables bar and the equipment bar are "
      .. "HUD strips. Drag the grip at a "
      .. "strip's top-left corner (untick Options > Interface > Nameplates & Chat Bubbles > "
      .. "Lock Status Movement to see it), use the Position buttons in settings (HUD layout), or type e.g. "
      .. "/toolbox buffs move 600 40." },
  { "Notifications",
    "A Notifications window tells you what's new since you last saw it: your guild's message of the "
      .. "day, new mail, mail about to expire, ransoms, new rewards, guild applications and gear needing "
      .. "repair. It opens at "
      .. "login, after /lua reload, or as soon as something changes, and shows everything new together. "
      .. "Nothing already seen shows again.",
    "Switch each one on or off in settings (Notifications), or with /toolbox notify <name> on|off "
      .. "(names: motd, mail, expiring, ransoms, rewards, applications, durability, friends, guild). Friends and "
      .. "guild members coming online arrive as chat lines by default (guild: off). /toolbox notify lists them; "
      .. "/toolbox notify show shows everything current; /toolbox motd shows the guild message.",
    "Each can show in the Notifications window, on the notification HUD or as a chat line, with or "
      .. "without a sound (the dropdown next to it in settings, e.g. HUD + sound; or /toolbox notify <name> "
      .. "via window|hud|chat and /toolbox notify <name> sound on|off, or leave out the name for all). The "
      .. "sound is a rising chime by default; each source can have its own (Sounds page: Notification sounds: "
      .. "Chime, Ping, Tap, Bell or Low notes; or /toolbox notify friends sound ping). Several arriving "
      .. "together play each sound once. The window can be compact (settings: "
      .. "Compact Notifications window, or /toolbox notify compact on): its title bar shows only on hover. "
      .. "The HUD lists the "
      .. "latest 20, newest on top, one line each (hover a line for all of it; scroll for older ones). It "
      .. "shows when something arrives and hides after 10 seconds, or never (HUD: hide after, or "
      .. "/toolbox notify hud hide 30); it stays while the pointer is on it. Move it like the other HUD "
      .. "strips (settings, or /toolbox notify hud move <x> <y>); /toolbox notify hud clear deletes its history." },
  { "Sounds",
    "The alert sounds live in the add-on's folder. To use your own, put "
      .. "toolbox_buff_expiring.ogg, toolbox_debuff_landed.ogg, toolbox_notify.ogg, toolbox_ping.ogg or "
      .. "toolbox_tap.ogg (or .wav) in your Lua folder, "
      .. "beside the toolbox folder, or pick any file in settings. /toolbox sounds shows what "
      .. "each alert uses; /toolbox sounds 50 sets the volume." },
  { "Backup & reset",
    "Your settings are in the game's saved-variable files (Lua/SavedVariables): one per character, ending "
      .. ".character.json, and one shared, ending .account.json. To back up, press Save now (Settings, Backup "
      .. "& reset) and copy them. To restore or move computers, quit the game and copy them back.",
    "Reset all settings applies at the next /lua reload; stats are kept." },
}

local function heading(text)
  return UI.Label{ text = text, class = "heading", style = { marginTop = 8 } }
end

local function para(text)
  return UI.Label{ text = text, class = "text", style = { whiteSpace = "wrap", marginTop = 2 } }
end

-- "/toolbox name (or alias) - help" for every registered command.
function D.CommandLines()
  local lines = {}
  local c = "/" .. T.commands[1] .. " "
  for _, cmd in ipairs(T.CommandList()) do
    local also = cmd.aliases and (" (or " .. table.concat(cmd.aliases, ", ") .. ")") or ""
    lines[#lines + 1] = c .. cmd.name .. also .. " - " .. cmd.help
  end
  return lines
end

-- The Docs window shows one topic at a time, picked from a dropdown: each guide section, then
-- Commands. Each is built the first time it's picked (the whole guide was built at once; owner,
-- 2026-09-29, review item 11).
D.COMMANDS_TOPIC = "Commands"

-- The topic titles, in dropdown order. Pure.
function D.Topics()
  local out = {}
  for i, section in ipairs(D.SECTIONS) do out[i] = section[1] end
  out[#out + 1] = D.COMMANDS_TOPIC
  return out
end

-- The labels for one topic.
local function topicLabels(title)
  local out = { heading(title) }
  if title == D.COMMANDS_TOPIC then
    out[#out + 1] = para("/" .. T.commands[1] .. " and /" .. T.commands[2] .. " do the same thing.")
    for _, line in ipairs(D.CommandLines()) do
      out[#out + 1] = para(line)    -- same colour as the rest (dim was hard to read)
    end
    return out
  end
  for _, section in ipairs(D.SECTIONS) do
    if section[1] == title then
      for k = 2, #section do out[#out + 1] = para(section[k]) end
    end
  end
  return out
end

local dbody = nil             -- the column the topics are added to
local dbuilt = {}             -- title -> its column

-- Shows one topic (by title), building it the first time. Returns true when shown.
function D.ShowTopic(title)
  if not win then return false end
  local known = false
  for _, t in ipairs(D.Topics()) do
    if t == title then known = true end
  end
  if not known then return false end
  if not dbuilt[title] then
    local ok, col = pcall(function() return dbody:Add(UI.Column{ children = topicLabels(title) }) end)
    if not ok then
      T.Print("That part of the guide can't be shown right now; pick it again in a moment.")
      return false
    end
    dbuilt[title] = col
  end
  for t, col in pairs(dbuilt) do T.SetVisible(col, t == title) end
  local pick = win:Find("docs_pick")
  if pick then pick:SetValue(title) end
  return true
end

local function build()
  local topics = D.Topics()
  dbody = UI.Column{ id = "docs_body", style = { paddingLeft = GUTTER, paddingRight = GUTTER } }
  dbuilt = {}
  win = UI.Window{
    id = WINDOW_ID, title = "Toolbox Docs",
    width = 460, height = 520, minWidth = 300, minHeight = 200,
    x = T.Window.DEFAULT_X, y = T.Window.DEFAULT_Y,
    escCloses = true,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = {
      UI.Row{ style = { alignItems = "center", paddingLeft = GUTTER, paddingRight = GUTTER, marginBottom = 4 },
        children = {
          UI.Label{ text = "Topic", class = "text", style = { flexGrow = 1 } },
          UI.Dropdown{ id = "docs_pick", choices = topics, value = topics[1],
            tooltip = "Which part of the guide to show; Commands lists every command",
            onChange = function(_, title) D.ShowTopic(title) end },
        } },
      UI.Scroll{ style = { flexGrow = 1 }, children = { dbody } },
    },
  }
  D.ShowTopic(topics[1])
end

function D.IsShown()
  return win ~= nil and win:IsShown()
end

function D.Toggle()
  if not win then
    drop("version")
    build()
  end
  if win:IsShown() then
    win:Hide()
  elseif not win:Show() then
    T.Print("The Docs window can't reopen right now; try again in a few seconds.")
  end
end

function D.Open()
  if not win then
    drop("version")
    build()
  end
  if not win:IsShown() and not win:Show() then
    T.Print("The Docs window can't reopen right now; try again in a few seconds.")
  end
end

-- ---------------------------------------------------------------------------
-- Version window
-- ---------------------------------------------------------------------------

local VERSION_ID = "toolbox_version"

-- The changelog ({ kind, text } rows; see changelog.lua) split per version, newest first:
-- { { title, entries = { rows under it } } }. Pure.
function D.ChangelogVersions(rows)
  local out = {}
  for _, entry in ipairs(rows or {}) do
    if entry[1] == "version" then
      local title = entry[2]
      if title == "Unreleased" then title = "Unreleased (newer than " .. T.version .. ")" end
      out[#out + 1] = { title = title, entries = {} }
    elseif out[#out] then
      local list = out[#out].entries
      list[#list + 1] = entry
    end
  end
  return out
end

-- The labels for one version's rows (sections, items, paragraphs).
local function versionLabels(entries)
  local out = {}
  for _, entry in ipairs(entries) do
    local kind, text = entry[1], entry[2]
    if kind == "section" then
      out[#out + 1] = UI.Label{ text = text, class = "bright", style = { marginTop = 6 } }
    elseif kind == "item" then
      out[#out + 1] = UI.Label{ text = "- " .. text, class = "text",
        style = { whiteSpace = "wrap", marginTop = 2, paddingLeft = 8 } }
    else
      out[#out + 1] = para(text)
    end
  end
  if #out == 0 then out[1] = para("No changes listed.") end
  return out
end

-- The version window shows one version's notes at a time, picked from a dropdown; each is built the
-- first time it's picked (the whole changelog was ~140 labels at once; owner, 2026-09-29).
local versions = nil          -- D.ChangelogVersions(T.CHANGELOG), when the window is built
local vbody = nil             -- the column the versions' notes are added to
local vbuilt = {}             -- title -> its column

-- Shows one version's notes (by title), building them the first time. Returns true when shown.
function D.ShowChangelogVersion(title)
  if not vwin or not versions then return false end
  local found = nil
  for _, v in ipairs(versions) do
    if v.title == title then found = v end
  end
  if not found then return false end
  if not vbuilt[title] then
    local ok, col = pcall(function()
      return vbody:Add(UI.Column{ children = versionLabels(found.entries) })
    end)
    if not ok then
      T.Print("Those notes can't be shown right now; pick them again in a moment.")
      return false
    end
    vbuilt[title] = col
  end
  for t, col in pairs(vbuilt) do T.SetVisible(col, t == title) end
  local pick = vwin:Find("version_pick")
  if pick then pick:SetValue(title) end
  return true
end

local function buildVersion()
  versions = D.ChangelogVersions(T.CHANGELOG)
  local titles = {}
  for i, v in ipairs(versions) do titles[i] = v.title end
  if #titles == 0 then titles[1] = "No changelog" end
  vbody = UI.Column{ id = "version_body", style = { paddingLeft = GUTTER, paddingRight = GUTTER } }
  vbuilt = {}
  vwin = UI.Window{
    id = VERSION_ID, title = "Toolbox " .. T.version,
    width = 460, height = 480, minWidth = 300, minHeight = 160,
    x = T.Window.DEFAULT_X, y = T.Window.DEFAULT_Y,
    escCloses = true,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = {
      UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER, marginBottom = 4 }, children = {
        UI.Label{ id = "version_line", text = T.VersionLine(), class = "text", style = { whiteSpace = "wrap" } },
        UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
          UI.Label{ text = "Changes in", class = "text", style = { flexGrow = 1 } },
          UI.Dropdown{ id = "version_pick", choices = titles, value = titles[1],
            tooltip = "Which version's changes to show",
            onChange = function(_, title) D.ShowChangelogVersion(title) end },
        } },
      } },
      UI.Scroll{ style = { flexGrow = 1 }, children = { vbody } },
    },
  }
  if versions[1] then D.ShowChangelogVersion(versions[1].title) end
end

-- Opens the version window (leaves it open if it already is), with the version line current.
function D.OpenVersion()
  if not vwin then
    drop("docs")
    buildVersion()
  end
  vwin:Find("version_line"):SetText(T.VersionLine())
  if not vwin:IsShown() and not vwin:Show() then
    T.Print("The version window can't reopen right now; try again in a few seconds.")
  end
end

function D.IsVersionShown()
  return vwin ~= nil and vwin:IsShown()
end

-- ---------------------------------------------------------------------------
-- Notifications (Toolbox.Notify)
-- ---------------------------------------------------------------------------
-- Tells the player about what's new since they last saw it: the guild message of the day, new
-- mail, mail about to expire, ransoms, new rewards, guild applications (all API 14). Three
-- parts, kept apart so each can grow on its own:
--   * N.SOURCES, one entry per kind: key (chat and saved-var name), label, tip, default, and
--     Check(seen, ctx) -> notice or nil, plus an optional second value to remember quietly
--     (a count going down: nothing to say). A notice is { title?, text, seen = what to remember
--     once it has been delivered }. ctx holds this check's game reads (social, notes).
--   * N.DELIVERY, how notices reach the player, by name: "window" (one Notifications window) and
--     "hud" (a HUD strip listing the latest, newest on top, hidden again after a while). Each
--     source has a `via` pref naming one (N.VIAS lists them for settings); a chat line, a sound or
--     another kind of window is a new entry here and in N.VIAS, with no change to the sources.
--   * N.Check (every tick, ShroudOnStart, and the game's social / notification callbacks): per
--     source, compare with what it last saw, gather new notices by delivery, deliver them, and
--     remember them as seen only once delivered (a window's Show can be refused: it is simply
--     tried again next tick). Sources switched off are tracked quietly, so switching one on
--     doesn't bring up old news. For N.SETTLE seconds after start or a character change, counts
--     going down are not remembered: at login they read 0 until the game has loaded them.
-- Saved var "notify" (character scope): { v = 1, sources = { [key] = { on = bool, seen = any,
-- via = "window"|"hud"|"chat", sound = bool } } }. The older "guild_motd" ({ show, seen }) is taken over once.
-- `sound`: the source's sound (`soundKey`, one of N.SOUNDS; default the "notify" chime) plays once per check
-- that delivered one of its notices; several sources arriving together play each distinct sound once.
-- The HUD's: "notify_hud" { hideAfter = seconds (0 = never), x, y } and "notify_history"
-- { v = 1, list = { { when = "HH:MM", title, text } } } (newest first, at most N.Hud.KEEP).

local N = {}
Toolbox.Notify = N

local nprefs = nil        -- this character's prefs (the saved-var scope follows the character)

N.SETTLE = 30             -- seconds after start / a character change before counts can go down
N.WINDOW_ID = "toolbox_notify"

local function plural(n, one, many) return T.FormatNumber(n) .. " " .. (n == 1 and one or many) end

-- A Check for a count the game shows (unread mail, ransoms, ...): a notice when it goes up.
-- `say(total, new)` words it; new == total when nothing was seen before.
local function countCheck(field, say)
  return function(seen, ctx)
    local n = nil
    if type(ctx.notes) == "table" then n = ctx.notes[field] end
    if type(n) ~= "number" or n < 0 then return nil end
    local before = type(seen) == "number" and seen or 0
    if n < before then return nil, n end
    if n == before then return nil end
    return { text = say(n, n - before), seen = n }
  end
end

-- A Check for an on/off indicator (mail expiring, new rewards): a notice when it comes on.
local function flagCheck(field, text)
  return function(seen, ctx)
    local v = nil                            -- not `a and b or nil`: b is often false here
    if type(ctx.notes) == "table" then v = ctx.notes[field] end
    if type(v) ~= "boolean" then return nil end
    if not v then
      if seen == true then return nil, false end
      return nil
    end
    if seen == true then return nil end
    return { text = text, seen = true }
  end
end

-- The guild message to show, or nil: in a guild, not empty, and not the one already seen.
-- Leading and trailing spaces don't count as a change.
function N.NewMotd(summary, seen)
  if type(summary) ~= "table" or summary.inGuild ~= true then return nil end
  if type(summary.guildMotd) ~= "string" then return nil end
  local text = T.Trim(summary.guildMotd)
  if text == "" or text == seen then return nil end
  return text
end

-- A saved table `seen` (the gear source's { [item] = stage }), keeping string keys and values only.
local function plainStrings(t)
  local out = {}
  for k, v in pairs(t) do
    if type(k) == "string" and type(v) == "string" then out[k] = v end
  end
  return out
end

-- Friends and guild members coming online (API 18 events, not a state to compare): each event is queued
-- with a running number, and the source's "seen" is the last number delivered. The numbers restart with
-- the add-on, so these sources' `seen` isn't taken from the save (`transient`).
N.ONLINE_KEEP = 20            -- queued names per source
local online = { friends = { n = 0, list = {}, dropped = 0 }, guild = { n = 0, list = {}, dropped = 0 } }

-- From ShroudOnFriendStatusChanged / ShroudOnGuildMemberStatusChanged (core.lua): queues who came online.
function N.OnStatus(which, changes, dropped)
  local q = online[which]
  if not q then return end
  for _, c in ipairs(T.List(changes)) do
    local name = T.Field(c, "name")
    if T.Field(c, "online") == true and type(name) == "string" and name ~= "" then
      q.n = q.n + 1
      q.list[#q.list + 1] = { id = q.n, name = name }
      if #q.list > N.ONLINE_KEEP then table.remove(q.list, 1) end
    end
  end
  if type(dropped) == "number" and dropped > 0 then q.dropped = q.dropped + dropped end
  N.Check()
end

local function onlineCheck(which, title)
  return function(seen)
    local q = online[which]
    local last = type(seen) == "number" and seen or 0
    if q.n <= last then return nil end
    local names = {}
    for _, e in ipairs(q.list) do
      if e.id > last then names[#names + 1] = e.name end
    end
    local text = table.concat(names, ", ") .. " came online."
    if q.dropped > 0 then text = text .. " (And others the game didn't list.)" end
    q.dropped = 0
    return { title = title, text = text, seen = q.n }
  end
end

N.SOURCES = {
  { key = "motd", label = "Guild message of the day", default = true,
    tip = "Your guild's message of the day, when it has changed since you last saw it",
    Check = function(seen, ctx)
      local text = N.NewMotd(ctx.social, seen)
      if not text then return nil end
      local guild = type(ctx.social.guildName) == "string" and ctx.social.guildName or ""
      return { title = guild ~= "" and (guild .. ": message of the day") or "Guild message of the day",
               text = text, seen = text }
    end },
  { key = "mail", label = "New mail", default = true,
    tip = "When new letters arrive in your mailbox",
    Check = countCheck("unreadMail", function(total, new)
      if new == total then return "You have " .. plural(total, "unread letter", "unread letters") .. "." end
      return plural(new, "new letter", "new letters") .. " (" .. T.FormatNumber(total) .. " unread in all)."
    end) },
  { key = "expiring", label = "Mail about to expire", default = true,
    tip = "When some of your mail is about to expire (expired mail is lost)",
    Check = flagCheck("mailExpiring", "Some of your mail is about to expire. Collect it before it's gone.") },
  { key = "ransoms", label = "Ransoms", default = true,
    tip = "When a thief holds something of yours for ransom",
    Check = countCheck("ransoms", function(total, new)
      if new == total then return "You have " .. plural(total, "ransom notice", "ransom notices") .. "." end
      return plural(new, "new ransom notice", "new ransom notices") .. " (" .. T.FormatNumber(total) .. " in all)."
    end) },
  { key = "rewards", label = "New rewards", default = true,
    tip = "When the game's new-reward indicator lights up",
    Check = flagCheck("newRewards", "You have new rewards waiting.") },
  { key = "applications", label = "Guild applications", default = true,
    tip = "When players apply to your guild (only if you may manage recruitment)",
    Check = countCheck("guildApplications", function(total, new)
      if new == total then return plural(total, "guild application is", "guild applications are") .. " waiting." end
      return plural(new, "new guild application", "new guild applications") .. " (" .. T.FormatNumber(total)
        .. " waiting)."
    end) },
  { key = "durability", label = "Gear needs repair", default = true,
    tip = "When a worn item drops below the repair threshold (Equipment bar settings), and again when it breaks",
    Check = function(seen)
      local items = T.Gear.Latest()          -- the equipment bar's reading, not a new one
      if #items == 0 then return nil end     -- not loaded (or a scene change): keep what was seen
      local notice, quiet = T.Gear.Notice(items, seen, T.Gear.Threshold())
      if notice then notice.title = "Gear needs repair" end
      return notice, quiet
    end },
  { key = "friends", label = "Friends coming online", default = true, via = "chat", transient = true,
    tip = "When a friend logs in (a chat line by default)",
    Check = onlineCheck("friends", "Friends online") },
  { key = "guild", label = "Guild members coming online", default = false, via = "chat", transient = true,
    tip = "When a member of your guild logs in (off by default: a big guild is busy)",
    Check = onlineCheck("guild", "Guild members online") },
}

local function sourceFor(key)
  for _, src in ipairs(N.SOURCES) do if src.key == key then return src end end
  return nil
end

-- ---------------------------------------------------------------------------
-- Delivery
-- ---------------------------------------------------------------------------

N.DELIVERY = {}
N.DELIVERY_DEFAULT = "window"
local nwin = nil

local function clearWindow()
  if not nwin then return end
  for _, src in ipairs(N.SOURCES) do nwin:Find("n_" .. src.key):SetVisible(false) end
end

local function buildWindow()
  local sections = {}
  for _, src in ipairs(N.SOURCES) do       -- one fixed section per source, shown when it has news
    sections[#sections + 1] = UI.Column{ id = "n_" .. src.key, visible = false, style = { marginBottom = 8 },
      children = {
        UI.Label{ id = "n_" .. src.key .. "_title", text = src.label, class = "heading" },
        UI.Label{ id = "n_" .. src.key .. "_text", text = "", class = "text",
          style = { whiteSpace = "wrap", marginTop = 2 } },
      } }
  end
  local compact = N.GetCompact()
  nwin = UI.Window{
    id = N.WINDOW_ID, title = "Notifications",
    compact = compact,          -- API 19: the title bar only on hover, over the content (setting: N.SetCompact)
    width = 380, height = 240, minWidth = 220, minHeight = 120,
    x = T.Window.DEFAULT_X, y = T.Window.DEFAULT_Y,
    escCloses = not compact,    -- a compact window's close button only shows on hover
    onClose = function() clearWindow() end,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = {
      UI.Scroll{ style = { flexGrow = 1 }, children = {
        UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = sections },
      } },
      UI.Row{ style = { justifyContent = "end", paddingRight = GUTTER, marginTop = 4 }, children = {
        UI.Button{ id = "n_ok", text = "OK", onClick = function()
          nwin:Hide()
          clearWindow()
        end },
      } },
    },
  }
end

-- "window": every notice gets its source's section in the one Notifications window (added to
-- what it already shows). True when the window is on screen.
N.DELIVERY.window = function(list)
  if not nwin then buildWindow() end
  for _, item in ipairs(list) do
    local id = "n_" .. item.source.key
    nwin:Find(id .. "_title"):SetText(item.notice.title or item.source.label)
    nwin:Find(id .. "_text"):SetText(item.notice.text)
    nwin:Find(id):SetVisible(true)
  end
  if nwin:IsShown() then return true end
  return nwin:Show() == true
end

function N.IsShown() return nwin ~= nil and nwin:IsShown() end

-- ---------------------------------------------------------------------------
-- The notification HUD (delivery "hud"): a Toolbox.Hud module
-- ---------------------------------------------------------------------------
-- A fixed pool of KEEP one-line labels in a Scroll LINES lines high, filled from `history`
-- (newest first) on every change: rows are never created per notice (element-creation cap;
-- no reorder API). A label that runs out of width ends in "..." by itself; its tooltip has the
-- whole notice. Shown when something arrives, hidden `hideAfter` seconds later (0 = never),
-- kept while the pointer is over it, and shown while settings are open so it can be placed.

local NH = {}
N.Hud = NH
NH.FRAME_ID = "toolbox_notify_hud"
NH.HOME = { 40, 120 }
NH.KEEP = 20              -- notices kept (and rows built)
NH.LINES = 5              -- lines shown; the rest scroll
NH.WIDTH = 320            -- pixels
NH.PAD = 4
-- Room left for the Scroll's vertical scrollbar: lines as wide as the Scroll overflowed sideways
-- and showed a horizontal scrollbar (reported 2026-09-28). The bar's width isn't documented.
NH.SCROLLBAR = 16
NH.EMPTY_TEXT = "Notifications will show here, newest on top."
NH.HIDE_CHOICES = { { 0, "Never" }, { 5, "5 seconds" }, { 10, "10 seconds" }, { 20, "20 seconds" },
                    { 30, "30 seconds" }, { 60, "1 minute" } }
NH.HIDE_DEFAULT = 10

local hprefs = { hideAfter = NH.HIDE_DEFAULT }
local history = {}        -- newest first: { when, title, text }
local hudRows = {}
local hudScroll = nil
local hudEmpty = nil
local visibleUntil = 0
local hovered = {}
local hudShown = nil      -- NH.IsShown() at the last check, to refresh the HUD when it changes

local function lineHeight() return T.Window.LineHeight() end

local function clockText()
  local osTable = rawget(_G, "os")
  local date = type(osTable) == "table" and osTable.date
  if type(date) ~= "function" then return "" end
  local ok, s = pcall(date, "%H:%M")
  return (ok and type(s) == "string") and s or ""
end

-- One notice's line and its tooltip.
function NH.Line(e)
  local when = e.when ~= "" and (e.when .. "  ") or ""
  return when .. e.title .. ": " .. e.text
end

function NH.Tooltip(e)
  return e.title .. (e.when ~= "" and (" (" .. e.when .. ")") or "") .. "\n" .. e.text
end

local function saveHistory() T.Save("notify_history", { v = 1, list = history }) end
local function saveHud() T.Save("notify_hud", hprefs) end

-- True when any source is delivered here (otherwise the HUD never shows, even in settings).
local function inUse()
  local p = nprefs
  if not p then return false end
  for _, sp in pairs(p.sources) do
    if sp.on and sp.via == "hud" then return true end
  end
  return false
end

function NH.IsShown()
  if not inUse() and #history == 0 then return false end
  if T.Config.IsShown() then return true end           -- to place it
  if #history == 0 then return false end
  if next(hovered) then return true end
  return hprefs.hideAfter == 0 or T.Now() < visibleUntil
end

-- Puts `history` into the rows (and the scroll's height to the lines used).
-- Lines the strip shows: the list (at most NH.LINES), or the one empty-state line.
local function shownLines() return math.max(1, math.min(#history, NH.LINES)) end

function NH.Fill()
  if not hudScroll then return end
  for i = 1, NH.KEEP do
    local e = history[i]
    local row = hudRows[i]
    if e then
      row:SetText(NH.Line(e))
      row:SetTooltip(NH.Tooltip(e))
    end
    row:SetVisible(e ~= nil)
  end
  local empty = #history == 0             -- only seen in settings, to place the strip
  hudEmpty:SetVisible(empty)
  hudScroll:SetVisible(not empty)
  hudScroll:SetStyle{ height = shownLines() * lineHeight() }
end

local function hover(k, over)
  if over then
    hovered[k] = true
  else
    hovered[k] = nil
    if not next(hovered) then visibleUntil = T.Now() + hprefs.hideAfter end   -- a fresh wait after
  end
end

-- For Toolbox.Hud: the strip was destroyed; the HUD's refresh skips it until BuildContent runs again.
function NH.Unbuilt()
  hudScroll, hudEmpty = nil, nil
  hudRows = {}
end

function NH.BuildContent()
  hudRows = {}
  local rows = {}
  for i = 1, NH.KEEP do
    hudRows[i] = UI.Label{ id = "nh_" .. i, text = "", class = "text", visible = false,
      style = T.Window.TextStyle{ width = NH.WIDTH - NH.SCROLLBAR, whiteSpace = "nowrap", marginLeft = 0,
                                  marginRight = 0 },
      onHover = function(_, over) hover("row" .. i, over) end }
    rows[i] = hudRows[i]
  end
  hudScroll = UI.Scroll{ id = "nh_scroll", style = { width = NH.WIDTH, height = lineHeight() },
    children = { UI.Column{ children = rows } } }
  hudEmpty = UI.Label{ id = "nh_empty", text = NH.EMPTY_TEXT, class = "dim", visible = false,
    style = T.Window.TextStyle{ width = NH.WIDTH, whiteSpace = "nowrap", marginLeft = 0, marginRight = 0 } }
  local content = UI.Column{ id = "nh_panel", style = { padding = NH.PAD, backgroundColor = "#00000099" },
    onHover = function(_, over) hover("panel", over) end, children = { hudEmpty, hudScroll } }
  NH.Fill()
  return content
end

function NH.ContentSize()
  return NH.WIDTH + 2 * NH.PAD, shownLines() * lineHeight() + 2 * NH.PAD
end

function NH.GetSavedPosition() return hprefs.x, hprefs.y end
function NH.SavePosition(x, y)
  if x ~= hprefs.x or y ~= hprefs.y then
    hprefs.x, hprefs.y = x, y
    saveHud()
  end
end

local hudMover = T.Hud.MoverFor("notify", NH.HOME)
NH.GetPosition, NH.MoveTo, NH.Nudge, NH.ResetPosition = hudMover.Get, hudMover.MoveTo, hudMover.Nudge, hudMover.Reset

-- Shows or hides the strip when that should change (from N.Check, every tick).
function NH.Tick()
  local shown = NH.IsShown()
  if shown ~= hudShown then
    hudShown = shown
    T.Hud.Refresh()
  end
end

-- "hud": each notice goes on top of the list; the HUD shows for hideAfter seconds.
-- "chat": each notice as a chat line, "Title: text". Always delivered.
N.DELIVERY.chat = function(list)
  for _, item in ipairs(list) do
    T.Print((item.notice.title or item.source.label) .. ": " .. item.notice.text)
  end
  return true
end

N.DELIVERY.hud = function(list)
  for _, item in ipairs(list) do
    table.insert(history, 1, { when = clockText(), title = item.notice.title or item.source.label,
                               text = item.notice.text })
  end
  for i = #history, NH.KEEP + 1, -1 do history[i] = nil end
  saveHistory()
  visibleUntil = T.Now() + hprefs.hideAfter
  NH.Fill()
  hudShown = nil                         -- refit and show now
  NH.Tick()
  return true
end

function NH.Init()
  local saved = T.Load("notify_hud")
  hprefs = { hideAfter = NH.HIDE_DEFAULT }
  if type(saved) == "table" then
    for _, c in ipairs(NH.HIDE_CHOICES) do if saved.hideAfter == c[1] then hprefs.hideAfter = c[1] end end
    if type(saved.x) == "number" and type(saved.y) == "number" then hprefs.x, hprefs.y = saved.x, saved.y end
  end
  history = {}
  local h = T.Load("notify_history")
  if type(h) == "table" and h.v == 1 and type(h.list) == "table" then
    for _, e in ipairs(h.list) do
      if type(e) == "table" and type(e.title) == "string" and type(e.text) == "string" and #history < NH.KEEP then
        history[#history + 1] = { when = type(e.when) == "string" and e.when or "", title = e.title, text = e.text }
      end
    end
  end
  visibleUntil, hovered, hudShown = 0, {}, nil
  T.Hud.Register("notify", NH)
end

function NH.GetHideAfter() return hprefs.hideAfter end

-- Seconds, one of NH.HIDE_CHOICES (0 = never). Returns false for anything else.
function NH.SetHideAfter(seconds)
  local ok = false
  for _, c in ipairs(NH.HIDE_CHOICES) do if c[1] == seconds then ok = true end end
  if not ok then return false end
  hprefs.hideAfter = seconds
  saveHud()
  NH.Tick()
  T.Config.Sync()
  return true
end

function NH.HideLabel(seconds)
  for _, c in ipairs(NH.HIDE_CHOICES) do if c[1] == seconds then return c[2] end end
  return nil
end

function NH.Clear()
  history = {}
  saveHistory()
  NH.Fill()
  hudShown = nil
  NH.Tick()
end

function NH.Count() return #history end

-- ---------------------------------------------------------------------------
-- Prefs and the check loop
-- ---------------------------------------------------------------------------

local nprefsFor = nil     -- the player name they were loaded for
local settleUntil = 0

local function save()
  T.Save("notify", nprefs)
  T.unflushed = true      -- written to disk with the session's periodic flush
end

local function prefsNow()
  local name = ShroudGetPlayerName()
  if nprefs ~= nil and nprefsFor == name then return nprefs end
  nprefsFor = name
  settleUntil = T.Now() + N.SETTLE
  local saved = T.Load("notify")
  local stored = type(saved) == "table" and saved.v == 1 and type(saved.sources) == "table" and saved.sources or {}
  if type(saved) ~= "table" then
    local old = T.Load("guild_motd")       -- before notifications, the guild message had its own
    if type(old) == "table" then
      stored = { motd = { on = old.show ~= false, seen = type(old.seen) == "string" and old.seen or "" } }
    end
  end
  nprefs = { v = 1, sources = {}, compact = type(saved) == "table" and saved.compact == true }
  for _, src in ipairs(N.SOURCES) do
    local s = type(stored[src.key]) == "table" and stored[src.key] or {}
    local sp = { on = src.default, via = src.via or N.DELIVERY_DEFAULT, sound = false, soundKey = "notify" }
    if type(s.on) == "boolean" then sp.on = s.on end
    if s.sound == true then sp.sound = true end
    if N.SoundLabel(s.soundKey) then sp.soundKey = s.soundKey end
    if type(s.via) == "string" and N.DELIVERY[s.via] then sp.via = s.via end
    if src.transient then
      sp.seen = nil                          -- event numbers restart with the add-on
    elseif type(s.seen) == "table" then
      sp.seen = plainStrings(s.seen)
    elseif s.seen ~= nil then
      sp.seen = s.seen
    end
    nprefs.sources[src.key] = sp
  end
  return nprefs
end

-- What the sources read this check, once. The guild message comes from its own getter when the client
-- has it (API 18: "" outside a guild), else from the social summary; `guildSocial` is reused (every tick).
local guildSocial = {}
local function context()
  local ctx = {}
  local ok, social = pcall(ShroudGetSocialSummary)
  if ok and type(social) == "table" then ctx.social = social end
  if type(ShroudGetGuildMotd) == "function" then
    local okMotd, motd = pcall(ShroudGetGuildMotd)
    if okMotd and type(motd) == "string" then
      guildSocial.guildMotd = motd
      guildSocial.inGuild = (ctx.social ~= nil and ctx.social.inGuild == true) or motd ~= ""
      guildSocial.guildName = ctx.social ~= nil and ctx.social.guildName or ""
      ctx.social = guildSocial
    end
  end
  local ok2, notes = pcall(ShroudGetNotifications)
  if ok2 and type(notes) == "table" then ctx.notes = notes end
  return ctx
end

-- Hands each delivery its notices; remembers them as seen once delivered. Returns true if any.
-- `withSound`: play the notification sound once if a delivered source asks for it.
local playList = {}              -- reused: the distinct sounds this check plays
local function deliver(byVia, withSound)
  local p, any = nprefs, false
  for i = #playList, 1, -1 do playList[i] = nil end
  for via, list in pairs(byVia) do
    local ok, done = pcall(N.DELIVERY[via], list)
    if ok and done then
      for _, item in ipairs(list) do
        local sp = p.sources[item.source.key]
        sp.seen = item.notice.seen
        if sp.sound then
          local key, dup = sp.soundKey or "notify", false
          for _, k in ipairs(playList) do if k == key then dup = true end end
          if not dup then playList[#playList + 1] = key end
        end
      end
      any = true
    end
  end
  if withSound then
    for _, key in ipairs(playList) do T.Sounds.Play(key) end
  end
  return any
end

function N.Check()
  local p = prefsNow()
  local ctx = context()
  local settling = T.Now() < settleUntil
  local byVia, changed = {}, false
  for _, src in ipairs(N.SOURCES) do
    local sp = p.sources[src.key]
    local ok, notice, quiet = pcall(src.Check, sp.seen, ctx)
    if ok and notice and sp.on then
      local via = N.DELIVERY[sp.via] and sp.via or N.DELIVERY_DEFAULT
      byVia[via] = byVia[via] or {}
      local list = byVia[via]
      list[#list + 1] = { source = src, notice = notice }
    elseif ok and notice then                  -- switched off: keep up quietly
      sp.seen, changed = notice.seen, true
    elseif ok and quiet ~= nil and not settling then
      sp.seen, changed = quiet, true
    end
  end
  if deliver(byVia, true) then changed = true end
  if changed then save() end
  NH.Tick()
end

-- Shows a source's current state (or every enabled one's), new or not. Returns how many showed.
function N.ShowCurrent(key)
  local p = prefsNow()
  local ctx = context()
  local byVia, n = {}, 0
  for _, src in ipairs(N.SOURCES) do
    if (key and src.key == key) or (not key and p.sources[src.key].on) then
      local ok, notice = pcall(src.Check, nil, ctx)
      if ok and notice then
        local via = p.sources[src.key].via
        byVia[via] = byVia[via] or {}
        local list = byVia[via]
        list[#list + 1] = { source = src, notice = notice }
        n = n + 1
      end
    end
  end
  if n > 0 then
    if deliver(byVia) then
      save()
    else
      T.Print("The notifications window can't open right now; try again in a few seconds.")
    end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function N.Sources() return N.SOURCES end

function N.Label(key)
  local src = sourceFor(key)
  return src and src.label or nil
end

function N.IsOn(key)
  local sp = prefsNow().sources[key]
  return sp ~= nil and sp.on == true
end

-- Returns false for an unknown key.
function N.SetOn(key, on)
  local sp = prefsNow().sources[key]
  if not sp then return false end
  sp.on = on == true
  save()
  T.Config.Sync()
  return true
end

-- The Notifications window as a compact window (API 19: its title bar shows only on hover) or a normal
-- one. A window's fields are fixed when it's made, so it is rebuilt, keeping what it shows.
function N.GetCompact() return prefsNow().compact == true end

function N.SetCompact(on)
  local p = prefsNow()
  on = on == true
  if on == (p.compact == true) then return end
  p.compact = on
  save()
  if nwin then
    local open = nwin:IsShown()
    local kept = {}
    for _, src in ipairs(N.SOURCES) do
      local sec = nwin:Find("n_" .. src.key)
      if sec and sec:IsVisible() then
        kept[#kept + 1] = { key = src.key, title = nwin:Find("n_" .. src.key .. "_title").text,
                            text = nwin:Find("n_" .. src.key .. "_text").text }
      end
    end
    pcall(function() nwin:Destroy() end)
    nwin = nil
    buildWindow()
    for _, k in ipairs(kept) do
      nwin:Find("n_" .. k.key .. "_title"):SetText(k.title)
      nwin:Find("n_" .. k.key .. "_text"):SetText(k.text)
      nwin:Find("n_" .. k.key):SetVisible(true)
    end
    if open then nwin:Show() end
  end
  T.Config.Sync()
end

-- The deliveries, in the order settings offer them: { name, label }.
N.VIAS = { { "window", "Window" }, { "hud", "HUD" }, { "chat", "Chat" } }
N.SOUND_SUFFIX = " + sound"

-- The settings dropdown's choices: each delivery, and each with the sound ("Window + sound").
function N.Choices()
  local out = {}
  for _, v in ipairs(N.VIAS) do
    out[#out + 1] = v[2]
    out[#out + 1] = v[2] .. N.SOUND_SUFFIX
  end
  return out
end

function N.ChoiceLabel(key)
  local label = N.ViaLabel(N.GetVia(key)) or N.VIAS[1][2]
  if N.GetSound(key) then label = label .. N.SOUND_SUFFIX end
  return label
end

-- A choice back to (via, sound), or nil for an unknown label.
function N.ParseChoice(label)
  if type(label) ~= "string" then return nil end
  local sound = label:sub(-#N.SOUND_SUFFIX) == N.SOUND_SUFFIX
  local base = sound and label:sub(1, #label - #N.SOUND_SUFFIX) or label
  for _, v in ipairs(N.VIAS) do
    if v[2] == base then return v[1], sound end
  end
  return nil
end

-- The sounds a notification can play, in the order settings offer them: { sound key, label }.
N.SOUNDS = { { "notify", "Chime" }, { "ping", "Ping" }, { "tap", "Tap" }, { "buff_expiring", "Bell" },
             { "debuff_landed", "Low notes" } }

function N.SoundLabel(soundKey)
  for _, s in ipairs(N.SOUNDS) do if s[1] == soundKey then return s[2] end end
  return nil
end

function N.SoundLabels()
  local out = {}
  for i, s in ipairs(N.SOUNDS) do out[i] = s[2] end
  return out
end

function N.GetSoundKey(key)
  local sp = prefsNow().sources[key]
  return sp and sp.soundKey or "notify"
end

-- Which sound a source plays (by N.SOUNDS key or label, any case). Returns false for an unknown one.
function N.SetSoundKey(key, which)
  local sp = prefsNow().sources[key]
  if not sp or type(which) ~= "string" then return false end
  local found = nil
  for _, s in ipairs(N.SOUNDS) do
    if s[1] == which or s[2]:lower() == which:lower() then found = s[1] end
  end
  if not found then return false end
  sp.soundKey = found
  save()
  T.Config.Sync()
  return true
end

function N.GetSound(key)
  local sp = prefsNow().sources[key]
  return sp ~= nil and sp.sound == true
end

-- Plays the notification sound with a source's notices, or not. Returns false for an unknown key.
function N.SetSound(key, on)
  local sp = prefsNow().sources[key]
  if not sp then return false end
  sp.sound = on == true
  save()
  T.Config.Sync()
  return true
end

function N.ViaLabel(via)
  for _, v in ipairs(N.VIAS) do if v[1] == via then return v[2] end end
  return nil
end

-- The delivery a source uses ("window" or "hud").
function N.GetVia(key)
  local sp = prefsNow().sources[key]
  return sp and sp.via or N.DELIVERY_DEFAULT
end

-- Sends a source's notices another way (a key from N.DELIVERY). Returns false if unknown.
function N.SetVia(key, via)
  local sp = prefsNow().sources[key]
  if not sp or not N.DELIVERY[via] then return false end
  sp.via = via
  save()
  NH.Tick()
  T.Config.Sync()
  return true
end
