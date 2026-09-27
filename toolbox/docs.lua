-- Toolbox: docs.lua
-- The Docs window (/toolbox docs, or the Docs button in settings): getting started, each
-- feature and its main options, tips, and every chat command (listed from the same table the
-- commands are registered from, so it can't go out of date). Built on first open.
--
-- Also the version window (/toolbox version): the version line and the changelog, which
-- tools/build.py bakes into changelog.lua (Toolbox.CHANGELOG) from CHANGELOG.md.
--
-- And the guild message of the day window (Toolbox.Motd, at the end), shown when it changes.

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
    "Shortcut: Ctrl+Shift+; opens the settings (if the game isn't using it). Change it, or pick one, in the "
      .. "add-on manager on Toolbox's row under Keys. /toolbox key shows the current one." },
  { "XP",
    "XP (/toolbox xp): session time, your adventurer and producer pools, and the XP you earned "
      .. "in the last hour. Rest the pointer on it and XP Detailed pops up.",
    "XP Detailed (/toolbox xpdetailed): per track, XP gained, XP per hour (session and last "
      .. "10 minutes), level, progress, XP needed and time to the next level, and a Reset button. "
      .. "A session starts when you log in or press Reset, and survives /lua reload.",
    "Smaller: /toolbox xp hud (or \"As a HUD strip\" in settings) shows the XP window as a HUD strip, "
      .. "with no title bar or frame. Move it by its grip or /toolbox xp move <x> <y>; hovering still "
      .. "pops up XP Detailed. /toolbox xp window turns it back into a window." },
  { "Today",
    "Today (/toolbox daily): gold picked up, kills by you or your pet, and adventurer and "
      .. "producer XP since midnight. Rest the pointer on it for Today Detailed: every item that "
      .. "arrived in your bags today, with counts.",
    "Like XP, it can be a HUD strip: /toolbox daily hud (and daily window, daily move <x> <y>)." },
  { "Buff bar",
    "/toolbox buffs: your buffs and debuffs (outlined red) as their skill icons. A darkening "
      .. "sweep shows the time left; it turns red when a buff is about to run out. Hover an icon "
      .. "for its tooltip.",
    "Options: icon size; a sound before a buff runs out (/toolbox buffalert 10 = ten seconds "
      .. "before); a sound when a debuff lands (/toolbox debuffalert on/off).",
    "Long-lasting buffs (the Obsidian potions, BlessingOf...) share one slot at the end of the row, showing how "
      .. "many there are; hover it for each one and its time left. They're picked by name: "
      .. "/toolbox buffs group add <part of a name> adds more, remove takes one off, and "
      .. "/toolbox buffs group lists them." },
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
  { "Guild message of the day",
    "When your guild's message of the day has changed since you last saw it, a window shows it: at "
      .. "login, after /lua reload, or when an officer changes it while you play. An unchanged message "
      .. "doesn't show again. /toolbox motd shows it any time; /toolbox motd off (or the Guild setting) "
      .. "stops it opening by itself." },
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
    children[#children + 1] = para(line)    -- same colour as the rest (dim was hard to read)
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

-- ---------------------------------------------------------------------------
-- Version window
-- ---------------------------------------------------------------------------

local VERSION_ID = "toolbox_version"
local vwin = nil

-- Labels for the changelog entries ({ kind, text }; see changelog.lua).
function D.ChangelogLabels()
  local out = {}
  for _, entry in ipairs(T.CHANGELOG or {}) do
    local kind, text = entry[1], entry[2]
    if kind == "version" then
      if text == "Unreleased" then text = "Unreleased (newer than " .. T.version .. ")" end
      out[#out + 1] = UI.Label{ text = text, class = "heading", style = { marginTop = 10 } }
    elseif kind == "section" then
      out[#out + 1] = UI.Label{ text = text, class = "bright", style = { marginTop = 4 } }
    elseif kind == "item" then
      out[#out + 1] = UI.Label{ text = "- " .. text, class = "text",
        style = { whiteSpace = "wrap", marginTop = 2, paddingLeft = 8 } }
    else
      out[#out + 1] = para(text)
    end
  end
  return out
end

local function buildVersion()
  local children = {
    UI.Label{ id = "version_line", text = T.VersionLine(), class = "text", style = { whiteSpace = "wrap" } },
  }
  for _, label in ipairs(D.ChangelogLabels()) do children[#children + 1] = label end
  vwin = UI.Window{
    id = VERSION_ID, title = "Toolbox " .. T.version,
    width = 460, height = 480, minWidth = 300, minHeight = 160,
    x = T.Window.DEFAULT_X, y = T.Window.DEFAULT_Y,
    escCloses = true,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = { UI.Scroll{ style = { flexGrow = 1 }, children = {
      UI.Column{ id = "version_body", style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = children },
    } } },
  }
end

-- Opens the version window (leaves it open if it already is), with the version line current.
function D.OpenVersion()
  if not vwin then buildVersion() end
  vwin:Find("version_line"):SetText(T.VersionLine())
  if not vwin:IsShown() and not vwin:Show() then
    T.Print("The version window can't reopen right now; try again in a few seconds.")
  end
end

function D.IsVersionShown()
  return vwin ~= nil and vwin:IsShown()
end

-- ---------------------------------------------------------------------------
-- Guild message of the day (Toolbox.Motd)
-- ---------------------------------------------------------------------------
-- Opens a window with the guild's message of the day when it differs from the last one this
-- character was shown: at login, after a reload, or when it changes while playing. The text
-- is ShroudGetSocialSummary().guildMotd (API 14). The guild data may arrive after login, so
-- a missing or empty message is never "new"; it is simply checked again next tick. A message
-- counts as seen once its window has actually opened (Show can be refused).
-- Saved var "guild_motd" (character scope): { show = bool, seen = "text" }.

local M = {}
Toolbox.Motd = M

local MOTD_ID = "toolbox_motd"
local mwin = nil
local mprefs = nil        -- this character's prefs (the saved-var scope follows the character)
local mprefsFor = nil     -- the player name mprefs were loaded for

-- The message to show, or nil: in a guild, not empty, and not the one already seen.
-- Leading and trailing spaces don't count as a change.
function M.NewMessage(summary, seen)
  if type(summary) ~= "table" or summary.inGuild ~= true then return nil end
  if type(summary.guildMotd) ~= "string" then return nil end
  local text = summary.guildMotd:match("^%s*(.-)%s*$")
  if text == "" or text == seen then return nil end
  return text
end

local function prefsNow()
  local name = ShroudGetPlayerName()
  if mprefs == nil or mprefsFor ~= name then
    local saved = T.Load("guild_motd")
    mprefs = { show = true, seen = "" }
    if type(saved) == "table" then
      if type(saved.show) == "boolean" then mprefs.show = saved.show end
      if type(saved.seen) == "string" then mprefs.seen = saved.seen end
    end
    mprefsFor = name
  end
  return mprefs
end

local function saveMotd()
  T.Save("guild_motd", mprefs)
  T.unflushed = true          -- written to disk with the session's periodic flush
end

local function summaryNow()
  local ok, summary = pcall(ShroudGetSocialSummary)
  if ok and type(summary) == "table" then return summary end
  return nil
end

local function buildMotd()
  mwin = UI.Window{
    id = MOTD_ID, title = "Guild message of the day",
    width = 380, height = 220, minWidth = 220, minHeight = 120,
    x = T.Window.DEFAULT_X, y = T.Window.DEFAULT_Y,
    escCloses = true,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = {
      UI.Scroll{ style = { flexGrow = 1 }, children = {
        UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = {
          UI.Label{ id = "motd_guild", text = "", class = "heading" },
          UI.Label{ id = "motd_text", text = "", class = "text", style = { whiteSpace = "wrap", marginTop = 4 } },
        } },
      } },
      UI.Row{ style = { justifyContent = "end", paddingRight = GUTTER, marginTop = 4 }, children = {
        UI.Button{ id = "motd_ok", text = "OK", onClick = function() mwin:Hide() end },
      } },
    },
  }
end

-- Shows the window with this text. Returns true when it is on screen.
function M.Show(text, guildName)
  if not mwin then buildMotd() end
  mwin:Find("motd_guild"):SetText(type(guildName) == "string" and guildName or "")
  mwin:Find("motd_text"):SetText(text)
  if mwin:IsShown() then return true end
  return mwin:Show() == true
end

function M.IsShown()
  return mwin ~= nil and mwin:IsShown()
end

-- Called from ShroudOnStart, every tick and ShroudOnSocialChanged: opens the window when
-- the message is new to this character.
function M.Check()
  local p = prefsNow()
  if not p.show then return end
  local summary = summaryNow()
  local text = M.NewMessage(summary, p.seen)
  if not text then return end
  if M.Show(text, summary.guildName) then
    p.seen = text
    saveMotd()
  end
end

-- /toolbox motd: the current message, whether or not it's new.
function M.OpenCurrent()
  local summary = summaryNow()
  if not summary or summary.inGuild ~= true then
    T.Print("You're not in a guild.")
    return
  end
  local text = M.NewMessage(summary, nil)
  if not text then
    T.Print("Your guild has no message of the day (or it hasn't loaded yet).")
    return
  end
  if M.Show(text, summary.guildName) then
    local p = prefsNow()
    p.seen = text
    saveMotd()
  else
    T.Print("The guild message window can't open right now; try again in a few seconds.")
  end
end

function M.GetShow() return prefsNow().show end

function M.SetShow(on)
  prefsNow().show = on == true
  saveMotd()
  T.Config.Sync()
end
