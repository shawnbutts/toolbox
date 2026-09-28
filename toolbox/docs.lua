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
    "Estimated values (optional): switch on Estimated values (SOTA.net) in settings, or /toolbox dd "
      .. "values on, and switch Internet on for Toolbox in the add-on manager. Today Detailed then shows "
      .. "each item's count times its 90-day average sale price from shroudoftheavatar.net (player-"
      .. "uploaded receipts) and a total; hover a value for the price each. Items with no recent sales "
      .. "stay blank. Only item names are sent, and each price is kept for 24 hours; /toolbox dd values "
      .. "refresh looks them up again, and /toolbox dd values test [item] checks the connection.",
    "Like XP, it can be a HUD strip: /toolbox daily hud (and daily window, daily move <x> <y>)." },
  { "Buff bar",
    "/toolbox buffs: your buffs and debuffs (outlined red) as their skill icons, the one that runs out "
      .. "soonest on the left. A darkening "
      .. "sweep shows the time left; it turns red when a buff is about to run out. Hover an icon "
      .. "for its tooltip.",
    "Options: icon size; a sound before a buff runs out (/toolbox buffalert 10 = ten seconds "
      .. "before); a sound when a debuff lands (/toolbox debuffalert on/off).",
    "Buffs with more than 15 minutes left (Obsidian potions, for example) share one slot at the end of "
      .. "the row, showing how many there are; hover it for each one and its time left. A buff moves back "
      .. "onto the bar once it has less than that left. Change the time in settings (Group buffs lasting "
      .. "longer than) or with /toolbox buffs group after 30 (minutes; off turns it off). To always group "
      .. "a buff, add part of its name: /toolbox buffs group add <name> (remove <name> takes it off; "
      .. "/toolbox buffs debug shows buffs' names).",
    "Only during combat (settings, or /toolbox buffs combat on|off) shows the bar only while you're "
      .. "in combat and for a few seconds after, so it can sit in your line of sight without being in "
      .. "the way. It also shows while the settings window is open, so you can place it.",
    "Two settings on newer game clients: Replace the game's buff bar hides the game's own bar while "
      .. "this one is showing (it comes back whenever this one is off), and Click a buff to dismiss it "
      .. "works like the game's right-click Dismiss. Chat: /toolbox buffs replace on|off, "
      .. "/toolbox buffs dismiss on|off." },
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
  { "Notifications",
    "A Notifications window tells you what's new since you last saw it: your guild's message of the "
      .. "day, new mail, mail about to expire, ransoms, new rewards and guild applications. It opens at "
      .. "login, after /lua reload, or as soon as something changes, and shows everything new together. "
      .. "Nothing already seen shows again.",
    "Switch each one on or off in settings (Notifications), or with /toolbox notify <name> on|off "
      .. "(names: motd, mail, expiring, ransoms, rewards, applications). /toolbox notify lists them; "
      .. "/toolbox notify show shows everything current; /toolbox motd shows the guild message." },
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
-- Notifications (Toolbox.Notify)
-- ---------------------------------------------------------------------------
-- Tells the player about what's new since they last saw it: the guild message of the day, new
-- mail, mail about to expire, ransoms, new rewards, guild applications (all API 14). Three
-- parts, kept apart so each can grow on its own:
--   * N.SOURCES, one entry per kind: key (chat and saved-var name), label, tip, default, and
--     Check(seen, ctx) -> notice or nil, plus an optional second value to remember quietly
--     (a count going down: nothing to say). A notice is { title?, text, seen = what to remember
--     once it has been delivered }. ctx holds this check's game reads (social, notes).
--   * N.DELIVERY, how notices reach the player, by name: "window" for now. Each source has a
--     `via` pref naming one; a chat line, a sound or another kind of window is a new entry here
--     plus a control in settings, with no change to the sources.
--   * N.Check (every tick, ShroudOnStart, and the game's social / notification callbacks): per
--     source, compare with what it last saw, gather new notices by delivery, deliver them, and
--     remember them as seen only once delivered (a window's Show can be refused: it is simply
--     tried again next tick). Sources switched off are tracked quietly, so switching one on
--     doesn't bring up old news. For N.SETTLE seconds after start or a character change, counts
--     going down are not remembered: at login they read 0 until the game has loaded them.
-- Saved var "notify" (character scope): { v = 1, sources = { [key] = { on = bool, seen = any,
-- via = "window" } } }. The older "guild_motd" ({ show, seen }) is taken over once.

local N = {}
Toolbox.Notify = N

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
  local text = summary.guildMotd:match("^%s*(.-)%s*$")
  if text == "" or text == seen then return nil end
  return text
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
  nwin = UI.Window{
    id = N.WINDOW_ID, title = "Notifications",
    width = 380, height = 240, minWidth = 220, minHeight = 120,
    x = T.Window.DEFAULT_X, y = T.Window.DEFAULT_Y,
    escCloses = true,
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
-- Prefs and the check loop
-- ---------------------------------------------------------------------------

local nprefs = nil        -- this character's prefs (the saved-var scope follows the character)
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
  nprefs = { v = 1, sources = {} }
  for _, src in ipairs(N.SOURCES) do
    local s = type(stored[src.key]) == "table" and stored[src.key] or {}
    local sp = { on = src.default, via = N.DELIVERY_DEFAULT }
    if type(s.on) == "boolean" then sp.on = s.on end
    if type(s.via) == "string" and N.DELIVERY[s.via] then sp.via = s.via end
    if s.seen ~= nil and type(s.seen) ~= "table" then sp.seen = s.seen end
    nprefs.sources[src.key] = sp
  end
  return nprefs
end

-- What the sources read this check, once.
local function context()
  local ctx = {}
  local ok, social = pcall(ShroudGetSocialSummary)
  if ok and type(social) == "table" then ctx.social = social end
  local ok2, notes = pcall(ShroudGetNotifications)
  if ok2 and type(notes) == "table" then ctx.notes = notes end
  return ctx
end

-- Hands each delivery its notices; remembers them as seen once delivered. Returns true if any.
local function deliver(byVia)
  local p, any = nprefs, false
  for via, list in pairs(byVia) do
    local ok, done = pcall(N.DELIVERY[via], list)
    if ok and done then
      for _, item in ipairs(list) do p.sources[item.source.key].seen = item.notice.seen end
      any = true
    end
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
  if deliver(byVia) then changed = true end
  if changed then save() end
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

-- The delivery a source uses ("window"); for settings to offer choices once there are several.
function N.GetVia(key)
  local sp = prefsNow().sources[key]
  return sp and sp.via or N.DELIVERY_DEFAULT
end
