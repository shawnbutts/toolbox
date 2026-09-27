-- Toolbox: compact.lua
-- The compact XP window (/toolbox compact): session time, the current adventurer
-- and producer pools, and the XP earned on each over the last hour.
-- Shares the text size with the Session XP window; has its own open state and position.
--
-- Hovering it pops up the Session XP window after C.HOVER_SHOW_DELAY seconds. The
-- pop-up stays while the pointer is over either window (so its Reset button can be
-- used) and closes C.HOVER_HIDE_DELAY seconds after the pointer has left both.

local T = Toolbox
local C = {}
Toolbox.Compact = C

local UI = Shroud.UI
local WINDOW_ID = "toolbox_compact"
local GUTTER = 8

C.HOVER_SHOW_DELAY = 0.5   -- passing over the window on the way elsewhere does nothing
C.HOVER_HIDE_DELAY = 0.75  -- time to cross from the compact window to the pop-up

local SHOW_TIMER = "toolbox_hover_show"
local HIDE_TIMER = "toolbox_hover_hide"

local win = nil
local el = {}
local prefs = { open = false, hover = true }
local hovered = {}         -- hover keys currently reporting "over" (see C.PopupHover)
local showPending = false  -- the show timer is running

-- id, left text, theme class for both cells, indented under the line above
local LINES = {
  { id = "a_pool", label = "Adv pool", class = "text" },
  { id = "a_hour", label = "Last hour", class = "text", indent = true },
  { id = "p_pool", label = "Prod pool", class = "text" },
  { id = "p_hour", label = "Last hour", class = "text", indent = true },
}
local TEXT_IDS = { "elapsed" }
for _, line in ipairs(LINES) do
  TEXT_IDS[#TEXT_IDS + 1] = line.id .. "_label"
  TEXT_IDS[#TEXT_IDS + 1] = line.id
end

-- A label on the left and a right-aligned value.
local function line(spec)
  local W = T.Window
  return UI.Row{ style = { alignItems = "center" }, children = {
    UI.Label{ id = spec.id .. "_label", text = spec.label, class = spec.class,
      style = W.TextStyle{ flexGrow = 1, paddingLeft = spec.indent and 10 or 0 } },
    UI.Label{ id = spec.id, text = "", class = spec.class, style = W.TextStyle{ textAlign = "right" } },
  } }
end

local function build()
  local rows = { UI.Label{ id = "elapsed", text = "", class = "title", style = T.Window.TextStyle() } }
  for _, spec in ipairs(LINES) do rows[#rows + 1] = line(spec) end

  win = UI.Window{
    id = WINDOW_ID, title = "Compact XP",
    width = 190, height = 130, minWidth = 140, minHeight = 50,
    x = prefs.x, y = prefs.y,
    escCloses = true,
    onClose = function()
      prefs.open = false
      C.SavePrefs()
      C.ClearHover("compact_")
      T.Config.Sync()
    end,
    onHover = function(_, over) C.PopupHover("compact_window", over) end,
    style = { paddingTop = 4, paddingBottom = 4 },
    children = {
      UI.Scroll{
        id = "body", style = { flexGrow = 1 },
        onHover = function(_, over) C.PopupHover("compact_body", over) end,
        children = {
          UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = rows },
        } },
    },
  }
  el = {}
  for _, id in ipairs(TEXT_IDS) do el[id] = win:Find(id) end
end

function C.SavePrefs()
  T.Save("compact", prefs)
end

function C.IsShown()
  return win ~= nil and win:IsShown()
end

function C.Init()
  local saved = T.Load("compact")
  prefs = { open = false, hover = true }
  hovered = {}
  if type(saved) == "table" then
    prefs.open = saved.open == true
    prefs.hover = saved.hover ~= false
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
  end
  build()
  if prefs.open and not win:Show() then
    T.Print("Compact XP window could not reopen yet; use /toolbox compact.")
  end
  C.Refresh()
end

-- Opens or closes the window and remembers the choice. Returns true when the
-- window ends up in the requested state.
function C.SetOpen(open)
  if not win then build() end
  local ok = true
  if not open then
    win:Hide()
    prefs.open = false
    C.ClearHover("compact_")
  elseif win:IsShown() or win:Show() then
    prefs.open = true
    C.Refresh()
  else
    T.Print("The compact window can't reopen right now; try again in a few seconds.")
    ok = false
  end
  C.SavePrefs()
  T.Config.Sync()
  return ok
end

function C.Toggle()
  return C.SetOpen(not C.IsShown())
end

-- ---------------------------------------------------------------------------
-- Hover pop-up
-- ---------------------------------------------------------------------------
-- Several elements report hover (each window and its sections) because the docs
-- don't say whether moving onto a child counts as leaving the parent. "Hovering"
-- means any key is over; the delays absorb flicker between them.

local function anyHovered(prefix)
  for key in pairs(hovered) do
    if not prefix or key:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local function onShowTimer()
  if prefs.hover and C.IsShown() and anyHovered("compact_") then T.Window.ShowPopup() end
end

local function onHideTimer()
  if not anyHovered() then T.Window.HidePopup() end
end

local function update()
  if anyHovered() then
    ShroudRemovePeriodic(HIDE_TIMER)
    if prefs.hover and anyHovered("compact_") and not T.Window.IsShown() then
      -- Registering the same name again restarts it, so only start it once per hover.
      if not showPending then
        showPending = true
        ShroudRegisterPeriodic(SHOW_TIMER, function() showPending = false; onShowTimer() end,
          C.HOVER_SHOW_DELAY, false)
      end
    end
  else
    ShroudRemovePeriodic(SHOW_TIMER)
    showPending = false
    if T.Window.IsPopup() then
      ShroudRegisterPeriodic(HIDE_TIMER, onHideTimer, C.HOVER_HIDE_DELAY, false)
    end
  end
end

-- Hover report from an element of either window. key starts with "compact_" or "xp_".
function C.PopupHover(key, over)
  hovered[key] = over and true or nil
  update()
end

-- Forgets hover keys starting with prefix (a window closed under the pointer
-- reports no "left" event we can rely on).
function C.ClearHover(prefix)
  for key in pairs(hovered) do
    if key:sub(1, #prefix) == prefix then hovered[key] = nil end
  end
  update()
end

-- The Session XP window was closed by the player.
function C.PopupClosed()
  C.ClearHover("xp_")
end

function C.SetHover(on)
  prefs.hover = on == true
  C.SavePrefs()
  if not prefs.hover then
    ShroudRemovePeriodic(SHOW_TIMER)
    showPending = false
    T.Window.HidePopup()
  end
  T.Config.Sync()
end

function C.GetHover()
  return prefs.hover
end

-- Follows the Session XP window's text size and line spacing (called from Toolbox.Window.ApplyText).
function C.ApplyText()
  if not win then return end
  local style = { fontSize = T.Window.GetFont(), height = T.Window.LineHeight() }
  for _, id in ipairs(TEXT_IDS) do el[id]:SetStyle(style) end
end

function C.Track()
  if T.Window.TrackPosition(win, prefs) then C.SavePrefs() end
end

-- Current pool; 0 without a character, per the docs.
local function pool(fn)
  local n = fn()
  if type(n) ~= "number" or n < 0 then return nil end
  return n
end

function C.Refresh()
  if not C.IsShown() then return end
  local s = T.session
  if not s then
    el.elapsed:SetText("Waiting for character...")
    return
  end
  local now = T.Now()
  el.elapsed:SetText("Session " .. T.FormatDuration(T.XP.Elapsed(s, now)))

  local adv = pool(ShroudGetPooledAdventurerExperience)
  local prod = pool(ShroudGetPooledProducerExperience)
  el.a_pool:SetText(adv and T.FormatNumber(adv) or "--")
  el.p_pool:SetText(prod and T.FormatNumber(prod) or "--")
  el.a_hour:SetText("+" .. T.FormatNumber(T.XP.LastHour(s, "a", now)))
  el.p_hour:SetText("+" .. T.FormatNumber(T.XP.LastHour(s, "p", now)))
end
