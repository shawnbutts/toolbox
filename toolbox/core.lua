-- Toolbox: core.lua
-- Namespace, chat output, saved-variable helpers, slash commands and callback wiring.
-- Loaded first (see manifest.json). Later files add Toolbox.XP and Toolbox.Window.

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

local function add(name, help, fn)
  handlers[name] = fn
  order[#order + 1] = { name = name, help = help }
end

add("help", "list commands", function()
  T.Print("Commands (/" .. table.concat(T.commands, " or /") .. "):")
  for _, c in ipairs(order) do
    T.Print("  /" .. T.commands[1] .. " " .. c.name .. " - " .. c.help)
  end
end)

add("xp", "show or hide the Session XP window", function()
  T.Window.Toggle()
end)

add("reset", "start a new XP session", function()
  if T.StartSession("reset") then
    T.Print("New XP session started.")
  else
    T.Print("No character data yet; try again once you are in the world.")
  end
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
  T.SaveSession(true)
  T.Window.Refresh()
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
  if not T.session or T.session.ended then return end
  local adv, prod = T.ReadTotals()
  if not adv then return end
  -- Store every change (in memory, cheap) so a reload loses nothing.
  if T.XP.Record(T.session, T.Now(), adv, prod) then T.SaveSession(false) end
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
  T.Window.Track()
  -- Write a changed session to disk at most every flushSeconds.
  if T.unflushed and T.Now() - T.lastFlush >= T.flushSeconds then
    T.Flush()
    T.lastFlush = T.Now()
    T.unflushed = false
  end
  T.Window.Refresh()
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

function ShroudOnStart()
  T.RegisterCommands()
  T.ResumeOrStart()
  T.Window.Init()
  ShroudRegisterPeriodic(PERIODIC, T.Tick, T.tickSeconds, true)
end

-- Only a trigger: the amount's relation to pooled vs total XP is not documented,
-- so the totals are re-read instead of summing `amount`.
function ShroudOnExperienceGain(_, _)
  T.Sample()
end

function ShroudOnLogOut()
  if T.session then
    T.Sample()
    T.session.ended = true
    T.SaveSession(false)
  end
  T.Window.SavePrefs()
  T.Flush()
end

function ShroudOnDisableScript()
  -- Not marked ended: it is not documented whether /lua reload goes through here.
  if T.session then T.SaveSession(false) end
  T.Window.SavePrefs()
  T.Flush()
end
