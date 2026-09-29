-- Toolbox: core.lua
-- Namespace, chat output, saved-variable helpers, slash commands and callback wiring.
-- Loaded first (see manifest.json). Later files add Toolbox.XP, Toolbox.Window,
-- Toolbox.Hover, Toolbox.Compact, Toolbox.Daily, Toolbox.DailyDetail, Toolbox.Sounds,
-- Toolbox.Hud, Toolbox.BuffBar, Toolbox.Vitals and Toolbox.Config.

Toolbox = {
  name = "Toolbox",
  version = "0.4.0",
  build = "dev",         -- tools/build.py stamps the git commit here in dist/ (see /toolbox version)
  commands = { "toolbox", "tbx" },
  tickSeconds = 1.0,     -- periodic refresh; nothing runs per frame
  flushSeconds = 30,     -- how often a changed session is flushed to disk
}

local T = Toolbox

-- Every copy of Toolbox that loads adds itself here. All add-ons share one global table, so a
-- second copy (an old folder left in Lua/) would tangle the two; /toolbox version reports it.
ToolboxCopies = (rawget(_G, "ToolboxCopies") or 0) + 1
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
-- Seconds since 1970 from the local clock (os.time, undocumented in the SotA docs, so feature-
-- detected like os.date in T.Today), or nil when there's no usable clock.
function T.Clock()
  local osTable = rawget(_G, "os")
  local time = type(osTable) == "table" and osTable.time
  if type(time) ~= "function" then return nil end
  local ok, now = pcall(time)
  if ok and type(now) == "number" then return now end
  return nil
end

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
    datePart = T.Trim((datePart:gsub("UTC", ""):gsub("[Zz]%s*$", ""):gsub("[Tt]%s*$", "")), "%s,")
    if datePart:find("%d") then return "utc:" .. datePart, datePart .. " UTC", "utc" end
  end
  return nil
end

-- Trims `set` (a pattern class body, default "%s": spaces) from both ends, with a plain loop:
-- the game's MoonSharp gives up on the usual lazy-capture trim pattern over long text ("pattern
-- too complex", on a buff description, 2026-09-28), which standard Lua (and so the tests) handles.
function T.Trim(s, set)
  s = tostring(s or "")
  local class = "[" .. (set or "%s") .. "]"
  local i, j = 1, #s
  while i <= j and s:sub(i, i):find(class) do i = i + 1 end
  while j >= i and s:sub(j, j):find(class) do j = j - 1 end
  return s:sub(i, j)
end

-- ---------------------------------------------------------------------------
-- UI updates: only when something changes
-- ---------------------------------------------------------------------------
-- Every SetText / SetVisible / SetStyle is a call into the game's UI (and may re-lay it out), and
-- windows refreshing every tick mostly re-set what they already show. These helpers remember what
-- each element was last given and skip the call when nothing is new (2026-09-28: ~100 UI calls a
-- second idle with every window open, most of them no-ops). Use them for everything a refresh
-- sets repeatedly, and don't mix them with direct calls on the same element and property.
-- (MoonSharp may not honour weak keys; the few elements ever rebuilt make that a non-issue.)
local seen = setmetatable({}, { __mode = "k" })

local function memo(element)
  local m = seen[element]
  if not m then
    m = { style = {} }
    seen[element] = m
  end
  return m
end

function T.SetText(element, text)
  local m = memo(element)
  if m.text ~= text then
    m.text = text
    element:SetText(text)
  end
end

function T.SetTooltip(element, text)
  local m = memo(element)
  if m.tip ~= text then
    m.tip = text
    element:SetTooltip(text)
  end
end

function T.SetVisible(element, on)
  on = on == true
  local m = memo(element)
  if m.visible ~= on then
    m.visible = on
    element:SetVisible(on)
  end
end

function T.SetValue(element, value)
  local m = memo(element)
  if m.value ~= value then
    m.value = value
    element:SetValue(value)
  end
end

-- Applies only the style keys whose values changed (never a nil: see the hard rules).
function T.SetStyle(element, style)
  local m = memo(element)
  local diff = nil
  for k, v in pairs(style) do
    if m.style[k] ~= v then
      m.style[k] = v
      diff = diff or {}
      diff[k] = v
    end
  end
  if diff then element:SetStyle(diff) end
end

-- Forgets what an element was given (after something else changed it directly).
function T.Forget(element)
  seen[element] = nil
end

-- ---------------------------------------------------------------------------
-- Game data: tables or game objects
-- ---------------------------------------------------------------------------
-- The docs describe tables, but the game can hand add-ons C# objects (userdata): the buff list
-- did (2026-09-28), and every `type(x) == "table"` check skipped it. Read fields by name through
-- T.Field and copy what's needed into plain tables.

-- Field `k` of a table or game object, or nil when it can't be read.
function T.Field(obj, k)
  local ty = type(obj)
  if ty ~= "table" and ty ~= "userdata" then return nil end
  local ok, v = pcall(function() return obj[k] end)
  if ok then return v end
  return nil
end

-- A list from the game as a Lua list: a table (1-based), or a game-side list (userdata) with
-- Count, indexed from 0 (C#) or else from 1.
function T.List(list)
  local out = {}
  if type(list) == "table" then
    for i, v in ipairs(list) do out[i] = v end
    return out
  end
  if type(list) ~= "userdata" then return out end
  local n = T.Field(list, "Count")
  if type(n) ~= "number" then
    local ok, len = pcall(function() return #list end)
    n = (ok and type(len) == "number") and len or 0
  end
  local base = (n > 0 and T.Field(list, 0) == nil) and 1 or 0
  for i = base, base + n - 1 do
    local v = T.Field(list, i)
    if v ~= nil then out[#out + 1] = v end
  end
  return out
end

-- The documented fields of a combat event (API 14, and API 17's rune ... targetKey).
T.EVENT_FIELDS = { "kind", "source", "target", "amount", "skill", "fromYou", "toYou", "fromYourPet",
  "toYourPet", "party", "rune", "runeId", "damageType", "dot", "overheal", "time", "sourceKey", "targetKey" }

-- ShroudOnCombatEvents' list as plain tables (each also noting `raw`, the game's type for it).
function T.ReadEvents(events)
  -- Plain tables already (as in game, 2026-09-28): used as they are, no copy per event.
  if type(events) == "table" then
    local plain = true
    for _, e in ipairs(events) do
      if type(e) ~= "table" then
        plain = false
        break
      end
    end
    if plain then return events end
  end
  local out = {}
  for _, e in ipairs(T.List(events)) do
    local copy = { raw = type(e) }
    for _, f in ipairs(T.EVENT_FIELDS) do copy[f] = T.Field(e, f) end
    out[#out + 1] = copy
  end
  return out
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

-- Percent-encodes text for a URL query ("Gold Ore" -> "Gold%20Ore"); UTF-8 bytes one by one.
function T.UrlEncode(s)
  return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

-- Decodes JSON text: objects -> tables, arrays -> lists, null -> nil (a null in an array
-- leaves a hole; `n` is not kept). Returns the value, or nil and an error message. The
-- sandbox has no JSON library; used for the SotANET price API's answers.
function T.JsonDecode(s)
  if type(s) ~= "string" then return nil, "not text" end
  local pos = 1
  local function fail(msg) error({ json = msg .. " at " .. pos }, 0) end
  local function skip() pos = s:find("[^ \t\r\n]", pos) or (#s + 1) end
  local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
      return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
      0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
  local function str()
    pos = pos + 1                                  -- past the opening quote
    local out = {}
    while true do
      local c = s:sub(pos, pos)
      if c == "" then fail("unfinished string") end
      if c == '"' then
        pos = pos + 1
        return table.concat(out)
      elseif c == "\\" then
        local e = s:sub(pos + 1, pos + 1)
        if e == "u" then
          local hex = s:sub(pos + 2, pos + 5)
          if not hex:match("^%x%x%x%x$") then fail("bad \\u escape") end
          local cp = tonumber(hex, 16)
          pos = pos + 6
          if cp >= 0xD800 and cp <= 0xDBFF and s:sub(pos, pos + 1) == "\\u" then
            local lo = tonumber(s:sub(pos + 2, pos + 5), 16)
            if lo and lo >= 0xDC00 and lo <= 0xDFFF then
              cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
              pos = pos + 6
            end
          end
          out[#out + 1] = utf8char(cp)
        elseif ESCAPES[e] then
          out[#out + 1] = ESCAPES[e]
          pos = pos + 2
        else
          fail("bad escape")
        end
      else
        local j = s:find('["\\]', pos) or (#s + 1)
        out[#out + 1] = s:sub(pos, j - 1)
        pos = j
      end
    end
  end
  local value = nil
  value = function(depth)
    if depth > 64 then fail("nested too deep") end
    skip()
    local c = s:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local obj = {}
      skip()
      if s:sub(pos, pos) == "}" then
        pos = pos + 1
        return obj
      end
      while true do
        skip()
        if s:sub(pos, pos) ~= '"' then fail("expected a key") end
        local k = str()
        skip()
        if s:sub(pos, pos) ~= ":" then fail("expected ':'") end
        pos = pos + 1
        obj[k] = value(depth + 1)
        skip()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then fail("expected ',' or '}'") end
      end
    elseif c == "[" then
      pos = pos + 1
      local arr, n = {}, 0
      skip()
      if s:sub(pos, pos) == "]" then
        pos = pos + 1
        return arr
      end
      while true do
        n = n + 1
        arr[n] = value(depth + 1)
        skip()
        local d = s:sub(pos, pos)
        pos = pos + 1
        if d == "]" then return arr end
        if d ~= "," then fail("expected ',' or ']'") end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif s:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif s:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    end
    local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
    local v = num and tonumber(num)
    if not v then fail("unexpected '" .. c .. "'") end
    pos = pos + #num
    return v
  end
  local ok, result = pcall(function()
    local v = value(0)
    skip()
    if pos <= #s then fail("text after the value") end
    return v
  end)
  if ok then return result end
  return nil, type(result) == "table" and result.json or tostring(result)
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

-- The registered commands in order: { name, help, aliases } (for the Docs window).
function T.CommandList()
  local out = {}
  for _, c in ipairs(order) do out[#out + 1] = { name = c.name, help = c.help, aliases = c.aliases } end
  return out
end

add("help", "open the Docs window: a guide to everything (/toolbox alone opens the settings)", function()
  T.Docs.Open()
end)

add("commands", "list every command in chat", function()
  T.Print("Commands (/" .. table.concat(T.commands, " or /") .. "):")
  for _, c in ipairs(order) do
    local also = c.aliases and (" (or " .. table.concat(c.aliases, ", ") .. ")") or ""
    T.Print("  /" .. T.commands[1] .. " " .. c.name .. also .. " - " .. c.help)
  end
end)

add("docs", "open or close the Docs window (same as help)", function()
  T.Docs.Toggle()
end)

-- /toolbox xp and /toolbox daily: toggle, or "hud" / "window" to pick the form, or "move [x y]"
-- for the HUD strip.
local function formCommand(m, cmd, name, rest)
  local word, args = T.ParseArgs(rest)
  if word == "hud" or word == "window" then
    if m.SetHud(word == "hud") then
      T.Print(name .. " shows as a " .. (word == "hud" and "HUD strip" or "window") .. ".")
    end
  elseif word == "move" then
    if not m.GetHud() then
      T.Print("Move the " .. name .. " window by its title bar; move only applies to the HUD strip (/"
        .. T.commands[1] .. " " .. cmd .. " hud).")
      return
    end
    T.MoveCommand(m, cmd, name .. " strip", args)
  else
    m.Toggle()
  end
end

-- /toolbox xp debug: the session's recorded totals next to the game's, and ignored readings.
function T.XPDebugLines()
  local s, now = T.session, T.Now()
  if not s then return { "No XP session yet (waiting for a character)." } end
  local cur = T.XP.Current(s)
  local lines = {
    string.format("Session: %s, started %s ago, %d samples; newest %s ago: adventurer %s, producer %s%s.",
      tostring(s.player), T.FormatDuration(T.XP.Elapsed(s, now)), #s.samples, T.FormatDuration(now - cur.t),
      T.FormatNumber(cur.a), T.FormatNumber(cur.p), s.ended and " (ended: logged out)" or ""),
  }
  local adv, prod = T.ReadTotals()
  lines[#lines + 1] = adv and ("Game totals now: adventurer " .. T.FormatNumber(adv) .. ", producer "
    .. T.FormatNumber(prod) .. ".") or "Game totals now: not readable."
  lines[#lines + 1] = "Last hour: adventurer +" .. T.FormatNumber(T.XP.LastHour(s, "a", now)) .. ", producer +"
    .. T.FormatNumber(T.XP.LastHour(s, "p", now)) .. "."
  local low = T.xpLow
  lines[#lines + 1] = low and string.format("Readings lower than recorded, ignored: %d; the last %s ago: "
      .. "adventurer %s (recorded %s), producer %s (recorded %s).", low.count, T.FormatDuration(now - low.at),
      T.FormatNumber(low.a), T.FormatNumber(low.ca), T.FormatNumber(low.p), T.FormatNumber(low.cp))
    or "Readings lower than recorded, ignored: none."
  local off = type(s.offset) == "table" and s.offset or {}
  if (off.a or 0) > 0 or (off.p or 0) > 0 then
    lines[#lines + 1] = "XP lost this session (not counted against gains): adventurer "
      .. T.FormatNumber(off.a or 0) .. ", producer " .. T.FormatNumber(off.p or 0) .. "."
  end
  return lines
end

add("xp", "show or hide the XP window (session time, pools, XP in the last hour; hud / window; move [x y]; "
    .. "debug)", function(rest)
  if T.ParseArgs(rest) == "debug" then
    for _, line in ipairs(T.XPDebugLines()) do T.Print(line) end
    return
  end
  formCommand(T.Compact, "xp", "XP", rest)
end)

add("xpdetailed", "show or hide the XP Detailed window (levels, rates, Reset)", function()
  T.Window.Toggle()
end, { "xpd" })

add("daily", "show or hide today's stats (gold, kills, XP; resets at midnight; hud / window; move [x y])",
    function(rest)
  formCommand(T.Daily, "daily", "Today", rest)
end)

add("dailydetailed", "show or hide Today Detailed (every item gained today, with counts; view looted|crafted|"
    .. "gathered; include on|off: crafted and gathered items in Looted; values on|off: estimated values from"
    .. " SotANET; values test [item]: check the connection; values refresh: look prices up again)", function(rest)
  local word, arg = T.ParseArgs(rest)
  local DD = T.DailyDetail
  if word == "view" then
    if not DD.SetView(DD.ViewKey(arg)) then
      T.Print(T.Daily.HasResults() and "Use /" .. T.commands[1] .. " dd view looted, crafted or gathered."
        or "This game client doesn't report crafting and gathering (it needs Lua API 18).")
      return
    end
    if not DD.IsShown() then DD.SetOpen(true) end
    return
  end
  if word == "include" then
    local a = arg:lower()
    if a == "on" or a == "off" then DD.SetInclude(a == "on") end
    T.Print("Crafted and gathered items in Today Detailed's Looted list: "
      .. (DD.GetInclude() and "included" or "left out") .. ".")
    return
  end
  if word == "values" then
    local sub, item = T.ParseArgs(arg)
    if sub == "test" then
      T.Prices.Test(item)
      return
    end
    if sub == "refresh" then
      local n = T.Prices.Forget()
      T.Print("Forgot " .. n .. " cached price" .. (n == 1 and "" or "s")
        .. "; Today Detailed looks them up again while it's open.")
      return
    end
    arg = arg:lower()
    if arg == "on" or arg == "off" then T.DailyDetail.SetValues(arg == "on") end
    T.Print("Estimated values (SotANET): " .. (T.DailyDetail.GetValues() and "on" or "off") .. "."
      .. (T.DailyDetail.GetValues() and " Switch Internet on for Toolbox in the add-on manager too." or ""))
    return
  end
  T.DailyDetail.Toggle()
end, { "dd" })

-- The Toolbelt: the buff bar with the health bars, consumables and equipment bars joined to it.
add("toolbelt", "the buff bar with your health bars, consumables and gear repair joined to it (vitals|consumables|"
    .. "gear on|off: which bars join it; combat on|off: only during combat; move [x y])", function(rest)
  local word, args = T.ParseArgs(rest)
  local a = args:lower()
  local c = "/" .. T.commands[1] .. " toolbelt "
  local joins = { vitals = { T.Hud.SetGlued, "Health, focus & Vigor bars" },
                  consumables = { T.Consumables.SetGlue, "Consumables bar" },
                  gear = { T.Gear.SetGlue, "Equipment bar" } }
  if joins[word] then
    if a ~= "on" and a ~= "off" then
      T.Print("Use " .. c .. word .. " on|off.")
      return
    end
    joins[word][1](a == "on")
  elseif word == "combat" then
    if a == "on" or a == "off" then T.BuffBar.SetCombatOnly(a == "on") end
    T.Print("Toolbelt only during combat: " .. (T.BuffBar.GetCombatOnly() and "on" or "off") .. ".")
    return
  elseif word == "move" then
    T.MoveCommand(T.BuffBar, "toolbelt", "Toolbelt", args)
    return
  elseif word ~= "" then
    T.Print("Use " .. c .. "vitals|consumables|gear on|off, combat on|off, or move <x> <y>.")
    return
  end
  for line in (T.Config.HudSummary() .. "\n"):gmatch("([^\n]*)\n") do T.Print(line) end
end)

-- Today Detailed on its Crafted / Gathered view.
local function openView(view)
  if not T.DailyDetail.SetView(view) then
    T.Print("This game client doesn't report crafting and gathering (it needs Lua API 18).")
    return
  end
  if not T.DailyDetail.IsShown() then T.DailyDetail.SetOpen(true) end
end

add("crafted", "today's crafting: items made, crafts per recipe, exceptional and XP (Today Detailed)",
  function() openView("crafted") end)

add("gathered", "today's gathering: items harvested, nodes and XP (Today Detailed)",
  function() openView("gathered") end)

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

-- "/toolbox <cmd> move [x y]" for a HUD strip `m` (GetPosition / MoveTo).
function T.MoveCommand(m, cmd, what, args)
  local x, y = args:match("^(%-?%d+)[%s,]+(%-?%d+)$")
  if x then
    m.MoveTo(tonumber(x), tonumber(y))
  elseif args ~= "" then
    T.Print("Use /" .. T.commands[1] .. " " .. cmd .. " move <x> <y>, e.g. 40 220.")
    return
  end
  local px, py = m.GetPosition()
  T.Print(what .. " at " .. (px and (px .. ", " .. py) or "(not laid out yet)")
    .. ". Move it with /" .. T.commands[1] .. " " .. cmd .. " move <x> <y>, the buttons in settings, or its grip"
    .. " (to see the grip, untick Options > Interface > Nameplates & Chat Bubbles > Lock Status Movement).")
end

add("buffs", "show or hide the buff bar (move [x y]; group [after <minutes>|off; add|remove <name>|reset]; "
    .. "combat on|off (only during combat); flash on|off; countdown on|off|<seconds>; replace on|off; "
    .. "dismiss on|off; debug; raw; trace [name]; frame <0-119> [red]|off; uvtest)", function(rest)
  local word, name = T.ParseArgs(rest)
  if word == "uvtest" then
    local ok, why = T.BuffBar.UVTest()
    if not ok then
      T.Print(why == "stopped" and "UV test stopped." or ("UV test: " .. why .. "."))
      return
    end
    T.Print("UV test: six light squares (at 300, 200 on screen) each sweep the clock round for "
      .. T.BuffBar.UVTEST_SECONDS .. " s, " .. T.BuffBar.UVTEST_FRAMES_PER_STEP .. " frames every "
      .. T.BuffBar.UVTEST_STEP .. " s. Which ones visibly sweep round? Each label shows the % it asks for.")
    for i, way in ipairs(T.BuffBar.UVTEST_WAYS) do T.Print("  " .. i .. ": " .. way[2]) end
    return
  end
  if word == "frame" then
    local B = T.BuffBar
    local arg, extra = T.ParseArgs(name)
    if arg:lower() == "off" then
      B.FrameTest(nil)
      T.Print("Frame test off: the icons show their buffs' time again.")
      return
    end
    local k = tonumber(arg)
    local red = extra:lower() == "red"
    local n, why = B.FrameTest(k, red)
    if not n then
      T.Print("Use /" .. T.commands[1] .. " buffs frame <0-" .. (B.CLOCK.FRAMES - 1) .. "> [red] (or off): "
        .. why .. ".")
      return
    end
    T.Print(string.format("Every icon on the buff bar now shows sweep frame %d of %d: %d%% shaded clockwise from "
      .. "12 o'clock, %s, for %d s (%d icon%s showing).", k, B.CLOCK.FRAMES, math.floor(k * 100 / B.CLOCK.FRAMES),
      red and "dark red" or "dark", B.FRAME_TEST_SECONDS, n, n == 1 and "" or "s"))
    if n == 0 then T.Print("No icons are showing: cast a buff (or open settings to show the bar) and try again.") end
    return
  end
  if word == "countdown" then
    local B, arg = T.BuffBar, name:lower()
    if arg == "on" or arg == "off" then
      B.SetCountdown(arg == "on")
    elseif arg ~= "" and not B.SetCountdownSeconds(tonumber(arg)) then
      T.Print("Use /" .. T.commands[1] .. " buffs countdown on|off, or the seconds (" .. B.COUNTDOWN_MIN .. "-"
        .. B.COUNTDOWN_MAX .. ").")
      return
    end
    T.Print("Seconds left on icons: " .. (B.GetCountdown() and "on" or "off") .. ", in the last "
      .. B.GetCountdownSeconds() .. " s.")
    return
  end
  if word == "flash" then
    local B, arg = T.BuffBar, name:lower()
    if arg == "on" or arg == "off" then B.SetFlash(arg == "on") end
    T.Print("Flash icons about to run out: " .. (B.GetFlash() and "on" or "off") .. ".")
    return
  end
  if word == "combat" then
    local B, arg = T.BuffBar, name:lower()
    if arg == "on" or arg == "off" then B.SetCombatOnly(arg == "on") end
    T.Print("Buff bar only during combat: " .. (B.GetCombatOnly() and "on" or "off") .. ".")
    return
  end
  if word == "replace" or word == "dismiss" then
    local B, arg = T.BuffBar, name:lower()
    local set = word == "replace" and B.SetReplace or B.SetClickDismiss
    local get = word == "replace" and B.GetReplace or B.GetClickDismiss
    if (arg == "on" or arg == "off") and not set(arg == "on") then
      T.Print("This game client can't do that (needs Lua API 16; it has " .. tostring(ShroudLuaApiVersion) .. ").")
    end
    local what = word == "replace" and "Replace the game's buff bar" or "Click a buff to dismiss it"
    T.Print(what .. ": " .. (get() and "on" or "off") .. ".")
    return
  end
  if word == "group" then
    local B, c = T.BuffBar, "/" .. T.commands[1] .. " buffs group"
    local verb, part = T.ParseArgs(name)
    if verb == "after" then
      local arg = part:lower()
      local minutes = tonumber(arg)
      local seconds = (arg == "off" and 0) or (minutes and math.floor(minutes * 60 + 0.5)) or -1
      if not B.SetGroupAfter(seconds) then
        local choices = {}
        for _, ch in ipairs(B.GROUP_AFTER_CHOICES) do
          if ch[1] > 0 then choices[#choices + 1] = tostring(math.floor(ch[1] / 60)) end
        end
        T.Print("Use " .. c .. " after off, or a number of minutes: " .. table.concat(choices, ", ") .. ".")
        return
      end
    elseif verb == "add" or verb == "remove" then
      local _, msg = (verb == "add" and B.AddGroupPart or B.RemoveGroupPart)(part)
      T.Print(msg)
    elseif verb == "reset" then
      B.ResetGroup()
    elseif verb == "cat" then
      local catName, onoff = T.ParseArgs(part)
      local key = nil
      for _, k in ipairs(T.Consumables.Categories()) do
        if k:lower() == catName:lower() then key = k end
      end
      onoff = onoff:lower()
      if not key or (onoff ~= "on" and onoff ~= "off") then
        T.Print("Use " .. c .. " cat <Category> on|off. Categories: " .. table.concat(T.Consumables.Categories(), ", ")
          .. ".")
        return
      end
      B.SetGroupCategory(key, onoff == "on")
    elseif verb ~= "" then
      T.Print("Use " .. c .. " after <minutes>|off, cat <Category> on|off, add <name>, remove <name> or reset.")
      return
    end
    local after = B.GetGroupAfter()
    T.Print("Grouped into one slot: buffs lasting longer than " .. (after > 0 and B.GroupAfterLabel(after) or "(off)")
      .. ".")
    local cats = {}
    for _, k in ipairs(T.Consumables.Categories()) do
      if B.GetGroupCategory(k) then cats[#cats + 1] = k end
    end
    T.Print("Always, by kind: " .. (#cats > 0 and table.concat(cats, ", ") or "none") .. ".")
    local parts = B.GroupParts()
    T.Print("Also by name: " .. (#parts > 0 and table.concat(parts, ", ") or "none") .. ".")
    return
  end
  if word == "move" then
    T.MoveCommand(T.BuffBar, "buffs", "Buff bar", name)
    return
  end
  if word == "debug" then
    for _, line in ipairs(T.BuffBar.DebugLines()) do T.Print(line) end
    return
  end
  if word == "raw" then
    for _, line in ipairs(T.BuffBar.RawLines()) do T.Print(line) end
    return
  end
  if word == "trace" then
    T.BuffBar.Trace(name)
    return
  end
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

add("sounds", "show the alert sound files; <0-100> sets the volume, test plays them", function(rest)
  if rest:lower() == "test" then
    for _, def in ipairs(T.Sounds.DEFS) do T.Sounds.Test(def.key) end
    return
  end
  if rest:lower() == "debug" then
    for _, line in ipairs(T.Sounds.DebugLines()) do T.Print(line) end
    return
  end
  if rest ~= "" and not T.Sounds.SetVolume(tonumber(rest)) then
    T.Print("Volume must be a whole number from 0 to 100.")
    return
  end
  for _, line in ipairs(T.Sounds.Report()) do T.Print(line) end
end)

-- Lists character stats whose internal or displayed name contains `filter` (any case):
-- index, names, value, and whether add-ons may read it. For finding stat names in game.
T.STATS_MAX_LINES = 40
function T.StatLines(filter)
  filter = (filter or ""):lower()
  local lines, hidden, shown = {}, 0, 0
  local count = ShroudGetStatCount() or 0
  for i = 0, count - 1 do
    local name = ShroudGetStatNameByNumber(i)
    local label = ShroudGetStatDescriptionByNumber(i)
    name = type(name) == "string" and name or "?"
    label = type(label) == "string" and label or ""
    if filter == "" or name:lower():find(filter, 1, true) or label:lower():find(filter, 1, true) then
      if ShroudIsStatVisible(i) then
        shown = shown + 1
        if shown <= T.STATS_MAX_LINES then
          local v = ShroudGetStatValueByNumber(i)
          lines[#lines + 1] = string.format("%d %s%s = %s", i, name,
            (label ~= "" and label ~= name) and (" (" .. label .. ")") or "",
            type(v) == "number" and string.format("%g", v) or tostring(v))
        end
      else
        hidden = hidden + 1
      end
    end
  end
  if shown > T.STATS_MAX_LINES then
    lines[#lines + 1] = "... " .. (shown - T.STATS_MAX_LINES) .. " more; narrow it with a word."
  end
  lines[#lines + 1] = string.format("%d readable, %d hidden from add-ons%s (of %d stats).", shown, hidden,
    filter ~= "" and (" matching '" .. filter .. "'") or "", count)
  return lines
end

add("vitals", "health, focus & Vigor bars (size; text|bars|vigor on|off; bg; flash <%>|off|test; glue on|off; "
    .. "move)",
    function(rest)
  local word, args = T.ParseArgs(rest)
  local V = T.Vitals
  if word == "vigor" then
    local a = args:lower()
    if a == "on" or a == "off" then V.SetShowVigor(a == "on") end
    T.Print("Vigor bar: " .. (V.GetShowVigor() and "on" or "off")
      .. (V.HasVigor() and "" or " (this game client has no Vigor for add-ons: it needs Lua API 20)") .. ".")
    return
  end
  if word == "text" or word == "bars" then
    local set = word == "text" and V.SetShowText or V.SetShowBars
    if args:lower() == "on" or args:lower() == "off" then
      set(args:lower() == "on")
    else
      T.Print("Use /" .. T.commands[1] .. " vitals " .. word .. " on|off.")
    end
    return
  end
  if word == "glue" then
    local a = args:lower()
    if a == "on" or a == "off" then
      T.Hud.SetGlued(a == "on")
    elseif a ~= "" then
      T.Print("Use /" .. T.commands[1] .. " vitals glue on|off.")
      return
    end
    T.Print("Health & focus bars " .. (T.Hud.IsGlued() and "in the Toolbelt (beside the buffs)."
      or "on their own strip."))
    return
  end
  if word == "flash" then
    local a = args:lower()
    if a == "test" then
      V.PreviewFlash()
      return
    end
    if a == "on" or a == "off" then
      V.SetFlash(a == "on")
    elseif a ~= "" then
      if not V.SetFlashBelow(tonumber(a)) then
        T.Print("Use /" .. T.commands[1] .. " vitals flash <" .. V.FLASH_MIN .. "-" .. V.FLASH_MAX
          .. ">, on, off or test.")
        return
      end
      V.SetFlash(true)
    end
    T.Print("Flash when low: " .. (V.GetFlash() and ("on, below " .. V.GetFlashBelow() .. "%") or "off") .. ".")
    return
  end
  if word == "bg" then
    if args ~= "" and not V.SetBackground(args) then
      T.Print("Backgrounds: " .. table.concat(V.BackgroundNames(), ", ") .. ".")
      return
    end
    T.Print("Number background: " .. V.GetBackground() .. ".")
    return
  end
  if word == "size" then
    if args ~= "" and not V.SetScale(tonumber(args)) then
      T.Print("Size is a whole percent from " .. V.SCALE_MIN .. " to " .. V.SCALE_MAX .. ".")
      return
    end
    T.Print("Health & focus bars size: " .. V.GetScale() .. "%.")
    return
  end
  if word == "debug" then
    for _, line in ipairs(T.Vitals.DebugLines()) do T.Print(line) end
    return
  end
  if word == "move" then
    T.MoveCommand(T.Vitals, "vitals", "Health & focus bars", args)
    return
  end
  T.Vitals.Toggle()
end)

-- /toolbox combat help: every combat command, with the "add a stat on the fly" steps.
function T.CombatHelp()
  local c = "/" .. T.commands[1] .. " "
  return {
    "Combat stats HUD:",
    "  " .. c .. "combat - show or hide it",
    "  " .. c .. "combat reset - clear the fight and session numbers",
    "  " .. c .. "combat detail [fight|session] - the Combat Detailed window: damage by skill, the last"
      .. " minute, healing (it also pops up when you hover the HUD)",
    "  " .. c .. "combat size 150 - scale it (75-250%)",
    "  " .. c .. "combat bg dark 70 - background: dark, light or none, with opacity 10-100%",
    "  " .. c .. "combat pet on|off - count your pet's damage in DPS",
    "  " .. c .. "combat move 600 300 - place it (or drag its grip, or use settings)",
    "Adding stats while playing (up to " .. Toolbox.Combat.MAX_STATS .. ", saved per character):",
    "  1. Find a stat's name: " .. c .. "stats resist  (any word: absorb, dodge, block, crit, regen...)",
    "  2. Add it by the name shown: " .. c .. "combat stat add CombatHealthRegen",
    "  3. Remove it: " .. c .. "combat stat remove CombatHealthRegen",
    "  List what's shown: " .. c .. "combat stats   (a stat the game hides shows \"n/a\")",
    "Checking: " .. c .. "combat events 5 - print the next 5 combat events' fields",
  }
end

add("combat", "combat stats HUD; add stats while playing: /toolbox combat help",
    function(rest)
  local C = T.Combat
  local word, args = T.ParseArgs(rest)
  if word == "" then
    C.Toggle()
  elseif word == "reset" then
    C.Reset()
    T.Print("Combat stats reset.")
  elseif word == "move" then
    T.MoveCommand(C, "combat", "Combat stats", args)
  elseif word == "debug" then
    T.Print(T.Hud.Debug("combat"))
    T.Print(C.LayoutDebug())
  elseif word == "detail" then
    local scope = args:lower()
    if scope == "fight" or scope == "session" then
      C.Detail.SetScope(scope)
      if not C.Detail.IsShown() then C.Detail.SetOpen(true) end
    else
      C.Detail.Toggle()
    end
  elseif word == "events" then
    local n = tonumber(args) or C.CAPTURE_DEFAULT
    C.Capture(n)
    T.Print("Printing the next " .. C.CaptureLeft() .. " combat events' fields (hit something, or get hit).")
  elseif word == "size" then
    if args ~= "" and not C.SetScale(tonumber(args)) then
      T.Print("Size is a whole percent from " .. C.SCALE_MIN .. " to " .. C.SCALE_MAX .. ".")
      return
    end
    T.Print("Combat stats size: " .. C.GetScale() .. "%.")
  elseif word == "pet" then
    if args:lower() == "on" or args:lower() == "off" then C.SetPet(args:lower() == "on") end
    T.Print("Pet damage counts toward DPS: " .. (C.GetPet() and "on" or "off") .. ".")
  elseif word == "stat" then
    local verb, name = T.ParseArgs(args)
    local ok, msg = nil, nil
    if verb == "add" then ok, msg = C.AddStat(name)
    elseif verb == "remove" then ok, msg = C.RemoveStat(name)
    else msg = "Use /" .. T.commands[1] .. " combat stat add <Name> or remove <Name>." end
    T.Print(msg)
    return ok
  elseif word == "bg" then
    local name, pct = args:match("^(%a*)%s*(%d*)$")
    if not name or (args ~= "" and not C.SetBackground(name ~= "" and name or (C.GetBackground()),
        pct ~= "" and tonumber(pct) or nil)) then
      T.Print("Use /" .. T.commands[1] .. " combat bg None, Dark, Light [opacity " .. C.OPACITY_MIN .. "-"
        .. C.OPACITY_MAX .. "%], e.g. dark 70.")
      return
    end
    local bg, o = C.GetBackground()
    T.Print("Combat stats background: " .. bg .. (bg ~= "None" and (", " .. o .. "%") or "") .. ".")
  elseif word == "stats" then
    local list = C.Stats()
    T.Print("Stats on the combat HUD (" .. #list .. " of " .. C.MAX_STATS .. "): "
      .. (#list > 0 and table.concat(list, ", ") or "none") .. ".")
    T.Print("Add one while playing: /" .. T.commands[1] .. " stats <word> to find its name, then /"
      .. T.commands[1] .. " combat stat add <Name>. /" .. T.commands[1] .. " combat help for more.")
  elseif word == "help" then
    for _, line in ipairs(T.CombatHelp()) do T.Print(line) end
  else
    T.Print("Unknown: /" .. T.commands[1] .. " combat " .. word .. ". Try /" .. T.commands[1] .. " help.")
  end
end)

add("consumables", "food, potions and combat items in effect, on their own bar (bar on|off; glue on|off: in the "
    .. "Toolbelt; combat on|off; max <1-10>: icons before the rest are grouped; "
    .. "cat <Category> on|off: which kinds; add|remove <name>: always on it; exclude add|remove <name>: "
    .. "never; move [x y])", function(rest)
  local K = T.Consumables
  local word, args = T.ParseArgs(rest)
  local a = args:lower()
  local c = "/" .. T.commands[1] .. " consumables "
  if word == "" then
    local cats = {}
    for _, key in ipairs(K.Categories()) do
      if K.GetCategory(key) then cats[#cats + 1] = key end
    end
    T.Print("Consumables bar: " .. (K.GetShow() and "on" or "off") .. (K.GetGlue() and ", in the Toolbelt" or "")
      .. ". Kinds: " .. (#cats > 0 and table.concat(cats, ", ") or "none")
      .. (K.HasCategories() and "" or " (this client has no buff categories: Food and Potion go by name)") .. ".")
    if #K.Exclude() > 0 then T.Print("Left out: names containing " .. table.concat(K.Exclude(), ", ") .. ".") end
    if #K.Extra() > 0 then T.Print("Always on it: names containing " .. table.concat(K.Extra(), ", ") .. ".") end
    local list = K.Current()
    if #list == 0 then T.Print("None in effect.") end
    for _, e in ipairs(list) do
      T.Print(string.format("  %s (%s, %s): %s left", e.label, e.category, e.name, T.FormatDuration(e.remaining)))
    end
  elseif word == "bar" then
    if a == "on" or a == "off" then K.SetShow(a == "on") end
    T.Print("Consumables bar: " .. (K.GetShow() and "on" or "off (they stay on the buff bar)") .. ".")
  elseif word == "combat" then
    if a == "on" or a == "off" then K.SetCombatOnly(a == "on") end
    T.Print("Consumables bar only during combat: " .. (K.GetCombatOnly() and "on" or "off")
      .. (K.Glued() and " (in the Toolbelt it follows the Toolbelt: /" .. T.commands[1] .. " toolbelt combat)" or "")
      .. ".")
  elseif word == "max" then
    if args ~= "" and not K.SetMax(tonumber(args)) then
      T.Print("Use " .. c .. "max <1-" .. K.SLOTS .. ">.")
      return
    end
    T.Print("Consumables bar: at most " .. K.GetMax() .. " icons; the rest (and long-lasting ones) share one slot.")
  elseif word == "glue" then
    if a == "on" or a == "off" then K.SetGlue(a == "on") end
    T.Print("Consumables bar in the Toolbelt: " .. (K.GetGlue() and "on" or "off")
      .. (K.GetGlue() and not T.BuffBar.IsEnabled() and " (the buff bar is off, so it has its own strip)" or "")
      .. ".")
  elseif word == "cat" then
    local name, onoff = T.ParseArgs(args)
    local key = nil
    for _, k in ipairs(K.Categories()) do
      if k:lower() == name:lower() then key = k end
    end
    onoff = onoff:lower()
    if not key or (onoff ~= "on" and onoff ~= "off") then
      T.Print("Use " .. c .. "cat <Category> on|off. Categories: " .. table.concat(K.Categories(), ", ") .. ".")
      return
    end
    K.SetCategory(key, onoff == "on")
    T.Print(key .. " on the consumables bar: " .. onoff .. ".")
  elseif word == "add" or word == "remove" then
    local ok, msg = nil, nil
    if word == "add" then ok, msg = K.AddExtra(args) else ok, msg = K.RemoveExtra(args) end
    T.Print(msg)
    return ok
  elseif word == "exclude" then
    local verb, part = T.ParseArgs(args)
    local ok, msg = nil, nil
    if verb == "add" then
      ok, msg = K.AddExclude(part)
    elseif verb == "remove" then
      ok, msg = K.RemoveExclude(part)
    else
      msg = "Use " .. c .. "exclude add <name> or exclude remove <name>."
    end
    T.Print(msg)
    return ok
  elseif word == "move" then
    T.MoveCommand(K, "consumables", "Consumables bar", args)
  else
    T.Print("Unknown: " .. c .. word .. ". Try /" .. T.commands[1] .. " help.")
  end
end)

add("gear", "worn gear's durability, lowest first (bar on|off: the equipment bar; glue on|off: under the "
    .. "buff bar; repair <percent>: when to warn; move [x y])", function(rest)
  local G = T.Gear
  local word, args = T.ParseArgs(rest)
  if word == "" then
    for _, line in ipairs(G.Lines()) do T.Print(line) end
  elseif word == "bar" then
    if args:lower() == "on" or args:lower() == "off" then G.SetShow(args:lower() == "on") end
    T.Print("Equipment bar (worn items below " .. G.Threshold() .. "%): " .. (G.GetShow() and "on" or "off") .. ".")
  elseif word == "debug" then
    for _, line in ipairs(G.DebugLines()) do T.Print(line) end
  elseif word == "glue" then
    if args:lower() == "on" or args:lower() == "off" then G.SetGlue(args:lower() == "on") end
    T.Print("Equipment bar in the Toolbelt: " .. (G.GetGlue() and "on" or "off")
      .. (G.GetGlue() and not T.BuffBar.IsEnabled() and " (the buff bar is off, so it has its own strip)" or "")
      .. ".")
  elseif word == "repair" then
    if args ~= "" and not G.SetThreshold(tonumber((args:gsub("%%", "")))) then
      local list = {}
      for i, v in ipairs(G.THRESHOLDS) do list[i] = tostring(v) end
      T.Print("Repair threshold is one of " .. table.concat(list, ", ") .. " (percent).")
      return
    end
    T.Print("Warn when worn gear drops below " .. G.Threshold() .. "% durability.")
  elseif word == "move" then
    T.MoveCommand(G, "gear", "Equipment bar", args)
  else
    T.Print("Unknown: /" .. T.commands[1] .. " gear " .. word .. ". Try /" .. T.commands[1] .. " help.")
  end
end)

add("welcome", "show the first-run welcome again (reset: show it at the next /lua reload)", function(rest)
  if rest:lower() == "reset" then
    ShroudDeleteSavedVar("welcomed", "account")
    T.Print("The welcome will show again at the next /lua reload or login.")
    return
  end
  ShroudDeleteSavedVar("welcomed", "account")
  T.Welcome()
end)

-- "Toolbox 0.2.0, build a52051c; API 14; copies loaded: 1" (chat and the version window).
function T.VersionLine()
  return "Toolbox " .. T.version .. ", build " .. T.build .. "; API " .. tostring(ShroudLuaApiVersion)
    .. "; copies loaded: " .. tostring(ToolboxCopies) .. (ToolboxCopies > 1 and " (remove the extra one)" or "")
end

add("version", "show the installed version and build, and open the changelog", function()
  T.Print(T.VersionLine())
  T.Docs.OpenVersion()
end)

-- "Notifications: Guild message of the day on, New mail on, ..." for chat.
local function notifyList()
  local parts = {}
  for _, src in ipairs(T.Notify.Sources()) do
    parts[#parts + 1] = src.key .. " (" .. src.label .. ") " .. (T.Notify.IsOn(src.key) and "on" or "off")
      .. (T.Notify.GetVia(src.key) == "hud" and " (HUD)" or "")
  end
  return "Notifications: " .. table.concat(parts, ", ") .. "."
end

-- /toolbox notify hud ...: the notification HUD's options.
local function notifyHud(args)
  local NH, c = T.Notify.Hud, "/" .. T.commands[1] .. " notify hud"
  local word, rest = T.ParseArgs(args)
  if word == "move" then
    T.MoveCommand(NH, "notify hud", "Notification HUD", rest)
  elseif word == "clear" then
    NH.Clear()
    T.Print("Notification history cleared.")
  elseif word == "hide" then
    local secs = rest:lower() == "never" and 0 or tonumber(rest)
    if rest ~= "" and not NH.SetHideAfter(secs) then
      local choices = {}
      for _, ch in ipairs(NH.HIDE_CHOICES) do if ch[1] > 0 then choices[#choices + 1] = tostring(ch[1]) end end
      T.Print("Use " .. c .. " hide never, or seconds: " .. table.concat(choices, ", ") .. ".")
      return
    end
    T.Print("Notification HUD hides after: " .. NH.HideLabel(NH.GetHideAfter()) .. ".")
  else
    T.Print("Use " .. c .. " hide <seconds>|never, move <x> <y>, or clear.")
  end
end

add("notify", "notifications: list them; <name> on|off; [<name>] via window|hud; show; hud (hide, move, clear)",
    function(rest)
  local c = "/" .. T.commands[1] .. " notify"
  local word, arg = T.ParseArgs(rest)
  if word == "show" then
    if T.Notify.ShowCurrent() == 0 then T.Print("Nothing to show right now.") end
    return
  end
  if word == "hud" then
    notifyHud(arg)
    return
  end
  if word == "via" or (T.Notify.Label(word) and arg:lower():match("^via%s")) then
    local via = (word == "via" and arg or arg:match("^%S+%s+(.*)$") or ""):lower()
    if not T.Notify.ViaLabel(via) then
      T.Print("Use " .. c .. " [<name>] via window|hud.")
      return
    end
    for _, src in ipairs(T.Notify.Sources()) do
      if word == "via" or src.key == word then T.Notify.SetVia(src.key, via) end
    end
    T.Print((word == "via" and "All notifications" or T.Notify.Label(word)) .. " now show in the "
      .. (via == "hud" and "notification HUD." or "Notifications window."))
    return
  end
  if word ~= "" then
    arg = arg:lower()
    if not T.Notify.Label(word) or (arg ~= "on" and arg ~= "off" and arg ~= "") then
      T.Print("Use " .. c .. " <name> on|off, or " .. c .. " show. " .. notifyList())
      return
    end
    if arg ~= "" then T.Notify.SetOn(word, arg == "on") end
    T.Print(T.Notify.Label(word) .. ": " .. (T.Notify.IsOn(word) and "on" or "off") .. ".")
    return
  end
  T.Print(notifyList())
end)

add("motd", "show your guild's message of the day (on / off: open it by itself when it changes)", function(rest)
  local word = rest:lower()
  if word == "on" or word == "off" then
    T.Notify.SetOn("motd", word == "on")
    T.Print("New guild messages " .. (word == "on" and "open by themselves." or "no longer open by themselves."))
    return
  end
  local social = ShroudGetSocialSummary()
  if type(social) ~= "table" or social.inGuild ~= true then
    T.Print("You're not in a guild.")
  elseif T.Notify.ShowCurrent("motd") == 0 then
    T.Print("Your guild has no message of the day (or it hasn't loaded yet).")
  end
end)

-- /toolbox api: which functions from newer APIs this client really has. The docs (API 17 on
-- 2026-09-27) lag the client (API 20), and a documented crafting/social group was withdrawn,
-- so ask the game. Names are referenced directly: no lookup by a built name.
-- The Lua API version the official docs described when this build was made (update with each docs check).
T.DOCS_API = 24

function T.ApiLines()
  local function has(f) return type(f) == "function" end
  local groups = {
    { "Buff bar (API 16)", {
      { "ShroudSetBuffBarVisible", has(ShroudSetBuffBarVisible) },
      { "ShroudIsBuffBarVisible", has(ShroudIsBuffBarVisible) },
      { "ShroudGetBuffBarRect", has(ShroudGetBuffBarRect) },
      { "ShroudCanDismissBuff", has(ShroudCanDismissBuff) },
      { "ShroudDismissBuff", has(ShroudDismissBuff) } } },
    { "Crafting (API 18)", {
      { "ShroudGetRecipe", has(ShroudGetRecipe) },
      { "ShroudGetCraftingState", has(ShroudGetCraftingState) } } },
    { "Friends & guild (API 18)", {
      { "ShroudGetFriends", has(ShroudGetFriends) },
      { "ShroudGetGuildMembers", has(ShroudGetGuildMembers) },
      { "ShroudGetGuildMotd", has(ShroudGetGuildMotd) } } },
    { "Vigor (API 20)", { { "ShroudGetVigor", has(ShroudGetVigor) } } },
    { "Buff categories (API 23)", {
      { "ShroudGetBuffCategory", has(ShroudGetBuffCategory) },
      { "ShroudGetTargetBuffCategory", has(ShroudGetTargetBuffCategory) },
      { "ShroudBuffCategories", type(ShroudBuffCategories) == "table" } } },
  }
  local lines = { "Lua API " .. tostring(ShroudLuaApiVersion) .. " (the docs described " .. T.DOCS_API
    .. " when this build was made)." }
  for _, g in ipairs(groups) do
    local missing, count = {}, #g[2]
    for _, fn in ipairs(g[2]) do
      if not fn[2] then missing[#missing + 1] = fn[1] end
    end
    local state = nil
    if #missing == 0 then
      state = "all " .. count .. " present"
    elseif #missing == count then
      state = "none present"
    else
      state = (count - #missing) .. " of " .. count .. " present; missing " .. table.concat(missing, ", ")
    end
    lines[#lines + 1] = g[1] .. ": " .. state .. "."
  end
  lines[#lines + 1] = "Sounds (API 15) can't be probed: re-test with /" .. T.commands[1] .. " sounds test."
  for _, line in ipairs(T.ProbeLines()) do lines[#lines + 1] = line end
  return lines
end

-- ---------------------------------------------------------------------------
-- Result-event probe (API 18)
-- ---------------------------------------------------------------------------
-- The craft / gather result events feed Today Detailed's Crafted / Gathered views (daily.lua); this
-- probe also records them for /toolbox api (and one chat line the first time each fires), to check
-- what a client really sends (it has differed from the docs: `item` before API 24).

T.PROBE_EVENTS = {
  craft = { event = "ShroudOnCraftResults", fields = { "kind", "recipeId", "recipeName", "item", "quantity",
    "crafted", "exceptional", "failed", "made", "outcome", "experience" } },
  gather = { event = "ShroudOnGatherResults", fields = { "node", "failed", "experience" } },
  state = { event = "ShroudOnCraftingStateChanged", fields = { "open", "station", "busy" } },
}
T.probe = { craft = { n = 0 }, gather = { n = 0 }, state = { n = 0 }, items = nil, gained = {}, gatheredNames = {},
            stationItems = {} }
T.PROBE_KEEP = 40          -- item names remembered for the name checks

-- One result (a table or a game object) as "field=value; ..., items: A x2, B x1".
function T.DescribeResult(r, fields)
  local parts = {}
  for _, k in ipairs(fields) do
    local v = T.Field(r, k)
    if v ~= nil then parts[#parts + 1] = k .. "=" .. tostring(v) end
  end
  local items = T.Field(r, "items")
  if items ~= nil then
    local names = {}
    for _, it in ipairs(T.List(items)) do
      names[#names + 1] = tostring(T.Field(it, "name")) .. " x" .. tostring(T.Field(it, "quantity"))
    end
    parts[#parts + 1] = "items: " .. (#names > 0 and table.concat(names, ", ") or "none")
  end
  if #parts == 0 then return type(r) .. " with none of the documented fields" end
  return table.concat(parts, "; ")
end

-- From the result callbacks: counts them, keeps the first and last result's fields, and says in
-- chat the first time each kind fires this session.
function T.ProbeEvent(key, results, dropped)
  local p, spec = T.probe[key], T.PROBE_EVENTS[key]
  if not p then return end
  p.n = p.n + 1
  p.at = T.Now()
  local list = nil
  if key == "state" then list = { results } else list = T.List(results) end
  p.results = (p.results or 0) + #list
  if type(dropped) == "number" and dropped > 0 then p.dropped = (p.dropped or 0) + dropped end
  if #list == 0 then return end
  p.last = T.DescribeResult(list[#list], spec.fields)
  if key ~= "state" then p.lastItem = T.Field(list[#list], "item") end
  if key == "craft" then           -- API 24: the recipe's fixed yield
    local id = T.Field(list[#list], "recipeId")
    if type(id) == "number" and type(ShroudGetRecipe) == "function" then
      local ok, recipe = pcall(ShroudGetRecipe, id)
      local res = ok and recipe ~= nil and T.Field(recipe, "results") or nil
      if res == nil then
        p.yield = "no results field (before API 24)"
      else
        local names = {}
        for _, it in ipairs(T.List(res)) do
          names[#names + 1] = tostring(T.Field(it, "name")) .. " x" .. tostring(T.Field(it, "quantity"))
        end
        p.yield = #names > 0 and table.concat(names, ", ") or "empty (a rolled result)"
      end
    end
  end
  if key == "state" then T.probe.stationOpen = T.Field(list[#list], "open") == true end
  if key == "gather" then          -- the names a node's loot window held, to find among the items gained
    for _, r in ipairs(list) do
      for _, it in ipairs(T.List(T.Field(r, "items"))) do
        local name = T.Field(it, "name")
        if type(name) == "string" and #T.probe.gatheredNames < T.PROBE_KEEP then
          T.probe.gatheredNames[#T.probe.gatheredNames + 1] = name
        end
      end
    end
  end
  if not p.first then
    p.first = T.DescribeResult(list[1], spec.fields)
    T.Print("Probe: " .. spec.event .. " fired: " .. p.first .. " (/" .. T.commands[1] .. " api for more)")
  end
end

-- From ShroudOnItemsGained: the latest batch's names, to compare with the result events' names.
function T.ProbeItems(items)
  local names = {}
  for _, it in ipairs(T.List(items)) do
    local name = T.Field(it, "name")
    if type(name) == "string" then names[#names + 1] = name .. " x" .. tostring(T.Field(it, "quantity")) end
  end
  if #names > 0 then T.probe.items = { at = T.Now(), text = table.concat(names, ", ") } end
  for _, it in ipairs(T.List(items)) do
    local name = T.Field(it, "name")
    if type(name) == "string" then
      T.probe.gained[name] = true
      if T.probe.stationOpen and #T.probe.stationItems < T.PROBE_KEEP then   -- taken off a crafting station
        T.probe.stationItems[#T.probe.stationItems + 1] = name .. " x" .. tostring(T.Field(it, "quantity"))
      end
    end
  end
end

function T.ProbeLines()
  local lines = { "Result events (API 18; seen fire this session?):" }
  local now = T.Now()
  for _, key in ipairs({ "craft", "gather", "state" }) do
    local p, spec = T.probe[key], T.PROBE_EVENTS[key]
    if p.n == 0 then
      lines[#lines + 1] = "  " .. spec.event .. ": not yet"
    else
      lines[#lines + 1] = string.format("  %s: %d time%s (%d result%s%s), last %ds ago", spec.event, p.n,
        p.n == 1 and "" or "s", p.results, p.results == 1 and "" or "s",
        p.dropped and (", " .. p.dropped .. " dropped") or "", math.floor(now - p.at))
      lines[#lines + 1] = "    first: " .. (p.first or "?")
      if p.last and p.last ~= p.first then lines[#lines + 1] = "    last: " .. p.last end
      if p.yield then lines[#lines + 1] = "    last recipe's yield: " .. p.yield end
    end
  end
  local items = T.probe.items
  if items then
    lines[#lines + 1] = string.format("  Last items gained (%ds ago): %s", math.floor(now - items.at), items.text)
    local item = T.probe.craft.lastItem
    if type(item) == "string" then
      local same = items.text:find(item .. " x", 1, true) ~= nil
      lines[#lines + 1] = "  Last craft's item \"" .. item .. "\" " .. (same and "matches a gained item's name"
        or "isn't among them (compare the names)")
    end
  end
  local found, missing = {}, {}
  for _, name in ipairs(T.probe.gatheredNames) do
    if T.probe.gained[name] then found[#found + 1] = name else missing[#missing + 1] = name end
  end
  if #found + #missing > 0 then
    lines[#lines + 1] = "  Gathered names also seen gained: " .. (#found > 0 and table.concat(found, ", ") or "none")
      .. (#missing > 0 and ("; not seen gained (yet): " .. table.concat(missing, ", ")) or "")
  end
  if #T.probe.stationItems > 0 then
    lines[#lines + 1] = "  Gained while a crafting window was open: " .. table.concat(T.probe.stationItems, ", ")
  end
  lines[#lines + 1] = "  To check: craft something, harvest a node, open and close a crafting station,"
    .. " then run this again."
  return lines
end

add("api", "list which newer game functions this client has (to check it against the docs)", function()
  for _, line in ipairs(T.ApiLines()) do T.Print(line) end
end)

add("stats", "list character stats matching a word, e.g. /toolbox stats health", function(rest)
  for _, line in ipairs(T.StatLines(rest)) do T.Print(line) end
end)

-- ---------------------------------------------------------------------------
-- Shortcut key
-- ---------------------------------------------------------------------------
-- Shroud.Keybind: the player sees and changes it in the add-on manager, on Toolbox's row
-- under "Keys". Shift is never a modifier (docs; CONFIRMED 2026-09-29: the owner's Ctrl+Shift+; is
-- recorded as "Ctrl + ;" and works). Ctrl+; is suggested; an unusable key raises, and then none is.
-- (Earlier the suggested Ctrl+Semicolon showed as bound but counted 0 presses; unexplained, pending a
-- re-test: /toolbox key counts presses.)
T.KEY_ID = "settings"
T.KEY_SUGGESTIONS = { "Ctrl+Semicolon" }

function T.RegisterKeybind()
  if not ShroudLuaApiVersion or ShroudLuaApiVersion < 14 then return end
  -- Presses are counted so /toolbox key can tell "the key never arrives" from "it arrives but
  -- nothing happens" (in game, Ctrl+; showed as bound but did nothing).
  T.keyPresses = 0
  local function onPress()
    T.keyPresses = T.keyPresses + 1
    T.Config.Toggle()
  end
  -- A fresh spec each time, with `key` only when there is one: in the game's Lua a key set to nil
  -- stays in the table and reaches the UI as a nil entry (see AGENTS.md).
  local function spec(key)
    local s = { id = T.KEY_ID, label = "Open Toolbox settings", onPress = onPress }
    if key then s.key = key end
    return s
  end
  local refused = {}
  for _, key in ipairs(T.KEY_SUGGESTIONS) do
    local ok, err = pcall(Shroud.Keybind, spec(key))
    if ok then
      T.keySuggested = key
      if #refused > 0 then T.keyNote = "not accepted: " .. table.concat(refused, ", ") end
      return
    end
    refused[#refused + 1] = key .. " (" .. tostring(err) .. ")"
  end
  T.keyNote = "no suggested key was accepted: " .. table.concat(refused, ", ")
  local ok, err = pcall(Shroud.Keybind, spec(nil))
  if not ok then T.Print("Couldn't add the settings shortcut: " .. tostring(err)) end
end

-- "Ctrl+Semicolon (bound)" style description of the shortcut, and how to change it.
function T.KeyStatus()
  local ok, key, state = pcall(Shroud.GetKeybind, T.KEY_ID)
  if not ok or key == nil then return "no shortcut" end
  local what = {
    bound = key,
    unbound = "none set",
    gameKey = key .. " (the game uses it, so it doesn't reach Toolbox)",
    conflict = key .. " (another binding has it)",
  }
  return (what[state] or (tostring(key) .. " (" .. tostring(state) .. ")"))
end

add("key", "show the shortcut that opens the settings (change it in the add-on manager, under Keys)", function()
  T.Print("Settings shortcut: " .. T.KeyStatus() .. ". Change it in the add-on manager, on Toolbox's row"
    .. " under Keys." .. (T.keyNote and (" Note: " .. T.keyNote .. ".") or ""))
  T.Print("Pressed " .. tostring(T.keyPresses or 0) .. " time(s) since the last reload"
    .. ((T.keyPresses or 0) == 0 and " (0 means the game hasn't delivered the key to Toolbox)." or "."))
end)

-- Parses "  XP  extra " -> "xp", "extra".
function T.ParseArgs(args)
  args = T.Trim(args)
  local gap = args:find("%s")
  if not gap then return args:lower(), "" end
  return args:sub(1, gap - 1):lower(), T.Trim(args:sub(gap + 1))
end

function T.Dispatch(args)
  local word, rest = T.ParseArgs(args)
  if word == "" then word = "config" end       -- /toolbox alone opens the settings window
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
      help = "Toolbox: XP, daily stats, buff bar, health bars, combat stats. /" .. name .. " help: guide.",
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

-- Takes one reading of the totals into the session: `adv, prod` when the caller has just read them
-- (Tick), otherwise read here (ShroudOnExperienceGain).
function T.Sample(adv, prod)
  if adv == nil then adv, prod = T.ReadTotals() end
  if not adv then return end
  T.Daily.ObserveTotals(adv, prod)
  if not T.session or T.session.ended then return end
  local cur = T.XP.Current(T.session)
  if T.XP.Adjusted(T.session, "a", adv) < cur.a or T.XP.Adjusted(T.session, "p", prod) < cur.p then
    -- lower than recorded: ignored until it holds (XP.Record); counted for /toolbox xp debug
    local low = T.xpLow or { count = 0 }
    low.count, low.at, low.a, low.p, low.ca, low.cp = low.count + 1, T.Now(), adv, prod, cur.a, cur.p
    T.xpLow = low
  end
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
  local adv, prod = T.ReadTotals()   -- once a tick (it was read twice: review, 2026-09-29)
  if not s then
    T.ResumeOrStart()                -- no character yet when the add-on started
  elseif s.ended then
    T.StartSession("login")          -- logged out and back in without a restart
  elseif s.player ~= ShroudGetPlayerName() and adv then
    T.StartSession("character")
  else
    T.Sample(adv, prod)
  end
  T.Daily.Tick(adv ~= nil)
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
  T.Prices.Tick()                    -- estimated values: the next SotANET lookup, when due
  T.Hud.Tick()                       -- remember where the HUD strips are
  T.Gear.Tick()                      -- worn gear's durability, every Gear.POLL seconds
  T.Config.SyncLive()
  T.RefreshViews()
  -- Notifications: the game's change callbacks catch changes; this is the fallback for data that
  -- loads after login without one: every second for the first T.NOTIFY_EARLY seconds after start,
  -- then every T.NOTIFY_POLL seconds.
  local early = T.Now() - (T.startedAt or 0) < T.NOTIFY_EARLY
  if early or T.Now() - (T.lastNotifyPoll or -math.huge) >= T.NOTIFY_POLL then
    T.lastNotifyPoll = T.Now()
    T.Notify.Check()
  end
  T.Notify.Hud.Tick()                -- the notification HUD's auto-hide: every tick
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

-- A one-time line the first time Toolbox runs on this account.
-- A one-time welcome the first time Toolbox runs on this account: a chat line, and the
-- settings window opened. Call after everything is initialised (the settings window reads
-- every module's settings). Returns true when it showed.
T.WELCOME_DELAY = 2
T.NOTIFY_POLL, T.NOTIFY_EARLY = 5, 60

function T.Welcome()
  if ShroudGetSavedVar("welcomed", "account") then return false end
  T.Print("Toolbox is ready: type /" .. T.commands[1] .. " to open its settings, or /" .. T.commands[1]
    .. " docs for a guide to everything.")
  ShroudSetSavedVar("welcomed", true, "account")
  -- A moment later: start-up has just built every window and HUD strip, and the settings window's
  -- ~180 elements on top could pass the game's element-creation cap (2026-09-28).
  ShroudRegisterPeriodic("toolbox_welcome", function() T.Config.Open() end, T.WELCOME_DELAY, false)
  return true
end

-- Runs one start-up step; a failure is reported and the rest still start (one broken part, such
-- as a window hitting the game's element-creation cap, shouldn't take Toolbox down with it).
local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then T.Print("Couldn't start " .. name .. ": " .. tostring(err)) end
end

function ShroudOnStart()
  T.startedAt = T.Now()
  T.RegisterCommands()
  T.RegisterKeybind()
  step("today's stats", T.Daily.Load)  -- before the session: a new login re-bases daily gold
  step("the crafting state", T.Daily.ReadCraftingState)
  T.ResumeOrStart()
  T.Sample()                         -- XP gained since the last save (e.g. across a reload)
  step("XP Detailed", T.Window.Init)
  step("the XP window", T.Compact.Init)
  step("the Today window", T.Daily.InitWindow)
  step("Today Detailed", T.DailyDetail.Init)
  step("sounds", T.Sounds.Init)
  step("the buff bar", T.BuffBar.Init)
  step("the health bars", T.Vitals.Init)
  step("combat stats", T.Combat.Init)
  step("the equipment bar", T.Gear.Init)
  step("the consumables bar", T.Consumables.Init)
  step("the notification HUD", T.Notify.Hud.Init)
  step("the HUD strips", T.Hud.Init)  -- builds the HUD strips (glued or not); retries on the cap
  step("the buff bar", T.BuffBar.Tick)
  step("the health bars", T.Vitals.Tick)
  step("the equipment bar", function() T.Gear.Poll(true) end)
  ShroudRegisterPeriodic(PERIODIC, T.Tick, T.tickSeconds, true)
  T.Welcome()                        -- first run only: a chat line and the settings window
  step("notifications", T.Notify.Check)   -- anything new: the guild message, mail, ...
end

-- Only a trigger: the amount's relation to pooled vs total XP is not documented,
-- so the totals are re-read instead of summing `amount`.
function ShroudOnExperienceGain(_, _)
  T.Sample()
end

-- Kills for the daily stats (combat chat lines about you, your party or your pet).
function ShroudOnCombatEvents(events, dropped)
  local list = T.ReadEvents(events)  -- plain tables, whatever the game hands over
  T.Daily.OnCombat(list)
  T.Combat.OnEvents(list, dropped)
end

-- Fight start / end for the combat HUD.
function ShroudOnCombatModeChanged(inCombat)
  T.Combat.OnCombatMode(inCombat)
  T.BuffBar.OnCombatMode(inCombat)     -- "only during combat"
end

-- Buff bar and the debuff alert.
function ShroudOnBuffsChanged()
  T.BuffBar.OnBuffsChanged("event")
end

-- Vigor moved, appeared or went away (API 20; never fires on older clients).
function ShroudOnVigorChanged(vigor)
  T.Vitals.OnVigorChanged(vigor)
end

-- A scene change rebuilds the buff list: don't alert for debuffs that were already there.
function ShroudOnSceneUnloaded()
  T.BuffBar.SceneChange()
end

function ShroudOnSceneLoaded(_)
  T.BuffBar.SceneChange()
end

-- Guild or friends changed (twice a second at most): maybe a new guild message of the day.
function ShroudOnSocialChanged()
  T.Notify.Check()
end

-- A notification count or flag changed (mail, ransoms, rewards, guild applications).
function ShroudOnNotificationsChanged()
  T.Notify.Check()
end

-- Web answers (only the SotANET price lookups ask for any).
function ShroudOnHttpResponse(requestId, ok, status, body, err)
  T.Prices.OnResponse(requestId, ok, status, body, err)
end

-- Items for the daily stats (anything that arrives in your bags).
function ShroudOnItemsGained(items, dropped)
  T.Daily.OnItems(items, dropped)
  T.ProbeItems(items)
end

-- API 18 result events: today's crafting and gathering (Toolbox.Daily), and the /toolbox api probe.
function ShroudOnCraftResults(results, dropped)
  T.Daily.OnCraftResults(results, dropped)
  T.ProbeEvent("craft", results, dropped)
end

function ShroudOnGatherResults(results, dropped)
  T.Daily.OnGatherResults(results, dropped)
  T.ProbeEvent("gather", results, dropped)
end

function ShroudOnCraftingStateChanged(state)
  T.Daily.OnCraftingState(state)
  T.ProbeEvent("state", state)
end

function ShroudOnLogOut()
  if T.session then
    T.Sample()
    T.session.ended = true
    T.SaveSession(false)
  end
  T.Daily.Save()
  T.Hud.Tick()
  T.BuffBar.SaveTimers()
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
  T.Hud.Tick()
  T.BuffBar.SaveTimers()
  T.Window.SavePrefs()
  T.Compact.SavePrefs()
  T.Daily.SavePrefs()
  T.DailyDetail.SavePrefs()
  T.Flush()
end
