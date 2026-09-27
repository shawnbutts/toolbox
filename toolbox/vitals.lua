-- Toolbox: vitals.lua
-- Health & focus bars (/toolbox vitals): a movable HUD strip with a red health bar and a
-- blue focus bar, each with "current / max". A Size setting (75-250%) scales the whole strip.
--
-- Current values are the documented per-frame globals ShroudPlayerCurrentHealth and
-- ShroudPlayerCurrentFocus. The player's maximums have no documented getter; in game
-- (`/toolbox stats health`) the readable stats "Health" and "Focus" equal the current values
-- at full, so they are taken as the maximums, never shown below the current value. Vigor
-- isn't exposed to add-ons (no stat matches it), so there is no vigor bar.
--
-- Updated by a light periodic (V.TICK), touching the UI only when a shown value changes.

local T = Toolbox
local V = {}
Toolbox.Vitals = V

local UI = Shroud.UI
local FRAME_ID = "toolbox_vitals"
local PERIODIC = "toolbox_vitals"

V.TICK = 0.2
V.WIDTH_MIN, V.WIDTH_MAX, V.WIDTH_DEFAULT = 100, 400, 220   -- bar length at 100% size
V.SCALE_MIN, V.SCALE_MAX, V.SCALE_DEFAULT = 75, 250, 100    -- percent
V.BASE_FONT = 12                                             -- text size at 100%
V.HOME = { 40, 300 }
V.NUDGE = 10
-- `current` reads the per-frame global directly: reaching a global through a name built at
-- runtime is treated by review like runtime code loading (see AGENTS.md).
-- In game the bars first showed "--" and stayed empty, so the current value falls back to the
-- CurrentHealth / CurrentFocus stats when the per-frame global isn't a number.
V.BARS = {
  { key = "health", current = function() return ShroudPlayerCurrentHealth end, global = "ShroudPlayerCurrentHealth",
    currentStat = "CurrentHealth", maxStat = "Health", color = "@red", label = "Health" },
  { key = "focus", current = function() return ShroudPlayerCurrentFocus end, global = "ShroudPlayerCurrentFocus",
    currentStat = "CurrentFocus", maxStat = "Focus", color = "@blue", label = "Focus" },
}

local prefs = { show = false }
local frame = nil
local el = {}
local shown = {}          -- key -> { value = bar fill, text = label text } last set

-- ---------------------------------------------------------------------------
-- Model
-- ---------------------------------------------------------------------------

local function readable(n) return type(n) == "number" and n == n and n ~= InvalidStatResult end

-- Bar fill (0..1) and text for a current value and a maximum (either may be missing).
-- The maximum is never below the current value (the stat is fractional: 942.23 at 943).
function V.Format(current, max)
  if not readable(current) or current < 0 then return 0, "--" end
  local cur = math.floor(current + 0.5)
  if not readable(max) or max <= 0 then return 1, tostring(cur) end
  local m = math.max(math.floor(max + 0.5), cur)
  return m > 0 and cur / m or 0, cur .. " / " .. m
end

-- A readable stat's value, or nil (unknown name: -999; hidden: reads 0).
local function stat(name)
  local v = ShroudGetStatValueByName(name)
  if not readable(v) or (v == 0 and not ShroudIsStatVisible(name)) then return nil end
  return v
end

-- Current and max for one bar definition, and where the current value came from.
function V.Read(bar)
  local current, source = bar.current(), "global"
  if not readable(current) then current, source = stat(bar.currentStat), "stat" end
  return current, stat(bar.maxStat), current ~= nil and source or nil
end

-- ---------------------------------------------------------------------------
-- HUD frame
-- ---------------------------------------------------------------------------

local function width() return prefs.width or V.WIDTH_DEFAULT end
local function scale() return prefs.scale or V.SCALE_DEFAULT end

-- Everything's size from one factor (Shroud.UI has no zoom): text, line height, bar
-- thickness and length, the gap and number box, and the strip itself. The number box has a
-- fixed width so both bars line up; its text is left-aligned so it sits right after the bar.
function V.Metrics()
  local f = scale() / 100
  local font = math.max(9, math.min(32, math.floor(V.BASE_FONT * f + 0.5)))   -- fontSize is 9..32
  local line = math.ceil(font * 1.15) + 1
  local m = {
    font = font, line = line,
    barH = math.max(4, math.floor(line * 0.7 + 0.5)),
    barW = math.floor(width() * f + 0.5),
    gap = math.max(2, math.floor(4 * f + 0.5)),
    textW = math.ceil(font * 5.2),        -- room for "9999 / 9999"
    rowGap = math.max(1, math.floor(2 * f + 0.5)),
  }
  m.frameW = m.barW + m.gap + m.textW + 8
  m.frameH = #V.BARS * (line + m.rowGap) + 8
  return m
end

local function barStyle(m) return { width = m.barW, height = m.barH } end
local function textStyle(m)
  return { fontSize = m.font, height = m.line, minHeight = m.line, maxHeight = m.line, marginTop = 0,
           marginBottom = 0, paddingTop = 0, paddingBottom = 0, marginLeft = m.gap, width = m.textW,
           textAlign = "left" }
end

local function build()
  local m = V.Metrics()
  local rows = {}
  for _, bar in ipairs(V.BARS) do
    rows[#rows + 1] = UI.Row{ style = { alignItems = "center", marginBottom = m.rowGap }, children = {
      UI.Bar{ id = bar.key .. "_bar", value = 0, color = bar.color, tooltip = bar.label, style = barStyle(m) },
      UI.Label{ id = bar.key .. "_text", text = "", class = "text", style = textStyle(m) },
    } }
  end
  frame = UI.HudFrame{ id = FRAME_ID, x = prefs.x or V.HOME[1], y = prefs.y or V.HOME[2],
    width = m.frameW, height = m.frameH, visible = prefs.show, children = rows }
  el, shown = {}, {}
  for _, bar in ipairs(V.BARS) do
    el[bar.key .. "_bar"] = frame:Find(bar.key .. "_bar")
    el[bar.key .. "_text"] = frame:Find(bar.key .. "_text")
  end
end

local mover = T.Window.HudMover(function() return frame end, V.HOME)
V.GetPosition, V.MoveTo, V.Nudge, V.ResetPosition = mover.Get, mover.MoveTo, mover.Nudge, mover.Reset

function V.Tick()
  if frame and prefs.show then
    for _, bar in ipairs(V.BARS) do
      local current, max = V.Read(bar)
      local value, text = V.Format(current, max)
      local last = shown[bar.key] or {}
      if value ~= last.value then el[bar.key .. "_bar"]:SetValue(value) end
      if text ~= last.text then el[bar.key .. "_text"]:SetText(text) end
      shown[bar.key] = { value = value, text = text }
    end
  end
  -- Remember where the player put it (grip drag or buttons), as the buff bar does.
  local x, y = V.GetPosition()
  if x and (x ~= prefs.x or y ~= prefs.y) then
    prefs.x, prefs.y = x, y
    T.Save("vitals", prefs)
  end
end

function V.Init()
  local saved = T.Load("vitals")
  prefs = { show = false }
  if type(saved) == "table" then
    prefs.show = saved.show == true
    if type(saved.width) == "number" and saved.width >= V.WIDTH_MIN and saved.width <= V.WIDTH_MAX then
      prefs.width = math.floor(saved.width)
    end
    if type(saved.scale) == "number" and saved.scale >= V.SCALE_MIN and saved.scale <= V.SCALE_MAX then
      prefs.scale = math.floor(saved.scale)
    end
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
  end
  build()
  ShroudRegisterPeriodic(PERIODIC, V.Tick, V.TICK, true)
  V.Tick()
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

-- /toolbox vitals debug: what each source holds and what the bar shows.
function V.DebugLines()
  local lines = {}
  for _, bar in ipairs(V.BARS) do
    local g = bar.current()
    local current, max, source = V.Read(bar)
    local fill, text = V.Format(current, max)
    local function show(v) return type(v) == "number" and string.format("%g", v) or (type(v) .. " " .. tostring(v)) end
    lines[#lines + 1] = string.format("%s: %s = %s; stat %s = %s; stat %s = %s; using %s -> \"%s\", fill %.2f",
      bar.label, bar.global, show(g), bar.currentStat, show(ShroudGetStatValueByName(bar.currentStat)),
      bar.maxStat, show(ShroudGetStatValueByName(bar.maxStat)), source or "nothing readable", text, fill)
  end
  return lines
end

function V.IsShown() return prefs.show == true end

function V.SetShown(on)
  prefs.show = on == true
  T.Save("vitals", prefs)
  if frame then
    frame:SetVisible(prefs.show)
    shown = {}
    V.Tick()
  end
  T.Config.Sync()
end

function V.Toggle() V.SetShown(not prefs.show) end

-- Re-applies the sizes to every element and the strip (after a width or size change).
local function applySize()
  if not frame then return end
  local m = V.Metrics()
  for _, bar in ipairs(V.BARS) do
    el[bar.key .. "_bar"]:SetStyle(barStyle(m))
    el[bar.key .. "_text"]:SetStyle(textStyle(m))
  end
  pcall(function() frame:SetSize(m.frameW, m.frameH) end)   -- refused past the HUD area limit: keep the old size
end

local function inRange(n, lo, hi) return type(n) == "number" and n == math.floor(n) and n >= lo and n <= hi end

function V.SetWidth(n)
  if not inRange(n, V.WIDTH_MIN, V.WIDTH_MAX) then return false end
  prefs.width = n
  T.Save("vitals", prefs)
  applySize()
  T.Config.Sync()
  return true
end

function V.GetWidth() return width() end

-- Size of the whole strip, in percent (V.SCALE_MIN..V.SCALE_MAX).
function V.SetScale(n)
  if not inRange(n, V.SCALE_MIN, V.SCALE_MAX) then return false end
  prefs.scale = n
  T.Save("vitals", prefs)
  applySize()
  T.Config.Sync()
  return true
end

function V.GetScale() return scale() end

-- The strip has its own Size setting, so the global text size and spacing don't change it.
-- (Kept so Toolbox.Window.ApplyText can call every text user alike.)
function V.ApplyText() end
