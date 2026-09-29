-- Toolbox: dailydetail.lua
-- The "Today Detailed" window (/toolbox dailydetailed, dd): today's totals plus every
-- item gained, with counts. Pops up when the Today window is hovered (daily.lua), or
-- can be pinned open like XP Detailed.
--
-- Rows can't be reordered and creating elements quickly is capped (~500 burst, then
-- ~200/s), so the list is never rebuilt on a timer. New item names are appended (a
-- batch sorted by count) and after that only the counts change. When the window is
-- shown and the rows are out of order, the list is rebuilt sorted, at most once every
-- DD.RESORT_SECONDS; rows are capped at DD.MAX_ROWS (4 elements each) to stay well
-- inside the burst.
--
-- Optional estimated values (Toolbox.Prices, below the window code): each row's count times
-- the item's 90-day average sale price from SOTA.net's public price API, and a total in the
-- header. Off by default; it also needs the player to switch Internet on for Toolbox in the
-- add-on manager. Items with no recent sales stay blank.

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
local rows = {}        -- item name -> { name = label, count = label, value = label }
local order = {}       -- item names in row order
local rowCount = 0
local lastRebuild = -math.huge
local listKey = nil    -- day key the rows were built for
local prefs = { open = false, values = false }
local popup = false

local HEADER_IDS = { "date", "summary", "items_summary", "value_summary", "more" }
local P = {}           -- Toolbox.Prices (defined below)

local function text(id, class, extra)
  return UI.Label{ id = id, text = "", class = class, style = T.Window.TextStyle(extra) }
end

local function addRow(name)
  if rowCount >= DD.MAX_ROWS then return false end
  local nameLabel = UI.Label{ text = name, class = "text", style = T.Window.TextStyle{ flexGrow = 1, flexShrink = 1 } }
  local countLabel = UI.Label{ text = "", class = "text",
    style = T.Window.TextStyle{ textAlign = "right", marginLeft = 6 } }
  local valueLabel = UI.Label{ text = "", class = "dim", visible = prefs.values == true,
    style = T.Window.TextStyle{ textAlign = "right", marginLeft = 8 } }
  el.list:Add(UI.Row{ style = { alignItems = "center" }, children = { nameLabel, countLabel, valueLabel } })
  rows[name] = { name = nameLabel, count = countLabel, value = valueLabel }
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
    x = prefs.x or T.Window.DEFAULT_X, y = prefs.y or T.Window.DEFAULT_Y,   -- never nil in a spec
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
          text("value_summary", "dim"),
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
  DD.Refresh(true)
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
    prefs.values = saved.values == true
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
  local style = T.Window.LineStyle()
  for _, id in ipairs(HEADER_IDS) do el[id]:SetStyle(style) end
  for _, r in pairs(rows) do
    r.name:SetStyle(style)
    r.count:SetStyle(style)
    r.value:SetStyle(style)
  end
end

function DD.SampleLabel()
  return DD.IsShown() and el.date or nil
end

function DD.Track()
  if T.Window.TrackPosition(win, prefs) then DD.SavePrefs() end
end

-- The list, counts and values are redrawn only when something they show changed: today's items
-- (Daily.itemsVersion), a price (Prices.version), the values setting, the day, or the window opening;
-- and once a DD.FULL_EVERY as a catch-all (it also re-queues prices past their age). It used to redo
-- all of it every second, ~10 KB/s of garbage with a full day's 250 names (stress test, 2026-09-29).
DD.FULL_EVERY = 60
local drawn = { items = nil, prices = nil, values = nil, at = -math.huge, gold = nil, kills = nil }

local function byCountThenName(day)
  return function(x, y)
    if day.items[x] ~= day.items[y] then return day.items[x] > day.items[y] end
    return x < y
  end
end

function DD.Refresh(force)
  if not DD.IsShown() then return end
  local day = T.Daily.day
  if not day then return end
  local now = T.Now()
  if day.key ~= listKey then
    rebuildList()
    force = true
  end
  if day.gold ~= drawn.gold or day.kills ~= drawn.kills then
    drawn.gold, drawn.kills = day.gold, day.kills
    T.SetText(el.summary, "Gold " .. T.FormatNumber(day.gold) .. "  |  Kills " .. T.FormatNumber(day.kills))
  end
  if not (force or drawn.items ~= T.Daily.itemsVersion or drawn.prices ~= P.version
      or drawn.values ~= prefs.values or now - drawn.at >= DD.FULL_EVERY) then
    if prefs.values then T.SetText(el.value_summary, DD.ValueLine()) end   -- its status can change with time
    return
  end
  drawn.items, drawn.prices, drawn.values, drawn.at = T.Daily.itemsVersion, P.version, prefs.values, now
  T.SetText(el.date, (T.Daily.DateText()))

  local kinds, total, new = 0, 0, {}
  for name, n in pairs(day.items) do
    kinds, total = kinds + 1, total + n
    if not rows[name] then new[#new + 1] = name end
  end
  -- Append new names highest count first, so a batch lands in a sensible order.
  if #new > 1 then table.sort(new, byCountThenName(day)) end
  for _, name in ipairs(new) do
    if not addRow(name) then break end
  end
  for name, r in pairs(rows) do T.SetText(r.count, T.FormatNumber(day.items[name] or 0)) end
  DD.RefreshValues(day)
  local hidden = kinds - rowCount
  T.SetText(el.items_summary, kinds == 0 and "No items gained yet"
    or ("Items gained: " .. T.FormatNumber(total) .. " (" .. kinds .. (kinds == 1 and " kind)" or " kinds)")))

  local notes = {}
  if hidden > 0 then notes[#notes + 1] = "+" .. hidden .. " more kinds not listed" end
  if day.dropped > 0 then notes[#notes + 1] = "+" .. day.dropped .. " kinds the game didn't itemise" end
  if prefs.values and hidden > 0 then notes[#notes + 1] = "the value includes them" end
  T.SetText(el.more, table.concat(notes, "; "))
  T.SetVisible(el.more, #notes > 0)
end

-- The value column and the header's value line (estimated values on), or hides them.
local valued = { total = 0, priced = 0, kinds = 0 }   -- the totals behind the value line
function DD.RefreshValues(day)
  T.SetVisible(el.value_summary, prefs.values == true)
  if not prefs.values then return end
  local total, priced, kinds = 0, 0, 0
  for name, n in pairs(day.items) do
    if name ~= T.Daily.OTHER then
      kinds = kinds + 1
      P.Want(name)
      local each = P.Average(name)
      if each then
        total, priced = total + n * each, priced + 1
      end
    end
  end
  for name, r in pairs(rows) do
    local each = P.Average(name)
    local n = day.items[name] or 0
    T.SetText(r.value, each and ("~" .. P.Format(n * each)) or "")
    T.SetTooltip(r.value, P.Tooltip(name))
  end
  valued.total, valued.priced, valued.kinds = total, priced, kinds
  T.SetText(el.value_summary, DD.ValueLine())
end

-- The header's value line, from the last totals and the lookup status (which changes with time).
function DD.ValueLine()
  local line = P.StatusLine()
  if line then return line end
  local total, priced, kinds = valued.total, valued.priced, valued.kinds
  if kinds == 0 then return "Estimated value: nothing gained yet" end
  if priced == 0 and P.Idle() then return "Estimated value: none of today's items sold recently (SOTA.net)" end
  if priced == 0 then return "Estimated value: looking up prices on SOTA.net..." end
  return "Estimated value ~" .. P.Format(total) .. " (" .. priced .. " of " .. kinds .. " kinds priced, SOTA.net)"
end

function DD.GetValues() return prefs.values == true end

function DD.SetValues(on)
  prefs.values = on == true
  DD.SavePrefs()
  for _, r in pairs(rows) do T.SetVisible(r.value, prefs.values) end
  if prefs.values then P.Wake() end
  DD.Refresh(true)
  T.Config.Sync()
end

-- ---------------------------------------------------------------------------
-- Estimated values (Toolbox.Prices): SOTA.net's 90-day average sale prices
-- ---------------------------------------------------------------------------
-- GET https://shroudoftheavatar.net/api/v1/receipts/prices?item=A&item=B (up to 50 names,
-- matched whole and case-insensitively) -> { items = { { item, avg90d (null: no sales in 90
-- days), sold90d, lastPrice, lastSoldAt } }, missing = { names with no sales } }.
-- Through ShroudHttpGet: the manifest declares "network" and the host, and the player must
-- switch Internet on for Toolbox in the add-on manager. Only item names are sent. Prices are
-- kept per account, across reloads and restarts, for P.MAX_AGE (24 hours) after they were
-- fetched (by the local clock; without one, until local midnight): they barely move (90-day
-- averages), so each name is looked up at most once a day. /toolbox dd values refresh forgets
-- them all. Requests are spaced P.GAP apart (the client allows about 6 a minute), one at a
-- time; one that never answers is given up after P.TIMEOUT.
-- Saved var "prices" (account scope): { v = 1, items = { [lower name] = { avg = n|false,
-- sold = n, last = "ISO date"|"", day = Toolbox.Today() key, at = Toolbox.Clock() (if any) } } }.

Toolbox.Prices = P

P.URL = "https://shroudoftheavatar.net/api/v1/receipts/prices"
P.BATCH = 50          -- names per request (the API's limit)
P.URL_MAX = 1900      -- characters: under the client's 2048 limit
P.GAP = 12            -- seconds between requests
P.RETRY = 60          -- seconds after a failed or refused request
P.TIMEOUT = 40        -- seconds before a request with no answer is given up (a reload drops it)
P.MAX_KEEP = 2000     -- prices kept (saved-var size)
P.MAX_AGE = 86400     -- seconds a price is used before it is looked up again

local cache = {}      -- lower name -> { avg, sold, last, day }
P.version = 0         -- bumped when the cache changes (Today Detailed redraws its values then)
local queue = {}      -- names (as looted) waiting for a lookup
local queued = {}     -- lower name -> true while queued or in flight
local inflight = nil  -- { id, names, at }
local nextAt = 0
local status = nil    -- nil = fine; otherwise a key of STATUS
local loaded = false

local STATUS = {
  needs_permission = "Estimated values: switch Internet on for Toolbox in the add-on manager",
  unavailable = "Estimated values: this game client can't reach the internet",
  disabled = "Estimated values: internet access is switched off on this server",
  quota = "Estimated values: too many lookups this session; they resume after a restart",
  failed = "Estimated values: SOTA.net didn't answer; trying again in a minute",
}

-- Gold for display: "1,234g", "12g", "4.5g", "<1g".
function P.Format(g)
  if type(g) ~= "number" or g <= 0 then return "0g" end
  if g >= 10 then return T.FormatNumber(g) .. "g" end
  if g >= 1 then return (string.format("%.1f", g):gsub("%.0$", "")) .. "g" end
  return "<1g"
end

local function key(name) return tostring(name):lower() end

local function readCache()
  if loaded then return end
  loaded = true
  local saved = ShroudGetSavedVar("prices", "account")
  cache = {}
  P.version = P.version + 1
  if type(saved) == "table" and saved.v == 1 and type(saved.items) == "table" then
    for k, e in pairs(saved.items) do
      if type(k) == "string" and type(e) == "table" and type(e.day) == "string"
          and (e.avg == false or type(e.avg) == "number") then
        cache[k] = { avg = e.avg, sold = type(e.sold) == "number" and e.sold or 0,
                     last = type(e.last) == "string" and e.last or "", day = e.day }
        if type(e.at) == "number" then cache[k].at = e.at end
      end
    end
  end
end

local function writeCache()
  local keys = {}
  for k in pairs(cache) do keys[#keys + 1] = k end
  if #keys > P.MAX_KEEP then                 -- drop the oldest days first
    table.sort(keys, function(a, b) return cache[a].day > cache[b].day end)
    for i = P.MAX_KEEP + 1, #keys do cache[keys[i]] = nil end
  end
  ShroudSetSavedVar("prices", T.Copy({ v = 1, items = cache }), "account")
end

-- The 90-day average price per unit, or nil (not looked up yet, or no recent sales).
function P.Average(name)
  readCache()
  local e = cache[key(name)]
  if e and type(e.avg) == "number" and e.avg > 0 then return e.avg end
  return nil
end

-- A row's tooltip: the unit price and sales, or why it's blank.
function P.Tooltip(name)
  readCache()
  local e = cache[key(name)]
  if not e then return "Looking up its price on SOTA.net..." end
  if type(e.avg) ~= "number" then return "No sales on SOTA.net in the last 90 days" end
  local when = e.last ~= "" and ("; last sold " .. e.last:sub(1, 10)) or ""
  return "~" .. P.Format(e.avg) .. " each: the average of " .. T.FormatNumber(e.sold)
    .. " sold in the last 90 days" .. when .. " (SOTA.net, from player-uploaded receipts)"
end

-- Whether a cached price is still good: under P.MAX_AGE old by the local clock, or (no clock,
-- or saved without a time) from today.
function P.Fresh(e)
  if type(e) ~= "table" then return false end
  local now = T.Clock()
  if now and type(e.at) == "number" then return now >= e.at and now - e.at < P.MAX_AGE end
  return e.day == T.Today()
end

-- Queues a name for a lookup unless it has a fresh price or is already waiting.
function P.Want(name)
  readCache()
  local k = key(name)
  if queued[k] then return end
  if P.Fresh(cache[k]) then return end
  queued[k] = true
  queue[#queue + 1] = name
end

-- True when nothing is waiting or in flight.
function P.Idle() return #queue == 0 and inflight == nil end

function P.StatusLine() return status and STATUS[status] or nil end

-- Retry now (the setting was switched on).
function P.Wake()
  nextAt, status = 0, nil
end

-- The next request's names (up to P.BATCH, the URL under P.URL_MAX) and its URL.
function P.NextBatch(names)
  local url, batch = P.URL, {}
  for _, name in ipairs(names) do
    local part = (#batch == 0 and "?item=" or "&item=") .. T.UrlEncode(name)
    if #batch >= P.BATCH or #url + #part > P.URL_MAX then break end
    url = url .. part
    batch[#batch + 1] = name
  end
  return batch, url
end

-- From Toolbox.Tick (1 s): sends the next request when it's time.
function P.Tick()
  local now = T.Now()
  if inflight then
    if now - inflight.at < P.TIMEOUT then return end
    if inflight.test then
      T.Print("Price test: no answer after " .. P.TIMEOUT .. " s (network_error or a dropped request).")
    else
      for _, name in ipairs(inflight.names) do queue[#queue + 1] = name end   -- never answered
    end
    inflight = nil
  end
  if not prefs.values then return end
  if #queue == 0 or now < nextAt then return end
  if type(ShroudHttpGet) ~= "function" then
    status = "unavailable"
    return
  end
  local batch, url = P.NextBatch(queue)
  local ok, id, reason = pcall(ShroudHttpGet, url)
  if not ok then id, reason = nil, "failed" end
  if not id then
    -- Refused before anything was sent: wait, and say why in the header (a busy client is normal).
    local waits = { rate_limited = P.GAP, too_many_in_flight = P.GAP, not_permitted = P.RETRY,
                    disabled = 600, quota_exceeded = 3600 }
    local shown = { not_permitted = "needs_permission", disabled = "disabled", quota_exceeded = "quota" }
    nextAt = now + (waits[reason] or P.RETRY)
    if shown[reason] then
      status = shown[reason]
    elseif not waits[reason] then
      status = "failed"
    end
    return
  end
  local rest = {}
  for i = #batch + 1, #queue do rest[#rest + 1] = queue[i] end
  queue = rest
  inflight = { id = id, names = batch, at = now }
  nextAt = now + P.GAP
end

-- Stores the answer for `names`: a price for each item listed, "no sales" for the rest.
function P.Apply(names, data)
  local today, clock = T.Today(), T.Clock()
  local function put(k, e)
    e.day = today
    if clock then e.at = clock end
    cache[k] = e
  end
  P.version = P.version + 1
  local found = {}
  for _, it in ipairs(type(data) == "table" and type(data.items) == "table" and data.items or {}) do
    if type(it) == "table" and type(it.item) == "string" then
      local avg = type(it.avg90d) == "number" and it.avg90d or false
      put(key(it.item), { avg = avg, sold = type(it.sold90d) == "number" and it.sold90d or 0,
                          last = type(it.lastSoldAt) == "string" and it.lastSoldAt or "" })
      found[key(it.item)] = true
    end
  end
  for _, name in ipairs(names) do
    local k = key(name)
    if not found[k] then put(k, { avg = false, sold = 0, last = "" }) end
    queued[k] = nil
  end
  writeCache()
end

-- /toolbox dd values refresh: forgets every cached price; what's on screen is looked up again.
function P.Forget()
  readCache()
  local n = 0
  for _ in pairs(cache) do n = n + 1 end
  cache = {}
  writeCache()
  nextAt, status = 0, nil
  P.version = P.version + 1
  DD.Refresh()
  return n
end

-- /toolbox dd values test [item]: one lookup now, whatever the setting, each step in chat. For
-- checking the connection without looting anything; the answer is kept like any other.
P.TEST_ITEM = "Iron Ore"
local REFUSALS = {
  not_permitted = "switch Internet on for Toolbox in the add-on manager",
  disabled = "internet access is switched off on this server",
  rate_limited = "too many requests just now; wait a minute",
  too_many_in_flight = "other requests are still running; try again in a few seconds",
  quota_exceeded = "the limit for this play session is used up",
  host_not_allowed = "the package doesn't declare shroudoftheavatar.net",
}
function P.Test(name)
  name = T.Trim(name)
  if name == "" then name = P.TEST_ITEM end
  if type(ShroudHttpGet) ~= "function" then
    T.Print("Price test: this game client has no internet access for add-ons (no ShroudHttpGet).")
    return
  end
  if inflight then
    T.Print("Price test: a lookup is already running; try again in a few seconds.")
    return
  end
  local _, url = P.NextBatch({ name })
  local ok, id, reason = pcall(ShroudHttpGet, url)
  if not ok then
    T.Print("Price test: ShroudHttpGet raised an error: " .. tostring(id))
    return
  end
  if not id then
    T.Print("Price test: the game refused the request: " .. tostring(reason)
      .. (REFUSALS[reason] and (" (" .. REFUSALS[reason] .. ")") or ""))
    return
  end
  T.Print("Price test: asked SOTA.net for '" .. name .. "'...")
  inflight = { id = id, names = { name }, at = T.Now(), test = true }
  nextAt = T.Now() + P.GAP
end

-- The chat lines for a test lookup's answer.
function P.Report(name, ok, code, body, err, data)
  if not ok then
    local snippet = type(body) == "string" and body ~= "" and (": " .. body:sub(1, 120)) or ""
    T.Print("Price test: failed, " .. tostring(err) .. " (HTTP " .. tostring(code) .. ")" .. snippet)
    return
  end
  if type(data) ~= "table" then
    T.Print("Price test: the answer wasn't JSON: " .. tostring(body):sub(1, 120))
    return
  end
  local it = type(data.items) == "table" and data.items[1] or nil
  if type(it) ~= "table" or type(it.avg90d) ~= "number" then
    T.Print("Price test: connected. '" .. name .. "' has no sales on SOTA.net in the last 90 days"
      .. " (or no item has that exact name).")
    return
  end
  T.Print(string.format("Price test: connected. '%s': ~%s each (90-day average), %s sold in 90 days, last sold %s.",
    tostring(it.item), P.Format(it.avg90d), T.FormatNumber(it.sold90d or 0),
    type(it.lastSoldAt) == "string" and it.lastSoldAt:sub(1, 10) or "?"))
end

-- ShroudOnHttpResponse (from core.lua). Returns true when the answer was ours.
function P.OnResponse(id, ok, code, body, err)
  if not inflight or id ~= inflight.id then return false end
  local names, test = inflight.names, inflight.test
  inflight = nil
  local data = ok and T.JsonDecode(body) or nil
  if test then
    P.Report(names[1], ok, code, body, err, data)
    if type(data) == "table" then P.Apply(names, data) end
    DD.Refresh()
    return true
  end
  if type(data) ~= "table" then
    -- 4xx/5xx (429 too many requests), no answer, or not JSON: try these again later
    for _, name in ipairs(names) do queue[#queue + 1] = name end
    nextAt = T.Now() + P.RETRY
    status = "failed"
    P.lastError = tostring(err or code)      -- for tests and debugging
    DD.Refresh()
    return true
  end
  status = nil
  P.Apply(names, data)
  DD.Refresh()
  return true
end
