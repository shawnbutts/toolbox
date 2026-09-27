-- Toolbox: buffbar.lua
-- A buff bar (/toolbox buffs): your buffs and debuffs as their real skill icons on a HUD
-- strip, with a clock-style sweep over each icon instead of a time readout. Plus two
-- alerts that work whether or not the bar is shown:
--   * a buff is about to run out: fires once when a buff's remaining time crosses the
--     player's threshold (a buff that starts below it never fires);
--   * a debuff landed: fires when a debuff you didn't have appears (the API doesn't say
--     who applied it).
--
-- From API 16 two opt-in settings: "Replace the game's buff bar" hides the game's own bar
-- (ShroudSetBuffBarVisible; never saved by the game and released on reload, so it's asserted
-- again every tick while wanted), but only while this bar is actually showing; and "Click to
-- dismiss" makes a click on an icon dismiss that buff (ShroudDismissBuff, which needs the
-- player's click: never from a timer). Both are feature-detected.
--
-- Long-lasting buffs (Obsidian potions last days, and several can run at once) are grouped
-- into one slot at the end of the buff row: a count over the first one's icon, with each
-- buff and its time left in the tooltip. The API has no "long-lasting" flag and doesn't give
-- a buff's full duration, so they are picked by name (BB.GROUP_DEFAULT; /toolbox buffs group).
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
BB.BUFF_SLOTS, BB.DEBUFF_SLOTS = 20, 10
BB.SIZE_MIN, BB.SIZE_MAX, BB.SIZE_DEFAULT = 20, 48, 32
BB.ALERT_MIN, BB.ALERT_MAX, BB.ALERT_DEFAULT = 1, 60, 10
BB.GAP = 3
-- Name parts of the buffs grouped by default: the Obsidian potions' rune names (seen in game
-- 2026-09-27; ~3.5 days each). Listed one by one: other "BlessingOf" runes may not be potions.
BB.GROUP_DEFAULT = {
  "BlessingOfCapacity", "BlessingOfConservation", "BlessingOfExpedience", "BlessingOfPrecision",
  "BlessingOfPrevention", "BlessingOfReclamation", "BlessingOfStamina",
}
BB.GROUP_MAX = 20                  -- name parts kept
BB.GROUP_LEN = 40                  -- characters per name part
BB.HOME = { 40, 220 }         -- where the bar starts, and where Reset puts it
BB.NUDGE = 10                 -- pixels per nudge button press
BB.DEBUFF_SUPPRESS = 3        -- seconds after start / a scene change with no debuff alerts
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
-- TotalDuration / CurrentDuration have no documented units or meaning, so a reading is
-- used only when it agrees with the documented seconds remaining: in seconds or
-- milliseconds, with CurrentDuration as either the time elapsed or the time remaining.
function BB.TotalFromEffects(remaining, effects)
  if type(remaining) ~= "number" or remaining <= 0 or type(effects) ~= "table" then return nil end
  local best = nil
  for _, e in ipairs(effects) do
    local tot, cur = type(e) == "table" and e.TotalDuration, type(e) == "table" and e.CurrentDuration
    if type(tot) == "number" and type(cur) == "number" and tot > 0 then
      for _, scale in ipairs({ 1, 1000 }) do
        local total, current = tot / scale, cur / scale
        local fits = total >= remaining - 0.5 and
          (math.abs((total - current) - remaining) <= 1.5 or math.abs(current - remaining) <= 1.5)
        if fits and (not best or total > best) then best = total end
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

-- Clock frame for a fraction remaining: 0 = full time left (no shading).
function BB.Frame(fraction)
  local n = BB.CLOCK.FRAMES
  local k = math.floor((1 - fraction) * n)
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
local sceneQuietUntil = 0 -- buffs first seen before this (scene load) aren't "fresh"
BB.GRACE = 10             -- seconds a vanished buff keeps its timer (scene loads)
local lastTimerSave = -math.huge
BB.TIMER_SAVE = 5         -- seconds between saves of the running timers (for a reload)
local debuffs = {}        -- debuff names seen at the last change (set)
local timers = {}         -- rune name -> BB.Track state
local quietUntil = 0      -- no debuff alerts before this T.Now()
local lastDebuffSound = -math.huge
local content = nil       -- the icon rows (in a strip owned by Toolbox.Hud)
local contentW, contentH = 0, 0
local slots = { buffs = {}, debuffs = {} }
local clockTex = -1
local group = nil         -- the long-lasting buffs' slot { row, icon, count, ... }
local groupedCache = {}   -- rune name -> grouped? (a rune's displayed name doesn't change)
local stockHidden = false -- we asked the game to hide its own buff bar

local function defaults()
  local parts = {}
  for i, p in ipairs(BB.GROUP_DEFAULT) do parts[i] = p end
  return { show = false, size = BB.SIZE_DEFAULT, expire = true, expireSeconds = BB.ALERT_DEFAULT, debuff = true,
           group = parts, replaceStock = false, clickDismiss = false }
end

local function savePrefs()
  T.Save("buffbar", prefs)
end

local readEffects = nil

-- A buff's displayed name without the game's colour markup ([c][27E833]...[-][/c]).
local function plainLabel(index, fallback)
  local label = ShroudGetBuffDescription(index)
  if type(label) ~= "string" or label == "Invalid" then return fallback end
  label = label:gsub("%[%x%x%x%x%x%x%x?%x?%]", ""):gsub("%[%-%]", ""):gsub("%[/?%a%]", "")
  label = label:match("^%s*(.-)%s*$")
  return label ~= "" and label or fallback
end

-- Whether a buff goes in the long-lasting group (debuffs never do).
local function isGrouped(e)
  local g = groupedCache[e.name]
  if g == nil then
    g = BB.Grouped(e.name, plainLabel(e.index, e.name), prefs.group)
    groupedCache[e.name] = g
  end
  return g
end

-- Re-reads the grouped list (debuff flags, icons, full durations) and raises the debuff alert.
function BB.OnBuffsChanged()
  local list = ShroudGetPlayerBuff()
  local remainingByName = {}
  for _, e in ipairs(readEffects()) do remainingByName[e.name] = e.remaining end
  runes = {}
  local now = {}
  for _, rune in ipairs(type(list) == "table" and list or {}) do
    if type(rune) == "table" and type(rune.RuneName) == "string" then
      runes[rune.RuneName] = { debuff = rune.IsDebuff == true, icon = rune.IconId,
        total = BB.TotalFromEffects(remainingByName[rune.RuneName], rune.Effects) }
      if rune.IsDebuff then now[rune.RuneName] = true end
    end
  end
  local new = BB.NewNames(debuffs, now)
  debuffs = now
  if #new > 0 and prefs.debuff and T.Now() >= quietUntil and T.Now() - lastDebuffSound >= BB.DEBUFF_COOLDOWN then
    lastDebuffSound = T.Now()
    T.Sounds.Play("debuff_landed")
  end
end

-- A scene change rebuilds the buff list: treat what's there as already known.
function BB.Quiet()
  quietUntil = T.Now() + BB.DEBUFF_SUPPRESS
end

function BB.SceneChange()
  BB.Quiet()
  sceneQuietUntil = T.Now() + BB.DEBUFF_SUPPRESS
end

-- One entry per rune in the game's order: { name, remaining, index (first flat index) }.
function readEffects()
  local out, byName = {}, {}
  local n = ShroudGetBuffCount() or 0
  for i = 0, n - 1 do
    local name = ShroudGetBuffName(i)
    if type(name) == "string" and name ~= "Invalid" then
      local remaining = ShroudGetBuffTimeRemaining(i)
      local e = byName[name]
      if not e then
        e = { name = name, remaining = remaining, index = i }
        byName[name] = e
        out[#out + 1] = e
      elseif type(remaining) == "number" and remaining > (e.remaining or -1) then
        e.remaining = remaining          -- a rune lasts until its last effect ends
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
  local want = prefs.replaceStock == true and prefs.show == true and content ~= nil
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
  local used = math.max(buffsShown, debuffsShown)
  local rows = debuffsShown > 0 and 2 or 1
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
  local overlaySpec = { width = s, height = s, visible = false,
    style = { marginLeft = -s } }      -- no absolute positioning: overlap by a negative margin
  if clockTex >= 0 then iconSpec.texture, overlaySpec.texture = clockTex, clockTex end
  local icon = UI.Image(iconSpec)
  local overlay = UI.Image(overlaySpec)
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
local function makeGroupSlot()
  local s = size()
  local f = countFont(s)
  local iconSpec = { width = s, height = s, onClick = function() end }
  if clockTex >= 0 then iconSpec.texture = clockTex end
  local icon = UI.Image(iconSpec)
  local count = UI.Label{ text = "", class = "bright",
    style = { width = s, height = s, minHeight = s, maxHeight = s, marginLeft = -s, marginRight = 0,
              marginTop = 0, marginBottom = 0, paddingTop = math.max(0, math.floor((s - f * 1.2) / 2)),
              fontSize = f, fontStyle = "bold", textAlign = "center" } }
  local row = UI.Row{ visible = false, children = { icon, count },
    style = { width = s, height = s, marginRight = BB.GAP, backgroundColor = "#00000066" } }
  return { row = row, icon = icon, count = count, used = false }
end

-- Builds the icon rows (a fixed slot pool) and returns them; Toolbox.Hud puts them in a strip.
function BB.BuildContent()
  clockTex = ShroudLoadTexture(BB.CLOCK.path)
  local buffRow, debuffRow = {}, {}
  slots = { buffs = {}, debuffs = {} }
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
  content = UI.Column{ id = "buffbar", children = {
    UI.Row{ id = "buffs", style = { marginBottom = BB.GAP }, children = buffRow },
    UI.Row{ id = "debuffs", children = debuffRow },
  } }
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
-- red sweep (the buff's expiry alert has fired).
local function fill(slot, e, fraction, warn)
  if not e then
    if slot.used then slot.row:SetVisible(false) end
    slot.used, slot.name, slot.label, slot.k, slot.warn = false, nil, nil, nil, nil
    return
  end
  if not slot.used then slot.row:SetVisible(true) end
  slot.used = true
  if slot.name ~= e.name then slot.name, slot.label = e.name, plainLabel(e.index, e.name) end
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
  if k ~= slot.k or warn ~= slot.warn then
    slot.k, slot.warn = k, warn
    if k and k > 0 and clockTex >= 0 then
      slot.overlay:SetUV(BB.FrameUV(k, warn))
      slot.overlay:SetVisible(true)
    else
      slot.overlay:SetVisible(false)
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
    group.count:SetText(tostring(#list))
  end
  local tip = BB.GroupTooltip(list)
  if tip ~= group.tip then
    group.tip = tip
    group.icon:SetTooltip(tip)
    group.count:SetTooltip(tip)
  end
end

-- ---------------------------------------------------------------------------
-- Tick: timers, alerts, and the bar
-- ---------------------------------------------------------------------------

function BB.Tick()
  local effects = readEffects()
  local seen, bi, di, grouped = {}, 0, 0, {}
  local threshold = prefs.expireSeconds or BB.ALERT_DEFAULT
  local expiring = false
  for _, e in ipairs(effects) do
    seen[e.name] = true
    local rune = runes[e.name] or {}
    local known = rune.total
    if not known and not timers[e.name] then known = BB.Recall(e.name, e.remaining) end
    if not known then known = learned[e.name] end
    local fresh = not preexisting[e.name] and T.Now() >= sceneQuietUntil
    local st, fraction, fire = BB.Track(timers[e.name], e.remaining, threshold, known, nil, fresh)
    if st and st.learn then
      st.learn = nil
      BB.Learn(e.name, st.total)
    end
    if st then st.missingSince = nil end
    timers[e.name] = st
    if fire and not rune.debuff then expiring = true end
    if content and prefs.show then
      if rune.debuff then
        di = di + 1
        if slots.debuffs[di] then fill(slots.debuffs[di], e, fraction) end
      elseif isGrouped(e) then
        local tex = (type(rune.icon) == "number" and rune.icon >= 0) and rune.icon or ShroudGetBuffIcon(e.index)
        grouped[#grouped + 1] = { plainLabel(e.index, e.name), e.remaining, tex }
      else
        bi = bi + 1
        if slots.buffs[bi] then fill(slots.buffs[bi], e, fraction, st and st.warned) end
      end
    end
  end
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
  if content and prefs.show then
    for i = bi + 1, BB.BUFF_SLOTS do fill(slots.buffs[i], nil) end
    for i = di + 1, BB.DEBUFF_SLOTS do fill(slots.debuffs[i], nil) end
    fillGroup(grouped)
    fitFrame(math.min(bi, BB.BUFF_SLOTS) + (#grouped > 0 and 1 or 0), math.min(di, BB.DEBUFF_SLOTS))
  end
  if expiring and prefs.expire then T.Sounds.Play("buff_expiring") end
  if T.Now() - lastTimerSave >= BB.TIMER_SAVE then BB.SaveTimers() end
  applyStock()
end

-- One chat line per current effect, for checking durations in game:
-- "Light: 9.5 s left; TotalDuration 40, CurrentDuration 30.5; full duration 40 s (from the game)".
-- %g: the same text on every Lua (5.3+ would print 39.0 where MoonSharp prints 39).
local function num(x) return type(x) == "number" and string.format("%g", x) or tostring(x) end

function BB.DebugLines()
  local lines = {}
  local list = ShroudGetPlayerBuff()
  local byName = {}
  for _, rune in ipairs(type(list) == "table" and list or {}) do
    if type(rune) == "table" and type(rune.RuneName) == "string" then byName[rune.RuneName] = rune end
  end
  for _, e in ipairs(readEffects()) do
    local rune = byName[e.name] or {}
    local fx = type(rune.Effects) == "table" and rune.Effects[1] or {}
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
function BB.Trace(filter)
  filter = (filter or ""):lower()
  local n = 0
  ShroudRegisterPeriodic("toolbox_bufftrace", function()
    n = n + 1
    local byName = {}
    local list = ShroudGetPlayerBuff()
    for _, rune in ipairs(type(list) == "table" and list or {}) do
      if type(rune) == "table" and type(rune.RuneName) == "string" then byName[rune.RuneName] = rune end
    end
    local shown = 0
    for _, e in ipairs(readEffects()) do
      local label = plainLabel(e.index, e.name)
      local match = filter == "" or e.name:lower():find(filter, 1, true) or label:lower():find(filter, 1, true)
      if match and shown < BB.TRACE_MAX then
        shown = shown + 1
        local fx = byName[e.name] and type(byName[e.name].Effects) == "table" and byName[e.name].Effects[1] or {}
        local st = timers[e.name]
        local named = label == e.name and e.name or (label .. " [" .. e.name .. "]")
        local effects = byName[e.name] and byName[e.name].Effects
        T.Print(string.format("+%ds %s: game %s left (%s effects; Total %s, Current %s) | bar %s of %s",
          n, named, num(e.remaining), type(effects) == "table" and #effects or "no", num(fx.TotalDuration),
          num(fx.CurrentDuration), st and string.format("%.1f", st.last or -1) or "?",
          st and (string.format("%.1f", st.total) .. (st.trusted and "" or " (unknown)")) or "?"))
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
function BB.Learn(name, total)
  if type(total) ~= "number" or total <= 0 or learned[name] == total then return end
  learned[name] = math.floor(total * 10 + 0.5) / 10
  T.Save("buff_durations", learned)
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
  -- v2: only trusted totals. v1 (unversioned) saves could hold a wrong "first seen" total.
  T.Save("buff_timers", { v = 2, timers = out })
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
    prefs.replaceStock = saved.replaceStock == true
    prefs.clickDismiss = saved.clickDismiss == true
    -- { "Obsidian" } alone was the first default, which matches no potion's name: take it as unset.
    local old = type(saved.group) == "table" and #saved.group == 1 and saved.group[1] == "Obsidian"
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
  T.Hud.Register("buffs", BB)
  local savedTimers = T.Load("buff_timers")
  remembered = (type(savedTimers) == "table" and savedTimers.v == 2 and type(savedTimers.timers) == "table")
    and savedTimers.timers or {}
  learned = {}
  local savedDurations = T.Load("buff_durations")
  for name, v in pairs(type(savedDurations) == "table" and savedDurations or {}) do
    if type(name) == "string" and type(v) == "number" and v > 0 then learned[name] = v end
  end
  preexisting, sceneQuietUntil = {}, 0
  for _, e in ipairs(readEffects()) do preexisting[e.name] = true end
  BB.Quiet()
  BB.OnBuffsChanged()                  -- the change callback only fires on changes
  ShroudRegisterPeriodic(PERIODIC, BB.Tick, BB.TICK, true)
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function BB.IsShown() return prefs.show == true end

function BB.SetShown(on)
  prefs.show = on == true
  savePrefs()
  T.Hud.Refresh()
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
        slot.overlay:SetSize(n, n)
        slot.overlay:SetStyle{ marginLeft = -n }
      end
    end
    if group then
      local f = countFont(n)
      group.row:SetStyle{ width = n, height = n }
      group.icon:SetSize(n, n)
      group.count:SetStyle{ width = n, height = n, minHeight = n, maxHeight = n, marginLeft = -n, fontSize = f,
                            paddingTop = math.max(0, math.floor((n - f * 1.2) / 2)) }
    end
    BB.Tick()                                  -- re-fits the strip for the new icon size
  end
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
  part = (part or ""):match("^%s*(.-)%s*$")
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
  part = (part or ""):match("^%s*(.-)%s*$"):lower()
  local parts, kept, found = BB.GroupParts(), {}, nil
  for _, p in ipairs(parts) do
    if p:lower() == part then found = p else kept[#kept + 1] = p end
  end
  if not found then return false, "'" .. part .. "' isn't in the list." end
  setGroup(kept)
  return true, "Buffs with '" .. found .. "' in their name show on the bar again."
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
