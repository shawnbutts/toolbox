-- Toolbox: buffbar.lua
-- A buff bar (/toolbox buffs): your buffs and debuffs as their real skill icons on a HUD
-- strip, with a clock-style sweep over each icon instead of a time readout. Plus two
-- alerts that work whether or not the bar is shown:
--   * a buff is about to run out: fires once when a buff's remaining time crosses the
--     player's threshold (a buff that starts below it never fires);
--   * a debuff landed: fires when a debuff you didn't have appears (the API doesn't say
--     who applied it).
--
-- The game's own buff bar can't be hidden from Lua; this one sits alongside it.
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
  local best
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

-- Tracks one buff's timer. st = { total, last, armed, warned } (created on first sight).
-- `known` is the buff's full duration when it can be established (TotalFromEffects, or
-- remembered across a reload); otherwise the largest remaining time seen stands in for it,
-- which is wrong for a buff that was already running when the add-on started.
-- Returns st, fraction remaining (0..1) or nil without a timer, and true when the
-- expiry alert should fire now. st.warned stays true for the rest of the run once it has
-- fired (the sweep turns red); a refresh starts a new run.
function BB.Track(st, remaining, threshold, known)
  if type(remaining) ~= "number" or remaining <= 0 then return st, nil, false end
  if type(known) ~= "number" or known < remaining - 0.5 then known = nil end
  if not st or remaining > st.last + 1 then
    -- First sight, or refreshed (time went up): a new run. Only arm the alert when the
    -- buff has more time than the threshold, so short buffs don't alert on arrival.
    st = { total = known or remaining, last = remaining, armed = remaining > threshold, warned = false }
  elseif known then
    st.total = known
  end
  st.last = remaining
  if remaining > st.total then st.total = remaining end
  local fire = false
  if st.armed and remaining <= threshold then
    st.armed, st.warned, fire = false, true, true
  elseif remaining > threshold then
    st.armed = true
  end
  return st, remaining / st.total, fire
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

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------

local prefs = {}
local runes = {}          -- rune name -> { debuff, icon, total } from ShroudGetPlayerBuff
local remembered = {}     -- rune name -> { total, remaining, at } saved before a reload
local lastTimerSave = -math.huge
BB.TIMER_SAVE = 5         -- seconds between saves of the running timers (for a reload)
local debuffs = {}        -- debuff names seen at the last change (set)
local timers = {}         -- rune name -> BB.Track state
local quietUntil = 0      -- no debuff alerts before this T.Now()
local lastDebuffSound = -math.huge
local frame = nil
local slots = { buffs = {}, debuffs = {} }
local clockTex = -1

local function defaults()
  return { show = false, size = BB.SIZE_DEFAULT, expire = true, expireSeconds = BB.ALERT_DEFAULT, debuff = true }
end

local function savePrefs()
  T.Save("buffbar", prefs)
end

local readEffects

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
-- HUD frame
-- ---------------------------------------------------------------------------

local function size() return prefs.size or BB.SIZE_DEFAULT end

local function frameSize()
  local cell = size() + BB.GAP
  return BB.BUFF_SLOTS * cell + 8, 2 * cell + 8
end

local function makeSlot(debuff)
  local s = size()
  local tex = clockTex >= 0 and clockTex or nil  -- a placeholder until a buff's icon is set
  local icon = UI.Image{ texture = tex, width = s, height = s,
    onClick = function() end }         -- an Image only takes the pointer (tooltip) with a click handler
  local overlay = UI.Image{ texture = tex, width = s, height = s, visible = false,
    style = { marginLeft = -s } }      -- no absolute positioning: overlap by a negative margin
  local slot = UI.Row{ visible = false, children = { icon, overlay },
    style = { width = s, height = s, marginRight = BB.GAP, backgroundColor = "#00000066",
              borderWidth = debuff and 2 or 0, borderColor = "@red" } }
  return { row = slot, icon = icon, overlay = overlay, used = false }
end

local function build()
  clockTex = ShroudLoadTexture(BB.CLOCK.path)
  local buffRow, debuffRow = {}, {}
  slots = { buffs = {}, debuffs = {} }
  for i = 1, BB.BUFF_SLOTS do
    slots.buffs[i] = makeSlot(false)
    buffRow[i] = slots.buffs[i].row
  end
  for i = 1, BB.DEBUFF_SLOTS do
    slots.debuffs[i] = makeSlot(true)
    debuffRow[i] = slots.debuffs[i].row
  end
  local w, h = frameSize()
  frame = UI.HudFrame{ id = FRAME_ID, x = 40, y = 220, width = w, height = h, visible = prefs.show,
    children = {
      UI.Row{ id = "buffs", style = { marginBottom = BB.GAP }, children = buffRow },
      UI.Row{ id = "debuffs", children = debuffRow },
    } }
end

-- Puts entry e (or nothing) into a slot, touching only what changed. `warn` shows the
-- red sweep (the buff's expiry alert has fired).
local function fill(slot, e, fraction, warn)
  if not e then
    if slot.used then slot.row:SetVisible(false) end
    slot.used, slot.name, slot.k, slot.warn = false, nil, nil, nil
    return
  end
  if not slot.used then slot.row:SetVisible(true) end
  slot.used = true
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

-- ---------------------------------------------------------------------------
-- Tick: timers, alerts, and the bar
-- ---------------------------------------------------------------------------

function BB.Tick()
  local effects = readEffects()
  local seen, bi, di = {}, 0, 0
  local threshold = prefs.expireSeconds or BB.ALERT_DEFAULT
  local expiring = false
  for _, e in ipairs(effects) do
    seen[e.name] = true
    local rune = runes[e.name] or {}
    local known = rune.total
    if not known and not timers[e.name] then known = BB.Recall(e.name, e.remaining) end
    local st, fraction, fire = BB.Track(timers[e.name], e.remaining, threshold, known)
    timers[e.name] = st
    if fire and not rune.debuff then expiring = true end
    if frame and prefs.show then
      if rune.debuff then
        di = di + 1
        if slots.debuffs[di] then fill(slots.debuffs[di], e, fraction) end
      else
        bi = bi + 1
        if slots.buffs[bi] then fill(slots.buffs[bi], e, fraction, st and st.warned) end
      end
    end
  end
  for name in pairs(timers) do
    if not seen[name] then timers[name] = nil end
  end
  if frame and prefs.show then
    for i = bi + 1, BB.BUFF_SLOTS do fill(slots.buffs[i], nil) end
    for i = di + 1, BB.DEBUFF_SLOTS do fill(slots.debuffs[i], nil) end
  end
  if expiring and prefs.expire then T.Sounds.Play("buff_expiring") end
  if T.Now() - lastTimerSave >= BB.TIMER_SAVE then BB.SaveTimers() end
end

-- One chat line per current effect, for checking durations in game:
-- "Light: 9.5 s left; TotalDuration 40, CurrentDuration 30.5; full duration 40 s (from the game)".
function BB.DebugLines()
  -- %g: the same text on every Lua (5.3+ would print 39.0 where MoonSharp prints 39)
  local function num(x) return type(x) == "number" and string.format("%g", x) or tostring(x) end
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
    local source = fromGame and "from the game" or (st and "observed or remembered") or "none yet"
    lines[#lines + 1] = string.format("%s%s: %s s left; TotalDuration %s, CurrentDuration %s; full duration %s (%s)",
      e.name, rune.IsDebuff and " (debuff)" or "", num(e.remaining), num(fx.TotalDuration),
      num(fx.CurrentDuration), st and (num(st.total) .. " s") or "?", source)
  end
  if #lines == 0 then lines[1] = "No buffs or debuffs right now." end
  return lines
end

-- Remembers the running timers so a /lua reload can pick them up (ShroudTime keeps running
-- through a reload, so "remaining then minus time since" is where each should be now).
function BB.SaveTimers()
  lastTimerSave = T.Now()
  local out = {}
  for name, st in pairs(timers) do
    if st and st.last and st.last > 0 then out[name] = { total = st.total, remaining = st.last, at = T.Now() } end
  end
  T.Save("buff_timers", out)
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
  end
  timers, debuffs, runes = {}, {}, {}
  local savedTimers = T.Load("buff_timers")
  remembered = type(savedTimers) == "table" and savedTimers or {}
  build()
  BB.Quiet()
  BB.OnBuffsChanged()                  -- the change callback only fires on changes
  ShroudRegisterPeriodic(PERIODIC, BB.Tick, BB.TICK, true)
  BB.Tick()
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function BB.IsShown() return prefs.show == true end

function BB.SetShown(on)
  prefs.show = on == true
  savePrefs()
  if frame then
    frame:SetVisible(prefs.show)
    if prefs.show then BB.Tick() end
  end
  T.Config.Sync()
end

function BB.Toggle() BB.SetShown(not prefs.show) end

local function inRange(n, lo, hi) return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi end

function BB.SetSize(n)
  if not inRange(n, BB.SIZE_MIN, BB.SIZE_MAX) then return false end
  prefs.size = n
  savePrefs()
  if frame then
    local w, h = frameSize()
    -- HUD frames of one add-on may cover at most 35% of the screen; a refused size keeps the old one.
    pcall(function() frame:SetSize(w, h) end)
    for _, group in pairs(slots) do
      for _, slot in ipairs(group) do
        slot.row:SetStyle{ width = n, height = n }
        slot.icon:SetSize(n, n)
        slot.overlay:SetSize(n, n)
        slot.overlay:SetStyle{ marginLeft = -n }
      end
    end
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
