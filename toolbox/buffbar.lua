-- Toolbox: buffbar.lua
-- A buff bar (/toolbox buffs): your buffs and debuffs as their real skill icons on a HUD
-- strip, with a clock-style sweep over each icon instead of a time readout, soonest to run out on
-- the left (permanent effects, then the long-lasting group, at the right end). Plus two
-- alerts that work whether or not the bar is shown:
--   * a buff is about to run out: fires once when a buff's remaining time crosses the
--     player's threshold (a buff that starts below it never fires);
--   * a debuff landed: fires when a debuff you didn't have appears (the API doesn't say
--     who applied it).
--
-- "Only during combat" (opt-in) shows the bar only in combat mode (and BB.COMBAT_LINGER seconds
-- after), or while the settings window is open so it can be placed; alerts run either way.
--
-- From API 16 two opt-in settings: "Replace the game's buff bar" hides the game's own bar
-- (ShroudSetBuffBarVisible; never saved by the game and released on reload, so it's asserted
-- again every tick while wanted), but only while this bar is actually showing; and "Click to
-- dismiss" makes a click on an icon dismiss that buff (ShroudDismissBuff, which needs the
-- player's click: never from a timer). Both are feature-detected.
--
-- Long-lasting buffs (Obsidian potions last days, and several can run at once) are grouped
-- into one slot at the end of the buff row: a count over the first one's icon, with each
-- buff and its time left in the tooltip. A buff goes there when it has more than
-- "group after" left (default 15 minutes; it moves back onto the bar once it drops below), or
-- when its name matches the player's list (a power-user extra, empty by default).
--
-- Data: ShroudGetPlayerBuff() (grouped by rune: IsDebuff, IconId) is read when
-- ShroudOnBuffsChanged fires; the flat per-effect list (names, time remaining, tooltips)
-- every BB.TICK seconds. Icons are a fixed pool of slots built once: changes only update
-- textures, frames, tooltips and visibility (element creation is rate-limited).

local T = Toolbox
local BB = {}
Toolbox.BuffBar = BB

local UI = Shroud.UI
local FRAME_ID = "toolbox_buffs"
local PERIODIC = "toolbox_buffbar"

BB.TICK = 0.5                 -- seconds between updates (sweep + alerts)
-- A frame stays up for a whole tick while the buff runs on, so the sweep is drawn for the middle of
-- that tick (BB.TICK / 2 ahead): on average level with the game's smooth sweep, not half a tick behind.
BB.SWEEP_LEAD = BB.TICK / 2
BB.BUFF_SLOTS, BB.DEBUFF_SLOTS = 20, 10
BB.SIZE_MIN, BB.SIZE_MAX, BB.SIZE_DEFAULT = 20, 48, 32
BB.ALERT_MIN, BB.ALERT_MAX, BB.ALERT_DEFAULT = 1, 60, 10
BB.GAP = 3
BB.GROUP_DEFAULT = {}               -- name parts grouped by default: none (the time rule does it)
-- Earlier defaults, cleared when found saved as they were: the Obsidian potions' rune names.
BB.GROUP_OLD_DEFAULTS = {
  { "Obsidian" },
  { "BlessingOfCapacity", "BlessingOfConservation", "BlessingOfExpedience", "BlessingOfPrecision",
    "BlessingOfPrevention", "BlessingOfReclamation", "BlessingOfStamina" },
}
-- "Group buffs lasting longer than": the choices (seconds; 0 = off) and the default.
BB.GROUP_AFTER_CHOICES = {
  { 0, "Off" }, { 300, "5 minutes" }, { 600, "10 minutes" }, { 900, "15 minutes" }, { 1800, "30 minutes" },
  { 3600, "1 hour" }, { 7200, "2 hours" }, { 14400, "4 hours" }, { 43200, "12 hours" }, { 86400, "1 day" },
}
BB.GROUP_AFTER_DEFAULT = 900
BB.GROUP_MAX = 20                  -- name parts kept
BB.GROUP_LEN = 40                  -- characters per name part
BB.HOME = { 40, 220 }         -- where the bar starts, and where Reset puts it
BB.NUDGE = 10                 -- pixels per nudge button press
BB.DEBUFF_SUPPRESS = 3        -- seconds after start / a scene change with no debuff alerts
-- Seconds after start, a scene change or a character change during which newly seen buffs count
-- as already running, not cast. At login the buff list fills in well after the add-on starts:
-- buffs taken for casts then had their time left learned as their full duration, and the sweep
-- lagged the game's for the rest of the run (found in game 2026-09-28).
BB.SETTLE = 15
BB.COMBAT_LINGER = 5          -- seconds the bar stays after combat ends ("only during combat")
BB.DEBUFF_COOLDOWN = 1        -- at most one debuff sound a second

-- The clock sprite sheet (art/clock.py): FRAMES frames in a COLS x ROWS grid, once per SET
-- stacked top to bottom: set 0 is the normal (dark) sweep, set 1 the warning (red) one.
-- 120 frames (3 degrees each): with fewer, a long buff (a 20-minute Light spell) moved so
-- rarely it looked frozen.
BB.CLOCK = { path = "toolbox/clock.png", FRAMES = 120, COLS = 20, ROWS = 6, SETS = 2 }

-- ---------------------------------------------------------------------------
-- Model (no API calls)
-- ---------------------------------------------------------------------------

-- A buff's full duration in seconds from its ShroudGetPlayerBuff() Effects, or nil.
-- CONFIRMED in game 2026-09-28 (`/toolbox buffs raw`): TotalDuration is the full length in seconds
-- and CurrentDuration the seconds left. A rune can apply several effects of different lengths, and
-- `remaining` is the rune's (its longest-running effect's), so the total comes from the effect whose
-- time left matches it. (This used to also accept milliseconds and "CurrentDuration = time elapsed",
-- guesses from before the fields could be read, and took the LONGEST total that fitted any of them:
-- another effect of the same rune could then set the sweep's length, putting it out of step with the
-- game's bar.)
function BB.TotalFromEffects(remaining, effects)
  if type(remaining) ~= "number" or remaining <= 0 or type(effects) ~= "table" then return nil end
  local best, bestGap = nil, nil
  for _, e in ipairs(effects) do
    local tot, cur = nil, nil
    if type(e) == "table" then tot, cur = e.TotalDuration, e.CurrentDuration end
    if type(tot) == "number" and type(cur) == "number" and tot > 0 and tot >= remaining - 0.5 then
      local gap = math.abs(cur - remaining)
      if gap <= 1.5 and (bestGap == nil or gap < bestGap or (gap == bestGap and tot > best)) then
        best, bestGap = tot, gap
      end
    end
  end
  return best
end

-- Tracks one buff's timer and returns st, fraction remaining (0..1) or nil when there is no
-- timer or its full duration isn't known, true when the expiry alert should fire now, and the
-- remaining seconds used.
--
-- Time left counts down from each run's end time (st.endAt, on the T.Now() clock), which
-- follows the game's value whenever it changes; a value that jumps up is a recast.
--
-- The sweep needs the full duration, which the game doesn't give (in game, TotalDuration /
-- CurrentDuration are nil). A run's total is trusted (st.trusted) only when:
--   * `fresh`: the buff appeared while the add-on was running, so its first time left IS
--     its full duration (also every recast);
--   * `known`: a duration from TotalFromEffects, a timer remembered across a reload, or one
--     learned from an earlier cast.
-- Otherwise (a buff already running when the add-on started, never seen cast) there is no
-- sweep rather than a wrong one. The expiry alert only needs time left, so it always works.
-- st.warned stays true for the rest of a run once the alert has fired (the sweep turns red).
function BB.Track(st, api, threshold, known, now, fresh)
  if type(api) ~= "number" or api <= 0 then return st, nil, false, nil end
  now = now or T.Now()
  if type(known) ~= "number" or known < api - 0.5 then known = nil end
  local function newRun(seenFromStart)
    local run = { endAt = now + api, api = api, armed = api > threshold, warned = false }
    if seenFromStart then
      run.total, run.trusted, run.learn = api, true, true
    elseif known then
      run.total, run.trusted = known, true
    else
      run.total, run.trusted = api, false
    end
    return run
  end
  if not st then
    st = newRun(fresh)
  elseif api ~= st.api then
    if api > (st.endAt - now) + 1.5 then
      st = newRun(true)                  -- time went up: a recast, seen from its start
    else
      st.endAt, st.api = now + api, api  -- follow the game's value
    end
  end
  local remaining = st.endAt - now
  if remaining < 0 then remaining = 0 end
  -- A known duration wins, except on the tick a run was seen starting (its own first time left
  -- is exact; a learned or remembered one may be out of date).
  if known and not st.learn then st.total, st.trusted = known, true end
  if remaining > st.total then st.total = remaining end
  st.last = remaining
  local fire = false
  if st.armed and remaining <= threshold then
    st.armed, st.warned, fire = false, true, true
  elseif remaining > threshold then
    st.armed = true
  end
  local fraction = (st.trusted and st.total > 0) and remaining / st.total or nil
  return st, fraction, fire, remaining
end

-- Consumables by rune name (the API has no item categories). FOUND in game 2026-09-28 (`/toolbox buffs
-- raw`): food is RuneFood_<dish> (e.g. RuneFood_Stew_Dragon, 8 h), the Obsidian potions BlessingOf<x>
-- (7 days). NOT potions: POT_Blessing_* and Rune_Reward_Blessing_Shrine_* are shrine blessings (owner).
-- Weapon poisons: not seen yet (unknown whether they show as a buff on the player at all).
BB.CONSUMABLE_PREFIXES = { { "RuneFood_", "food" }, { "BlessingOf", "potion" } }

-- "food", "potion" or "extra" (a name part the player added) for a rune name / displayed label, or nil.
function BB.ConsumableKind(name, label, extra)
  if type(name) ~= "string" then return nil end
  for _, p in ipairs(BB.CONSUMABLE_PREFIXES) do
    if name:sub(1, #p[1]) == p[1] then return p[2] end
  end
  local lname, llabel = name:lower(), type(label) == "string" and label:lower() or ""
  for _, part in ipairs(extra or {}) do
    local l = part:lower()
    if l ~= "" and (lname:find(l, 1, true) or llabel:find(l, 1, true)) then return "extra" end
  end
  return nil
end

-- Clock frame for a fraction remaining: 0 = full time left (no shading). The NEAREST frame: rounding
-- down kept the shading behind the true position by up to a frame (1/120 of the buff; 7.5 s of a
-- 15-minute one), and the game's own bar sweeps smoothly (reported 2026-09-28: "ours lags behind").
function BB.Frame(fraction)
  local n = BB.CLOCK.FRAMES
  local k = math.floor((1 - fraction) * n + 0.5)
  if k < 0 then k = 0 end
  if k > n - 1 then k = n - 1 end
  return k
end

-- UV rectangle (x, y, w, h as fractions, top-left origin) of a clock frame, from the
-- warning (red) set when `warn` is true.
function BB.FrameUV(k, warn)
  local c = BB.CLOCK
  local rows = c.ROWS * c.SETS
  local row = math.floor(k / c.COLS) + (warn and c.ROWS or 0)
  return (k % c.COLS) / c.COLS, row / rows, 1 / c.COLS, 1 / rows
end

-- Names in `now` that aren't in `before` (both sets name -> true).
function BB.NewNames(before, now)
  local out = {}
  for name in pairs(now) do
    if not before[name] then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- Whether a buff with `remaining` seconds left goes in the group by time: more than `after`
-- left (after > 0). Permanent effects (0 or less) don't: they have no time to go by.
function BB.GroupedByTime(remaining, after)
  return type(after) == "number" and after > 0 and type(remaining) == "number" and remaining > after
end

-- The label for a "group after" value in seconds ("15 minutes"), or nil when it isn't a choice.
function BB.GroupAfterLabel(seconds)
  for _, c in ipairs(BB.GROUP_AFTER_CHOICES) do
    if c[1] == seconds then return c[2] end
  end
  return nil
end

-- True when the rune name or the displayed name contains one of the name parts (any case).
function BB.Grouped(name, label, parts)
  local a, b = (name or ""):lower(), (label or ""):lower()
  for _, part in ipairs(parts or {}) do
    local p = part:lower()
    if p ~= "" and (a:find(p, 1, true) or b:find(p, 1, true)) then return true end
  end
  return false
end

-- Time left in the two biggest units: 612000 -> "7d 2h", 7260 -> "2h 1m", 245 -> "4m 5s", 9 -> "9s".
-- Nothing known (nil, negative, 0 for a permanent effect) -> "".
function BB.ShortTime(s)
  if type(s) ~= "number" or s <= 0 then return "" end
  s = math.floor(s)
  local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
  if d > 0 then return string.format("%dd %dh", d, h) end
  if h > 0 then return string.format("%dh %dm", h, m) end
  if m > 0 then return string.format("%dm %ds", m, s % 60) end
  return string.format("%ds", s)
end

-- Sorts { name, remaining } entries in place: soonest to run out first, buffs that never run
-- out (0 or less: permanent, or no time given) last; ties by name, so the order stays put.
local function byExpiry(x, y)
  local a = (type(x.remaining) == "number" and x.remaining > 0) and x.remaining or math.huge
  local b = (type(y.remaining) == "number" and y.remaining > 0) and y.remaining or math.huge
  if a ~= b then return a < b end
  return x.name < y.name
end

function BB.SortByExpiry(list)
  table.sort(list, byExpiry)             -- one comparison function, not a new one per call
  return list
end

-- The group slot's tooltip: a heading line, then "name: time left" per buff, longest first.
-- `list` is { { label, remaining } }.
function BB.GroupTooltip(list)
  local sorted = {}
  for i, g in ipairs(list) do sorted[i] = g end
  table.sort(sorted, function(x, y)
    local a, b = x[2] or 0, y[2] or 0
    if a ~= b then return a > b end
    return x[1] < y[1]
  end)
  local lines = { "Long-lasting buffs (" .. #sorted .. ")" }
  for _, g in ipairs(sorted) do
    local left = BB.ShortTime(g[2])
    lines[#lines + 1] = g[1] .. (left ~= "" and (": " .. left) or "")
  end
  return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------

local prefs = {}
local runes = {}          -- rune name -> { debuff, icon, total } from ShroudGetPlayerBuff
local remembered = {}     -- rune name -> { total, remaining, at } saved before a reload
local learned = {}        -- rune name -> full duration (s), seen from a cast (saved: buff_durations)
local preexisting = {}    -- names already present when the add-on started (not seen cast)
local sceneQuietUntil = 0 -- buffs first seen before this (start, scene load) aren't "fresh"
local lastPlayer = nil    -- the character seen last tick (a change settles like a scene load)
local lastSeen = {}       -- names in the effect list last tick
local inCombat = false    -- the game's combat mode
local combatUntil = 0     -- "only during combat": still shown until this T.Now() after combat
local lastShown = nil     -- BB.IsShown() at the last tick, to refresh the HUD when it changes
BB.GRACE = 10             -- seconds a vanished buff keeps its timer (scene loads)
local lastTimerSave = -math.huge
BB.TIMER_SAVE = 5         -- seconds between saves of the running timers (for a reload)
local debuffs = {}        -- debuff names seen at the last change (set)
local timers = {}         -- rune name -> BB.Track state
local quietUntil = 0      -- no debuff alerts before this T.Now()
local lastDebuffSound = -math.huge
local content = nil       -- the icon rows (in a strip owned by Toolbox.Hud)
local contentW, contentH = 0, 0
local slots = { buffs = {}, debuffs = {}, consumables = {} }
local clockTex = -1
-- Toolbox.Consumables (the bottom of this file): declared here so the buff bar's tick can hand it
-- food and potions.
local K = {}
Toolbox.Consumables = K
local kContent = nil      -- the consumables bar's row (its own strip, or a row of the buff bar when glued)
local kCount = 0          -- consumables showing on it
local group = nil         -- the long-lasting buffs' slot { row, icon, count, ... }
local groupedCache = {}   -- rune name -> grouped? (a rune's displayed name doesn't change)
local stockHidden = false -- we asked the game to hide its own buff bar

local function defaults()
  local parts = {}
  for i, p in ipairs(BB.GROUP_DEFAULT) do parts[i] = p end
  return { show = false, size = BB.SIZE_DEFAULT, expire = true, expireSeconds = BB.ALERT_DEFAULT, debuff = true,
           group = parts, groupAfter = BB.GROUP_AFTER_DEFAULT, replaceStock = false, clickDismiss = false,
           combatOnly = false, flash = true }
end

local function savePrefs()
  T.Save("buffbar", prefs)
end

local readEffects = nil
local labelFor = nil

-- A buff's displayed name without the game's colour markup ([c][27E833]...[-][/c]).
-- Only its first line, at most BB.LABEL_MAX characters: some descriptions run to several long
-- lines (one cut the debug line short and, with a pattern, stopped the add-on; 2026-09-28).
BB.LABEL_MAX = 60
function BB.PlainLabel(label, fallback)
  if type(label) ~= "string" or label == "Invalid" then return fallback end
  label = label:gsub("%[%x%x%x%x%x%x%x?%x?%]", ""):gsub("%[%-%]", ""):gsub("%[/?%a%]", "")
  label = T.Trim(label)
  local eol = label:find("[\r\n]")
  if eol then label = T.Trim(label:sub(1, eol - 1)) end
  if #label > BB.LABEL_MAX then label = T.Trim(label:sub(1, BB.LABEL_MAX - 3)) .. "..." end
  return label ~= "" and label or fallback
end

local function plainLabel(index, fallback)
  return BB.PlainLabel(ShroudGetBuffDescription(index), fallback)
end

-- The "group after" limit in use, in seconds (0 = off). This is where a game setting would come
-- in: the game's own buff bar has the same option, but add-ons can't read game settings yet
-- (asked for 2026-09-28). When they can, read it here, and let the player's choice apply only
-- when the game's can't be read.
function BB.GroupAfter()
  return prefs.groupAfter or BB.GROUP_AFTER_DEFAULT
end

-- A buff's display name, remembered by rune name (it doesn't change; read once, not twice a second).
local labels = {}
function labelFor(e)
  local l = labels[e.name]
  if not l then
    l = plainLabel(e.index, e.name)
    labels[e.name] = l
  end
  return l
end

-- Whether a buff goes in the long-lasting group (debuffs never do): by time left, or by name.
local function isGrouped(e)
  if BB.GroupedByTime(e.remaining, BB.GroupAfter()) then return true end
  local g = groupedCache[e.name]
  if g == nil then
    g = BB.Grouped(e.name, plainLabel(e.index, e.name), prefs.group)
    groupedCache[e.name] = g
  end
  return g
end

-- ---------------------------------------------------------------------------
-- The game's grouped buff list, as plain data
-- ---------------------------------------------------------------------------
-- The docs describe ShroudGetPlayerBuff() entries as tables; in game (2026-09-28) they are game
-- objects (userdata "LuaManager+RuneEffects"), which `pairs` can't walk and which every
-- `type(x) == "table"` check here skipped: no debuff flag, icon or Effects was ever read (so no
-- debuff sound, and no full durations). BB.ReadRunes copies the documented fields into tables.

-- Field `k` of a table or game object, or nil when it can't be read.
local function field(obj, k)
  local ty = type(obj)
  if ty ~= "table" and ty ~= "userdata" then return nil end
  local ok, v = pcall(function() return obj[k] end)
  if ok then return v end
  return nil
end

-- A list from the game as a Lua list: a table (1-based), or a game-side list (userdata) with
-- Count, indexed from 0 (C#) or else from 1.
local function items(list)
  local out = {}
  if type(list) == "table" then
    for i, v in ipairs(list) do out[i] = v end
    return out
  end
  if type(list) ~= "userdata" then return out end
  local n = field(list, "Count")
  if type(n) ~= "number" then
    local ok, len = pcall(function() return #list end)
    n = (ok and type(len) == "number") and len or 0
  end
  local base = (n > 0 and field(list, 0) == nil) and 1 or 0
  for i = base, base + n - 1 do
    local v = field(list, i)
    if v ~= nil then out[#out + 1] = v end
  end
  return out
end

BB.RUNE_FIELDS = { "RuneName", "RuneId", "IsDebuff", "IconId", "StackCount" }
BB.EFFECT_FIELDS = { "Description", "Value", "CurrentDuration", "TotalDuration", "TotalTick" }

-- ShroudGetPlayerBuff()'s answer as { { RuneName, RuneId, IsDebuff, IconId, StackCount,
-- Effects = { { Description, Value, CurrentDuration, TotalDuration, TotalTick } } } }.
function BB.ReadRunes(list)
  local out = {}
  for _, r in ipairs(items(list)) do
    local rune = { Effects = {} }
    for _, f in ipairs(BB.RUNE_FIELDS) do rune[f] = field(r, f) end
    for _, e in ipairs(items(field(r, "Effects"))) do
      local fx = {}
      for _, f in ipairs(BB.EFFECT_FIELDS) do fx[f] = field(e, f) end
      rune.Effects[#rune.Effects + 1] = fx
    end
    if type(rune.RuneName) == "string" then out[#out + 1] = rune end
  end
  return out
end

local function playerRunes()
  local ok, list = pcall(ShroudGetPlayerBuff)
  return BB.ReadRunes(ok and list or nil)
end

-- Re-reads the grouped list (debuff flags, icons, full durations) and raises the debuff alert.
-- `from` = "event" (ShroudOnBuffsChanged), "tick" (the bar saw the list change) or "start";
-- the first two are counted for debug.
BB.changes = { event = 0, tick = 0 }
function BB.OnBuffsChanged(from)
  if BB.changes[from] then BB.changes[from] = BB.changes[from] + 1 end
  local list = playerRunes()
  local remainingByName = {}
  for _, e in ipairs(readEffects()) do remainingByName[e.name] = e.remaining end
  runes = {}
  local now = {}
  for _, rune in ipairs(list) do
    runes[rune.RuneName] = { debuff = rune.IsDebuff == true, icon = rune.IconId,
      total = BB.TotalFromEffects(remainingByName[rune.RuneName], rune.Effects) }
    if rune.IsDebuff == true then now[rune.RuneName] = true end
  end
  local new = BB.NewNames(debuffs, now)
  debuffs = now
  if #new == 0 then return end
  -- What became of the last new debuff, for /toolbox buffs debug (a missing sound, 2026-09-28).
  local result = nil
  if not prefs.debuff then
    result = "not played: the debuff alert is off"
  elseif T.Now() < quietUntil then
    result = "not played: quiet just after start or a scene change"
  elseif T.Now() - lastDebuffSound < BB.DEBUFF_COOLDOWN then
    result = "not played: another debuff sounded under " .. BB.DEBUFF_COOLDOWN .. " s ago"
  else
    lastDebuffSound = T.Now()
    local ok, info = T.Sounds.Play("debuff_landed")
    result = ok and ("played on channel " .. tostring(info.channel))
      or ("not played: " .. tostring(info.reason) .. " (see /toolbox sounds)")
  end
  BB.lastDebuff = { name = table.concat(new, ", "), at = T.Now(), result = result }
end

-- A scene change rebuilds the buff list: treat what's there as already known.
function BB.Quiet()
  quietUntil = T.Now() + BB.DEBUFF_SUPPRESS
end

function BB.SceneChange()
  BB.Quiet()
  sceneQuietUntil = T.Now() + BB.SETTLE
end

-- One entry per rune in the game's order: { name, remaining, index (first flat index) }.
-- The list and its entries are reused call to call (it runs twice a second): callers must not
-- keep them past the tick.
local effOut, effByName, effPool = {}, {}, {}
function readEffects()
  local out, byName = effOut, effByName
  for k = #out, 1, -1 do out[k] = nil end
  for k in pairs(byName) do byName[k] = nil end
  local n = ShroudGetBuffCount() or 0
  for i = 0, n - 1 do
    local name = ShroudGetBuffName(i)
    if type(name) == "string" and name ~= "Invalid" then
      local remaining = ShroudGetBuffTimeRemaining(i)
      local e = byName[name]
      if not e then
        e = effPool[name]
        if not e then
          e = {}
          effPool[name] = e
        end
        e.name, e.remaining, e.index = name, remaining, i
        byName[name] = e
        out[#out + 1] = e
      elseif type(remaining) == "number" and remaining > (e.remaining or -1) then
        e.remaining, e.index = remaining, i   -- a rune lasts until its last effect ends; its tooltip
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- The game's buff bar and dismissing (API 16)
-- ---------------------------------------------------------------------------

function BB.CanReplace()
  return type(ShroudSetBuffBarVisible) == "function" and type(ShroudIsBuffBarVisible) == "function"
end

function BB.CanDismiss()
  return type(ShroudCanDismissBuff) == "function" and type(ShroudDismissBuff) == "function"
end

-- Hides the game's bar while "replace" is on and ours is showing; shows it otherwise, so the
-- player is never left without one. Runs every tick: the game forgets a hide on reload.
local function applyStock()
  if not BB.CanReplace() then return end
  local want = prefs.replaceStock == true and BB.IsShown() and content ~= nil
  if want then
    if not stockHidden or ShroudIsBuffBarVisible() == true then
      ShroudSetBuffBarVisible(false)
      stockHidden = true
    end
  elseif stockHidden then
    ShroudSetBuffBarVisible(true)
    stockHidden = false
  end
end

local DISMISS_REASONS = {
  notDismissable = "that buff can't be dismissed",
  notNow = "not right now (loading, talking, crafting, looting or in a menu)",
  needsGesture = "it needs a click",
  gestureSpent = "too many actions from one click",
  tooOften = "too many dismissals in a short time; wait a few seconds",
  badIndex = "the buff is gone",
}

-- The flat index of the buff called `name` now (indices shift as buffs come and go), or nil.
local function indexOf(name)
  local n = ShroudGetBuffCount() or 0
  for i = 0, n - 1 do
    if ShroudGetBuffName(i) == name then return i end
  end
  return nil
end

-- A click on an icon: dismiss that buff if "click to dismiss" is on. The slot's name is from the
-- last tick, so its index is looked up again now.
local function clickSlot(slot)
  if not prefs.clickDismiss or not BB.CanDismiss() or not slot.name then return end
  local i = indexOf(slot.name)
  if not i then return end
  if not ShroudCanDismissBuff(i) then
    T.Print("Can't dismiss " .. (slot.label or slot.name) .. ": that buff can't be dismissed.")
    return
  end
  local ok, reason = ShroudDismissBuff(i)
  if not ok then
    T.Print("Can't dismiss " .. (slot.label or slot.name) .. ": "
      .. (DISMISS_REASONS[reason] or tostring(reason)) .. ".")
  end
end

-- ---------------------------------------------------------------------------
-- HUD frame
-- ---------------------------------------------------------------------------

local function size() return prefs.size or BB.SIZE_DEFAULT end

-- The content's size for `used` icons across (the busier row) and `rows` rows. The strip is
-- sized to what is showing, not to the whole slot pool: the game keeps HUD frames on screen,
-- so a strip as wide as 20 empty slots couldn't be dragged near the right edge (reported).
local function contentSize(used, rows)
  local cell = size() + BB.GAP
  used = math.max(1, math.min(BB.BUFF_SLOTS + 1, used or 1))
  return used * cell, (rows or 1) * cell
end

local sizedFor = nil          -- "used,rows,size" the content was last sized for

-- Re-fits the strip to the icons showing (only when that changes). buffsShown counts the
-- group slot.
local function fitFrame(buffsShown, debuffsShown)
  local gear = T.Gear.GluedCount()     -- the equipment bar's row under the debuffs, when glued
  local cons = K.GluedCount()          -- the consumables row (above the equipment), when glued
  local used = math.max(buffsShown, debuffsShown, gear, cons)
  local rows = 1 + (debuffsShown > 0 and 1 or 0) + (gear > 0 and 1 or 0) + (cons > 0 and 1 or 0)
  local key = used .. "," .. rows .. "," .. size()
  if key == sizedFor or not content then return end
  sizedFor = key
  contentW, contentH = contentSize(used, rows)
  T.Hud.Refresh()
end

local function makeSlot(debuff)
  local s = size()
  -- The clock texture is a placeholder until a buff's icon is set. It's left out, not set to
  -- nil, when it didn't load: the game's Lua passes a nil entry on to the UI.
  local slotRef = {}
  local iconSpec = { width = s, height = s,  -- an Image only takes the pointer (tooltip) with a click handler
    onClick = function() clickSlot(slotRef) end }
  if clockTex >= 0 then iconSpec.texture = clockTex end
  local icon = UI.Image(iconSpec)
  local overlay = BB.SweepHolder(s)
  local slot = UI.Row{ visible = false, children = { icon, overlay },
    style = { width = s, height = s, marginRight = BB.GAP, backgroundColor = "#00000066",
              borderWidth = debuff and 2 or 0, borderColor = "@red" } }
  slotRef.row, slotRef.icon, slotRef.overlay, slotRef.used = slot, icon, overlay, false
  return slotRef
end

-- The count text's size for an icon of s pixels.
local function countFont(s) return math.max(9, math.min(32, math.floor(s * 0.5))) end

-- The long-lasting buffs' slot: the first one's icon with the count over it (the same overlap
-- by negative margin as the clock). Both take the pointer so the tooltip shows anywhere on it.
-- The count has a dark outline so it reads on any icon: Shroud.UI has no text outline or shadow,
-- so it is drawn four times in black, nudged a pixel each way, under the bright one (owner,
-- 2026-09-28: "blends in on some icons"). Black because the theme has no dark text colour.
BB.COUNT_OUTLINE = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }   -- (dx, dy) px of the dark copies
BB.OUTLINE_COLOR = "#000000"

-- A count label's style for icon size s, font f, nudged dx, dy pixels (padding on one side moves
-- centred text half as far, so it is doubled).
local function countStyle(s, f, dx, dy)
  local top = math.max(1, math.floor((s - f * 1.2) / 2))
  return { width = s, height = s, minHeight = s, maxHeight = s, marginLeft = -s, marginRight = 0,
           marginTop = 0, marginBottom = 0, paddingTop = math.max(0, top + dy),
           paddingLeft = dx > 0 and 2 * dx or 0, paddingRight = dx < 0 and -2 * dx or 0,
           fontSize = f, fontStyle = "bold", textAlign = "center" }
end

local function makeGroupSlot()
  local s = size()
  local f = countFont(s)
  local iconSpec = { width = s, height = s, onClick = function() end }
  if clockTex >= 0 then iconSpec.texture = clockTex end
  local icon = UI.Image(iconSpec)
  local children, counts = { icon }, {}
  for _, d in ipairs(BB.COUNT_OUTLINE) do
    local style = countStyle(s, f, d[1], d[2])
    style.color = BB.OUTLINE_COLOR
    counts[#counts + 1] = UI.Label{ text = "", style = style }
    children[#children + 1] = counts[#counts]
  end
  local count = UI.Label{ text = "", class = "bright", style = countStyle(s, f, 0, 0) }   -- on top
  counts[#counts + 1] = count
  children[#children + 1] = count
  local row = UI.Row{ visible = false, children = children,
    style = { width = s, height = s, marginRight = BB.GAP, backgroundColor = "#00000066" } }
  return { row = row, icon = icon, count = count, counts = counts, used = false }
end

-- Builds the icon rows (a fixed slot pool) and returns them; Toolbox.Hud puts them in a strip.
function BB.BuildContent()
  clockTex = ShroudLoadTexture(BB.CLOCK.path)
  local buffRow, debuffRow = {}, {}
  -- the consumables pool belongs to its own strip unless glued (then it is built here, below)
  slots = { buffs = {}, debuffs = {}, consumables = K.Glued() and {} or slots.consumables }
  for i = 1, BB.BUFF_SLOTS do
    slots.buffs[i] = makeSlot(false)
    buffRow[i] = slots.buffs[i].row
  end
  group = makeGroupSlot()
  buffRow[#buffRow + 1] = group.row
  for i = 1, BB.DEBUFF_SLOTS do
    slots.debuffs[i] = makeSlot(true)
    debuffRow[i] = slots.debuffs[i].row
  end
  sizedFor = nil
  contentW, contentH = contentSize(1, 1)
  local extraRows = K.Glued() or T.Gear.Glued()
  local rows = {
    UI.Row{ id = "buffs", style = { marginBottom = BB.GAP }, children = buffRow },
    UI.Row{ id = "debuffs", style = { marginBottom = extraRows and BB.GAP or 0 }, children = debuffRow },
  }
  if K.Glued() then                     -- the consumables bar as the next row
    rows[#rows + 1] = K.BuildRow(T.Gear.Glued())
  end
  if T.Gear.Glued() then                -- the equipment bar as the last row
    rows[#rows + 1] = T.Gear.BuildRow()
  end
  content = UI.Column{ id = "buffbar", children = rows }
  return content
end

function BB.ContentSize() return contentW, contentH end
function BB.GetSavedPosition() return prefs.x, prefs.y end
function BB.SavePosition(x, y)
  if x ~= prefs.x or y ~= prefs.y then
    prefs.x, prefs.y = x, y
    savePrefs()
  end
end

-- Puts entry e (or nothing) into a slot, touching only what changed. `warn` shows the
-- red sweep (the buff's expiry alert has fired); `flash` also blinks a red border, on and off
-- with each tick (owner, 2026-09-28: "flash red when it's about to run out").
-- Clears a slot's sweep and flash for its next buff. Slots are reused (never created per buff),
-- and a red sweep stayed on the next buff in the slot after one ran out (reported 2026-09-28): so
-- a new occupant starts from a clean slot, not from what the last one left.
local pendingSweeps = {}      -- slots whose sweep needs a new frame (see drawSweeps)

local function resetSlot(slot)
  BB.HideFrame(slot)
  slot.wantK, slot.wantWarn = nil, nil
  if slot.blink ~= false then slot.row:SetStyle{ borderWidth = 0 } end
  slot.k, slot.warn, slot.blink, slot.tip = nil, nil, false, nil
end

-- /toolbox buffs frame <k> [red]: every icon on the bar shows clock frame k for BB.FRAME_TEST_SECONDS,
-- whatever its buff's time, to compare what the game draws with what was asked for (reported
-- 2026-09-28: a sweep under half covered at the expiry alert, while the trace said 96%).
BB.FRAME_TEST_SECONDS = 15
local frameTest = nil          -- { k, warn, till } while a test runs

-- How a sweep frame reaches the screen. FOUND in game 2026-09-28 (`/toolbox buffs uvtest`): this
-- client draws an Image's UV only when the Image is created. SetUV on an existing one changes nothing
-- on screen (also after SetTexture, a hide/show, or with an IconButton), so a sweep stayed at the frame
-- it first showed: it "lagged", "barely moved", and sat under half covered at the expiry alert. So
-- each slot's overlay is a holder (a Row over the icon, by negative margin) whose Image is replaced,
-- with `uv` in its spec, whenever the frame changes. If a client update makes SetUV redraw, the
-- uvtest will show it (way 1 sweeping).
-- Load (owner, 2026-09-28: "50 a second seems like a lot"): at most BB.SWEEP_RATE new Images a second
-- for all sweeps together (a token bucket, BB.SWEEP_BURST deep, so a few new buffs start at once).
-- Sweeps that can't all be redrawn take turns by how far behind they are (drawSweeps).
BB.SWEEP_RATE, BB.SWEEP_BURST = 8, 10
local sweepTokens, sweepAt = BB.SWEEP_BURST, nil

-- A slot's overlay holder for an s px icon: empty and hidden until a frame is shown.
function BB.SweepHolder(s)
  return UI.Row{ visible = false, style = { width = s, height = s, marginLeft = -s } }
end

local function replaceSweep(holder, k, warn, s)
  local x, y, w, h = BB.FrameUV(k, warn)
  holder:Clear()
  holder:Add(UI.Image{ texture = clockTex, width = s, height = s, uv = { x, y, w, h } })
end

-- Shows clock frame k (> 0) of the normal or red set in `slot.overlay` (an s px holder). Returns
-- false when the rate is used up (nothing changed: try again next tick). `force` (the frame test)
-- ignores the rate.
function BB.ShowFrame(slot, k, warn, s, force)
  local now = T.Now()
  sweepTokens = math.min(BB.SWEEP_BURST, sweepTokens + (now - (sweepAt or now)) * BB.SWEEP_RATE)
  sweepAt = now
  if sweepTokens < 1 and not force then return false end
  local ok = pcall(replaceSweep, slot.overlay, k, warn, s)
  if not ok then                         -- the game's creation cap: leave it for the next tick
    sweepTokens = 0
    return false
  end
  sweepTokens = math.max(0, sweepTokens - 1)
  if slot.sweepShown ~= true then
    slot.overlay:SetVisible(true)
    slot.sweepShown = true
  end
  return true
end

function BB.HideFrame(slot)
  if slot.sweepShown ~= false then
    slot.overlay:SetVisible(false)
    slot.sweepShown = false
  end
end

-- /toolbox buffs uvtest: a standalone check of how the game redraws a sprite-sheet frame, away from
-- the buff bar's own logic. A small HUD strip shows the clock sheet six times, each stepping through
-- the frames a different way for BB.UVTEST_SECONDS; the player reports which ones animate.
BB.UVTEST_SECONDS, BB.UVTEST_STEP, BB.UVTEST_FRAMES_PER_STEP = 20, 0.5, 4
BB.UVTEST_WAYS = {
  { "uv", "SetUV only" },
  { "toggle", "hide, SetUV, show (same moment)" },
  { "later", "hide, then SetUV + show 0.1 s later" },
  { "texture", "SetTexture again, then SetUV" },
  { "rebuild", "a new Image (uv in its spec) each step" },
  { "iconbutton", "an IconButton instead of an Image, SetUV" },
}
local uvtest = nil

local function uvtestStop()
  if not uvtest then return end
  ShroudRemovePeriodic("toolbox_uvtest")
  ShroudRemovePeriodic("toolbox_uvtest_later")
  pcall(function() uvtest.frame:Destroy() end)
  uvtest = nil
end

local function uvtestImage(way, k, s)
  local x, y, w, h = BB.FrameUV(k, false)
  if way == "iconbutton" then
    -- its own spec: an IconButton has no width/height fields, and setting a key to nil doesn't
    -- remove it in the game's Lua (the UI then rejects it; 2026-09-28)
    return UI.IconButton{ texture = clockTex, uv = { x, y, w, h }, onClick = function() end,
      style = { width = s, height = s, padding = 0 } }
  end
  return UI.Image{ texture = clockTex, width = s, height = s, uv = { x, y, w, h } }
end

local function uvtestStep()
  local t = uvtest
  if not t then return end
  if T.Now() - t.started >= BB.UVTEST_SECONDS then
    uvtestStop()
    T.Print("UV test finished.")
    return
  end
  t.k = (t.k + BB.UVTEST_FRAMES_PER_STEP) % BB.CLOCK.FRAMES
  if t.k == 0 then t.k = BB.UVTEST_FRAMES_PER_STEP end
  local k = t.k
  local x, y, w, h = BB.FrameUV(k, false)
  for i, c in ipairs(t.cells) do
    local ok, err = pcall(function()
      if c.way == "uv" or c.way == "iconbutton" then
        c.img:SetUV(x, y, w, h)
      elseif c.way == "toggle" then
        c.img:SetVisible(false)
        c.img:SetUV(x, y, w, h)
        c.img:SetVisible(true)
      elseif c.way == "later" then
        c.img:SetVisible(false)
        ShroudRegisterPeriodic("toolbox_uvtest_later", function()
          if uvtest then
            c.img:SetUV(x, y, w, h)
            c.img:SetVisible(true)
          end
        end, 0.1, false)
      elseif c.way == "texture" then
        c.img:SetTexture(clockTex)
        c.img:SetUV(x, y, w, h)
      elseif c.way == "rebuild" then
        c.holder:Clear()
        c.img = c.holder:Add(uvtestImage("rebuild", k, t.size))
      end
      c.label:SetText(i .. ": " .. math.floor(k * 100 / BB.CLOCK.FRAMES) .. "%")
    end)
    if not ok and not c.failed then
      c.failed = true
      T.Print("UV test way " .. i .. " (" .. c.way .. ") raised: " .. tostring(err))
    end
  end
end

-- Starts the UV test (or stops one that is running). Returns true, or false and why.
function BB.UVTest()
  if uvtest then
    uvtestStop()
    return false, "stopped"
  end
  if clockTex < 0 then clockTex = ShroudLoadTexture(BB.CLOCK.path) end
  if clockTex < 0 then return false, "the clock picture " .. BB.CLOCK.path .. " isn't available" end
  local s, gap = 40, 8
  local cols, cells = {}, {}
  for i, way in ipairs(BB.UVTEST_WAYS) do
    local img = uvtestImage(way[1], BB.UVTEST_FRAMES_PER_STEP, s)
    -- a light square behind each (the theme's text colour), so the dark wedge shows clearly
    local holder = UI.Row{ style = { width = s, height = s, backgroundColor = "@text" }, children = { img } }
    local label = UI.Label{ text = i .. ": starting", class = "text",
      style = { fontSize = 10, width = s + gap, marginLeft = 0, marginRight = 0 } }
    cols[i] = UI.Column{ style = { marginRight = gap }, children = { holder, label } }
    cells[i] = { way = way[1], img = img, holder = holder, label = label }
  end
  local ok, frame = pcall(UI.HudFrame, { id = "toolbox_uvtest", x = 300, y = 200,
    width = T.Window.GRIP + #cols * (s + gap) + 16, height = s + 40,
    children = { UI.Row{ style = { paddingLeft = T.Window.GRIP }, children = cols } } })
  if not ok then return false, "couldn't open its HUD strip: " .. tostring(frame) end
  uvtest = { frame = frame, cells = cells, k = BB.UVTEST_FRAMES_PER_STEP, started = T.Now(), size = s }
  ShroudRegisterPeriodic("toolbox_uvtest", uvtestStep, BB.UVTEST_STEP, true)
  return true
end

-- Starts (k = 0..FRAMES-1) or ends (k = nil) a frame test. Returns the number of icons it covers,
-- or nil and a reason.
function BB.FrameTest(k, warn)
  if k == nil then
    frameTest = nil
    BB.Tick()
    return 0
  end
  if type(k) ~= "number" or k ~= math.floor(k) or k < 0 or k >= BB.CLOCK.FRAMES then
    return nil, "a frame from 0 to " .. (BB.CLOCK.FRAMES - 1)
  end
  if clockTex < 0 then return nil, "the clock picture " .. BB.CLOCK.path .. " isn't available" end
  frameTest = { k = k, warn = warn == true, till = T.Now() + BB.FRAME_TEST_SECONDS }
  BB.Tick()
  local n = 0
  for _, pool in pairs(slots) do
    for _, slot in ipairs(pool) do
      if slot.used then n = n + 1 end
    end
  end
  return n
end

local function fill(slot, e, fraction, warn, flash)
  if not e then
    if slot.used then
      slot.row:SetVisible(false)
      resetSlot(slot)
    end
    slot.used, slot.name, slot.label = false, nil, nil
    return
  end
  if not slot.used then slot.row:SetVisible(true) end
  slot.used = true
  if slot.name ~= e.name then
    resetSlot(slot)
    slot.name, slot.label = e.name, plainLabel(e.index, e.name)
  end
  local blink = flash == true and math.floor(T.Now() * 2) % 2 == 0
  if blink ~= (slot.blink == true) then
    slot.blink = blink
    slot.row:SetStyle{ borderWidth = blink and 2 or 0 }
  end
  local rune = runes[e.name] or {}
  local tex = (type(rune.icon) == "number" and rune.icon >= 0) and rune.icon or ShroudGetBuffIcon(e.index)
  if tex ~= slot.tex then
    slot.tex = tex
    if type(tex) == "number" and tex >= 0 then
      slot.icon:SetTexture(tex)
      slot.icon:SetVisible(true)
    else
      slot.icon:SetVisible(false)
    end
  end
  local tip = ShroudGetBuffTooltip(e.index)
  if prefs.clickDismiss and BB.CanDismiss() and ShroudCanDismissBuff(e.index) then
    tip = (tip ~= "" and tip or e.name) .. "\nClick to dismiss"
  end
  if tip ~= slot.tip then
    slot.tip = tip
    slot.icon:SetTooltip(tip ~= "" and tip or e.name)
  end
  local k = fraction and BB.Frame(fraction) or nil
  warn = warn == true
  if frameTest then
    if T.Now() < frameTest.till then
      k, warn = frameTest.k, frameTest.warn
    else
      frameTest = nil
    end
  end
  if k ~= slot.k or warn ~= slot.warn then
    if k and k > 0 and clockTex >= 0 then
      slot.wantK, slot.wantWarn = k, warn        -- drawn by drawSweeps, oldest first, within the budget
      if not slot.pending then
        slot.pending = true
        pendingSweeps[#pendingSweeps + 1] = slot
      end
    else
      BB.HideFrame(slot)
      slot.k, slot.warn = k, warn
    end
  end
end

-- Redraws the sweeps fill() asked for as far as BB.SWEEP_RATE goes; the rest stay pending (fill asks
-- again next tick). Most urgent first: turning red (the expiry alert fired), then the most frames
-- behind, so short buffs (which fall behind fastest) get more turns than long ones, and none starves
-- (an earlier first-come order left the last of 30 fast sweeps never redrawn).
local function behind(slot)
  if slot.wantWarn ~= slot.warn then return math.huge end
  if not slot.k then return BB.CLOCK.FRAMES end
  return math.abs(slot.wantK - slot.k)
end
local function byUrgency(a, b)
  local x, y = behind(a), behind(b)
  if x ~= y then return x > y end
  return (a.drawnAt or -math.huge) < (b.drawnAt or -math.huge)
end
local function drawSweeps()
  if #pendingSweeps == 0 then return end
  table.sort(pendingSweeps, byUrgency)
  local s, now, testing = size(), T.Now(), frameTest ~= nil
  for i = 1, #pendingSweeps do
    local slot = pendingSweeps[i]
    pendingSweeps[i] = nil
    slot.pending = false
    if slot.used and slot.wantK and (slot.wantK ~= slot.k or slot.wantWarn ~= slot.warn)
        and BB.ShowFrame(slot, slot.wantK, slot.wantWarn, s, testing) then
      slot.k, slot.warn, slot.drawnAt = slot.wantK, slot.wantWarn, now
    end
  end
end

-- Shows the long-lasting buffs' slot for `list` ({ { label, remaining, icon } }), or hides it.
local function fillGroup(list)
  if not group then return end
  if #list == 0 then
    if group.used then group.row:SetVisible(false) end
    group.used, group.n, group.tip, group.tex = false, nil, nil, nil
    return
  end
  if not group.used then group.row:SetVisible(true) end
  group.used = true
  local tex = list[1][3]
  if tex ~= group.tex then
    group.tex = tex
    if type(tex) == "number" and tex >= 0 then group.icon:SetTexture(tex) end
  end
  if #list ~= group.n then
    group.n = #list
    for _, c in ipairs(group.counts) do c:SetText(tostring(#list)) end
  end
  local tip = BB.GroupTooltip(list)
  if tip ~= group.tip then
    group.tip = tip
    group.icon:SetTooltip(tip)
    for _, c in ipairs(group.counts) do c:SetTooltip(tip) end
  end
end

-- ---------------------------------------------------------------------------
-- Tick: timers, alerts, and the bar
-- ---------------------------------------------------------------------------

-- Reused by BB.Tick: two "seen" sets taking turns (the last one is kept as lastSeen), and the
-- display lists with their entry tables.
local seenA, seenB = {}, {}
local groupedList, buffList, debuffList, consList = {}, {}, {}, {}
local groupedPool, buffPool, debuffPool, consPool = {}, {}, {}, {}
local NOTHING = {}

local function clear(t)
  for k in pairs(t) do t[k] = nil end
  return t
end

local function pooled(pool, i)
  local x = pool[i]
  if not x then
    x = {}
    pool[i] = x
  end
  return x
end

function BB.Tick()
  local effects = readEffects()
  local seen = clear(lastSeen == seenA and seenB or seenA)
  local grouped, shownBuffs, shownDebuffs = clear(groupedList), clear(buffList), clear(debuffList)
  local shownCons = clear(consList)
  local threshold = prefs.expireSeconds or BB.ALERT_DEFAULT
  local expiring = false
  local shown = BB.IsShown()
  if shown ~= lastShown then          -- combat started or ended, the settings window opened or closed
    lastShown = shown
    T.Hud.Refresh()
  end
  local who = ShroudGetPlayerName()
  if who ~= lastPlayer then
    lastPlayer = who
    sceneQuietUntil = math.max(sceneQuietUntil, T.Now() + BB.SETTLE)   -- logged in, or another character
  end
  -- Two or more buffs appearing in the same tick came in with a login or a zone change, not from
  -- casts: nobody casts two buffs within half a second.
  local newNow = 0
  for _, e in ipairs(effects) do
    seen[e.name] = true
    if not lastSeen[e.name] then newNow = newNow + 1 end
  end
  -- The list changed (a name came or went): re-read debuff flags and run the debuff alert here
  -- too, not only from ShroudOnBuffsChanged, so the alert doesn't depend on that callback
  -- (reported 2026-09-28: no debuff sound). A second run for the same change finds nothing new.
  local changed = newNow > 0
  for name in pairs(lastSeen) do
    if not seen[name] then changed = true end
  end
  if changed then BB.OnBuffsChanged("tick") end
  local settling = T.Now() < sceneQuietUntil or newNow >= 2
  for _, e in ipairs(effects) do
    local rune = runes[e.name] or NOTHING
    local known = rune.total
    if not known and not timers[e.name] then known = BB.Recall(e.name, e.remaining) end
    if not known then known = learned[e.name] end
    local fresh = not preexisting[e.name] and not settling
    local st, fraction, fire = BB.Track(timers[e.name], e.remaining, threshold, known, nil, fresh)
    if fraction and st.total > 0 then fraction = math.max(0, fraction - BB.SWEEP_LEAD / st.total) end
    if st and st.learn then
      st.learn = nil
      BB.Learn(e.name, st.total)
    end
    if st then st.missingSince = nil end
    timers[e.name] = st
    if fire and not rune.debuff then expiring = true end
    local consumable = not rune.debuff and K.Takes(e)
    if consumable then                   -- on the consumables bar, not the buff bar
      local x = pooled(consPool, #shownCons + 1)
      x.e, x.fraction, x.warn, x.name, x.remaining = e, fraction, st ~= nil and st.warned == true, e.name,
        e.remaining
      shownCons[#shownCons + 1] = x
    elseif content and shown then
      if rune.debuff then
        local x = pooled(debuffPool, #shownDebuffs + 1)
        x.e, x.fraction, x.warn, x.name, x.remaining = e, fraction, false, e.name, e.remaining
        shownDebuffs[#shownDebuffs + 1] = x
      elseif isGrouped(e) then
        local tex = (type(rune.icon) == "number" and rune.icon >= 0) and rune.icon or ShroudGetBuffIcon(e.index)
        local x = pooled(groupedPool, #grouped + 1)
        x[1], x[2], x[3] = labelFor(e), e.remaining, tex
        grouped[#grouped + 1] = x
      else
        local x = pooled(buffPool, #shownBuffs + 1)
        x.e, x.fraction, x.warn, x.name, x.remaining = e, fraction, st ~= nil and st.warned == true, e.name,
          e.remaining
        shownBuffs[#shownBuffs + 1] = x
      end
    end
  end
  lastSeen = seen
  -- A vanished buff keeps its timer for BB.GRACE seconds (a scene load empties the list).
  for name, st in pairs(timers) do
    if not seen[name] then
      st.missingSince = st.missingSince or T.Now()
      if T.Now() - st.missingSince >= BB.GRACE then
        timers[name] = nil
        preexisting[name] = nil        -- next time it appears, it was cast
      end
    end
  end
  if content and shown then
    BB.SortByExpiry(shownBuffs)
    BB.SortByExpiry(shownDebuffs)
    for i = 1, BB.BUFF_SLOTS do
      local s = shownBuffs[i]
      if s then fill(slots.buffs[i], s.e, s.fraction, s.warn, s.warn and prefs.flash) else fill(slots.buffs[i], nil) end
    end
    for i = 1, BB.DEBUFF_SLOTS do
      local s = shownDebuffs[i]
      if s then fill(slots.debuffs[i], s.e, s.fraction) else fill(slots.debuffs[i], nil) end
    end
    fillGroup(grouped)                 -- always last: the longest-lasting buffs
  end
  K.Fill(shownCons)                    -- before the fit: a glued consumables row counts in it
  if content and shown then
    fitFrame(math.min(#shownBuffs, BB.BUFF_SLOTS) + (#grouped > 0 and 1 or 0),
      math.min(#shownDebuffs, BB.DEBUFF_SLOTS))
  end
  drawSweeps()
  if expiring and prefs.expire then T.Sounds.Play("buff_expiring") end
  if T.Now() - lastTimerSave >= BB.TIMER_SAVE then BB.SaveTimers() end
  applyStock()
end

-- One chat line per current effect, for checking durations in game:
-- "Light: 9.5 s left; TotalDuration 40, CurrentDuration 30.5; full duration 40 s (from the game)".
-- %g: the same text on every Lua (5.3+ would print 39.0 where MoonSharp prints 39).
local function num(x) return type(x) == "number" and string.format("%g", x) or tostring(x) end

-- /toolbox buffs raw: ShroudGetPlayerBuff() as the game returns it: each entry's type and its
-- documented fields as read (BB.ReadRunes), its first effect's fields, and how many RuneNames
-- match the flat list's names.
BB.RAW_MAX = 25
function BB.RawLines()
  local ok, list = pcall(ShroudGetPlayerBuff)
  if not ok then return { "ShroudGetPlayerBuff() raised: " .. tostring(list) } end
  local flat, flatCount = {}, 0
  for _, e in ipairs(readEffects()) do
    flat[e.name] = true
    flatCount = flatCount + 1
  end
  local raw = items(list)
  local runesRead = BB.ReadRunes(list)
  local lines, matched = {}, 0
  for i, rune in ipairs(runesRead) do
    if flat[rune.RuneName] then matched = matched + 1 end
    if i <= BB.RAW_MAX then
      local parts = {}
      for _, f in ipairs(BB.RUNE_FIELDS) do parts[#parts + 1] = f .. "=" .. tostring(rune[f]) end
      local fx = rune.Effects[1]
      local inner = {}
      if fx then
        for _, f in ipairs(BB.EFFECT_FIELDS) do inner[#inner + 1] = f .. "=" .. tostring(fx[f]) end
      end
      lines[#lines + 1] = "  [" .. i .. "] " .. type(raw[i]) .. ": " .. table.concat(parts, "; ") .. "; Effects="
        .. #rune.Effects .. (fx and (" [1] {" .. table.concat(inner, ", ") .. "}") or "")
    end
  end
  table.insert(lines, 1, string.format("ShroudGetPlayerBuff(): %s, %d entries (%d read); %d RuneNames match the"
    .. " %d names from ShroudGetBuffName", type(list), #raw, #runesRead, matched, flatCount))
  return lines
end

function BB.DebugLines()
  local lines = {}
  local byName = {}
  for _, rune in ipairs(playerRunes()) do byName[rune.RuneName] = rune end
  for _, e in ipairs(readEffects()) do
    local rune = byName[e.name] or {}
    local fx = rune.Effects and rune.Effects[1] or {}
    local fromGame = BB.TotalFromEffects(e.remaining, rune.Effects)
    local st = timers[e.name]
    local source = fromGame and "from the game" or learned[e.name] and "learned from a cast"
      or (st and st.trusted) and "seen cast or remembered" or "unknown: cast it once"
    local label = plainLabel(e.index, e.name)
    local named = label ~= e.name and (label .. " [" .. e.name .. "]") or e.name
    lines[#lines + 1] = string.format("%s%s: %s s left; TotalDuration %s, CurrentDuration %s; full duration %s (%s)",
      named, rune.IsDebuff and " (debuff)" or "", num(e.remaining), num(fx.TotalDuration),
      num(fx.CurrentDuration), st and (num(st.total) .. " s") or "?", source)
  end
  if #lines == 0 then lines[1] = "No buffs or debuffs right now." end
  lines[#lines + 1] = "Buff list changes seen: " .. BB.changes.event .. " from ShroudOnBuffsChanged, "
    .. BB.changes.tick .. " by the bar's own check. Debuff alert: " .. (prefs.debuff and "on" or "off") .. "."
  local ld = BB.lastDebuff
  lines[#lines + 1] = ld and string.format("Last new debuff: %s, %d s ago: %s.", ld.name,
    math.floor(T.Now() - ld.at), ld.result) or "Last new debuff: none seen since the add-on started."
  if BB.CanReplace() then
    lines[#lines + 1] = "Game's buff bar: " .. (ShroudIsBuffBarVisible() and "showing" or "hidden")
      .. " (Toolbox is " .. (stockHidden and "hiding it" or "not hiding it") .. ")."
  end
  return lines
end

-- /toolbox buffs trace [name]: once a second for BB.TRACE_SECONDS, log buffs' raw game values
-- next to what the bar uses, to see how the game reports buff time. With a name, only buffs
-- whose rune name or displayed name contains it (any case); without, the first BB.TRACE_MAX.
BB.TRACE_SECONDS = 10
BB.TRACE_MAX = 8
BB.TRACE_EFFECTS = 6            -- effects listed per buff in a trace line
function BB.Trace(filter)
  filter = (filter or ""):lower()
  local n = 0
  ShroudRegisterPeriodic("toolbox_bufftrace", function()
    n = n + 1
    local byName = {}
    for _, rune in ipairs(playerRunes()) do byName[rune.RuneName] = rune end
    local shown = 0
    for _, e in ipairs(readEffects()) do
      local label = plainLabel(e.index, e.name)
      local match = filter == "" or e.name:lower():find(filter, 1, true) or label:lower():find(filter, 1, true)
      if match and shown < BB.TRACE_MAX then
        shown = shown + 1
        local st = timers[e.name]
        local named = label == e.name and e.name or (label .. " [" .. e.name .. "]")
        local effects = byName[e.name] and byName[e.name].Effects
        -- every effect of the rune as "left/total" (a rune can apply several of different lengths)
        local parts = {}
        if type(effects) == "table" then
          for k, fx in ipairs(effects) do
            if k <= BB.TRACE_EFFECTS then
              parts[#parts + 1] = num(fx.CurrentDuration) .. "/" .. num(fx.TotalDuration)
            end
          end
          if #effects > BB.TRACE_EFFECTS then parts[#parts + 1] = "..." end
        end
        -- the sweep frame the slot is showing now (what should be on screen)
        local sweep = "not on the bar"
        for _, slot in ipairs(slots.buffs) do
          if slot.used and slot.name == e.name then
            sweep = (slot.k and slot.k > 0) and string.format("frame %d/%d (%d%% shaded%s)", slot.k, BB.CLOCK.FRAMES,
              math.floor(slot.k * 100 / BB.CLOCK.FRAMES), slot.warn and ", red" or "") or "no sweep"
          end
        end
        for _, slot in ipairs(slots.debuffs) do
          if slot.used and slot.name == e.name then
            sweep = (slot.k and slot.k > 0) and string.format("frame %d/%d (%d%% shaded)", slot.k, BB.CLOCK.FRAMES,
              math.floor(slot.k * 100 / BB.CLOCK.FRAMES)) or "no sweep"
          end
        end
        T.Print(string.format("+%ds %s: game %s left (effects left/total: %s) | bar %s of %s | %s",
          n, named, num(e.remaining), #parts > 0 and table.concat(parts, ", ") or "none",
          st and string.format("%.1f", st.last or -1) or "?",
          st and (string.format("%.1f", st.total) .. (st.trusted and "" or " (unknown)")) or "?", sweep))
      end
    end
    if shown == 0 then
      T.Print("+" .. n .. "s: no buffs" .. (filter ~= "" and (" matching '" .. filter .. "'") or ""))
    end
    if n >= BB.TRACE_SECONDS then ShroudRemovePeriodic("toolbox_bufftrace") end
  end, 1, true)
  local what = filter ~= "" and ("buffs matching '" .. filter .. "'") or ("up to " .. BB.TRACE_MAX .. " buffs")
  T.Print("Tracing " .. what .. " for " .. BB.TRACE_SECONDS .. " s...")
end

-- Records a buff's full duration, seen from a cast, for next time it is already running.
-- Saved as { v = 2, durations = { [name] = seconds } }: unversioned saves were learned before the
-- login settling (BB.SETTLE) and may hold time left at login instead of a full duration.
function BB.Learn(name, total)
  if type(total) ~= "number" or total <= 0 or learned[name] == total then return end
  learned[name] = math.floor(total * 10 + 0.5) / 10
  T.Save("buff_durations", { v = 2, durations = learned })
end

-- Remembers the running timers so a /lua reload can pick them up (ShroudTime keeps running
-- through a reload, so "remaining then minus time since" is where each should be now).
function BB.SaveTimers()
  lastTimerSave = T.Now()
  local out = {}
  for name, st in pairs(timers) do
    if st and st.trusted and st.last and st.last > 0 then
      out[name] = { total = st.total, remaining = st.last, at = T.Now() }
    end
  end
  -- v3: only trusted totals, learned with the login settling. v1/v2 saves could hold a wrong total.
  T.Save("buff_timers", { v = 3, timers = out })
end

-- A remembered full duration for a buff seen for the first time since start, when its
-- remaining time is where the remembered one would be now (within 2 s); otherwise nil.
function BB.Recall(name, remaining)
  local r = remembered[name]
  remembered[name] = nil
  if type(r) ~= "table" or type(r.total) ~= "number" or type(r.remaining) ~= "number" or type(r.at) ~= "number" then
    return nil
  end
  local now = T.Now()
  if r.at > now or type(remaining) ~= "number" then return nil end
  if math.abs((r.remaining - (now - r.at)) - remaining) > 2 then return nil end
  return r.total
end

function BB.Init()
  local saved = T.Load("buffbar")
  prefs = defaults()
  if type(saved) == "table" then
    prefs.show = saved.show == true
    if type(saved.size) == "number" and saved.size >= BB.SIZE_MIN and saved.size <= BB.SIZE_MAX then
      prefs.size = math.floor(saved.size)
    end
    prefs.expire = saved.expire ~= false
    if type(saved.expireSeconds) == "number" and saved.expireSeconds >= BB.ALERT_MIN
        and saved.expireSeconds <= BB.ALERT_MAX then
      prefs.expireSeconds = math.floor(saved.expireSeconds)
    end
    prefs.debuff = saved.debuff ~= false
    if BB.GroupAfterLabel(saved.groupAfter) then prefs.groupAfter = saved.groupAfter end
    prefs.replaceStock = saved.replaceStock == true
    prefs.clickDismiss = saved.clickDismiss == true
    prefs.combatOnly = saved.combatOnly == true
    prefs.flash = saved.flash ~= false
    -- A list saved exactly as an earlier default is taken as unset (the time rule replaced it).
    local old = false
    if type(saved.group) == "table" then
      for _, d in ipairs(BB.GROUP_OLD_DEFAULTS) do
        local same = #saved.group == #d
        for i = 1, #d do if saved.group[i] ~= d[i] then same = false end end
        if same then old = true end
      end
    end
    if type(saved.group) == "table" and not old then
      prefs.group = {}
      for _, p in ipairs(saved.group) do
        if type(p) == "string" and p ~= "" and #prefs.group < BB.GROUP_MAX then
          prefs.group[#prefs.group + 1] = p:sub(1, BB.GROUP_LEN)
        end
      end
    end
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
  end
  timers, debuffs, runes, groupedCache, stockHidden = {}, {}, {}, {}, false
  inCombat, combatUntil, lastShown = ShroudGetPlayerCombatMode() == true, 0, nil
  T.Hud.Register("buffs", BB)
  local savedTimers = T.Load("buff_timers")
  remembered = (type(savedTimers) == "table" and savedTimers.v == 3 and type(savedTimers.timers) == "table")
    and savedTimers.timers or {}
  learned = {}
  local savedDurations = T.Load("buff_durations")
  local durations = type(savedDurations) == "table" and savedDurations.v == 2
    and type(savedDurations.durations) == "table" and savedDurations.durations or {}
  for name, v in pairs(durations) do
    if type(name) == "string" and type(v) == "number" and v > 0 then learned[name] = v end
  end
  preexisting, sceneQuietUntil, lastPlayer = {}, T.Now() + BB.SETTLE, ShroudGetPlayerName()
  for _, e in ipairs(readEffects()) do preexisting[e.name] = true end
  lastSeen = {}
  for name in pairs(preexisting) do lastSeen[name] = true end
  BB.Quiet()
  BB.OnBuffsChanged("start")           -- the change callback only fires on changes
  ShroudRegisterPeriodic(PERIODIC, BB.Tick, BB.TICK, true)
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

-- The "Show buff bar" setting.
function BB.IsEnabled() return prefs.show == true end

-- Whether the bar is on screen now (what Toolbox.Hud asks): enabled, and with "only during
-- combat", in combat (or just after), or while the settings window is open to place it.
function BB.IsShown()
  if prefs.show ~= true then return false end
  if not prefs.combatOnly then return true end
  return inCombat or T.Now() < combatUntil or T.Config.IsShown()
end

-- For Toolbox.Hud: out of combat with "only during combat", a glued strip (health & focus bars
-- and buffs) hides as a whole, not just its buffs part.
function BB.HidesGlued()
  return prefs.show == true and prefs.combatOnly == true and not BB.IsShown()
end

-- ShroudOnCombatModeChanged (from core.lua).
function BB.OnCombatMode(on)
  inCombat = on == true
  if not inCombat then combatUntil = T.Now() + BB.COMBAT_LINGER end
  BB.Tick()                            -- shows or hides the bar now, not at the next tick
end

function BB.GetCombatOnly() return prefs.combatOnly == true end

function BB.SetCombatOnly(on)
  prefs.combatOnly = on == true
  savePrefs()
  BB.Tick()
  T.Config.Sync()
end

function BB.SetShown(on)
  prefs.show = on == true
  savePrefs()
  if T.Gear.GetGlue() then
    T.Hud.Build()                      -- the glued equipment bar moves to its own strip, or back
  else
    T.Hud.Refresh()
  end
  if prefs.show then BB.Tick() end
  applyStock()                       -- off: the game's bar comes back at once
  T.Config.Sync()
end

function BB.Toggle() BB.SetShown(not prefs.show) end

local function inRange(n, lo, hi) return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi end

function BB.SetSize(n)
  if not inRange(n, BB.SIZE_MIN, BB.SIZE_MAX) then return false end
  prefs.size = n
  savePrefs()
  if content then
    for _, pool in pairs(slots) do
      for _, slot in ipairs(pool) do
        slot.row:SetStyle{ width = n, height = n }
        slot.icon:SetSize(n, n)
        slot.overlay:SetStyle{ width = n, height = n, marginLeft = -n }
        slot.k = nil                           -- redraw the sweep at the new size
      end
    end
    if group then
      local f = countFont(n)
      group.row:SetStyle{ width = n, height = n }
      group.icon:SetSize(n, n)
      for i, c in ipairs(group.counts) do
        local d = BB.COUNT_OUTLINE[i] or { 0, 0 }              -- the last is the bright one
        c:SetStyle(countStyle(n, f, d[1], d[2]))
      end
    end
    BB.Tick()                                  -- re-fits the strip for the new icon size
  end
  T.Gear.ApplySize(n)                          -- the equipment bar uses the same icon size
  T.Config.Sync()
  return true
end

function BB.GetSize() return size() end

function BB.SetExpireSeconds(n)
  if not inRange(n, BB.ALERT_MIN, BB.ALERT_MAX) then return false end
  prefs.expireSeconds = n
  savePrefs()
  T.Config.Sync()
  return true
end

function BB.GetExpireSeconds() return prefs.expireSeconds end

function BB.SetExpireAlert(on)
  prefs.expire = on == true
  savePrefs()
  T.Config.Sync()
end

function BB.GetExpireAlert() return prefs.expire end

function BB.SetDebuffAlert(on)
  prefs.debuff = on == true
  savePrefs()
  T.Config.Sync()
end

function BB.GetDebuffAlert() return prefs.debuff end

-- A red border blinks on a buff once its expiry alert time is reached (with or without the sound).
function BB.GetFlash() return prefs.flash ~= false end

function BB.SetFlash(on)
  prefs.flash = on == true
  savePrefs()
  if content and BB.IsShown() then BB.Tick() end
  T.Config.Sync()
end

function BB.GetReplace() return prefs.replaceStock == true end

-- Returns false when this client can't hide the game's bar.
function BB.SetReplace(on)
  if on and not BB.CanReplace() then return false end
  prefs.replaceStock = on == true
  savePrefs()
  applyStock()
  T.Config.Sync()
  return true
end

function BB.GetClickDismiss() return prefs.clickDismiss == true end

function BB.SetClickDismiss(on)
  if on and not BB.CanDismiss() then return false end
  prefs.clickDismiss = on == true
  savePrefs()
  for _, pool in pairs(slots) do
    for _, slot in ipairs(pool) do slot.tip = nil end   -- redo tooltips (the "Click to dismiss" line)
  end
  if content and prefs.show then BB.Tick() end
  T.Config.Sync()
  return true
end

-- The name parts of the grouped (long-lasting) buffs.
function BB.GroupParts()
  local out = {}
  for i, p in ipairs(prefs.group or {}) do out[i] = p end
  return out
end

local function setGroup(parts)
  prefs.group = parts
  groupedCache = {}
  savePrefs()
  if content and prefs.show then BB.Tick() end
  T.Config.Sync()
end

-- Returns ok, message (for chat).
function BB.AddGroupPart(part)
  part = T.Trim(part)
  if part == "" then return false, "Give part of a buff's name, e.g. BlessingOfStamina." end
  if #part > BB.GROUP_LEN then return false, "Keep it under " .. BB.GROUP_LEN .. " characters." end
  local parts = BB.GroupParts()
  for _, p in ipairs(parts) do
    if p:lower() == part:lower() then return false, "'" .. p .. "' is already grouped." end
  end
  if #parts >= BB.GROUP_MAX then return false, "At most " .. BB.GROUP_MAX .. " names; remove one first." end
  parts[#parts + 1] = part
  setGroup(parts)
  return true, "Buffs with '" .. part .. "' in their name are now grouped."
end

function BB.RemoveGroupPart(part)
  part = T.Trim(part):lower()
  local parts, kept, found = BB.GroupParts(), {}, nil
  for _, p in ipairs(parts) do
    if p:lower() == part then found = p else kept[#kept + 1] = p end
  end
  if not found then return false, "'" .. part .. "' isn't in the list." end
  setGroup(kept)
  return true, "Buffs with '" .. found .. "' in their name show on the bar again."
end

function BB.GetGroupAfter() return prefs.groupAfter or BB.GROUP_AFTER_DEFAULT end

-- Seconds, one of BB.GROUP_AFTER_CHOICES (0 = off). Returns false for anything else.
function BB.SetGroupAfter(seconds)
  if not BB.GroupAfterLabel(seconds) then return false end
  prefs.groupAfter = seconds
  savePrefs()
  if content and prefs.show then BB.Tick() end
  T.Config.Sync()
  return true
end

function BB.ResetGroup()
  local parts = {}
  for i, p in ipairs(BB.GROUP_DEFAULT) do parts[i] = p end
  setGroup(parts)
end

-- ---------------------------------------------------------------------------
-- Position. A HUD frame can also be dragged by the grip at its top-left corner, but the
-- grip is hidden while the player has the HUD locked; these move it from settings or chat.
-- The game remembers a HUD frame's position itself (SetPosition "remembers the new spot as
-- the player's"; its Reset Positions button puts it back).
-- ---------------------------------------------------------------------------

BB.FRAME_ID = FRAME_ID
local mover = T.Hud.MoverFor("buffs", BB.HOME)
BB.GetPosition, BB.MoveTo, BB.Nudge, BB.ResetPosition = mover.Get, mover.MoveTo, mover.Nudge, mover.Reset

-- ===========================================================================
-- Equipment bar and repair alerts (Toolbox.Gear)
-- ===========================================================================
-- Worn items below the repair threshold as icons on a HUD strip, with the buff bar's clock sweep
-- showing durability used up (red below the threshold, full red when broken); all worn items
-- while settings are open, to place it. The "Gear needs repair" notification source (docs.lua)
-- uses the same reading. The game fires no event when gear wears (ShroudOnInventoryChanged skips
-- durability), so the equipment list is read every G.POLL seconds. Items are keyed by name, with
-- "#2", "#3"... for same-named ones (two rings). Only items with a maximum durability count.
-- Icons are the buff bar's size. Glued (`glue`, while the buff bar is on), the slots are a third
-- row of the buff bar's strip, under the debuffs, and the gear strip isn't built (`Wanted`).
-- Saved var "gear" (character scope): { show = bool, threshold = percent, glue = bool, x, y }.

local G = {}
Toolbox.Gear = G
G.FRAME_ID = "toolbox_gear"
G.HOME = { 40, 300 }
G.SLOTS = 12                                 -- a worn set has about 12 items with durability
G.POLL = 10                                  -- seconds between readings of the equipment
G.THRESHOLDS = { 5, 10, 15, 20, 25, 30, 50 }
G.THRESHOLD_DEFAULT = 20

-- The worn items with durability, as { key, name, dur, max, pct (0-1), icon, primary }.
-- `list` is ShroudGetEquipmentItems()'s answer (tables or game objects).
function G.Read(list)
  local out, count = {}, {}
  for _, it in ipairs(T.List(list)) do
    local name, dur, max = T.Field(it, "name"), T.Field(it, "durability"), T.Field(it, "maxDurability")
    if type(name) == "string" and type(dur) == "number" and type(max) == "number" and max > 0 then
      count[name] = (count[name] or 0) + 1
      local icon = T.Field(it, "icon")
      out[#out + 1] = { key = count[name] > 1 and (name .. "#" .. count[name]) or name, name = name,
        dur = math.max(0, dur), max = max, pct = math.max(0, math.min(1, dur / max)),
        icon = type(icon) == "number" and icon or -1, primary = T.Field(it, "primaryDurability") }
    end
  end
  return out
end

-- "broken" at 0, "low" below `threshold` percent, nil otherwise.
function G.Stage(item, threshold)
  if item.dur <= 0 then return "broken" end
  if item.pct * 100 < threshold then return "low" end
  return nil
end

local function sameStages(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

-- For the notification source: a notice for items that got worse since `seen` ({ [key] = stage }):
-- fine -> low, or anything -> broken. Repairs and unequipped items are remembered quietly (the
-- second value), so an item warns again the next time it wears down.
function G.Notice(worn, seen, threshold)
  seen = type(seen) == "table" and seen or {}
  local now, worse = {}, {}
  for _, it in ipairs(worn) do
    local st = G.Stage(it, threshold)
    if st then now[it.key] = st end
    if st and st ~= seen[it.key] and (st == "broken" or seen[it.key] == nil) then worse[#worse + 1] = it end
  end
  if #worse == 0 then
    if not sameStages(now, seen) then return nil, now end
    return nil
  end
  local parts = {}
  for _, it in ipairs(worse) do
    if it.dur <= 0 then
      parts[#parts + 1] = it.name .. " is broken"
    else
      parts[#parts + 1] = it.name .. " is at " .. math.floor(it.pct * 100) .. "% durability"
    end
  end
  return { text = table.concat(parts, ". ") .. ". Repair it before it breaks.", seen = now }
end

-- The equipment now (a fresh reading), for the notification source and /toolbox gear.
function G.Items()
  local ok, list = pcall(ShroudGetEquipmentItems)
  if not ok then return {} end
  return G.Read(list)
end

-- ---------------------------------------------------------------------------
-- The strip
-- ---------------------------------------------------------------------------

local gprefs = { show = true, threshold = G.THRESHOLD_DEFAULT }
local gContent = nil
local gSlots = {}
local gItems = {}                     -- the last reading, lowest first
local gShownList = {}                 -- what the strip shows now
local lastPoll, lastSettingsOpen = -math.huge, nil
local gShown = nil

local function gSave() T.Save("gear", gprefs) end

function G.Threshold() return gprefs.threshold end

local function byDurability(a, b)
  if a.pct ~= b.pct then return a.pct < b.pct end
  return a.key < b.key
end

-- What the strip lists: items below the threshold, or every worn item while settings are open.
local function shownList()
  local out, all = {}, T.Config.IsShown()
  if gprefs.show ~= true then return out end
  for _, it in ipairs(gItems) do
    if all or G.Stage(it, gprefs.threshold) then out[#out + 1] = it end
  end
  return out
end

function G.IsShown()
  return gprefs.show == true and #gShownList > 0 and not G.Glued()
end

-- Glued to the buff bar right now (the setting, and the buff bar switched on).
function G.Glued() return gprefs.glue == true and BB.IsEnabled() end

-- For Toolbox.Hud: the gear strip is built only when not glued.
function G.Wanted() return not G.Glued() end

-- Slots showing in the buff bar's third row (0 when not glued).
function G.GluedCount()
  if not G.Glued() then return 0 end
  return math.min(G.SLOTS, #gShownList)
end

-- The row of slots: the gear strip's content, or the buff bar's third row when glued.
function G.BuildRow()
  if clockTex < 0 then clockTex = ShroudLoadTexture(BB.CLOCK.path) end
  local s = size()
  local row = {}
  gSlots = {}
  for i = 1, G.SLOTS do
    local iconSpec = { width = s, height = s, onClick = function() end }   -- a click handler: tooltips show
    if clockTex >= 0 then iconSpec.texture = clockTex end
    local icon, overlay = UI.Image(iconSpec), BB.SweepHolder(s)
    local slot = UI.Row{ visible = false, children = { icon, overlay },     -- as the buff slots' style
      style = { width = s, height = s, marginRight = BB.GAP, backgroundColor = "#00000066", borderWidth = 0 } }
    gSlots[i] = { row = slot, icon = icon, overlay = overlay }
    row[i] = slot
  end
  gContent = UI.Row{ id = "gear", children = row }
  lastPoll = -math.huge                 -- new slots: fill them on the next tick
  return gContent
end
G.BuildContent = G.BuildRow

-- The buff bar's icon size changed (BB.SetSize).
function G.ApplySize(n)
  for _, slot in ipairs(gSlots) do
    slot.row:SetStyle{ width = n, height = n }
    slot.icon:SetSize(n, n)
    slot.overlay:SetStyle{ width = n, height = n, marginLeft = -n }
    slot.k = nil                                -- redraw the sweep at the new size
  end
  lastPoll = -math.huge                         -- ... on the next tick
  if G.Glued() then BB.Tick() else T.Hud.Refresh() end    -- re-fit the strip
end

function G.ContentSize()
  local cell = size() + BB.GAP
  return math.max(1, math.min(G.SLOTS, #gShownList)) * cell, cell
end

function G.GetSavedPosition() return gprefs.x, gprefs.y end
function G.SavePosition(x, y)
  if x ~= gprefs.x or y ~= gprefs.y then
    gprefs.x, gprefs.y = x, y
    gSave()
  end
end

local gearMover = T.Hud.MoverFor("gear", G.HOME)
G.GetPosition, G.MoveTo, G.Nudge, G.ResetPosition = gearMover.Get, gearMover.MoveTo, gearMover.Nudge,
  gearMover.Reset

-- Puts gShownList into the slots (only what changed) and refits the strip when that changes.
-- `gPending`: a sweep couldn't be drawn (the budget was spent); G.Tick tries again next second.
local gPending = false
local function fillGear()
  if not gContent then return end
  gPending = false
  for i, slot in ipairs(gSlots) do
    local it = gShownList[i]
    if it then
      if slot.tex ~= it.icon then
        slot.tex = it.icon
        if it.icon >= 0 then slot.icon:SetTexture(it.icon) end
      end
      local stage = G.Stage(it, gprefs.threshold)
      local k = it.dur <= 0 and (BB.CLOCK.FRAMES - 1) or BB.Frame(it.pct)
      local warn = stage ~= nil
      if k ~= slot.k or warn ~= slot.warn then
        if k > 0 and clockTex >= 0 then
          if BB.ShowFrame(slot, k, warn, size()) then
            slot.k, slot.warn = k, warn
          else
            gPending = true
          end
        else
          BB.HideFrame(slot)
          slot.k, slot.warn = k, warn
        end
      end
      T.SetTooltip(slot.icon, string.format("%s\nDurability %s / %s (%d%%)%s", it.name, T.FormatNumber(it.dur),
        T.FormatNumber(it.max), math.floor(it.pct * 100), stage == "broken" and "\nBroken: repair it"
        or (stage == "low" and "\nNeeds repair" or "")))
    end
    T.SetVisible(slot.row, it ~= nil)
  end
end

-- Reads the equipment (every G.POLL seconds, or `force`), and shows or hides the strip.
function G.Poll(force)
  local now = T.Now()
  local settings = T.Config.IsShown()
  if not force and settings == lastSettingsOpen and now - lastPoll < G.POLL then return end
  lastPoll, lastSettingsOpen = now, settings
  gItems = G.Items()
  table.sort(gItems, byDurability)
  gShownList = shownList()
  fillGear()
  local shown = (G.IsShown() or G.Glued()) and #gShownList or 0
  if shown ~= gShown then
    gShown = shown
    if G.Glued() then BB.Tick() else T.Hud.Refresh() end   -- glued: the buff strip re-fits
  end
end

-- From Toolbox.Tick (1 s).
function G.Tick()
  G.Poll(false)
  if gPending then fillGear() end
end

function G.Init()
  local saved = T.Load("gear")
  gprefs = { show = true, threshold = G.THRESHOLD_DEFAULT }
  if type(saved) == "table" then
    gprefs.show = saved.show ~= false
    gprefs.glue = saved.glue == true
    for _, v in ipairs(G.THRESHOLDS) do if saved.threshold == v then gprefs.threshold = v end end
    if type(saved.x) == "number" and type(saved.y) == "number" then gprefs.x, gprefs.y = saved.x, saved.y end
  end
  gItems, gShownList, gShown, lastPoll, lastSettingsOpen = {}, {}, nil, -math.huge, nil
  T.Hud.Register("gear", G)
end

function G.GetShow() return gprefs.show == true end
function G.GetGlue() return gprefs.glue == true end

-- Glue the equipment bar under the buff bar's debuffs, or give it its own strip.
function G.SetGlue(on)
  gprefs.glue = on == true
  gSave()
  gShown = nil
  T.Hud.Build()
  G.Poll(true)
  BB.Tick()                            -- the rebuilt buff strip fits its rows now, not next tick
  T.Config.Sync()
end

function G.SetShow(on)
  gprefs.show = on == true
  gSave()
  gShown = nil
  G.Poll(true)
  if G.Glued() then BB.Tick() else T.Hud.Refresh() end
  T.Config.Sync()
end

-- Percent, one of G.THRESHOLDS. Returns false for anything else.
function G.SetThreshold(pct)
  local ok = false
  for _, v in ipairs(G.THRESHOLDS) do if v == pct then ok = true end end
  if not ok then return false end
  gprefs.threshold = pct
  gSave()
  for _, slot in ipairs(gSlots) do slot.k = nil end    -- redraw the sweeps' colours
  G.Poll(true)
  T.Config.Sync()
  return true
end

-- /toolbox gear: every worn item with durability, lowest first, and the raw fields.
function G.Lines()
  local worn = G.Items()
  table.sort(worn, byDurability)
  if #worn == 0 then return { "No worn items with durability (or the equipment isn't loaded yet)." } end
  local lines = { "Worn gear (repair below " .. gprefs.threshold .. "%):" }
  for _, it in ipairs(worn) do
    local stage = G.Stage(it, gprefs.threshold)
    lines[#lines + 1] = string.format("  %s: %d%% (%s / %s)%s  [primaryDurability %s]", it.name,
      math.floor(it.pct * 100), T.FormatNumber(it.dur), T.FormatNumber(it.max),
      stage == "broken" and " BROKEN" or (stage == "low" and " needs repair" or ""), tostring(it.primary))
  end
  return lines
end

-- /toolbox gear debug: the laid-out sizes of a buff slot and a gear slot (and their rows), to
-- compare them in game (reported 2026-09-28: gear icons look larger and start further left).
function G.DebugLines()
  local function sz(e)
    if not e then return "none" end
    local ok, w, h = pcall(e.GetSize, e)
    if not ok then return "?" end
    return tostring(w) .. "x" .. tostring(h)
  end
  local function firstShown(pool)
    for _, slot in ipairs(pool or {}) do
      if slot.row:IsVisible() then return slot end
    end
    return nil
  end
  local b, g = firstShown(slots and slots.buffs), firstShown(gSlots)
  local lines = {
    string.format("icon size %d; glued %s (setting %s, buff bar %s); gear showing %d of %d worn; settings open %s",
      size(), tostring(G.Glued()), tostring(gprefs.glue == true), tostring(BB.IsEnabled()), #gShownList, #gItems,
      tostring(T.Config.IsShown())),
    "buff slot " .. sz(b and b.row) .. ", its icon " .. sz(b and b.icon) .. ", sweep " .. sz(b and b.overlay),
    "gear slot " .. sz(g and g.row) .. ", its icon " .. sz(g and g.icon) .. ", sweep " .. sz(g and g.overlay),
    "rows: buffs " .. sz(content and content:Find("buffs")) .. ", debuffs " .. sz(content and content:Find("debuffs"))
      .. ", gear " .. sz(gContent),
  }
  if not b or not g then
    lines[#lines + 1] = "(a slot shows \"none\" when nothing is up in it: open settings for gear)"
  end
  return lines
end

-- ===========================================================================
-- Consumables bar (Toolbox.Consumables)
-- ===========================================================================
-- Food and potions in effect, as icons with the buff bar's sweep, on their own HUD strip or glued to
-- the buff bar as a row under the debuffs (above the equipment bar). Recognised by rune name
-- (BB.ConsumableKind), plus name parts the player adds. While the bar is on, they leave the buff bar
-- (owner, 2026-09-28); the buff bar's expiry alert, sound and red flash apply to them as to any buff,
-- and one that has run out simply goes. With the bar off they stay on the buff bar.
-- Saved var "consumables" (character scope): { show = bool, glue = bool, extra = { name parts }, x, y }.

K.FRAME_ID = "toolbox_consumables"
K.HOME = { 40, 340 }
K.SLOTS = 10
K.EXTRA_MAX = 20

local kprefs = { show = true, glue = false, extra = {} }
local kCache = {}              -- rune name -> kind or false (a rune's name and label don't change)
local kShown = nil             -- K.IsShown() last time, to refresh the HUD when it changes

local function kSave() T.Save("consumables", kprefs) end

-- Glued to the buff bar right now (the setting, and the buff bar switched on).
function K.Glued() return kprefs.glue == true and kprefs.show == true and BB.IsEnabled() end

-- For Toolbox.Hud: its own strip only while it is on and not glued.
function K.Wanted() return kprefs.show == true and not K.Glued() end

function K.GluedCount()
  if not K.Glued() then return 0 end
  return math.min(K.SLOTS, kCount)
end

-- Whether effect e goes on the consumables bar (it is on, and e is food, a potion or an added name).
function K.Takes(e)
  if kprefs.show ~= true then return false end
  local kind = kCache[e.name]
  if kind == nil then
    kind = BB.ConsumableKind(e.name, labelFor(e), kprefs.extra) or false
    kCache[e.name] = kind
  end
  return kind ~= false
end

function K.IsShown()
  if kprefs.show ~= true or K.Glued() then return false end
  return kCount > 0 or T.Config.IsShown()        -- empty but shown while settings are open, to place it
end

-- The row of slots: its strip's content, or a row of the buff bar when glued (`gapBelow`: another row
-- follows it).
function K.BuildRow(gapBelow)
  if clockTex < 0 then clockTex = ShroudLoadTexture(BB.CLOCK.path) end
  local row = {}
  slots.consumables = {}
  for i = 1, K.SLOTS do
    slots.consumables[i] = makeSlot(false)
    row[i] = slots.consumables[i].row
  end
  kContent = UI.Row{ id = "consumables", style = { marginBottom = gapBelow and BB.GAP or 0 }, children = row }
  kShown = nil
  return kContent
end
function K.BuildContent() return K.BuildRow(false) end

function K.ContentSize()
  local cell = size() + BB.GAP
  return math.max(1, math.min(K.SLOTS, kCount)) * cell, cell
end

function K.GetSavedPosition() return kprefs.x, kprefs.y end
function K.SavePosition(x, y)
  if x ~= kprefs.x or y ~= kprefs.y then
    kprefs.x, kprefs.y = x, y
    kSave()
  end
end

local consMover = T.Hud.MoverFor("consumables", K.HOME)
K.GetPosition, K.MoveTo, K.Nudge, K.ResetPosition = consMover.Get, consMover.MoveTo, consMover.Nudge,
  consMover.Reset

-- From BB.Tick: the consumables in effect ({ e, fraction, warn } each), soonest to run out first.
function K.Fill(list)
  BB.SortByExpiry(list)
  local count = math.min(#list, K.SLOTS)
  local pool = slots.consumables
  if kContent and (not K.Glued() or BB.IsShown()) then
    for i = 1, K.SLOTS do
      local x = list[i]
      if pool[i] then
        if x then fill(pool[i], x.e, x.fraction, x.warn, x.warn and prefs.flash) else fill(pool[i], nil) end
      end
    end
  end
  local changed = count ~= kCount
  kCount = count
  local shownNow = K.IsShown()
  if (changed or shownNow ~= kShown) and not K.Glued() then T.Hud.Refresh() end
  kShown = shownNow
end

-- The consumables in effect now, for /toolbox consumables: { label, kind, remaining }.
function K.Current()
  local out = {}
  for _, e in ipairs(readEffects()) do
    local rune = runes[e.name] or NOTHING
    if not rune.debuff then
      local kind = BB.ConsumableKind(e.name, labelFor(e), kprefs.extra)
      if kind then out[#out + 1] = { label = labelFor(e), name = e.name, kind = kind, remaining = e.remaining } end
    end
  end
  return out
end

function K.Init()
  local saved = T.Load("consumables")
  kprefs = { show = true, glue = false, extra = {} }
  if type(saved) == "table" then
    kprefs.show = saved.show ~= false
    kprefs.glue = saved.glue == true
    if type(saved.extra) == "table" then
      for _, part in ipairs(saved.extra) do
        if type(part) == "string" and part ~= "" and #kprefs.extra < K.EXTRA_MAX then
          kprefs.extra[#kprefs.extra + 1] = part
        end
      end
    end
    if type(saved.x) == "number" and type(saved.y) == "number" then kprefs.x, kprefs.y = saved.x, saved.y end
  end
  kCache, kCount, kShown, kContent = {}, 0, nil, nil
  T.Hud.Register("consumables", K)
end

function K.GetShow() return kprefs.show == true end
function K.GetGlue() return kprefs.glue == true end
function K.Extra() return kprefs.extra end

-- The bar on or off, glued or not: both change which strips exist, so the HUD is rebuilt.
local function rebuild()
  kSave()
  kCache, kCount = {}, 0
  T.Hud.Build()
  BB.Tick()
  T.Config.Sync()
end

function K.SetShow(on)
  kprefs.show = on == true
  rebuild()
end

function K.SetGlue(on)
  kprefs.glue = on == true
  rebuild()
end

-- Adds / removes a name part (any case; matched in the rune name or the displayed name). Returns ok, message.
function K.AddExtra(part)
  part = T.Trim(part or "")
  if part == "" then return false, "Give a name, or part of one: /" .. T.commands[1] .. " consumables add Poison" end
  for _, p in ipairs(kprefs.extra) do
    if p:lower() == part:lower() then return false, "Already tracked: " .. p .. "." end
  end
  if #kprefs.extra >= K.EXTRA_MAX then return false, "At most " .. K.EXTRA_MAX .. " names." end
  kprefs.extra[#kprefs.extra + 1] = part
  kSave()
  kCache = {}
  BB.Tick()
  T.Config.Sync()
  return true, "Buffs matching '" .. part .. "' now go on the consumables bar."
end

function K.RemoveExtra(part)
  part = T.Trim(part or ""):lower()
  for i, p in ipairs(kprefs.extra) do
    if p:lower() == part then
      table.remove(kprefs.extra, i)
      kSave()
      kCache = {}
      BB.Tick()
      T.Config.Sync()
      return true, "No longer tracked: " .. p .. "."
    end
  end
  return false, "Not in the list: " .. part .. "."
end

