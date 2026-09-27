-- Toolbox: core.lua
-- Namespace, chat output, saved-variable helpers, slash commands and callback wiring.
-- Loaded first (see manifest.json). Later files add Toolbox.XP, Toolbox.Window,
-- Toolbox.Hover, Toolbox.Compact, Toolbox.Daily, Toolbox.DailyDetail, Toolbox.Sounds,
-- Toolbox.BuffBar and Toolbox.Config.

Toolbox = {
  name = "Toolbox",
  version = "0.1.0",
  commands = { "toolbox", "tbx" },
  tickSeconds = 1.0,     -- periodic refresh; nothing runs per frame
  flushSeconds = 30,     -- how often a changed session is flushed to disk
}

local T = Toolbox
local SCOPE = "character"
local PERIODIC = "toolbox_tick"

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

function T.Print(msg)
  -- ShroudConsoleLog already prefixes "[Add-on: Toolbox]".
  ShroudConsoleLog(tostring(msg))
end

-- Engine time in seconds (Unity Time.time). Continuous across /lua reload,
-- restarts from 0 when the client restarts.
function T.Now()
  return ShroudTime or 0
end

-- Today's date for the daily reset: returns key, label, source.
--   source "local": the local calendar date from os.date, which the SotA docs don't
--                   document, so it is feature-detected on every call;
--   source "utc":   the date part of ShroudServerTime ("server UTC time, formatted as
--                   a string"; the format isn't documented, so the time of day is
--                   stripped and whatever date text remains is used as the key);
--   nil:            no usable clock.
function T.Today()
  local osTable = rawget(_G, "os")
  local date = type(osTable) == "table" and osTable.date
  if type(date) == "function" then
    local ok, d = pcall(date, "%Y-%m-%d")
    if ok and type(d) == "string" and d:match("^%d%d%d%d%-%d%d%-%d%d$") then
      return "local:" .. d, d, "local"
    end
  end
  local server = ShroudServerTime
  if type(server) == "string" then
    local datePart = server:gsub("%d%d?:%d%d:?%d?%d?%.?%d*%s*[AaPp]?%.?[Mm]?%.?", "")
    datePart = datePart:gsub("UTC", ""):gsub("[Zz]%s*$", ""):gsub("[Tt]%s*$", ""):match("^%s*(.-)[%s,]*$")
    if datePart:find("%d") then return "utc:" .. datePart, datePart .. " UTC", "utc" end
  end
  return nil
end

-- Deep copy of plain data (tables, strings, numbers, booleans). Used so the
-- live session never aliases the saved-variable cache.
function T.Copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = T.Copy(x) end
  return out
end

function T.Load(key)
  return T.Copy(ShroudGetSavedVar(key, SCOPE))
end

function T.Save(key, value)
  local ok = ShroudSetSavedVar(key, T.Copy(value), SCOPE)
  if not ok then T.Print("Could not save '" .. key .. "'.") end
  return ok
end

function T.Flush()
  return ShroudFlushSavedVars()
end

-- 1234567 -> "1,234,567" (rounded to a whole number).
function T.FormatNumber(n)
  n = math.floor((n or 0) + 0.5)
  local s = string.format("%d", math.abs(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  if n < 0 then out = "-" .. out end
  return out
end

-- Seconds -> "1h 02m 03s" / "4m 05s" / "7s".
function T.FormatDuration(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then return string.format("%dh %02dm %02ds", h, m, s) end
  if m > 0 then return string.format("%dm %02ds", m, s) end
  return string.format("%ds", s)
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local handlers = {}
local order = {}

-- aliases: other names that run the same command (shown in help after the name).
local function add(name, help, fn, aliases)
  handlers[name] = fn
  for _, alias in ipairs(aliases or {}) do handlers[alias] = fn end
  order[#order + 1] = { name = name, help = help, aliases = aliases }
end

add("help", "list commands", function()
  T.Print("Commands (/" .. table.concat(T.commands, " or /") .. "):")
  for _, c in ipairs(order) do
    local also = c.aliases and (" (or " .. table.concat(c.aliases, ", ") .. ")") or ""
    T.Print("  /" .. T.commands[1] .. " " .. c.name .. also .. " - " .. c.help)
  end
end)

add("xp", "show or hide the XP window (session time, pools, XP in the last hour)", function()
  T.Compact.Toggle()
end)

add("xpdetailed", "show or hide the XP Detailed window (levels, rates, Reset)", function()
  T.Window.Toggle()
end, { "xpd" })

add("daily", "show or hide today's stats (gold, kills, XP; resets at midnight)", function()
  T.Daily.Toggle()
end)

add("dailydetailed", "show or hide Today Detailed (every item gained today, with counts)", function()
  T.DailyDetail.Toggle()
end, { "dd" })

add("config", "open or close the settings window", function()
  T.Config.Toggle()
end)

add("reset", "start a new XP session", function()
  if T.StartSession("reset") then
    T.Print("New XP session started.")
  else
    T.Print("No character data yet; try again once you are in the world.")
  end
end)

add("font", "set the window text size, 9-32 (no number: show the current size)", function(rest)
  if rest == "" then
    T.Print("Window text size is " .. T.Window.GetFont() .. ". Use /" .. T.commands[1] .. " font <9-32>.")
  elseif T.Window.SetFont(tonumber(rest)) then
    T.Print("Window text size set to " .. T.Window.GetFont() .. ".")
  else
    T.Print("Text size must be a whole number from 9 to 32.")
  end
end)

-- "Line spacing is 2: lines should be 16 px; in XP they measure 16 px."
local function spacingReport(prefix)
  local W = T.Window
  local msg = prefix .. " " .. W.GetSpacing() .. ": lines should be " .. W.LineHeight() .. " px"
  local measured, where = W.MeasureLine()
  if measured then
    msg = msg .. "; in " .. where .. " they measure " .. measured .. " px"
    if measured ~= W.LineHeight() then msg = msg .. " (the game is not applying the height)" end
  else
    msg = msg .. " (open a window to measure)"
  end
  return msg .. "."
end

add("spacing", "set the extra space between lines, 0-12 (no number: show and measure it)", function(rest)
  if rest == "" then
    T.Print(spacingReport("Line spacing is") .. " Use /" .. T.commands[1] .. " spacing <0-12>.")
  elseif T.Window.SetSpacing(tonumber(rest)) then
    -- Not measured here: the game lays the change out on the next frame.
    T.Print("Line spacing set to " .. T.Window.GetSpacing() .. " (lines " .. T.Window.LineHeight()
      .. " px). Type /" .. T.commands[1] .. " spacing to measure.")
  else
    T.Print("Line spacing must be a whole number from 0 to 12.")
  end
end)

add("buffs", "show or hide the buff bar", function()
  T.BuffBar.Toggle()
end)

add("buffalert", "sound N seconds before a buff runs out, 1-60 (on / off; no argument: show)", function(rest)
  local B, word = T.BuffBar, rest:lower()
  if word == "on" or word == "off" then
    B.SetExpireAlert(word == "on")
  elseif word ~= "" and not B.SetExpireSeconds(tonumber(word)) then
    T.Print("Use a whole number of seconds from " .. B.ALERT_MIN .. " to " .. B.ALERT_MAX .. ", or on / off.")
    return
  elseif word ~= "" then
    B.SetExpireAlert(true)
  end
  local state = B.GetExpireAlert() and ("on, " .. B.GetExpireSeconds() .. " s before") or "off"
  T.Print("Buff expiring alert: " .. state .. ".")
end)

add("debuffalert", "sound when a debuff lands (on / off; no argument: show)", function(rest)
  local B, word = T.BuffBar, rest:lower()
  if word == "on" or word == "off" then B.SetDebuffAlert(word == "on")
  elseif word ~= "" then T.Print("Use on or off.") return end
  T.Print("Debuff alert: " .. (B.GetDebuffAlert() and "on" or "off") .. ".")
end)

add("sounds", "show which sound files the alerts use; /toolbox sounds <0-100> sets the volume", function(rest)
  if rest ~= "" and not T.Sounds.SetVolume(tonumber(rest)) then
    T.Print("Volume must be a whole number from 0 to 100.")
    return
  end
  for _, line in ipairs(T.Sounds.Report()) do T.Print(line) end
end)

-- Parses "  XP  extra " -> "xp", "extra".
function T.ParseArgs(args)
  args = tostring(args or "")
  local word, rest = args:match("^%s*(%S*)%s*(.-)%s*$")
  return (word or ""):lower(), rest or ""
end

function T.Dispatch(args)
  local word, rest = T.ParseArgs(args)
  if word == "" then word = "help" end
  local fn = handlers[word]
  if not fn then
    T.Print("Unknown command '" .. word .. "'. Try /" .. T.commands[1] .. " help.")
    return false
  end
  fn(rest)
  return true
end

function T.RegisterCommands()
  if not ShroudLuaApiVersion or ShroudLuaApiVersion < 14 then
    T.Print("Slash commands need Lua API 14; this client has " .. tostring(ShroudLuaApiVersion) .. ".")
    return
  end
  for _, name in ipairs(T.commands) do
    local ok, reason = Shroud.Command{
      name = name,
      help = "Toolbox: session XP and more. /" .. name .. " help lists commands.",
      run = T.Dispatch,
    }
    if not ok then
      T.Print("Could not register /" .. name .. ": " .. tostring(reason))
    end
  end
end

-- ---------------------------------------------------------------------------
-- Session lifecycle
-- ---------------------------------------------------------------------------

T.session = nil       -- live session table (see xp.lua), nil until character data exists
T.lastFlush = 0       -- T.Now() of the last flush of a session save
T.unsaved = false     -- session changed since it was last stored in saved vars
T.unflushed = false   -- session stored but not yet written to disk

-- Reads the character's totals, or nil when there is no character yet.
-- ShroudGetLevelProgress returns nil without a character; the total getters
-- return 0 in that case, which would look like a real reading.
function T.ReadTotals()
  if not ShroudGetLevelProgress() then return nil end
  local adv = ShroudGetTotalAdventurerExperience()
  local prod = ShroudGetTotalProducerExperience()
  if type(adv) ~= "number" or type(prod) ~= "number" or adv < 0 or prod < 0 then return nil end
  return adv, prod
end

function T.SaveSession(flush)
  if not T.session then return end
  T.session.clock = T.Now()
  T.Save("session", T.session)
  T.unsaved = false
  if flush then
    T.Flush()
    T.lastFlush = T.Now()
    T.unflushed = false
  else
    T.unflushed = true
  end
end

-- Starts a fresh session from the current totals. Returns false when there is
-- no character data to baseline against.
function T.StartSession(why)
  local adv, prod = T.ReadTotals()
  if not adv then return false end
  T.session = T.XP.NewSession(T.Now(), adv, prod, ShroudGetPlayerName())
  T.session.reason = why
  if why ~= "reset" then T.Daily.OnLogin(adv, prod) end
  T.SaveSession(true)
  T.RefreshViews()
  return true
end

-- Resume the saved session if it belongs to this client run and this character,
-- otherwise start a new one. See README "Sessions" for the rules.
function T.ResumeOrStart()
  if not T.ReadTotals() then return "waiting" end
  local saved = T.Load("session")
  local now = T.Now()
  if T.XP.IsValid(saved)
      and not saved.ended
      and saved.clock <= now                       -- clock went backwards: client restarted
      and saved.player == ShroudGetPlayerName() then
    T.session = saved
    return "resumed"
  end
  if T.StartSession("start") then return "started" end
  return "waiting"
end

-- Takes one reading of the totals into the session.
function T.Sample()
  local adv, prod = T.ReadTotals()
  if not adv then return end
  T.Daily.ObserveTotals(adv, prod)
  if not T.session or T.session.ended then return end
  if T.XP.Record(T.session, T.Now(), adv, prod) then T.unsaved = true end
end

-- Every window that shows session data.
function T.RefreshViews()
  T.Window.Refresh()
  T.Compact.Refresh()
  T.Daily.Refresh()
  T.DailyDetail.Refresh()
end

function T.Tick()
  local s = T.session
  if not s then
    T.ResumeOrStart()                -- no character yet when the add-on started
  elseif s.ended then
    T.StartSession("login")          -- logged out and back in without a restart
  elseif s.player ~= ShroudGetPlayerName() and T.ReadTotals() then
    T.StartSession("character")
  else
    T.Sample()
  end
  T.Daily.Tick(T.ReadTotals() ~= nil)
  T.Window.Track()
  T.Compact.Track()
  T.Daily.Track()
  T.DailyDetail.Track()
  -- Store a changed session once a tick (in memory; copying up to an hour of
  -- samples per XP event would be wasteful), and write it to disk at most
  -- every flushSeconds. A reload re-reads the totals, so it loses no XP.
  if T.unsaved then T.SaveSession(false) end
  if T.unflushed and T.Now() - T.lastFlush >= T.flushSeconds then
    T.Flush()
    T.lastFlush = T.Now()
    T.unflushed = false
  end
  T.Sounds.Poll()
  T.Config.SyncSounds()
  T.RefreshViews()
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

function ShroudOnStart()
  T.RegisterCommands()
  T.Daily.Load()                     -- before the session: a new login re-bases daily gold
  T.ResumeOrStart()
  T.Sample()                         -- XP gained since the last save (e.g. across a reload)
  T.Window.Init()
  T.Compact.Init()
  T.Daily.InitWindow()
  T.DailyDetail.Init()
  T.Sounds.Init()
  T.BuffBar.Init()
  ShroudRegisterPeriodic(PERIODIC, T.Tick, T.tickSeconds, true)
end

-- Only a trigger: the amount's relation to pooled vs total XP is not documented,
-- so the totals are re-read instead of summing `amount`.
function ShroudOnExperienceGain(_, _)
  T.Sample()
end

-- Kills for the daily stats (combat chat lines about you, your party or your pet).
function ShroudOnCombatEvents(events, _)
  T.Daily.OnCombat(events)
end

-- Buff bar and the debuff alert.
function ShroudOnBuffsChanged()
  T.BuffBar.OnBuffsChanged()
end

-- A scene change rebuilds the buff list: don't alert for debuffs that were already there.
function ShroudOnSceneUnloaded()
  T.BuffBar.Quiet()
end

function ShroudOnSceneLoaded(_)
  T.BuffBar.Quiet()
end

-- Items for the daily stats (anything that arrives in your bags).
function ShroudOnItemsGained(items, dropped)
  T.Daily.OnItems(items, dropped)
end

function ShroudOnLogOut()
  if T.session then
    T.Sample()
    T.session.ended = true
    T.SaveSession(false)
  end
  T.Daily.Save()
  T.Window.SavePrefs()
  T.Compact.SavePrefs()
  T.Daily.SavePrefs()
  T.DailyDetail.SavePrefs()
  T.Flush()
end

function ShroudOnDisableScript()
  -- Not marked ended: it is not documented whether /lua reload goes through here.
  if T.session then T.SaveSession(false) end
  T.Daily.Save()
  T.Window.SavePrefs()
  T.Compact.SavePrefs()
  T.Daily.SavePrefs()
  T.DailyDetail.SavePrefs()
  T.Flush()
end
