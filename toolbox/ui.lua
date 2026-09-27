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
local TEXT_IDS = { "elapsed" }
for _, track in ipairs(T.XP.TRACKS) do
  for _, suffix in ipairs({ "_head", "_gain", "_eta" }) do TEXT_IDS[#TEXT_IDS + 1] = track.key .. suffix end
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

-- Height of one text line at the current font size and spacing.
function W.LineHeight()
  return math.ceil(fontSize() * 1.15) + spacing()
end

-- Size and line height for a text label. The height is pinned with minHeight and
-- maxHeight too: a theme class can set its own minimum height, which would win over
-- a smaller `height` and make small spacing values do nothing.
function W.LineStyle()
  local h = W.LineHeight()
  return { fontSize = fontSize(), height = h, minHeight = h, maxHeight = h }
end

-- Style for a text label: LineStyle plus no vertical margins or padding.
-- `extra` adds or overrides keys. Shared with the other windows.
function W.TextStyle(extra)
  local style = W.LineStyle()
  style.marginTop, style.marginBottom, style.paddingTop, style.paddingBottom = 0, 0, 0, 0
  for k, v in pairs(extra or {}) do style[k] = v end
  return style
end

local function barHeight()
  return math.max(4, math.floor(fontSize() / 2))
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
    } }
end

local function build()
  local f = fontSize()
  local rows = {}
  for _, track in ipairs(T.XP.TRACKS) do rows[#rows + 1] = trackRows(track) end

  win = UI.Window{
    id = WINDOW_ID, title = "XP Detailed",
    -- Only the first open uses width/height: the host remembers the size the player drags it to.
    width = 250, height = 200, minWidth = 160, minHeight = 60,
    x = prefs.x, y = prefs.y,
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
  local saved = T.Load("window")
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
  end
  build()
  if prefs.open then
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

-- Moves a HUD frame from settings or chat (its own grip is hidden while the game's "Lock
-- Status Movement" is on). getFrame() returns the frame or nil; home = { x, y } for Reset.
-- Returns { Get, MoveTo, Nudge, Reset }. The game keeps HUD frames on screen, and
-- SetPosition "remembers the new spot as the player's".
function W.HudMover(getFrame, home)
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

  function m.Nudge(dx, dy)
    local x, y = m.Get()
    if not x then x, y = home[1], home[2] end
    return m.MoveTo(x + dx, y + dy)
  end

  function m.Reset()
    return m.MoveTo(home[1], home[2])
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
    return "Next level: " .. T.FormatNumber(remaining) .. " XP (~" .. T.FormatDuration(seconds)
      .. " at " .. rateText(ratePerHour) .. ")"
  elseif status == "norate" then
    return "Next level: " .. T.FormatNumber(remaining) .. " XP (no XP gained yet)"
  elseif status == "cap" then
    return "Next level: max level"
  end
  return "Next level: --"
end

function W.Refresh()
  if not W.IsShown() then return end
  local s = T.session
  if not s then
    el.elapsed:SetText("Waiting for character...")
    return
  end
  local now = T.Now()
  el.elapsed:SetText("Session " .. T.FormatDuration(T.XP.Elapsed(s, now)))

  local progress = ShroudGetLevelProgress()
  for _, track in ipairs(T.XP.TRACKS) do
    local k = track.key
    local sessionRate = T.XP.SessionRate(s, k, now)
    el[k .. "_gain"]:SetText("+" .. T.FormatNumber(T.XP.Gained(s, k)) .. "  " .. rateText(sessionRate)
      .. "  (10m " .. rateText(T.XP.WindowRate(s, k, now)) .. ")")

    local p = progress and progress[track.progress]
    if type(p) == "table" and type(p.level) == "number" then
      local pct = math.max(0, math.min(1, tonumber(p.percent) or 0))
      el[k .. "_head"]:SetText(string.format("%s  Lv %d  %.1f%%", track.name, math.floor(p.level), pct * 100))
      el[k .. "_bar"]:SetValue(pct)
      el[k .. "_eta"]:SetText(W.NextLevelText(p, sessionRate))
    else
      el[k .. "_head"]:SetText(track.name .. "  Lv --")
      el[k .. "_bar"]:SetValue(0)
      el[k .. "_eta"]:SetText(W.NextLevelText(nil, 0))
    end
  end
end
