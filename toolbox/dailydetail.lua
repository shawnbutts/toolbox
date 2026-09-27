-- Toolbox: dailydetail.lua
-- The "Today Detailed" window (/toolbox dailydetailed, dd): today's totals plus every
-- item gained, with counts. Pops up when the Today window is hovered (daily.lua), or
-- can be pinned open like XP Detailed.
--
-- Rows can't be reordered and creating elements quickly is capped (~500 burst, then
-- ~200/s), so the list is never rebuilt on a timer. New item names are appended (a
-- batch sorted by count) and after that only the counts change. When the window is
-- shown and the rows are out of order, the list is rebuilt sorted, at most once every
-- DD.RESORT_SECONDS; rows are capped at DD.MAX_ROWS (3 elements each) to stay well
-- inside the burst.

local T = Toolbox
local DD = {}
Toolbox.DailyDetail = DD

local UI = Shroud.UI
local WINDOW_ID = "toolbox_daily_detail"
local GUTTER = 8
DD.MAX_ROWS = 60       -- item rows shown; the rest are summarised in one line
DD.RESORT_SECONDS = 10 -- minimum time between sorted rebuilds

local win = nil
local el = {}          -- fixed labels by id
local rows = {}        -- item name -> { name = label, count = label }
local order = {}       -- item names in row order
local rowCount = 0
local lastRebuild = -math.huge
local listKey = nil    -- day key the rows were built for
local prefs = { open = false }
local popup = false

local HEADER_IDS = { "date", "summary", "items_summary", "more" }

local function text(id, class, extra)
  return UI.Label{ id = id, text = "", class = class, style = T.Window.TextStyle(extra) }
end

local function addRow(name)
  if rowCount >= DD.MAX_ROWS then return false end
  local nameLabel = UI.Label{ text = name, class = "text", style = T.Window.TextStyle{ flexGrow = 1, flexShrink = 1 } }
  local countLabel = UI.Label{ text = "", class = "text",
    style = T.Window.TextStyle{ textAlign = "right", marginLeft = 6 } }
  el.list:Add(UI.Row{ style = { alignItems = "center" }, children = { nameLabel, countLabel } })
  rows[name] = { name = nameLabel, count = countLabel }
  rowCount = rowCount + 1
  order[rowCount] = name
  return true
end

-- (Re)creates the item rows for the current day, sorted by count.
local function rebuildList()
  el.list:Clear()
  rows, order, rowCount = {}, {}, 0
  lastRebuild = T.Now()
  local day = T.Daily.day
  listKey = day and day.key
  if not day then return end
  for _, name in ipairs(T.Daily.SortedItems(day)) do
    if not addRow(name) then break end
  end
end

local function build()
  win = UI.Window{
    id = WINDOW_ID, title = "Today Detailed",
    width = 240, height = 260, minWidth = 170, minHeight = 60,
    x = prefs.x, y = prefs.y,
    escCloses = true,
    onClose = function()
      prefs.open = false
      popup = false
      DD.SavePrefs()
      T.Daily.PopupClosed()
      T.Config.Sync()
    end,
    onHover = function(_, over) T.Daily.PopupHover("window", over) end,
    style = { paddingTop = 4, paddingBottom = 4 },
    children = {
      UI.Column{ id = "header", style = { paddingLeft = GUTTER, paddingRight = GUTTER },
        onHover = function(_, over) T.Daily.PopupHover("header", over) end,
        children = {
          text("date", "title"),
          text("summary", "text"),
          text("items_summary", "heading", { marginTop = 3 }),
        } },
      UI.Scroll{ id = "body", style = { flexGrow = 1 },
        onHover = function(_, over) T.Daily.PopupHover("body", over) end,
        children = {
          UI.Column{ id = "list", style = { paddingLeft = GUTTER, paddingRight = GUTTER } },
          UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = { text("more", "text") } },
        } },
    },
  }
  el = { list = win:Find("list") }
  for _, id in ipairs(HEADER_IDS) do el[id] = win:Find(id) end
  rebuildList()
end

-- True when the rows aren't in count order (or the day's list has rows missing that
-- would fit): worth a rebuild when the window is shown.
local function outOfOrder()
  local day = T.Daily.day
  if not day then return false end
  local sorted = T.Daily.SortedItems(day)
  local shown = math.min(#sorted, DD.MAX_ROWS)
  if rowCount ~= shown then return true end
  for i = 1, shown do
    if order[i] ~= sorted[i] then return true end
  end
  return false
end

-- Called whenever the window becomes visible.
local function onShown()
  if T.Now() - lastRebuild >= DD.RESORT_SECONDS and outOfOrder() then rebuildList() end
  DD.Refresh()
end

function DD.SavePrefs()
  T.Save("daily_detail", prefs)
end

function DD.IsShown()
  return win ~= nil and win:IsShown()
end

function DD.IsOpen()
  return prefs.open == true
end

function DD.IsPopup()
  return popup and DD.IsShown()
end

function DD.Init()
  local saved = T.Load("daily_detail")
  prefs = { open = false }
  popup = false
  if type(saved) == "table" then
    prefs.open = saved.open == true
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
  end
  build()
  if prefs.open and not win:Show() then
    T.Print("Today Detailed window could not reopen yet; use /toolbox dailydetailed.")
  end
  onShown()
end

-- Pinned open or closed by the player. Returns true when it ends up as asked.
function DD.SetOpen(open)
  if not win then build() end
  local ok = true
  if not open then
    win:Hide()
    prefs.open, popup = false, false
  elseif win:IsShown() then
    prefs.open, popup = true, false          -- pinning a pop-up
  elseif win:Show() then
    prefs.open, popup = true, false
    onShown()
  else
    T.Print("The Today Detailed window can't reopen right now; try again in a few seconds.")
    ok = false
  end
  DD.SavePrefs()
  T.Config.Sync()
  return ok
end

function DD.Toggle()
  return DD.SetOpen(not DD.IsOpen())
end

function DD.ShowPopup()
  if not win then build() end
  if win:IsShown() or not win:Show() then return false end
  popup = true
  onShown()
  return true
end

function DD.HidePopup()
  if popup and win then win:Hide() end
  popup = false
end

function DD.ApplyText()
  if not win then return end
  local style = { fontSize = T.Window.GetFont(), height = T.Window.LineHeight() }
  for _, id in ipairs(HEADER_IDS) do el[id]:SetStyle(style) end
  for _, r in pairs(rows) do
    r.name:SetStyle(style)
    r.count:SetStyle(style)
  end
end

function DD.Track()
  if T.Window.TrackPosition(win, prefs) then DD.SavePrefs() end
end

function DD.Refresh()
  if not DD.IsShown() then return end
  local day = T.Daily.day
  if not day then return end
  if day.key ~= listKey then rebuildList() end

  el.date:SetText((T.Daily.DateText()))
  el.summary:SetText("Gold " .. T.FormatNumber(day.gold) .. "  |  Kills " .. T.FormatNumber(day.kills))

  local kinds, total, new = 0, 0, {}
  for name, n in pairs(day.items) do
    kinds, total = kinds + 1, total + n
    if not rows[name] then new[#new + 1] = name end
  end
  -- Append new names highest count first, so a batch lands in a sensible order.
  table.sort(new, function(x, y)
    if day.items[x] ~= day.items[y] then return day.items[x] > day.items[y] end
    return x < y
  end)
  for _, name in ipairs(new) do
    if not addRow(name) then break end
  end
  for name, r in pairs(rows) do r.count:SetText(T.FormatNumber(day.items[name] or 0)) end
  local hidden = kinds - rowCount
  el.items_summary:SetText(kinds == 0 and "No items gained yet"
    or ("Items gained: " .. T.FormatNumber(total) .. " (" .. kinds .. (kinds == 1 and " kind)" or " kinds)")))

  local notes = {}
  if hidden > 0 then notes[#notes + 1] = "+" .. hidden .. " more kinds not listed" end
  if day.dropped > 0 then notes[#notes + 1] = "+" .. day.dropped .. " kinds the game didn't itemise" end
  el.more:SetText(table.concat(notes, "; "))
  el.more:SetVisible(#notes > 0)
end
