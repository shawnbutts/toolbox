-- Toolbox: daily.lua
-- Daily stats (/toolbox daily): gold picked up, kills, and adventurer / producer XP
-- gained today. Resets at local midnight (see Toolbox.Today). Kept per character in
-- the saved var "daily", so it survives reloads and relogs on the same day.
--
-- day = {
--   v     = 1,
--   key   = "local:2026-09-27",   -- Toolbox.Today() key the counts belong to
--   gold  = n, kills = n, a = n, p = n,   -- today's counts
--   items = { [name] = n },  -- items gained today, by name (at most D.MAX_KINDS names)
--   dropped = n,             -- item kinds the game didn't itemise (past 20 in one call)
--   last  = { gold = n|nil, a = n|nil, p = n|nil },  -- last readings, to diff against
--   -- crafting and gathering (API 18 result events; added 2026-09-29, filled in for older days):
--   crafted  = { [name] = n },   -- items gained while a crafting window was open (taken off a station)
--   gathered = { [name] = n },   -- what harvested nodes' loot windows held
--   recipes  = { [recipe] = { n = crafts, exc = n, fail = n } },   -- "Recipe: " removed from the name
--   craft    = { n = crafts, exc = n, fail = n, salvaged = n, xp = n },
--   gather   = { nodes = n, failed = n, xp = n },
-- }
-- The loot list (Today Detailed, "Looted") is `items` minus `crafted` and `gathered`, per name, unless
-- the player includes them. In game (2026-09-29) a craft result's `item` is the recipe's name and
-- `crafted` counts crafts, not items made, so what was made is counted as it reaches the bags.

local T = Toolbox
local D = {}
Toolbox.Daily = D

local UI = Shroud.UI
local WINDOW_ID = "toolbox_daily"
local GUTTER = 8
D.FORMAT = 1
D.MAX_KINDS = 250                 -- distinct item names kept per day (saved-var size)
D.OTHER = "(other items)"         -- where kinds past D.MAX_KINDS are counted

-- ---------------------------------------------------------------------------
-- Model (plain data, no API calls)
-- ---------------------------------------------------------------------------

D.MAX_RECIPES = 100               -- recipes kept per day

function D.New(key)
  return D.Upgrade({ v = D.FORMAT, key = key, gold = 0, kills = 0, a = 0, p = 0, items = {}, dropped = 0,
                     last = {} })
end

local function isCount(x) return type(x) == "number" and x == x and x >= 0 end

function D.IsValid(d)
  if type(d) ~= "table" or d.v ~= D.FORMAT or type(d.key) ~= "string" or type(d.last) ~= "table" then
    return false
  end
  for _, k in ipairs({ "gold", "kills", "a", "p" }) do
    if not isCount(d[k]) then return false end
  end
  -- items / dropped arrived after v1 shipped: absent is fine (D.Upgrade fills them in).
  if d.items ~= nil then
    if type(d.items) ~= "table" then return false end
    for name, n in pairs(d.items) do
      if type(name) ~= "string" or not isCount(n) then return false end
    end
  end
  if d.dropped ~= nil and not isCount(d.dropped) then return false end
  return true
end

-- A name -> count table from a save, keeping only valid entries (crafting fields: a bad entry is
-- dropped, not the whole day).
local function counts(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for name, n in pairs(t) do
    if type(name) == "string" and isCount(n) then out[name] = n end
  end
  return out
end

local function totals(t, keys)
  local out = {}
  for _, k in ipairs(keys) do
    local v = type(t) == "table" and t[k] or nil
    out[k] = isCount(v) and v or 0
  end
  return out
end

-- Fills in fields added after the first v1 saves (and cleans the crafting ones).
function D.Upgrade(d)
  d.items = d.items or {}
  d.dropped = d.dropped or 0
  d.crafted, d.gathered = counts(d.crafted), counts(d.gathered)
  local recipes = {}
  if type(d.recipes) == "table" then
    for name, r in pairs(d.recipes) do
      if type(name) == "string" and type(r) == "table" then recipes[name] = totals(r, { "n", "exc", "fail" }) end
    end
  end
  d.recipes = recipes
  d.craft = totals(d.craft, { "n", "exc", "fail", "salvaged", "xp" })
  d.gather = totals(d.gather, { "nodes", "failed", "xp" })
  return d
end

-- Adds `qty` of `name` to a name -> count table, capped at D.MAX_KINDS names (the rest go to D.OTHER).
local function addCount(t, name, qty)
  if t[name] == nil then
    local kinds = 0
    for _ in pairs(t) do kinds = kinds + 1 end
    if kinds >= D.MAX_KINDS then name = D.OTHER end
  end
  t[name] = (t[name] or 0) + qty
end

-- A recipe's name as a row shows it: "Recipe: Crimson Pine Board" -> "Crimson Pine Board". Nothing
-- more is guessed (item names can have brackets too: "Hopper (Bait)").
function D.RecipeName(name)
  if type(name) ~= "string" then return nil end
  if name:sub(1, 8) == "Recipe: " then name = name:sub(9) end
  return name ~= "" and name or nil
end

local function num(r, k)
  local v = T.Field(r, k)
  return isCount(v) and v or 0
end

-- Adds one ShroudOnCraftResults batch (results may be game objects). Returns true when counted.
function D.AddCraftResults(d, results)
  local changed = false
  for _, r in ipairs(T.List(results)) do
    local kind = T.Field(r, "kind")
    if kind == "salvage" then
      d.craft.salvaged = d.craft.salvaged + math.max(1, num(r, "quantity"))   -- returns counted as they arrive
      d.craft.xp = d.craft.xp + num(r, "experience")
      changed = true
    elseif kind == "craft" or kind == "refine" then
      local made, exc, fail = num(r, "crafted"), num(r, "exceptional"), num(r, "failed")
      d.craft.n, d.craft.exc, d.craft.fail = d.craft.n + made, d.craft.exc + exc, d.craft.fail + fail
      d.craft.xp = d.craft.xp + num(r, "experience")
      local name = D.RecipeName(T.Field(r, "recipeName")) or D.RecipeName(T.Field(r, "item"))
      if name then
        local rec = d.recipes[name]
        if not rec then
          local n = 0
          for _ in pairs(d.recipes) do n = n + 1 end
          if n < D.MAX_RECIPES then
            rec = { n = 0, exc = 0, fail = 0 }
            d.recipes[name] = rec
          end
        end
        if rec then rec.n, rec.exc, rec.fail = rec.n + made, rec.exc + exc, rec.fail + fail end
      end
      changed = true
    end
  end
  return changed
end

-- Adds one ShroudOnGatherResults batch. Returns true when counted.
function D.AddGatherResults(d, results)
  local changed = false
  for _, r in ipairs(T.List(results)) do
    d.gather.nodes = d.gather.nodes + 1
    if T.Field(r, "failed") == true then d.gather.failed = d.gather.failed + 1 end
    d.gather.xp = d.gather.xp + num(r, "experience")
    for _, it in ipairs(T.List(T.Field(r, "items"))) do
      local name, qty = T.Field(it, "name"), T.Field(it, "quantity")
      if type(name) == "string" and name ~= "" and isCount(qty) and qty > 0 then addCount(d.gathered, name, qty) end
    end
    changed = true
  end
  return changed
end

-- The looted count of `name`: gained, less what was made or gathered (never below 0).
function D.Looted(d, name)
  local n = (d.items[name] or 0) - (d.crafted[name] or 0) - (d.gathered[name] or 0)
  return n > 0 and n or 0
end

-- Adds one ShroudOnItemsGained batch. `atStation`: a crafting window is open, so the items came off
-- a station (made, or salvage returns): also counted as crafted. Returns true when anything was counted.
function D.AddItems(d, items, dropped, atStation)
  local changed = false
  for _, item in ipairs(type(items) == "table" and items or {}) do
    local name, qty = type(item) == "table" and item.name, type(item) == "table" and item.quantity
    if type(name) == "string" and name ~= "" and isCount(qty) and qty > 0 then
      addCount(d.items, name, qty)
      if atStation then addCount(d.crafted, name, qty) end
      changed = true
    end
  end
  if isCount(dropped) and dropped > 0 then
    d.dropped = d.dropped + dropped
    changed = true
  end
  return changed
end

-- Item names sorted by count (highest first), then name.
function D.SortedItems(d)
  local names = {}
  for name in pairs(d.items) do names[#names + 1] = name end
  table.sort(names, function(x, y)
    if d.items[x] ~= d.items[y] then return d.items[x] > d.items[y] end
    return x < y
  end)
  return names
end

-- Starts a new day when the key changed. Keeps the last readings so gains
-- that straddle midnight land on the new day. Returns true when it rolled over.
function D.Roll(d, key)
  if key == nil or d.key == key then return false end
  d.key, d.gold, d.kills, d.a, d.p = key, 0, 0, 0, 0
  d.items, d.dropped, d.la, d.lp = {}, 0, 0, 0
  d.crafted, d.gathered, d.recipes, d.craft, d.gather = {}, {}, {}, nil, nil
  D.Upgrade(d)                       -- zeroed craft and gather totals
  return true
end

-- XP totals: only increases count. A lower reading is a bad read (a 0 while a scene loads)
-- until Toolbox.XP.ConfirmDrop believes it (it held for a few seconds: XP lost, e.g. on death);
-- then counting carries on from it. Before 2026-09-28 a real loss stopped the count until the
-- total climbed back.
local pending = {}     -- per track: since when a lower total has held (not saved)

local function observeTrack(d, key, v, now)
  local last = d.last[key]
  if last == nil or v > last then
    if last ~= nil then d[key] = d[key] + (v - last) end
    d.last[key], pending[key] = v, nil
    return true
  end
  if v == last then
    pending[key] = nil
    return false
  end
  if T.XP.ConfirmDrop(pending, key, v, now) then
    d["l" .. key] = (d["l" .. key] or 0) + (last - v)   -- a loss (shown only with the net option)
    d.last[key] = v                  -- count on from here, nothing subtracted
    return true
  end
  return false
end

-- Today's XP on a track as shown: gains, or with the net option (Toolbox.Window.GetNet) gains
-- minus losses (d.la / d.lp), which can be negative.
function D.XPToday(d, key)
  local gained = d[key] or 0
  if T.Window.GetNet() then return gained - (d["l" .. key] or 0) end
  return gained
end

function D.ObserveXP(d, adv, prod, now)
  now = now or T.Now()
  local a = observeTrack(d, "a", adv, now)
  local p = observeTrack(d, "p", prod, now)
  return a or p
end

-- Gold: every increase counts (the API has no "picked up" event, so vendor sales,
-- trades and mail count too). Spending lowers the baseline without counting. A read
-- of exactly 0 from a positive balance is ignored as a bad read.
function D.ObserveGold(d, gold)
  local last = d.last.gold
  if last == nil then
    d.last.gold = gold
    return true
  end
  if gold == last or (gold == 0 and last > 0) then return false end
  if gold > last then d.gold = d.gold + (gold - last) end
  d.last.gold = gold
  return true
end

-- Sets the baselines to the current readings, so changes while the add-on wasn't
-- running (gold from a player vendor while logged out) don't count.
function D.Rebase(d, adv, prod, gold)
  d.last.a, d.last.p = adv, prod
  pending = {}
  d.last.gold = (type(gold) == "number" and gold >= 0) and gold or nil
end

-- A kill is a combat "death" line dealt by you or your pet (and not about you or it).
function D.IsKill(e)
  return type(e) == "table" and e.kind == "death"
    and (e.fromYou == true or e.fromYourPet == true)
    and e.toYou ~= true and e.toYourPet ~= true
end

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------

D.day = nil
D.unsaved = false
D.source = nil      -- "local" | "utc" | nil (from Toolbox.Today)
D.label = nil       -- date shown in the window

local function today()
  local key, label, source = T.Today()
  D.source, D.label = source, label
  return key
end

function D.Load()
  local saved = T.Load("daily")
  local key = today()
  if D.IsValid(saved) then
    D.day = D.Upgrade(saved)
  else
    D.day = D.New(key or "none")
  end
  if D.Roll(D.day, key) then D.unsaved = true end
end

function D.Save()
  if not D.day then return end
  T.Save("daily", D.day)
  D.unsaved = false
  T.unflushed = true          -- written to disk with the session's periodic flush
end

-- Called with fresh totals by Toolbox.Sample (every tick and on XP gain).
function D.ObserveTotals(adv, prod)
  if not D.day then return end
  if D.ObserveXP(D.day, adv, prod) then D.unsaved = true end
end

-- Once a tick, from Toolbox.Tick: day rollover, gold, and storing changes.
function D.Tick(hasCharacter)
  if not D.day then return end
  if D.Roll(D.day, today()) then D.unsaved = true end
  if hasCharacter then
    local gold = ShroudPlayerGold
    if type(gold) == "number" and gold >= 0 and D.ObserveGold(D.day, gold) then D.unsaved = true end
  end
  if D.unsaved then D.Save() end
end

-- A new login or character (not a reload), with that character's current totals:
-- load its day and start counting from now.
function D.OnLogin(adv, prod)
  D.Load()
  D.Rebase(D.day, adv, prod, ShroudPlayerGold)
  D.unsaved = true
end

-- Bumped whenever today's items change, so Today Detailed redraws its list only then.
D.itemsVersion = 0

-- A crafting window is open (ShroudOnCraftingStateChanged; read at start where the client has it).
D.stationOpen = false

-- Whether this client reports crafting and gathering results (API 18). The result callbacks can't be
-- probed, so this goes by the crafting getter the same group added.
function D.HasResults() return type(ShroudGetCraftingState) == "function" end

local function changed()
  D.unsaved = true
  D.itemsVersion = D.itemsVersion + 1
end

function D.OnItems(items, dropped)
  if D.day and D.AddItems(D.day, items, dropped, D.stationOpen) then changed() end
end

function D.OnCraftResults(results)
  if D.day and D.AddCraftResults(D.day, results) then changed() end
end

function D.OnGatherResults(results)
  if D.day and D.AddGatherResults(D.day, results) then changed() end
end

function D.OnCraftingState(state)
  D.stationOpen = T.Field(state, "open") == true
end

-- At start: whether a crafting window is already open (a /lua reload at a station).
function D.ReadCraftingState()
  if not D.HasResults() then return end
  local ok, state = pcall(ShroudGetCraftingState)
  if ok then D.OnCraftingState(state) end
end

function D.OnCombat(events)
  if not D.day or type(events) ~= "table" then return end
  for _, e in ipairs(events) do
    if D.IsKill(e) then
      D.day.kills = D.day.kills + 1
      D.unsaved = true
    end
  end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local win = nil
local el = {}
local prefs = { open = false, hover = true, hud = false }
local strip = nil                     -- the HUD strip form (Toolbox.Hud.TextStrip; see compact.lua)
D.HOME = { 40, 200 }

-- Hover pop-up of the Today Detailed window (Toolbox.DailyDetail).
local hover = T.Hover.New{
  name = "daily",
  enabled = function() return prefs.hover end,
  trigger = function() return D.IsShown() end,
  popup = {
    IsShown = function() return T.DailyDetail.IsShown() end,
    IsPopup = function() return T.DailyDetail.IsPopup() end,
    ShowPopup = function() return T.DailyDetail.ShowPopup() end,
    HidePopup = function() return T.DailyDetail.HidePopup() end,
  },
}

local LINES = {
  { id = "gold", label = "Gold picked up",
    tooltip = "Every increase in your gold today: loot, but also vendor sales, trades and mail" },
  { id = "kills", label = "Kills", tooltip = "Kills by you or your pet today, from combat chat" },
  { id = "adv", label = "Adventurer XP" },
  { id = "prod", label = "Producer XP" },
}
local TEXT_IDS = { "date" }
for _, line in ipairs(LINES) do
  TEXT_IDS[#TEXT_IDS + 1] = line.id .. "_label"
  TEXT_IDS[#TEXT_IDS + 1] = line.id
end

local function row(spec)
  local W = T.Window
  return UI.Row{ style = { alignItems = "center" }, tooltip = spec.tooltip or spec.label, children = {
    UI.Label{ id = spec.id .. "_label", text = spec.label, class = "text", style = W.TextStyle{ flexGrow = 1 } },
    UI.Label{ id = spec.id, text = "0", class = "text", style = W.TextStyle{ textAlign = "right" } },
  } }
end

local function build()
  local rows = { UI.Label{ id = "date", text = "", class = "title", style = T.Window.TextStyle() } }
  for _, spec in ipairs(LINES) do rows[#rows + 1] = row(spec) end
  win = UI.Window{
    id = WINDOW_ID, title = "Today",
    width = 200, height = 130, minWidth = 150, minHeight = 50,
    x = prefs.x or T.Window.DEFAULT_X, y = prefs.y or T.Window.DEFAULT_Y,   -- never nil in a spec
    escCloses = true,
    onClose = function()
      prefs.open = false
      D.SavePrefs()
      hover:Clear("t:")
      T.Config.Sync()
    end,
    onHover = function(_, over) hover:Report("t:window", over) end,
    style = { paddingTop = 4, paddingBottom = 4 },
    children = {
      UI.Scroll{ id = "body", style = { flexGrow = 1 },
        onHover = function(_, over) hover:Report("t:body", over) end, children = {
        UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = rows },
      } },
    },
  }
  el = {}
  for _, id in ipairs(TEXT_IDS) do el[id] = win:Find(id) end
end

function D.SavePrefs()
  T.Save("daily_window", prefs)
end

function D.IsShown()
  if prefs.hud then return prefs.open == true and strip ~= nil end
  return win ~= nil and win:IsShown()
end

-- The labels of the form in use (window or HUD strip).
local function active()
  if prefs.hud then return strip and strip.el or {} end
  return el
end

-- Builds the window (after Toolbox.Window.Init, whose text settings it uses).
-- The data is loaded earlier, by D.Load from ShroudOnStart.
function D.InitWindow()
  local saved = T.Load("daily_window")
  prefs = { open = false, hover = true, hud = false }
  if type(saved) == "table" then
    prefs.open = saved.open == true
    prefs.hover = saved.hover ~= false
    prefs.hud = saved.hud == true
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
    if type(saved.hx) == "number" and type(saved.hy) == "number" then prefs.hx, prefs.hy = saved.hx, saved.hy end
  end
  strip = T.Hud.TextStrip{ key = "daily", FRAME_ID = "toolbox_daily_hud", HOME = D.HOME, titleId = "date",
    lines = LINES, hover = hover, prefs = prefs, save = D.SavePrefs,
    isShown = function() return prefs.hud and prefs.open == true end }
  T.Hud.Register("daily", strip)       -- built by Toolbox.Hud.Init, after this
  build()
  if prefs.open and not prefs.hud and not win:Show() then
    T.Print("Daily stats window could not reopen yet; use /toolbox daily.")
  end
  D.Refresh()
end

function D.SetOpen(open)
  if not win then build() end
  local ok = true
  if not open then
    win:Hide()
    prefs.open = false
    hover:Clear("t:")
  elseif prefs.hud then
    prefs.open = true
  elseif win:IsShown() or win:Show() then
    prefs.open = true
  else
    T.Print("The daily stats window can't reopen right now; try again in a few seconds.")
    ok = false
  end
  D.SavePrefs()
  T.Hud.Refresh()
  D.Refresh()
  T.Config.Sync()
  return ok
end

function D.Toggle()
  return D.SetOpen(not D.IsShown())
end

-- Shows today's stats as a HUD strip (true) or a window (false); open or closed stays as it was.
-- Returns false when the window can't reopen yet.
function D.SetHud(on)
  on = on == true
  if on == prefs.hud then return true end
  local open = D.IsShown()
  hover:Clear("t:")
  prefs.hud = on
  local ok = true
  if on then
    if win then win:Hide() end
    prefs.open = open
  elseif open then
    if not win then build() end
    ok = win:IsShown() or win:Show()
    if not ok then T.Print("The daily stats window can't reopen right now; try again in a few seconds.") end
    prefs.open = ok
  end
  D.SavePrefs()
  T.Hud.Build(true)                   -- the HUD strip exists only in the HUD form (8 HUD frames per add-on)
  T.Hud.Refresh()
  D.Refresh()
  T.Config.Sync()
  return ok
end

function D.GetHud()
  return prefs.hud
end

-- The strip's position (for /toolbox daily move); nil while it isn't laid out.
function D.GetPosition()
  if not strip then return nil end
  return strip.GetPosition()          -- both numbers ("strip and ..." would keep only x)
end
function D.MoveTo(x, y) return strip ~= nil and strip.MoveTo(x, y) end

function D.ApplyText()
  if strip then strip.ApplyText() end
  if not win then return end
  local style = T.Window.LineStyle()
  for _, id in ipairs(TEXT_IDS) do el[id]:SetStyle(style) end
end

function D.SampleLabel()
  return D.IsShown() and active().date or nil
end

function D.Track()
  if T.Window.TrackPosition(win, prefs) then D.SavePrefs() end
end

-- Hover reports from the Today Detailed window (key without prefix).
function D.PopupHover(key, over)
  hover:Report("p:" .. key, over)
end

function D.PopupClosed()
  hover:Clear("p:")
end

function D.SetHover(on)
  prefs.hover = on == true
  D.SavePrefs()
  if not prefs.hover then hover:Cancel() end
  T.Config.Sync()
end

function D.GetHover()
  return prefs.hover
end

-- "Today 2026-09-27", and a tooltip saying which clock resets it.
function D.DateText()
  if D.source == "local" then return "Today " .. D.label, "Resets at local midnight" end
  if D.source == "utc" then return "Today " .. D.label, "Local clock unavailable: resets at midnight UTC" end
  return "Today (no clock)", "No usable clock: these counts will not reset by themselves"
end

function D.Refresh()
  local e = active()
  if not D.IsShown() or not D.day or not e.date then return end
  local date, tip = D.DateText()
  T.SetText(e.date, date)
  T.SetTooltip(e.date, tip)
  T.SetText(e.gold, T.FormatNumber(D.day.gold))
  T.SetText(e.kills, T.FormatNumber(D.day.kills))
  T.SetText(e.adv, T.FormatNumber(D.XPToday(D.day, "a")))
  T.SetText(e.prod, T.FormatNumber(D.XPToday(D.day, "p")))
end
