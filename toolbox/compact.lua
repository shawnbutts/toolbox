-- Toolbox: compact.lua
-- The "XP" window (/toolbox xp; internally the compact window): session time, the
-- current adventurer and producer pools, and the XP earned on each over the last hour.
-- Shares the text size with the XP Detailed window; has its own open state and position.
--
-- Hovering it pops up the XP Detailed window (see hover.lua).

local T = Toolbox
local C = {}
Toolbox.Compact = C

local UI = Shroud.UI
local WINDOW_ID = "toolbox_compact"
local GUTTER = 8

local win = nil
local el = {}
local prefs = { open = false, hover = true }

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
    width = 190, height = 130, minWidth = 140, minHeight = 50,
    x = prefs.x, y = prefs.y,
    escCloses = true,
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
  return win ~= nil and win:IsShown()
end

function C.Init()
  local saved = T.Load("compact")
  prefs = { open = false, hover = true }
  if type(saved) == "table" then
    prefs.open = saved.open == true
    prefs.hover = saved.hover ~= false
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
  end
  build()
  if prefs.open and not win:Show() then
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
  elseif win:IsShown() or win:Show() then
    prefs.open = true
    C.Refresh()
  else
    T.Print("The XP window can't reopen right now; try again in a few seconds.")
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
  if not win then return end
  local style = T.Window.LineStyle()
  for _, id in ipairs(TEXT_IDS) do el[id]:SetStyle(style) end
end

function C.SampleLabel()
  return C.IsShown() and el.elapsed or nil
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
