-- Toolbox: docs.lua
-- The Docs window (/toolbox docs, or the Docs button in settings): getting started, each
-- feature and its main options, tips, and every chat command (listed from the same table the
-- commands are registered from, so it can't go out of date). Built on first open.

local T = Toolbox
local D = {}
Toolbox.Docs = D

local UI = Shroud.UI
local WINDOW_ID = "toolbox_docs"
local GUTTER = 10
local win = nil

-- { heading, paragraph, paragraph, ... }. Plain text: markup is never interpreted.
D.SECTIONS = {
  { "Getting started",
    "Type /toolbox (or /tbx) to open the settings window and tick what you want on screen. "
      .. "Everything is saved per character. /toolbox help opens this guide; /toolbox commands "
      .. "lists the commands in chat.",
    "Shortcut: Ctrl+; opens the settings (if the game isn't using it). Change it, or pick one, in the "
      .. "add-on manager on Toolbox's row under Keys. /toolbox key shows the current one." },
  { "XP",
    "XP (/toolbox xp): session time, your adventurer and producer pools, and the XP you earned "
      .. "in the last hour. Rest the pointer on it and XP Detailed pops up.",
    "XP Detailed (/toolbox xpdetailed): per track, XP gained, XP per hour (session and last "
      .. "10 minutes), level, progress, XP needed and time to the next level, and a Reset button. "
      .. "A session starts when you log in or press Reset, and survives /lua reload." },
  { "Today",
    "Today (/toolbox daily): gold picked up, kills by you or your pet, and adventurer and "
      .. "producer XP since midnight. Rest the pointer on it for Today Detailed: every item that "
      .. "arrived in your bags today, with counts." },
  { "Buff bar",
    "/toolbox buffs: your buffs and debuffs (outlined red) as their skill icons. A darkening "
      .. "sweep shows the time left; it turns red when a buff is about to run out. Hover an icon "
      .. "for its tooltip.",
    "Options: icon size; a sound before a buff runs out (/toolbox buffalert 10 = ten seconds "
      .. "before); a sound when a debuff lands (/toolbox debuffalert on/off)." },
  { "Health & focus bars",
    "/toolbox vitals: your health and focus with \"current / max\".",
    "Options: size (75-250%), bar length, show bars and/or numbers, a dark or light panel "
      .. "behind the numbers, and a flash when a value drops below a percentage (Test flash "
      .. "shows it). Glue to the buff bar joins them into one HUD." },
  { "Combat stats",
    "/toolbox combat: fight timer, DPS (last 5 seconds and fight average), damage taken and "
      .. "healing per second, crit % and avoided %, plus character stats you choose.",
    "Add a stat mid-fight: /toolbox stats resist finds names (any word: absorb, dodge, crit, "
      .. "regen...); /toolbox combat stat add CombatHealthRegen adds one; stat remove takes it "
      .. "off. Up to 8. /toolbox combat help has more." },
  { "Moving the HUD strips",
    "The buff bar, health & focus bars and combat stats are HUD strips. Drag the grip at a "
      .. "strip's top-left corner (untick Options > Interface > Nameplates & Chat Bubbles > "
      .. "Lock Status Movement to see it), use the Position buttons in settings, or type e.g. "
      .. "/toolbox buffs move 600 40." },
  { "Sounds",
    "The alert sounds live in the add-on's folder. To use your own, put "
      .. "toolbox_buff_expiring.ogg or toolbox_debuff_landed.ogg (or .wav) in your Lua folder, "
      .. "beside the toolbox folder, or pick any file in settings. /toolbox sounds shows what "
      .. "each alert uses; /toolbox sounds 50 sets the volume." },
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

local function build()
  local children = {}
  for _, section in ipairs(D.SECTIONS) do
    children[#children + 1] = heading(section[1])
    for i = 2, #section do children[#children + 1] = para(section[i]) end
  end
  children[#children + 1] = heading("Commands")
  children[#children + 1] = para("/" .. T.commands[1] .. " and /" .. T.commands[2] .. " do the same thing.")
  for _, line in ipairs(D.CommandLines()) do
    children[#children + 1] = UI.Label{ text = line, class = "dim", style = { whiteSpace = "wrap", marginTop = 2 } }
  end
  win = UI.Window{
    id = WINDOW_ID, title = "Toolbox Docs",
    width = 460, height = 520, minWidth = 300, minHeight = 200,
    x = T.Window.DEFAULT_X, y = T.Window.DEFAULT_Y,
    escCloses = true,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = { UI.Scroll{ style = { flexGrow = 1 }, children = {
      UI.Column{ id = "docs_body", style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = children },
    } } },
  }
end

function D.IsShown()
  return win ~= nil and win:IsShown()
end

function D.Toggle()
  if not win then build() end
  if win:IsShown() then
    win:Hide()
  elseif not win:Show() then
    T.Print("The Docs window can't reopen right now; try again in a few seconds.")
  end
end

function D.Open()
  if not win then build() end
  if not win:IsShown() and not win:Show() then
    T.Print("The Docs window can't reopen right now; try again in a few seconds.")
  end
end
