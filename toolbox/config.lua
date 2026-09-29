-- Toolbox: config.lua
-- The "Toolbox Settings" window (/toolbox config). Each control reads its value
-- from the owning module and writes back through that module's setter, so the
-- settings live in one place and the matching chat commands keep working.
--
-- A "Show:" dropdown picks one category (C.CATEGORIES); each is built the first time it is shown
-- (fewer elements created when the window opens), so anything that updates controls must allow
-- for ones not built yet (the set* helpers below skip them). Controls whose feature is off are
-- greyed out (SetEnabled) rather than hidden. The review of 2026-09-29 asked for this layout.

local T = Toolbox
local C = {}
Toolbox.Config = C

local UI = Shroud.UI
local WINDOW_ID = "toolbox_config"
local GUTTER = 10
C.WIDTH, C.HEIGHT = 360, 680

local win = nil
local body = nil          -- the column the categories are added to
local el = {}             -- id -> element, for the categories built so far
local built = {}          -- category key -> its column
local current = nil       -- the category shown (kept across a window rebuild, not saved)

local function fontLabel(n)
  return string.format("%d", n)
end

-- Control updates that skip controls not built yet (their category hasn't been shown).
local function setValue(id, v)
  local e = el[id]
  if e then e:SetValue(v) end
end
local function setText(id, text)
  local e = el[id]
  if e then e:SetText(text) end
end
local function setEnabled(id, on)
  local e = el[id]
  if e and e:IsEnabled() ~= on then e:SetEnabled(on) end
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

-- "Label ........ [dropdown]"
local function dropdownRow(label, spec)
  return UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
    UI.Label{ text = label, class = "text", style = { flexGrow = 1, whiteSpace = "wrap" } },
    UI.Dropdown(spec),
  } }
end

local function heading(text, first)
  return UI.Label{ text = text, class = "heading", style = { marginTop = first and 2 or 10 } }
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
function C.PositionRows(prefix, m, label)
  local n = C.NUDGE
  local function button(id, text, tip, fn, gap)
    return UI.Button{ id = prefix .. "_" .. id, text = text, tooltip = tip, style = { marginLeft = gap },
      onClick = fn }
  end
  return UI.Column{ children = {
    UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
      UI.Label{ text = label or "Position", class = "text", style = { flexGrow = 1 },
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

-- ---------------------------------------------------------------------------
-- XP and Today: Hidden / Window / HUD strip
-- ---------------------------------------------------------------------------

C.MODES = { "Hidden", "Window", "HUD strip" }

-- The display mode of Toolbox.Compact (XP) or Toolbox.Daily (Today).
function C.ModeOf(m)
  if not m.IsShown() then return "Hidden" end
  if m.GetHud() then return "HUD strip" end
  return "Window"
end

-- Sets the mode; returns true when it took (a window can be refused while the game is busy).
function C.SetMode(m, label)
  if label == "Hidden" then return m.SetOpen(false) ~= false end
  local hud = label == "HUD strip"
  if label ~= "Window" and not hud then return false end
  local ok = m.SetHud(hud)
  if ok ~= false then ok = m.SetOpen(true) end
  return ok ~= false
end

local function onMode(m, id, label)
  if not C.SetMode(m, label) then setValue(id, C.ModeOf(m)) end   -- refused: put the dropdown back
  C.Sync()
end

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------

function C.XPSection()
  local W = T.Window
  return UI.Column{ children = {
    heading("XP", true),
    dropdownRow("XP window", { id = "xp_mode", choices = C.MODES, value = C.ModeOf(T.Compact),
      tooltip = "Session time, pools and XP in the last hour: as a window, or as a HUD strip (no title bar;"
        .. " moved by its grip, like the buff bar)",
      onChange = function(_, v) onMode(T.Compact, "xp_mode", v) end }),
    UI.Toggle{ id = "hover_popup", text = "Show XP Detailed on hover", value = T.Compact.GetHover(),
      style = { marginLeft = 16 }, tooltip = "Hovering the XP window pops up the XP Detailed window",
      onChange = function(_, value) T.Compact.SetHover(value) end },
    UI.Toggle{ id = "show_xp", text = "Show XP Detailed window", value = W.IsOpen(),
      onChange = function(_, value) C.OnShowXP(value) end },
    UI.Toggle{ id = "xp_net", text = "Subtract XP lost (net change)", value = W.GetNet(),
      tooltip = "Off: XP figures count gains only (a death doesn't lower them). On: XP lost is"
        .. " subtracted, so last hour, XP/hour and today's XP can go negative.",
      onChange = function(_, value) W.SetNet(value) end },
    heading("Today"),
    dropdownRow("Today window", { id = "daily_mode", choices = C.MODES, value = C.ModeOf(T.Daily),
      tooltip = "Gold, kills and XP since midnight: as a window, or as a HUD strip",
      onChange = function(_, v) onMode(T.Daily, "daily_mode", v) end }),
    UI.Toggle{ id = "hover_daily", text = "Show Today Detailed on hover", value = T.Daily.GetHover(),
      style = { marginLeft = 16 }, tooltip = "Hovering the Today window pops up the Today Detailed window",
      onChange = function(_, value) T.Daily.SetHover(value) end },
    UI.Toggle{ id = "show_daily_detail", text = "Show Today Detailed window", value = T.DailyDetail.IsOpen(),
      onChange = function(_, value) C.OnShowDailyDetail(value) end },
    UI.Toggle{ id = "dd_values", text = "Estimated values (SotANET)", value = T.DailyDetail.GetValues(),
      style = { marginLeft = 16 },
      tooltip = "Adds each item's value to Today Detailed: count x its 90-day average sale price from"
        .. " shroudoftheavatar.net (player-uploaded receipts); blank when it hasn't sold. Sends item"
        .. " names to that site. Also switch Internet on for Toolbox in the add-on manager.",
      onChange = function(_, value) T.DailyDetail.SetValues(value) end },
    UI.Toggle{ id = "dd_include", text = "Include crafted and gathered items", value = T.DailyDetail.GetInclude(),
      style = { marginLeft = 16 }, enabled = T.Daily.HasResults(),
      tooltip = T.Daily.HasResults() and "Off: Today Detailed's Looted list leaves out what you crafted or"
        .. " gathered (they have their own views)" or "Needs a newer game client (Lua API 18)",
      onChange = function(_, value) T.DailyDetail.SetInclude(value) end },
    heading("Text in these windows"),
    slider("font", "Text size", W.FONT_MIN, W.FONT_MAX, 1, W.GetFont(),
      "Text size of the XP and Today windows (" .. W.FONT_MIN .. "-" .. W.FONT_MAX .. ")",
      function(n) C.OnFont(n) end),
    slider("spacing", "Line spacing", W.SPACING_MIN, W.SPACING_MAX, 1, W.GetSpacing(),
      "Extra pixels between lines (" .. W.SPACING_MIN .. "-" .. W.SPACING_MAX .. ")",
      function(n) C.OnSpacing(n) end),
  } }
end

-- The "Buff bar" category: the common controls first, then alerts, then advanced grouping.
function C.BuffBarSection()
  local B = T.BuffBar
  return UI.Column{ children = {
    heading("Buff bar", true),
    UI.Toggle{ id = "show_buffs", text = "Show buff bar", value = B.IsEnabled(),
      onChange = function(_, v) B.SetShown(v) end },
    UI.Toggle{ id = "buffs_combat_only", text = "Only during combat", value = B.GetCombatOnly(),
      style = { marginLeft = 16 },
      tooltip = "Show the bar only in combat (and a few seconds after). It also shows while this window"
        .. " is open, so you can place it.",
      onChange = function(_, v) B.SetCombatOnly(v) end },
    UI.Toggle{ id = "buff_replace", text = "Replace the game's buff bar", value = B.GetReplace(),
      enabled = B.CanReplace(), style = { marginLeft = 16 },
      tooltip = B.CanReplace() and "Hides the game's own buff bar while this one is showing"
        or "Needs a newer game client (Lua API 16)",
      onChange = function(_, v) C.OnReplace(v) end },
    UI.Toggle{ id = "buff_dismiss", text = "Click a buff to dismiss it", value = B.GetClickDismiss(),
      enabled = B.CanDismiss(), style = { marginLeft = 16 },
      tooltip = B.CanDismiss() and "Like the game's right-click Dismiss; only buffs the game lets you dismiss"
        or "Needs a newer game client (Lua API 16)",
      onChange = function(_, v) C.OnDismiss(v) end },
    slider("buff_size", "Icon size", B.SIZE_MIN, B.SIZE_MAX, 1, B.GetSize(),
      "Buff icon size in pixels (the consumables and equipment bars use it too)", function(n) B.SetSize(n) end),
    heading("Alerts (they work with the bar hidden)"),
    UI.Toggle{ id = "expire_alert", text = "Sound when a buff is about to run out", value = B.GetExpireAlert(),
      onChange = function(_, v) B.SetExpireAlert(v) end },
    slider("expire_seconds", "Seconds before it runs out", B.ALERT_MIN, B.ALERT_MAX, 1, B.GetExpireSeconds(),
      "How long before a buff ends to play the alert", function(n) B.SetExpireSeconds(n) end),
    UI.Toggle{ id = "buff_flash", text = "Flash icons about to run out", value = B.GetFlash(),
      tooltip = "A red border blinks on a buff for the seconds above, before it runs out (sound or not)",
      onChange = function(_, v) B.SetFlash(v) end },
    UI.Toggle{ id = "debuff_alert", text = "Sound when a debuff lands", value = B.GetDebuffAlert(),
      onChange = function(_, v) B.SetDebuffAlert(v) end },
    heading("Grouping"),
    dropdownRow("Group buffs lasting longer than", { id = "buff_group_after", choices = C.GroupAfterLabels(),
      value = B.GroupAfterLabel(B.GetGroupAfter()) or "15 minutes",
      tooltip = "Buffs with more time left than this share one slot with a count at the end of the row;"
        .. " hover it for the list. They move back onto the bar as they near their end.",
      onChange = function(_, value) C.OnGroupAfter(value) end }),
    UI.Label{ id = "buff_group", text = "", class = "dim", style = { whiteSpace = "wrap" },
      tooltip = "Buffs whose names contain these are always grouped" },
  } }
end

-- The "Consumables & gear" category.
function C.ConsumablesGearSection()
  local K, G = T.Consumables, T.Gear
  return UI.Column{ children = {
    heading("Consumables bar", true),
    UI.Toggle{ id = "show_consumables", text = "Show food and potions on their own bar", value = K.GetShow(),
      tooltip = "Food and Obsidian potions in effect, with the buff bar's sweep, flash and alert; they leave"
        .. " the buff bar. Off: they stay on the buff bar.",
      onChange = function(_, v) K.SetShow(v) end },
    UI.Toggle{ id = "cons_combat", text = "Only during combat", value = K.GetCombatOnly(), style = { marginLeft = 16 },
      tooltip = "On its own strip. In the Toolbelt it follows the Toolbelt's own setting.",
      onChange = function(_, v) K.SetCombatOnly(v) end },
    slider("cons_max", "Most icons", 1, K.SLOTS, 1, K.GetMax(),
      "Icons before the rest share one slot with a count (hover it). Long-lasting ones share it too (Buffs:"
        .. " Group buffs lasting longer than).", function(n) K.SetMax(n) end),
    C.CategoryToggles(),
    UI.Label{ id = "cons_exclude", text = "", class = "dim", style = { whiteSpace = "wrap", marginTop = 4 },
      tooltip = "Buffs whose names contain these stay off the bar (the Consumable kind also has scrolls, torches"
        .. " and bait)" },
    UI.Label{ id = "consumables_extra", text = "", class = "dim", style = { whiteSpace = "wrap" },
      tooltip = "Buffs whose names contain these go on the bar too" },
    heading("Equipment bar"),
    UI.Toggle{ id = "show_gear", text = "Show worn gear needing repair", value = G.GetShow(),
      tooltip = "Icons of worn items below the threshold, the sweep showing durability used up. Every worn"
        .. " item shows while this window is open, so you can place it.",
      onChange = function(_, v) G.SetShow(v) end },
    dropdownRow("Repair below", { id = "gear_threshold", choices = C.ThresholdLabels(), value = G.Threshold() .. "%",
      tooltip = "Durability at which an item shows on the bar and the \"Gear needs repair\" notification"
        .. " comes (again when it breaks)",
      onChange = function(_, value) G.SetThreshold(tonumber((value:gsub("%%", "")))) end }),
    UI.Label{ text = "Glue either bar to the buff bar, and place them, under HUD layout.", class = "dim",
      style = { whiteSpace = "wrap", marginTop = 6 } },
  } }
end

-- A checkbox per buff category for the consumables bar (the game's categories, API 23).
local CATEGORY_TIPS = {
  Food = "Food and drink", Potion = "Potions, Obsidian ones included", Blessing = "Shrine, store, reward, virtue"
    .. " and event blessings", Poison = "Weapon poisons (a poison on you stays a debuff)",
  Consumable = "Bombs, caltrops, scrolls, torches, bait (see Left out below)", Skill = "Effects of your skills",
  Song = "Bard songs", Pet = "Pet effects", Equipment = "Armor and weapon procs", Event = "Fireworks, event powerups",
  Environment = "Hazards and fields", Creature = "Effects from creatures", Other = "Anything else",
}
function C.CategoryToggles()
  local K = T.Consumables
  local children = {
    UI.Label{ text = "Kinds on the bar", class = "text", style = { marginTop = 6 },
      tooltip = K.HasCategories() and "The game sorts every buff into one of these"
        or "This game client has no buff categories (Lua API 23): Food and Potion go by name" },
  }
  for _, key in ipairs(K.Categories()) do
    children[#children + 1] = UI.Toggle{ id = "cons_cat_" .. key, text = key, value = K.GetCategory(key),
      style = { marginLeft = 16 }, tooltip = CATEGORY_TIPS[key] or key,
      onChange = function(_, v) K.SetCategory(key, v) end }
  end
  return UI.Column{ children = children }
end

-- The "Health bars" category.
function C.VitalsSection()
  local V = T.Vitals
  return UI.Column{ children = {
    heading("Health, focus & Vigor bars", true),
    UI.Toggle{ id = "show_vitals", text = "Show health & focus bars", value = V.IsShown(),
      onChange = function(_, v) V.SetShown(v) end },
    slider("vitals_scale", "Size (%)", V.SCALE_MIN, V.SCALE_MAX, 5, V.GetScale(),
      "Scales the bars, their text and the gap together", function(n) V.SetScale(n) end),
    slider("vitals_width", "Bar length", V.WIDTH_MIN, V.WIDTH_MAX, 10, V.GetWidth(),
      "Length of the bars at 100% size, in pixels", function(n) V.SetWidth(n) end),
    UI.Toggle{ id = "vitals_show_bars", text = "Show bars", value = V.GetShowBars(),
      style = { marginTop = 6 }, onChange = function(_, v) V.SetShowBars(v) end },
    UI.Toggle{ id = "vitals_show_text", text = "Show numbers", value = V.GetShowText(),
      onChange = function(_, v) V.SetShowText(v) end },
    UI.Toggle{ id = "vitals_vigor", text = "Show Vigor", value = V.GetShowVigor(), enabled = V.HasVigor(),
      tooltip = V.HasVigor() and "A gold Vigor bar under focus (hover it for the regen and crit bonuses);"
        .. " it hides below the level where Vigor applies" or "Needs a newer game client (Lua API 20)",
      onChange = function(_, v) V.SetShowVigor(v) end },
    dropdownRow("Number background", { id = "vitals_bg", choices = V.BackgroundNames(), value = V.GetBackground(),
      tooltip = "A dark or light panel behind the numbers, in your UI theme's colours",
      onChange = function(_, value) V.SetBackground(value) end }),
    UI.Toggle{ id = "vitals_flash", text = "Flash when low", value = V.GetFlash(),
      style = { marginTop = 6 }, onChange = function(_, v) V.SetFlash(v) end },
    slider("vitals_flash_below", "Flash below (%)", V.FLASH_MIN, V.FLASH_MAX, 1, V.GetFlashBelow(),
      "Health or focus under this percentage flashes", function(n) V.SetFlashBelow(n) end),
    UI.Row{ style = { justifyContent = "end", marginTop = 2 }, children = {
      UI.Button{ id = "vitals_flash_test", text = "Test flash",
        tooltip = "Flash both bars for " .. V.PREVIEW_SECONDS .. " seconds to see what it looks like",
        onClick = function() V.PreviewFlash() end },
    } },
  } }
end

-- The "Combat" category.
function C.CombatSection()
  local M = T.Combat
  return UI.Column{ children = {
    heading("Combat stats", true),
    UI.Toggle{ id = "show_combat", text = "Show combat stats", value = M.IsShown(),
      onChange = function(_, v) M.SetShown(v) end },
    UI.Toggle{ id = "combat_detail_hover", text = "Show Combat Detailed on hover", value = M.Detail.GetHover(),
      style = { marginLeft = 16 }, tooltip = "Hovering the combat stats HUD pops up Combat Detailed",
      onChange = function(_, v) M.Detail.SetHover(v) end },
    UI.Toggle{ id = "combat_detail", text = "Show Combat Detailed window", value = M.Detail.IsOpen(),
      tooltip = "Damage by skill, the last minute as a chart, and healing",
      onChange = function(_, v) C.OnShowCombatDetail(v) end },
    UI.Toggle{ id = "combat_pet", text = "Count pet damage in DPS", value = M.GetPet(),
      onChange = function(_, v) M.SetPet(v) end },
    slider("combat_scale", "Size (%)", M.SCALE_MIN, M.SCALE_MAX, 5, M.GetScale(),
      "Scales the combat stats text", function(n) M.SetScale(n) end),
    dropdownRow("Background", { id = "combat_bg", choices = M.BACKGROUNDS, value = (M.GetBackground()),
      tooltip = "A dark panel, or a light one in your UI theme's text colour, behind the combat stats",
      onChange = function(_, value) M.SetBackground(value) end }),
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
  } }
end

-- The "Notifications" category: one toggle and delivery dropdown per source (Toolbox.Notify.SOURCES).
function C.NotifySection()
  local children = {
    heading("Notifications", true),
    UI.Label{ text = "Tells you what's new since you last saw it, in a window or on the notification HUD.",
      class = "dim", style = { whiteSpace = "wrap" } },
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
  children[#children + 1] = heading("Notification HUD")
  children[#children + 1] = dropdownRow("Hide after", { id = "nhud_hide", choices = hides,
    value = NH.HideLabel(NH.GetHideAfter()) or hides[1],
    tooltip = "The notification HUD shows when something arrives and hides after this (Never: always shown)",
    onChange = function(_, label) C.OnNotifyHide(label) end })
  children[#children + 1] = UI.Row{ style = { justifyContent = "end", marginTop = 4 }, children = {
    UI.Button{ id = "nhud_clear", text = "Clear notification history",
      tooltip = "Delete the notification HUD's saved list (it can't be undone)",
      onClick = function() NH.Clear() end },
  } }
  return UI.Column{ children = children }
end

-- The "Sounds" category: the alert volume and which file each alert plays.
function C.SoundsSection()
  local S = T.Sounds
  local children = {
    heading("Alert sounds", true),
    slider("volume", "Volume", 0, 100, 5, S.GetVolume(), "0 mutes the alerts", function(n) S.SetVolume(n) end),
    UI.Label{ text = "Each alert plays the add-on's own sound unless you pick a file:", class = "dim",
      style = { whiteSpace = "wrap", marginTop = 6 } },
  }
  for _, def in ipairs(S.DEFS) do children[#children + 1] = soundRows(def) end
  return UI.Column{ children = children }
end

-- The HUD strips with Position rows, in the order the HUD layout category lists them:
-- { id prefix, module, label }. Built once (config.lua loads last, so every module exists here).
local POSITIONED = {
  { "buff", T.BuffBar, "Buff bar" }, { "vitals", T.Vitals, "Health bars" },
  { "consumables", T.Consumables, "Consumables bar" }, { "gear", T.Gear, "Equipment bar" },
  { "combat", T.Combat, "Combat stats" }, { "nhud", T.Notify.Hud, "Notification HUD" },
}

-- The "Toolbelt" category: the buff bar with the health bars, consumables and gear repair joined to it,
-- one strip moved as one (owner, 2026-09-29: "this combined bar will be the main selling point").
-- Underneath it is the glue machinery: Hud.SetGlued (health bars beside the buffs) and the consumables
-- and equipment bars' glue (rows under the buffs).
function C.ToolbeltSection()
  return UI.Column{ children = {
    heading("Toolbelt", true),
    UI.Label{ text = "Your buff bar with your health, focus and Vigor bars beside it and your consumables and"
      .. " gear repair under it: one strip, moved as one.", class = "text", style = { whiteSpace = "wrap" } },
    UI.Label{ id = "hud_summary", text = "", class = "dim", style = { whiteSpace = "wrap", marginTop = 4 } },
    UI.Toggle{ id = "toolbelt_combat", text = "Only during combat", value = T.BuffBar.GetCombatOnly(),
      style = { marginTop = 6 },
      tooltip = "The whole Toolbelt shows only in combat (and a few seconds after), and while this window is open",
      onChange = function(_, v) T.BuffBar.SetCombatOnly(v) end },
    heading("In the Toolbelt"),
    UI.Toggle{ id = "vitals_glue", text = "Health, focus & Vigor bars", value = T.Hud.IsGlued(),
      tooltip = "On the left of the buffs",
      onChange = function(_, v) T.Hud.SetGlued(v) end },
    UI.Toggle{ id = "consumables_glue", text = "Consumables bar", value = T.Consumables.GetGlue(),
      tooltip = "A row under the debuffs",
      onChange = function(_, v) T.Consumables.SetGlue(v) end },
    UI.Toggle{ id = "gear_glue", text = "Equipment bar", value = T.Gear.GetGlue(),
      tooltip = "The last row",
      onChange = function(_, v) T.Gear.SetGlue(v) end },
    UI.Label{ text = "The buff bar is the Toolbelt's base: with it off, the others use their own strips. Place"
      .. " it under HUD layout (Buff bar), or drag its grip.", class = "dim",
      style = { whiteSpace = "wrap", marginTop = 6 } },
  } }
end

-- The "HUD layout" category: every strip's position, in one place.
function C.HudSection()
  local children = {
    heading("HUD layout", true),
    UI.Label{ text = "Strips show while this window is open, so you can place them. Drag a strip's grip"
      .. " (untick Options > Interface > Nameplates & Chat Bubbles > Lock Status Movement to see it) or"
      .. " use the buttons.", class = "dim", style = { whiteSpace = "wrap", marginTop = 6 } },
  }
  for _, p in ipairs(POSITIONED) do children[#children + 1] = C.PositionRows(p[1], p[2], p[3]) end
  return UI.Column{ children = children }
end

-- key, label, builder. The first is shown when the window first opens.
C.CATEGORIES = {
  { key = "xp", label = "XP & Today", build = function() return C.XPSection() end },
  { key = "toolbelt", label = "Toolbelt", build = function() return C.ToolbeltSection() end },
  { key = "buffs", label = "Buffs", build = function() return C.BuffBarSection() end },
  { key = "gear", label = "Consumables & gear", build = function() return C.ConsumablesGearSection() end },
  { key = "vitals", label = "Health bars", build = function() return C.VitalsSection() end },
  { key = "combat", label = "Combat", build = function() return C.CombatSection() end },
  { key = "notify", label = "Notifications", build = function() return C.NotifySection() end },
  { key = "sounds", label = "Sounds", build = function() return C.SoundsSection() end },
  { key = "hud", label = "HUD layout", build = function() return C.HudSection() end },
}

local function category(keyOrLabel)
  for _, c in ipairs(C.CATEGORIES) do
    if c.key == keyOrLabel or c.label == keyOrLabel then return c end
  end
  return nil
end

-- Every control id Sync and the handlers look up (found in whichever categories are built).
local ALL_IDS = { "font", "font_value", "spacing", "spacing_value", "xp_net", "xp_mode", "daily_mode", "show_xp",
  "show_daily_detail", "dd_values", "dd_include", "hover_popup", "hover_daily",
  "show_buffs", "buffs_combat_only", "buff_replace", "buff_dismiss", "buff_size", "buff_size_value",
  "expire_alert", "expire_seconds", "expire_seconds_value", "buff_flash", "debuff_alert", "buff_group_after",
  "buff_group", "show_consumables", "consumables_extra", "show_gear", "gear_threshold",
  "show_vitals", "vitals_scale", "vitals_scale_value", "vitals_width", "vitals_width_value", "vitals_show_bars",
  "vitals_show_text", "vitals_vigor", "vitals_bg", "vitals_flash", "vitals_flash_below", "vitals_flash_below_value",
  "vitals_flash_test", "show_combat", "combat_detail", "combat_detail_hover", "combat_pet", "combat_scale",
  "combat_scale_value", "combat_bg", "combat_bg_opacity", "combat_bg_opacity_value", "combat_stats",
  "nhud_hide", "volume", "volume_value", "hud_summary", "vitals_glue", "consumables_glue", "gear_glue",
  "toolbelt_combat", "cons_combat", "cons_max", "cons_max_value" }
for _, def in ipairs(T.Sounds.DEFS) do
  ALL_IDS[#ALL_IDS + 1] = "snd_" .. def.key .. "_status"
  ALL_IDS[#ALL_IDS + 1] = "snd_" .. def.key .. "_path"
end
for _, src in ipairs(T.Notify.Sources()) do
  ALL_IDS[#ALL_IDS + 1] = "notify_" .. src.key
  ALL_IDS[#ALL_IDS + 1] = "notify_" .. src.key .. "_via"
end
for _, p in ipairs(POSITIONED) do ALL_IDS[#ALL_IDS + 1] = p[1] .. "_pos" end
for _, key in ipairs(T.Consumables.Categories()) do ALL_IDS[#ALL_IDS + 1] = "cons_cat_" .. key end
ALL_IDS[#ALL_IDS + 1] = "cons_exclude"

-- Shows one category (by key or label), building it the first time. Returns true when it shows.
function C.ShowCategory(which)
  local cat = category(which)
  if not cat or not win then return false end
  if not built[cat.key] then
    -- the game limits how fast elements are created: a category that can't be built now can be
    -- picked again in a moment
    local ok, col = pcall(function() return body:Add(cat.build()) end)
    if not ok then
      T.Print("The " .. cat.label .. " settings can't be shown right now; pick them again in a moment. ("
        .. tostring(col) .. ")")
      return false
    end
    built[cat.key] = col
    for _, id in ipairs(ALL_IDS) do
      if not el[id] then el[id] = col:Find(id) end
    end
  end
  for key, col in pairs(built) do T.SetVisible(col, key == cat.key) end
  current = cat.key
  setValue("category", cat.label)
  C.Sync()
  return true
end

function C.CurrentCategory() return current end

-- Builds every category (the tests look controls up by id across all of them).
function C.BuildAll()
  if not win then return end
  local keep = current
  for _, cat in ipairs(C.CATEGORIES) do C.ShowCategory(cat.key) end
  C.ShowCategory(keep)
end

local function build()
  local labels = {}
  for i, c in ipairs(C.CATEGORIES) do labels[i] = c.label end
  body = UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER } }
  win = UI.Window{
    id = WINDOW_ID, title = "Toolbox Settings",
    width = C.WIDTH, height = C.HEIGHT, minWidth = 260, minHeight = 120,
    escCloses = true,
    style = { paddingTop = 6, paddingBottom = 6 },
    children = {
      UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER, marginBottom = 4 }, children = {
        UI.Label{ text = "Tick what you want on screen and tune it here. Everything is saved per character.",
          class = "text", style = { whiteSpace = "wrap" } },
        UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
          UI.Label{ id = "shortcut", text = "", class = "dim", style = { flexGrow = 1, whiteSpace = "wrap" },
            tooltip = "Change it in the add-on manager, on Toolbox's row under Keys" },
          UI.Button{ id = "docs", text = "Docs", tooltip = "How everything works, and every command",
            onClick = function() T.Docs.Open() end },
        } },
        dropdownRow("Show", { id = "category", choices = labels, value = labels[1],
          tooltip = "Which settings to show",
          onChange = function(_, label) C.ShowCategory(label) end }),
      } },
      UI.Scroll{ style = { flexGrow = 1 }, children = { body } },
    },
  }
  el, built = {}, {}
  el.shortcut, el.category = win:Find("shortcut"), win:Find("category")
  C.ShowCategory(current or C.CATEGORIES[1].key)
end

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

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
    setValue("show_xp", T.Window.IsOpen())   -- Show() was refused; put the box back
  end
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

function C.ThresholdLabels()
  local out = {}
  for i, v in ipairs(T.Gear.THRESHOLDS) do out[i] = v .. "%" end
  return out
end

-- The buff bar's API 16 options: refused on an older client, so put the box back.
function C.OnReplace(value)
  if not T.BuffBar.SetReplace(value == true) then setValue("buff_replace", T.BuffBar.GetReplace()) end
end

function C.OnDismiss(value)
  if not T.BuffBar.SetClickDismiss(value == true) then setValue("buff_dismiss", T.BuffBar.GetClickDismiss()) end
end

function C.OnShowCombatDetail(value)
  if not T.Combat.Detail.SetOpen(value == true) then setValue("combat_detail", T.Combat.Detail.IsOpen()) end
end

function C.OnShowDailyDetail(value)
  if not T.DailyDetail.SetOpen(value == true) then setValue("show_daily_detail", T.DailyDetail.IsOpen()) end
end

-- ---------------------------------------------------------------------------
-- Keeping the controls in step
-- ---------------------------------------------------------------------------

-- What shares a strip, and what has its own, in words (the HUD layout category's summary).
function C.HudSummary()
  local B, K, G, V = T.BuffBar, T.Consumables, T.Gear, T.Vitals
  local lines = {}
  local own = {}
  if B.IsEnabled() then
    local parts = { "Buffs" }
    if T.Hud.IsGlued() and V.IsShown() then table.insert(parts, 1, "Health bars") end
    if K.Glued() then parts[#parts + 1] = "Consumables" end
    if G.Glued() then parts[#parts + 1] = "Equipment" end
    if #parts > 1 then
      lines[#lines + 1] = "Toolbelt: " .. table.concat(parts, " + ") .. "."
    else
      lines[#lines + 1] = "Toolbelt: just the buff bar so far. Add bars below."
    end
  else
    local waiting = {}
    if K.GetGlue() and K.GetShow() then waiting[#waiting + 1] = "Consumables" end
    if G.GetGlue() and G.GetShow() then waiting[#waiting + 1] = "Equipment" end
    if #waiting > 0 then
      lines[#lines + 1] = "The buff bar is off (the Toolbelt's base), so " .. table.concat(waiting, " and ")
        .. (#waiting > 1 and " use their own strips." or " uses its own strip.")
    else
      lines[#lines + 1] = "The buff bar is off: the Toolbelt needs it (Buffs: Show buff bar)."
    end
  end
  if V.IsShown() and not (T.Hud.IsGlued() and B.IsEnabled()) then own[#own + 1] = "Health bars" end
  if K.GetShow() and not K.Glued() then own[#own + 1] = "Consumables" end
  if G.GetShow() and not G.Glued() then own[#own + 1] = "Equipment" end
  if T.Combat.IsShown() then own[#own + 1] = "Combat stats" end
  if T.Compact.GetHud() and T.Compact.IsShown() then own[#own + 1] = "XP" end
  if T.Daily.GetHud() and T.Daily.IsShown() then own[#own + 1] = "Today" end
  if #own > 0 then lines[#lines + 1] = "On their own strips: " .. table.concat(own, ", ") .. "." end
  if #lines == 0 then lines[1] = "No HUD strips are switched on." end
  return table.concat(lines, "\n")
end

-- Brings the controls in line with the current settings, and greys out the ones whose feature is
-- off. Our own SetValue calls never fire the onChange handlers, so this cannot loop.
function C.Sync()
  if not win then return end
  local W, B, S, V, M = T.Window, T.BuffBar, T.Sounds, T.Vitals, T.Combat
  local function sliderValue(id, v)
    setValue(id, v)
    setText(id .. "_value", fontLabel(v))
  end
  -- XP & Today
  sliderValue("font", W.GetFont())
  sliderValue("spacing", W.GetSpacing())
  setValue("xp_net", W.GetNet())
  setValue("show_xp", W.IsOpen())
  setValue("xp_mode", C.ModeOf(T.Compact))
  setValue("daily_mode", C.ModeOf(T.Daily))
  setValue("show_daily_detail", T.DailyDetail.IsOpen())
  setValue("dd_values", T.DailyDetail.GetValues())
  setValue("dd_include", T.DailyDetail.GetInclude())
  setValue("hover_popup", T.Compact.GetHover())
  setValue("hover_daily", T.Daily.GetHover())
  setEnabled("hover_popup", T.Compact.IsShown())
  setEnabled("hover_daily", T.Daily.IsShown())
  -- Buffs
  local buffsOn = B.IsEnabled()
  setValue("show_buffs", buffsOn)
  setValue("buffs_combat_only", B.GetCombatOnly())
  setValue("buff_replace", B.GetReplace())
  setValue("buff_dismiss", B.GetClickDismiss())
  sliderValue("buff_size", B.GetSize())
  setValue("expire_alert", B.GetExpireAlert())
  sliderValue("expire_seconds", B.GetExpireSeconds())
  setValue("buff_flash", B.GetFlash())
  setValue("debuff_alert", B.GetDebuffAlert())
  setValue("buff_group_after", B.GroupAfterLabel(B.GetGroupAfter()) or "15 minutes")
  local parts = B.GroupParts()
  setText("buff_group", "Also grouped by name: " .. (#parts > 0 and table.concat(parts, ", ") or "none")
    .. " (/toolbox buffs group add <name>)")
  -- (not the icon size: the consumables and equipment bars use it too)
  for _, id in ipairs({ "buffs_combat_only", "buff_flash", "buff_group_after" }) do
    setEnabled(id, buffsOn)
  end
  setEnabled("buff_replace", buffsOn and B.CanReplace())
  setEnabled("buff_dismiss", buffsOn and B.CanDismiss())
  -- Consumables & gear
  local K = T.Consumables
  setValue("show_consumables", K.GetShow())
  setValue("cons_combat", K.GetCombatOnly())
  setEnabled("cons_combat", K.GetShow() and not K.Glued())
  sliderValue("cons_max", K.GetMax())
  setEnabled("cons_max", K.GetShow())
  for _, key in ipairs(K.Categories()) do
    setValue("cons_cat_" .. key, K.GetCategory(key))
    setEnabled("cons_cat_" .. key, K.GetShow() and (K.HasCategories() or key == "Food" or key == "Potion"))
  end
  local left = K.Exclude()
  setText("cons_exclude", "Left out by name: " .. (#left > 0 and table.concat(left, ", ") or "none")
    .. " (/toolbox consumables exclude add <name>)")
  local extra = T.Consumables.Extra()
  setText("consumables_extra", "Also tracked by name: " .. (#extra > 0 and table.concat(extra, ", ") or "none")
    .. " (/toolbox consumables add <name>)")
  setValue("show_gear", T.Gear.GetShow())
  setValue("gear_threshold", T.Gear.Threshold() .. "%")
  -- Health bars
  local vitalsOn = V.IsShown()
  setValue("show_vitals", vitalsOn)
  sliderValue("vitals_scale", V.GetScale())
  sliderValue("vitals_width", V.GetWidth())
  setValue("vitals_show_bars", V.GetShowBars())
  setValue("vitals_show_text", V.GetShowText())
  setValue("vitals_vigor", V.GetShowVigor())
  setValue("vitals_bg", V.GetBackground())
  setValue("vitals_flash", V.GetFlash())
  sliderValue("vitals_flash_below", V.GetFlashBelow())
  for _, id in ipairs({ "vitals_scale", "vitals_width", "vitals_show_bars", "vitals_show_text", "vitals_bg",
                        "vitals_flash", "vitals_flash_below", "vitals_flash_test" }) do
    setEnabled(id, vitalsOn)
  end
  setEnabled("vitals_vigor", vitalsOn and V.HasVigor())
  -- Combat
  local combatOn = M.IsShown()
  setValue("show_combat", combatOn)
  setValue("combat_pet", M.GetPet())
  setValue("combat_detail", M.Detail.IsOpen())
  setValue("combat_detail_hover", M.Detail.GetHover())
  sliderValue("combat_scale", M.GetScale())
  local shownStats = M.Stats()
  setText("combat_stats", "Stats shown: " .. (#shownStats > 0 and table.concat(shownStats, ", ") or "none"))
  local cbg, cop = M.GetBackground()
  setValue("combat_bg", cbg)
  sliderValue("combat_bg_opacity", cop)
  for _, id in ipairs({ "combat_detail_hover", "combat_scale", "combat_bg", "combat_bg_opacity" }) do
    setEnabled(id, combatOn)
  end
  -- Notifications
  for _, src in ipairs(T.Notify.Sources()) do
    setValue("notify_" .. src.key, T.Notify.IsOn(src.key))
    setValue("notify_" .. src.key .. "_via", T.Notify.ViaLabel(T.Notify.GetVia(src.key)) or "Window")
  end
  setValue("nhud_hide", T.Notify.Hud.HideLabel(T.Notify.Hud.GetHideAfter()) or "Never")
  -- Sounds
  sliderValue("volume", S.GetVolume())
  -- Toolbelt
  setValue("toolbelt_combat", B.GetCombatOnly())
  setEnabled("toolbelt_combat", buffsOn)
  setValue("vitals_glue", T.Hud.IsGlued())
  setValue("consumables_glue", T.Consumables.GetGlue())
  setValue("gear_glue", T.Gear.GetGlue())
  setEnabled("consumables_glue", T.Consumables.GetShow())
  setEnabled("gear_glue", T.Gear.GetShow())
  setText("hud_summary", C.HudSummary())
  C.SyncLive()
end

-- Things that change without a setter being called (sound loads settling, a strip being dragged
-- by its grip); called once a tick from Toolbox.Tick, and from Sync (so opening the window brings
-- them up to date). Only while the window is shown: once built, the window stays built while
-- hidden, and refreshing it then cost ~9 UI calls a second for nothing (review, 2026-09-29).
function C.SyncLive()
  if not C.IsShown() then return end
  C.SyncSounds()
  if el.shortcut then T.SetText(el.shortcut, "Shortcut: " .. T.KeyStatus()) end
  for _, p in ipairs(POSITIONED) do
    local e = el[p[1] .. "_pos"]
    if e then
      local x, y = p[2].GetPosition()
      T.SetText(e, x and (x .. ", " .. y) or "")
    end
  end
end

-- Sound status lines ("Buff expiring: playing toolbox_buff_expiring.ogg"). Path fields are
-- left alone so typing isn't overwritten.
function C.SyncSounds()
  if not win then return end
  for _, def in ipairs(T.Sounds.DEFS) do
    local e = el["snd_" .. def.key .. "_status"]
    if e then
      local status, path = T.Sounds.Status(def.key)
      local state = status == "loading" and "looking..." or "no file"
      if status == "ready" then state = path end
      T.SetText(e, def.label .. ": " .. state)
    end
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
