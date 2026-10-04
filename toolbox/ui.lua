-- Toolbox: ui.lua
-- The "XP Detailed" window (/toolbox xpdetailed), built with Shroud.UI. Internally
-- Toolbox.Window with id "toolbox_xp" and saved var "window" (kept from when it was
-- the only XP window, so players keep their position and settings). Updated from the 1-second
-- periodic in core.lua, never per frame.

local T = Toolbox
local W = {}
Toolbox.Window = W

local UI = Shroud.UI   -- reading Shroud.UI at top level is allowed; constructors are not
local WINDOW_ID = "toolbox_xp"

local win = nil        -- window handle, rebuilt in ShroudOnStart after every reload
local el = {}          -- element handles by id
local prefs = { open = false }   -- open = pinned by the player (/toolbox xpdetailed, settings)
local popup = false              -- shown only because the XP (compact) window is hovered

W.FONT_MIN, W.FONT_MAX, W.FONT_DEFAULT = 9, 32, 12   -- fontSize range from the Shroud.UI docs
-- Shroud.UI has no line-height style, so each text line gets an explicit height:
-- the glyph box (about 1.15 x fontSize) plus W.spacing pixels, with no vertical margins.
W.SPACING_MIN, W.SPACING_MAX, W.SPACING_DEFAULT = 0, 12, 2

local function rateText(n)
  return T.FormatNumber(n) .. "/h"
end

-- Labels whose size and line height follow prefs.font / prefs.spacing (the Reset
-- button follows the font only).
local TEXT_IDS = { "elapsed", "session_extra" }
for _, track in ipairs(T.XP.TRACKS) do
  for _, suffix in ipairs({ "_head", "_gain", "_eta", "_chart_note" }) do
    TEXT_IDS[#TEXT_IDS + 1] = track.key .. suffix
  end
end

-- Side gutter, set on each section rather than relying on the window body's padding
-- reaching inside the Scroll (the progress bars ran to the window edge without it).
W.GUTTER = 10

local function fontSize()
  return prefs.font or W.FONT_DEFAULT
end

local function spacing()
  return prefs.spacing or W.SPACING_DEFAULT
end

-- Height of one text line at the current font size and spacing (or font size `f`, spacing `sp`).
function W.LineHeight(f, sp)
  return math.ceil((f or fontSize()) * 1.15) + (sp or spacing())
end

-- Size and line height for a text label. The height is pinned with minHeight and
-- maxHeight too: a theme class can set its own minimum height, which would win over
-- a smaller `height` and make small spacing values do nothing.
-- `f` and `sp` override the font size and spacing (the notification HUD has its own).
function W.LineStyle(f, sp)
  f = f or fontSize()
  local h = W.LineHeight(f, sp)
  return { fontSize = f, height = h, minHeight = h, maxHeight = h }
end

-- Style for a text label: LineStyle plus no vertical margins or padding.
-- `extra` adds or overrides keys; `f` and `sp` override the font size and spacing. Shared with the other windows.
function W.TextStyle(extra, f, sp)
  local style = W.LineStyle(f, sp)
  style.marginTop, style.marginBottom, style.paddingTop, style.paddingBottom = 0, 0, 0, 0
  for k, v in pairs(extra or {}) do style[k] = v end
  return style
end

local function barHeight()
  return math.max(4, math.floor(fontSize() / 2))
end

-- The last hour as a column chart under each track: W.CHART_COLS columns of XP gained, bottom
-- aligned (the same layout as Combat Detailed's timeline, which works in game).
W.CHART_COLS, W.CHART_SPAN = 30, 3600       -- 2-minute columns over the last hour
W.CHART_COL_W, W.CHART_GAP, W.CHART_H = 5, 1, 24
W.CHART_COLORS = { a = "@gold", p = "@green" }
local chartCols = {}                          -- track key -> the column blocks
local chartShown = {}                         -- track key -> the height each column shows
-- What each chart was last drawn from: redrawn only when a sample is added or changes, a column
-- rolls over, or the net option changes (not every second).
local chartDrawn = {}

-- One element per column (the element-creation cap): a block pushed down by its top margin so it
-- stands on the baseline. An empty column is a transparent 1 px block, not hidden: hidden elements
-- take no room and the others would slide left.
W.CHART_EMPTY = "#00000000"

local function columnStyle(h, color)
  if h <= 0 then return { height = 1, marginTop = W.CHART_H - 1, backgroundColor = W.CHART_EMPTY } end
  return { height = h, marginTop = W.CHART_H - h, backgroundColor = color }
end

local function chart(track)
  local k = track.key
  local cols = {}
  chartCols[k], chartShown[k], chartDrawn[k] = {}, {}, nil
  for i = 1, W.CHART_COLS do
    local style = columnStyle(0)
    style.width, style.marginLeft = W.CHART_COL_W, i > 1 and W.CHART_GAP or 0
    cols[i] = UI.Column{ style = style }
    chartCols[k][i] = cols[i]
  end
  return UI.Row{ id = k .. "_chart", style = { marginTop = 2, height = W.CHART_H, alignItems = "start" },
    children = cols }
end

local function trackRows(track)
  local k = track.key
  return UI.Column{ style = { marginTop = 3, paddingLeft = W.GUTTER, paddingRight = W.GUTTER },
    children = {
      UI.Label{ id = k .. "_head", text = track.name, class = "heading", style = W.TextStyle() },
      UI.Bar{ id = k .. "_bar", value = 0, color = "@gold",
        style = { height = barHeight(), marginTop = 1, marginBottom = 1 } },
      UI.Label{ id = k .. "_gain", text = "", class = "text", style = W.TextStyle() },
      UI.Label{ id = k .. "_eta", text = "", class = "text", style = W.TextStyle() },
      chart(track),
      UI.Label{ id = k .. "_chart_note", text = "", class = "dim", style = W.TextStyle() },
    } }
end

-- Puts a track's last hour into its chart, scaled to the busiest column.
local function fillChart(s, k, now, net)
  local cur = T.XP.Current(s)
  local sig = #s.samples .. ":" .. cur.t .. ":" .. cur[k] .. ":" .. (cur["l" .. k] or 0) .. ":"
    .. math.floor(now / (W.CHART_SPAN / W.CHART_COLS)) .. ":" .. tostring(net) .. ":" .. s.start
  if chartDrawn[k] == sig then return end
  chartDrawn[k] = sig
  local series = T.XP.Series(s, k, now, W.CHART_COLS, W.CHART_SPAN, net)
  local peak = 0
  for _, g in ipairs(series) do
    if g and g > peak then peak = g end
  end
  for i, block in ipairs(chartCols[k] or {}) do
    local g = series[i]
    local h = (g and peak > 0) and math.floor(W.CHART_H * math.max(0, g) / peak + 0.5) or 0
    if h ~= chartShown[k][i] then
      chartShown[k][i] = h
      block:SetStyle(columnStyle(h, W.CHART_COLORS[k] or "@gold"))
    end
  end
  local per = W.CHART_SPAN / W.CHART_COLS
  el[k .. "_chart_note"]:SetText("Last hour, " .. math.floor(per / 60) .. "-min columns; best "
    .. T.FormatNumber(peak * 3600 / per) .. "/h")
end

local function build()
  local f = fontSize()
  local rows = { UI.Label{ id = "session_extra", text = "", class = "dim",
    tooltip = "Skill levels gained (trained levels) and deaths this session",
    style = W.TextStyle{ paddingLeft = W.GUTTER, paddingRight = W.GUTTER } } }
  for _, track in ipairs(T.XP.TRACKS) do rows[#rows + 1] = trackRows(track) end

  win = UI.Window{
    id = WINDOW_ID, title = "XP Detailed",
    -- Only the first open uses width/height: the host remembers the size the player drags it to.
    width = 250, height = 200, minWidth = 160, minHeight = 60,
    x = prefs.x or T.Window.DEFAULT_X, y = prefs.y or T.Window.DEFAULT_Y,   -- never nil in a spec
    escCloses = true,
    onClose = function()
      prefs.open = false
      popup = false
      W.SavePrefs()
      T.Compact.PopupClosed()
      T.Config.Sync()
    end,
    -- Hover is reported on the window and its two sections, so the pop-up stays up
    -- whichever way the host reports entering a child (see Toolbox.Compact).
    onHover = function(_, over) T.Compact.PopupHover("window", over) end,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = {
      UI.Row{
        id = "header",
        onHover = function(_, over) T.Compact.PopupHover("header", over) end,
        style = { alignItems = "center", paddingLeft = W.GUTTER, paddingRight = W.GUTTER },
        children = {
          UI.Label{ id = "elapsed", text = "", class = "title", style = W.TextStyle{ flexGrow = 1 } },
          UI.Button{ id = "reset", text = "Reset", tooltip = "Start a new XP session", style = { fontSize = f },
            onClick = function() T.Dispatch("reset") end },
        },
      },
      -- Scrolls when the player makes the window smaller than its content.
      UI.Scroll{ id = "body", style = { flexGrow = 1 }, children = rows,
        onHover = function(_, over) T.Compact.PopupHover("body", over) end },
    },
  }

  el = { reset = win:Find("reset") }
  for _, id in ipairs(TEXT_IDS) do el[id] = win:Find(id) end
  for _, track in ipairs(T.XP.TRACKS) do el[track.key .. "_bar"] = win:Find(track.key .. "_bar") end
end

-- Sets the text size (W.FONT_MIN..W.FONT_MAX) and remembers it. Returns false when out of range.
function W.SetFont(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < W.FONT_MIN or n > W.FONT_MAX then return false end
  prefs.font = n
  W.SavePrefs()
  W.ApplyText()
  return true
end

function W.GetFont()
  return fontSize()
end

-- Sets the extra pixels per text line (W.SPACING_MIN..W.SPACING_MAX). Returns false when out of range.
function W.SetSpacing(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < W.SPACING_MIN or n > W.SPACING_MAX then return false end
  prefs.spacing = n
  W.SavePrefs()
  W.ApplyText()
  return true
end

function W.GetSpacing()
  return spacing()
end

-- "Subtract XP lost": XP windows and today's XP show the net change (losses subtracted, can be
-- negative) instead of gains only (the default). Owner's option, 2026-09-28.
function W.GetNet() return prefs.net == true end

function W.SetNet(on)
  prefs.net = on == true
  W.SavePrefs()
  T.RefreshViews()
  T.Config.Sync()
end

-- A label in this window while it is shown (for measuring), else nil.
function W.SampleLabel()
  return W.IsShown() and el.elapsed or nil
end

-- The height the game actually laid one text line out at, from the first shown
-- window, and that window's name. nil when no window is shown or not laid out yet.
function W.MeasureLine()
  local sources = {
    { "XP Detailed", W.SampleLabel }, { "XP", T.Compact.SampleLabel },
    { "Today", T.Daily.SampleLabel }, { "Today Detailed", T.DailyDetail.SampleLabel },
  }
  for _, src in ipairs(sources) do
    local label = src[2]()
    if label then
      local _, h = label:GetSize()
      if type(h) == "number" then return math.floor(h + 0.5), src[1] end
    end
  end
  return nil
end

-- Re-applies text size and line height to both XP windows and syncs the settings window.
function W.ApplyText()
  if win then
    local line = W.LineStyle()
    for _, id in ipairs(TEXT_IDS) do el[id]:SetStyle(line) end
    el.reset:SetStyle{ fontSize = fontSize() }
    for _, track in ipairs(T.XP.TRACKS) do el[track.key .. "_bar"]:SetStyle{ height = barHeight() } end
  end
  T.Compact.ApplyText()
  T.Daily.ApplyText()
  T.DailyDetail.ApplyText()
  T.Vitals.ApplyText()
  T.Notify.Hud.ApplyText()        -- its own size and spacing, or these when unset
  T.Config.Sync()
end

function W.SavePrefs()
  T.Save("window", prefs)
end

function W.IsShown()
  return win ~= nil and win:IsShown()
end

-- Pinned open by the player (as opposed to popped up by hovering the compact window).
function W.IsOpen()
  return prefs.open == true
end

function W.IsPopup()
  return popup and W.IsShown()
end

-- Pops the window up for the compact window's hover. Does nothing when it is
-- already showing. Quiet on refusal: hover is not worth a chat line.
function W.ShowPopup()
  if not win then build() end
  if win:IsShown() then return false end
  if not win:Show() then return false end
  popup = true
  W.Refresh()
  return true
end

-- Hides the window only if it is a pop-up; a pinned window stays.
function W.HidePopup()
  if popup and win then win:Hide() end
  popup = false
end

function W.Init()
  local saved = T.ReadSaved("window")
  prefs = { open = false }
  if type(saved) == "table" then
    prefs.open = saved.open == true
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
    if type(saved.font) == "number" and saved.font >= W.FONT_MIN and saved.font <= W.FONT_MAX then
      prefs.font = math.floor(saved.font)
    end
    if type(saved.spacing) == "number" and saved.spacing >= W.SPACING_MIN and saved.spacing <= W.SPACING_MAX then
      prefs.spacing = math.floor(saved.spacing)
    end
    prefs.net = saved.net == true
  end
  -- Built only when first shown (pinned now, or popped up later): it is ~80 elements, and start-up
  -- builds everything at once against the game's element-creation cap.
  win, el = nil, {}
  if prefs.open then
    build()
    if not win:Show() then T.Print("XP Detailed window could not reopen yet; use /toolbox xpdetailed.") end
  end
  W.Refresh()
end

-- Opens or closes the window and remembers the choice. Returns true when the
-- window ends up in the requested state.
function W.SetOpen(open)
  if not win then build() end
  local ok = true
  if not open then
    win:Hide()
    prefs.open = false
    popup = false
  elseif win:IsShown() or win:Show() then
    prefs.open = true
    popup = false                  -- pinning a popped-up window keeps it open
    W.Refresh()
  else
    -- Show() is refused within 3 s of the player closing it, or more than 5 times in 10 s.
    T.Print("The XP Detailed window can't reopen right now; try again in a few seconds.")
    ok = false
  end
  W.SavePrefs()
  T.Config.Sync()
  return ok
end

function W.Toggle()
  return W.SetOpen(not W.IsOpen())
end

-- Room left of a HUD strip's contents for the drag grip at its top-left corner, which
-- otherwise covers the first number / icon. The docs don't give the grip's size; 14 px is an
-- estimate. Add-ons can't tell whether the grip is showing (Lock Status Movement), so the
-- room is always kept.
W.GRIP = 14

-- A window's position before the player has moved it (the documented Window defaults).
-- Specs get these rather than nil: the game's Lua passes nil entries on to the UI.
W.DEFAULT_X, W.DEFAULT_Y = 200, 120

-- Moves a HUD frame from settings or chat (its own grip is hidden while the game's "Lock
-- Status Movement" is on). getFrame() returns the frame or nil; home = { x, y } for Reset
-- (or homeFn() returning one, when it depends on the layout).
-- Returns { Get, MoveTo, Nudge, Reset }. The game keeps HUD frames on screen, and
-- SetPosition "remembers the new spot as the player's".
function W.HudMover(getFrame, home, homeFn)
  local m = {}
  local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end

  -- Left and top as laid out, or nil before the first layout.
  function m.Get()
    local frame = getFrame()
    if not frame then return nil end
    local ok, x, y = pcall(frame.GetPosition, frame)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return math.floor(x + 0.5), math.floor(y + 0.5)
  end

  function m.MoveTo(x, y)
    local frame = getFrame()
    if not frame or not finite(x) or not finite(y) then return false end
    local ok = pcall(frame.SetPosition, frame, math.floor(x + 0.5), math.floor(y + 0.5))
    T.Config.SyncLive()
    return ok
  end

  local function where() return homeFn and homeFn() or home end

  function m.Nudge(dx, dy)
    local x, y = m.Get()
    if not x then x, y = where()[1], where()[2] end
    return m.MoveTo(x + dx, y + dy)
  end

  function m.Reset()
    return m.MoveTo(where()[1], where()[2])
  end

  return m
end

-- Copies a shown window's position into prefs.x/y. Returns true when it moved.
-- Shared with the compact window.
function W.TrackPosition(window, p)
  if not (window and window:IsShown()) then return false end
  local x, y = window:GetPosition()
  if type(x) ~= "number" or type(y) ~= "number" then return false end
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  if x == p.x and y == p.y then return false end
  p.x, p.y = x, y
  return true
end

-- Remembers where the player left the window (checked once a second).
function W.Track()
  if W.TrackPosition(win, prefs) then W.SavePrefs() end
end


-- "Next level: 80,000 XP (~1h 06m 40s at 72,000/h)", or why there is no estimate.
function W.NextLevelText(progress, ratePerHour)
  local status, remaining, seconds = T.XP.NextLevel(progress, ratePerHour)
  if status == "eta" then
    return "Next level: " .. T.FormatNumber(remaining) .. " XP (about " .. T.FormatDuration(seconds)
      .. " at " .. rateText(ratePerHour) .. ")"
  elseif status == "norate" then
    local why = (type(ratePerHour) == "number" and ratePerHour < 0) and "losing XP" or "no XP gained yet"
    return "Next level: " .. T.FormatNumber(remaining) .. " XP (" .. why .. ")"
  elseif status == "cap" then
    return "Next level: max level"
  end
  return "Next level: --"
end

-- "Skill levels +3, deaths 1" for the session (pure).
function W.SessionExtra(s)
  local skills, deaths = s.skills or 0, s.deaths or 0
  return "Skill levels +" .. T.FormatNumber(skills) .. ", deaths " .. T.FormatNumber(deaths)
end

function W.Refresh()
  if not W.IsShown() then return end
  local s = T.session
  if not s then
    T.SetText(el.elapsed, "Waiting for character...")
    return
  end
  local now = T.Now()
  T.SetText(el.elapsed, "Session " .. T.FormatDuration(T.XP.Elapsed(s, now)))
  T.SetText(el.session_extra, W.SessionExtra(s))

  local progress = ShroudGetLevelProgress()
  for _, track in ipairs(T.XP.TRACKS) do
    local k = track.key
    local net = W.GetNet()
    fillChart(s, k, now, net)
    local sessionRate = T.XP.SessionRate(s, k, now, net)
    T.SetText(el[k .. "_gain"], T.XP.Signed(T.XP.Gained(s, k, net)) .. "  " .. rateText(sessionRate)
      .. "  (10m " .. rateText(T.XP.WindowRate(s, k, now, net)) .. ")")

    local p = progress and progress[track.progress]
    if type(p) == "table" and type(p.level) == "number" then
      local pct = math.max(0, math.min(1, tonumber(p.percent) or 0))
      T.SetText(el[k .. "_head"], string.format("%s  Lv %d  %.1f%%", track.name, math.floor(p.level), pct * 100))
      T.SetValue(el[k .. "_bar"], pct)
      T.SetText(el[k .. "_eta"], W.NextLevelText(p, sessionRate))
    else
      T.SetText(el[k .. "_head"], track.name .. "  Lv --")
      T.SetValue(el[k .. "_bar"], 0)
      T.SetText(el[k .. "_eta"], W.NextLevelText(nil, 0))
    end
  end
end
