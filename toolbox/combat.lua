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
-- colour.
--   Dark: the rows' parent gets a flat black background whose alpha is the opacity
--   ("#000000b3"). A colour's own alpha doesn't fade the children (the opacity style would).
--   It was the theme's `inset` look, built from per-row slabs, but that look has shaded edges,
--   which showed as a line between every row in game (2026-09-27).
--   Light: a panel in the theme colour @text with dark text on it. A token carries no alpha, so
--   it is built from slabs under the rows: each row has a full-width slab one line tall, and the
--   row is pulled up onto it by one line height. (One big panel with the rows shifted across it
--   by the strip's width doesn't work: the game clamps margins to -64..256.)
C.BACKGROUNDS = { "None", "Dark", "Light" }
C.BG_DEFAULT, C.OPACITY_DEFAULT = "Dark", 70
C.OPACITY_MIN, C.OPACITY_MAX = 10, 100
C.DARK_TEXT = "#1a1a1a"

C.DAMAGE_KINDS = { hit = true, critical = true, glancing = true, ultraslay = true }
C.HEAL_KINDS = { heal = true, criticalHeal = true }
C.AVOID_KINDS = { dodge = true, parry = true, block = true }
C.SLICE = 2                    -- seconds per column of the damage timeline
C.TIMELINE = 60                -- seconds the timeline covers
C.HISTORY = 10                 -- finished fights the session remembers

-- ---------------------------------------------------------------------------
-- Fight model (no API calls)
-- ---------------------------------------------------------------------------

function C.NewFight(now)
  return { start = now, last = now, ended = nil, out = 0, taken = 0, healed = 0, hits = 0, crits = 0,
           attacksIn = 0, avoided = 0, dropped = 0, recent = {}, overheal = 0, runes = {}, targets = {},
           types = { out = {}, taken = {} } }
end

-- The whole session: the same numbers summed over every fight (API 17 per-skill details too),
-- `active` = seconds of finished fights, and the damage timeline (C.SLICE-second slices keyed by
-- slice number: { out, taken }), which runs across fights.
function C.NewSession(now)
  local s = C.NewFight(now)
  s.active, s.fights, s.timeline, s.history = 0, 0, {}, {}
  return s
end

-- A finished fight's summary for the session's history: { secs, out, dps, taken, healed, top
-- (skill with the most damage, or ""), kills }.
function C.Summary(f)
  local secs = C.Duration(f, f.ended or f.last)
  local top = C.TopRunes(f, 1)[1]
  local kills = 0
  for _, tg in pairs(f.targets) do
    if tg.killed then kills = kills + 1 end
  end
  return { secs = secs, out = f.out, dps = f.out / math.max(1, secs), taken = f.taken, healed = f.healed,
           top = top and top.name or "", kills = kills }
end

-- Adds a finished fight to the session's history (newest first, at most C.HISTORY). Fights with no
-- damage either way (a combat-mode blip) are left out.
function C.Remember(s, f)
  if f.out <= 0 and f.taken <= 0 then return end
  table.insert(s.history, 1, C.Summary(f))
  for i = #s.history, C.HISTORY + 1, -1 do s.history[i] = nil end
end

-- One skill's numbers (by runeId, the same in every language; by name when there is no id;
-- "(other)" when the line names no skill).
local function runeStats(stats, e)
  local id = type(e.runeId) == "number" and e.runeId > 0 and e.runeId or nil
  local name = type(e.rune) == "string" and e.rune ~= "" and e.rune or nil
  if not name and type(e.skill) == "string" and e.skill ~= "" then name = e.skill end
  local key = id or (name and ("n:" .. name)) or "other"
  local r = stats.runes[key]
  if not r then
    r = { name = name or "(other)", dmg = 0, hits = 0, crits = 0, dots = 0, heal = 0, overheal = 0 }
    stats.runes[key] = r
  end
  return r
end

-- Adds a line's per-skill and healing details (API 17 fields; absent fields count as nothing).
-- The key of a line's creature: its per-scene key (API 17) with its name, since keys start over
-- in each scene; by name alone when there's no key.
function C.TargetKey(key, name)
  name = type(name) == "string" and name or ""
  if type(key) == "number" and key > 0 then return key .. ":" .. name end
  if name ~= "" then return "n:" .. name end
  return nil
end

local function addDetails(stats, e, amount, kind, t)
  local dtype = type(e.damageType) == "string" and e.damageType ~= "" and e.damageType or "other"
  if kind == "out" then
    local r = runeStats(stats, e)
    r.dmg, r.hits = r.dmg + amount, r.hits + 1
    if e.kind == "critical" then r.crits = r.crits + 1 end
    if e.dot == true then r.dots = r.dots + 1 end
    stats.types.out[dtype] = (stats.types.out[dtype] or 0) + amount
    local key = C.TargetKey(e.targetKey, e.target)
    if key then
      local tg = stats.targets[key]
      if not tg then
        tg = { name = type(e.target) == "string" and e.target ~= "" and e.target or "(unknown)", dmg = 0, hits = 0,
               first = t, last = t }
        stats.targets[key] = tg
      end
      tg.dmg, tg.hits, tg.last = tg.dmg + amount, tg.hits + 1, t
    end
  elseif kind == "taken" then
    stats.types.taken[dtype] = (stats.types.taken[dtype] or 0) + amount
  elseif kind == "heal" then
    local over = type(e.overheal) == "number" and e.overheal > 0 and e.overheal or 0
    local r = runeStats(stats, e)
    r.heal, r.overheal = r.heal + amount, r.overheal + over
    stats.overheal = stats.overheal + over
  end
end

-- Puts damage in the session's timeline slice for the line's time.
function C.AddTimeline(s, t, out, taken)
  local k = math.floor(t / C.SLICE)
  local slot = s.timeline[k]
  if not slot then
    slot = { out = 0, taken = 0 }
    s.timeline[k] = slot
  end
  slot.out, slot.taken = slot.out + (out or 0), slot.taken + (taken or 0)
end

-- The last C.TIMELINE seconds as per-second rates, oldest first: { { out, taken } ... }, and the
-- slices older than that dropped.
function C.Timeline(s, now)
  local n = math.floor(C.TIMELINE / C.SLICE)
  local last = math.floor(now / C.SLICE)
  for k in pairs(s.timeline) do
    if k <= last - n then s.timeline[k] = nil end
  end
  local out = {}
  for i = 1, n do
    local slot = s.timeline[last - n + i]
    out[i] = { out = slot and slot.out / C.SLICE or 0, taken = slot and slot.taken / C.SLICE or 0 }
  end
  return out
end

-- Skills by damage, most first (at most `n`): { name, dmg, share (0-1 of all damage), hits,
-- crits, dots }.
function C.TopRunes(stats, n)
  local list = {}
  for _, r in pairs(stats.runes) do
    if r.dmg > 0 then list[#list + 1] = r end
  end
  table.sort(list, function(a, b)
    if a.dmg ~= b.dmg then return a.dmg > b.dmg end
    return a.name < b.name
  end)
  local out = {}
  for i = 1, math.min(n, #list) do
    local r = list[i]
    out[i] = { name = r.name, dmg = r.dmg, share = stats.out > 0 and r.dmg / stats.out or 0, hits = r.hits,
               crits = r.crits, dots = r.dots }
  end
  return out
end

-- Creatures by damage you did to them, most first (at most `n`): { name, dmg, hits, secs (first
-- hit to kill, or to the last hit while alive), killed }.
function C.TopTargets(stats, n)
  local list = {}
  for _, tg in pairs(stats.targets) do list[#list + 1] = tg end
  table.sort(list, function(a, b)
    if a.dmg ~= b.dmg then return a.dmg > b.dmg end
    return a.name < b.name
  end)
  local out = {}
  for i = 1, math.min(n, #list) do
    local tg = list[i]
    out[i] = { name = tg.name, dmg = tg.dmg, hits = tg.hits, killed = tg.killed == true,
               secs = tg.killed and tg.killTime or math.max(0, tg.last - tg.first) }
  end
  return out
end

-- Damage by type ("out" = done, "taken"), most first: { type, amount, share (0-1) }.
function C.Types(stats, which)
  local list, total = {}, 0
  for dtype, amount in pairs(stats.types[which] or {}) do
    if amount > 0 then
      list[#list + 1] = { type = dtype, amount = amount }
      total = total + amount
    end
  end
  table.sort(list, function(a, b)
    if a.amount ~= b.amount then return a.amount > b.amount end
    return a.type < b.type
  end)
  for _, x in ipairs(list) do x.share = total > 0 and x.amount / total or 0 end
  return list
end

-- Overheal as a percentage of all healing done (healed + wasted), or nil when nothing healed.
function C.OverhealPct(stats)
  local total = stats.healed + stats.overheal
  if total <= 0 then return nil end
  return 100 * stats.overheal / total
end

-- Adds one combat line to a fight (and, when given, the session). `pet` counts your pet's damage
-- as yours.
-- One line's numbers into one set of stats (a fight, or the session).
local function addTo(s, e, amount, mine, atMe, t, now)
  if mine and C.DAMAGE_KINDS[e.kind] and not atMe then
    s.out = s.out + amount
    s.hits = s.hits + 1
    if e.kind == "critical" then s.crits = s.crits + 1 end
    addDetails(s, e, amount, "out", t)
  elseif e.fromYou == true and C.HEAL_KINDS[e.kind] then
    s.healed = s.healed + amount
    addDetails(s, e, amount, "heal", t)
  end
  if atMe and not e.fromYou then
    if C.DAMAGE_KINDS[e.kind] then
      s.taken = s.taken + amount
      addDetails(s, e, amount, "taken", t)
      s.attacksIn = s.attacksIn + 1
    elseif C.AVOID_KINDS[e.kind] then
      s.attacksIn = s.attacksIn + 1
      s.avoided = s.avoided + 1
    end
  end
  -- A creature you damaged died: its kill time runs from your first hit to its death.
  if e.kind == "death" then
    local tg = s.targets[C.TargetKey(e.targetKey, e.target) or ""]
      or s.targets[C.TargetKey(e.sourceKey, e.source) or ""]
    if tg and not tg.killed then tg.killed, tg.killTime = true, math.max(0, t - tg.first) end
  end
  s.last = now
end

function C.Add(f, e, now, pet, session)
  if type(e) ~= "table" then return end
  local amount = type(e.amount) == "number" and e.amount > 0 and e.amount or 0
  local mine = e.fromYou == true or (pet and e.fromYourPet == true)
  local atMe = e.toYou == true
  local t = type(e.time) == "number" and e.time or now     -- API 17: the line's own time
  addTo(f, e, amount, mine, atMe, t, now)
  if session then addTo(session, e, amount, mine, atMe, t, now) end
  if mine and C.DAMAGE_KINDS[e.kind] and not atMe then
    f.recent[#f.recent + 1] = { t = now, out = amount }
    if session then C.AddTimeline(session, t, amount, 0) end
  elseif e.fromYou == true and C.HEAL_KINDS[e.kind] then
    f.recent[#f.recent + 1] = { t = now, heal = amount }
  end
  if atMe and not e.fromYou and C.DAMAGE_KINDS[e.kind] then
    f.recent[#f.recent + 1] = { t = now, taken = amount }
    if session then C.AddTimeline(session, t, 0, amount) end
  end
end

-- Seconds of fighting in the session: finished fights, plus the current one while it runs.
function C.SessionDuration(s, current, now)
  local d = s.active
  if current and not current.ended then d = d + C.Duration(current, now) end
  return d
end

-- Drops "recent" entries older than the window.
function C.Prune(f, now)
  local r, n = f.recent, 0                -- in place: no new table each tick
  for i = 1, #r do
    if now - r[i].t < C.WINDOW then
      n = n + 1
      r[n] = r[i]
    end
  end
  for i = #r, n + 1, -1 do r[i] = nil end
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
local session = nil          -- every fight since start (or /toolbox combat reset)
local inCombat = false
local content = nil
local el = {}
local shownText = {}

local idleFight, idleEnded, idleStats = nil, nil, {}   -- what the HUD showed while no fight ran

local function scale() return prefs.scale or C.SCALE_DEFAULT end

local function save() T.Save("combat", prefs) end

local function statList() return prefs.stats or C.DEFAULT_STATS end

local function startFight()
  fight = C.NewFight(T.Now())
end

local function endFight()
  if fight and not fight.ended then
    fight.ended = fight.last > fight.start and fight.last or T.Now()
    if session then
      session.active = session.active + C.Duration(fight, fight.ended)
      session.fights = session.fights + 1
      C.Remember(session, fight)
    end
  end
end

function C.OnCombatMode(on)
  inCombat = on == true
  if inCombat then
    if not fight or fight.ended then startFight() end
  else
    endFight()
  end
end

-- /toolbox combat events [n]: print the fields of the next n combat events, to see what the game
-- really sends (API 17's rune, damageType, dot, overheal, time and keys; tables or game objects).
C.CAPTURE_DEFAULT, C.CAPTURE_MAX = 5, 20
local captureLeft = 0
function C.Capture(n)
  captureLeft = math.max(1, math.min(C.CAPTURE_MAX, math.floor(tonumber(n) or C.CAPTURE_DEFAULT)))
end
function C.CaptureLeft() return captureLeft end

function C.EventLine(e)
  local parts = { "(" .. tostring(e.raw or type(e)) .. ")" }
  for _, f in ipairs(T.EVENT_FIELDS) do
    local v = e[f]
    if v ~= nil and v ~= "" and v ~= false and v ~= 0 then parts[#parts + 1] = f .. "=" .. tostring(v) end
  end
  return table.concat(parts, " ")
end

function C.OnEvents(events, dropped)
  if type(events) ~= "table" then return end
  local now = T.Now()
  for _, e in ipairs(events) do
    if captureLeft > 0 then
      captureLeft = captureLeft - 1
      T.Print("Combat event: " .. C.EventLine(e))
    end
    local relevant = type(e) == "table" and (C.DAMAGE_KINDS[e.kind] or C.HEAL_KINDS[e.kind] or C.AVOID_KINDS[e.kind])
      and (e.fromYou or e.toYou or e.fromYourPet)
    if relevant then
      if not fight or fight.ended then startFight() end
      session = session or C.NewSession(now)
      C.Add(fight, e, now, prefs.pet ~= false, session)
    elseif type(e) == "table" and e.kind == "death" and fight then
      C.Add(fight, e, now, prefs.pet ~= false, session)   -- marks a target killed; starts nothing
    end
  end
  if fight and type(dropped) == "number" and dropped > 0 then fight.dropped = fight.dropped + dropped end
end

function C.Reset()
  fight, session = nil, nil
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
-- Rows are reused across ticks (no new tables twice a second).
local rowsOut, rowPool = {}, {}
local function putRow(i, id, label, value)
  local r = rowPool[i]
  if not r then
    r = {}
    rowPool[i] = r
  end
  r.id, r.label, r.value = id, label, value
  rowsOut[i] = r
end

function C.Rows(now)
  for k = #rowsOut, 1, -1 do rowsOut[k] = nil end
  local f = fight
  local recent, avg = { out = 0, taken = 0, healed = 0 }, { out = 0, taken = 0, healed = 0 }
  if f then recent, avg = C.Rates(f, now) end
  local timer = f and T.FormatDuration(C.Duration(f, now)) or "--"
  local status = not f and "" or (f.ended and " (ended)" or "")
  putRow(#rowsOut + 1, "fight", "Fight", timer .. status)
  putRow(#rowsOut + 1, "dps", "DPS", num(recent.out) .. "  avg " .. num(avg.out))
  putRow(#rowsOut + 1, "taken", "Taken /s", num(recent.taken) .. "  avg " .. num(avg.taken))
  putRow(#rowsOut + 1, "hps", "Healing /s", num(recent.healed) .. "  avg " .. num(avg.healed))
  putRow(#rowsOut + 1, "crit", "Crit", f and pct(C.CritPct(f)) or "--")
  putRow(#rowsOut + 1, "avoid", "Avoided", f and pct(C.AvoidPct(f)) or "--")
  for i, name in ipairs(statList()) do
    local v = ShroudGetStatValueByName(name)
    local readable = type(v) == "number" and v ~= InvalidStatResult and not (v == 0 and not ShroudIsStatVisible(name))
    putRow(#rowsOut + 1, "stat" .. i, name, readable and string.format("%g", v) or "n/a")
  end
  return rowsOut
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

-- Never a nil in a style table: the game's Lua passes a nil entry on to the UI, which
-- rejects it ("style color takes a number or a string" hid the whole strip in game).
local function labelStyle(m, width, align)
  local color = align == "left" and "@text" or "@text-bright"   -- names normal, values bright
  if background() == "Light" then color = C.DARK_TEXT end
  return { fontSize = m.font, height = m.line, minHeight = m.line, maxHeight = m.line, width = width,
           marginTop = 0, marginBottom = 0, paddingTop = 0, paddingBottom = 0,
           -- the labels' own side margins made each row ~8 px wider than its panel in game,
           -- pushing the values onto the right edge (/toolbox combat debug, 2026-09-27)
           marginLeft = 0, marginRight = 0, paddingLeft = 0, paddingRight = 0, textAlign = align,
           color = color }
end

local shownRows = 0
local pads = {}              -- top and bottom Light padding slabs: { light, group }

-- "#000000b3": black at the opacity setting, for the Dark panel.
function C.DarkColour()
  return string.format("#000000%02x", math.floor(opacity() / 100 * 255 + 0.5))
end

-- Shows, sizes and fades the panel for the current background and size.
local function applyBackground()
  if not content then return end
  local m = C.Metrics()
  local bg = background()
  local w = m.w + 2 * m.pad
  local dark, light = bg == "Dark", bg == "Light"
  content:SetStyle{ backgroundColor = dark and C.DarkColour() or "#00000000",
    paddingTop = dark and m.pad or 0, paddingBottom = dark and m.pad or 0 }
  local function slab(e, h)
    e:SetVisible(light)
    e:SetStyle{ width = w, height = h, opacity = opacity() / 100 }
  end
  for _, slot in ipairs(el) do
    slab(slot.light, m.line)
    -- the same inset both sides, so the right-aligned values sit off the panel's edge like the names
    slot.line:SetStyle{ marginTop = light and -m.line or 0, paddingLeft = m.pad, paddingRight = m.pad }
  end
  for _, p in ipairs(pads) do
    slab(p.light, m.pad)
    p.group:SetVisible(light)
  end
end

-- Nothing between the slabs: the theme's border and default margins drew a line between every
-- row in game (reported 2026-09-27), so the panel is flat.
local FLUSH = { marginTop = 0, marginBottom = 0, marginLeft = 0, marginRight = 0 }
local function flush(style)
  for k, v in pairs(FLUSH) do if style[k] == nil then style[k] = v end end
  return style
end

-- A Light panel slab (see the note on C.BACKGROUNDS).
local function slab(h)
  return UI.Column{ visible = false, style = flush{ backgroundColor = "@text", height = h, borderWidth = 0,
    borderRadius = 0 } }
end

function C.BuildContent()
  local m = C.Metrics()
  local groups = {}
  el, shownText, shownRows, pads = {}, {}, 0, {}
  for _, where in ipairs({ "top", "bottom" }) do
    local light = slab(m.pad)
    pads[#pads + 1] = { light = light,
      group = UI.Column{ id = "pad_" .. where, visible = false, style = flush{}, children = { light } } }
  end
  groups[1] = pads[1].group
  for i = 1, 6 + C.MAX_STATS do
    -- names in the normal text colour and values bright (the dim names were hard to read)
    local name = UI.Label{ text = "", class = "text", style = labelStyle(m, m.labelW, "left") }
    local value = UI.Label{ text = "", class = "bright", style = labelStyle(m, m.valueW, "right") }
    local light = slab(m.line)
    -- no id: ids repeated per row may not be allowed
    local line = UI.Row{ style = flush{}, children = { name, value },
      onHover = function(_, over) C.HudHover("row" .. i, over) end }
    local group = UI.Column{ visible = false, style = flush{}, children = { light, line } }
    groups[#groups + 1] = group
    el[i] = { row = group, name = name, value = value, light = light, line = line }
  end
  groups[#groups + 1] = pads[2].group
  content = UI.Column{ id = "combat_rows", style = flush{}, children = groups,
    onHover = function(_, over) C.HudHover("hud", over) end }
  C.Tick()
  applyBackground()
  return content
end

function C.ContentSize()
  local m = C.Metrics()
  return m.w + 2 * m.pad, math.max(1, shownRows) * m.line + 2 * m.pad
end

-- One chat line with the sizes the game laid out for the first row (for /toolbox combat debug):
-- what Metrics asked for next to what GetSize reports, to see where the space goes.
function C.LayoutDebug()
  local m = C.Metrics()
  local slot = el[1]
  local function size(e)
    if not e then return "?" end
    local ok, w, h = pcall(e.GetSize, e)
    if not ok then return "?" end
    return tostring(w) .. "x" .. tostring(h)
  end
  return string.format("layout: bg %s, pad %d, name %d + value %d = %d wide; "
    .. "laid out: slab %s, row %s, name %s, value %s",
    background(), m.pad, m.labelW, m.valueW, m.w + 2 * m.pad, size(slot and slot.light), size(slot and slot.line),
    size(slot and slot.name), size(slot and slot.value))
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
  C.Detail.Refresh()
  C.Detail.Track()
  if not content or not prefs.show then return end
  -- No fight running and the stats unchanged: the rows would come out the same, so skip building
  -- them (their strings are most of the HUD's garbage).
  if not fight or fight.ended then
    local same = idleFight == fight and idleEnded == (fight and fight.ended) and #idleStats == #statList()
    for i, name in ipairs(statList()) do
      local v = ShroudGetStatValueByName(name)
      if idleStats[i] ~= v then
        same = false
        idleStats[i] = v
      end
    end
    for k = #idleStats, #statList() + 1, -1 do idleStats[k] = nil end
    if same and next(shownText) then return end
    idleFight, idleEnded = fight, fight and fight.ended
  else
    idleFight = nil
  end
  local rows = C.Rows(now)
  for i, slot in ipairs(el) do
    local r = rows[i]
    if r then
      T.SetText(slot.name, r.label)
      T.SetText(slot.value, r.value)
    end
    T.SetVisible(slot.row, r ~= nil)
    shownText[i] = r ~= nil
  end
  if #rows ~= shownRows then
    shownRows = #rows
    applyBackground()
    T.Hud.Refresh()
  end
end

local mover = T.Hud.MoverFor("combat", C.HOME)
C.GetPosition, C.MoveTo, C.Nudge, C.ResetPosition = mover.Get, mover.MoveTo, mover.Nudge, mover.Reset

-- The current fight and the session (for the Combat Detailed window and tests).
function C.Current() return fight, session end

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
  C.Detail.Init()
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
  local found = nil
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
  T.Config.Sync()                      -- an open settings window shows the new list
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
  T.Config.Sync()                      -- an open settings window shows the new list
  return true, "Removed " .. name .. "."
end

-- ---------------------------------------------------------------------------
-- Combat Detailed window (/toolbox combat detail; pops up when the combat HUD is hovered)
-- ---------------------------------------------------------------------------
-- Damage by skill as bars (longest first), the last minute's damage done (up) and taken (down)
-- as columns, and healing with its overheal, for the current fight or the whole session. Built
-- once from fixed pools (the element-creation cap): refreshes only change text, bar values,
-- column heights and visibility. Uses API 17's per-skill fields; without them every line counts
-- as "(other)" or the skill the line names.
-- Saved var "combat_detail": { open = bool (pinned), x, y, scope = "fight"|"session", hover = bool }.

local CD = {}
C.Detail = CD
CD.WINDOW_ID = "toolbox_combat_detail"
CD.SKILL_ROWS = 8
CD.NAME_W, CD.BAR_W, CD.VALUE_W = 120, 110, 100
CD.COL_W, CD.COL_GAP = 7, 2           -- timeline columns (pixels)
CD.OUT_H, CD.IN_H = 44, 28            -- the two halves of the timeline chart
CD.OUT_COLOR, CD.IN_COLOR, CD.BAR_COLOR = "@green", "@red", "@gold"
CD.EMPTY = "#00000000"                -- an empty timeline column: transparent, still taking its room
CD.SCOPES = { { "fight", "This fight" }, { "session", "Session" } }
CD.OPEN_DELAY = 3                      -- seconds after start-up before a pinned window is rebuilt
CD.TARGET_ROWS = 6
CD.HISTORY_ROWS = 10
CD.TYPE_W, CD.TYPE_H = 330, 10         -- the damage-type bars
-- Damage types in the docs' order, and a colour for each: the theme has no colours for them, so
-- these are fixed (weapons in greys and browns, elements in their usual colours).
CD.TYPES = { "handToHand", "blade", "polearm", "bludgeon", "ranged", "shield", "life", "death", "sun", "lunar",
  "earth", "water", "fire", "air", "chaos", "curse", "disease", "poison", "transfer", "other" }
CD.TYPE_COLORS = { handToHand = "#b8a58c", blade = "#c0c6cc", polearm = "#9aa3ab", bludgeon = "#8c7b6b",
  ranged = "#a8b86c", shield = "#7f8c99", life = "#9be08a", death = "#8a6bb0", sun = "#f2cf4a", lunar = "#a7c7f2",
  earth = "#a0703c", water = "#3f7fd6", fire = "#e2562b", air = "#d8f0f5", chaos = "#d04fc3", curse = "#6b2f7a",
  disease = "#8a9a3a", poison = "#4fb04a", transfer = "#e07fa0", other = "#808080" }

-- "handToHand" -> "Hand to hand".
function CD.TypeName(dtype)
  local words = dtype:gsub("(%u)", function(c) return " " .. c:lower() end)
  return (words:gsub("^%l", string.upper))
end

local cdPrefs = { open = false, scope = "fight", hover = true }
local cdWin = nil
local cdEl = {}
local cdPopup = false

local function cdSave() T.Save("combat_detail", cdPrefs) end

local cdHover = T.Hover.New{
  name = "combat",
  enabled = function() return cdPrefs.hover ~= false end,
  trigger = function() return prefs.show == true end,
  popup = {
    IsShown = function() return CD.IsShown() end,
    IsPopup = function() return CD.IsPopup() end,
    ShowPopup = function() return CD.ShowPopup() end,
    HidePopup = function() return CD.HidePopup() end,
  },
}

-- The combat HUD reports hover here (its panel and rows).
function C.HudHover(key, over) cdHover:Report("t:" .. key, over) end

local function heading(text)
  return UI.Label{ text = text, class = "heading", style = { marginTop = 8 } }
end

local function scopeLabel(scope)
  for _, s in ipairs(CD.SCOPES) do if s[1] == scope then return s[2] end end
  return CD.SCOPES[1][2]
end

-- A bar row: name, bar, value (the skills and targets sections).
local function barRow()
  local name = UI.Label{ text = "", class = "text",
    style = { width = CD.NAME_W, whiteSpace = "nowrap", marginLeft = 0, marginRight = 4 } }
  local bar = UI.Bar{ value = 0, color = CD.BAR_COLOR, style = { width = CD.BAR_W, height = 8 } }
  local value = UI.Label{ text = "", class = "bright",
    style = { width = CD.VALUE_W, textAlign = "right", whiteSpace = "nowrap", marginLeft = 4, marginRight = 0 } }
  local row = UI.Row{ visible = false, style = { alignItems = "center", marginTop = 1 },
    children = { name, bar, value } }
  return { row = row, name = name, bar = bar, value = value }
end

-- A damage-type bar: one segment per type (hidden until it has a share), and its legend line.
local function typeBar(which)
  local segs, children = {}, {}
  for i, dtype in ipairs(CD.TYPES) do
    segs[dtype] = UI.Column{ visible = false,
      style = { width = 1, height = CD.TYPE_H, backgroundColor = CD.TYPE_COLORS[dtype] } }
    children[i] = segs[dtype]
  end
  local bar = UI.Row{ style = { width = CD.TYPE_W, height = CD.TYPE_H, marginTop = 2 }, children = children }
  local legend = UI.Label{ id = "cd_types_" .. which, text = "", class = "dim", style = { whiteSpace = "wrap" } }
  return bar, legend, segs
end

local function buildDetail()
  local skills = {}
  cdEl = { skills = {}, outCols = {}, inCols = {}, targets = {}, history = {} }
  for i = 1, CD.SKILL_ROWS do
    local name = UI.Label{ text = "", class = "text",
      style = { width = CD.NAME_W, whiteSpace = "nowrap", marginLeft = 0, marginRight = 4 } }
    local bar = UI.Bar{ value = 0, color = CD.BAR_COLOR, style = { width = CD.BAR_W, height = 8 } }
    local value = UI.Label{ text = "", class = "bright",
      style = { width = CD.VALUE_W, textAlign = "right", whiteSpace = "nowrap", marginLeft = 4, marginRight = 0 } }
    local row = UI.Row{ visible = false, style = { alignItems = "center", marginTop = 1 },
      children = { name, bar, value } }
    skills[i] = row
    cdEl.skills[i] = { row = row, name = name, bar = bar, value = value }
  end
  -- One element per timeline column (the element-creation cap): an "up" block pushed down onto
  -- the baseline by its top margin, and a "down" block hanging from it. Empty columns are
  -- transparent 1 px blocks, not hidden (hidden elements take no room; the rest would slide).
  local n = math.floor(C.TIMELINE / C.SLICE)
  local outRow, inRow = {}, {}
  cdEl.shown = { up = {}, down = {} }
  for i = 1, n do
    local gap = i > 1 and CD.COL_GAP or 0
    outRow[i] = UI.Column{ style = { width = CD.COL_W, marginLeft = gap, height = 1, marginTop = CD.OUT_H - 1,
      backgroundColor = CD.EMPTY } }
    inRow[i] = UI.Column{ style = { width = CD.COL_W, marginLeft = gap, height = 1, backgroundColor = CD.EMPTY } }
    cdEl.outCols[i], cdEl.inCols[i] = outRow[i], inRow[i]
  end
  local choices = {}
  for i, s in ipairs(CD.SCOPES) do choices[i] = s[2] end
  local targetRows = {}
  for i = 1, CD.TARGET_ROWS do
    cdEl.targets[i] = barRow()
    targetRows[i] = cdEl.targets[i].row
  end
  local historyRows = {}
  for i = 1, CD.HISTORY_ROWS do
    cdEl.history[i] = barRow()
    historyRows[i] = cdEl.history[i].row
  end
  local outTypes, outLegend, outSegs = typeBar("out")
  local inTypes, inLegend, inSegs = typeBar("taken")
  cdEl.typeSegs = { out = outSegs, taken = inSegs }
  cdWin = UI.Window{
    id = CD.WINDOW_ID, title = "Combat Detailed",
    width = 380, height = 440, minWidth = 260, minHeight = 160,
    x = cdPrefs.x or T.Window.DEFAULT_X, y = cdPrefs.y or T.Window.DEFAULT_Y,
    escCloses = true,
    onClose = function()
      cdPrefs.open, cdPopup = false, false
      cdSave()
      cdHover:Clear("p:")
      T.Config.Sync()
    end,
    onHover = function(_, over) cdHover:Report("p:window", over) end,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = { UI.Scroll{ style = { flexGrow = 1 }, onHover = function(_, over) cdHover:Report("p:body", over) end,
      children = { UI.Column{ style = { paddingLeft = 10, paddingRight = 10 }, children = {
        UI.Row{ style = { alignItems = "center" }, children = {
          UI.Label{ id = "cd_summary", text = "", class = "text", style = { flexGrow = 1, whiteSpace = "wrap" } },
          UI.Dropdown{ id = "cd_scope", choices = choices, value = scopeLabel(cdPrefs.scope),
            tooltip = "This fight, or every fight since you logged in (or reset)",
            onChange = function(_, label) CD.OnScope(label) end },
        } },
        heading("Damage by skill"),
        UI.Column{ children = skills },
        UI.Label{ id = "cd_noskills", text = "No damage yet.", class = "dim", visible = false },
        heading("Last minute: damage done (up) and taken (down), per second"),
        UI.Row{ style = { marginTop = 4, height = CD.OUT_H, alignItems = "start" }, children = outRow },
        UI.Row{ style = { height = 1, width = n * (CD.COL_W + CD.COL_GAP), backgroundColor = "@text" } },
        UI.Row{ style = { height = CD.IN_H, alignItems = "start" }, children = inRow },
        UI.Label{ id = "cd_peak", text = "", class = "dim", style = { marginTop = 2 } },
        heading("Healing"),
        UI.Label{ id = "cd_heal", text = "", class = "text", style = { whiteSpace = "wrap" } },
        heading("Targets"),
        UI.Column{ children = targetRows },
        UI.Label{ id = "cd_notargets", text = "Nothing hit yet.", class = "dim", visible = false },
        heading("Damage types"),
        UI.Label{ text = "Done", class = "text", style = { marginTop = 2 } },
        outTypes, outLegend,
        UI.Label{ text = "Taken", class = "text", style = { marginTop = 4 } },
        inTypes, inLegend,
        heading("Recent fights (newest first)"),
        UI.Column{ children = historyRows },
        UI.Label{ id = "cd_nohistory", text = "No finished fights yet this session.", class = "dim", visible = false },
      } } } } },
  }
  for _, id in ipairs({ "cd_summary", "cd_scope", "cd_noskills", "cd_peak", "cd_heal", "cd_notargets",
                        "cd_types_out", "cd_types_taken", "cd_nohistory" }) do
    cdEl[id] = cdWin:Find(id)
  end
end

-- Builds the window, reporting a failure instead of raising (about 230 elements: past the game's
-- creation cap it raises "elements are being created too fast"; 2026-09-28 at start-up).
local function tryBuild()
  local ok, err = pcall(buildDetail)
  if ok then return true end
  cdWin = nil
  T.Print("Couldn't build Combat Detailed yet (" .. tostring(err) .. "); try again in a moment.")
  return false
end

local function short(n)
  n = n or 0
  if n >= 1000000 then return string.format("%.1fm", n / 1000000) end
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return T.FormatNumber(n)
end
CD.Short = short

function CD.IsShown() return cdWin ~= nil and cdWin:IsShown() end
function CD.IsOpen() return cdPrefs.open == true end
function CD.IsPopup() return cdPopup and CD.IsShown() end

-- The stats the window shows now (fight or session) and their fighting time in seconds.
local function scoped(now)
  if cdPrefs.scope == "session" then
    if not session then return nil, 0 end
    return session, C.SessionDuration(session, fight, now)
  end
  if not fight then return nil, 0 end
  return fight, C.Duration(fight, now)
end

-- A bar row's contents: text, bar, value and tooltip, the tooltip rebuilt only when `sig` (the
-- numbers behind it) changes.
local function fillRow(slot, name, bar, value, sig, tipFn)
  T.SetText(slot.name, name)
  T.SetValue(slot.bar, bar)
  T.SetText(slot.value, value)
  if slot.sig ~= sig then
    slot.sig = sig
    local tip = tipFn()
    T.SetTooltip(slot.name, tip)
    T.SetTooltip(slot.value, tip)
  end
  T.SetVisible(slot.row, true)
end

local lastRefresh = -math.huge
CD.REFRESH = 1                        -- seconds between refreshes while shown

-- `force`: now, not on the 1 s pace (opened, scope changed).
function CD.Refresh(force)
  if not CD.IsShown() then return end
  local now = T.Now()
  if not force and now - lastRefresh < CD.REFRESH then return end
  lastRefresh = now
  local s, dur = scoped(now)
  local span = math.max(1, dur)
  if not s then
    T.SetText(cdEl.cd_summary, cdPrefs.scope == "session" and "No fights yet this session." or "No fight yet.")
  else
    T.SetText(cdEl.cd_summary, string.format("%s: %s. Damage %s (%s/s), taken %s (%s/s)%s.",
      scopeLabel(cdPrefs.scope), T.FormatDuration(dur), short(s.out), short(s.out / span), short(s.taken),
      short(s.taken / span), (s.fights and s.fights > 0) and (", " .. s.fights .. " fights done") or ""))
  end
  local top = s and C.TopRunes(s, CD.SKILL_ROWS) or {}
  for i, slot in ipairs(cdEl.skills) do
    local r = top[i]
    if r then
      fillRow(slot, r.name, top[1].dmg > 0 and r.dmg / top[1].dmg or 0,
        short(r.dmg) .. "  " .. math.floor(r.share * 100 + 0.5) .. "%",
        r.name .. r.dmg .. ":" .. r.hits .. ":" .. r.crits .. ":" .. r.dots, function()
          return string.format("%s: %s damage (%d%%)\n%d hits, %d critical (%d%%), %d over-time ticks\n"
            .. "average hit %s", r.name, T.FormatNumber(r.dmg), math.floor(r.share * 100 + 0.5), r.hits, r.crits,
            r.hits > 0 and math.floor(100 * r.crits / r.hits + 0.5) or 0, r.dots,
            T.FormatNumber(r.hits > 0 and r.dmg / r.hits or 0))
        end)
    else
      T.SetVisible(slot.row, false)
    end
  end
  T.SetVisible(cdEl.cd_noskills, #top == 0)
  local tl = session and C.Timeline(session, now) or {}
  local peakOut, peakIn = 0, 0
  for _, x in ipairs(tl) do
    peakOut, peakIn = math.max(peakOut, x.out), math.max(peakIn, x.taken)
  end
  for i = 1, #cdEl.outCols do
    local x = tl[i]
    local hu = (x and peakOut > 0) and math.floor(CD.OUT_H * x.out / peakOut + 0.5) or 0
    local hd = (x and peakIn > 0) and math.floor(CD.IN_H * x.taken / peakIn + 0.5) or 0
    if hu ~= cdEl.shown.up[i] then
      cdEl.shown.up[i] = hu
      cdEl.outCols[i]:SetStyle(hu > 0 and { height = hu, marginTop = CD.OUT_H - hu, backgroundColor = CD.OUT_COLOR }
        or { height = 1, marginTop = CD.OUT_H - 1, backgroundColor = CD.EMPTY })
    end
    if hd ~= cdEl.shown.down[i] then
      cdEl.shown.down[i] = hd
      cdEl.inCols[i]:SetStyle(hd > 0 and { height = hd, backgroundColor = CD.IN_COLOR }
        or { height = 1, backgroundColor = CD.EMPTY })
    end
  end
  T.SetText(cdEl.cd_peak, "Peaks: " .. short(peakOut) .. "/s done, " .. short(peakIn) .. "/s taken ("
    .. C.SLICE .. " s columns, newest on the right)")
  local tops = s and C.TopTargets(s, CD.TARGET_ROWS) or {}
  for i, slot in ipairs(cdEl.targets) do
    local tg = tops[i]
    if tg then
      fillRow(slot, tg.name, tops[1].dmg > 0 and tg.dmg / tops[1].dmg or 0,
        short(tg.dmg) .. (tg.killed and ("  killed " .. T.FormatDuration(tg.secs)) or ""),
        tg.name .. tg.dmg .. ":" .. tg.hits .. ":" .. tg.secs .. tostring(tg.killed), function()
          return string.format("%s: %s damage in %d hits over %s (%s/s)%s", tg.name, T.FormatNumber(tg.dmg),
            tg.hits, T.FormatDuration(tg.secs), short(tg.dmg / math.max(1, tg.secs)),
            tg.killed and "; killed" or "; not killed (yet)")
        end)
    else
      T.SetVisible(slot.row, false)
    end
  end
  T.SetVisible(cdEl.cd_notargets, #tops == 0)
  for _, which in ipairs({ "out", "taken" }) do
    local list = s and C.Types(s, which) or {}
    local widths, parts, used = {}, {}, 0
    for i, x in ipairs(list) do
      local key = cdEl.typeSegs[which][x.type] and x.type or "other"
      local w = i == #list and (CD.TYPE_W - used) or math.floor(CD.TYPE_W * x.share + 0.5)
      w = math.max(0, math.min(CD.TYPE_W - used, w))
      if w > 0 then
        local seg = cdEl.typeSegs[which][key]
        widths[key] = w
        T.SetStyle(seg, { width = w })
        T.SetTooltip(seg, CD.TypeName(x.type) .. ": " .. T.FormatNumber(x.amount) .. " ("
          .. math.floor(x.share * 100 + 0.5) .. "%)")
        used = used + w
      end
      if i <= 4 then parts[#parts + 1] = CD.TypeName(x.type) .. " " .. math.floor(x.share * 100 + 0.5) .. "%" end
    end
    for key, seg in pairs(cdEl.typeSegs[which]) do T.SetVisible(seg, widths[key] ~= nil) end
    T.SetText(cdEl["cd_types_" .. which], #parts > 0 and table.concat(parts, "  ·  ") or "None yet.")
  end
  local hist = session and session.history or {}
  local best = 0
  for _, h in ipairs(hist) do best = math.max(best, h.dps) end
  for i, slot in ipairs(cdEl.history) do
    local h = hist[i]
    if h then
      fillRow(slot, T.FormatDuration(h.secs) .. (h.top ~= "" and ("  " .. h.top) or ""),
        best > 0 and h.dps / best or 0, "DPS " .. short(h.dps),
        h.secs .. ":" .. h.out .. ":" .. h.taken .. ":" .. h.healed .. ":" .. h.kills .. h.top, function()
          return string.format("%s fight: %s damage (%s/s), %s taken, %s healed; %d killed; most damage: %s",
            T.FormatDuration(h.secs), T.FormatNumber(h.out), short(h.dps), T.FormatNumber(h.taken),
            T.FormatNumber(h.healed), h.kills, h.top ~= "" and h.top or "none")
        end)
    else
      T.SetVisible(slot.row, false)
    end
  end
  T.SetVisible(cdEl.cd_nohistory, #hist == 0)
  if s and s.healed + s.overheal > 0 then
    local over = C.OverhealPct(s)
    T.SetText(cdEl.cd_heal, string.format("%s healed (%s/s); %s wasted as overheal (%d%%).", short(s.healed),
      short(s.healed / span), short(s.overheal), math.floor((over or 0) + 0.5)))
  else
    T.SetText(cdEl.cd_heal, "No healing yet.")
  end
end

function CD.OnScope(label)
  for _, s in ipairs(CD.SCOPES) do
    if s[2] == label then CD.SetScope(s[1]) end
  end
end

function CD.SetScope(scope)
  if scope ~= "fight" and scope ~= "session" then return false end
  cdPrefs.scope = scope
  cdSave()
  if cdEl.cd_scope then cdEl.cd_scope:SetValue(scopeLabel(scope)) end
  CD.Refresh(true)
  return true
end

function CD.GetScope() return cdPrefs.scope end

-- Pinned open or closed by the player. Returns true when it ends up as asked.
function CD.SetOpen(open)
  if not cdWin and not tryBuild() then return false end
  local ok = true
  if not open then
    cdWin:Hide()
    cdPrefs.open, cdPopup = false, false
  elseif cdWin:IsShown() then
    cdPrefs.open, cdPopup = true, false
  elseif cdWin:Show() then
    cdPrefs.open, cdPopup = true, false
    CD.Refresh(true)
  else
    T.Print("The Combat Detailed window can't open right now; try again in a few seconds.")
    ok = false
  end
  cdSave()
  T.Config.Sync()
  return ok
end

function CD.Toggle() return CD.SetOpen(not CD.IsOpen()) end

function CD.ShowPopup()
  if not cdWin and not tryBuild() then return false end
  if cdWin:IsShown() or not cdWin:Show() then return false end
  cdPopup = true
  CD.Refresh(true)
  return true
end

function CD.HidePopup()
  if cdPopup and cdWin then cdWin:Hide() end
  cdPopup = false
end

function CD.GetHover() return cdPrefs.hover ~= false end

function CD.SetHover(on)
  cdPrefs.hover = on == true
  cdSave()
  if not cdPrefs.hover then cdHover:Cancel() end
  T.Config.Sync()
end

function CD.Track()
  if cdWin and T.Window.TrackPosition(cdWin, cdPrefs) then cdSave() end
end

function CD.Init()
  local saved = T.Load("combat_detail")
  cdPrefs = { open = false, scope = "fight", hover = true }
  if type(saved) == "table" then
    cdPrefs.open = saved.open == true
    cdPrefs.hover = saved.hover ~= false
    if saved.scope == "session" then cdPrefs.scope = "session" end
    if type(saved.x) == "number" and type(saved.y) == "number" then cdPrefs.x, cdPrefs.y = saved.x, saved.y end
  end
  cdWin, cdPopup = nil, false
  if cdPrefs.open then
    -- Pinned: reopen a few seconds after start-up, once the rest has been built (the creation cap).
    ShroudRegisterPeriodic("toolbox_combat_detail_open", function()
      if not cdWin and not tryBuild() then return end
      if not cdWin:Show() then T.Print("Combat Detailed could not reopen yet; use /toolbox combat detail.") end
      CD.Refresh(true)
    end, CD.OPEN_DELAY, false)
  end
end
