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

local function trackRows(track)
  local k = track.key
  return UI.Column{ style = { marginBottom = 6 }, children = {
    UI.Label{ id = k .. "_head", text = track.name, class = "heading" },
    UI.Label{ id = k .. "_gain", text = "", class = "text" },
    UI.Label{ id = k .. "_rate", text = "", class = "dim" },
    UI.Label{ id = k .. "_level", text = "", class = "text" },
    UI.Bar{ id = k .. "_bar", value = 0, color = "@gold" },
    UI.Label{ id = k .. "_eta", text = "", class = "dim" },
  } }
end

local function build()
  local children = { UI.Label{ id = "elapsed", text = "", class = "title" } }
  for _, track in ipairs(T.XP.TRACKS) do children[#children + 1] = trackRows(track) end
  children[#children + 1] = UI.Row{ style = { justifyContent = "end" }, children = {
    UI.Button{ id = "reset", text = "Reset", tooltip = "Start a new XP session",
      onClick = function() T.Dispatch("reset") end },
  } }

  win = UI.Window{
    id = WINDOW_ID, title = "Session XP",
    width = 320, height = 360, minWidth = 260, minHeight = 300,
    x = prefs.x, y = prefs.y,
    escCloses = true,
    onClose = function()
      prefs.open = false
      W.SavePrefs()
    end,
    style = { padding = 8 },
    children = children,
  }

  el = {}
  local ids = { "elapsed", "reset" }
  for _, track in ipairs(T.XP.TRACKS) do
    for _, suffix in ipairs({ "_gain", "_rate", "_level", "_bar", "_eta" }) do
      ids[#ids + 1] = track.key .. suffix
    end
  end
  for _, id in ipairs(ids) do el[id] = win:Find(id) end
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

function W.Refresh()
  if not W.IsShown() then return end
  local s = T.session
  if not s then
    el.elapsed:SetText("Waiting for character data...")
    return
  end
  local now = T.Now()
  el.elapsed:SetText("Session: " .. T.FormatDuration(T.XP.Elapsed(s, now)))

  local progress = ShroudGetLevelProgress()
  for _, track in ipairs(T.XP.TRACKS) do
    local k = track.key
    local sessionRate = T.XP.SessionRate(s, k, now)
    el[k .. "_gain"]:SetText("Gained: " .. T.FormatNumber(T.XP.Gained(s, k)))
    el[k .. "_rate"]:SetText("Session " .. rateText(sessionRate)
      .. "  |  Last 10m " .. rateText(T.XP.WindowRate(s, k, now)))

    local p = progress and progress[track.progress]
    if type(p) == "table" and type(p.level) == "number" then
      local pct = math.max(0, math.min(1, tonumber(p.percent) or 0))
      el[k .. "_level"]:SetText(string.format("Level %d  |  %.1f%%", math.floor(p.level), pct * 100))
      el[k .. "_bar"]:SetValue(pct)
      local eta = T.XP.TimeToLevel(p, sessionRate)
      el[k .. "_eta"]:SetText("Next level: " .. (eta and ("~" .. T.FormatDuration(eta)) or "--"))
    else
      el[k .. "_level"]:SetText("Level: --")
      el[k .. "_bar"]:SetValue(0)
      el[k .. "_eta"]:SetText("Next level: --")
    end
  end
end
