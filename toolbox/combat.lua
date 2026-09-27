-- Toolbox: combat.lua
-- Combat stats HUD (/toolbox combat): damage per second (last few seconds and fight
-- average), damage taken and healing per second, crit % and avoided %, the fight timer,
-- and a configurable list of character stats (magic resistance by default).
--
-- Numbers come from ShroudOnCombatEvents: the combat chat lines about you, your party or
-- your pet ("the same lines your combat chat shows"). A fight starts with
-- ShroudOnCombatModeChanged(true) or the first damage line, and ends when combat mode ends
-- (or after C.IDLE_END quiet seconds); its numbers stay up until the next fight starts.
-- The game passes at most 50 lines a frame; extra ones (`dropped`) can't be counted.

local T = Toolbox
local C = {}
Toolbox.Combat = C

local UI = Shroud.UI
local PERIODIC = "toolbox_combat"
C.FRAME_ID = "toolbox_combat"
C.HOME = { 40, 380 }
C.TICK = 0.5
C.WINDOW = 5                   -- seconds for the "now" rates
C.IDLE_END = 12                -- a fight also ends after this long without a combat line
C.SCALE_MIN, C.SCALE_MAX, C.SCALE_DEFAULT = 75, 250, 100
C.BASE_FONT = 12
-- Stats shown by default. The docs name MagicResistance (Animal Lore's "Defenses" stat);
-- other names are found in game with /toolbox stats and added with /toolbox combat stat add.
C.DEFAULT_STATS = { "MagicResistance" }
C.MAX_STATS = 8

-- A panel behind the whole strip, for readability. There is no documented theme background
-- colour, so, as for the health & focus numbers: Dark is the theme's `inset` look, Light a
-- panel in the theme colour @text with dark text on it.
-- The panel must not be the rows' parent (its opacity would fade the text too), so it is
-- built from slabs under the rows: each row has a full-width slab one line tall, and the row
-- is pulled up onto it by one line height. (One big panel with the rows shifted across it by
-- the strip's width doesn't work: the game clamps margins to -64..256, which pushed the rows
-- out of the strip in game.) Dark and Light are separate slabs because a colour set on an
-- element can't be unset.
C.BACKGROUNDS = { "None", "Dark", "Light" }
C.BG_DEFAULT, C.OPACITY_DEFAULT = "Dark", 70
C.OPACITY_MIN, C.OPACITY_MAX = 10, 100
C.DARK_TEXT = "#1a1a1a"

C.DAMAGE_KINDS = { hit = true, critical = true, glancing = true, ultraslay = true }
C.HEAL_KINDS = { heal = true, criticalHeal = true }
C.AVOID_KINDS = { dodge = true, parry = true, block = true }

-- ---------------------------------------------------------------------------
-- Fight model (no API calls)
-- ---------------------------------------------------------------------------

function C.NewFight(now)
  return { start = now, last = now, ended = nil, out = 0, taken = 0, healed = 0, hits = 0, crits = 0,
           attacksIn = 0, avoided = 0, dropped = 0, recent = {} }
end

-- Adds one combat line. `pet` counts your pet's damage as yours.
function C.Add(f, e, now, pet)
  if type(e) ~= "table" then return end
  local amount = type(e.amount) == "number" and e.amount > 0 and e.amount or 0
  local mine = e.fromYou == true or (pet and e.fromYourPet == true)
  local atMe = e.toYou == true
  if mine and C.DAMAGE_KINDS[e.kind] and not atMe then
    f.out = f.out + amount
    f.hits = f.hits + 1
    if e.kind == "critical" then f.crits = f.crits + 1 end
    f.recent[#f.recent + 1] = { t = now, out = amount }
  elseif e.fromYou == true and C.HEAL_KINDS[e.kind] then
    f.healed = f.healed + amount
    f.recent[#f.recent + 1] = { t = now, heal = amount }
  end
  if atMe and not e.fromYou then
    if C.DAMAGE_KINDS[e.kind] then
      f.taken = f.taken + amount
      f.attacksIn = f.attacksIn + 1
      f.recent[#f.recent + 1] = { t = now, taken = amount }
    elseif C.AVOID_KINDS[e.kind] then
      f.attacksIn = f.attacksIn + 1
      f.avoided = f.avoided + 1
    end
  end
  f.last = now
end

-- Drops "recent" entries older than the window.
function C.Prune(f, now)
  local keep = {}
  for _, r in ipairs(f.recent) do
    if now - r.t < C.WINDOW then keep[#keep + 1] = r end
  end
  f.recent = keep
end

function C.Duration(f, now)
  return math.max(0, (f.ended or now) - f.start)
end

-- Per-second rates for the last C.WINDOW seconds (or the whole fight while it's shorter)
-- and over the whole fight: { out, taken, healed } each.
function C.Rates(f, now)
  local dur = C.Duration(f, now)
  local recentSpan = math.max(1, math.min(C.WINDOW, dur))
  local r = { out = 0, taken = 0, healed = 0 }
  if not f.ended then
    for _, e in ipairs(f.recent) do
      if now - e.t < C.WINDOW then
        r.out, r.taken, r.healed = r.out + (e.out or 0), r.taken + (e.taken or 0), r.healed + (e.heal or 0)
      end
    end
  end
  local span = math.max(1, dur)
  return { out = r.out / recentSpan, taken = r.taken / recentSpan, healed = r.healed / recentSpan },
         { out = f.out / span, taken = f.taken / span, healed = f.healed / span }
end

-- Percentages (0-100) or nil when there's nothing to divide by.
function C.CritPct(f) return f.hits > 0 and 100 * f.crits / f.hits or nil end
function C.AvoidPct(f) return f.attacksIn > 0 and 100 * f.avoided / f.attacksIn or nil end

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------

local prefs = {}
local fight = nil            -- current or last fight
local inCombat = false
local content = nil
local el = {}
local shownText = {}

local function scale() return prefs.scale or C.SCALE_DEFAULT end

local function save() T.Save("combat", prefs) end

local function statList() return prefs.stats or C.DEFAULT_STATS end

local function startFight()
  fight = C.NewFight(T.Now())
end

local function endFight()
  if fight and not fight.ended then fight.ended = fight.last > fight.start and fight.last or T.Now() end
end

function C.OnCombatMode(on)
  inCombat = on == true
  if inCombat then
    if not fight or fight.ended then startFight() end
  else
    endFight()
  end
end

function C.OnEvents(events, dropped)
  if type(events) ~= "table" then return end
  local now = T.Now()
  for _, e in ipairs(events) do
    local relevant = type(e) == "table" and (C.DAMAGE_KINDS[e.kind] or C.HEAL_KINDS[e.kind] or C.AVOID_KINDS[e.kind])
      and (e.fromYou or e.toYou or e.fromYourPet)
    if relevant then
      if not fight or fight.ended then startFight() end
      C.Add(fight, e, now, prefs.pet ~= false)
    end
  end
  if fight and type(dropped) == "number" and dropped > 0 then fight.dropped = fight.dropped + dropped end
end

function C.Reset()
  fight = nil
  if inCombat then startFight() end
  shownText = {}
  C.Tick()
end

-- ---------------------------------------------------------------------------
-- HUD content: rows of "label ........ value"
-- ---------------------------------------------------------------------------

local function num(n) return T.FormatNumber(n or 0) end
local function pct(p) return p and string.format("%d%%", math.floor(p + 0.5)) or "--" end

-- The rows as { id, label, value } for the current fight and stats.
function C.Rows(now)
  local rows = {}
  local f = fight
  local recent, avg = { out = 0, taken = 0, healed = 0 }, { out = 0, taken = 0, healed = 0 }
  if f then recent, avg = C.Rates(f, now) end
  local timer = f and T.FormatDuration(C.Duration(f, now)) or "--"
  local status = not f and "" or (f.ended and " (ended)" or "")
  rows[#rows + 1] = { id = "fight", label = "Fight", value = timer .. status }
  rows[#rows + 1] = { id = "dps", label = "DPS", value = num(recent.out) .. "  avg " .. num(avg.out) }
  rows[#rows + 1] = { id = "taken", label = "Taken /s", value = num(recent.taken) .. "  avg " .. num(avg.taken) }
  rows[#rows + 1] = { id = "hps", label = "Healing /s", value = num(recent.healed) .. "  avg " .. num(avg.healed) }
  rows[#rows + 1] = { id = "crit", label = "Crit", value = f and pct(C.CritPct(f)) or "--" }
  rows[#rows + 1] = { id = "avoid", label = "Avoided", value = f and pct(C.AvoidPct(f)) or "--" }
  for i, name in ipairs(statList()) do
    local v = ShroudGetStatValueByName(name)
    local readable = type(v) == "number" and v ~= InvalidStatResult and not (v == 0 and not ShroudIsStatVisible(name))
    rows[#rows + 1] = { id = "stat" .. i, label = name, value = readable and string.format("%g", v) or "n/a" }
  end
  return rows
end

local function background() return prefs.bg or C.BG_DEFAULT end
local function opacity() return prefs.bgOpacity or C.OPACITY_DEFAULT end

function C.Metrics()
  local f = scale() / 100
  local font = math.max(9, math.min(32, math.floor(C.BASE_FONT * f + 0.5)))
  local line = math.ceil(font * 1.15) + 1
  local labelW, valueW = math.ceil(font * 7.5), math.ceil(font * 9)
  local pad = background() ~= "None" and math.max(3, math.floor(5 * f + 0.5)) or 0
  return { font = font, line = line, labelW = labelW, valueW = valueW, pad = pad,
           w = labelW + valueW, h = (6 + C.MAX_STATS) * line }
end

local function labelStyle(m, width, align)
  return { fontSize = m.font, height = m.line, minHeight = m.line, maxHeight = m.line, width = width,
           marginTop = 0, marginBottom = 0, paddingTop = 0, paddingBottom = 0, textAlign = align,
           color = background() == "Light" and C.DARK_TEXT or nil }
end

local shownRows = 0
local pads = {}              -- top and bottom padding slabs: { dark, light, group }

-- Shows, sizes and fades the panel slabs for the current background and size.
local function applyBackground()
  if not content then return end
  local m = C.Metrics()
  local bg = background()
  local w = m.w + 2 * m.pad
  local function slab(dark, light, h)
    dark:SetVisible(bg == "Dark")
    light:SetVisible(bg == "Light")
    for _, e in ipairs({ dark, light }) do e:SetStyle{ width = w, height = h, opacity = opacity() / 100 } end
  end
  for _, slot in ipairs(el) do
    slab(slot.dark, slot.light, m.line)
    slot.line:SetStyle{ marginTop = bg ~= "None" and -m.line or 0, paddingLeft = m.pad }
  end
  for _, p in ipairs(pads) do
    slab(p.dark, p.light, m.pad)
    p.group:SetVisible(bg ~= "None")
  end
end

local function slabs(h)
  return UI.Column{ class = "inset", visible = false, style = { height = h } },
         UI.Column{ visible = false, style = { backgroundColor = "@text", height = h } }
end

function C.BuildContent()
  local m = C.Metrics()
  local groups = {}
  el, shownText, shownRows, pads = {}, {}, 0, {}
  for _, where in ipairs({ "top", "bottom" }) do
    local dark, light = slabs(m.pad)
    pads[#pads + 1] = { dark = dark, light = light,
      group = UI.Column{ id = "pad_" .. where, visible = false, children = { dark, light } } }
  end
  groups[1] = pads[1].group
  for i = 1, 6 + C.MAX_STATS do
    -- names in the normal text colour and values bright (the dim names were hard to read)
    local name = UI.Label{ text = "", class = "text", style = labelStyle(m, m.labelW, "left") }
    local value = UI.Label{ text = "", class = "bright", style = labelStyle(m, m.valueW, "right") }
    local dark, light = slabs(m.line)
    local line = UI.Row{ children = { name, value } }     -- no id: ids repeated per row may not be allowed
    local group = UI.Column{ visible = false, children = { dark, light, line } }
    groups[#groups + 1] = group
    el[i] = { row = group, name = name, value = value, dark = dark, light = light, line = line }
  end
  groups[#groups + 1] = pads[2].group
  content = UI.Column{ id = "combat_rows", children = groups }
  C.Tick()
  applyBackground()
  return content
end

function C.ContentSize()
  local m = C.Metrics()
  return m.w + 2 * m.pad, math.max(1, shownRows) * m.line + 2 * m.pad
end

function C.GetSavedPosition() return prefs.x, prefs.y end
function C.SavePosition(x, y)
  if x ~= prefs.x or y ~= prefs.y then
    prefs.x, prefs.y = x, y
    save()
  end
end

function C.Tick()
  local now = T.Now()
  if fight and not fight.ended then
    C.Prune(fight, now)
    if not inCombat and now - fight.last >= C.IDLE_END then endFight() end
  end
  if not content or not prefs.show then return end
  local rows = C.Rows(now)
  for i, slot in ipairs(el) do
    local r = rows[i]
    local key = r and (r.label .. "\0" .. r.value) or nil
    if key ~= shownText[i] then
      shownText[i] = key
      if r then
        slot.name:SetText(r.label)
        slot.value:SetText(r.value)
      end
      slot.row:SetVisible(r ~= nil)
    end
  end
  if #rows ~= shownRows then
    shownRows = #rows
    applyBackground()
    T.Hud.Refresh()
  end
end

local mover = T.Hud.MoverFor("combat", C.HOME)
C.GetPosition, C.MoveTo, C.Nudge, C.ResetPosition = mover.Get, mover.MoveTo, mover.Nudge, mover.Reset

function C.Init()
  local saved = T.Load("combat")
  prefs = { show = false }
  if type(saved) == "table" then
    prefs.show = saved.show == true
    prefs.pet = saved.pet ~= false
    if type(saved.scale) == "number" and saved.scale >= C.SCALE_MIN and saved.scale <= C.SCALE_MAX then
      prefs.scale = math.floor(saved.scale)
    end
    if type(saved.stats) == "table" then
      prefs.stats = {}
      for _, name in ipairs(saved.stats) do
        if type(name) == "string" and #prefs.stats < C.MAX_STATS then prefs.stats[#prefs.stats + 1] = name end
      end
    end
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
    for _, b in ipairs(C.BACKGROUNDS) do if saved.bg == b then prefs.bg = b end end
    if type(saved.bgOpacity) == "number" and saved.bgOpacity >= C.OPACITY_MIN and saved.bgOpacity <= C.OPACITY_MAX then
      prefs.bgOpacity = math.floor(saved.bgOpacity)
    end
  end
  inCombat = ShroudGetPlayerCombatMode() == true   -- change callbacks only fire on changes
  if inCombat then startFight() end
  T.Hud.Register("combat", C)
  ShroudRegisterPeriodic(PERIODIC, C.Tick, C.TICK, true)
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function C.IsShown() return prefs.show == true end

function C.SetShown(on)
  prefs.show = on == true
  save()
  shownText = {}
  T.Hud.Refresh()
  C.Tick()
  T.Config.Sync()
end

function C.Toggle() C.SetShown(not prefs.show) end

function C.SetScale(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < C.SCALE_MIN or n > C.SCALE_MAX then return false end
  prefs.scale = n
  save()
  if content then
    local m = C.Metrics()
    for _, slot in ipairs(el) do
      slot.name:SetStyle(labelStyle(m, m.labelW, "left"))
      slot.value:SetStyle(labelStyle(m, m.valueW, "right"))
    end
    applyBackground()
    T.Hud.Refresh()
  end
  T.Config.Sync()
  return true
end

-- Background: "None" / "Dark" / "Light" (any case), and optionally its opacity in percent.
function C.SetBackground(name, percent)
  local found
  for _, b in ipairs(C.BACKGROUNDS) do
    if b:lower() == tostring(name or ""):lower() then found = b end
  end
  if not found then return false end
  if percent ~= nil then
    local ok = type(percent) == "number" and percent == math.floor(percent)
      and percent >= C.OPACITY_MIN and percent <= C.OPACITY_MAX
    if not ok then return false end
  end
  prefs.bg = found
  if percent then prefs.bgOpacity = percent end
  save()
  if content then
    local m = C.Metrics()
    for _, slot in ipairs(el) do
      slot.name:SetStyle(labelStyle(m, m.labelW, "left"))
      slot.value:SetStyle(labelStyle(m, m.valueW, "right"))
    end
    applyBackground()
    T.Hud.Refresh()
  end
  T.Config.Sync()
  return true
end

function C.GetBackground() return background(), opacity() end

function C.GetScale() return scale() end

function C.SetPet(on)
  prefs.pet = on == true
  save()
  T.Config.Sync()
end

function C.GetPet() return prefs.pet ~= false end

function C.Stats() return statList() end

-- Adds a stat by its internal name (as /toolbox stats lists it). Returns ok, message.
function C.AddStat(name)
  name = tostring(name or ""):match("^%s*(%S+)%s*$")
  if not name then return false, "Give a stat's internal name, as /" .. T.commands[1] .. " stats lists it." end
  local list = {}
  for _, s in ipairs(statList()) do
    if s:lower() == name:lower() then return false, s .. " is already shown." end
    list[#list + 1] = s
  end
  local v = ShroudGetStatValueByName(name)
  if v == InvalidStatResult then
    return false, "No stat is called " .. name .. " (see /" .. T.commands[1] .. " stats)."
  end
  if not ShroudIsStatVisible(name) then return false, name .. " is hidden from add-ons." end
  if #list >= C.MAX_STATS then return false, "At most " .. C.MAX_STATS .. " stats." end
  list[#list + 1] = name
  prefs.stats = list
  save()
  shownText = {}
  C.Tick()
  return true, "Added " .. name .. "."
end

function C.RemoveStat(name)
  local list, found = {}, false
  for _, s in ipairs(statList()) do
    if s:lower() == tostring(name or ""):lower() then found = true else list[#list + 1] = s end
  end
  if not found then return false, "Not shown: " .. tostring(name) .. "." end
  prefs.stats = list
  save()
  shownText = {}
  C.Tick()
  return true, "Removed " .. name .. "."
end
