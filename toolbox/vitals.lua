-- Toolbox: vitals.lua
-- Health & focus bars (/toolbox vitals): a movable HUD strip with a red health bar and a
-- blue focus bar, each with "current / max". A Size setting (75-250%) scales the whole strip.
--
-- Current values are the documented per-frame globals ShroudPlayerCurrentHealth and
-- ShroudPlayerCurrentFocus. The player's maximums have no documented getter; in game
-- (`/toolbox stats health`) the readable stats "Health" and "Focus" equal the current values
-- at full, so they are taken as the maximums, never shown below the current value.
--
-- A third, gold Vigor bar (API 20, feature-detected: ShroudGetVigor / ShroudOnVigorChanged) shows
-- "64%" with the regen and crit bonuses in its tooltip. The reading is kept from the callback (core.lua)
-- and re-read every V.VIGOR_POLL s; the row hides while there is none (below the level where
-- Vigor applies) or when the "vigor" setting is off. Vigor never flashes.
--
-- Updated by a light periodic (V.TICK), touching the UI only when a shown value changes.

local T = Toolbox
local V = {}
Toolbox.Vitals = V

local UI = Shroud.UI
local FRAME_ID = "toolbox_vitals"
local PERIODIC = "toolbox_vitals"

V.TICK = 0.2
V.WIDTH_MIN, V.WIDTH_MAX, V.WIDTH_DEFAULT = 20, 400, 220    -- bar length at 100% size
V.SCALE_MIN, V.SCALE_MAX, V.SCALE_DEFAULT = 75, 250, 100    -- percent
V.ROW_GAP = 2                                                 -- px between rows at 100%
V.BAR_THICKNESS = 0.5     -- bar height / line height (was 0.7: the bars touched, "looks like a flag")
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
  { key = "vigor", vigor = true, color = "@gold", label = "Vigor" },
}
V.VIGOR_POLL = 5          -- seconds between re-reads of ShroudGetVigor (the callback is the main source)

local prefs = { show = false }
local content = nil       -- the bar rows (in a strip owned by Toolbox.Hud)
local el = {}
local shown = {}          -- key -> { value = bar fill, text = label text } last set
local barEls = {}         -- key -> { bar = Bar, text = Label } (set at build)
local vigor = nil         -- the last Vigor reading (V.ReadVigor's shape), nil when there is none
local vigorShow = { 0, "--", "Vigor" }   -- its fill, text and tooltip, formatted once per reading
local lastVigorRead = -math.huge
local vigorRowShown = nil

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

-- Vigor (API 20): ShroudGetVigor()'s answer (a table or a game object) as plain data
-- { vigor, max, percent, rested, health, focus, crit }, or nil when there is none.
function V.ReadVigor(v)
  if v == nil then return nil end
  local function num(k)
    local x = T.Field(v, k)
    return (type(x) == "number" and x == x) and x or nil
  end
  local out = { vigor = num("vigor"), max = num("max") or 100, percent = num("percent"),
                rested = T.Field(v, "rested") == true, health = num("healthRegenBonus") or 0,
                focus = num("focusRegenBonus") or 0, crit = num("critBonus") or 0 }
  if not out.vigor then return nil end
  if not out.percent then out.percent = math.floor(out.vigor * 100 / math.max(1, out.max)) end
  return out
end

-- Bar fill (0..1), text and tooltip for a Vigor reading.
function V.FormatVigor(v)
  if not v then return 0, "--", "Vigor" end
  local fill = math.max(0, math.min(1, v.vigor / math.max(1, v.max)))
  local tip = string.format("Vigor %d%%%s\n+%s%% health regen, +%s%% focus regen, +%s%% critical chance",
    math.floor(v.percent), v.rested and " (rested)" or "", tostring(v.health), tostring(v.focus), tostring(v.crit))
  return fill, math.floor(v.percent) .. "%", tip
end

function V.HasVigor() return type(ShroudGetVigor) == "function" end

-- From ShroudOnVigorChanged (core.lua), and the periodic re-read.
function V.OnVigorChanged(v)
  vigor = V.ReadVigor(v)
  lastVigorRead = T.Now()
  vigorShow[1], vigorShow[2], vigorShow[3] = V.FormatVigor(vigor)
end

local function readVigorNow()
  if not V.HasVigor() then
    if vigor then V.OnVigorChanged(nil) end
    lastVigorRead = T.Now()
    return
  end
  local ok, v = pcall(ShroudGetVigor)
  V.OnVigorChanged(ok and v or nil)
end

-- ---------------------------------------------------------------------------
-- HUD frame
-- ---------------------------------------------------------------------------

local function width() return prefs.width or V.WIDTH_DEFAULT end
local function scale() return prefs.scale or V.SCALE_DEFAULT end
local function showText() return prefs.showText ~= false end
local function showBars() return prefs.showBars ~= false end
local function vigorShown() return prefs.vigor ~= false and vigor ~= nil end

-- How many bar rows show (the Vigor row only while there is a reading).
local function rowCount()
  local n = 0
  for _, bar in ipairs(V.BARS) do
    if not bar.vigor or vigorShown() then n = n + 1 end
  end
  return n
end

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
    barH = math.max(3, math.floor(line * V.BAR_THICKNESS + 0.5)),
    barW = math.floor(width() * f + 0.5),
    gap = math.max(2, math.floor(4 * f + 0.5)),
    textW = math.ceil(font * 5.2),        -- room for "9999 / 9999"
    rowGap = math.max(2, math.floor(V.ROW_GAP * f + 0.5)),   -- rows are a text line high
  }
  local hasBg = V.BackgroundClass() or V.BackgroundPanel()
  m.pad = hasBg and math.max(2, math.floor(3 * f + 0.5)) or 0   -- room around the text on a background
  if not showBars() then m.barW, m.gap = 0, 0 end
  if not showText() then m.textW, m.gap, m.pad = 0, 0, 0 end
  m.contentW = m.barW + m.gap + m.textW + 2 * m.pad
  m.contentH = rowCount() * (line + m.rowGap)
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
    rows[#rows + 1] = UI.Row{ id = bar.key .. "_row", visible = not bar.vigor or vigorShown(),
      style = { alignItems = "center", marginBottom = m.rowGap }, children = {
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
    el[bar.key .. "_row"] = content:Find(bar.key .. "_row")
    barEls[bar.key] = { bar = el[bar.key .. "_bar"], text = el[bar.key .. "_text"] }
  end
  vigorRowShown = vigorShown()
  return content
end

-- For Toolbox.Hud: the strip was destroyed; V.Tick skips the bars until BuildContent runs again.
function V.Unbuilt()
  content, vigorRowShown = nil, nil
end

-- The health and focus rows' heights as laid out (GetSize; nil before the first layout or unbuilt).
-- The mirrored target copies them, so its bars sit level with these (owner, 2026-09-29: "lower than mine").
function V.RowHeights()
  if not content then return nil, nil end
  local function h(e)
    if not e then return nil end
    local ok, _, height = pcall(e.GetSize, e)
    if ok and type(height) == "number" and height > 0 then return height end
    return nil
  end
  return h(el.health_row), h(el.focus_row)
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

-- Five times a second, so it allocates nothing on a quiet tick: one state table per bar (updated in
-- place; `shown = {}` elsewhere forces a full re-apply) and the bars' elements looked up once at build.
function V.Tick()
  ticks = ticks + 1
  local phase = math.floor(ticks / V.FLASH_TICKS) % 2 == 1
  local now = T.Now()
  if now - lastVigorRead >= V.VIGOR_POLL then readVigorNow() end
  if content and vigorShown() ~= vigorRowShown then       -- Vigor appeared, went away, or was switched
    vigorRowShown = vigorShown()
    el.vigor_row:SetVisible(vigorRowShown)
    T.Hud.Refresh()
  end
  if content and prefs.show then
    for _, bar in ipairs(V.BARS) do
      local current, value, text, tip = nil, nil, nil, nil
      if bar.vigor then
        value, text, tip = vigorShow[1], vigorShow[2], vigorShow[3]
      else
        local max = nil
        current, max = V.Read(bar)
        value, text = V.Format(current, max)
      end
      local flashing = not bar.vigor and (V.IsLow(current, value) or now < previewUntil) and phase
      local last = shown[bar.key]
      if not last then
        last = {}
        shown[bar.key] = last
      end
      local els = barEls[bar.key]
      if value ~= last.value then els.bar:SetValue(value) end
      if text ~= last.text then els.text:SetText(text) end
      if tip then
        T.SetTooltip(els.bar, tip)
        T.SetTooltip(els.text, tip)
      end
      if flashing ~= last.flashing then
        local barColor, textColor = V.Colors(bar, flashing)
        els.bar:SetColor(barColor)
        els.text:SetStyle{ color = textColor }
      end
      last.value, last.text, last.flashing = value, text, flashing
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
    prefs.vigor = saved.vigor ~= false
  end
  vigor, lastVigorRead, vigorRowShown = nil, -math.huge, nil
  vigorShow[1], vigorShow[2], vigorShow[3] = V.FormatVigor(nil)
  readVigorNow()                     -- the callback fires only on a change: read the start here
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
    if bar.vigor then
      local raw = nil
      if V.HasVigor() then
        local ok, v = pcall(ShroudGetVigor)
        raw = ok and v or nil
      end
      local fill, text = V.FormatVigor(vigor)
      lines[#lines + 1] = string.format("Vigor: ShroudGetVigor %s; vigor %s, percent %s, max %s, rested %s; "
        .. "bonuses health %s, focus %s, crit %s; showing \"%s\", fill %.2f, setting %s",
        V.HasVigor() and type(raw) or "missing (needs API 20)", tostring(T.Field(raw, "vigor")),
        tostring(T.Field(raw, "percent")), tostring(T.Field(raw, "max")), tostring(T.Field(raw, "rested")),
        tostring(T.Field(raw, "healthRegenBonus")), tostring(T.Field(raw, "focusRegenBonus")),
        tostring(T.Field(raw, "critBonus")), text, fill, prefs.vigor ~= false and "on" or "off")
    else
    local g = bar.current()
    local current, max, source = V.Read(bar)
    local fill, text = V.Format(current, max)
    local function show(v) return type(v) == "number" and string.format("%g", v) or (type(v) .. " " .. tostring(v)) end
    lines[#lines + 1] = string.format("%s: %s = %s; stat %s = %s; stat %s = %s; using %s -> \"%s\", fill %.2f",
      bar.label, bar.global, show(g), bar.currentStat, show(ShroudGetStatValueByName(bar.currentStat)),
      bar.maxStat, show(ShroudGetStatValueByName(bar.maxStat)), source or "nothing readable", text, fill)
    end
  end
  -- What the rows asked for next to what the game laid out (does a Bar honour its height?).
  local m = V.Metrics()
  local function size(e)
    if not e then return "?" end
    local ok, w, h = pcall(e.GetSize, e)
    if not ok then return "?" end
    return tostring(w) .. "x" .. tostring(h)
  end
  lines[#lines + 1] = string.format("Layout: asked bar %dx%d, row %d high, %d px between rows; laid out: "
    .. "health bar %s, health row %s, focus row %s", m.barW, m.barH, m.line, m.rowGap,
    size(content and el.health_bar), size(content and el.health_row), size(content and el.focus_row))
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
  if T.Target then T.Target.ApplySize() end   -- the Toolbelt's target bars match these
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

-- The Vigor row (shown while there is a reading).
function V.GetShowVigor() return prefs.vigor ~= false end

function V.SetShowVigor(on)
  prefs.vigor = on == true
  T.Save("vitals", prefs)
  shown = {}
  V.Tick()
  T.Config.Sync()
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

-- ===========================================================================
-- Toolbox.Target: the target HUD (/toolbox target)
-- ===========================================================================
-- One row: the target's name with its health (and focus) as thin bars, then its effects as icons with
-- the buff bar's clock sweep: debuffs (outlined) first, then the soonest to end. Its own strip, or the
-- Toolbelt's last row (built by the buff bar, like the consumables and equipment rows: TG.BuildRow,
-- TG.Glued, TG.GluedCount). Every value is what the game's own target frame shows: a creature hiding its
-- health reads full ("health hidden"). The API doesn't say who applied an effect, so every effect on the
-- target is listed, not only yours.
--
-- Read every TG.POLL seconds while built and at once on ShroudOnTargetChanged (core.lua). The grouped
-- list (ShroudGetTargetBuff: debuff flags and full durations) is read only when the target or its effect
-- count changes, or every TG.GROUP_EVERY seconds; the flat getters give names, time left, icons, tooltips.
-- Saved var "target": { show = bool (default false), glue = bool (default true), place = "top"|"bottom"
-- (in the Toolbelt: above the buffs, the default, or under everything), x, y }.
-- On top its row keeps its height while there's no target, so the buffs under it don't jump each time
-- you pick up or drop a target (the strip is anchored at its top-left grip).

local TG = {}
Toolbox.Target = TG

TG.FRAME_ID = "toolbox_target"
TG.HOME = { 40, 420 }
TG.SLOTS = 8                 -- effect icons at most
TG.INFO_CELLS = 4            -- the name block's width, in icon cells
TG.POLL = 0.25
TG.GROUP_EVERY = 2
TG.PLACES = { top = "Above the buffs", bottom = "Under everything", left = "Left of your bars (mirrored)" }
TG.PLACE_ORDER = { "top", "bottom", "left" }
TG.LEFT_SLOTS = 5            -- icons when mirrored on the left (its width is always kept: keep it small)
local TPERIODIC = "toolbox_target"

local tprefs = { show = false, glue = true, place = "top" }
local tContent, tInfo, tName, tHealth, tFocus = nil, nil, nil, nil, nil
local tSlots = {}
local tShownCount = nil      -- cells the row takes (for the strip's size), when it last changed
local tHas = nil             -- whether the last poll had a target
local tId, tCount, tGroupAt = nil, nil, -math.huge
local tInfoBy = {}           -- rune name -> { debuff = bool, total = seconds }, from the grouped list
local tRaw = {}              -- reused: one entry per effect this poll
local tList = {}             -- reused: what the slots show, sorted
local tPending = false       -- a sweep couldn't be drawn (the shared budget); tried again next poll

local function tSave() T.Save("target", tprefs) end
local function iconSize() return T.BuffBar.GetSize() end

-- "73%", "health hidden" or "dead" for the name line (pure).
function TG.HealthText(cur, max, hidden, dead)
  if dead then return "dead" end
  if hidden then return "health hidden" end
  if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return "" end
  return math.floor(math.max(0, math.min(1, cur / max)) * 100 + 0.5) .. "%"
end

-- The name to show (pure). Some creatures have no display name, and the game then reports its fallback:
-- "Entity with no name (Stag_04_Large(Clone))" (seen 2026-09-29). That shows the object's internal name
-- tidied up ("Stag Large": "(Clone)" and number-only parts dropped, underscores as spaces), or "Unnamed".
-- Plain find/sub only (MoonSharp: no lazy patterns on game text).
function TG.CleanName(name)
  if type(name) ~= "string" then return "" end
  local at = name:lower():find("with no name", 1, true)
  if not at then return name end
  local open = name:find("(", at, true)
  if not open then return "Unnamed" end
  local inner = name:sub(open + 1)
  local clone = inner:find("(Clone)", 1, true)
  if clone then inner = inner:sub(1, clone - 1) end
  local words = {}
  for w in inner:gmatch("[^_%s%(%)]+") do
    if not w:match("^%d+$") then words[#words + 1] = w end
  end
  if #words == 0 then return "Unnamed" end
  return table.concat(words, " ")
end

-- Sorts effects for the row (pure): debuffs first, then the soonest to end (permanent ones, 0 left,
-- last), then by name.
function TG.Before(a, b)
  if a.debuff ~= b.debuff then return a.debuff end
  local ra = (a.remaining > 0) and a.remaining or math.huge
  local rb = (b.remaining > 0) and b.remaining or math.huge
  if ra ~= rb then return ra < rb end
  return a.name < b.name
end

-- Groups the flat effects (`raw`, entries { name, remaining, index }) by name, keeping the longest time
-- left, fills in debuff and full duration from `infoBy`, sorts them (TG.Before) and writes at most `max`
-- into `out` (reused entries). Returns how many. Pure.
function TG.Collect(raw, n, infoBy, out, max)
  local count = 0
  for i = 1, n do
    local r = raw[i]
    local found = nil
    for j = 1, count do
      if out[j].name == r.name then found = out[j] end
    end
    if found then
      if r.remaining > found.remaining then found.remaining, found.index = r.remaining, r.index end
    else
      count = count + 1
      local e = out[count] or {}
      out[count] = e
      local info = infoBy[r.name]
      e.name, e.remaining, e.index = r.name, r.remaining, r.index
      e.debuff = info ~= nil and info.debuff == true
      e.total = info ~= nil and info.total or 0
    end
  end
  for j = count + 1, #out do out[j] = nil end
  table.sort(out, TG.Before)
  for j = max + 1, #out do out[j] = nil end
  return math.min(count, max)
end

-- The grouped list's debuff flags and full durations, by rune name (game objects read by field).
local function readGroups()
  tInfoBy = {}
  local ok, list = pcall(ShroudGetTargetBuff)
  if not ok then return end
  for _, rune in ipairs(T.List(list)) do
    local name = T.Field(rune, "RuneName")
    if type(name) == "string" then
      local total = 0
      for _, e in ipairs(T.List(T.Field(rune, "Effects"))) do
        local td = T.Field(e, "TotalDuration")
        if type(td) == "number" and td > total then total = td end
      end
      tInfoBy[name] = { debuff = T.Field(rune, "IsDebuff") == true, total = total }
    end
  end
end

function TG.IsEnabled() return tprefs.show == true end
function TG.GetShow() return tprefs.show == true end
function TG.GetGlue() return tprefs.glue ~= false end

-- In the Toolbelt right now (the setting, and the buff bar switched on).
function TG.Glued() return tprefs.show == true and tprefs.glue ~= false and T.BuffBar.IsEnabled() end

-- In the Toolbelt with the health bars there too: Toolbox.Hud puts the row under both columns, so the
-- target's bars start at the health bars' left end (owner, 2026-09-29). Otherwise, in the Toolbelt, it is
-- the buff column's last row.
function TG.Below() return TG.Glued() and T.Hud.IsGlued() end

-- The buff column's last row (in the Toolbelt, the health bars not).
function TG.InBuffColumn() return TG.Glued() and not TG.Below() end

-- For Toolbox.Hud: built by it on its own strip, or under the Toolbelt's columns (Below).
function TG.Wanted() return tprefs.show == true and (not TG.Glued() or TG.Below()) end

function TG.Place()
  if tprefs.place == "bottom" then return "bottom" end
  if TG.Mirrored() then return "left" end
  return "top"
end
function TG.GetPlace() return tprefs.place end

-- Mirrored to the left of the health bars (owner, 2026-09-29, "may remove it"): only with the health bars
-- in the Toolbelt too (TG.Below); otherwise "left" works like "top".
function TG.Mirrored() return tprefs.place == "left" and TG.Below() end

-- Above or to the left in the Toolbelt: the row keeps its space with no target (the strip is anchored at
-- its top-left grip, so anything appearing above or left of the bars would push them).
local function reserved() return tprefs.place ~= "bottom" and TG.Glued() end

-- Whether the row shows: a target, the settings window open (to place it), or its space kept.
local function wantRow() return tHas == true or T.Config.IsShown() or reserved() end

function TG.IsShown() return TG.Wanted() and wantRow() end

-- Cells the name block takes (set when built; the Toolbelt's depends on the health bars' size).
local tInfoCells = TG.INFO_CELLS
local tBelt = false          -- built for the Toolbelt: no text, bars sized like the player's
local tBelow = false         -- ... and across both of its columns (TG.Below)
local tLeft = false          -- ... mirrored to the left of the health bars (TG.Mirrored)
local tRows = {}             -- the mirrored form's two bar rows (health, focus)
local tRowH = {}             -- ... their heights, measured from the health bars' rows (V.RowHeights)
local tSyncUntil, tSyncAt = 0, -math.huge
TG.SYNC_FOR, TG.SYNC_EVERY = 5, 10   -- measure for this long after a build or resize, then this often

-- Cells the row takes in the Toolbelt (0 when hidden or not glued).
function TG.GluedCount()
  if not TG.Glued() or TG.Below() or not wantRow() then return 0 end
  return tInfoCells + #tList
end

-- The name block's sizes for icon size s. Own strip: the name over a thin health and focus bar, INFO_CELLS
-- wide. In the Toolbelt (owner, 2026-09-29: no name or percent there; hover for them): just the bars, the
-- length and thickness of the player's health bars (V.Metrics: their Size and Bar length). Under the
-- columns (Below) the block is as wide as the health bars' column, so the icons line up under the buffs.
local function infoLayout(s)
  local gap, cell = T.BuffBar.GAP, s + T.BuffBar.GAP
  local L = {}
  if tBelt then
    local m = V.Metrics()
    L.barW = math.floor(V.GetWidth() * V.GetScale() / 100 + 0.5)
    L.hBar, L.fBar = m.barH, m.barH
    L.line, L.rowGap = m.line, m.rowGap
    if tLeft then
      -- a fixed block: the icons, then the bars (their rows as tall as the health bars' rows)
      L.w = L.barW
      L.blockW = TG.LEFT_SLOTS * cell + L.barW
      L.blockH = math.max(s, 2 * (m.line + m.rowGap))
      L.cells = 0
    elseif tBelow then
      L.w = math.max(L.barW, (V.ContentSize()) + T.Hud.GAP - gap)
      L.cells = (L.w + gap) / cell                -- not whole cells: ContentSize adds the icons
    else
      L.cells = math.max(1, math.ceil((L.barW + gap) / cell))
      L.w = L.cells * cell - gap
    end
  else
    L.cells = TG.INFO_CELLS
    L.w = TG.INFO_CELLS * cell - gap
    L.barW = L.w
    L.font = math.max(9, math.floor(s * 0.4))
    L.hBar = math.max(3, math.floor(s * 0.22))
    L.fBar = math.max(2, math.floor(s * 0.12))
  end
  return L
end

local function barStyleT(w, h, below)
  return { width = w, height = h, minHeight = h, maxHeight = h, marginBottom = below or 0 }
end

-- Applies infoLayout to the built name block (at build, and when a size changes).
local tBlockW, tBlockH = 0, 0

-- Mirrored: copies the health bars' rows' laid-out heights to the target's two rows (their asked-for height
-- isn't what the game lays out), so each target bar sits level with the player's. Returns true on a change.
local function syncRows(s)
  local changed = false
  local h1, h2 = V.RowHeights()
  local gap = V.Metrics().rowGap
  for i, h in ipairs({ h1 or false, h2 or false }) do
    if h and tRows[i] and h ~= tRowH[i] then
      tRowH[i] = h
      tRows[i]:SetStyle{ height = h, minHeight = h, maxHeight = h, marginBottom = gap }
      changed = true
    end
  end
  if changed then
    tBlockH = math.max(s, (tRowH[1] or 0) + (tRowH[2] or 0) + 2 * gap)
    tContent:SetStyle{ height = tBlockH, minHeight = tBlockH }
  end
  return changed
end
local function styleInfo(s)
  local L = infoLayout(s)
  tInfoCells = L.cells
  if tLeft then
    tBlockW, tBlockH = L.blockW, L.blockH
    tInfo:SetStyle{ width = L.w, marginRight = 0 }
    for _, r in ipairs(tRows) do
      r:SetStyle{ width = L.w, height = L.line, minHeight = L.line, maxHeight = L.line, marginBottom = L.rowGap }
    end
    local bar = barStyleT(L.barW, L.hBar, 0)
    bar.rotate = 180                             -- fills from the right: a mirror of the player's bars
    tHealth:SetStyle(bar)
    tFocus:SetStyle(bar)
    if tContent then tContent:SetStyle{ width = tBlockW, minWidth = tBlockW, height = tBlockH, minHeight = tBlockH } end
    tRowH, tSyncUntil = {}, T.Now() + TG.SYNC_FOR  -- measure the health bars' rows again
    return
  end
  tInfo:SetStyle{ width = L.w, height = s, marginRight = T.BuffBar.GAP }
  tHealth:SetStyle(barStyleT(L.barW, L.hBar, 2))
  tFocus:SetStyle(barStyleT(L.barW, L.fBar, 0))
  if not tBelt then
    local h = s - L.hBar - L.fBar - 2
    tName:SetStyle{ fontSize = L.font, width = L.w, height = h, minHeight = h, maxHeight = h,
                    whiteSpace = "nowrap", marginLeft = 0, marginRight = 0, marginTop = 0, marginBottom = 0,
                    paddingTop = 0, paddingBottom = 0 }
  end
end

-- The row: the name block and the effect slots. The target strip's content, or the Toolbelt's last row.
function TG.BuildRow()
  T.BuffBar.ClockReady()
  local s = iconSize()
  tBelow = TG.inBuffBar ~= true and TG.Below()
  tBelt = TG.inBuffBar == true or tBelow
  tLeft = tBelow and TG.Mirrored()
  tHealth = UI.Bar{ id = "target_health", value = 0, color = "@red" }
  tFocus = UI.Bar{ id = "target_focus", value = 0, color = "@blue", visible = false }
  tRows = {}
  if tLeft then
    tName = nil
    tRows[1] = UI.Row{ style = { alignItems = "center", justifyContent = "end" }, children = { tHealth } }
    tRows[2] = UI.Row{ style = { alignItems = "center", justifyContent = "end" }, children = { tFocus } }
    tInfo = UI.Column{ id = "target_info", children = { tRows[1], tRows[2] } }
  elseif tBelt then
    tName = nil
    tInfo = UI.Column{ id = "target_info", style = { justifyContent = "center" }, children = { tHealth, tFocus } }
  else
    tName = UI.Label{ id = "target_name", text = "", class = "text" }
    tInfo = UI.Column{ id = "target_info", children = { tName, tHealth, tFocus } }
  end
  styleInfo(s)
  local children = { tInfo }
  tSlots = {}
  for i = 1, (tLeft and TG.LEFT_SLOTS or TG.SLOTS) do
    local icon = UI.Image{ width = s, height = s, onClick = function() end }   -- a click handler: tooltips show
    local overlay = T.BuffBar.SweepHolder(s)
    local row = UI.Row{ visible = false, children = { icon, overlay },
      style = { width = s, height = s, marginRight = T.BuffBar.GAP, backgroundColor = "#00000066",
                borderWidth = 0, borderColor = "@red" } }
    tSlots[i] = { row = row, icon = icon, overlay = overlay }
    if tLeft then table.insert(children, 1, row) else children[#children + 1] = row end   -- mirrored: outward
  end
  if tLeft then           -- a fixed block, its contents against the health bars (right)
    tContent = UI.Row{ id = "target", visible = false, style = { alignItems = "start", justifyContent = "end",
      width = tBlockW, minWidth = tBlockW, height = tBlockH, minHeight = tBlockH }, children = children }
  else
    tContent = UI.Row{ id = "target", visible = false, style = { alignItems = "center", height = s, minHeight = s },
      children = children }
  end
  tShownCount, tHas, tId, tCount, tGroupAt = nil, nil, nil, nil, -math.huge
  return tContent
end

function TG.BuildContent()
  TG.inBuffBar = false
  return TG.BuildRow()
end

-- For Toolbox.Hud (and BB.Unbuilt when in the Toolbelt): the row was destroyed; the poll skips it.
function TG.Unbuilt()
  tContent, tInfo, tName, tHealth, tFocus, TG.inBuffBar = nil, nil, nil, nil, nil, false
  tSlots, tRows, tShownCount = {}, {}, nil
end

function TG.ContentSize()
  if tLeft and tContent then return tBlockW, tBlockH end
  local cell = iconSize() + T.BuffBar.GAP
  return math.ceil((tInfoCells + #tList) * cell), iconSize()
end

-- A size changed (the buff bar's icon size, or the health bars' Size / Bar length): resized in place
-- (sliders fire many changes; rebuilding each time would hit the element-creation cap), then re-fitted.
function TG.ApplySize()
  if not tContent then return end
  local s = iconSize()
  styleInfo(s)
  for _, slot in ipairs(tSlots) do
    slot.row:SetStyle{ width = s, height = s }
    slot.icon:SetSize(s, s)
    slot.overlay:SetStyle{ width = s, height = s, marginLeft = -s }
    slot.k = nil                                -- redraw the sweep at the new size
  end
  tShownCount = nil
  TG.Poll(false)
  if TG.Glued() and not TG.Below() then T.BuffBar.Tick() else T.Hud.Refresh() end
end

-- Fills the effect slots from tList.
local function fillSlots(s)
  tPending = false
  for i, slot in ipairs(tSlots) do
    local e = tList[i]
    if e then
      local tex = ShroudGetTargetBuffIcon(e.index)
      if tex ~= slot.tex then
        slot.tex = tex
        if type(tex) == "number" and tex >= 0 then slot.icon:SetTexture(tex) end
      end
      T.SetVisible(slot.icon, type(tex) == "number" and tex >= 0)
      if e.debuff ~= slot.debuff then
        slot.debuff = e.debuff
        slot.row:SetStyle{ borderWidth = e.debuff and 2 or 0 }
      end
      if e.name ~= slot.name then
        slot.name = e.name
        slot.k = nil
      end
      local tip = ShroudGetTargetBuffTooltip(e.index)
      T.SetTooltip(slot.icon, (type(tip) == "string" and tip ~= "") and tip or e.name)
      local k = 0
      if e.total > 0 and e.remaining > 0 then k = T.BuffBar.Frame(math.min(1, e.remaining / e.total)) end
      if k ~= slot.k then
        if k > 0 then
          if T.BuffBar.ShowFrame(slot, k, false, s) then slot.k = k else tPending = true end
        else
          T.BuffBar.HideFrame(slot)
          slot.k = k
        end
      end
    end
    T.SetVisible(slot.row, e ~= nil)
  end
end

-- Reads the target and updates the row. `force`: re-read the grouped list too.
function TG.Poll(force)
  if not tContent then return end
  local has = tprefs.show == true and ShroudHasTarget() == true
  local s = iconSize()
  if has then
    local id = ShroudGetTargetId()
    local n = ShroudGetTargetBuffCount()
    if type(n) ~= "number" or n < 0 then n = 0 end
    local now = T.Now()
    if force or id ~= tId or n ~= tCount or now - tGroupAt >= TG.GROUP_EVERY then
      tId, tCount, tGroupAt = id, n, now
      readGroups()
    end
    for i = 1, n do
      local r = tRaw[i] or {}
      tRaw[i] = r
      r.index = i - 1
      r.name = ShroudGetTargetBuffName(i - 1)
      local left = ShroudGetTargetBuffTimeRemaining(i - 1)
      r.remaining = (type(left) == "number" and left > 0) and left or 0
    end
    TG.Collect(tRaw, n, tInfoBy, tList, #tSlots)
    local cur, max = ShroudGetTargetCurrentHealth(), ShroudGetTargetMaxHealth()
    local hidden, dead = ShroudIsTargetHealthHidden() == true, ShroudIsTargetDead() == true
    local pct = TG.HealthText(cur, max, hidden, dead)
    local raw = ShroudGetTargetName()
    local name = TG.CleanName(raw)
    if tName then T.SetText(tName, name .. (pct ~= "" and ("  " .. pct) or "")) end
    local fill = 0
    if not dead and type(cur) == "number" and type(max) == "number" and max > 0 then
      fill = math.max(0, math.min(1, cur / max))
    end
    T.SetValue(tHealth, fill)
    local fcur, fmax = ShroudGetTargetCurrentFocus(), ShroudGetTargetMaxFocus()
    local hasFocus = type(fmax) == "number" and fmax > 0 and type(fcur) == "number"
    T.SetVisible(tFocus, hasFocus)
    if hasFocus then T.SetValue(tFocus, math.max(0, math.min(1, fcur / fmax))) end
    local tip = name .. ((raw ~= name and type(raw) == "string") and ("\n(" .. raw .. ")") or "")
      .. (hidden and "\nHealth hidden" or ((type(cur) == "number" and type(max) == "number"
      and max > 0) and string.format("\nHealth %s / %s", T.FormatNumber(cur), T.FormatNumber(max)) or ""))
      .. (hasFocus and string.format("\nFocus %s / %s", T.FormatNumber(fcur), T.FormatNumber(fmax)) or "")
      .. (dead and "\nDead" or "")
    T.SetTooltip(tInfo, tip)
  else
    for j = 1, #tList do tList[j] = nil end
    if tName then T.SetText(tName, T.Config.IsShown() and "Target (none)" or "") end
    T.SetValue(tHealth, 0)
    T.SetVisible(tFocus, false)
    T.SetTooltip(tInfo, "Your target's health and effects show here")
    tId, tCount = nil, nil
  end
  fillSlots(s)
  if tLeft then
    local now = T.Now()
    if now < tSyncUntil or now - tSyncAt >= TG.SYNC_EVERY then
      tSyncAt = now
      if syncRows(s) then tShownCount = nil end      -- re-fit the strip below
    end
  end
  local show = has or T.Config.IsShown() or reserved()
  T.SetVisible(tContent, show)
  T.SetVisible(tInfo, has or T.Config.IsShown())     -- kept space only: empty, not a bar at 0
  local cells = show and (tInfoCells + #tList) or 0
  if has ~= tHas or cells ~= tShownCount then
    tHas, tShownCount = has, cells
    if TG.Glued() and not TG.Below() then T.BuffBar.Tick() else T.Hud.Refresh() end
  end
end

-- In the Toolbelt: "top" (above the buffs), "bottom" (under everything) or "left" (mirrored, left of the
-- health bars). Returns false for anything else.
function TG.SetPlace(where)
  if not TG.PLACES[where] then return false end
  tprefs.place = where
  tSave()
  if TG.Glued() then T.Hud.Build() end
  TG.Poll(true)
  T.BuffBar.Tick()
  T.Config.Sync()
  return true
end

-- ShroudOnTargetChanged (core.lua): a new target, or none.
function TG.OnTargetChanged()
  TG.Poll(true)
end

function TG.GetSavedPosition() return tprefs.x, tprefs.y end
function TG.SavePosition(x, y)
  if x ~= tprefs.x or y ~= tprefs.y then
    tprefs.x, tprefs.y = x, y
    tSave()
  end
end

local targetMover = T.Hud.MoverFor("target", TG.HOME)
TG.GetPosition, TG.MoveTo, TG.Nudge, TG.ResetPosition = targetMover.Get, targetMover.MoveTo, targetMover.Nudge,
  targetMover.Reset

function TG.Init()
  local saved = T.Load("target")
  tprefs = { show = false, glue = true, place = "top" }
  if type(saved) == "table" then
    tprefs.show = saved.show == true
    tprefs.glue = saved.glue ~= false
    if saved.place == "bottom" then tprefs.place = "bottom" end
    if type(saved.x) == "number" and type(saved.y) == "number" then tprefs.x, tprefs.y = saved.x, saved.y end
  end
  tList, tRaw, tInfoBy = {}, {}, {}
  T.Hud.Register("target", TG)
  ShroudRegisterPeriodic(TPERIODIC, function()
    TG.Poll(false)
  end, TG.POLL, true)
end

-- A sweep left undrawn (the shared budget) is retried on the next poll anyway; this is for tests.
function TG.Pending() return tPending end

-- Shows the target HUD, or not.
function TG.SetShow(on)
  tprefs.show = on == true
  tSave()
  if TG.Glued() or not on then T.Hud.Build() else T.Hud.Build(true) end
  TG.Poll(true)
  T.Config.Sync()
end

-- In the Toolbelt (its last row), or its own strip.
function TG.SetGlue(on)
  tprefs.glue = on == true
  tSave()
  T.Hud.Build()
  TG.Poll(true)
  T.BuffBar.Tick()
  T.Config.Sync()
end

-- /toolbox target debug: what the game reports for the target.
function TG.DebugLines()
  local lines = {}
  if not ShroudHasTarget() then
    lines[1] = "No target (ShroudHasTarget false). Setting: " .. (tprefs.show and "on" or "off")
      .. (TG.Glued() and ", in the Toolbelt" or (tprefs.show and ", own strip" or "")) .. "."
    return lines
  end
  lines[#lines + 1] = string.format("Target %q (id %s): health %s / %s%s%s, focus %s / %s",
    tostring(ShroudGetTargetName()),
    tostring(ShroudGetTargetId()), tostring(ShroudGetTargetCurrentHealth()), tostring(ShroudGetTargetMaxHealth()),
    ShroudIsTargetHealthHidden() and " (hidden)" or "", ShroudIsTargetDead() and " (dead)" or "",
    tostring(ShroudGetTargetCurrentFocus()), tostring(ShroudGetTargetMaxFocus()))
  local n = ShroudGetTargetBuffCount()
  lines[#lines + 1] = "Effects (flat): " .. tostring(n)
  for i = 0, math.min((tonumber(n) or 0), 20) - 1 do
    local name = ShroudGetTargetBuffName(i)
    local info = tInfoBy[name]
    lines[#lines + 1] = string.format("  %d %s: %s s left, icon %s%s%s", i, tostring(name),
      tostring(ShroudGetTargetBuffTimeRemaining(i)), tostring(ShroudGetTargetBuffIcon(i)),
      info and info.debuff and ", debuff" or "", info and info.total > 0 and (", of " .. info.total .. " s") or "")
  end
  return lines
end
