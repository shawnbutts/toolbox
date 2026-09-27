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

-- A labelled slider: "Label ........ value" then the slider.
local function slider(id, label, lo, hi, step, value, tooltip, onChange)
  return UI.Column{ style = { marginTop = 4 }, children = {
    UI.Row{ style = { alignItems = "center" }, children = {
      UI.Label{ text = label, class = "text", style = { flexGrow = 1 } },
      UI.Label{ id = id .. "_value", text = fontLabel(value), class = "dim" },
    } },
    UI.Slider{ id = id, min = lo, max = hi, step = step, value = value, tooltip = tooltip,
      onChange = function(_, v) onChange(math.floor((tonumber(v) or value) + 0.5)) end },
  } }
end

local function soundRows(def)
  local S = T.Sounds
  return UI.Column{ style = { marginTop = 4 }, children = {
    UI.Label{ id = "snd_" .. def.key .. "_status", text = "", class = "dim" },
    UI.Row{ style = { alignItems = "center" }, children = {
      UI.TextField{ id = "snd_" .. def.key .. "_path", text = S.GetPath(def.key),
        placeholder = "custom file in your Lua folder", maxLength = 200, style = { flexGrow = 1, flexShrink = 1 },
        tooltip = "A .ogg/.wav/.mp3 path inside your Lua folder; press Enter to use it, clear it for the default",
        onSubmit = function(_, text) S.SetPath(def.key, text) end },
      UI.Button{ id = "snd_" .. def.key .. "_test", text = "Test", style = { marginLeft = 4 },
        tooltip = "Play " .. def.label:lower(),
        onClick = function() S.Test(def.key) end },
    } },
  } }
end

-- The "Buff bar" part of the settings (built inside build()).
function C.BuffBarSection()
  local B, S = T.BuffBar, T.Sounds
  local children = {
    UI.Label{ text = "Buff bar", class = "heading", style = { marginTop = 8 } },
    UI.Toggle{ id = "show_buffs", text = "Show buff bar", value = B.IsShown(),
      onChange = function(_, v) B.SetShown(v) end },
    UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
      UI.Label{ text = "Position", class = "text", style = { flexGrow = 1 },
        tooltip = "Or drag the grip at the bar's top-left corner (unlock the HUD in the game's settings to see it)" },
      UI.Label{ id = "buff_pos", text = "", class = "dim" },
    } },
    UI.Row{ style = { marginTop = 2 }, children = {
      UI.Button{ id = "buff_left", text = "<", tooltip = "Move left " .. B.NUDGE .. " px",
        onClick = function() B.Nudge(-B.NUDGE, 0) end },
      UI.Button{ id = "buff_up", text = "^", tooltip = "Move up " .. B.NUDGE .. " px",
        style = { marginLeft = 2 }, onClick = function() B.Nudge(0, -B.NUDGE) end },
      UI.Button{ id = "buff_down", text = "v", tooltip = "Move down " .. B.NUDGE .. " px",
        style = { marginLeft = 2 }, onClick = function() B.Nudge(0, B.NUDGE) end },
      UI.Button{ id = "buff_right", text = ">", tooltip = "Move right " .. B.NUDGE .. " px",
        style = { marginLeft = 2 }, onClick = function() B.Nudge(B.NUDGE, 0) end },
      UI.Button{ id = "buff_reset", text = "Reset", tooltip = "Put the bar back where it started",
        style = { marginLeft = 6 }, onClick = function() B.ResetPosition() end },
    } },
    slider("buff_size", "Icon size", B.SIZE_MIN, B.SIZE_MAX, 1, B.GetSize(),
      "Buff icon size in pixels", function(n) B.SetSize(n) end),
    UI.Toggle{ id = "expire_alert", text = "Sound when a buff is about to run out", value = B.GetExpireAlert(),
      style = { marginTop = 6 }, onChange = function(_, v) B.SetExpireAlert(v) end },
    slider("expire_seconds", "Seconds before it runs out", B.ALERT_MIN, B.ALERT_MAX, 1, B.GetExpireSeconds(),
      "How long before a buff ends to play the alert", function(n) B.SetExpireSeconds(n) end),
    UI.Toggle{ id = "debuff_alert", text = "Sound when a debuff lands", value = B.GetDebuffAlert(),
      style = { marginTop = 6 }, onChange = function(_, v) B.SetDebuffAlert(v) end },
    slider("volume", "Alert volume", 0, 100, 5, S.GetVolume(), "0 mutes the alerts",
      function(n) S.SetVolume(n) end),
  }
  for _, def in ipairs(S.DEFS) do children[#children + 1] = soundRows(def) end
  return UI.Column{ children = children }
end

local function build()
  local W = T.Window
  win = UI.Window{
    id = WINDOW_ID, title = "Toolbox Settings",
    width = 280, height = 460, minWidth = 220, minHeight = 120,
    escCloses = true,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = { UI.Scroll{ style = { flexGrow = 1 }, children = {
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
        C.BuffBarSection(),
      } },
    } } },
  }
  el = {}
  local ids = { "font", "font_value", "spacing", "spacing_value", "show_xp", "show_compact", "show_daily",
                "show_daily_detail", "hover_popup", "hover_daily",
                "show_buffs", "buff_size", "buff_size_value", "expire_alert", "expire_seconds",
                "expire_seconds_value", "debuff_alert", "volume", "volume_value", "buff_pos" }
  for _, def in ipairs(T.Sounds.DEFS) do
    ids[#ids + 1] = "snd_" .. def.key .. "_status"
    ids[#ids + 1] = "snd_" .. def.key .. "_path"
  end
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
  local B, S = T.BuffBar, T.Sounds
  el.show_buffs:SetValue(B.IsShown())
  for id, v in pairs({ buff_size = B.GetSize(), expire_seconds = B.GetExpireSeconds(), volume = S.GetVolume() }) do
    el[id]:SetValue(v)
    el[id .. "_value"]:SetText(fontLabel(v))
  end
  el.expire_alert:SetValue(B.GetExpireAlert())
  el.debuff_alert:SetValue(B.GetDebuffAlert())
  C.SyncLive()
end

-- Things that change without a setter being called (sound loads settling, the bar being
-- dragged by its grip); called once a tick from Toolbox.Tick, and from Sync.
function C.SyncLive()
  if not win then return end
  C.SyncSounds()
  local x, y = T.BuffBar.GetPosition()
  el.buff_pos:SetText(x and (x .. ", " .. y) or "")
end

-- Sound status lines ("Buff expiring: playing toolbox_buff_expiring.ogg"). Path fields are
-- left alone so typing isn't overwritten.
function C.SyncSounds()
  if not win then return end
  for _, def in ipairs(T.Sounds.DEFS) do
    local status, path = T.Sounds.Status(def.key)
    local text = def.label .. ": " .. (status == "ready" and path or status == "loading" and "looking..." or "no file")
    el["snd_" .. def.key .. "_status"]:SetText(text)
  end
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
