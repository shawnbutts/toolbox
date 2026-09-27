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
-- }

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

function D.New(key)
  return { v = D.FORMAT, key = key, gold = 0, kills = 0, a = 0, p = 0, items = {}, dropped = 0, last = {} }
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

-- Fills in fields added after the first v1 saves.
function D.Upgrade(d)
  d.items = d.items or {}
  d.dropped = d.dropped or 0
  return d
end

-- Adds one ShroudOnItemsGained batch. Returns true when anything was counted.
function D.AddItems(d, items, dropped)
  local changed = false
  for _, item in ipairs(type(items) == "table" and items or {}) do
    local name, qty = type(item) == "table" and item.name, type(item) == "table" and item.quantity
    if type(name) == "string" and name ~= "" and isCount(qty) and qty > 0 then
      if d.items[name] == nil then
        local kinds = 0
        for _ in pairs(d.items) do kinds = kinds + 1 end
        if kinds >= D.MAX_KINDS then name = D.OTHER end
      end
      d.items[name] = (d.items[name] or 0) + qty
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
  d.items, d.dropped = {}, 0
  return true
end

-- XP totals: only increases count. A lower reading is treated as a bad read (a 0
-- while a scene loads) and ignored, as in the session model.
local function observeTrack(d, key, v)
  local last = d.last[key]
  if last ~= nil and v <= last then return false end
  if last ~= nil then d[key] = d[key] + (v - last) end
  d.last[key] = v
  return true
end

function D.ObserveXP(d, adv, prod)
  local a = observeTrack(d, "a", adv)
  local p = observeTrack(d, "p", prod)
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

function D.OnItems(items, dropped)
  if D.day and D.AddItems(D.day, items, dropped) then D.unsaved = true end
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
local prefs = { open = false, hover = true }

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
  return UI.Row{ style = { alignItems = "center" }, tooltip = spec.tooltip, children = {
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
    x = prefs.x, y = prefs.y,
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
  return win ~= nil and win:IsShown()
end

-- Builds the window (after Toolbox.Window.Init, whose text settings it uses).
-- The data is loaded earlier, by D.Load from ShroudOnStart.
function D.InitWindow()
  local saved = T.Load("daily_window")
  prefs = { open = false, hover = true }
  if type(saved) == "table" then
    prefs.open = saved.open == true
    prefs.hover = saved.hover ~= false
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
  end
  build()
  if prefs.open and not win:Show() then
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
  elseif win:IsShown() or win:Show() then
    prefs.open = true
    D.Refresh()
  else
    T.Print("The daily stats window can't reopen right now; try again in a few seconds.")
    ok = false
  end
  D.SavePrefs()
  T.Config.Sync()
  return ok
end

function D.Toggle()
  return D.SetOpen(not D.IsShown())
end

function D.ApplyText()
  if not win then return end
  local style = { fontSize = T.Window.GetFont(), height = T.Window.LineHeight() }
  for _, id in ipairs(TEXT_IDS) do el[id]:SetStyle(style) end
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
  if not D.IsShown() or not D.day then return end
  local date, tip = D.DateText()
  el.date:SetText(date)
  el.date:SetTooltip(tip)
  el.gold:SetText(T.FormatNumber(D.day.gold))
  el.kills:SetText(T.FormatNumber(D.day.kills))
  el.adv:SetText(T.FormatNumber(D.day.a))
  el.prod:SetText(T.FormatNumber(D.day.p))
end
