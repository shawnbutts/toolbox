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

-- Backgrounds for the numbers, from the game's theme so they follow the player's skin.
-- Dark is the theme class `inset` (works in game). Light was the class `card`, which showed
-- nothing behind a label in game, so it is a panel in the theme colour @text (the skin's
-- light text colour) with dark text on it (the theme has no dark text colour). The Light
-- panel sits on a wrapper around the number: a colour set on the label itself can't be
-- unset later and would hide the Dark class's panel.
V.BACKGROUNDS = {
  { name = "None" },
  { name = "Dark", class = "inset" },
  { name = "Light", color = "@text", darkText = true },
}
V.DARK_TEXT = "#1a1a1a"

-- Flashing when low: below `flashBelow` % the bar and its number swap colours every
-- FLASH_TICKS ticks (0.4 s), to the theme's bright text colour.
V.FLASH_COLOR = "@text-bright"
V.FLASH_TICKS = 2
V.FLASH_MIN, V.FLASH_MAX, V.FLASH_DEFAULT = 1, 95, 20
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
local content = nil       -- the bar rows (in a strip owned by Toolbox.Hud)
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
local function showText() return prefs.showText ~= false end
local function showBars() return prefs.showBars ~= false end

local function background()
  for _, bg in ipairs(V.BACKGROUNDS) do
    if bg.name == prefs.bg then return bg end
  end
  return V.BACKGROUNDS[1]
end

-- The theme class for the current background, or nil.
function V.BackgroundClass()
  return background().class
end

-- The panel colour for the current background (on the wrapper), or nil.
function V.BackgroundPanel()
  return background().color
end

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
  local hasBg = V.BackgroundClass() or V.BackgroundPanel()
  m.pad = hasBg and math.max(2, math.floor(3 * f + 0.5)) or 0   -- room around the text on a background
  if not showBars() then m.barW, m.gap = 0, 0 end
  if not showText() then m.textW, m.gap, m.pad = 0, 0, 0 end
  m.contentW = m.barW + m.gap + m.textW + 2 * m.pad
  m.contentH = #V.BARS * (line + m.rowGap)
  m.frameW = T.Window.GRIP + m.contentW + 8        -- when in its own strip
  m.frameH = m.contentH + 8
  return m
end

local function barStyle(m) return { width = m.barW, height = m.barH } end
-- Colours for a bar and its number, normal or in the "flash" half of a low-value flash.
-- Numbers: dark on the Light panel; the bar's colour when the bars are hidden (so health and
-- focus can still be told apart); otherwise the theme's text colour.
function V.Colors(bar, flashing)
  local dark = background().darkText
  local text = nil
  if dark then
    text = flashing and bar.color or V.DARK_TEXT
  elseif not showBars() then
    text = flashing and V.FLASH_COLOR or bar.color
  else
    text = flashing and bar.color or "@text"
  end
  return flashing and V.FLASH_COLOR or bar.color, text
end

local function textStyle(m, bar)
  local _, color = V.Colors(bar, false)
  return { fontSize = m.font, height = m.line, minHeight = m.line, maxHeight = m.line, marginTop = 0,
           marginBottom = 0, paddingTop = 0, paddingBottom = 0,
           width = m.textW + 2 * m.pad, paddingLeft = m.pad, paddingRight = m.pad, textAlign = "left",
           color = color }
end

-- The wrapper around a number: the gap after the bar, and the Light panel.
local function wrapStyle(m)
  local panel = V.BackgroundPanel()
  return { marginLeft = m.gap, backgroundColor = panel or "#00000000", borderRadius = panel and 3 or 0 }
end

-- Builds the bar rows and returns them; Toolbox.Hud puts them in a strip.
function V.BuildContent()
  local m = V.Metrics()
  local rows = {}
  for _, bar in ipairs(V.BARS) do
    rows[#rows + 1] = UI.Row{ style = { alignItems = "center", marginBottom = m.rowGap }, children = {
      UI.Bar{ id = bar.key .. "_bar", value = 0, color = bar.color, tooltip = bar.label, style = barStyle(m),
        visible = showBars() },
      UI.Row{ id = bar.key .. "_wrap", style = wrapStyle(m), visible = showText(), children = {
        UI.Label{ id = bar.key .. "_text", text = "", class = V.BackgroundClass() and { "text", V.BackgroundClass() }
          or "text", style = textStyle(m, bar), tooltip = bar.label },
      } },
    } }
  end
  content = UI.Column{ id = "vitals", children = rows }
  el, shown = {}, {}
  for _, bar in ipairs(V.BARS) do
    el[bar.key .. "_bar"] = content:Find(bar.key .. "_bar")
    el[bar.key .. "_text"] = content:Find(bar.key .. "_text")
    el[bar.key .. "_wrap"] = content:Find(bar.key .. "_wrap")
  end
  return content
end

function V.ContentSize()
  local m = V.Metrics()
  return m.contentW, m.contentH
end
function V.GetSavedPosition() return prefs.x, prefs.y end
function V.SavePosition(x, y)
  if x ~= prefs.x or y ~= prefs.y then
    prefs.x, prefs.y = x, y
    T.Save("vitals", prefs)
  end
end

V.FRAME_ID = FRAME_ID
local mover = T.Hud.MoverFor("vitals", V.HOME)
V.GetPosition, V.MoveTo, V.Nudge, V.ResetPosition = mover.Get, mover.MoveTo, mover.Nudge, mover.Reset

local ticks = 0
local previewUntil = -math.huge
V.PREVIEW_SECONDS = 5

-- Flashes both bars for V.PREVIEW_SECONDS whatever the values, to see what it looks like.
-- Returns false (and says why) when the strip is hidden.
function V.PreviewFlash()
  if not prefs.show then
    T.Print("Show the health & focus bars first (/" .. T.commands[1] .. " vitals), then test the flash.")
    return false
  end
  previewUntil = T.Now() + V.PREVIEW_SECONDS
  T.Print("Flashing the bars for " .. V.PREVIEW_SECONDS .. " s...")
  return true
end

-- True while a value is below the flash threshold (and flashing is on).
function V.IsLow(current, value)
  return prefs.flash ~= false and type(current) == "number" and value < (prefs.flashBelow or V.FLASH_DEFAULT) / 100
end

function V.Tick()
  ticks = ticks + 1
  local phase = math.floor(ticks / V.FLASH_TICKS) % 2 == 1
  if content and prefs.show then
    for _, bar in ipairs(V.BARS) do
      local current, max = V.Read(bar)
      local value, text = V.Format(current, max)
      local flashing = (V.IsLow(current, value) or T.Now() < previewUntil) and phase
      local last = shown[bar.key] or {}
      if value ~= last.value then el[bar.key .. "_bar"]:SetValue(value) end
      if text ~= last.text then el[bar.key .. "_text"]:SetText(text) end
      if flashing ~= last.flashing then
        local barColor, textColor = V.Colors(bar, flashing)
        el[bar.key .. "_bar"]:SetColor(barColor)
        el[bar.key .. "_text"]:SetStyle{ color = textColor }
      end
      shown[bar.key] = { value = value, text = text, flashing = flashing }
    end
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
    prefs.showText = saved.showText ~= false
    prefs.showBars = saved.showBars ~= false
    if not prefs.showText and not prefs.showBars then prefs.showText = true end
    if type(saved.bg) == "string" then prefs.bg = saved.bg end
    prefs.flash = saved.flash ~= false
    if type(saved.flashBelow) == "number" and saved.flashBelow >= V.FLASH_MIN and saved.flashBelow <= V.FLASH_MAX then
      prefs.flashBelow = math.floor(saved.flashBelow)
    end
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
  end
  T.Hud.Register("vitals", V)
  ShroudRegisterPeriodic(PERIODIC, V.Tick, V.TICK, true)
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
  shown = {}
  T.Hud.Refresh()
  V.Tick()
  T.Config.Sync()
end

function V.Toggle() V.SetShown(not prefs.show) end

-- Re-applies the sizes to every element and the strip (after a width or size change).
local function applySize()
  if not content then return end
  local m = V.Metrics()
  for _, bar in ipairs(V.BARS) do
    el[bar.key .. "_bar"]:SetStyle(barStyle(m))
    el[bar.key .. "_bar"]:SetVisible(showBars())
    el[bar.key .. "_text"]:SetStyle(textStyle(m, bar))
    el[bar.key .. "_wrap"]:SetStyle(wrapStyle(m))
    el[bar.key .. "_wrap"]:SetVisible(showText())
    -- swap the background's theme class
    for _, bg in ipairs(V.BACKGROUNDS) do
      if bg.class then el[bar.key .. "_text"]:RemoveClass(bg.class) end
    end
    if V.BackgroundClass() then el[bar.key .. "_text"]:AddClass(V.BackgroundClass()) end
  end
  T.Hud.Refresh()
  shown = {}                                -- colours were reset: re-apply on the next tick
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

-- Shows or hides the numbers / the bars. Refuses to hide the last one (hide the strip with
-- /toolbox vitals instead). Returns true when the setting took.
local function setPart(key, on)
  local other = nil                        -- the other part (not `a and b or c`: b can be false)
  if key == "showText" then other = showBars() else other = showText() end
  if not on and not other then
    T.Print("The bars and the numbers can't both be off; hide the strip with /" .. T.commands[1] .. " vitals.")
    T.Config.Sync()
    return false
  end
  prefs[key] = on == true
  T.Save("vitals", prefs)
  shown = {}
  applySize()
  V.Tick()
  T.Config.Sync()
  return true
end

function V.SetShowText(on) return setPart("showText", on) end
function V.SetShowBars(on) return setPart("showBars", on) end
function V.GetShowText() return showText() end
function V.GetShowBars() return showBars() end

-- Background behind the numbers by display name (any case): None, Dark or Light.
function V.SetBackground(name)
  local found = nil
  for _, bg in ipairs(V.BACKGROUNDS) do
    if bg.name:lower() == tostring(name or ""):lower() then found = bg end
  end
  if not found then return false end
  prefs.bg = found.name
  T.Save("vitals", prefs)
  applySize()
  T.Config.Sync()
  return true
end

function V.GetBackground() return background().name end

-- Flash when low: on/off, and the threshold in percent.
function V.SetFlash(on)
  prefs.flash = on == true
  T.Save("vitals", prefs)
  shown = {}
  T.Config.Sync()
end

function V.GetFlash() return prefs.flash ~= false end

function V.SetFlashBelow(n)
  if not inRange(n, V.FLASH_MIN, V.FLASH_MAX) then return false end
  prefs.flashBelow = n
  T.Save("vitals", prefs)
  T.Config.Sync()
  return true
end

function V.GetFlashBelow() return prefs.flashBelow or V.FLASH_DEFAULT end

function V.BackgroundNames()
  local out = {}
  for _, bg in ipairs(V.BACKGROUNDS) do out[#out + 1] = bg.name end
  return out
end

-- The strip has its own Size setting, so the global text size and spacing don't change it.
-- (Kept so Toolbox.Window.ApplyText can call every text user alike.)
function V.ApplyText() end
