-- Toolbox: config.lua
-- The "Toolbox Settings" window (/toolbox config). Each control reads its value
-- from the owning module and writes back through that module's setter, so the
-- settings live in one place and the matching chat commands keep working.

local T = Toolbox
local C = {}
Toolbox.Config = C

local UI = Shroud.UI
local WINDOW_ID = "toolbox_config"
local GUTTER = 10

local win = nil
local el = {}

local function fontLabel(n)
  return string.format("%d", n)
end

local function build()
  local W = T.Window
  win = UI.Window{
    id = WINDOW_ID, title = "Toolbox Settings",
    width = 260, height = 330, minWidth = 200, minHeight = 120,
    escCloses = true,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = {
      UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = {
        UI.Label{ text = "XP windows", class = "heading" },
        UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
          UI.Label{ text = "Text size", class = "text", style = { flexGrow = 1 } },
          UI.Label{ id = "font_value", text = fontLabel(W.GetFont()), class = "dim" },
        } },
        UI.Slider{
          id = "font", min = W.FONT_MIN, max = W.FONT_MAX, step = 1, value = W.GetFont(),
          tooltip = "Text size of the XP windows (" .. W.FONT_MIN .. "-" .. W.FONT_MAX .. ")",
          onChange = function(_, value) C.OnFont(value) end,
        },
        UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
          UI.Label{ text = "Line spacing", class = "text", style = { flexGrow = 1 } },
          UI.Label{ id = "spacing_value", text = fontLabel(W.GetSpacing()), class = "dim" },
        } },
        UI.Slider{
          id = "spacing", min = W.SPACING_MIN, max = W.SPACING_MAX, step = 1, value = W.GetSpacing(),
          tooltip = "Extra pixels between lines in the XP windows (" .. W.SPACING_MIN .. "-" .. W.SPACING_MAX .. ")",
          onChange = function(_, value) C.OnSpacing(value) end,
        },
        UI.Toggle{
          id = "show_compact", text = "Show XP window", value = T.Compact.IsShown(),
          style = { marginTop = 6 },
          onChange = function(_, value) C.OnShowCompact(value) end,
        },
        UI.Toggle{
          id = "show_xp", text = "Show XP Detailed window", value = W.IsOpen(),
          onChange = function(_, value) C.OnShowXP(value) end,
        },
        UI.Toggle{
          id = "show_daily", text = "Show daily stats window", value = T.Daily.IsShown(),
          onChange = function(_, value) C.OnShowDaily(value) end,
        },
        UI.Toggle{
          id = "show_daily_detail", text = "Show Today Detailed window", value = T.DailyDetail.IsOpen(),
          onChange = function(_, value) C.OnShowDailyDetail(value) end,
        },
        UI.Toggle{
          id = "hover_popup", text = "Show XP Detailed on hover", value = T.Compact.GetHover(),
          tooltip = "Hovering the XP window pops up the XP Detailed window",
          onChange = function(_, value) T.Compact.SetHover(value) end,
        },
        UI.Toggle{
          id = "hover_daily", text = "Show Today Detailed on hover", value = T.Daily.GetHover(),
          tooltip = "Hovering the Today window pops up the Today Detailed window",
          onChange = function(_, value) T.Daily.SetHover(value) end,
        },
      } },
    },
  }
  el = {}
  local ids = { "font", "font_value", "spacing", "spacing_value", "show_xp", "show_compact", "show_daily",
                "show_daily_detail", "hover_popup", "hover_daily" }
  for _, id in ipairs(ids) do el[id] = win:Find(id) end
end

-- Player dragged the slider. Steps are 1, but round anyway: the value is a float.
function C.OnFont(value)
  local n = math.floor((tonumber(value) or T.Window.GetFont()) + 0.5)
  T.Window.SetFont(n)
end

-- Player dragged the line spacing slider.
function C.OnSpacing(value)
  local n = math.floor((tonumber(value) or T.Window.GetSpacing()) + 0.5)
  T.Window.SetSpacing(n)
end

-- Player ticked or unticked the checkbox.
function C.OnShowXP(value)
  if not T.Window.SetOpen(value == true) then
    el.show_xp:SetValue(T.Window.IsOpen())   -- Show() was refused; put the box back
  end
end

-- Player ticked or unticked the compact window's checkbox.
function C.OnShowCompact(value)
  if not T.Compact.SetOpen(value == true) then
    el.show_compact:SetValue(T.Compact.IsShown())
  end
end

function C.OnShowDaily(value)
  if not T.Daily.SetOpen(value == true) then
    el.show_daily:SetValue(T.Daily.IsShown())
  end
end

function C.OnShowDailyDetail(value)
  if not T.DailyDetail.SetOpen(value == true) then
    el.show_daily_detail:SetValue(T.DailyDetail.IsOpen())
  end
end

-- Brings the controls in line with the current settings. Our own SetValue calls
-- never fire the onChange handlers, so this cannot loop.
function C.Sync()
  if not win then return end
  local font = T.Window.GetFont()
  el.font:SetValue(font)
  el.font_value:SetText(fontLabel(font))
  local spacing = T.Window.GetSpacing()
  el.spacing:SetValue(spacing)
  el.spacing_value:SetText(fontLabel(spacing))
  el.show_xp:SetValue(T.Window.IsOpen())
  el.show_compact:SetValue(T.Compact.IsShown())
  el.show_daily:SetValue(T.Daily.IsShown())
  el.show_daily_detail:SetValue(T.DailyDetail.IsOpen())
  el.hover_popup:SetValue(T.Compact.GetHover())
  el.hover_daily:SetValue(T.Daily.GetHover())
end

function C.IsShown()
  return win ~= nil and win:IsShown()
end

function C.Toggle()
  if not win then build() end
  if win:IsShown() then
    win:Hide()
  elseif win:Show() then
    C.Sync()
  else
    T.Print("The settings window can't reopen right now; try again in a few seconds.")
  end
end
