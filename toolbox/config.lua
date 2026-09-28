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

-- "Position  x, y" and < ^ v > Reset buttons for a HUD strip. `m` has GetPosition, Nudge,
-- ResetPosition and NUDGE; ids are <prefix>_pos, _left, _up, _down, _right, _reset.
C.NUDGE = 10
function C.PositionRows(prefix, m)
  local n = C.NUDGE
  local function button(id, text, tip, fn, gap)
    return UI.Button{ id = prefix .. "_" .. id, text = text, tooltip = tip, style = { marginLeft = gap },
      onClick = fn }
  end
  return UI.Column{ children = {
    UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
      UI.Label{ text = "Position", class = "text", style = { flexGrow = 1 },
        tooltip = "Or drag the grip at its top-left corner. To see the grip, untick Lock Status Movement"
          .. " (Options > Interface > Nameplates & Chat Bubbles)." },
      UI.Label{ id = prefix .. "_pos", text = "", class = "dim" },
    } },
    UI.Row{ style = { marginTop = 2 }, children = {
      button("left", "<", "Move left " .. n .. " px", function() m.Nudge(-n, 0) end, 0),
      button("up", "^", "Move up " .. n .. " px", function() m.Nudge(0, -n) end, 2),
      button("down", "v", "Move down " .. n .. " px", function() m.Nudge(0, n) end, 2),
      button("right", ">", "Move right " .. n .. " px", function() m.Nudge(n, 0) end, 2),
      button("reset", "Reset", "Put it back where it started", function() m.ResetPosition() end, 6),
    } },
  } }
end

-- The "Health & focus bars" part of the settings.
function C.VitalsSection()
  local V = T.Vitals
  return UI.Column{ children = {
    UI.Label{ text = "Health & focus bars", class = "heading", style = { marginTop = 8 } },
    UI.Toggle{ id = "show_vitals", text = "Show health & focus bars", value = V.IsShown(),
      onChange = function(_, v) V.SetShown(v) end },
    UI.Toggle{ id = "vitals_glue", text = "Glue to the buff bar (one HUD)", value = T.Hud.IsGlued(),
      tooltip = "Health & focus on the left, buffs on the right, moved as one",
      onChange = function(_, v) T.Hud.SetGlued(v) end },
    slider("vitals_scale", "Size (%)", V.SCALE_MIN, V.SCALE_MAX, 5, V.GetScale(),
      "Scales the bars, their text and the gap together", function(n) V.SetScale(n) end),
    slider("vitals_width", "Bar length", V.WIDTH_MIN, V.WIDTH_MAX, 10, V.GetWidth(),
      "Length of the bars at 100% size, in pixels", function(n) V.SetWidth(n) end),
    UI.Toggle{ id = "vitals_show_bars", text = "Show bars", value = V.GetShowBars(),
      style = { marginTop = 6 }, onChange = function(_, v) V.SetShowBars(v) end },
    UI.Toggle{ id = "vitals_show_text", text = "Show numbers", value = V.GetShowText(),
      onChange = function(_, v) V.SetShowText(v) end },
    UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
      UI.Label{ text = "Number background", class = "text", style = { flexGrow = 1 } },
      UI.Dropdown{ id = "vitals_bg", choices = V.BackgroundNames(), value = V.GetBackground(),
        tooltip = "A dark or light panel behind the numbers, in your UI theme's colours",
        onChange = function(_, value) V.SetBackground(value) end },
    } },
    UI.Toggle{ id = "vitals_flash", text = "Flash when low", value = V.GetFlash(),
      style = { marginTop = 6 }, onChange = function(_, v) V.SetFlash(v) end },
    slider("vitals_flash_below", "Flash below (%)", V.FLASH_MIN, V.FLASH_MAX, 1, V.GetFlashBelow(),
      "Health or focus under this percentage flashes", function(n) V.SetFlashBelow(n) end),
    UI.Row{ style = { justifyContent = "end", marginTop = 2 }, children = {
      UI.Button{ id = "vitals_flash_test", text = "Test flash",
        tooltip = "Flash both bars for " .. V.PREVIEW_SECONDS .. " seconds to see what it looks like",
        onClick = function() V.PreviewFlash() end },
    } },
    C.PositionRows("vitals", V),
  } }
end

-- The "Combat stats" part of the settings.
function C.CombatSection()
  local M = T.Combat
  return UI.Column{ children = {
    UI.Label{ text = "Combat stats", class = "heading", style = { marginTop = 8 } },
    UI.Toggle{ id = "show_combat", text = "Show combat stats", value = M.IsShown(),
      onChange = function(_, v) M.SetShown(v) end },
    UI.Toggle{ id = "combat_detail", text = "Show Combat Detailed window", value = M.Detail.IsOpen(),
      style = { marginLeft = 16 }, tooltip = "Damage by skill, the last minute as a chart, and healing",
      onChange = function(_, v) C.OnShowCombatDetail(v) end },
    UI.Toggle{ id = "combat_detail_hover", text = "Show it on hover", value = M.Detail.GetHover(),
      style = { marginLeft = 16 }, tooltip = "Hovering the combat stats HUD pops up Combat Detailed",
      onChange = function(_, v) M.Detail.SetHover(v) end },
    UI.Toggle{ id = "combat_pet", text = "Count pet damage in DPS", value = M.GetPet(),
      onChange = function(_, v) M.SetPet(v) end },
    slider("combat_scale", "Size (%)", M.SCALE_MIN, M.SCALE_MAX, 5, M.GetScale(),
      "Scales the combat stats text", function(n) M.SetScale(n) end),
    UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
      UI.Label{ text = "Background", class = "text", style = { flexGrow = 1 } },
      UI.Dropdown{ id = "combat_bg", choices = M.BACKGROUNDS, value = (M.GetBackground()),
        tooltip = "A dark panel, or a light one in your UI theme's text colour, behind the combat stats",
        onChange = function(_, value) M.SetBackground(value) end },
    } },
    slider("combat_bg_opacity", "Background opacity (%)", M.OPACITY_MIN, M.OPACITY_MAX, 5,
      select(2, M.GetBackground()), "How solid the panel is; the text stays solid",
      function(n) M.SetBackground((M.GetBackground()), n) end),
    UI.Label{ id = "combat_stats", text = "", class = "text", style = { whiteSpace = "wrap", marginTop = 4 } },
    UI.Label{ text = "Add a stat while playing: /toolbox stats <word> finds its name, then "
      .. "/toolbox combat stat add <Name>. /toolbox combat help lists every option.",
      class = "dim", style = { whiteSpace = "wrap" } },
    UI.Row{ style = { justifyContent = "end", marginTop = 2 }, children = {
      UI.Button{ id = "combat_reset", text = "Reset fight", onClick = function() M.Reset() end },
    } },
    C.PositionRows("combat", M),
  } }
end

-- The "Buff bar" part of the settings (built inside build()).
function C.BuffBarSection()
  local B, S = T.BuffBar, T.Sounds
  local children = {
    UI.Label{ text = "Buff bar", class = "heading", style = { marginTop = 8 } },
    UI.Toggle{ id = "show_buffs", text = "Show buff bar", value = B.IsEnabled(),
      onChange = function(_, v) B.SetShown(v) end },
    UI.Toggle{ id = "buffs_combat_only", text = "Only during combat", value = B.GetCombatOnly(),
      style = { marginLeft = 16 },
      tooltip = "Show the bar only in combat (and a few seconds after). It also shows while this window"
        .. " is open, so you can place it.",
      onChange = function(_, v) B.SetCombatOnly(v) end },
    C.PositionRows("buff", B),
    slider("buff_size", "Icon size", B.SIZE_MIN, B.SIZE_MAX, 1, B.GetSize(),
      "Buff icon size in pixels", function(n) B.SetSize(n) end),
    UI.Toggle{ id = "expire_alert", text = "Sound when a buff is about to run out", value = B.GetExpireAlert(),
      style = { marginTop = 6 }, onChange = function(_, v) B.SetExpireAlert(v) end },
    slider("expire_seconds", "Seconds before it runs out", B.ALERT_MIN, B.ALERT_MAX, 1, B.GetExpireSeconds(),
      "How long before a buff ends to play the alert", function(n) B.SetExpireSeconds(n) end),
    UI.Toggle{ id = "buff_flash", text = "Flash icons about to run out", value = B.GetFlash(),
      tooltip = "A red border blinks on a buff for the seconds above, before it runs out (sound or not)",
      onChange = function(_, v) B.SetFlash(v) end },
    UI.Toggle{ id = "debuff_alert", text = "Sound when a debuff lands", value = B.GetDebuffAlert(),
      style = { marginTop = 6 }, onChange = function(_, v) B.SetDebuffAlert(v) end },
    UI.Toggle{ id = "buff_replace", text = "Replace the game's buff bar", value = B.GetReplace(),
      enabled = B.CanReplace(), style = { marginTop = 6 },
      tooltip = B.CanReplace() and "Hides the game's own buff bar while this one is showing"
        or "Needs a newer game client (Lua API 16)",
      onChange = function(_, v) C.OnReplace(v) end },
    UI.Toggle{ id = "buff_dismiss", text = "Click a buff to dismiss it", value = B.GetClickDismiss(),
      enabled = B.CanDismiss(),
      tooltip = B.CanDismiss() and "Like the game's right-click Dismiss; only buffs the game lets you dismiss"
        or "Needs a newer game client (Lua API 16)",
      onChange = function(_, v) C.OnDismiss(v) end },
    UI.Row{ style = { alignItems = "center", marginTop = 6 }, children = {
      UI.Label{ text = "Group buffs lasting longer than", class = "text",
        style = { flexGrow = 1, whiteSpace = "wrap" } },
      UI.Dropdown{ id = "buff_group_after", choices = C.GroupAfterLabels(),
        value = B.GroupAfterLabel(B.GetGroupAfter()) or "15 minutes",
        tooltip = "Buffs with more time left than this share one slot with a count at the end of the row;"
          .. " hover it for the list. They move back onto the bar as they near their end.",
        onChange = function(_, value) C.OnGroupAfter(value) end },
    } },
    UI.Label{ id = "buff_group", text = "", class = "dim", style = { whiteSpace = "wrap" },
      tooltip = "Buffs whose names contain these are always grouped" },
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
    width = 280, height = 680, minWidth = 220, minHeight = 120,
    escCloses = true,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = { UI.Scroll{ style = { flexGrow = 1 }, children = {
      UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = {
        UI.Label{ text = "Tick what you want on screen and tune it here. Everything is saved per character.",
          class = "text", style = { whiteSpace = "wrap" } },
        UI.Row{ style = { alignItems = "center", marginTop = 2, marginBottom = 4 }, children = {
          UI.Label{ id = "shortcut", text = "", class = "dim", style = { flexGrow = 1, whiteSpace = "wrap" },
            tooltip = "Change it in the add-on manager, on Toolbox's row under Keys" },
          UI.Button{ id = "docs", text = "Docs", tooltip = "How everything works, and every command",
            onClick = function() T.Docs.Open() end },
        } },
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
          id = "xp_net", text = "Subtract XP lost (net change)", value = W.GetNet(),
          tooltip = "Off: XP figures count gains only (a death doesn't lower them). On: XP lost is"
            .. " subtracted, so last hour, XP/hour and today's XP can go negative.",
          onChange = function(_, value) W.SetNet(value) end,
        },
        UI.Toggle{
          id = "show_compact", text = "Show XP window", value = T.Compact.IsShown(),
          style = { marginTop = 6 },
          onChange = function(_, value) C.OnShowCompact(value) end,
        },
        UI.Toggle{
          id = "xp_hud", text = "As a HUD strip", value = T.Compact.GetHud(), style = { marginLeft = 16 },
          tooltip = "No title bar or frame: a small panel moved by its grip, like the buff bar",
          onChange = function(_, value) T.Compact.SetHud(value) end,
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
          id = "daily_hud", text = "As a HUD strip", value = T.Daily.GetHud(), style = { marginLeft = 16 },
          tooltip = "No title bar or frame: a small panel moved by its grip, like the buff bar",
          onChange = function(_, value) T.Daily.SetHud(value) end,
        },
        UI.Toggle{
          id = "show_daily_detail", text = "Show Today Detailed window", value = T.DailyDetail.IsOpen(),
          onChange = function(_, value) C.OnShowDailyDetail(value) end,
        },
        UI.Toggle{
          id = "dd_values", text = "Estimated values (SOTA.net)", value = T.DailyDetail.GetValues(),
          style = { marginLeft = 16 },
          tooltip = "Adds each item's value to Today Detailed: count x its 90-day average sale price from"
            .. " shroudoftheavatar.net (player-uploaded receipts); blank when it hasn't sold. Sends item"
            .. " names to that site. Also switch Internet on for Toolbox in the add-on manager.",
          onChange = function(_, value) T.DailyDetail.SetValues(value) end,
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
        C.VitalsSection(),
        C.CombatSection(),
        C.NotifySection(),
      } },
    } } },
  }
  el = {}
  local ids = { "font", "font_value", "spacing", "spacing_value", "show_xp", "show_compact", "show_daily",
                "show_daily_detail", "hover_popup", "hover_daily", "xp_hud", "daily_hud",
                "show_buffs", "buff_size", "buff_size_value", "expire_alert", "expire_seconds",
                "expire_seconds_value", "debuff_alert", "volume", "volume_value", "buff_pos",
                "show_vitals", "vitals_width", "vitals_width_value", "vitals_scale", "vitals_scale_value",
                "vitals_pos", "vitals_show_bars", "vitals_show_text", "vitals_bg",
                "vitals_flash", "vitals_flash_below", "vitals_flash_below_value", "vitals_glue",
                "show_combat", "combat_pet", "combat_scale", "combat_scale_value", "combat_stats", "combat_pos",
                "combat_bg", "combat_bg_opacity", "combat_bg_opacity_value", "shortcut", "buff_group",
                "buff_replace", "buff_dismiss", "buff_group_after",
                "buffs_combat_only", "dd_values", "xp_net", "buff_flash", "combat_detail", "combat_detail_hover" }
  for _, def in ipairs(T.Sounds.DEFS) do
    ids[#ids + 1] = "snd_" .. def.key .. "_status"
    ids[#ids + 1] = "snd_" .. def.key .. "_path"
  end
  for _, src in ipairs(T.Notify.Sources()) do
    ids[#ids + 1] = "notify_" .. src.key
    ids[#ids + 1] = "notify_" .. src.key .. "_via"
  end
  for _, id in ipairs({ "nhud_hide", "nhud_pos" }) do ids[#ids + 1] = id end
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

-- The "Notifications" part of the settings: one toggle per source (Toolbox.Notify.SOURCES).
-- More per-source controls (how it's delivered, a sound) would go on each source's row.
function C.NotifySection()
  local children = {
    UI.Label{ text = "Notifications", class = "heading", style = { marginTop = 8 } },
    UI.Label{ text = "A window tells you what's new since you last saw it.", class = "dim",
      style = { whiteSpace = "wrap" } },
  }
  local vias = {}
  for i, v in ipairs(T.Notify.VIAS) do vias[i] = v[2] end
  for _, src in ipairs(T.Notify.Sources()) do
    local key = src.key
    children[#children + 1] = UI.Row{ style = { alignItems = "center" }, children = {
      UI.Toggle{ id = "notify_" .. key, text = src.label, value = T.Notify.IsOn(key), style = { flexGrow = 1 },
        tooltip = src.tip, onChange = function(_, v) T.Notify.SetOn(key, v) end },
      UI.Dropdown{ id = "notify_" .. key .. "_via", choices = vias,
        value = T.Notify.ViaLabel(T.Notify.GetVia(key)) or vias[1],
        tooltip = "Where it shows: the Notifications window, or the notification HUD",
        onChange = function(_, label) C.OnNotifyVia(key, label) end },
    } }
  end
  local NH = T.Notify.Hud
  local hides = {}
  for i, c in ipairs(NH.HIDE_CHOICES) do hides[i] = c[2] end
  children[#children + 1] = UI.Row{ style = { alignItems = "center", marginTop = 6 }, children = {
    UI.Label{ text = "HUD: hide after", class = "text", style = { flexGrow = 1 } },
    UI.Dropdown{ id = "nhud_hide", choices = hides, value = NH.HideLabel(NH.GetHideAfter()) or hides[1],
      tooltip = "The notification HUD shows when something arrives and hides after this (Never: always shown)",
      onChange = function(_, label) C.OnNotifyHide(label) end },
  } }
  children[#children + 1] = C.PositionRows("nhud", NH)
  children[#children + 1] = UI.Row{ style = { justifyContent = "end", marginTop = 2 }, children = {
    UI.Button{ id = "nhud_clear", text = "Clear HUD", tooltip = "Empty the notification HUD's list",
      onClick = function() NH.Clear() end },
  } }
  return UI.Column{ children = children }
end

function C.OnNotifyVia(key, label)
  for _, v in ipairs(T.Notify.VIAS) do
    if v[2] == label then T.Notify.SetVia(key, v[1]) end
  end
end

function C.OnNotifyHide(label)
  for _, c in ipairs(T.Notify.Hud.HIDE_CHOICES) do
    if c[2] == label then T.Notify.Hud.SetHideAfter(c[1]) end
  end
end

-- "Group buffs lasting longer than" choices, as shown in the dropdown.
function C.GroupAfterLabels()
  local out = {}
  for i, ch in ipairs(T.BuffBar.GROUP_AFTER_CHOICES) do out[i] = ch[2] end
  return out
end

function C.OnGroupAfter(label)
  for _, ch in ipairs(T.BuffBar.GROUP_AFTER_CHOICES) do
    if ch[2] == label then T.BuffBar.SetGroupAfter(ch[1]) return end
  end
end

-- The buff bar's API 16 options: refused on an older client, so put the box back.
function C.OnReplace(value)
  if not T.BuffBar.SetReplace(value == true) then el.buff_replace:SetValue(T.BuffBar.GetReplace()) end
end

function C.OnDismiss(value)
  if not T.BuffBar.SetClickDismiss(value == true) then el.buff_dismiss:SetValue(T.BuffBar.GetClickDismiss()) end
end

function C.OnShowCombatDetail(value)
  if not T.Combat.Detail.SetOpen(value == true) then el.combat_detail:SetValue(T.Combat.Detail.IsOpen()) end
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
  el.xp_net:SetValue(T.Window.GetNet())
  el.show_xp:SetValue(T.Window.IsOpen())
  el.show_compact:SetValue(T.Compact.IsShown())
  el.show_daily:SetValue(T.Daily.IsShown())
  el.show_daily_detail:SetValue(T.DailyDetail.IsOpen())
  el.dd_values:SetValue(T.DailyDetail.GetValues())
  el.hover_popup:SetValue(T.Compact.GetHover())
  el.hover_daily:SetValue(T.Daily.GetHover())
  el.xp_hud:SetValue(T.Compact.GetHud())
  el.daily_hud:SetValue(T.Daily.GetHud())
  local B, S = T.BuffBar, T.Sounds
  el.show_buffs:SetValue(B.IsEnabled())
  el.buffs_combat_only:SetValue(B.GetCombatOnly())
  for id, v in pairs({ buff_size = B.GetSize(), expire_seconds = B.GetExpireSeconds(), volume = S.GetVolume() }) do
    el[id]:SetValue(v)
    el[id .. "_value"]:SetText(fontLabel(v))
  end
  el.expire_alert:SetValue(B.GetExpireAlert())
  el.debuff_alert:SetValue(B.GetDebuffAlert())
  el.buff_flash:SetValue(B.GetFlash())
  el.buff_replace:SetValue(B.GetReplace())
  el.buff_dismiss:SetValue(B.GetClickDismiss())
  el.buff_group_after:SetValue(B.GroupAfterLabel(B.GetGroupAfter()) or "15 minutes")
  local parts = B.GroupParts()
  el.buff_group:SetText("Also grouped by name: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
    .. " (/toolbox buffs group add <name>)")
  el.show_vitals:SetValue(T.Vitals.IsShown())
  el.vitals_width:SetValue(T.Vitals.GetWidth())
  el.vitals_width_value:SetText(fontLabel(T.Vitals.GetWidth()))
  el.vitals_scale:SetValue(T.Vitals.GetScale())
  el.vitals_scale_value:SetText(fontLabel(T.Vitals.GetScale()))
  el.vitals_show_bars:SetValue(T.Vitals.GetShowBars())
  el.vitals_show_text:SetValue(T.Vitals.GetShowText())
  el.vitals_bg:SetValue(T.Vitals.GetBackground())
  el.vitals_flash:SetValue(T.Vitals.GetFlash())
  el.vitals_glue:SetValue(T.Hud.IsGlued())
  el.show_combat:SetValue(T.Combat.IsShown())
  el.combat_pet:SetValue(T.Combat.GetPet())
  el.combat_detail:SetValue(T.Combat.Detail.IsOpen())
  el.combat_detail_hover:SetValue(T.Combat.Detail.GetHover())
  el.combat_scale:SetValue(T.Combat.GetScale())
  el.combat_scale_value:SetText(fontLabel(T.Combat.GetScale()))
  local shownStats = T.Combat.Stats()
  el.combat_stats:SetText("Stats shown: " .. (#shownStats > 0 and table.concat(shownStats, ", ") or "none"))
  local cbg, cop = T.Combat.GetBackground()
  el.combat_bg:SetValue(cbg)
  el.combat_bg_opacity:SetValue(cop)
  el.combat_bg_opacity_value:SetText(fontLabel(cop))
  el.vitals_flash_below:SetValue(T.Vitals.GetFlashBelow())
  el.vitals_flash_below_value:SetText(fontLabel(T.Vitals.GetFlashBelow()))
  for _, src in ipairs(T.Notify.Sources()) do
    el["notify_" .. src.key]:SetValue(T.Notify.IsOn(src.key))
    el["notify_" .. src.key .. "_via"]:SetValue(T.Notify.ViaLabel(T.Notify.GetVia(src.key)) or "Window")
  end
  el.nhud_hide:SetValue(T.Notify.Hud.HideLabel(T.Notify.Hud.GetHideAfter()) or "Never")
  C.SyncLive()
end

-- Things that change without a setter being called (sound loads settling, the bar being
-- dragged by its grip); called once a tick from Toolbox.Tick, and from Sync.
function C.SyncLive()
  if not win then return end
  C.SyncSounds()
  el.shortcut:SetText("Shortcut: " .. T.KeyStatus())
  for prefix, m in pairs({ buff = T.BuffBar, vitals = T.Vitals, combat = T.Combat, nhud = T.Notify.Hud }) do
    local x, y = m.GetPosition()
    el[prefix .. "_pos"]:SetText(x and (x .. ", " .. y) or "")
  end
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

-- Opens the settings window (leaves it open if it already is).
function C.Open()
  if not win then build() end
  if win:IsShown() then return end
  if win:Show() then
    C.Sync()
  else
    T.Print("The settings window can't open right now; type /" .. T.commands[1] .. " to try again.")
  end
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
