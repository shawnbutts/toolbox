-- Toolbox: ui.lua
-- The "Session XP" window, built with Shroud.UI. Updated from the 1-second
-- periodic in core.lua, never per frame.

local T = Toolbox
local W = {}
Toolbox.Window = W

local UI = Shroud.UI   -- reading Shroud.UI at top level is allowed; constructors are not
local WINDOW_ID = "toolbox_xp"

local win = nil        -- window handle, rebuilt in ShroudOnStart after every reload
local el = {}          -- element handles by id
local prefs = { open = false }

W.FONT_MIN, W.FONT_MAX, W.FONT_DEFAULT = 9, 32, 12   -- fontSize range from the Shroud.UI docs

-- Elements whose text size follows prefs.font.
local TEXT_IDS = { "elapsed", "reset" }
for _, track in ipairs(T.XP.TRACKS) do
  for _, suffix in ipairs({ "_head", "_gain", "_eta" }) do TEXT_IDS[#TEXT_IDS + 1] = track.key .. suffix end
end

-- Side gutter, set on each section rather than relying on the window body's padding
-- reaching inside the Scroll (the progress bars ran to the window edge without it).
W.GUTTER = 10

local function fontSize()
  return prefs.font or W.FONT_DEFAULT
end

local function barHeight()
  return math.max(4, math.floor(fontSize() / 2))
end

local function trackRows(track)
  local k = track.key
  local f = fontSize()
  return UI.Column{ style = { marginTop = 4, paddingLeft = W.GUTTER, paddingRight = W.GUTTER }, children = {
    UI.Label{ id = k .. "_head", text = track.name, class = "heading", style = { fontSize = f } },
    UI.Bar{ id = k .. "_bar", value = 0, color = "@gold", style = { height = barHeight() } },
    UI.Label{ id = k .. "_gain", text = "", class = "text", style = { fontSize = f } },
    UI.Label{ id = k .. "_eta", text = "", class = "dim", style = { fontSize = f } },
  } }
end

local function build()
  local f = fontSize()
  local rows = {}
  for _, track in ipairs(T.XP.TRACKS) do rows[#rows + 1] = trackRows(track) end

  win = UI.Window{
    id = WINDOW_ID, title = "Session XP",
    -- Only the first open uses width/height: the host remembers the size the player drags it to.
    width = 250, height = 200, minWidth = 160, minHeight = 100,
    x = prefs.x, y = prefs.y,
    escCloses = true,
    onClose = function()
      prefs.open = false
      W.SavePrefs()
    end,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = {
      UI.Row{
        style = { alignItems = "center", paddingLeft = W.GUTTER, paddingRight = W.GUTTER },
        children = {
          UI.Label{ id = "elapsed", text = "", class = "title", style = { fontSize = f, flexGrow = 1 } },
          UI.Button{ id = "reset", text = "Reset", tooltip = "Start a new XP session", style = { fontSize = f },
            onClick = function() T.Dispatch("reset") end },
        },
      },
      -- Scrolls when the player makes the window smaller than its content.
      UI.Scroll{ style = { flexGrow = 1 }, children = rows },
    },
  }

  el = {}
  for _, id in ipairs(TEXT_IDS) do el[id] = win:Find(id) end
  for _, track in ipairs(T.XP.TRACKS) do el[track.key .. "_bar"] = win:Find(track.key .. "_bar") end
end

-- Sets the text size (W.FONT_MIN..W.FONT_MAX) and remembers it. Returns false when out of range.
function W.SetFont(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < W.FONT_MIN or n > W.FONT_MAX then return false end
  prefs.font = n
  W.SavePrefs()
  if win then
    for _, id in ipairs(TEXT_IDS) do el[id]:SetStyle{ fontSize = n } end
    for _, track in ipairs(T.XP.TRACKS) do el[track.key .. "_bar"]:SetStyle{ height = barHeight() } end
  end
  return true
end

function W.GetFont()
  return fontSize()
end

function W.SavePrefs()
  T.Save("window", prefs)
end

function W.IsShown()
  return win ~= nil and win:IsShown()
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
  end
  build()
  if prefs.open then
    if not win:Show() then T.Print("Session XP window could not reopen yet; use /toolbox xp.") end
  end
  W.Refresh()
end

function W.Toggle()
  if not win then build() end
  if win:IsShown() then
    win:Hide()
    prefs.open = false
  elseif win:Show() then
    prefs.open = true
    W.Refresh()
  else
    -- Show() is refused within 3 s of the player closing it, or more than 5 times in 10 s.
    T.Print("The window can't reopen right now; try again in a few seconds.")
  end
  W.SavePrefs()
end

-- Remembers where the player left the window (checked once a second).
function W.Track()
  if not W.IsShown() then return end
  local x, y = win:GetPosition()
  if type(x) ~= "number" or type(y) ~= "number" then return end
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  if x ~= prefs.x or y ~= prefs.y then
    prefs.x, prefs.y = x, y
    W.SavePrefs()
  end
end

local function rateText(n)
  return T.FormatNumber(n) .. "/h"
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
