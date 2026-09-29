-- Toolbox: compact.lua
-- The "XP" window (/toolbox xp; internally the compact window): session time, the
-- current adventurer and producer pools, and the XP earned on each over the last hour.
-- Shares the text size with the XP Detailed window; has its own open state and position.
--
-- Hovering it pops up the XP Detailed window (see hover.lua).
--
-- It can also be shown as a HUD strip instead of a window (prefs.hud; /toolbox xp hud): no
-- title bar or frame, moved by its grip like the other strips (Toolbox.Hud.TextStrip). The
-- strip keeps its own position (prefs.hx / hy); the window's (x / y) is left alone.

local T = Toolbox
local C = {}
Toolbox.Compact = C

local UI = Shroud.UI
local WINDOW_ID = "toolbox_compact"
local GUTTER = 8

local win = nil
local el = {}
local prefs = { open = false, hover = true, hud = false }
local strip = nil                     -- the HUD strip form (Toolbox.Hud.TextStrip), made in Init
C.HOME = { 40, 120 }

-- Hover pop-up of the XP Detailed window (Toolbox.Window).
local hover = T.Hover.New{
  name = "xp",
  enabled = function() return prefs.hover end,
  trigger = function() return C.IsShown() end,
  popup = {
    IsShown = function() return T.Window.IsShown() end,
    IsPopup = function() return T.Window.IsPopup() end,
    ShowPopup = function() return T.Window.ShowPopup() end,
    HidePopup = function() return T.Window.HidePopup() end,
  },
}

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
    id = WINDOW_ID, title = "XP",
    compact = prefs.compact == true,  -- API 19: the title bar only on hover, over the content (no fields in it)
    width = 190, height = 130, minWidth = 140, minHeight = 50,
    x = prefs.x or T.Window.DEFAULT_X, y = prefs.y or T.Window.DEFAULT_Y,   -- never nil in a spec
    escCloses = prefs.compact ~= true,  -- a compact window's close button only shows on hover
    onClose = function()
      prefs.open = false
      C.SavePrefs()
      hover:Clear("t:")
      T.Config.Sync()
    end,
    onHover = function(_, over) hover:Report("t:window", over) end,
    style = { paddingTop = 4, paddingBottom = 4 },
    children = {
      UI.Scroll{
        id = "body", style = { flexGrow = 1 },
        onHover = function(_, over) hover:Report("t:body", over) end,
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
  if prefs.hud then return prefs.open == true and strip ~= nil end
  return win ~= nil and win:IsShown()
end

-- The labels of the form in use (window or HUD strip).
local function active()
  if prefs.hud then return strip and strip.el or {} end
  return el
end

function C.Init()
  local saved = T.Load("compact")
  prefs = { open = false, hover = true, hud = false }
  if type(saved) == "table" then
    prefs.open = saved.open == true
    prefs.hover = saved.hover ~= false
    prefs.hud = saved.hud == true
    prefs.compact = saved.compact == true
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
    if type(saved.hx) == "number" and type(saved.hy) == "number" then prefs.hx, prefs.hy = saved.hx, saved.hy end
  end
  strip = T.Hud.TextStrip{ key = "xp", FRAME_ID = "toolbox_xp_hud", HOME = C.HOME, titleId = "elapsed",
    lines = LINES, hover = hover, prefs = prefs, save = C.SavePrefs,
    isShown = function() return prefs.hud and prefs.open == true end }
  T.Hud.Register("xp", strip)          -- built by Toolbox.Hud.Init, after this
  build()
  if prefs.open and not prefs.hud and not win:Show() then
    T.Print("XP window could not reopen yet; use /toolbox xp.")
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
    hover:Clear("t:")
  elseif prefs.hud then
    prefs.open = true
  elseif win:IsShown() or win:Show() then
    prefs.open = true
    C.Refresh()
  else
    T.Print("The XP window can't reopen right now; try again in a few seconds.")
    ok = false
  end
  C.SavePrefs()
  T.Hud.Refresh()
  C.Refresh()
  T.Config.Sync()
  return ok
end

function C.Toggle()
  return C.SetOpen(not C.IsShown())
end

-- Shows the XP window as a HUD strip (true) or a window (false); open or closed stays as it was.
-- Returns false when the window can't reopen yet (the game refuses a Show soon after a close).
function C.SetHud(on)
  on = on == true
  if on == prefs.hud then return true end
  local open = C.IsShown()
  hover:Clear("t:")
  prefs.hud = on
  local ok = true
  if on then
    if win then win:Hide() end
    prefs.open = open
  elseif open then
    if not win then build() end
    ok = win:IsShown() or win:Show()
    if not ok then T.Print("The XP window can't reopen right now; try again in a few seconds.") end
    prefs.open = ok
  end
  C.SavePrefs()
  T.Hud.Build(true)                   -- the HUD strip exists only in the HUD form (8 HUD frames per add-on)
  T.Hud.Refresh()
  C.Refresh()
  T.Config.Sync()
  return ok
end

function C.GetHud()
  return prefs.hud
end

-- The window form as a compact window (API 19: its title bar shows only on hover, laid over the content)
-- or a normal one. A window's fields are fixed when it's made, so it is rebuilt; open stays open.
function C.SetCompact(on)
  on = on == true
  if on == (prefs.compact == true) then return true end
  local open = not prefs.hud and win ~= nil and win:IsShown()
  hover:Clear("t:")
  if win then pcall(function() win:Destroy() end) end
  win = nil
  prefs.compact = on
  build()
  local ok = true
  if open then
    ok = win:Show() ~= false
    if not ok then T.Print("The XP window can't reopen right now; try again in a few seconds.") end
    prefs.open = ok
  end
  C.SavePrefs()
  C.ApplyText()
  C.Refresh()
  T.Config.Sync()
  return ok
end

function C.GetCompact() return prefs.compact == true end

-- The strip's position (for /toolbox xp move); nil while it isn't laid out.
function C.GetPosition()
  if not strip then return nil end
  return strip.GetPosition()          -- both numbers ("strip and ..." would keep only x)
end
function C.MoveTo(x, y) return strip ~= nil and strip.MoveTo(x, y) end

-- ---------------------------------------------------------------------------
-- Hover pop-up
-- ---------------------------------------------------------------------------

-- Hover report from an element of the XP Detailed window (key without prefix).
function C.PopupHover(key, over)
  hover:Report("p:" .. key, over)
end

-- The XP Detailed window was closed by the player.
function C.PopupClosed()
  hover:Clear("p:")
end

function C.SetHover(on)
  prefs.hover = on == true
  C.SavePrefs()
  if not prefs.hover then hover:Cancel() end
  T.Config.Sync()
end

function C.GetHover()
  return prefs.hover
end

-- Follows the XP Detailed window's text size and line spacing (called from Toolbox.Window.ApplyText).
function C.ApplyText()
  if strip then strip.ApplyText() end
  if not win then return end
  local style = T.Window.LineStyle()
  for _, id in ipairs(TEXT_IDS) do el[id]:SetStyle(style) end
end

function C.SampleLabel()
  return C.IsShown() and active().elapsed or nil
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
  local e = active()
  if not C.IsShown() or not e.elapsed then return end
  local s = T.session
  if not s then
    T.SetText(e.elapsed, "Waiting for character...")
    return
  end
  local now = T.Now()
  T.SetText(e.elapsed, "Session " .. T.FormatDuration(T.XP.Elapsed(s, now)))

  local adv = pool(ShroudGetPooledAdventurerExperience)
  local prod = pool(ShroudGetPooledProducerExperience)
  T.SetText(e.a_pool, adv and T.FormatNumber(adv) or "--")
  T.SetText(e.p_pool, prod and T.FormatNumber(prod) or "--")
  local net = T.Window.GetNet()
  T.SetText(e.a_hour, T.XP.Signed(T.XP.LastHour(s, "a", now, net)))
  T.SetText(e.p_hour, T.XP.Signed(T.XP.LastHour(s, "p", now, net)))
end
