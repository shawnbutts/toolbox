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
    UI.Toggle{ id = "combat_pet", text = "Count pet damage in DPS", value = M.GetPet(),
      onChange = function(_, v) M.SetPet(v) end },
    slider("combat_scale", "Size (%)", M.SCALE_MIN, M.SCALE_MAX, 5, M.GetScale(),
      "Scales the combat stats text", function(n) M.SetScale(n) end),
    UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
      UI.Label{ text = "Background", class = "text", style = { flexGrow = 1 } },
      UI.Dropdown{ id = "combat_bg", choices = M.BACKGROUNDS, value = (M.GetBackground()),
        tooltip = "A dark or light panel behind the combat stats, in your UI theme's colours",
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
    UI.Toggle{ id = "show_buffs", text = "Show buff bar", value = B.IsShown(),
      onChange = function(_, v) B.SetShown(v) end },
    C.PositionRows("buff", B),
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
        C.VitalsSection(),
        C.CombatSection(),
      } },
    } } },
  }
  el = {}
  local ids = { "font", "font_value", "spacing", "spacing_value", "show_xp", "show_compact", "show_daily",
                "show_daily_detail", "hover_popup", "hover_daily",
                "show_buffs", "buff_size", "buff_size_value", "expire_alert", "expire_seconds",
                "expire_seconds_value", "debuff_alert", "volume", "volume_value", "buff_pos",
                "show_vitals", "vitals_width", "vitals_width_value", "vitals_scale", "vitals_scale_value",
                "vitals_pos", "vitals_show_bars", "vitals_show_text", "vitals_bg",
                "vitals_flash", "vitals_flash_below", "vitals_flash_below_value", "vitals_glue",
                "show_combat", "combat_pet", "combat_scale", "combat_scale_value", "combat_stats", "combat_pos",
                "combat_bg", "combat_bg_opacity", "combat_bg_opacity_value", "shortcut" }
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
  C.SyncLive()
end

-- Things that change without a setter being called (sound loads settling, the bar being
-- dragged by its grip); called once a tick from Toolbox.Tick, and from Sync.
function C.SyncLive()
  if not win then return end
  C.SyncSounds()
  el.shortcut:SetText("Shortcut: " .. T.KeyStatus())
  for prefix, m in pairs({ buff = T.BuffBar, vitals = T.Vitals, combat = T.Combat }) do
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
