-- Toolbox: core.lua
-- Namespace, chat output, saved-variable helpers, slash commands and callback wiring.
-- Loaded first (see manifest.json). Later files add Toolbox.XP, Toolbox.Window,
-- Toolbox.Hover, Toolbox.Compact, Toolbox.Daily, Toolbox.DailyDetail, Toolbox.Sounds,
-- Toolbox.Hud, Toolbox.BuffBar, Toolbox.Vitals and Toolbox.Config.

Toolbox = {
  name = "Toolbox",
  version = "1.9.0",
  build = "dev",         -- tools/build.py stamps the git commit here in dist/ (see /toolbox version)
  commands = { "toolbox", "tbx" },
  tickSeconds = 1.0,     -- periodic refresh; nothing runs per frame
  flushSeconds = 30,     -- how often a changed session is flushed to disk
  FLUSH_STEPS = 5,       -- ticks the flush's work is spread over (T.Tick)
}

local T = Toolbox

-- Every copy of Toolbox that loads adds itself here. All add-ons share one global table, so a
-- second copy (an old folder left in Lua/) would tangle the two; /toolbox version reports it.
ToolboxCopies = (ToolboxCopies or 0) + 1   -- (nil the first time; read plainly, see AGENTS.md)
local SCOPE = "character"
local ACCOUNT = "account"            -- shared by every character on this computer (the docs: "on this install")
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
  local osTable = os                 -- nil in a sandbox without it (read plainly: see AGENTS.md)
  local time = type(osTable) == "table" and osTable.time
  if type(time) ~= "function" then return nil end
  local ok, now = pcall(time)
  if ok and type(now) == "number" then return now end
  return nil
end

-- The local time as "HH:MM", or "" without a clock.
function T.ClockText()
  local osTable = os                 -- nil in a sandbox without it (read plainly: see AGENTS.md)
  local date = type(osTable) == "table" and osTable.date
  if type(date) ~= "function" then return "" end
  local ok, s = pcall(date, "%H:%M")
  return (ok and type(s) == "string") and s or ""
end

function T.Today()
  local osTable = os                 -- nil in a sandbox without it (read plainly: see AGENTS.md)
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

-- A player name without the tags the game adds to the display name: "shawn[PVP]" and "shawn[404040][AFK][-]" (a
-- color and its end) were seen in game (2026-10-07, 2026-10-08), and Toolbox took each for another character: a new
-- XP session and every strip rebuilt on going AFK. Character names have no brackets, so every [...] goes. Plain
-- find/sub (no lazy pattern). Not a string: given back as it is.
-- The last tagged name's plain form is kept: the player's ("shawn[AFK]") was taken apart several times a second.
local plainOf, plainIs = nil, nil
function T.PlainName(name)
  if type(name) ~= "string" or not name:find("[", 1, true) then return name end
  if name == plainOf then return plainIs end
  plainOf, plainIs = name, nil
  local parts, at = {}, 1
  while true do
    local open = name:find("[", at, true)
    local close = open and name:find("]", open + 1, true)
    if not close then break end
    parts[#parts + 1] = name:sub(at, open - 1)
    at = close + 1
  end
  parts[#parts + 1] = name:sub(at)
  plainIs = T.Trim(table.concat(parts))
  return plainIs
end

-- The player's name, without tags (T.PlainName); the game's sentinels ("none", "INVALID") as they are. Every
-- module reads it here (tools/build.py refuses ShroudGetPlayerName anywhere else).
function T.PlayerName() return T.PlainName(ShroudGetPlayerName()) end

-- The add-on's 8th window (8 per add-on; Toolbox keeps 7 others): Docs, the version window and the Marks window take
-- turns. Taking it destroys the window that held it (its owner's `drop`); the taker builds its own.
local sharedOwner, sharedDrop = nil, nil
function T.TakeSharedWindow(name, drop)
  if sharedOwner and sharedOwner ~= name and sharedDrop then pcall(sharedDrop) end
  sharedOwner, sharedDrop = name, drop
end

-- A text field whose Enter works (owner, 2026-10-15: "when i type in chest in the top field and hit enter, nothing
-- happens", the handler given only as the spec's onSubmit). The reference lists both the spec field and the
-- OnSubmit method: the handler goes through both, and runs once for one press (a second call in the same frame with
-- the same text is the other way's). Constructors raise at file top level: call it from a builder.
function T.TextField(spec)
  local fn = spec.onSubmit
  if type(fn) ~= "function" then return Shroud.UI.TextField(spec) end
  local at, said = nil, nil
  local function once(el, text)
    if T.enterDebug then T.Print("[enter debug] Enter in " .. tostring(spec.id) .. ": '" .. tostring(text) .. "'") end
    if at == ShroudTime and said == text then return end
    at, said = ShroudTime, text
    return fn(el, text)
  end
  local copy = {}
  for k, v in pairs(spec) do copy[k] = v end
  copy.onSubmit = once
  local field = Shroud.UI.TextField(copy)
  pcall(function() field:OnSubmit(once) end)
  return field
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

-- Field `k` of a table or game object, or nil when it can't be read. One shared reader for pcall: a closure per
-- call was most of the vitals tick's garbage (the 1.8.0 performance pass).
local function readField(obj, k) return obj[k] end
function T.Field(obj, k)
  local ty = type(obj)
  if ty ~= "table" and ty ~= "userdata" then return nil end
  local ok, v = pcall(readField, obj, k)
  if ok then return v end
  return nil
end

-- The scene you're in, its display name and its id (ShroudGetCurrentSceneName / ...Raw), kept T.SCENE_EVERY s and
-- dropped whenever the scene changes (T.SceneChanged): the location strip and the day's play time asked for it
-- several times a second, and they were near most of Toolbox's hitches in the owner's perf runs (2026-10-14). An
-- empty answer (loading) isn't kept. Call through pcall as the game's functions.
T.SCENE_EVERY = 5
local sceneKept = { name = nil, nameAt = -math.huge, raw = nil, rawAt = -math.huge }
function T.SceneChanged() sceneKept.nameAt, sceneKept.rawAt = -math.huge, -math.huge end
function T.SceneName()
  local now = T.Now()
  if now - sceneKept.nameAt < T.SCENE_EVERY then return sceneKept.name end
  local name = ShroudGetCurrentSceneName()
  if type(name) == "string" and name ~= "" then sceneKept.name, sceneKept.nameAt = name, now end
  return name
end
function T.SceneRaw()
  local now = T.Now()
  if now - sceneKept.rawAt < T.SCENE_EVERY then return sceneKept.raw end
  local raw = ShroudGetCurrentSceneNameRaw()
  if type(raw) == "string" and raw ~= "" then sceneKept.raw, sceneKept.rawAt = raw, now end
  return raw
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

-- Saved data is kept to what the game's file reader is known to take (owner, 2026-10-08: twice a value it refused
-- lost a character's whole file: the game starts the add-on with defaults and the next save overwrites the file):
--  1. Text holds only printable ASCII other than " \ / and % (T.SAFE_CHARS). Anything else is written "%XX" (its
--     byte; "%uXXXX" for a character past 255, MoonSharp's strings being UTF-16), keys too, and read back. Found:
--     "/" (the saver writes "\/", the loader refuses it: "invalid escape sequence near '\/'", 2026-10-07). The
--     rest (quotes, newlines, accented letters) go through the same escaping and aren't trusted either.
--  2. A number is saved as a number only when it's 0 or positive, from T.SAVE_TINY and under T.SAVE_HUGE: a negative
--     one stopped the loader at its "-" ("Unexpected token : '-'", 2026-10-08), and the saver may write an exponent
--     ("1E-05"). Others are saved as text, "%N" and the number ("%N-12.5"), and read back as the number (text can't
--     start "%N": its "%" is "%25"). NaN and infinities aren't saved; -0 is saved as 0.
--  3. T.SetSavedVar checks every value before it reaches the game (T.CheckSaved) and refuses one that breaks those
--     rules, or would pass the game's 256 KB a table: that one value isn't saved, and chat says so once, instead of
--     the whole file being lost.
-- Upgrades from 1.3.0 on (owner, 2026-10-08; review 23): a table saved this way carries T.SAVE_FORMAT_KEY (no text
-- can be that key: a "%" in text is saved "%25"), and only such a table is read with the escapes above. One without
-- it was saved by 1.6.0 or before and reads as 1.6.0 read it: "%2F" a "/", "%25" a "%", nothing else (1.3.0 saved
-- text as typed, 1.5.1 and 1.6.0 wrote "%" and "/" so). A list (a table with [1]) saved whole is wrapped in a marked
-- table, its items under T.SAVE_LIST_KEY (a list can't carry a string key; review 24).
T.SAFE_CHARS = "[^ !#$&'()*+,%-%.0-9:;<=>?@A-Z%[%]^_`a-z{|}\126]"   -- (the complement: what gets escaped)
T.SAVED_CHARS = "[^ !#$%%&'()*+,%-%.0-9:;<=>?@A-Z%[%]^_`a-z{|}\126]"  -- what saved text may hold: those and the "%"
T.SAVE_TINY, T.SAVE_HUGE = 1e-4, 1e15
T.SAVE_MAX_CHARS = 240000            -- an estimate of a table's JSON size, under the game's 256 KB
-- The game's 256 KB is a whole FILE's (every key of a scope together; confirmed 2026-10-13, tmp/savelimit.lua: two
-- 150 KB keys were each taken, then the flush wrote nothing of that file). T.SetSavedVar keeps each file's estimate
-- (T.fileUse) and refuses a write that would take it past this.
T.FILE_MAX = 240000
T.SAVE_MAX_DEPTH = 24
T.SAVE_FORMAT_KEY = "%E"
T.SAVE_LIST_KEY = "%L"

local function escapeChar(c)
  local b = c:byte()
  if b > 255 then return string.format("%%u%04X", b) end
  return string.format("%%%02X", b)
end

local function encodeText(s)
  if not s:find(T.SAFE_CHARS) then return s end
  return (s:gsub(T.SAFE_CHARS, escapeChar))
end

local function unescapeWide(h)
  local ok, c = pcall(string.char, tonumber(h, 16))
  if ok then return c end
  return "%u" .. h
end

local function unescapeByte(h) return string.char(tonumber(h, 16)) end

local function decodeText(s)
  if not s:find("%", 1, true) then return s end
  return (s:gsub("%%u(%x%x%x%x)", unescapeWide):gsub("%%(%x%x)", unescapeByte))
end

local function encodeNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then return nil end
  if n == 0 then return 0 end
  if n < T.SAVE_TINY or n >= T.SAVE_HUGE then return "%N" .. string.format("%.17g", n) end
  return n
end

local function decodeNumber(s)
  if s:sub(1, 2) ~= "%N" then return nil end
  return tonumber(s:sub(3))
end

-- A deep copy with every string (keys too) encoded (`code` = encodeText) or decoded, and numbers to match.
local function codedCopy(v, code)
  if type(v) == "number" then
    if code == encodeText then return encodeNumber(v) end
    return v
  end
  if type(v) == "string" then
    if code == decodeText then
      local n = decodeNumber(v)
      if n then return n end
    end
    return code(v)
  end
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do
    local key = k
    if type(k) == "string" then key = code(k) end
    out[key] = codedCopy(x, code)
  end
  return out
end

-- How 1.5.1 to 1.6.0 read text back (1.3.0 and before wrote it as typed).
local function decodeOldText(s)
  if not s:find("%", 1, true) then return s end
  return (s:gsub("%%2F", "/"):gsub("%%25", "%%"))
end

-- For the few places that call the saved-var API themselves (the price cache, setups).
function T.ForSaving(v)
  local out = codedCopy(v, encodeText)
  if type(out) ~= "table" then return out end
  if out[1] ~= nil then out = { [T.SAVE_LIST_KEY] = out } end
  out[T.SAVE_FORMAT_KEY] = 1
  return out
end

function T.FromSaved(v)
  if type(v) ~= "table" then return codedCopy(v, decodeText) end    -- (only tables were saved with text)
  if v[T.SAVE_FORMAT_KEY] == nil then return codedCopy(v, decodeOldText) end
  local out = codedCopy(v, decodeText)
  out[T.SAVE_FORMAT_KEY] = nil
  if type(out[T.SAVE_LIST_KEY]) == "table" and next(out, next(out)) == nil then return out[T.SAVE_LIST_KEY] end
  return out
end
-- A value read straight from the saved vars, put in today's form (text saved before the escaping, for a copy).
function T.Resaved(v) return T.ForSaving(T.FromSaved(v)) end

-- Whether `v` (as it will be saved: already through T.ForSaving) is safe to hand to the game. Returns true, or
-- false and why ("text with a '/' at notify.sources.x.title").
local function numberOk(n)
  return n == n and n >= 0 and not (n == 0 and 1 / n < 0) and (n == 0 or (n >= T.SAVE_TINY and n < T.SAVE_HUGE))
end

-- A number's room in the file: a whole one its digits (and a comma), any other 24 (the saver may write 17 digits).
function T.NumberSize(x)
  if x ~= math.floor(x) or x >= T.SAVE_HUGE then return 24 end
  local digits = 2
  while x >= 10 do
    x = x / 10
    digits = digits + 1
  end
  return digits
end

-- A saved value's estimated room in its file, as T.CheckSaved counts it, without its checks (a value already there,
-- perhaps saved before them).
function T.SavedSize(v, depth)
  local kind = type(v)
  if kind == "string" then return #v + 3 end
  if kind == "number" then return T.NumberSize(v) end
  if kind == "boolean" then return 6 end
  if kind ~= "table" or (depth or 1) > T.SAVE_MAX_DEPTH then return 6 end
  local size = 2
  for k, item in pairs(v) do
    size = size + (type(k) == "string" and #k + 4 or (type(k) == "number" and T.NumberSize(k) + 3 or 0))
      + T.SavedSize(item, (depth or 1) + 1)
  end
  return size
end

-- Returns true and the value's estimated size, or false and why.
function T.CheckSaved(v)
  local size, inside, trail = 0, {}, {}
  -- Where in `v` (".notify.sources.x"): built only for a refusal (a path for every value was most of the garbage of
  -- checking a full set of map overlays, 2026-10-13).
  local function pathTo(depth)
    local parts = {}
    for d = 1, depth - 1 do parts[d] = "." .. tostring(trail[d]) end
    return table.concat(parts)
  end
  local function walk(x, depth)
    local kind = type(x)
    if kind == "boolean" then
      size = size + 6
      return true
    elseif kind == "number" then
      if not numberOk(x) then return false, "the number " .. tostring(x) .. " at " .. pathTo(depth) end
      size = size + T.NumberSize(x)
      return true
    elseif kind == "string" then
      local at = x:find(T.SAVED_CHARS)
      if at then return false, "unsafe text (" .. string.format("%q", x:sub(at, at)) .. ") at " .. pathTo(depth) end
      size = size + #x + 3
      return true
    elseif kind == "table" then
      if inside[x] then return false, "a table inside itself at " .. pathTo(depth) end
      if depth > T.SAVE_MAX_DEPTH then
        return false, "nesting deeper than " .. T.SAVE_MAX_DEPTH .. " at " .. pathTo(depth)
      end
      inside[x] = true
      size = size + 2
      for k, item in pairs(x) do
        if type(k) == "string" then
          if k:find(T.SAVED_CHARS) then return false, "an unsafe key at " .. pathTo(depth) end
          size = size + #k + 4
        elseif type(k) == "number" then
          if k < 1 or k ~= math.floor(k) or k >= T.SAVE_HUGE then
            return false, "the key " .. tostring(k) .. " at " .. pathTo(depth)
          end
          size = size + T.NumberSize(k) + 3          -- (counted as if written "12": a list's place, generously)
        else
          return false, "a " .. type(k) .. " key at " .. pathTo(depth)
        end
        trail[depth] = k
        local ok, why = walk(item, depth + 1)
        if not ok then return false, why end
        if size > T.SAVE_MAX_CHARS then return false, "more than the game's 256 KB a table" end
      end
      inside[x] = nil
      return true
    end
    return false, "a " .. kind .. " at " .. pathTo(depth)
  end
  local ok, why = walk(v, 1)
  if not ok then return false, why end
  return true, size
end

-- Each saved-variable file's estimated size: { total, keys = { [key] = its room, the key's name too } }. Measured
-- at start and for another character (T.MeasureFiles), kept by every write and delete below.
T.fileUse = { character = { total = 0, keys = {}, reserve = 0 }, account = { total = 0, keys = {}, reserve = 0 } }
local function fileOf(scope)
  return T.fileUse[(type(scope) == "string" and scope:lower() == "account") and "account" or "character"]
end
local function noteSize(scope, key, size)
  local f = fileOf(scope)
  f.total = f.total - (f.keys[key] or 0) + size
  f.keys[key] = size > 0 and size or nil
end

-- How full a file is: its estimate and T.FILE_MAX.
function T.FileUse(scope) return fileOf(scope).total, T.FILE_MAX - fileOf(scope).reserve end

-- Room kept free in scope's file for keys there that can't be measured (review 36: recovery copies from before
-- their index).
function T.ReserveFile(scope, size) fileOf(scope).reserve = size end

-- Whether `size` more (a key's whole room, its name included) would still fit in scope's file in place of `key`.
function T.FileFits(key, size, scope)
  local f = fileOf(scope)
  local old = f.keys[key] or 0
  return size <= old or f.total - old + size <= T.FILE_MAX - f.reserve
end

-- Measures every key in `keys` (scope's) as it is now, for one file (`fresh`: forget the old measure first).
function T.MeasureKeys(keys, scope, fresh)
  if fresh then
    local f = fileOf(scope)
    f.total, f.keys = 0, {}
  end
  for _, key in ipairs(keys) do
    local v = ShroudGetSavedVar(key, scope)
    noteSize(scope, key, v == nil and 0 or T.SavedSize(v) + #key + 4)
  end
end

-- The account file's values as the last flush that worked left them, for each key changed since (key -> { old }):
-- B.FlushFailed can put them back when the file passed 256 KB with copies Toolbox can't measure (review 36).
T.accountUndo = {}
local function noteUndo(key, scope)
  if fileOf(scope) == T.fileUse.account and T.accountUndo[key] == nil then
    T.accountUndo[key] = { old = ShroudGetSavedVar(key, scope) }
  end
end

-- Deletes a saved var (the file's measure follows).
-- No character in the world: after a logout (the reference: by ShroudOnLogOut "the character has already left": a
-- character-scope value written then belongs to no character; Toolbox's logout save went into
-- toolbox.nochar.character.json, owner 2026-10-16), or a start with none. Character-scope writes are skipped then,
-- quietly (false, "no character"), until T.FollowCharacter reads a character's settings again.
function T.NoCharacter() return T.loggedOut == true or not T.settingsFor end
local function characterScope(scope) return not (type(scope) == "string" and scope:lower() == "account") end

local function gameDelete(key, scope)
  return ShroudDeleteSavedVar(key, scope)
end

function T.DeleteSaved(key, scope)
  if characterScope(scope) and T.NoCharacter() then return false end
  noteUndo(key, scope)
  local ok = gameDelete(key, scope)
  -- still in the file until the game deletes it (review 61); a key already absent is gone too
  if ok or ShroudGetSavedVar(key, scope) == nil then noteSize(scope, key, 0) end
  return ok
end

-- Every saved-variable write goes through here. Refuses (false, why) a value that isn't safe to save (chat says so
-- once per key a session: one setting not saved, not the whole file lost) or a key the game wouldn't take; else
-- the game's answer. A write to this character's file marks the recovery copy behind (T.Backup.KeepRecovery).
T.saveRefused = {}                   -- key -> why, this session (the tests fail on any they don't expect)
function T.SetSavedVar(key, value, scope)
  if type(key) ~= "string" or key == "" or #key > 128 or key:find("[/\\%c]") then
    return false, "a bad key"
  end
  if characterScope(scope) and T.NoCharacter() then return false, "no character" end
  local t0 = T.PerfT()
  local ok, why = T.CheckSaved(value)
  T.PerfAdd("save " .. key .. ":check", t0)
  local size = ok and (why + #key + 4) or 0
  if ok and value == nil then size = 0 end
  if ok and not T.FileFits(key, size, scope) then
    ok, why = false, "its file would pass the game's 256 KB a file: then the game would save nothing of it"
    if not T.saveRefused[key] then
      T.Print("Toolbox didn't save '" .. key .. "': " .. (fileOf(scope) == T.fileUse.account and "the account file"
        or "this character's file") .. " is full (the game keeps at most 256 KB a file, and one past it isn't saved"
        .. " at all). Your other settings are safe.")
    end
    T.saveRefused[key] = why
    return false, why, "full"
  end
  if not ok then
    if not T.saveRefused[key] then
      T.Print("Toolbox didn't save '" .. key .. "' (" .. why .. "): the game couldn't have read its file back."
        .. " Your other settings are safe. Please report this with /" .. T.commands[1] .. " version.")
    end
    T.saveRefused[key] = why
    return false, why
  end
  if scope ~= "account" and T.Backup and T.Backup.Recovers(key) then T.recoveryDirty = true end
  noteUndo(key, scope)
  t0 = T.PerfT()
  local stored = ShroudSetSavedVar(key, value, scope) == true
  T.PerfAdd("save " .. key .. ":the game's store", t0)
  if stored then noteSize(scope, key, size) end
  return stored
end

function T.ReadSaved(key)
  return T.FromSaved(ShroudGetSavedVar(key, SCOPE))
end

-- Returns T.SetSavedVar's answer: true, or false, why and (a file past 256 KB) "full".
function T.Save(key, value)
  local t0 = T.PerfT()
  local saving = T.ForSaving(value)
  T.PerfAdd("save " .. key .. ":copy", t0)
  local ok, why, kind = T.SetSavedVar(key, saving, SCOPE)
  if not ok then T.Print("Could not save '" .. key .. "'.") end
  if T.Backup.IsSetting(key) then T.setupDirty = true end    -- this character's setup copy is behind
  return ok, why, kind
end

-- Writes the saved vars to disk. The game answers false when a write failed or a file passed 256 KB;
-- say so in chat (at most every T.FLUSH_WARN_EVERY seconds) rather than lose settings silently. Returns false and
-- "full" when the account file was written without its latest changes (B.FlushFailed said why in chat).
T.FLUSH_WARN_EVERY = 300
function T.Flush()
  if T.setupDirty then T.Backup.KeepCopy() end
  if T.recoveryDirty then T.Backup.KeepRecovery() end
  local ceilingKept = T.Backup.KeepCeiling()
  local t0 = T.PerfT()
  local ok = ShroudFlushSavedVars()
  T.PerfAdd("flush:the game's write", t0)
  local made = ok == false and T.Backup.FlushFailed()
  if made == true then ok = true end                          -- written after all
  if ok ~= false and ceilingKept then T.Backup.CeilingWritten() end
  if ok ~= false or made == "undone" then T.accountUndo = {} end
  if made == "undone" then return false, "full" end
  if ok == false then
    T.flushFailures = (T.flushFailures or 0) + 1
    if not T.flushWarnedAt or T.Now() - T.flushWarnedAt >= T.FLUSH_WARN_EVERY then
      T.flushWarnedAt = T.Now()
      T.Print("Couldn't write Toolbox's saved settings to disk (the game refused it). Recent changes may be lost"
        .. " if the game closes; please report it with /" .. T.commands[1] .. " version.")
    end
  end
  return ok
end

-- 1234567 -> "1,234,567" (rounded to a whole number).
-- HUD strip backgrounds (owner, 2026-10-15): black at a strip's `shade` % behind its text or icons, the same default
-- everywhere (the menu, combat stats, notifications, XP, Today, location, the health bars' and target's Dark panel). A
-- color's alpha doesn't fade the text (opacity would). The game has no opacity for HUD frames (only windows').
T.SHADE_DEFAULT, T.SHADE_MAX = 60, 90
-- A saved shade, or the default for anything else.
function T.ShadeOf(v)
  if type(v) == "number" and v == math.floor(v) and v >= 0 and v <= T.SHADE_MAX then return v end
  return T.SHADE_DEFAULT
end
-- "#00000099": black at `pct` % (0 or less: none).
function T.ShadeColor(pct)
  if type(pct) ~= "number" or pct <= 0 then return "#00000000" end
  return string.format("#000000%02x", math.floor(math.min(pct, 100) * 255 / 100 + 0.5))
end

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
-- For a module in its own file to add its command (skills.lua: the skill activity strip).
T.AddCommand = add

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
  if word == "hud" or word == "window" or word == "compact" then
    local ok = m.SetHud(word == "hud")
    if ok and word ~= "hud" then ok = m.SetCompact(word == "compact") end
    if ok then
      local form = { hud = "HUD strip", window = "window", compact = "compact window (title bar on hover)" }
      T.Print(name .. " shows as a " .. form[word] .. ".")
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

add("xp", "show or hide the XP window (session time, pools, XP in the last hour; hud / window / compact; move [x y]; "
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

add("daily", "show or hide today's stats (gold, kills, XP; resets at midnight; hud / window / compact; move [x y])",
    function(rest)
  formCommand(T.Daily, "daily", "Today", rest)
end)

add("loot", "show or hide the Loot Tracker (every item gained today, with counts; reset: count from now; today:"
    .. " back to the whole day; view looted|crafted|"
    .. "gathered|runs; include on|off: crafted and gathered items in Looted; values on|off: estimated values from"
    .. " SotANET; values each on|off: the price each in the count; values test [item]: check the connection;"
    .. " values refresh: look prices up again; log: the last item events as the game sent them)", function(rest)
  local word, arg = T.ParseArgs(rest)
  local DD = T.DailyDetail
  if word == "log" then
    local lines = T.Daily.ItemLogLines()
    T.Print(#lines > 0 and ("The last " .. #lines .. " item events (each line is one call from the game):")
      or "No items gained since Toolbox started.")
    for _, line in ipairs(lines) do T.Print("  " .. line) end
    return
  end
  if word == "reset" then
    T.Print(DD.ResetRun() and ("The Loot Tracker counts from now. The Today window keeps the whole day; /"
      .. T.commands[1] .. " loot today brings it back here too.") or "Nothing to reset yet: no character data.")
    return
  elseif word == "today" then
    T.Print(DD.EndRun() and "The Loot Tracker shows all of today again." or "It already shows all of today.")
    return
  end
  if word == "view" then
    if not DD.SetView(DD.ViewKey(arg)) then
      T.Print(T.Daily.HasResults() and "Use /" .. T.commands[1] .. " dd view looted, crafted, gathered or runs."
        or "This game client doesn't report crafting and gathering (it needs Lua API 18).")
      return
    end
    if not DD.IsShown() then DD.SetOpen(true) end
    return
  end
  if word == "include" then
    local a = arg:lower()
    if a == "on" or a == "off" then DD.SetInclude(a == "on") end
    T.Print("Crafted and gathered items in Loot Tracker's Looted list: "
      .. (DD.GetInclude() and "included" or "left out") .. ".")
    return
  end
  if word == "values" then
    local sub, item = T.ParseArgs(arg)
    if sub == "test" then
      T.Prices.Test(item)
      return
    end
    if sub == "each" then
      local a = item:lower()
      if a == "on" or a == "off" then T.DailyDetail.SetEach(a == "on") end
      T.Print("Price each in the count: " .. (T.DailyDetail.GetEach() and "on" or "off") .. ".")
      return
    end
    if sub == "refresh" then
      local n = T.Prices.Forget()
      T.Print("Forgot " .. n .. " cached price" .. (n == 1 and "" or "s")
        .. "; Loot Tracker looks them up again while it's open.")
      return
    end
    arg = arg:lower()
    if arg == "on" or arg == "off" then T.DailyDetail.SetValues(arg == "on") end
    T.Print("Estimated values (SotANET): " .. (T.DailyDetail.GetValues() and "on" or "off") .. "."
      .. (T.DailyDetail.GetValues() and " Switch Internet on for Toolbox in the add-on manager too." or ""))
    return
  end
  T.DailyDetail.Toggle()
end, { "dailydetailed", "dd" })

-- The Toolbelt: the buff bar with the health bars, consumables and equipment bars joined to it.
add("toolbelt", "the buff bar with your health bars, consumables, gear repair and target joined to it (vitals|"
    .. "consumables|gear|target on|off: which bars join it; combat on|off: only during combat; move [x y])",
    function(rest)
  local word, args = T.ParseArgs(rest)
  local a = args:lower()
  local c = "/" .. T.commands[1] .. " toolbelt "
  local joins = { vitals = { T.Hud.SetGlued, "Health, focus & Vigor bars" },
                  consumables = { T.Consumables.SetGlue, "Consumables bar" },
                  gear = { T.Gear.SetGlue, "Equipment bar" },
                  target = { T.Target.SetGlue, "Target HUD" } }
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
    T.Print("Use " .. c .. "vitals|consumables|gear|target on|off, combat on|off, or move <x> <y>.")
    return
  end
  for line in (T.Config.HudSummary() .. "\n"):gmatch("([^\n]*)\n") do T.Print(line) end
end)

-- Loot Tracker on its Crafted / Gathered view.
local function openView(view)
  if not T.DailyDetail.SetView(view) then
    T.Print("This game client doesn't report crafting and gathering (it needs Lua API 18).")
    return
  end
  if not T.DailyDetail.IsShown() then T.DailyDetail.SetOpen(true) end
end

add("recipe", "a known recipe as the game reports it, and what it takes from raw materials (recipe <name>)",
    function(rest)
  local D = T.Daily
  local lines = D.RecipeLines(rest)
  if lines then                        -- answered without the whole book (a list of matches, none, ...)
    for _, line in ipairs(lines) do T.Print(line) end
    return
  end
  local n = D.ReadRecipeBook(function(ok)
    if not ok then return end
    for _, line in ipairs(D.RecipeLines(rest) or {}) do T.Print(line) end
  end)
  if n and n > 0 then
    T.Print("Reading your recipe book (" .. n .. " recipes): the answer follows in a few seconds.")
  end
end)

-- You learned a recipe (or marked a favorite): /toolbox recipe reads the book again.
function ShroudOnRecipesChanged()
  T.Ran("recipes")
  T.Daily.ForgetRecipes(T.Planner.KeepsBook())   -- read only on ask: the old book stays, marked stale
  T.Planner.RecipesChanged()
end

-- Your bags changed: the crafting planner's counts (worked out again only while it shows).
function ShroudOnInventoryChanged()
  T.Ran("inventory")
  T.Planner.Changed()
end

add("plan", "the crafting planner: a recipe's materials, what to get and what to craft (plan [recipe]; plan hud"
  .. " [close <seconds>|start shop|build|auto on|off|shade <0-90>]; plan book [read|stop|need|login|manual];"
  .. " plan debug)",
  function(rest)
    local word = T.Trim(rest or ""):lower()
    local PL = T.Planner
    local cmd = "/" .. T.commands[1] .. " plan "
    local book = word == "book" and "" or word:match("^book%s+(.+)$")   -- not "bookcase"
    if book then
      if book == "read" then
        if not PL.ReadBook() and not T.Daily.ReadingRecipes() then
          T.Print("This game client has no recipe book for add-ons.")
        end
      elseif book == "stop" then
        T.Print(PL.StopBook() and "Recipe book: stopped. Nothing reads it on its own until you do (" .. cmd
          .. "book read)." or "The recipe book isn't being read.")
      elseif book ~= "" then
        if PL.SetBookWhen(book) then
          T.Print("Recipe book: read " .. PL.BookWhenName(PL.GetBookWhen()):lower() .. ".")
        else
          T.Print("Use " .. cmd .. "book read|stop|need|login|manual.")
        end
      else
        T.Print("Recipe book: " .. PL.BookStatus() .. ". Read " .. PL.BookWhenName(PL.GetBookWhen()):lower()
          .. " (" .. cmd .. "book need|login|manual; read; stop).")
      end
      return
    end
    local start = word:match("^hud start (.+)$")
    if start then
      if PL.SetHudStart(start) then
        T.Print(PL.HUD_NAME .. ": opens on the " .. PL.HudStartName(PL.GetHudStart()):lower() .. ".")
      else
        T.Print("Use " .. cmd .. "hud start shop|build.")
      end
      return
    end
    local auto = word:match("^hud auto (%a+)$")
    if auto == "on" or auto == "off" then
      PL.SetHudAuto(auto == "on")
      T.Print(PL.HUD_NAME .. (auto == "on" and ": on to the build order once everything is gathered."
        or ": the shopping list stays until you switch."))
      return
    end
    local shade = word:match("^hud shade (.+)$")
    if shade then
      if PL.SetHudShade(tonumber(shade)) then
        T.Print(PL.HUD_NAME .. ": background shade " .. PL.GetHudShade() .. "%.")
      else
        T.Print("Use " .. cmd .. "hud shade 0-" .. T.SHADE_MAX .. ".")
      end
      return
    end
    local close = word:match("^hud close (.+)$")
    if close then
      if PL.SetHudClose(close) then
        T.Print(PL.HUD_NAME .. ": closes " .. (PL.GetHudClose() > 0 and (PL.HudCloseName(PL.GetHudClose())
          .. " after every craft is done.") or "only when you close it."))
      else
        T.Print("Use /" .. T.commands[1] .. " plan hud close never|10|30|60|120|300 (seconds).")
      end
      return
    end
    if word == "hud" or word == "hud on" or word == "hud off" then
      local on = word == "hud on" or (word == "hud" and not PL.GetHud())
      PL.SetHud(on)
      T.Print(PL.HUD_NAME .. (on and " on: the shopping list, then the build order (/toolbox plan hud again"
        .. " hides it)." or " hidden."))
      return
    end
    if word == "debug" then
      T.Planner.debug = not T.Planner.debug
      T.enterDebug = T.Planner.debug
      T.Print("Planner debug " .. (T.Planner.debug and "on: each event the planner's search box gets, and Enter in"
        .. " any Toolbox text box (with its name), is said in chat." or "off."))
      return
    end
    T.Planner.Open(rest)
  end)

add("crafted", "today's crafting: items made, crafts per recipe, exceptional and XP (Loot Tracker)",
  function() openView("crafted") end)

add("gathered", "today's gathering: items harvested, nodes and XP (Loot Tracker)",
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

add("settings", "settings files and setups (save, reset, cancel, backup, backups, restore <n>; setups, export,"
    .. " import, delete <name>; share on|off)",
    function(rest)
  local B2 = T.Backup
  local word, name = T.ParseArgs(rest)
  local cmd = "/" .. T.commands[1] .. " settings"
  if word == "save" then
    T.Print(B2.SaveNow() == false and "The game refused to write the files (see the line above)."
      or "Saved: the files are up to date. Copy them now (" .. cmd .. " shows where).")
  elseif word == "reset" then
    local ok, why = B2.RequestReset()
    if not ok then
      T.Print("Couldn't ask for a reset: " .. why .. ".")
      return
    end
    T.Print("Every setting and position will go back to its default when Toolbox next starts: type /lua reload now."
      .. " " .. cmd .. " cancel drops it." .. B2.BackupNote(why))
  elseif word == "backup" then
    for _, line in ipairs(B2.BackupLines()) do T.Print(line) end
  elseif word == "backups" then
    local list, why = B2.BackupList()
    if #list == 0 then
      T.Print("No copies of this character's file to restore" .. (why and (" (" .. why .. ")") or "") .. ". "
        .. cmd .. " backup keeps one now.")
    else
      T.Print("Copies of this character's file, newest first (" .. cmd .. " restore <number>):")
      for i, b in ipairs(list) do T.Print("  " .. i .. ". " .. b.label) end
    end
  elseif word == "restore" then
    local list = B2.BackupList()
    local pick = list[tonumber(name) or 0]
    if not pick then
      T.Print("Which copy? " .. cmd .. " backups lists them; then " .. cmd .. " restore <number>.")
      return
    end
    local ok, kept, warn = B2.Restore(pick.name)
    T.Print(ok and ("Restored this character's settings from the copy of " .. pick.label
      .. (warn and (", " .. warn) or "") .. "." .. (kept and (" The file it replaced was kept too: " .. kept .. ".")
      or " The file already held that copy's settings.")) or ("Couldn't restore: " .. tostring(kept) .. "."))
  elseif word == "cancel" then
    local had, written = B2.Cancel()
    T.Print((had and "Dropped the waiting reset." or "Nothing was waiting.")
      .. (written and "" or " (The game couldn't write that to disk.)"))
  elseif word == "setups" then
    local list = B2.Setups()
    if #list == 0 then
      T.Print("No setups to import yet. Other characters' setups show up here once they've played with Toolbox;"
        .. " " .. cmd .. " export <name> saves yours under a name.")
    else
      T.Print("Setups you can import (" .. cmd .. " import <name>):")
      for _, s in ipairs(list) do T.Print("  " .. s.label) end
    end
  elseif word == "share" then
    if name == "on" or name == "off" then
      local ok, why = B2.SetShare(name == "on")
      if not ok then
        T.Print((name == "on" and "Couldn't list your setup: " or "Couldn't take your setup off the list: ")
          .. why .. ".")
      end
    end
    T.Print(B2.GetShare() and "This character's setup is listed for your other characters to import ("
      .. cmd .. " share off stops it)." or "This character's setup isn't listed for others (" .. cmd
      .. " share on lists it).")
  elseif word == "export" then
    local ok, saved = B2.Export(name)
    T.Print(ok and ("Exported your settings and positions as '" .. saved .. "'. Any character can import it.")
      or ("Couldn't export: " .. saved .. ". Use " .. cmd .. " export <name>."))
  elseif word == "import" then
    local s = B2.FindSetup(name)
    if not s then
      T.Print("No setup called '" .. name .. "'. " .. cmd .. " setups lists them.")
      return
    end
    local ok, why = B2.Import(s)
    T.Print(ok and ("Imported '" .. s.name .. "': this character now has a copy of its settings and positions."
      .. (why and (" (" .. why .. ")") or "") .. B2.BackupNote(B2.lastBackup))
      or ("Couldn't import: " .. tostring(why) .. "."))
  elseif word == "delete" then
    local s = B2.FindSetup(name)
    if not s then
      T.Print("No setup called '" .. name .. "'. " .. cmd .. " setups lists them.")
      return
    end
    local ok, why = B2.DeleteSetup(s)
    T.Print(ok and ("Deleted the setup '" .. s.name .. "'." .. (s.character
      and " (That character's copy comes back when it next plays, if it still lists its setup.)" or ""))
      or ("Couldn't delete '" .. s.name .. "': " .. tostring(why) .. "."))
  elseif word == "" then
    for _, line in ipairs(B2.HowTo()) do T.Print(line) end
    if B2.Pending() then T.Print("A reset is waiting: type /lua reload to apply it (" .. cmd .. " cancel).") end
  else
    T.Print("Use " .. cmd .. " (where the files are), " .. cmd .. " save, reset or cancel, or " .. cmd
      .. " setups, export <name>, import <name>, delete <name> or share on|off.")
  end
  T.Config.Sync()
end)

add("font", "set the text size of the windows and text strips, 9-32 (no number: show the current size)", function(rest)
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
    .. "quiet [add|remove <name>] (muted effects); sound [[get|end] <name> = <file>; test|remove [get|end] <name>] "
    .. "(an effect's own sound); repeat off|<minutes>|30s (don't repeat a sound); "
    .. "combat on|off (only during combat); flash on|off; countdown on|off|<seconds>; replace on|off; "
    .. "dismiss on|off; block [on|off|width <n>|size <n>|combat on|off|move [x y]]; debug; raw; trace [name]; "
    .. "tips [name])",
    function(rest)
  local word, name = T.ParseArgs(rest)
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
  if word == "repeat" then
    local B, arg = T.BuffBar, name:lower()
    if arg ~= "" then
      local secs, minutes = arg:match("^(%d+)%s*s$"), tonumber(arg)
      local seconds = (arg == "off" and 0) or (secs and tonumber(secs)) or (minutes and math.floor(minutes * 60 + 0.5))
        or -1
      if not B.SetRepeat(seconds) then
        local choices = {}
        for _, ch in ipairs(B.REPEAT_CHOICES) do
          if ch[1] > 0 then
            choices[#choices + 1] = ch[1] < 60 and (ch[1] .. "s") or tostring(math.floor(ch[1] / 60))
          end
        end
        T.Print("Use /" .. T.commands[1] .. " buffs repeat off, 30s or a number of minutes: "
          .. table.concat(choices, ", ") .. ".")
        return
      end
    end
    local r = B.GetRepeat()
    T.Print("Don't repeat a sound for the same effect within: " .. (B.RepeatLabel(r) or "Off")
      .. (r > 0 and " (each alert starts the time again)." or "."))
    return
  end
  if word == "sound" or word == "sounds" then
    local B, c = T.BuffBar, "/" .. T.commands[1] .. " buffs sound"
    local function when(text)                  -- "get Poison" -> "get", "Poison"; "Poison" -> nil, "Poison"
      local w, after = T.ParseArgs(text)
      if w == "get" or w == "end" then return w, after end
      return nil, text
    end
    local verb, effect = T.ParseArgs(name)
    local eq = name:find("=", 1, true)
    if eq then
      local w, target = when(T.Trim(name:sub(1, eq - 1)))
      local _, msg = B.SetEffectSound(target, name:sub(eq + 1), w)
      T.Print(msg)
      return
    end
    if verb == "remove" or verb == "test" then
      local w, target = when(effect)
      local _, msg = (verb == "remove" and B.RemoveEffectSound or B.TestEffectSound)(target, w)
      T.Print(msg)
      return
    end
    local set = {}
    for _, ch in ipairs(B.EffectSoundChoices()) do set[#set + 1] = ch.label end
    T.Print("Effect sounds: " .. (#set > 0 and table.concat(set, "; ") or "none") .. ".")
    T.Print(c .. " [get|end] <name> = <file> gives one its own, when you get it or when it's about to run out (a"
      .. " file inside your Lua folder: toolbox_sounds/atos.ogg; without get or end: a debuff's when you get it, a"
      .. " buff's when it's about to run out); " .. c .. " test [get|end] <name> plays it; " .. c
      .. " remove [get|end] <name> takes it away. Names as in /" .. T.commands[1] .. " buffs quiet.")
    return
  end
  if word == "quiet" then
    local B, c = T.BuffBar, "/" .. T.commands[1] .. " buffs quiet"
    local verb, effect = T.ParseArgs(name)
    if verb == "add" or verb == "remove" then
      local _, msg = (verb == "add" and B.Mute or B.Unmute)(effect)
      T.Print(msg)
      return
    end
    local function named(n)                    -- "Blessing of Atos [Reward_Blessing_CastleAtos4_7]"
      local shown = B.ShownName(n)
      return shown ~= n and (shown .. " [" .. n .. "]") or n
    end
    local muted = {}
    for _, n in ipairs(B.MutedList()) do muted[#muted + 1] = named(n) end
    T.Print("Muted (no sound): " .. (#muted > 0 and table.concat(muted, ", ") or "none") .. ".")
    local recent = {}
    for _, n in ipairs(B.recent) do if not B.IsMuted(n) then recent[#recent + 1] = named(n) end end
    T.Print("Recent alerts: " .. (#recent > 0 and table.concat(recent, ", ") or "none yet") .. ".")
    T.Print(c .. " add <name> mutes one (either name, as above); " .. c .. " remove <name> unmutes it.")
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
  if word == "block" then
    local MB, c = T.BuffBlock, "/" .. T.commands[1] .. " buffs block"
    local verb, arg = T.ParseArgs(name)
    verb = verb:lower()
    if verb == "move" then
      T.MoveCommand(MB, "buffblock", "Buff block", arg)
      return
    elseif verb == "" then
      MB.SetShow(not MB.GetShow())
    elseif verb == "on" or verb == "off" then
      MB.SetShow(verb == "on")
    elseif verb == "combat" and (arg:lower() == "on" or arg:lower() == "off") then
      MB.SetCombatOnly(arg:lower() == "on")
    elseif verb == "width" or verb == "size" then
      local ok = (verb == "width" and MB.SetWidth or MB.SetSize)(tonumber(arg))
      if not ok then
        local lo, hi = MB.WIDTH_MIN, MB.WIDTH_MAX
        if verb == "size" then lo, hi = T.BuffBar.SIZE_MIN, T.BuffBar.SIZE_MAX end
        T.Print("Use " .. c .. " " .. verb .. " <" .. lo .. "-" .. hi .. ">.")
        return
      end
    else
      T.Print("Use " .. c .. " [on|off], width <n>, size <n>, combat on|off or move [x y].")
      return
    end
    T.Print("Buff block: " .. (MB.GetShow() and "on" or "off") .. ", " .. MB.GetWidth() .. " icons a row, size "
      .. MB.GetSize() .. (MB.GetCombatOnly() and ", only during combat" or "") .. ".")
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
  if word == "tips" then
    for _, line in ipairs(T.BuffBar.TipLines(name)) do T.Print(line) end
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
-- The readable character stats whose internal name or label contains `filter` (any case; "" = all):
-- { name, label, value } in the game's order, at most `max`. Also returns how many matched in all and how
-- many matching ones are hidden from add-ons. Used by the settings' stat picker.
function T.StatMatches(filter, max)
  filter = (filter or ""):lower()
  local out, total, hidden = {}, 0, 0
  local count = ShroudGetStatCount() or 0
  for i = 0, count - 1 do
    local name = ShroudGetStatNameByNumber(i)
    local label = ShroudGetStatDescriptionByNumber(i)
    name = type(name) == "string" and name or ""
    label = type(label) == "string" and label or ""
    if name ~= "" and (filter == "" or name:lower():find(filter, 1, true) or label:lower():find(filter, 1, true)) then
      if ShroudIsStatVisible(i) then
        total = total + 1
        if #out < max then out[#out + 1] = { name = name, label = label, value = ShroudGetStatValueByNumber(i) } end
      else
        hidden = hidden + 1
      end
    end
  end
  return out, total, hidden
end

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

add("vitals", "health, focus & Vigor bars (size; text|bars|vigor|replace on|off; bg; flash <%>|off|test; glue on|off; "
    .. "move)",
    function(rest)
  local word, args = T.ParseArgs(rest)
  local V = T.Vitals
  if word == "replace" then
    local a = args:lower()
    if (a == "on" or a == "off") and not V.SetReplace(a == "on") then
      T.Print("This game client can't hide its own health bars for add-ons (it needs Lua API 28).")
      return
    end
    T.Print("Replace the game's health bars: " .. (V.GetReplace() and "on" or "off") .. ".")
    return
  end
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
    "  " .. c .. "combat size 150 - scale it (75-250% of the text size)",
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
  elseif word == "shout" then
    local CS, a = T.CombatShout, args:lower()
    local verb, which = T.ParseArgs(a)
    if verb == "on" or verb == "off" then
      CS.SetOn(verb == "on")
    elseif verb == "test" and CS.KINDS[which] then
      CS.Shout(which, true)
      return
    elseif verb ~= "" then
      T.Print("Use /" .. T.commands[1] .. " combat shout on|off, or test block|parry|dodge.")
      return
    end
    T.Print("Block, parry & dodge shouts: " .. (CS.GetOn() and "on" or "off") .. ".")
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

add("target", "your target's health and effects (on|off; toolbelt on|off; place top|bottom: in the Toolbelt; "
    .. "mirror on|off; effects all|debuffs|none; icons <1-8>; text|bars|name on|off; bg; flash <%>|on|off|test; "
    .. "pet on|off; move [x y]; debug)", function(rest)
  local TG = T.Target
  local word, args = T.ParseArgs(rest)
  word = word:lower()
  if word == "on" or word == "off" then
    TG.SetShow(word == "on")
  elseif word == "toolbelt" then
    if args:lower() == "on" or args:lower() == "off" then TG.SetGlue(args:lower() == "on") end
  elseif word == "debug" then
    for _, line in ipairs(TG.DebugLines()) do T.Print(line) end
    return
  elseif word == "effects" then
    if not TG.SetEffects(args:lower()) then
      T.Print("Use /" .. T.commands[1] .. " target effects all|debuffs|none.")
      return
    end
  elseif word == "icons" then
    if not TG.SetIcons(tonumber(args)) then
      T.Print("Use /" .. T.commands[1] .. " target icons <1-" .. TG.SLOTS .. ">.")
      return
    end
  elseif word == "mirror" then
    if args:lower() ~= "on" and args:lower() ~= "off" then
      T.Print("Use /" .. T.commands[1] .. " target mirror on|off (bars fill from the right; in the Toolbelt, "
        .. "left of your health bars).")
      return
    end
    TG.SetMirror(args:lower() == "on")
  elseif word == "place" then
    if not TG.SetPlace(args:lower()) then
      T.Print("Use /" .. T.commands[1] .. " target place top|bottom (where it goes in the Toolbelt).")
      return
    end
  elseif word == "name" then
    local a = args:lower()
    if a ~= "on" and a ~= "off" then
      T.Print("Use /" .. T.commands[1] .. " target name on|off (the target's name above its bars).")
      return
    end
    TG.SetShowName(a == "on")
    T.Print("Target's name above the bars: " .. (TG.GetShowName() and "on" or "off")
      .. ((TG.GetShowName() and not TG.InfoShown()) and " (it shows with the bars or the numbers on)" or "") .. ".")
    return
  elseif word == "text" or word == "bars" then
    local a = args:lower()
    if a ~= "on" and a ~= "off" then
      T.Print("Use /" .. T.commands[1] .. " target " .. word .. " on|off.")
      return
    end
    if word == "text" then TG.SetShowText(a == "on") else TG.SetShowBars(a == "on") end
    T.Print("Target bars: " .. (TG.GetShowBars() and "on" or "off") .. "; numbers: "
      .. (TG.GetShowText() and "on" or "off") .. ".")
    return
  elseif word == "pet" then
    local a = args:lower()
    if a == "on" or a == "off" then
      TG.SetHidePet(a == "off")
    elseif a ~= "" then
      T.Print("Use /" .. T.commands[1] .. " target pet on|off (off: your pet as the target isn't shown).")
      return
    end
    T.Print("Your pet as the target: " .. (TG.GetHidePet() and "left out" or "shown") .. ".")
    return
  elseif word == "bg" then
    if args ~= "" and not TG.SetBackground(args) then
      T.Print("Backgrounds: " .. table.concat(T.Vitals.BackgroundNames(), ", ") .. ".")
      return
    end
    T.Print("Target number background: " .. TG.GetBackground() .. ".")
    return
  elseif word == "flash" then
    local a = args:lower()
    if a == "test" then
      TG.PreviewFlash()
      return
    end
    if a == "on" or a == "off" then
      TG.SetFlash(a == "on")
    elseif a ~= "" then
      if not TG.SetFlashBelow(tonumber(a)) then
        T.Print("Use /" .. T.commands[1] .. " target flash <" .. T.Vitals.FLASH_MIN .. "-" .. T.Vitals.FLASH_MAX
          .. ">, on, off or test.")
        return
      end
      TG.SetFlash(true)
    end
    T.Print("Target flash when low: " .. (TG.GetFlash() and ("on, below " .. TG.GetFlashBelow() .. "%") or "off")
      .. ".")
    return
  elseif word == "move" then
    T.MoveCommand(TG, "target", "Target HUD", args)
    return
  elseif word ~= "" then
    T.Print("Use /" .. T.commands[1] .. " target on|off, toolbelt on|off, place top|bottom, mirror on|off, "
      .. "text|bars on|off, bg, flash, move [x y] or debug.")
    return
  end
  T.Print("Target HUD: " .. (TG.GetShow() and "on" or "off")
    .. (TG.GetShow() and (TG.Glued() and (", in the Toolbelt, " .. TG.PLACES[TG.Place()]:lower())
      or (", its own strip" .. (TG.GetMirror() and ", mirrored" or ""))) or "")
    .. (TG.GetShow() and TG.GetGlue() and not T.BuffBar.IsEnabled() and " (the Toolbelt is off)" or "")
    .. (TG.GetShow() and ("; effects: " .. TG.EFFECT_LABELS[TG.GetEffects()]:lower()
      .. (TG.GetEffects() ~= "none" and (", up to " .. TG.GetIcons()) or "")) or "") .. ".")
end)

add("welcome", "show the first-run welcome again (reset: show it at the next /lua reload)", function(rest)
  if rest:lower() == "reset" then
    T.DeleteSaved("welcomed", "account")
    T.Print("The welcome will show again at the next /lua reload or login.")
    return
  end
  T.DeleteSaved("welcomed", "account")
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
      .. (T.Notify.ChoiceLabel(src.key) ~= "Window" and (" (" .. T.Notify.ChoiceLabel(src.key) .. ")") or "")
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

add("notify", "notifications: list; <name> on|off; [<name>] via window|hud|chat; [<name>] sound on|off; "
    .. "compact on|off; show; hud",
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
  if word == "compact" then
    local a = arg:lower()
    if a == "on" or a == "off" then T.Notify.SetCompact(a == "on") end
    T.Print("Compact Notifications window: " .. (T.Notify.GetCompact() and "on" or "off") .. ".")
    return
  end
  if word == "via" or (T.Notify.Label(word) and arg:lower():match("^via%s")) then
    local via = (word == "via" and arg or arg:match("^%S+%s+(.*)$") or ""):lower()
    if not T.Notify.ViaLabel(via) then
      T.Print("Use " .. c .. " [<name>] via window|hud|chat.")
      return
    end
    if word ~= "via" and not T.Notify.Allows(word, via) then
      T.Print(T.Notify.Label(word) .. " can only show " .. T.Notify.AllowedText(word) .. ".")
      return
    end
    for _, src in ipairs(T.Notify.Sources()) do
      if word == "via" or src.key == word then T.Notify.SetVia(src.key, via) end   -- refused where not allowed
    end
    local where = { hud = "in the notification HUD.", chat = "in chat.", window = "in the Notifications window." }
    T.Print((word == "via" and "All notifications" or T.Notify.Label(word)) .. " now show " .. where[via])
    return
  end
  if word == "sound" or (T.Notify.Label(word) and arg:lower():match("^sound%s")) then
    local onoff = (word == "sound" and arg or arg:match("^%S+%s+(.*)$") or ""):lower()
    local soundKey = nil
    for _, snd in ipairs(T.Notify.SOUNDS) do
      if snd[1] == onoff or snd[2]:lower() == onoff then soundKey = snd[1] end
    end
    if onoff ~= "on" and onoff ~= "off" and not soundKey then
      local names = {}
      for _, snd in ipairs(T.Notify.SOUNDS) do names[#names + 1] = snd[2]:lower() end
      T.Print("Use " .. c .. " [<name>] sound on|off, or a sound: " .. table.concat(names, ", ") .. ".")
      return
    end
    for _, src in ipairs(T.Notify.Sources()) do
      if word == "sound" or src.key == word then
        if soundKey then T.Notify.SetSoundKey(src.key, soundKey) end
        T.Notify.SetSound(src.key, onoff ~= "off")
      end
    end
    T.Print((word == "sound" and "All notifications" or T.Notify.Label(word))
      .. (onoff == "off" and " play no sound." or (" now play the "
        .. (soundKey and T.Notify.SoundLabel(soundKey):lower() or "notification") .. " sound.")))
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
T.DOCS_API = 44

function T.ApiLines()
  local function has(f) return type(f) == "function" end
  local function since(n) return type(ShroudLuaApiVersion) == "number" and ShroudLuaApiVersion >= n end
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
    { "Vitals (API 25)", { { "ShroudGetPlayerVitals", has(ShroudGetPlayerVitals) } } },
    { "Skill training (API 27)", {
      { "ShroudSetSkillMode", has(ShroudSetSkillMode) },
      { "ShroudCanSetSkillMode", has(ShroudCanSetSkillMode) } } },
    { "Player frame bars (API 28)", {
      { "ShroudSetPlayerVitalBarsVisible", has(ShroudSetPlayerVitalBarsVisible) },
      { "ShroudIsPlayerVitalBarsVisible", has(ShroudIsPlayerVitalBarsVisible) } } },
    { "Location (API 29)", {
      { "ShroudGetLocationText", has(ShroudGetLocationText) },
      { "ShroudFormatLocation", has(ShroudFormatLocation) } } },
    { "Map markers (API 30)", {
      { "ShroudSetMapMarker", has(ShroudSetMapMarker) },
      { "ShroudRemoveMapMarker", has(ShroudRemoveMapMarker) },
      { "ShroudClearMapMarkers", has(ShroudClearMapMarkers) },
      { "ShroudGetMapMarkers", has(ShroudGetMapMarkers) },
      { "ShroudListMapMarkerIcons", has(ShroudListMapMarkerIcons) } } },
    { "Screen (API 31)", { { "ShroudGetScreenInfo", has(ShroudGetScreenInfo) } } },
    { "Water (API 32)", {
      { "ShroudGetSceneWaterTypes", has(ShroudGetSceneWaterTypes) },
      { "ShroudGetNearestWaterType", has(ShroudGetNearestWaterType) } } },
    { "File picker (API 33)", { { "ShroudPickFile", has(ShroudPickFile) } } },
    { "Sound handles (API 34)", {
      { "ShroudLoadSoundHandle", has(ShroudLoadSoundHandle) },
      { "ShroudListSoundPaths", has(ShroudListSoundPaths) },
      { "ShroudGetSoundState", has(ShroudGetSoundState) } } },
    { "World calendar (API 35)", {
      { "ShroudGetCalendarEvents", has(ShroudGetCalendarEvents) },
      { "ShroudGetCalendarEvent", has(ShroudGetCalendarEvent) },
      { "ShroudGetCalendarSummary", has(ShroudGetCalendarSummary) },
      { "ShroudGetCalendarReminders", has(ShroudGetCalendarReminders) },
      { "ShroudGetCalendarTags", has(ShroudGetCalendarTags) } } },
    { "Recipe book (API 37)", { { "ShroudGetRecipeBook", has(ShroudGetRecipeBook) } } },
    -- API 38 adds callbacks and element methods, which can't be looked up without one: told by the version
    { "Window show / hide, FollowHeading, calendar now (API 38)", {
      { "API 38", since(38) } } },
    { "Saved-file backups (API 39)", {
      { "ShroudBackupSavedVars", has(ShroudBackupSavedVars) },
      { "ShroudListSavedVarBackups", has(ShroudListSavedVarBackups) },
      { "ShroudRestoreSavedVarBackup", has(ShroudRestoreSavedVarBackup) } } },
    { "Map title (API 40)", {
      { "ShroudSetMapTitle", has(ShroudSetMapTitle) },
      { "ShroudGetMapTitle", has(ShroudGetMapTitle) } } },
    -- API 41, 43 and 44 change limits, fields and callbacks: told by the version too
    { "30 windows, one item's weight and value (API 41)", { { "API 41", since(41) } } },
    { "Helmet (API 42)", {
      { "ShroudIsHelmetVisible", has(ShroudIsHelmetVisible) },
      { "ShroudSetHelmetVisible", has(ShroudSetHelmetVisible) },
      { "ShroudToggleHelmet", has(ShroudToggleHelmet) } } },
    { "Save before logout, no nochar file (API 43)", { { "API 43", since(43) } } },
    { "Plain item names (API 44)", { { "API 44", since(44) } } },
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
-- The craft / gather result events feed Loot Tracker's Crafted / Gathered views (daily.lua); this
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

-- ---------------------------------------------------------------------------
-- /toolbox perf (the 1.8.0 performance pass; owner, 2026-10-14: players report hitching, "not clear if it's the lua
-- engine or toolbox itself"). For a while, a periodic at the game's shortest period (0.01 s: about every frame below
-- 100 a second, not every frame above) reads ShroudRealDeltaTime, the real length of the frame before it, and looks
-- for Toolbox's work since the sample before: every Toolbox periodic (T.RegisterPeriodic) and core's callbacks call
-- T.Ran(what), kept in a small ring (T.PERF_RING, reused tables) of { at = ShroudTime, what }. So it tells
-- "Toolbox worked near this hitch", a correlation, not proof (review 46): a slow sample with no Toolbox work in its
-- interval points to the game or another add-on. Memory only; nothing saved.
-- ---------------------------------------------------------------------------
T.PERF_ID = "toolbox_perf"
T.PERF_SLOW = 0.05                    -- s: a frame this long is a hitch you notice (three at 60 a second)
T.PERF_BAD = 0.1
-- Below this many frames a second on average every frame is long and Toolbox's timers land in most of them, so
-- "near" says little (a player's run, 2026-10-22: 21 a second, 543 of 1,249 frames over 50 ms, Toolbox "near" 426):
-- the report says so, with the timers' timed share, and points to perf quiet (not after a quiet / only run).
T.PERF_LOW_RATE = 30
T.PERF_DEFAULT, T.PERF_MIN, T.PERF_MAX = 60, 10, 600
-- The sampler's period: the documented shortest first; the live client refused 0.01 (owner, 2026-10-14: "The game
-- refused the measuring timer"), perhaps as a single-precision 0.01 just under its limit, so a little longer next.
T.PERF_PERIODS = { 0.01, 0.0125, 0.02, 0.05 }
T.PERF_RING = 32                      -- marks kept: more than a frame holds (every periodic and a few callbacks)
local ring, ringAt = {}, 0
for i = 1, T.PERF_RING do ring[i] = { at = -math.huge, what = nil } end
local perf = nil

-- Timing (owner, 2026-10-14: "Allow os.clock", for /toolbox perf only): while perf measures and the sandbox has
-- os.clock (feature-detected, read plainly like os.date), every Toolbox periodic and the parts marked with
-- T.PerfT / T.PerfAdd are timed: runs, total, the longest and how many took over T.PERF_PART_SLOW. Nothing is timed
-- otherwise (T.PerfT returns nil).
T.PERF_PART_SLOW = 0.016                -- s: a 60-a-second frame's worth
local timing = nil
local function clockFn()
  local osTable = os
  local clock = type(osTable) == "table" and osTable.clock
  if type(clock) ~= "function" then return nil end
  return clock
end
function T.PerfT()
  if not timing then return nil end
  local ok, now = pcall(timing.clock)
  return ok and type(now) == "number" and now or nil
end
function T.PerfAdd(label, t0)
  if not (timing and t0) then return end
  local ok, now = pcall(timing.clock)
  if not ok or type(now) ~= "number" then return end
  local d = now - t0
  local e = timing.parts[label]
  if not e then
    e = { n = 0, sum = 0, max = 0, over = 0 }
    timing.parts[label] = e
  end
  e.n, e.sum = e.n + 1, e.sum + d
  if d > e.max then e.max = d end
  if d > T.PERF_PART_SLOW then e.over = e.over + 1 end
end

-- Toolbox is working now: noted for /toolbox perf (the same work twice in a frame once).
function T.Ran(what)
  local now = ShroudTime
  local last = ring[ringAt]
  if last and last.at == now and last.what == what then return end
  ringAt = ringAt % T.PERF_RING + 1
  local e = ring[ringAt]
  e.at, e.what = now, what
end

-- ShroudRegisterPeriodic for a Toolbox periodic, marked for /toolbox perf. A repeating one under a second gets its
-- own phase (T.PHASE_STEP apart, in the order first registered): the half-second ones all ran in the same frame,
-- and the owner's first /toolbox perf (2026-10-14, crafting at about 29 frames a second) found Toolbox near 24 of 28
-- hitches, each naming every half-second periodic. Its first run comes after its phase, by a one-shot of the same
-- name that then registers the repeating one (so removing the name stops either).
T.PHASE_STEP = 0.06
T.PHASE_EDGE = 0.05
local phases, phaseNext = {}, 0
local periodicRuns = {}               -- name -> { run, period }: the repeating ones, for /toolbox perf quiet

-- Toolbox's active timers' names. ShroudListPeriodics gives a MoonSharp enumerator that only a generic for walks (the
-- docs; T.List read it as empty in game, so perf quiet paused nothing, 2026-10-14); a plain list is taken too.
local function walkNames(list, out)
  for name in list do
    if type(name) == "string" then out[#out + 1] = name end
  end
end
function T.PeriodicNames()
  local out = {}
  if type(ShroudListPeriodics) ~= "function" then return out end
  local ok, list = pcall(ShroudListPeriodics)
  if not ok or list == nil then return out end
  if type(list) == "table" then
    for _, name in ipairs(list) do
      if type(name) == "string" then out[#out + 1] = name end
    end
  else
    pcall(walkNames, list, out)
  end
  return out
end
function T.RegisterPeriodic(name, fn, period, repeating)
  local function run()
    T.Ran(name)
    local t0 = T.PerfT()
    fn()
    T.PerfAdd(name, t0)
  end
  if repeating then periodicRuns[name] = { run = run, period = period } end
  if repeating and T.PerfHolds(name) then return true end   -- a quiet / only run: started at its report (review 47)
  if not repeating or period > 1 or period < 0.2 or name == PERIODIC then         -- (a short one: every few frames)
    return ShroudRegisterPeriodic(name, run, period, repeating)
  end
  if not phases[name] then
    phaseNext = phaseNext + 1
    phases[name] = phaseNext
  end
  -- kept T.PHASE_EDGE off the whole seconds (the tick's beat): with the half-second ones at 0.48 and 0.24, the
  -- second perf run put three periodics in each slow frame
  local phase = T.PHASE_EDGE + (phases[name] * T.PHASE_STEP) % (period - 2 * T.PHASE_EDGE)
  if phase < 0.01 then return ShroudRegisterPeriodic(name, run, period, true) end
  return ShroudRegisterPeriodic(name, function()
    ShroudRegisterPeriodic(name, run, period, true)
    return run()
  end, phase, false)
end

-- Stops a repeating timer for good: a quiet / only run doesn't start it again at its report (review 48: a
-- character switch dropped the recipe book's read while perf held its timer, and the report restored it).
function T.RemovePeriodic(name)
  periodicRuns[name] = nil
  local p = perf
  if p and p.paused then
    for i = #p.paused, 1, -1 do
      if p.paused[i] == name then table.remove(p.paused, i) end
    end
  end
  return pcall(ShroudRemovePeriodic, name)
end

-- The timing's lines: the timers, then the parts, the longest first (at most T.PERF_LINES of each).
T.PERF_LINES = 6
function T.PerfTimingLines(parts)
  local timers, inner = {}, {}
  for label, e in pairs(parts) do
    local row = { label = label, e = e }
    if label:find(":", 1, true) then inner[#inner + 1] = row else timers[#timers + 1] = row end
  end
  local function byMax(a, b) return a.e.max > b.e.max end
  table.sort(timers, byMax)
  table.sort(inner, byMax)
  local function ms(s) return string.format("%.1f", s * 1000) end
  local lines = {}
  local function addLine(title, rows)
    local bits = {}
    for i = 1, math.min(T.PERF_LINES, #rows) do
      local e = rows[i].e
      bits[#bits + 1] = string.format("%s %s ms at most, %s on average, %d over %d ms in %d", rows[i].label, ms(e.max),
        ms(e.sum / math.max(e.n, 1)), e.over, math.floor(T.PERF_PART_SLOW * 1000 + 0.5), e.n)
    end
    if #bits > 0 then lines[#lines + 1] = title .. table.concat(bits, "; ") .. "." end
  end
  addLine("Timed (os.clock), timers: ", timers)
  addLine("Their parts: ", inner)
  return lines
end

-- Whether a quiet / only run keeps this timer from running now (one registered meanwhile too: a character switch
-- rebuilds every module, review 47); it is noted to be started at the report.
function T.PerfHolds(name)
  local p = perf
  if not (p and p.filter) or name == T.PERF_ID then return false end
  if type(p.filter) == "table" then
    for _, part in ipairs(p.filter) do
      if name:find(part, 1, true) then
        local listed = false
        for _, n in ipairs(p.kept) do listed = listed or n == name end
        if not listed then p.kept[#p.kept + 1] = name end   -- the report names it among the ones that ran
        return false
      end
    end
  end
  for _, n in ipairs(p.paused) do
    if n == name then return true end
  end
  p.paused[#p.paused + 1] = name
  return true
end

local function perfReport()
  local p = perf
  perf = nil
  pcall(ShroudRemovePeriodic, T.PERF_ID)
  local timed = timing
  timing = nil
  if not p then return end
  if timed then
    for _, line in ipairs(T.PerfTimingLines(timed.parts)) do T.Print(line) end
  else
    T.Print("(This client's Lua has no os.clock, so the timers couldn't be timed.)")
  end
  for _, name in ipairs(p.paused or {}) do               -- quiet: Toolbox's timers back
    local r = periodicRuns[name]
    if r then pcall(ShroudRegisterPeriodic, name, r.run, r.period, true) end
  end
  local secs = math.max(ShroudTime - p.from, 0.001)
  local function share(n, of) return of > 0 and math.floor(n * 100 / of + 0.5) or 0 end
  T.Print(string.format("Toolbox perf, %d s: %s samples (%d a second, about one a frame below %d frames a second);"
    .. " %d %s over %d ms (%d over %d ms), the longest %d ms.", math.floor(secs + 0.5),
    T.FormatNumber(p.frames), math.floor(p.frames / secs + 0.5), math.floor(1 / p.period + 0.5), p.slow,
    p.slow == 1 and "frame took" or "frames took",
    math.floor(T.PERF_SLOW * 1000), p.bad, math.floor(T.PERF_BAD * 1000), math.floor(p.worst * 1000 + 0.5)))
  if p.paused and #(p.kept or {}) > 0 then
    T.Print("Only " .. table.concat(p.kept, ", ") .. " ran (Toolbox's other " .. #p.paused .. " timers were paused;"
      .. " they run again now): compare the count with /" .. T.commands[1] .. " perf quiet and a normal perf.")
  elseif p.paused then
    T.Print("Toolbox's " .. #p.paused .. " timers were paused while it measured (they run again now): hitches"
      .. " counted then weren't Toolbox's timers. Compare the count with a normal /" .. T.commands[1] .. " perf.")
  end
  local rate = p.frames / secs
  local lowRate = nil
  if rate < T.PERF_LOW_RATE and not p.paused then
    local spent = nil
    if timed then
      spent = 0
      for label, e in pairs(timed.parts) do
        if not label:find(":", 1, true) then spent = spent + e.sum end
      end
    end
    lowRate = string.format("Your game ran at about %d frames a second on average, so its frames were long and"
      .. " Toolbox's timers fell in most of them: \"near\" says little here.", math.floor(rate + 0.5))
      .. (spent and string.format(" Its timers' own work took %d ms of the %d s (%s%%), but the game's drawing after"
      .. " them isn't timed.", math.floor(spent * 1000 + 0.5), math.floor(secs + 0.5),
      string.format("%.1f", spent * 100 / secs)) or "")
      .. " Compare with /" .. T.commands[1] .. " perf quiet: if the frame rate rises with Toolbox's timers paused,"
      .. " they're the cause."
  end
  if p.slow == 0 then
    T.Print("No hitches while it measured.")
    if lowRate then T.Print(lowRate) end
    return
  end
  local names = {}
  for what, n in pairs(p.whats) do names[#names + 1] = what .. (n > 1 and (" x" .. n) or "") end
  table.sort(names)
  T.Print(string.format("Toolbox was working near %d%% of all samples, and near %d of the %d hitches%s. Hitches with"
    .. " no Toolbox work near them point to the game or another add-on.", share(p.ours, p.frames), p.slowOurs, p.slow,
    #names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""))
  if lowRate then T.Print(lowRate) end
end

local function perfSample()
  local p = perf
  if not p then return end
  local now, dt = ShroudTime, ShroudRealDeltaTime
  if type(now) ~= "number" or now == p.last then return end
  local from = p.last                                   -- dt is the last frame of [from, now)
  p.last = now
  if type(dt) ~= "number" then return end
  p.frames = p.frames + 1
  local slow = dt > T.PERF_SLOW
  local near = false
  for i = 1, T.PERF_RING do
    local e = ring[i]
    if e.at >= from and e.at < now then
      near = true
      if not slow then break end
      if p.named[e.what] ~= p.frames then               -- once a sample
        p.named[e.what] = p.frames
        p.whats[e.what] = (p.whats[e.what] or 0) + 1
      end
    end
  end
  if near then p.ours = p.ours + 1 end
  if dt > p.worst then p.worst = dt end
  if slow then
    p.slow = p.slow + 1
    if dt > T.PERF_BAD then p.bad = p.bad + 1 end
    if near then p.slowOurs = p.slowOurs + 1 end
  end
  if now - p.from >= p.secs then perfReport() end
end

-- Starts measuring for `secs` seconds (T.PERF_MIN..T.PERF_MAX); false when the game refused the periodic. `quiet`:
-- Toolbox's repeating timers are paused meanwhile (the owner's perf runs, 2026-10-14: the hitch count stayed about
-- 25 a minute however Toolbox's work was spread, so the A/B: is it there with Toolbox idle?).
-- `quiet` = true pauses them all, or a list of name parts ({ "tick" }) pauses all but those (/toolbox perf only).
function T.PerfStart(secs, quiet)
  perf = { from = ShroudTime, secs = secs, last = ShroudTime, frames = 0, ours = 0, slow = 0, bad = 0, slowOurs = 0,
           worst = 0, whats = {}, named = {} }
  for _, period in ipairs(T.PERF_PERIODS) do
    if ShroudRegisterPeriodic(T.PERF_ID, perfSample, period, true) then
      perf.period = period
      local clock = clockFn()
      timing = clock and { clock = clock, parts = {} } or nil
      if quiet then
        local paused = {}
        local kept = {}
        for _, name in ipairs(T.PeriodicNames()) do
          local keep = false
          for _, part in ipairs(type(quiet) == "table" and quiet or {}) do
            if name:find(part, 1, true) then keep = true end
          end
          if keep then
            kept[#kept + 1] = name
          elseif name ~= T.PERF_ID and periodicRuns[name] and ShroudRemovePeriodic(name) then
            paused[#paused + 1] = name
          end
        end
        perf.paused, perf.kept, perf.filter = paused, kept, quiet
      end
      return true
    end
  end
  perf = nil
  return false
end

function T.PerfRunning() return perf ~= nil end

add("perf", "measure hitches for a minute (perf <seconds>; perf stop): slow frames, and whether Toolbox worked in"
  .. " them; perf quiet: the same with Toolbox's timers paused", function(rest)
  local word = rest:lower()
  local quiet = (" " .. word .. " "):find(" quiet ", 1, true) ~= nil      -- "quiet", "quiet 30", "30 quiet"
  if quiet then word = T.Trim((word:gsub("quiet", ""))) end
  local first, more = T.ParseArgs(word)                                     -- "only tick location [30]"
  if first == "only" then
    local parts, secsWord = {}, ""
    for w in more:gmatch("%S+") do
      if tonumber(w) then secsWord = w else parts[#parts + 1] = w end
    end
    if #parts == 0 then
      T.Print("Which timers? /" .. T.commands[1] .. " perf only tick (or location, target, buffbar, vitals...): the"
        .. " others are paused.")
      return
    end
    quiet, word = parts, secsWord
  end
  if word == "stop" then
    if not perf then
      T.Print("Not measuring.")
    else
      perfReport()
    end
    return
  end
  if perf then                                          -- one at a time: a second start replaced the first unreported
    T.Print("Already measuring (" .. math.max(0, math.ceil(perf.secs - (ShroudTime - perf.from))) .. " s left)"
      .. (perf.paused and ", with Toolbox's timers paused" or "") .. ": wait for its report, or /" .. T.commands[1]
      .. " perf stop.")
    return
  end
  local secs = tonumber(word) or (word == "" and T.PERF_DEFAULT) or nil
  if not secs then
    T.Print("Usage: /" .. T.commands[1] .. " perf [seconds] (" .. T.PERF_MIN .. " to " .. T.PERF_MAX .. "), or perf"
      .. " stop.")
    return
  end
  secs = math.floor(math.max(T.PERF_MIN, math.min(T.PERF_MAX, secs)))
  if type(ShroudRealDeltaTime) ~= "number" then
    T.Print("This game client doesn't give add-ons the frame time (ShroudRealDeltaTime).")
    return
  end
  if not T.PerfStart(secs, quiet) then
    local n = #T.PeriodicNames()
    T.Print("The game refused the measuring timer (every period from " .. T.PERF_PERIODS[1] .. " to "
      .. T.PERF_PERIODS[#T.PERF_PERIODS] .. " s" .. (n and (", with " .. n .. " of Toolbox's timers running") or "")
      .. "). Please report it with /" .. T.commands[1] .. " version.")
    return
  end
  local kept = perf.kept or {}
  local onlyText = type(quiet) == "table" and #kept > 0 and (" with only " .. table.concat(kept, ", ") .. " running"
    .. " (Toolbox's other strips and windows stand still until then)") or nil
  if type(quiet) == "table" and not onlyText then
    T.Print("No timer matches " .. table.concat(quiet, ", ") .. " yet: Toolbox's others are paused, and one that"
      .. " starts meanwhile with that in its name runs (the recipe book's, once the planner reads it).")
  end
  local how = onlyText or (quiet and " with Toolbox's timers paused (its strips and windows stand still until then)")
    or ""
  T.Print("Measuring hitches for " .. secs .. " s" .. how .. ": play as usual (or stand where it hitches). /"
    .. T.commands[1] .. " perf stop ends it early.")
end)

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
  T.Print("Pressed " .. tostring(T.keyPresses or 0) .. " time(s) since Toolbox last started"
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
  T.Ran("command")
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
  T.session = T.XP.NewSession(T.Now(), adv, prod, T.PlayerName())
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
  local saved = T.ReadSaved("session")
  local now = T.Now()
  if T.XP.IsValid(saved)
      and not saved.ended
      and saved.clock <= now                       -- clock went backwards: client restarted
      and T.PlainName(saved.player) == T.PlayerName() then   -- (1.7.0 or before saved the tags)
    saved.player = T.PlainName(saved.player)
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
  local offset = T.session.offset
  local la, lp = offset and offset.a or 0, offset and offset.p or 0
  if T.XP.Record(T.session, T.Now(), adv, prod) then T.unsaved = true end
  offset = T.session.offset
  if (offset and offset.a or 0) ~= la or (offset and offset.p or 0) ~= lp then
    T.SaveSession(false)               -- XP lost (a death): stored now, so a reload keeps it apart from gains
  end
end

-- Every window that shows session data.
function T.RefreshViews()
  T.Window.Refresh()
  T.Compact.Refresh()
  T.Daily.Refresh()
  T.DailyDetail.Refresh()
end

function T.Tick()
  local t0 = T.PerfT()
  T.FollowCharacter()                -- first: nothing may save the last character's settings into this one
  T.PerfAdd("tick:character", t0)
  t0 = T.PerfT()
  local s = T.session
  local adv, prod = T.ReadTotals()   -- once a tick (it was read twice: review, 2026-09-29)
  T.PerfAdd("tick:XP totals", t0)
  t0 = T.PerfT()
  if not s then
    T.ResumeOrStart()                -- no character yet when the add-on started
  elseif s.ended then
    T.StartSession("login")          -- logged out and back in without a restart
  elseif s.player ~= T.PlayerName() and adv then
    T.StartSession("character")
  else
    T.Sample(adv, prod)
  end
  T.PerfAdd("tick:session", t0)
  t0 = T.PerfT()
  T.Daily.Tick(adv ~= nil)
  T.PerfAdd("tick:day", t0)
  t0 = T.PerfT()
  -- A changed session is stored only as it goes to disk, at most every flushSeconds (and at shutdown / logout):
  -- each store copies and checks up to an hour of samples, about 160 KB of garbage an hour into a session (the
  -- 1.8.0 performance pass; it was every tick with XP, the bulk of Toolbox's garbage in a long fight). A reload
  -- re-reads the totals, so it loses no XP, at most the chart's last samples.
  -- The flush's work is spread over T.FLUSH_STEPS ticks ending flushSeconds after the last (the owner's timed perf,
  -- 2026-10-14: all of it in one tick took up to 44 ms): the session, the day, the setup copy, the recovery copy,
  -- then the game's write.
  local due = (T.unsaved or T.unflushed or T.setupDirty)
    and T.Now() - T.lastFlush >= T.flushSeconds - (T.FLUSH_STEPS - 1) * T.tickSeconds
  if T.flushStep or due then
    T.flushStep = (T.flushStep or 0) + 1
    local step = T.flushStep
    if step == 1 then
      if T.unsaved then T.SaveSession(false) end
    elseif step == 2 then
      T.Daily.SaveIfChanged()
    elseif step == 3 then
      if T.setupDirty then T.Backup.KeepCopy() end
    elseif step == 4 then
      if T.recoveryDirty then T.Backup.KeepRecovery() end
    else                                                    -- (what changed meanwhile goes with the next one)
      T.Flush()
      T.lastFlush = T.Now()
      T.unflushed = false
      T.flushStep = nil
    end
  end
  T.PerfAdd("tick:flush", t0)
end

-- The polls, in a periodic of their own (toolbox_poll; the owner's fourth perf run still put the tick near 13
-- hitches a minute): sounds loading, prices, worn gear, notifications.
function T.PollTick()
  T.FollowCharacter()
  T.Sounds.Poll()
  T.Prices.Tick()                    -- estimated values: the next SotANET lookup, when due
  T.Gear.Tick()                      -- worn gear's durability, every Gear.POLL seconds
  -- Notifications: the game's change callbacks catch changes; this is the fallback for data that
  -- loads after login without one: every second for the first T.NOTIFY_EARLY seconds after start,
  -- then every T.NOTIFY_POLL seconds.
  local early = T.Now() - (T.startedAt or 0) < T.NOTIFY_EARLY
  if early or T.Now() - (T.lastNotifyPoll or -math.huge) >= T.NOTIFY_POLL then
    T.lastNotifyPoll = T.Now()
    T.Notify.Check(early)              -- after the first minute, on the game's readings as last read (N.CONTEXT_EVERY)
  end
end

-- The rest of the once-a-second work, in two periodics of their own (each at its own phase, T.RegisterPeriodic): the
-- owner's /toolbox perf (2026-10-14) found 10 of the tick's 60 runs a minute in a hitch when it did all of it.
-- Where the windows and strips are (positions read from the UI, which may lay it out).
function T.TrackTick()
  T.FollowCharacter()                -- first, as in T.Tick: never save one character's places into another's
  T.Window.Track()
  T.Compact.Track()
  T.Daily.Track()
  T.DailyDetail.Track()
  T.Hud.Tick()                       -- remember where the HUD strips are
end

-- What the windows, the settings page and the map show.
function T.ViewsTick()
  T.FollowCharacter()
  T.DailyDetail.SyncMarkers()         -- Loot Tracker runs on the map (API 30), on a change only
  T.Overlays.DeathTick()              -- your last death clears itself (back there, or old and elsewhere)
  T.Overlays.Sync()                   -- the shown map overlay's places (API 30), on a change only
  T.Overlays.SyncTitle()              -- the map's title line naming them (API 40), on a change only
  T.Overlays.Tick()                   -- the Map overlays window follows a scene change
  T.Planner.Tick()                    -- the crafting planner follows your bags and crafts
  T.Config.SyncLive()
  T.RefreshViews()
  T.Notify.Hud.Tick()                -- the notification HUD's auto-hide
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
  T.SetSavedVar("welcomed", true, "account")
  -- A moment later: start-up has just built every window and HUD strip, and the settings window's
  -- ~180 elements on top could pass the game's element-creation cap (2026-09-28).
  T.RegisterPeriodic("toolbox_welcome", function() T.Config.Open() end, T.WELCOME_DELAY, false)
  return true
end

-- What's new (owner, 2026-10-14): the first start of a new version on this install (account scope, `version_seen`)
-- opens the version window, a moment later as the welcome's settings window. A new install (the welcome) only
-- notes the version. Returns true when it showed.
T.VERSION_SEEN = "version_seen"
function T.WhatsNew(welcomed)
  if ShroudGetSavedVar(T.VERSION_SEEN, "account") == T.version then return false end
  T.SetSavedVar(T.VERSION_SEEN, T.version, "account")
  if welcomed then return false end
  local kept = T.Backup.updateBackups
  T.Print("Toolbox is now " .. T.version .. ": the version window shows what's new (/" .. T.commands[1]
    .. " version)." .. (kept and (" Copies of your saved files from before were kept in Lua/SavedVariables ("
    .. table.concat(kept, ", ") .. ").") or "") .. (T.Backup.updateWhy and (" The game didn't keep a copy of every"
    .. " file (" .. T.Backup.updateWhy .. ").") or ""))
  T.RegisterPeriodic("toolbox_whatsnew", function() T.Docs.OpenVersion() end, T.WELCOME_DELAY, false)
  return true
end

-- ---------------------------------------------------------------------------
-- Settings files and reset (/toolbox settings, settings window: Backup & reset)
-- ---------------------------------------------------------------------------
-- Backups are the player's own copies of the game's saved-variable files (add-ons can't write files, and a
-- backup inside a saved var would eat into its 256 KB): per the docs, Lua/SavedVariables/<addon>.<character>
-- .character.json (one per character: settings, positions, stats) and <addon>.account.json (shared). The page
-- and the command say where they are and how to copy them back; "Save now" writes them first.
-- Reset doesn't change anything while Toolbox runs: the windows write their positions again at shutdown
-- (ShroudOnDisableScript / ShroudOnLogOut), and every module holds its settings in memory. It leaves an
-- instruction (B.PENDING, character scope) that ShroudOnStart carries out before any module reads its
-- settings; the player types /lua reload.
local B = {}
T.Backup = B
B.PENDING = "settings_pending"     -- character scope: { kind = "reset" }
-- The settings and positions a reset clears (stats, the XP session, histories and learned data stay).
B.KEYS = { "window", "compact", "daily_window", "daily_detail", "buffbar", "sounds", "vitals", "hud", "combat",
           "combat_detail", "consumables", "gear", "target", "notify", "notify_hud" }

-- Writes where every window and strip is now (the windows track their positions once a second, and write
-- some prefs only at shutdown). For "Save now" and the shutdown callbacks.
function T.SavePrefs()
  T.Window.Track()
  T.Compact.Track()
  T.Daily.Track()
  T.DailyDetail.Track()
  T.Combat.Detail.Track()
  T.Hud.Tick()
  T.Overlays.SavePending(true)       -- the auto map's unsaved marks
  T.Window.SavePrefs()
  T.Compact.SavePrefs()
  T.Daily.SavePrefs()
  T.DailyDetail.SavePrefs()
end

-- Everything to disk now, so a copy of the files is up to date. Returns the flush's answer.
function B.SaveNow()
  pcall(T.SavePrefs)
  if T.session then T.SaveSession(false) end
  T.Daily.Save()
  return T.Flush()
end

-- The folder the files are in: ShroudLuaPath (the docs: "absolute path to the addon's Lua folder") plus
-- SavedVariables, or the relative path when the client doesn't give it.
function B.Folder()
  local base = ShroudLuaPath
  if type(base) ~= "string" or base == "" then return "Lua/SavedVariables" end
  local sep = base:find("\\", 1, true) and "\\" or "/"
  if base:sub(-1) == sep then return base .. "SavedVariables" end
  return base .. sep .. "SavedVariables"
end

-- How to back up and restore, for the settings page and /toolbox settings.
-- The files are <addon>.<character>.character.json and <addon>.account.json (the docs); <addon> is "toolbox"
-- (confirmed in game 2026-09-30: toolbox.shawn.character.json).
B.FILE_PREFIX = "toolbox"

-- This character's file name ("toolbox.<name>.character.json"; "<character>" when there is no name yet).
function B.CharacterFile()
  local name = T.PlayerName()
  if type(name) ~= "string" or name == "" or name == "INVALID" or name == "None" then name = "<character>" end
  return B.FILE_PREFIX .. "." .. name .. ".character.json"
end

function B.HowTo()
  return {
    "Toolbox's settings are in the game's saved-variable files, in " .. B.Folder() .. ":",
    "  " .. B.CharacterFile() .. " (this character's settings, positions and stats; each character has its"
      .. " own) and " .. B.FILE_PREFIX .. ".account.json (shared by all your characters).",
    "To back up: Save now, then copy those files somewhere safe (keep a copy per setup you want to test).",
    "To restore, or to move to another computer: quit the game first (it writes the files as it closes),"
      .. " copy your saved files back into that folder, then start the game.",
  }
end

-- The waiting reset, or nil.
function B.Pending()
  local p = ShroudGetSavedVar(B.PENDING, SCOPE)
  if type(p) ~= "table" or p.kind ~= "reset" then return nil end
  return p
end

-- The game's backups (API 39; owner, 2026-10-15): a copy of a saved file as it is ON DISK (the last save) to
-- "<file>.<yyyyMMdd-HHmmss>" beside it in Lua/SavedVariables, the newest 5 kept, one a minute a file. Taken before
-- what could lose settings: a reset (B.ApplyPending), an import (B.Import) and the first start of a new version
-- (B.UpdateBackup: the account file and the first character's). Returns the backup's name, or nil (an older
-- client, nothing saved yet, or refused: the change goes ahead anyway; the recovery copies stay for older clients).
-- B.backupWhy: the game's reason when the last one wasn't kept (its word, or the error), for the note and the
-- debug command (owner, 2026-10-16: no copy was made in game and nothing said why).
B.backupWhy = nil
function B.HasBackups() return type(ShroudBackupSavedVars) == "function" end
function B.KeepBackup(scope)
  B.backupWhy = nil
  if not B.HasBackups() then return nil end
  local ok, done, name = pcall(ShroudBackupSavedVars, scope or SCOPE)
  if ok and done == true and type(name) == "string" and name ~= "" then return name end
  if not ok then
    B.backupWhy = "error " .. tostring(done)
  else
    B.backupWhy = tostring(done) .. " " .. tostring(name)
  end
  return nil
end

-- The game's reasons in words (the reference's).
B.BACKUP_REASONS = {
  noAddon = "the game didn't take the call as Toolbox's",
  noFile = "nothing saved yet",
  rateLimited = "the game keeps one a minute, and one was just made",
  diskError = "the copy couldn't be written",
}

-- "A copy of the file was kept first (name, in Lua/SavedVariables)."; when the game kept none, why; or "" on a
-- client without backups.
function B.BackupNote(name)
  if not name then
    if not B.HasBackups() or not B.backupWhy then return "" end
    local word = B.backupWhy:match("^false (%a+)$")
    return " The game kept no copy of the file first (" .. (word and B.BACKUP_REASONS[word] or B.backupWhy) .. ")."
  end
  return " A copy of the file from before was kept: " .. name .. " (in Lua/SavedVariables)."
end

-- /toolbox settings backup: the files written now, a copy of each tried, and the game's raw answers and lists.
function B.BackupLines()
  if not B.HasBackups() then return { "This game client can't keep backups (needs Lua API 39)." } end
  local out = {}
  local flushed = T.Flush()
  out[#out + 1] = "Backups: the files written first (" .. tostring(flushed ~= false) .. ")."
  for _, scope in ipairs({ SCOPE, ACCOUNT }) do
    local name = B.KeepBackup(scope)
    out[#out + 1] = "  " .. scope .. ": " .. (name and ("true " .. name) or tostring(B.backupWhy))
    if type(ShroudListSavedVarBackups) == "function" then
      local ok, rows, why = pcall(ShroudListSavedVarBackups, scope)
      if not ok then
        out[#out + 1] = "    list: error " .. tostring(rows)
      elseif type(rows) ~= "table" then
        out[#out + 1] = "    list: " .. tostring(rows) .. " " .. tostring(why)
      else
        out[#out + 1] = "    " .. #rows .. " kept, newest first:"
        for _, r in ipairs(rows) do
          out[#out + 1] = "    " .. tostring(T.Field(r, "name")) .. ", " .. tostring(T.Field(r, "size")) .. " bytes"
        end
      end
    end
  end
  return out
end

-- Back up now and Restore (owner, 2026-10-16): the player's own copies, and putting this character's file back
-- from one. Only the character file is restored: the account file holds every character's setups.
function B.CanRestore()
  return B.HasBackups() and type(ShroudListSavedVarBackups) == "function"
    and type(ShroudRestoreSavedVarBackup) == "function"
end

-- "2026-10-16 06:12" from a backup's name (its stamp is the local time it was made), else the name.
function B.BackupWhen(name)
  local y, mo, d, h, mi = tostring(name):match("%.(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)%d%d$")
  if not y then return tostring(name) end
  return y .. "-" .. mo .. "-" .. d .. " " .. h .. ":" .. mi
end

-- This character's file's copies, newest first: { { name, label, size } }; and why there are none (nil: none).
function B.BackupList()
  if not B.CanRestore() then return {}, "needs Lua API 39" end
  local ok, rows, why = pcall(ShroudListSavedVarBackups, SCOPE)
  if not ok then return {}, tostring(rows) end
  if type(rows) ~= "table" then return {}, tostring(why) end
  local out = {}
  for _, r in ipairs(rows) do
    local name = T.Field(r, "name")
    if type(name) == "string" and name ~= "" then
      local size = T.Field(r, "size")
      local kb = type(size) == "number" and size > 0 and math.max(1, math.floor(size / 1024 + 0.5)) or nil
      out[#out + 1] = { name = name, size = size,
        label = B.BackupWhen(name) .. (kb and (", " .. kb .. " KB") or "") }
    end
  end
  return out, nil
end

-- Back up now: the files written first, then a copy of each. Returns the character file's copy (or nil and why)
-- and the account file's (or nil).
function B.BackupNow()
  if B.SaveNow() == false then                -- the game copies the file on disk (review 53)
    return nil, "the game couldn't write the settings to disk first, so a copy wouldn't hold them", nil
  end
  local name = B.KeepBackup(SCOPE)
  local why = B.backupWhy
  local account = B.KeepBackup(ACCOUNT)
  return name, why, account
end

-- Puts this character's file back from the copy `name` (one of B.BackupList's): the file as it is now is written
-- first, so the game's copy of it (which it keeps, `kept`) holds the latest settings and the restore can be undone.
-- Every module then reads its settings again, as at a login; today's stats and the XP session carry on from memory.
-- A reset waiting in the copy (the reset's own backup has one) is dropped. Returns true and the kept copy's name
-- (nil when none), or false and why.
function B.Restore(name)
  if not B.CanRestore() then return false, "this game client can't restore (needs Lua API 39)" end
  if B.SaveNow() == false then                -- else the copy of the file replaced misses them (review 53)
    return false, "the game couldn't write the current settings to disk first, so nothing was restored"
  end
  local ok, done, kept = pcall(ShroudRestoreSavedVarBackup, SCOPE, name)
  if not ok then return false, "error " .. tostring(done) end
  if done ~= true then
    local word = tostring(kept)
    local words = { notFound = "that copy is gone", tooBig = "that copy is over the 256 KB a saved file may be",
      unreadable = "the game can't read that copy", rateLimited = "the game restores one a minute: try again soon",
      badName = "that isn't one of this character's copies", diskError = "the file couldn't be written",
      noAddon = "the game didn't take the call as Toolbox's" }
    return false, words[word] or word
  end
  local hadPending = ShroudGetSavedVar(B.PENDING, SCOPE) ~= nil
  if hadPending then T.DeleteSaved(B.PENDING, SCOPE) end
  T.settingsFor = false                -- read every module's settings again, as at a login
  T.FollowCharacter()
  kept = type(kept) == "string" and kept ~= "" and kept or nil
  -- on disk now: the reset waiting in an older copy must not come back at a restart (review 51)
  if T.Flush() == false then
    return true, kept, hadPending and "but the game couldn't write the file yet: if the game closes now, the reset"
      .. " in that copy may still happen" or "but the game couldn't write the file yet"
  end
  return true, kept
end

-- From ShroudOnStart, before anything is changed: the first start of a new version on an install that ran Toolbox
-- before (not a new one: no "welcomed") backs up the account file and this character's. The names, for T.WhatsNew.
function B.UpdateBackup()
  B.updateBackups = nil
  B.updateWhy = nil
  B.updateAccount = nil
  if ShroudGetSavedVar(T.VERSION_SEEN, ACCOUNT) == T.version or ShroudGetSavedVar("welcomed", ACCOUNT) == nil then
    return
  end
  local kept, why = {}, nil
  for _, scope in ipairs({ SCOPE, ACCOUNT }) do
    local name = B.KeepBackup(scope)           -- nil for a file never saved (a character's first start)
    if name then
      kept[#kept + 1] = name
      if scope == ACCOUNT then B.updateAccount = true end
    elseif B.backupWhy and B.backupWhy ~= "false noFile" then
      why = B.backupWhy
    end
  end
  if #kept > 0 then B.updateBackups = kept end
  B.updateWhy = why
end

-- Asks for a reset at the next start. Returns true, or false and why (the game refused to store the request,
-- or to write it to disk: then it may not survive to the next start).
-- With the game's backups (review 51): the settings are written and copied BEFORE the request is stored, so the copy
-- holds them and not the reset (restored by hand, it doesn't reset again); its name rides in the request, for the
-- line after the restart. Second value on success: the copy's name, or nil (B.backupWhy says why).
function B.RequestReset()
  local backup = nil
  B.backupWhy = nil
  if B.HasBackups() then
    if B.SaveNow() == false then
      return false, "the game couldn't write the settings to disk first, so no copy of them could be kept"
    end
    backup = B.KeepBackup(SCOPE)
  end
  local request = { kind = "reset" }
  if backup then request.backup = backup end
  if not T.SetSavedVar(B.PENDING, T.ForSaving(request), SCOPE) then
    return false, "the game refused to store the request"
  end
  if T.Flush() == false then return false, "the game couldn't write it to disk, so it may not happen" end
  return true, backup
end

-- Drops a waiting reset. Returns whether one was waiting, and false as a second value when the game
-- couldn't write the change to disk.
function B.Cancel()
  local had = B.Pending() ~= nil
  T.DeleteSaved(B.PENDING, SCOPE)
  return had, T.Flush() ~= false
end

-- ---------------------------------------------------------------------------
-- Setups: a character's settings and positions, copied into the account file (shared by every character on
-- this computer, whoever plays them) for another character to import (owner, 2026-10-04: "dad could copy
-- mom's settings to his own. so managed individually. but easily copied"). Each character's own copy is kept
-- up to date as it plays (B.KeepCopy, from T.Flush when a setting changed), so nobody has to export first; a
-- named one ("Raid layout") is exported on request. Importing copies one in now (T.Restart): never linked.
-- An add-on can't read another character's file, hence the copies.
B.SETUPS = "setups"         -- account: { v = 1, list = { { name, character = bool, when = "YYYY-MM-DD" } } }
B.SETUP_MAX = 20            -- named setups and character copies together
B.NAME_MAX = 24
-- "setup_share" (character scope, a setting: reset clears it): true when this character's copy is listed for the
-- others. Off by default (owner, 2026-10-04): nothing of a character's is shared until its player opts in.
-- Each character's own choice: never copied into a setup or imported.
B.SHARE = "setup_share"
B.KEYS[#B.KEYS + 1] = B.SHARE

local shareFor, share = nil, false  -- the choice, read once per character
function B.GetShare()
  if shareFor ~= T.settingsFor then
    shareFor, share = T.settingsFor, T.ReadSaved(B.SHARE) == true
  end
  return share
end

local settingSet = nil
function B.IsSetting(key)
  if not settingSet then                -- built at the first save: other files append to B.KEYS at load
    settingSet = {}
    for _, k in ipairs(B.KEYS) do settingSet[k] = true end
  end
  return settingSet[key] == true
end

-- A setup's saved-var key: the name in saved form (review 22: "Cafe" with an accent, "100%"). Over 128 characters
-- (B.NAME_MAX letters past 255, 6 characters each saved) the game won't take it: store says so.
local function setupKey(name, character)
  return (character and "setup_character:" or "setup:") .. T.ForSaving(name:lower())
end

-- Where setup `name` is saved: its key, or the plain-name key 1.6.0 used for a name with such letters, if only
-- that one is there.
local function foundSetupKey(name, character)
  local key = setupKey(name, character)
  local old = (character and "setup_character:" or "setup:") .. name:lower()
  if old ~= key and ShroudGetSavedVar(key, ACCOUNT) == nil and ShroudGetSavedVar(old, ACCOUNT) ~= nil then
    return old
  end
  return key
end

-- The setups' index as saved (names in saved form; 1.6.0's plain names read the same), and writing it.
local function readSetups() return T.FromSaved(ShroudGetSavedVar(B.SETUPS, ACCOUNT)) end
local function writeSetups(list) return T.SetSavedVar(B.SETUPS, T.ForSaving({ v = 1, list = list }), ACCOUNT) end

-- A name as typed, made safe for a key and short enough to show: nil when nothing is left.
function B.CleanName(text)
  if type(text) ~= "string" then return nil end
  local name = T.Trim((text:gsub("[%c/\\]", " "):gsub("%s+", " ")))
  if #name > B.NAME_MAX then name = T.Trim(name:sub(1, B.NAME_MAX)) end
  if name == "" then return nil end
  return name
end

-- The setups in the account file, character copies after named ones, each { name, character, when, label }.
-- This character's own copy is left out (importing it would change nothing).
function B.Setups()
  local saved = readSetups()
  local list = {}
  local me = T.settingsFor
  if type(saved) == "table" and saved.v == 1 and type(saved.list) == "table" then
    for _, s in ipairs(saved.list) do
      if type(s) == "table" and B.CleanName(s.name) == s.name then
        local character = s.character == true
        if not (character and me and s.name:lower() == me:lower()) then
          local when = type(s.when) == "string" and s.when or ""
          list[#list + 1] = { name = s.name, character = character, when = when,
            label = s.name .. (character and " (character" .. (when ~= "" and ", " .. when or "") .. ")" or "") }
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if a.character ~= b.character then return not a.character end
    return a.name:lower() < b.name:lower()
  end)
  return list
end

-- The whole list as saved, own copy included.
local function allSetups()
  local saved = readSetups()
  local list = {}
  if type(saved) == "table" and saved.v == 1 and type(saved.list) == "table" then
    for _, s in ipairs(saved.list) do
      if type(s) == "table" and type(s.name) == "string" then list[#list + 1] = T.Copy(s) end
    end
  end
  return list
end

-- The notification settings without what this character was told (`seen` stays each character's own).
local function withoutSeen(notify)
  local out = T.Copy(notify)
  if type(out) == "table" and type(out.sources) == "table" then
    for _, s in pairs(out.sources) do
      if type(s) == "table" then s.seen = nil end
    end
  end
  return out
end

-- This character's settings and positions, as saved; nil when it has none.
local function currentSettings()
  local keys, any = {}, false
  for _, key in ipairs(B.KEYS) do
    local v = key ~= B.SHARE and ShroudGetSavedVar(key, SCOPE) or nil
    if v ~= nil then
      keys[key] = T.Resaved(key == "notify" and withoutSeen(v) or v)
      any = true
    end
  end
  if not any then return nil end
  return keys
end

-- Stores this character's settings as setup `name`. Returns true, or false and why.
-- Stores this character's settings as setup `name`. Returns true, or false, why, and whether trying again later
-- can help (the game refused a write) rather than not (a limit, nothing to store).
local function store(name, character)
  local keys = currentSettings()
  if not keys then return false, "this character has no settings of its own yet", false end
  local list = allSetups()
  local at = nil
  for i, s in ipairs(list) do
    if s.name:lower() == name:lower() and (s.character == true) == character then at = i end
  end
  if not at and #list >= B.SETUP_MAX then
    return false, "there are already " .. B.SETUP_MAX .. " setups: delete one first", false
  end
  local key = setupKey(name, character)
  if #key > 128 then return false, "that name is too long for its special letters: try a shorter one", false end
  local before = ShroudGetSavedVar(key, ACCOUNT)
  local value = T.ForSaving({ v = 1, name = name })
  value.keys = keys                      -- already in saved form
  if not T.SetSavedVar(key, value, ACCOUNT) then
    return false, "the game refused to store it", true
  end
  local _, when = T.Today()
  local entry = { name = name, character = character, when = type(when) == "string" and when or "" }
  if at then list[at] = entry else list[#list + 1] = entry end
  if not writeSetups(list) then
    if before == nil then T.DeleteSaved(key, ACCOUNT) else T.SetSavedVar(key, T.Resaved(before), ACCOUNT) end
    return false, "the game refused to store the list of setups", true
  end
  local old = (character and "setup_character:" or "setup:") .. name:lower()
  if old ~= key then T.DeleteSaved(old, ACCOUNT) end   -- 1.6.0's copy under the plain name
  return true
end

-- Keeps this character's own copy up to date (from T.Flush, after a setting changed). Never at the login
-- screen or for a character whose settings the modules don't hold. A refused write is tried again at the next
-- flush (T.setupDirty stays set).
function B.KeepCopy()
  local who = T.settingsFor
  if not who or T.PlayerName() ~= who then return end
  local name = B.CleanName(who)
  if not (name and B.GetShare()) then
    T.setupDirty = false
    return
  end
  local ok, _, retry = store(name, true)
  T.setupDirty = not ok and retry == true
end

-- ---------------------------------------------------------------------------
-- Recovery (owner, 2026-10-08, after two values the game's loader refused cost a character its whole file):
-- the game gives no way to test a write or to read a file back, so each character's settings, positions and kept
-- history (B.RecoverList) are also copied into the account file ("recovery:<name>"), a separate file the same bad
-- value can't take with it, at the next flush after one changed (T.recoveryDirty, set by T.SetSavedVar). Each copy
-- has a number, also saved in the character's own file (B.MARK). At start (and for another character), before
-- anything reads its settings: a character whose file has no number but whose copy does lost its file (the game
-- couldn't read it, and starts the add-on empty), so the copy is written back at once and chat says so. A file
-- restored by hand, or one older than its copy, has its number: left alone. Stats that change all the time (the
-- day, the XP session) aren't copied.
-- ---------------------------------------------------------------------------
-- Only on a client without the game's backups (owner, 2026-10-16): from API 39 the game keeps a file it couldn't
-- read beside the new one (fixed since chaos build 318, before API 39) and copies a file before a reset, an import
-- or a new version, which the player can restore; there no copy is written or put back, and the old ones go once
-- (B.DropRecovery).
B.MARK = "save_mark"                 -- character: the number of the recovery copy last written
function B.UsesRecovery()
  return not (B.HasBackups() and type(ShroudRestoreSavedVarBackup) == "function")
end
B.RECOVER_EXTRA = { "loot_runs", "skill_levels", "buff_durations" }
local recoverList, recoverSet = nil, nil

-- The keys copied: every setting (B.KEYS) and B.RECOVER_EXTRA. Built at the first use: files append to B.KEYS.
function B.RecoverList()
  if not recoverList then
    recoverList, recoverSet = {}, {}
    for _, list in ipairs({ B.KEYS, B.RECOVER_EXTRA }) do
      for _, k in ipairs(list) do
        if not recoverSet[k] then
          recoverSet[k] = true
          recoverList[#recoverList + 1] = k
        end
      end
    end
  end
  return recoverList
end

function B.Recovers(key)
  B.RecoverList()
  return recoverSet[key] == true
end

local function recoveryKey(name) return "recovery:" .. T.ForSaving(name:lower()) end

-- This character's recovery copy as saved, or nil.
function B.RecoveryCopy(name)
  local copy = ShroudGetSavedVar(recoveryKey(name or T.settingsFor or ""), ACCOUNT)
  if type(copy) ~= "table" or copy.v ~= 1 or type(copy.keys) ~= "table" or type(copy.n) ~= "number" then
    return nil
  end
  return copy
end

-- Writes this character's recovery copy (from T.Flush, after a change). Its number goes into the character's file
-- first: a copy refused afterwards leaves an older copy, never a file without a number.
function B.KeepRecovery()
  if not B.UsesRecovery() then
    T.recoveryDirty = false
    return
  end
  local who = T.settingsFor
  if not who or T.PlayerName() ~= who then return end
  local keys = {}
  for _, key in ipairs(B.RecoverList()) do
    local v = ShroudGetSavedVar(key, SCOPE)
    if type(v) == "table" and v[T.SAVE_FORMAT_KEY] ~= nil then
      keys[key] = v                    -- already in today's form: as it is (a round trip of a full set of map
    elseif v ~= nil then               -- overlays was 3 MB of garbage a copy, 2026-10-13)
      keys[key] = T.Resaved(v)
    end
  end
  local mark = ShroudGetSavedVar(B.MARK, SCOPE)
  local n = (type(mark) == "number" and mark >= 1 and math.floor(mark) or 0) + 1
  if not T.SetSavedVar(B.MARK, n, SCOPE) then return end            -- tried again at the next flush
  local _, date = T.Today()
  local clock = T.ClockText()
  local when = (type(date) == "string" and date or "") .. ((clock ~= "" and date) and " " or "") .. clock
  -- listed first (review 36): a copy no other character's session could find would go unmeasured
  if not B.IndexRecovery(who) then
    T.recoveryDirty = T.saveRefused[B.RECOVERIES] == nil
    return
  end
  local ok = T.SetSavedVar(recoveryKey(who), { v = 1, n = n, when = when, keys = keys }, ACCOUNT)
  -- a value T.CheckSaved refused won't pass next time either (chat said so once): not retried every flush
  T.recoveryDirty = not ok and T.saveRefused[recoveryKey(who)] == nil
end

-- The characters with a recovery copy in the account file (B.RECOVERIES, from 1.8.0), so its size can be measured
-- without that character. Copies 1.7.0 wrote aren't listed until their character next plays, and the game can't
-- list keys: an install that ran 1.7.0 (`legacy`, set when the index is first made there) keeps B.LEGACY_RESERVE of
-- the account file free for them (review 36).
B.RECOVERIES = "recovery_index"      -- account: { v = 1, names = { lower name, ... }, legacy, ceiling, by }
B.LEGACY_RESERVE = 40000             -- a first guess: a 1.7.0 copy's learned buff durations have no cap (review 36)
B.CEILING_MARGIN = 8000
local function readRecoveryIndex()
  local saved = T.FromSaved(ShroudGetSavedVar(B.RECOVERIES, ACCOUNT))
  local names = {}
  for _, n in ipairs(type(saved) == "table" and type(saved.names) == "table" and saved.names or {}) do
    if type(n) == "string" and n ~= "" then names[#names + 1] = n end
  end
  return names, type(saved) == "table" and saved.legacy == true, saved
end

local function writeRecoveryIndex(names, legacy, ceiling, by)
  return T.SetSavedVar(B.RECOVERIES, T.ForSaving({ v = 1, names = names, legacy = legacy, ceiling = ceiling,
    by = by }), ACCOUNT) == true
end

-- The ceiling learned for this install's account file (B.FlushFailed), or nil; and whose session learned it.
local function learnedCeiling(saved)
  local c = type(saved) == "table" and saved.ceiling
  local by = type(saved) == "table" and type(saved.by) == "string" and saved.by or nil
  if type(c) == "number" and c > 0 then return c, by end
  return nil, nil
end

-- A learned ceiling not yet in the account file is also kept in this character's file (review 42: that file is
-- written on its own, so a restart before the account file takes it doesn't lose the bound), and read back at
-- start: { v = 1, ceiling, by }.
B.CEILING_DUE = "ceiling_due"
local function readCeilingDue()
  local due = T.FromSaved(ShroudGetSavedVar(B.CEILING_DUE, SCOPE))
  if type(due) ~= "table" or type(due.ceiling) ~= "number" or due.ceiling <= 0 then return nil end
  local out = { ceiling = due.ceiling }
  if type(due.by) == "string" then out.by = due.by end
  return out
end

-- The ceiling due is on disk in the account file: nothing pending, the character file's note dropped.
local function ceilingWritten()
  B.pendingCeiling = nil
  if ShroudGetSavedVar(B.CEILING_DUE, SCOPE) ~= nil then T.DeleteSaved(B.CEILING_DUE, SCOPE) end
end

-- At start and for another character: a ceiling due from this character's file joins the one pending (the lower).
local function takeCeilingDue()
  local due = readCeilingDue()
  if not due then return nil end
  if not B.pendingCeiling or due.ceiling < B.pendingCeiling.ceiling then B.pendingCeiling = due end
  return B.pendingCeiling.ceiling
end

-- The account file's room for what Toolbox can measure: all of it but what 1.7.0's unlisted copies may hold.
local function keepRoom(legacy, ceiling)
  local reserve = legacy and B.LEGACY_RESERVE or 0
  if ceiling then reserve = math.max(reserve, T.FILE_MAX - ceiling) end
  T.ReserveFile(ACCOUNT, reserve)
end

-- The game refused a flush, and gives no reason. Where the account file may hold copies Toolbox can't measure (a
-- reserve is kept), it may have passed 256 KB with them (review 36: no guessed reserve bounds them). Once a session:
-- 1. the same flush again: a refusal that passes teaches nothing and changes nothing (review 39);
-- 2. room made a step at a time, flushing after each: the price cache (looked up again), this character's recovery
--    copy (made again from its file), then the account file's changes since the last flush that worked;
-- 3. if a step works, everything is put back and flushed: if THAT works too the refusal had passed (nothing lost);
--    if it's refused, the size was why: the steps are taken again, and what's measured then, less a margin, is the
--    ceiling for the measured part (kept in the index, so later growth stops short of it).
-- Nothing is lost while it tries: the file on disk stays as it was until a flush works, and every value is put back
-- unless the size was shown to be why. Returns true when written, "undone" when written without the account file's
-- latest changes (chat names them), false when nothing worked (not the size: Toolbox's own part was smaller).
B.UNDONE_SHOWN = 4
function B.FlushFailed()
  local f = T.fileUse.account
  if f.reserve == 0 or B.freedForRoom then return false end
  if ShroudFlushSavedVars() ~= false then return true end
  B.freedForRoom = true
  local who = T.settingsFor
  local copyKey = who and recoveryKey(who)
  local reserve = f.reserve
  T.ReserveFile(ACCOUNT, 0)                    -- putting values back is never refused
  local taken, undone = {}, {}
  local function take(key, value)              -- leaves `value` (nil: none) in key, remembering what was there
    local now = ShroudGetSavedVar(key, ACCOUNT)
    if now == value then return end
    taken[#taken + 1] = { key = key, now = now }
    if value == nil then T.DeleteSaved(key, ACCOUNT) else T.SetSavedVar(key, value, ACCOUNT) end
  end
  local function giveBack()
    for i = #taken, 1, -1 do
      local e = taken[i]
      if e.now == nil then T.DeleteSaved(e.key, ACCOUNT) else T.SetSavedVar(e.key, e.now, ACCOUNT) end
    end
    taken = {}
  end
  local steps = {
    function() take("prices", nil) end,
    function() if copyKey then take(copyKey, nil) end end,
    function()
      local keys = {}
      for key in pairs(T.accountUndo) do
        -- not the index (review 40): it only gains names, and a copy kept must stay listed
        if key ~= "prices" and key ~= copyKey and key ~= B.RECOVERIES then keys[#keys + 1] = key end
      end
      table.sort(keys)
      for _, key in ipairs(keys) do
        local before = #taken
        take(key, T.accountUndo[key].old)
        if #taken > before then undone[#undone + 1] = key end
      end
    end,
  }
  local needed = 0
  for i, step in ipairs(steps) do
    step()
    if ShroudFlushSavedVars() ~= false then
      needed = i
      break
    end
  end
  giveBack()
  if needed == 0 or ShroudFlushSavedVars() ~= false then      -- not the size, or a refusal that passed
    T.ReserveFile(ACCOUNT, reserve)
    return needed > 0
  end
  undone = {}
  local written = false
  if needed == 3 then                          -- the latest changes undone may be room enough: the copy stays
    steps[1]()
    steps[3]()
    written = ShroudFlushSavedVars() ~= false
    if not written then
      giveBack()
      undone = {}
    end
  end
  if not written then
    for i = 1, needed do steps[i]() end
    written = ShroudFlushSavedVars() ~= false
  end
  if not written then
    giveBack()
    T.ReserveFile(ACCOUNT, reserve)
    return false
  end
  local hadPrices = ShroudGetSavedVar("prices", ACCOUNT) == nil and T.Prices.Count() > 0
  if hadPrices then T.Prices.Forget() end       -- the cache in memory follows (its empty form is tiny)
  local copyGone = copyKey ~= nil and needed >= 2 and ShroudGetSavedVar(copyKey, ACCOUNT) == nil
  if copyGone then T.recoveryDirty = true end
  for _, key in ipairs(undone) do
    if key:find("^setup_character:") then T.setupDirty = true end
  end
  -- below what was just written (review 36), by a margin for the estimate's own error (a tenth of a small file)
  local ceiling = math.max(1, f.total - math.min(B.CEILING_MARGIN, math.floor(f.total / 10)))
  B.pendingCeiling = { ceiling = ceiling }
  if who then B.pendingCeiling.by = who:lower() end
  local noted = T.SetSavedVar(B.CEILING_DUE, T.ForSaving({ v = 1, ceiling = ceiling, by = B.pendingCeiling.by or "" }),
    SCOPE) == true
  local kept = B.KeepCeiling()
  if not noted and not kept then             -- the bound lives in memory only (review 43: accepted risk; said so)
    T.Docs.Warn("Toolbox: settings file", "Toolbox couldn't keep a note of how full its shared account file can"
      .. " get: the game refused to save it. Until it can, please don't quit the game for a minute, and log in"
      .. " each of your characters once soon (that makes their old copies smaller, so the file has room again).")
  end
  local shown = {}
  for i = 1, math.min(#undone, B.UNDONE_SHOWN) do shown[i] = "'" .. undone[i] .. "'" end
  if #undone > B.UNDONE_SHOWN then shown[#shown + 1] = (#undone - B.UNDONE_SHOWN) .. " more" end
  T.Print("The game couldn't save Toolbox's shared account file: with copies of your other characters' settings"
    .. " that Toolbox 1.7.0 kept there, it passed the game's 256 KB a file. To make room Toolbox"
    .. (hadPrices and " cleared its remembered prices (they're looked up again)" or "")
    .. (copyGone and ((hadPrices and "," or "") .. " set aside this character's recovery copy") or "")
    .. (#undone > 0 and (((hadPrices or copyGone) and " and" or "") .. " undid its latest changes to that file,"
      .. " which weren't saved: " .. table.concat(shown, ", ")) or "")
    .. ". It keeps the file smaller from now on; logging in each of your other characters once makes their copies"
    .. " smaller and gives the room back.")
  if ShroudFlushSavedVars() == false then return false end   -- the ceiling stays due, the undo list kept (review 41)
  if kept then ceilingWritten() end              -- its note goes at the next flush (kept until then: harmless)
  return #undone > 0 and "undone" or true
end

-- A learned ceiling not on disk yet (review 41): { ceiling, by }, written into the index before every flush until
-- one works with it (T.Flush), whether or not this character's copy changes. A copy of this character's in the
-- account file is listed with it (review 40). Returns whether the index took it.
B.pendingCeiling = nil
function B.CeilingWritten() ceilingWritten() end
function B.KeepCeiling()
  local due = B.pendingCeiling
  if not due then return false end
  local names, legacy, saved = readRecoveryIndex()
  local who = T.settingsFor
  if who and ShroudGetSavedVar(recoveryKey(who), ACCOUNT) ~= nil then
    local listed = false
    for _, n in ipairs(names) do listed = listed or n == who:lower() end
    if not listed then names[#names + 1] = who:lower() end
  end
  local old = learnedCeiling(saved)
  if old and old < due.ceiling then due.ceiling = old end
  T.ReserveFile(ACCOUNT, 0)                    -- the bound itself is always written (a few bytes)
  local ok = writeRecoveryIndex(names, legacy, due.ceiling, due.by)
  keepRoom(legacy, due.ceiling)
  return ok
end

-- Lists `who` as having a copy. Returns whether the index says so. A copy listed only now was unmeasured when a
-- ceiling was learned in another character's session: its room is in the ceiling's margin, so the ceiling rises
-- by it (it's measured from now on), and the room comes back as characters log in.
function B.IndexRecovery(who)
  local lower = who:lower()
  local names, legacy, saved = readRecoveryIndex()
  for _, n in ipairs(names) do
    if n == lower then return true end
  end
  names[#names + 1] = lower
  if saved == nil then legacy = B.legacyInstall == true end
  local ceiling, by = learnedCeiling(saved)
  local key = recoveryKey(who)
  local unseen = ceiling and by and by ~= lower and ShroudGetSavedVar(key, ACCOUNT)
  local reserve = T.fileUse.account.reserve
  if type(unseen) == "table" then
    ceiling = math.min(T.FILE_MAX, ceiling + T.SavedSize(unseen) + #key + 4)
    keepRoom(legacy, ceiling)                  -- first: the index itself may need the room
  end
  if writeRecoveryIndex(names, legacy, ceiling, by) then return true end
  T.ReserveFile(ACCOUNT, reserve)
  return false
end

-- Character keys that aren't settings or recovered (B.KEYS, B.RecoverList()); other files append theirs. Every key
-- Toolbox saves is in one of them (tests/test_backup.lua), so each file's size is measured whole.
B.OTHER_KEYS = { "session", "daily", "buff_timers", "notify_history", "guild_motd", B.MARK, B.PENDING, B.CEILING_DUE }
-- Functions giving more of them, named at run time (the map overlays' scene keys, from their index).
B.KEY_LISTS = {}

-- Measures the files as they are (at start: both; for another character: its file).
function B.MeasureFiles(characterOnly)
  local keys, listed = {}, {}
  local lists = { B.RecoverList(), B.OTHER_KEYS }
  for _, more in ipairs(B.KEY_LISTS) do
    local ok, list = pcall(more)
    if ok and type(list) == "table" then lists[#lists + 1] = list end
  end
  for _, list in ipairs(lists) do
    for _, k in ipairs(list) do
      if not listed[k] then
        listed[k] = true
        keys[#keys + 1] = k
      end
    end
  end
  T.MeasureKeys(keys, SCOPE, true)
  local due = takeCeilingDue()
  if characterOnly then
    if due then
      local _, legacy, index = readRecoveryIndex()
      keepRoom(legacy, math.min(due, learnedCeiling(index) or due))
    end
    return
  end
  local account, inAccount = { "prices", "welcomed", T.VERSION_SEEN, B.SETUPS, B.RECOVERIES }, {}
  local function count(key)
    if not inAccount[key] then
      inAccount[key] = true
      account[#account + 1] = key
    end
  end
  local setups = readSetups()
  for _, e in ipairs(type(setups) == "table" and type(setups.list) == "table" and setups.list or {}) do
    if type(e) == "table" and type(e.name) == "string" then
      count(foundSetupKey(e.name, e.character))
      if e.character then count(recoveryKey(e.name)) end     -- a character known by its shared setup
    end
  end
  local names, legacy, index = readRecoveryIndex()
  for _, n in ipairs(names) do count(recoveryKey(n)) end
  if T.settingsFor then count(recoveryKey(T.settingsFor)) end
  T.MeasureKeys(account, ACCOUNT, true)
  -- no index yet: 1.7.0 ran here if it left anything in the account file (its copies may be there, unlisted)
  if index == nil then B.legacyInstall = ShroudGetSavedVar("welcomed", ACCOUNT) ~= nil or setups ~= nil end
  local ceiling = learnedCeiling(index)
  if due then ceiling = math.min(due, ceiling or due) end
  keepRoom(legacy or (index == nil and B.legacyInstall), ceiling)
end

-- At start and for another character, before anything reads its settings: writes the recovery copy back when the
-- character's file came back without its number (above). Returns true when it did.
function B.Recover()
  local who = T.settingsFor
  if not who or T.PlayerName() ~= who then return false end
  if not B.UsesRecovery() then
    B.DropRecovery()
    return false
  end
  if ShroudGetSavedVar(B.MARK, SCOPE) ~= nil then return false end
  local copy = B.RecoveryCopy(who)
  if not copy then return false end
  local restored, skipped = 0, 0
  for _, key in ipairs(B.RecoverList()) do
    local v = copy.keys[key]
    if v ~= nil then
      if T.SetSavedVar(key, T.Resaved(v), SCOPE) then restored = restored + 1 else skipped = skipped + 1 end
    end
  end
  T.SetSavedVar(B.MARK, math.floor(copy.n), SCOPE)
  local flushed = T.Flush() ~= false
  local when = type(copy.when) == "string" and copy.when ~= "" and (" from " .. copy.when) or ""
  T.Print("The game couldn't read Toolbox's saved file for " .. who .. " (it started empty), so your settings,"
    .. " positions and run history were put back from Toolbox's copy" .. when .. "." .. (skipped > 0 and (" "
    .. skipped .. " part(s) couldn't be put back.") or "") .. " Stats from before then (today's counts, the XP"
    .. " session) can't be." .. (flushed and "" or " The game couldn't write them to disk yet."))
  T.recoveryDirty = false
  return restored > 0
end

-- On a client with backups: the recovery copies leave the account file, once it has a game backup holding them
-- (the new version's, B.UpdateBackup, or one made now; none: tried again at the next start or character). Every
-- copy Toolbox can name (the index's, the shared setups' characters', this character's) and this character's
-- number go; the index stays, emptied, with its `legacy` and learned `ceiling` (1.7.0's unlisted copies can't be
-- named: their room stays kept), marked `dropped`. Returns how many copies went.
local droppedFor = {}
function B.DropRecovery()
  local who = T.settingsFor
  if who and ShroudGetSavedVar(B.MARK, SCOPE) ~= nil then T.DeleteSaved(B.MARK, SCOPE) end
  local names, legacy, index = readRecoveryIndex()
  local doneBefore = type(index) == "table" and index.dropped == true
  if doneBefore and (not who or droppedFor[who:lower()]) then return 0 end
  local keys, found = {}, {}
  local function addCopy(name)
    local key = type(name) == "string" and name ~= "" and recoveryKey(name)
    if key and not found[key] then
      found[key] = true
      if ShroudGetSavedVar(key, ACCOUNT) ~= nil then keys[#keys + 1] = key end
    end
  end
  if not doneBefore then
    for _, n in ipairs(names) do addCopy(n) end
    for _, e in ipairs(allSetups()) do
      if e.character == true then addCopy(e.name) end
    end
  end
  if who then addCopy(who) end
  if #keys == 0 and (doneBefore or index == nil) then
    if who then droppedFor[who:lower()] = true end
    return 0
  end
  if #keys > 0 then
    local backed = B.updateBackups ~= nil and B.updateAccount == true
    if not backed and not B.KeepBackup(ACCOUNT) then return 0 end
  end
  for _, key in ipairs(keys) do T.DeleteSaved(key, ACCOUNT) end
  local ceiling, by = learnedCeiling(index)
  T.SetSavedVar(B.RECOVERIES, T.ForSaving({ v = 1, names = {}, legacy = legacy, ceiling = ceiling, by = by,
    dropped = true }), ACCOUNT)
  if who then droppedFor[who:lower()] = true end
  return #keys
end

-- Character copies saved under a tagged name (T.PlainName: 1.7.0 and before kept "shawn[PVP]" apart from "shawn"):
-- each goes to its plain name, its recovery copy too, unless that name has one already (then it's dropped). Once a
-- run, at start, before the recovery check. Account keys can't be listed, so a tagged recovery copy of a character
-- that never listed its setup stays (unused). Returns how many copies it tidied.
local tidied = false
function B.TidyTagged()
  if tidied then return 0 end
  tidied = true
  local list, kept, moved = allSetups(), {}, 0
  local plainHas = {}
  for _, e in ipairs(list) do
    if e.character == true and T.PlainName(e.name) == e.name then plainHas[e.name:lower()] = true end
  end
  local function move(from, to, rename)
    local v = ShroudGetSavedVar(from, ACCOUNT)
    if v == nil then return true end
    if ShroudGetSavedVar(to, ACCOUNT) == nil then
      local value = T.Resaved(v)
      if rename and type(value) == "table" then value.name = T.ForSaving(rename) end
      if not T.SetSavedVar(to, value, ACCOUNT) then return false end
    end
    T.DeleteSaved(from, ACCOUNT)
    return true
  end
  for _, e in ipairs(list) do
    local plain = e.character == true and B.CleanName(T.PlainName(e.name)) or nil
    if plain and plain ~= e.name then
      local lower = plain:lower()
      local ok = move(foundSetupKey(e.name, true), setupKey(plain, true), plain)
        and move(recoveryKey(e.name), recoveryKey(plain))
      if not ok then
        kept[#kept + 1] = e                    -- refused: tried again next run
      else
        moved = moved + 1
        if not plainHas[lower] then
          plainHas[lower] = true
          kept[#kept + 1] = { name = plain, character = true, when = e.when }
        end
      end
    else
      kept[#kept + 1] = e
    end
  end
  if moved > 0 then writeSetups(kept) end
  return moved
end

-- The setup a player means by `text`: a named one first, then a character's copy. Nil when none matches.
function B.FindSetup(text)
  local want = B.CleanName(text)
  if not want then return nil end
  want = want:lower()
  for _, s in ipairs(B.Setups()) do
    if s.name:lower() == want or s.label:lower() == want then return s end
  end
  return nil
end

-- Saves this character's settings and positions as a named setup. Returns true and the name, or false and why.
function B.Export(text)
  local name = B.CleanName(text)
  if not name then return false, "give it a name" end
  T.SavePrefs()                          -- where the windows and strips are now
  local ok, why = store(name, false)
  if not ok then return false, why end
  local flushed, full = T.Flush()
  if flushed == false then
    return false, full and "the shared account file is full (above)" or "the game couldn't write it to disk"
  end
  return true, name
end

-- The values an import writes, read (each copy and file as it was saved): the setup's, notify without its `seen`
-- but with this character's own.
local function importValues(setupKeys)
  local out = {}
  local mine = T.ReadSaved("notify")
  for _, key in ipairs(B.KEYS) do
    local v = T.FromSaved(setupKeys[key])
    if key == B.SHARE then
      v = nil                             -- each character's own choice
    elseif key == "notify" then
      v = withoutSeen(v)
      local own = type(mine) == "table" and type(mine.sources) == "table" and mine.sources or {}
      for src, o in pairs(own) do
        if type(o) == "table" and o.seen ~= nil then
          if type(v) ~= "table" then v = { v = 1, sources = {} } end
          if type(v.sources) ~= "table" then v.sources = {} end
          if type(v.sources[src]) ~= "table" then v.sources[src] = {} end
          v.sources[src].seen = T.Copy(o.seen)
        end
      end
    end
    out[key] = v
  end
  return out
end

-- Copies setup `s` (from B.Setups / B.FindSetup) into this character, now. What this character was told by
-- notifications stays its own. Nothing is deleted until every new value was stored: a refused write puts the
-- old values back and changes nothing (review, 2026-10-04). Returns true, or false and why.
function B.Import(s)
  if type(s) ~= "table" then return false, "pick a setup" end
  local saved = ShroudGetSavedVar(foundSetupKey(s.name, s.character), ACCOUNT)
  if type(saved) ~= "table" or type(saved.keys) ~= "table" then return false, "that setup is gone" end
  local values = importValues(saved.keys)
  B.lastBackup = nil
  if B.HasBackups() then                 -- the game copies the file on disk: the settings written first (review 52)
    if B.SaveNow() == false then
      return false, "the game couldn't write this character's settings to disk first, so no copy of them could be"
        .. " kept; nothing was imported"
    end
    B.lastBackup = B.KeepBackup(SCOPE)   -- this character's settings as they were (the caller says so)
  end
  local old, written = {}, {}
  for _, key in ipairs(B.KEYS) do old[key] = T.Resaved(ShroudGetSavedVar(key, SCOPE)) end
  for _, key in ipairs(B.KEYS) do
    if values[key] ~= nil then
      if not T.SetSavedVar(key, T.ForSaving(values[key]), SCOPE) then
        for _, k in ipairs(written) do
          if old[k] == nil then T.DeleteSaved(k, SCOPE) else T.SetSavedVar(k, old[k], SCOPE) end
        end
        return false, "the game refused to store it, so nothing changed"
      end
      written[#written + 1] = key
    end
  end
  for _, key in ipairs(B.KEYS) do
    if values[key] == nil and key ~= B.SHARE and old[key] ~= nil then T.DeleteSaved(key, SCOPE) end
  end
  T.Restart()
  T.setupDirty = true                    -- this character's copy now holds the imported setup
  if T.Flush() == false then return true, "imported, but the game couldn't write it to disk yet" end
  return true
end

-- Deletes a setup from the account file (a character's copy comes back when that character next plays, if it
-- lists its setup). Returns true when it was there and is gone; false and why otherwise.
function B.DeleteSetup(s)
  if type(s) ~= "table" then return false, "pick a setup" end
  local list, kept = allSetups(), {}
  for _, e in ipairs(list) do
    if not (e.name:lower() == s.name:lower() and (e.character == true) == s.character) then kept[#kept + 1] = e end
  end
  local key = foundSetupKey(s.name, s.character)
  if #kept == #list and ShroudGetSavedVar(key, ACCOUNT) == nil then return false, "it wasn't there" end
  if #kept < #list and not writeSetups(kept) then
    return false, "the game refused to change the list of setups"
  end
  T.DeleteSaved(key, ACCOUNT)
  if T.Flush() == false then return false, "the game couldn't write it to disk yet" end
  return true
end

-- Takes this character's copy out of the account file (sharing off, or a reset). Returns true, or false and why.
local function unlistMine()
  local name = T.settingsFor and B.CleanName(T.settingsFor)
  if not name then return true end
  local ok, why = B.DeleteSetup({ name = name, character = true })
  if not ok and why ~= "it wasn't there" then return false, why end
  return true
end

-- Lists this character's setup for the others, or stops (its copy is deleted from the account file).
-- Returns true, or false and why; nothing is claimed that wasn't stored (review, 2026-10-07, 16). On: the copy
-- first, then the choice (a refused choice takes the copy back out); a character with no settings of its own yet
-- gets its copy at its first change (B.KeepCopy). Off: the copy goes first, then the choice; a refused choice puts
-- the copy back (or, if that's refused too, B.KeepCopy does at the next flush: sharing is still on).
function B.SetShare(on)
  on = on == true
  local ok, why = true, nil
  local name = T.settingsFor and B.CleanName(T.settingsFor)
  if not name then
    ok, why = false, "no character is logged in"
  elseif on then
    local copied = false
    if currentSettings() then ok, why = store(name, true); copied = ok end
    if ok and not T.Save(B.SHARE, true) then
      if copied then unlistMine() end
      ok, why = false, "the game refused to store the choice"
    end
    if ok then
      shareFor, share = T.settingsFor, true
      if T.Flush() == false then ok, why = false, "the game couldn't write it to disk yet" end
    end
  else
    T.setupDirty = false                 -- or unlistMine's flush would store the copy again (sharing is still on)
    ok, why = unlistMine()
    if ok and not T.Save(B.SHARE, false) then
      if currentSettings() then store(name, true) end
      ok, why = false, "the game refused to store the choice"
    end
    if ok then shareFor, share = T.settingsFor, false else T.setupDirty = true end   -- still on: keep it current
  end
  T.Config.Sync()
  return ok, why
end

-- The notification settings' defaults with this character's `seen` values kept (what was delivered stays
-- delivered: the guild message isn't shown again).
local function seenOnly(current)
  local out = { v = 1, sources = {} }
  local cur = type(current) == "table" and type(current.sources) == "table" and current.sources or {}
  for key, s in pairs(cur) do
    if type(s) == "table" and s.seen ~= nil then out.sources[key] = { seen = T.Copy(s.seen) } end
  end
  return out
end

-- From ShroudOnStart, before any module reads its settings: carries out a waiting reset.
function B.ApplyPending()
  local pending = B.Pending()
  if not pending then return end
  B.resetApplied = T.settingsFor   -- whose reset: the menu's "New" line isn't said to them (hud.lua, review 55)
  local kept = T.FromSaved(pending).backup   -- the copy made as it was asked for (review 51)
  if type(kept) ~= "string" or kept == "" then kept = nil end
  B.backupWhy = nil
  T.DeleteSaved(B.PENDING, SCOPE)     -- first: a failure below doesn't repeat at every start
  local unlisted, why = unlistMine()         -- sharing goes back to off: its copy goes too (review, 2026-10-04)
  if not unlisted then T.Print("Couldn't take this character's setup off the shared list: " .. why .. ".") end
  shareFor = nil
  local notify = T.ReadSaved("notify")
  for _, key in ipairs(B.KEYS) do T.DeleteSaved(key, SCOPE) end   -- false only for a key never set
  local saved = T.Save("notify", seenOnly(notify))
  if T.Flush() == false or not saved then
    T.Print("Toolbox's settings are back to their defaults for now, but the game couldn't write them to disk:"
      .. " your old settings may come back after a restart.")
  else
    T.Print("Toolbox's settings are back to their defaults." .. B.BackupNote(kept))
  end
end

-- Runs one start-up step; a failure is reported and the rest still start (one broken part, such
-- as a window hitting the game's element-creation cap, shouldn't take Toolbox down with it).
local function step(name, fn)
  local ok, err = pcall(fn)
  if not ok then T.Print("Couldn't start " .. name .. ": " .. tostring(err)) end
end

-- Every module's start: reads its settings and builds its windows and strips. Run again for another character
-- (T.FollowCharacter): each Init drops what it built before.
local function startModules(places)
  step("the Notifications window", T.Notify.DropWindow)
  step("XP Detailed", T.Window.Init)
  step("the XP window", T.Compact.Init)
  step("the Today window", T.Daily.InitWindow)
  step("Loot Tracker", T.DailyDetail.Init)
  step("sounds", T.Sounds.Init)
  step("the buff bar", T.BuffBar.Init)
  step("the health bars", T.Vitals.Init)
  step("combat stats", T.Combat.Init)
  step("the equipment bar", T.Gear.Init)
  step("the target HUD", T.Target.Init)
  step("the consumables bar", T.Consumables.Init)
  step("the notification HUD", T.Notify.Hud.Init)
  if T.SkillBar then step("the skill activity strip", T.SkillBar.Init) end   -- skills.lua, when present
  step("the location strip", T.Location.Init)
  step("the map overlays", T.Overlays.Init)
  step("the crafting planner", T.Planner.Init)
  step("the launcher", T.Launcher.Init)
  step("the HUD strips", function() T.Hud.Init(places) end)  -- builds the HUD strips (glued or not); retries on the cap
  step("the buff bar", T.BuffBar.Tick)
  step("the health bars", T.Vitals.Tick)
  step("the equipment bar", function() T.Gear.Poll(true) end)
  step("the target HUD", function() T.Target.Poll(true) end)
end

-- Another character: its XP session and day, before its windows are built (review, 2026-10-04: they showed the
-- last character's for a tick, and a daily event in between went into the last character's day). With no totals
-- yet, its saved day is loaded now and the session starts at the first tick that has them (T.Tick).
local function followSession()
  local s = T.session
  if T.ReadTotals() then
    if s and (s.ended or s.player ~= T.PlayerName()) then T.StartSession(s.ended and "login" or "character") end
    if not s then T.ResumeOrStart() end
  else
    T.session = nil
    T.Daily.ReadDay()
  end
end

-- The character whose settings the modules hold: its name, or false when Toolbox started with none.
T.settingsFor = false

local function characterName()
  local name = T.PlayerName()
  if type(name) ~= "string" or name == "" or name == "INVALID" or name == "None" or name == "none" then return nil end
  return name
end

-- The character in the world, or nil (the login screen, no character yet).
function T.CharacterName() return characterName() end

-- Another character logged in without a reload: ShroudOnStart doesn't run again; the docs: check the name in
-- ShroudOnSceneLoaded: every module starts again with that character's settings and positions, before
-- anything saves (the tick's window tracking would write the last character's into this one's file).
-- Returns true when it did.
function T.FollowCharacter()
  local name = characterName()
  if not name then return false end
  if T.loggedOut then                  -- back from the login screen: read from the files, whoever it is
    T.loggedOut = false
    T.settingsFor = false
  end
  if name == T.settingsFor then return false end
  T.settingsFor = name                 -- (false: started with no character, so read no settings yet)
  step("the saved files' size", function() B.MeasureFiles(true) end)
  local places = T.Hud.Places()        -- before the strips go: kept where this character has none
  step("the recovery check", T.Backup.Recover)        -- a file the game couldn't read: put back first
  step("the settings restore", T.Backup.ApplyPending)
  T.recoveryDirty = true               -- this character's recovery copy, at the next flush
  step("this character's session and day", followSession)   -- before its windows show them
  startModules(places)
  T.Config.Sync()
  T.setupDirty = true                  -- this character's copy in the account file, at the next flush
  return true
end

-- Every module starts again from this character's saved settings (an imported setup).
function T.Restart()
  T.Notify.ForgetPrefs()
  startModules(nil)
  T.Config.Sync()
end

function ShroudOnStart()
  T.Ran("start")
  T.startedAt = T.Now()
  T.RegisterCommands()
  T.RegisterKeybind()
  T.settingsFor = characterName() or false
  step("the saved files' size", T.Backup.MeasureFiles)  -- before any write: each file's 256 KB
  step("the update's backup", T.Backup.UpdateBackup)    -- a new version: the files as they were, before any change
  step("the price cache's size", T.Prices.KeepSize)     -- first: an older, bigger cache must not fill the file
  step("the setup names", T.Backup.TidyTagged)          -- copies kept under a tagged name, before the check
  step("the recovery check", T.Backup.Recover)          -- a file the game couldn't read: put back first
  step("the settings restore", T.Backup.ApplyPending)   -- before anything reads its settings
  T.recoveryDirty = true               -- this character's recovery copy, at the next flush
  step("today's stats", T.Daily.ReadDay)  -- before the session: a new login re-bases daily gold
  step("the crafting state", T.Daily.ReadCraftingState)
  T.ResumeOrStart()
  T.Sample()                         -- XP gained since the last save (e.g. across a reload)
  startModules()
  step("skill levels", function() T.Daily.OnSkills(true) end)
  T.RegisterPeriodic(PERIODIC, T.Tick, T.tickSeconds, true)
  T.RegisterPeriodic("toolbox_track", T.TrackTick, T.tickSeconds, true)
  T.RegisterPeriodic("toolbox_poll", T.PollTick, T.tickSeconds, true)
  T.RegisterPeriodic("toolbox_views", T.ViewsTick, T.tickSeconds, true)
  T.setupDirty = true                  -- this character's copy in the account file, at the next flush
  T.WhatsNew(T.Welcome())            -- first run only: a chat line and the settings window; else what's new
  step("notifications", function() T.Notify.Check(true) end)   -- anything new: the guild message, mail, ...
end

-- Only a trigger: the amount's relation to pooled vs total XP is not documented,
-- so the totals are re-read instead of summing `amount`.
function ShroudOnExperienceGain(_, _)
  T.Ran("xp")
  local t0 = T.PerfT()
  T.Sample()
  T.PerfAdd("callback:xp", t0)
end

-- Kills for the daily stats (combat chat lines about you, your party or your pet).
function ShroudOnCombatEvents(events, dropped)
  T.Ran("combat events")
  local t0 = T.PerfT()
  local list = T.ReadEvents(events)  -- plain tables, whatever the game hands over
  T.Daily.OnCombat(list)
  T.Combat.OnEvents(list, dropped)
  T.Overlays.OnCombat(list)          -- the auto map's fights
  T.PerfAdd("callback:combat events", t0)
end

-- Fight start / end for the combat HUD.
function ShroudOnCombatModeChanged(inCombat)
  T.Ran("combat mode")
  T.Combat.OnCombatMode(inCombat)
  T.BuffBar.OnCombatMode(inCombat)     -- "only during combat"
end

-- Buff bar and the debuff alert.
function ShroudOnBuffsChanged()
  T.Ran("buffs")
  T.BuffBar.OnBuffsChanged("event")
end

-- Vigor moved, appeared or went away (API 20; never fires on older clients).
function ShroudOnVigorChanged(vigor)
  T.Ran("vigor")
  T.Vitals.OnVigorChanged(vigor)
end

-- A scene change rebuilds the buff list: don't alert for debuffs that were already there.
function ShroudOnSceneUnloaded()
  T.Ran("scene")
  T.SceneChanged()
  T.Daily.SaveIfChanged()              -- the day is otherwise stored with the flush
  -- the last save with the character still in when this is a logout (ShroudOnLogOut comes after it has left)
  if T.CharacterName() and not T.NoCharacter() then
    if T.session then T.SaveSession(false) end
    T.BuffBar.SaveTimers()
    pcall(T.SavePrefs)
  end
  T.BuffBar.SceneChange()
end

function ShroudOnSceneLoaded(_)
  T.Ran("scene")
  T.SceneChanged()
  T.FollowCharacter()
  T.BuffBar.SceneChange()
end

-- Guild or friends changed (twice a second at most): maybe a new guild message of the day.
-- Friends / guild members came online or went offline (API 18).
function ShroudOnFriendStatusChanged(changes, dropped)
  T.Ran("friends")
  T.Notify.OnStatus("friends", changes, dropped)
end

function ShroudOnGuildMemberStatusChanged(changes, dropped)
  T.Ran("guild")
  T.Notify.OnStatus("guild", changes, dropped)
end

-- A skill was learned, gained or lost a level (levelsChanged), or only gained experience.
function ShroudOnSkillsChanged(levelsChanged)
  T.Ran("skills")
  T.Daily.OnSkills(levelsChanged)
  if T.SkillBar then T.SkillBar.OnSkillsChanged(levelsChanged) end   -- skills.lua, when present
end

-- You died (true) or are alive again (false).
function ShroudOnDeathChanged(isDead)
  T.Ran("death")
  T.Daily.OnDeath(isDead)
  T.Overlays.OnDeath(isDead)
end

-- The target the game's target frame shows changed (a new one, or none).
-- The world calendar changed (API 35): the World events notification reads it again.
function ShroudOnCalendarChanged()
  T.Ran("calendar")
  T.Notify.CalendarChanged()
end

-- A calendar date started or ended, or the UTC day rolled (API 38): what's on now moved; read it again at once.
function ShroudOnCalendarNowChanged()
  T.Ran("calendar")
  T.Notify.CalendarChanged()
end

-- The game window's size, UI scale or mode changed (API 31): strips past an edge come back.
function ShroudOnScreenChanged()
  T.Ran("screen")
  T.Hud.FitScreen()
end

function ShroudOnTargetChanged()
  T.Ran("target")
  T.Target.OnTargetChanged()
end

function ShroudOnSocialChanged()
  T.Ran("social")
  T.Notify.Check(true)
end

-- The guild message of the day changed (API 18; the game checks twice a second).
function ShroudOnGuildMotdChanged()
  T.Ran("guild message")
  T.Notify.Check(true)
end

-- A notification count or flag changed (mail, ransoms, rewards, guild applications).
function ShroudOnNotificationsChanged()
  T.Ran("notifications")
  T.Notify.Check(true)
end

-- Web answers (only the SotANET price lookups ask for any).
function ShroudOnHttpResponse(requestId, ok, status, body, err)
  T.Ran("prices")
  T.Prices.OnResponse(requestId, ok, status, body, err)
end

-- Items for the daily stats (anything that arrives in your bags).
function ShroudOnItemsGained(items, dropped)
  T.Ran("items")
  local t0 = T.PerfT()
  T.Daily.OnItems(items, dropped)
  T.ProbeItems(items)
  T.PerfAdd("callback:items", t0)
end

-- API 18 result events: today's crafting and gathering (Toolbox.Daily), and the /toolbox api probe.
function ShroudOnCraftResults(results, dropped)
  T.Ran("crafting")
  local t0 = T.PerfT()
  T.Daily.OnCraftResults(results, dropped)
  T.Planner.OnCraftResults(results)
  T.ProbeEvent("craft", results, dropped)
  T.PerfAdd("callback:crafting", t0)
end

function ShroudOnGatherResults(results, dropped)
  T.Ran("gathering")
  T.Daily.OnGatherResults(results, dropped)
  T.Overlays.OnGathered(results)
  T.ProbeEvent("gather", results, dropped)
end

function ShroudOnCraftingStateChanged(state)
  T.Ran("crafting")
  T.Daily.OnCraftingState(state)
  T.Planner.Changed()
  T.ProbeEvent("state", state)
end

-- The reference: it fires once the login scene loads, the character gone and its file flushed by the game: a
-- character-scope write now would go to no character (toolbox.nochar.character.json). The session is ended in
-- memory (the next login starts a new one); what the character had was saved at the scene's unload and the flush.
function ShroudOnLogOut()
  T.Ran("logout")
  T.loggedOut = true                   -- the next login reads its settings again; no character writes until then
  if T.session then T.session.ended = true end
  T.Flush()                            -- the account file's changes
end

function ShroudOnDisableScript()
  T.Ran("shutdown")
  -- Not marked ended: it is not documented whether /lua reload goes through here.
  if T.session then T.SaveSession(false) end
  T.Daily.Save()
  T.BuffBar.SaveTimers()
  T.SavePrefs()
  T.Flush()
end
