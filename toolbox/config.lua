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

-- Shroud.UI, through a stand-in: while `recording` (the settings search building its index, C.SearchIndex) the
-- page builders' UI.X{...} calls return plain { kind, spec } records instead of creating elements, so the
-- index is read from the pages themselves (it can't drift from them) and costs no elements.
local REAL_UI = Shroud.UI
local recording = false
local recorders = {}
-- A real element of `kind`: a text field through T.TextField (Enter both ways, once).
local function realUI(kind)
  if kind == "TextField" then return T.TextField end
  return REAL_UI[kind]
end
local UI = setmetatable({}, { __index = function(_, kind)
  if not recording then return realUI(kind) end
  local f = recorders[kind]
  if not f then
    f = function(spec) return { kind = kind, spec = spec } end
    recorders[kind] = f
  end
  return f
end })
local WINDOW_ID = "toolbox_config"
local GUTTER = 10
C.WIDTH, C.HEIGHT = 360, 680

local win = nil
local body = nil          -- the column the categories are added to
local el = {}             -- id -> element, for the header and the category shown
local built = {}          -- category key -> its column (only the one shown: see C.ShowCategory)
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

-- A HUD strip's background shade (owner, 2026-10-15: every strip has one, all T.SHADE_DEFAULT at first).
local function shadeSlider(id, value, what, onChange)
  return slider(id, "Background shade (%)", 0, T.SHADE_MAX, 5, value,
    "How dark the panel behind " .. what .. " is; the text stays solid. 0: none", onChange)
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

-- What a page built in another file uses (skills.lua): the same controls and Sync helpers as the pages here.
C.Helpers = {
  UI = UI,                             -- build with this, not Shroud.UI: the settings search records the page
  slider = slider, dropdownRow = dropdownRow, heading = heading, setValue = setValue, setEnabled = setEnabled,
  sliderValue = function(id, v)
    setValue(id, v)
    setText(id .. "_value", fontLabel(v))
  end,
}

-- A sound's own file, picked from the game's list (API 33): set and shown in its field.
function C.ChooseSound(key)
  local S = T.Sounds
  local ok, why = S.Pick(S.Label(key), function(path, bad)
    if not path then
      T.Print(S.Label(key) .. ": " .. tostring(bad))
      return
    end
    S.SetPath(key, path)
    setText("snd_" .. key .. "_path", path)
  end)
  if not ok then T.Print(S.Label(key) .. ": can't choose a file now: " .. why .. ".") end
end

local function soundRows(def)
  local S = T.Sounds
  local row = {
    UI.TextField{ id = "snd_" .. def.key .. "_path", text = S.GetPath(def.key),
      placeholder = "custom file in your Lua folder", maxLength = 200, style = { flexGrow = 1, flexShrink = 1 },
      tooltip = "A .ogg/.wav/.mp3 path inside your Lua folder: Set uses it; empty, the default",
      onSubmit = function(_, text) S.SetPath(def.key, text) end },
    -- Enter alone doesn't reach a field on the live client (owner, 2026-10-15): a button sets it
    UI.Button{ id = "snd_" .. def.key .. "_set", text = "Set", style = { marginLeft = 4 },
      tooltip = "Use the path typed here (empty: the default sound)",
      onClick = function()
        local field = el["snd_" .. def.key .. "_path"]
        if field then S.SetPath(def.key, field:GetText()) end
      end },
  }
  if S.CanPick() then
    row[#row + 1] = UI.Button{ id = "snd_" .. def.key .. "_choose", text = "Choose...", style = { marginLeft = 4 },
      tooltip = "Pick a sound file from your Lua folder for " .. def.label:lower(),
      onClick = function() C.ChooseSound(def.key) end }
  end
  row[#row + 1] = UI.Button{ id = "snd_" .. def.key .. "_test", text = "Test", style = { marginLeft = 4 },
    tooltip = "Play " .. def.label:lower(),
    onClick = function() S.Test(def.key) end }
  return UI.Column{ style = { marginTop = 4 }, children = {
    UI.Label{ id = "snd_" .. def.key .. "_status", text = def.label, class = "dim" },   -- its status, by Sync
    UI.Row{ style = { alignItems = "center" }, children = row },
    slider("snd_" .. def.key .. "_vol", "Its volume (% of the alert volume)", 0, 100, 5, S.GetLevel(def.key),
      "This sound's own volume, on top of the alert volume; 0 silences just this one",
      function(n) S.SetLevel(def.key, n) end),
  } }
end

-- A name list the player edits: the current names (label `listId`, set by Sync), a text field and
-- Add / Remove buttons; the result goes in a line under it. `add(text)` / `remove(text)` return
-- ok, message (as the matching chat commands do). Ids: listId, listId_field, _add, _remove, _msg.
function C.NameList(listId, tip, add, remove)
  local fieldId, msgId = listId .. "_field", listId .. "_msg"
  local function act(fn, typed)
    local field = el[fieldId]
    local text = typed or (field and field:GetText()) or ""
    local ok, msg = fn(text)
    setText(msgId, msg or "")
    if ok and field then field:SetText("") end
    C.Sync()
  end
  return UI.Column{ style = { marginTop = 4 }, children = {
    UI.Label{ id = listId, text = "", class = "text", style = { whiteSpace = "wrap" }, tooltip = tip },
    UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.TextField{ id = fieldId, text = "", placeholder = "a name, or part of one", maxLength = 40,
        style = { flexGrow = 1, flexShrink = 1 },
        tooltip = "Matched in the buff's name or its displayed name, any case",
        onSubmit = function(_, text) act(add, text) end },
      UI.Button{ id = listId .. "_add", text = "Add", style = { marginLeft = 4 }, onClick = function() act(add) end },
      UI.Button{ id = listId .. "_remove", text = "Remove", style = { marginLeft = 2 },
        onClick = function() act(remove) end },
    } },
    UI.Label{ id = msgId, text = "", class = "dim", style = { whiteSpace = "wrap" } },
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

C.MODES = { "Hidden", "Window", "Compact window", "HUD strip" }

-- The display mode of Toolbox.Compact (XP) or Toolbox.Daily (Today).
function C.ModeOf(m)
  if not m.IsShown() then return "Hidden" end
  if m.GetHud() then return "HUD strip" end
  if m.GetCompact() then return "Compact window" end
  return "Window"
end

-- Sets the mode; returns true when it took (a window can be refused while the game is busy).
function C.SetMode(m, label)
  if label == "Hidden" then return m.SetOpen(false) ~= false end
  local hud = label == "HUD strip"
  if label ~= "Window" and label ~= "Compact window" and not hud then return false end
  local ok = m.SetHud(hud)
  if ok ~= false and not hud then ok = m.SetCompact(label == "Compact window") end
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
    shadeSlider("xp_shade", T.Compact.GetShade(), "the XP HUD strip", function(n) T.Compact.SetShade(n) end),
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
    UI.Toggle{ id = "hover_daily", text = "Show Loot Tracker on hover", value = T.Daily.GetHover(),
      style = { marginLeft = 16 }, tooltip = "Hovering the Today window pops up the Loot Tracker window",
      onChange = function(_, value) T.Daily.SetHover(value) end },
    shadeSlider("daily_shade", T.Daily.GetShade(), "the Today HUD strip", function(n) T.Daily.SetShade(n) end),
    UI.Toggle{ id = "show_daily_detail", text = "Show Loot Tracker window", value = T.DailyDetail.IsOpen(),
      onChange = function(_, value) C.OnShowDailyDetail(value) end },
    UI.Toggle{ id = "dd_values", text = "Estimated values (SotANET)", value = T.DailyDetail.GetValues(),
      style = { marginLeft = 16 },
      tooltip = "Adds each item's value to Loot Tracker: count x its 90-day average sale price from"
        .. " shroudoftheavatar.net (player-uploaded receipts); -- when it hasn't sold. Sends item"
        .. " names to that site. Also switch Internet on for Toolbox in the add-on manager.",
      onChange = function(_, value) T.DailyDetail.SetValues(value) end },
    UI.Label{ text = "All price estimates come from receipt data retrieved from shroudoftheavatar.net. Submit"
      .. " your receipts today." .. (T.Prices.LanguageNote() and (" " .. T.Prices.LanguageNote()) or ""),
      class = "dim", style = { whiteSpace = "wrap", marginLeft = 32 } },
    UI.Toggle{ id = "dd_each", text = "Show the price each", value = T.DailyDetail.GetEach(),
      style = { marginLeft = 32 }, tooltip = "The count also shows the price each: \"40 x 5g\"",
      onChange = function(_, value) T.DailyDetail.SetEach(value) end },
    UI.Row{ style = { alignItems = "center", marginLeft = 32 }, children = {
      UI.Button{ id = "dd_values_test", text = "Test connection",
        tooltip = "Looks up one item (" .. T.Prices.TEST_ITEM .. ") on shroudoftheavatar.net now, even with"
          .. " estimated values off, and says what happened (also in chat)",
        onClick = function() T.Prices.Test("") end },
    } },
    UI.Label{ id = "dd_values_msg", text = "", class = "dim", style = { whiteSpace = "wrap", marginLeft = 32 } },
    UI.Toggle{ id = "dd_include", text = "Include crafted and gathered items", value = T.DailyDetail.GetInclude(),
      style = { marginLeft = 16 }, enabled = T.Daily.HasResults(),
      tooltip = T.Daily.HasResults() and "Off: Loot Tracker's Looted list leaves out what you crafted or"
        .. " gathered (they have their own views)" or "Needs a newer game client (Lua API 18)",
      onChange = function(_, value) T.DailyDetail.SetInclude(value) end },
  } }
end

-- The "General" category (owner, 2026-10-17: "make it clear where the everything controls are"): the text size and
-- line spacing every window and strip uses, and where the other all-of-Toolbox settings are.
function C.GeneralSection()
  local W = T.Window
  return UI.Column{ children = {
    heading("Text", true),
    UI.Label{ text = "For Toolbox's windows and HUD strips: XP, Today, the Loot Tracker, the Crafting Planner HUD,"
      .. " the location strip, the Docs, the combat stats (their Size on the Combat page scales it). Not the health"
      .. " bars: they have their own Size (Health bars page); the icon strips have their icon size. The"
      .. " Notifications window and HUD can have their own text size (Notifications page).",
      class = "dim", style = { whiteSpace = "wrap", marginTop = 6 } },
    slider("font", "Text size", W.FONT_MIN, W.FONT_MAX, 1, W.GetFont(),
      "Text size of Toolbox's windows and strips (" .. W.FONT_MIN .. "-" .. W.FONT_MAX .. "; /" .. T.commands[1]
        .. " font <n>)",
      function(n) C.OnFont(n) end),
    slider("spacing", "Line spacing", W.SPACING_MIN, W.SPACING_MAX, 1, W.GetSpacing(),
      "Extra pixels between lines (" .. W.SPACING_MIN .. "-" .. W.SPACING_MAX .. "; /" .. T.commands[1]
        .. " spacing <n>)",
      function(n) C.OnSpacing(n) end),
    heading("Also for all of Toolbox"),
    UI.Label{ text = "Sounds: the volume of every alert. HUD layout: every strip's place. Menu, setups, backup &"
      .. " reset: the menu, copying your settings to another character, backups and starting over.",
      class = "dim", style = { whiteSpace = "wrap", marginTop = 6 } },
  } }
end

-- The "Crafting" category (owner, 2026-10-17): the crafting planner, when its recipe book is read, and the Crafting
-- Planner HUD.
function C.CraftingSection()
  local PL = T.Planner
  local has = T.Daily.HasResults()
  local needs = "Needs a newer game client (Lua API 18)"
  local function names(list) local out = {} for i, c in ipairs(list) do out[i] = c[2] end return out end
  local reading = T.Daily.ReadingRecipes()
  return UI.Column{ children = {
    heading("Crafting planner", true),
    UI.Label{ text = "Plan a craft from your recipes: each ingredient you need, have and are short of, the"
      .. " material for each slot (and what it adds), what to craft from scratch, a shopping list and a build order."
      .. " Also the menu's hammer button, or /" .. T.commands[1] .. " plan <recipe>.",
      class = "dim", style = { whiteSpace = "wrap", marginTop = 6 } },
    UI.Row{ style = { marginTop = 4 }, children = {
      UI.Button{ id = "pl_open", text = "Open the crafting planner", enabled = has,
        tooltip = has and ("Opens the planner (it shares a window with the Docs and Map overlays;"
          .. " or /" .. T.commands[1] .. " plan)") or needs,
        onClick = function() PL.Open() end },
    } },
    UI.Toggle{ id = "pl_cfg_scratch", text = "From scratch", value = PL.GetScratch(), enabled = has,
      tooltip = "On: an ingredient you're short of can be crafted (I'll craft), its own materials added to the plan;"
        .. " it uses the recipe book (below). The same as the planner's From scratch.",
      onChange = function(_, on) PL.SetScratch(on == true) end },
    heading("Recipe book"),
    UI.Label{ text = "From scratch needs every recipe you know, read one at a time (about a minute and a half for a"
      .. " big book), and the game may stutter meanwhile. Until it's read, I'll craft knows only the recipes named"
      .. " like the item.", class = "dim", style = { whiteSpace = "wrap", marginTop = 6 } },
    dropdownRow("Read it", { id = "pl_book_when", choices = names(PL.BOOK_WHEN),
      value = PL.BookWhenName(PL.GetBookWhen()), enabled = has,
      tooltip = "When the planner needs it: as From scratch asks. At login: in the background a minute after you log"
        .. " in, and after learning a recipe. Only when I ask: never on its own (Read it now); a recipe learned"
        .. " leaves the book you read in use.",
      onChange = function(_, v) PL.SetBookWhen(v) end }),
    UI.Label{ id = "pl_book_status", text = PL.BookStatus(), class = "dim", style = { whiteSpace = "wrap" } },
    UI.Row{ style = { marginTop = 4 }, children = {
      UI.Button{ id = "pl_book_read", text = T.Daily.recipeIndex and "Read it again" or "Read it now",
        enabled = has and not reading,
        tooltip = has and ("Reads your recipe book now, in the background (or /" .. T.commands[1]
          .. " plan book read)") or needs,
        onClick = function() PL.ReadBook() end },
      UI.Button{ id = "pl_book_stop", text = "Stop", enabled = reading, style = { marginLeft = 4 },
        tooltip = "Stops the read (a fight coming, say); nothing starts another on its own until you read it",
        onClick = function() PL.StopBook() end },
    } },
    heading(PL.HUD_NAME),
    UI.Label{ text = "A small strip to follow the plan with the planner closed: the shopping list while you gather,"
      .. " then the build order as you craft.", class = "dim", style = { whiteSpace = "wrap", marginTop = 6 } },
    UI.Toggle{ id = "pl_hud_show", text = "Show the " .. PL.HUD_NAME, value = PL.GetHud(), enabled = has,
      tooltip = "Also the planner's button, or /" .. T.commands[1] .. " plan hud",
      onChange = function(_, on) PL.SetHud(on == true) end },
    dropdownRow("Open it on", { id = "pl_hud_start", choices = names(PL.HUD_STARTS),
      value = PL.HudStartName(PL.GetHudStart()),
      tooltip = "The build order skips the shopping list (crafting from your lot's containers); Start over goes"
        .. " back to it too",
      onChange = function(_, v) PL.SetHudStart(v) end }),
    UI.Toggle{ id = "pl_hud_auto", text = "Switch to the build order once everything is gathered",
      value = PL.GetHudAuto(),
      tooltip = "Off: the shopping list stays until you press its Build order button",
      onChange = function(_, on) PL.SetHudAuto(on == true) end },
    dropdownRow("Close it when every craft is done", { id = "pl_hud_close",
      choices = names(PL.HUD_CLOSE), value = PL.HudCloseName(PL.GetHudClose()),
      tooltip = "After this long (it plays the Crafting plan done sound first)",
      onChange = function(_, v) PL.SetHudClose(v) end }),
    UI.Row{ style = { marginTop = 4 }, children = {
      UI.Button{ id = "pl_hud_sound", text = "The Crafting plan done sound...",
        tooltip = "Its file and volume, on the Sounds page",
        onClick = function() C.GoToControl("snd_" .. PL.HUD_SOUND .. "_test") end },
    } },
    shadeSlider("pl_hud_shade", PL.GetHudShade(), "the " .. PL.HUD_NAME, function(n) PL.SetHudShade(n) end),
    C.PositionRows("plhud", PL.Strip, "Position"),
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
      tooltip = B.CanReplace() and "Hides the game's own buff bar while this one (or the buff block) is showing"
        or "Needs a newer game client (Lua API 16)",
      onChange = function(_, v) C.OnReplace(v) end },
    UI.Toggle{ id = "buff_dismiss", text = "Click a buff to dismiss it", value = B.GetClickDismiss(),
      enabled = B.CanDismiss(), style = { marginLeft = 16 },
      tooltip = B.CanDismiss() and "Like the game's right-click Dismiss; only buffs the game lets you dismiss"
        .. " (on the buff block too)"
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
    dropdownRow("Don't repeat a sound for the same effect within", { id = "buff_repeat",
      choices = C.RepeatLabels(), value = B.RepeatLabel(B.GetRepeat()) or "Off",
      tooltip = "An effect that alerted less than this long ago stays quiet (its icon still flashes); each alert"
        .. " starts the time again, so one that keeps coming in a fight sounds once. Try 2 minutes.",
      onChange = function(_, value) C.OnRepeat(value) end }),
    C.QuietRows(),
    C.EffectSoundRows(),
    UI.Toggle{ id = "buff_countdown", text = "Show seconds left near the end", value = B.GetCountdown(),
      style = { marginTop = 6 }, tooltip = "Whole seconds over the icon of a buff, debuff or consumable about to run"
        .. " out (the sweep also shows it)",
      onChange = function(_, v) B.SetCountdown(v) end },
    slider("buff_countdown_secs", "In the last (seconds)", B.COUNTDOWN_MIN, B.COUNTDOWN_MAX, 5,
      B.GetCountdownSeconds(), "How long before the end the seconds appear", function(n) B.SetCountdownSeconds(n) end),
    heading("Grouping"),
    dropdownRow("Group buffs lasting longer than", { id = "buff_group_after", choices = C.GroupAfterLabels(),
      value = B.GroupAfterLabel(B.GetGroupAfter()) or "15 minutes",
      tooltip = "Buffs with more time left than this share one slot with a count at the end of the row;"
        .. " hover it for the list. They move back onto the bar as they near their end.",
      onChange = function(_, value) C.OnGroupAfter(value) end }),
    C.CategoryToggles("buff_cat_", "Always group these kinds", B.GetGroupCategory, B.SetGroupCategory),
    C.NameList("buff_group", "Buffs whose names contain these are always grouped", B.AddGroupPart,
      B.RemoveGroupPart),
    C.BuffBlockSection(),
  } }
end

-- The buff block (Toolbox.BuffBlock), at the end of the Buffs page.
function C.BuffBlockSection()
  local MB = T.BuffBlock
  return UI.Column{ children = {
    heading("Buff block"),
    UI.Label{ text = "Every buff and debuff on a strip of its own, soonest to run out first, row after row: nothing"
      .. " grouped. Not part of the Toolbelt. The sweeps, flash, countdown and alerts above apply to it too.",
      class = "dim", style = { whiteSpace = "wrap" } },
    UI.Toggle{ id = "show_buffblock", text = "Show the buff block", value = MB.GetShow(),
      onChange = function(_, v) MB.SetShow(v) end },
    UI.Toggle{ id = "buffblock_combat", text = "Only during combat", value = MB.GetCombatOnly(),
      style = { marginLeft = 16 }, tooltip = "Show the block only in combat (and a few seconds after); it also"
        .. " shows while this window is open, so you can place it",
      onChange = function(_, v) MB.SetCombatOnly(v) end },
    slider("buffblock_width", "Icons per row", MB.WIDTH_MIN, MB.WIDTH_MAX, 1, MB.GetWidth(),
      "How many icons wide the block is; more effects start a new row (up to " .. MB.SLOTS .. " in all)",
      function(n) MB.SetWidth(n) end),
    slider("buffblock_size", "Icon size", T.BuffBar.SIZE_MIN, T.BuffBar.SIZE_MAX, 1, MB.GetSize(),
      "The block's icon size in pixels (its own)", function(n) MB.SetSize(n) end),
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
    C.CategoryToggles("cons_cat_", "Kinds on the bar", K.GetCategory, K.SetCategory),
    C.NameList("cons_exclude", "Buffs whose names contain these stay off the bar (the Consumable kind also has"
      .. " scrolls, torches and bait)", K.AddExclude, K.RemoveExclude),
    C.NameList("consumables_extra", "Buffs whose names contain these go on the bar, whatever their kind",
      K.AddExtra, K.RemoveExtra),
    heading("Equipment bar"),
    UI.Toggle{ id = "show_gear", text = "Show worn gear needing repair", value = G.GetShow(),
      tooltip = "Icons of worn items below the threshold, the sweep showing durability used up. Every worn"
        .. " item shows while this window is open, so you can place it.",
      onChange = function(_, v) G.SetShow(v) end },
    dropdownRow("Repair below", { id = "gear_threshold", choices = C.ThresholdLabels(), value = G.Threshold() .. "%",
      tooltip = "Durability at which an item shows on the bar and the \"Gear needs repair\" notification"
        .. " comes (again when it breaks)",
      onChange = function(_, value) G.SetThreshold(tonumber((value:gsub("%%", "")))) end }),
    UI.Label{ text = "Add either bar to the Toolbelt on the Toolbelt page; place them under HUD layout.", class = "dim",
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
-- A heading and a checkbox per buff category: ids <prefix><Category>; `get(key)` / `set(key, on)`.
function C.CategoryToggles(prefix, title, get, set)
  local K = T.Consumables
  local children = {
    UI.Label{ text = title, class = "text", style = { marginTop = 6 },
      tooltip = K.HasCategories() and "The game sorts every buff into one of these"
        or "This game client has no buff categories (Lua API 23)" },
  }
  for _, key in ipairs(K.Categories()) do
    children[#children + 1] = UI.Toggle{ id = prefix .. key, text = key, value = get(key),
      style = { marginLeft = 16 }, tooltip = CATEGORY_TIPS[key] or key,
      onChange = function(_, v) set(key, v) end }
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
    UI.Toggle{ id = "vitals_replace", text = "Replace the game's health bars", value = V.GetReplace(),
      enabled = V.CanReplace(),
      tooltip = V.CanReplace() and "Hides the health, focus and Vigor bars on the game's player frame while these"
        .. " show (the name and buffs there stay)" or "Needs a newer game client (Lua API 28)",
      onChange = function(_, v) V.SetReplace(v) end },
    UI.Toggle{ id = "vitals_vigor", text = "Show Vigor", value = V.GetShowVigor(), enabled = V.HasVigor(),
      tooltip = V.HasVigor() and "A gold Vigor bar under focus (hover it for the regen and crit bonuses);"
        .. " it hides below the level where Vigor applies" or "Needs a newer game client (Lua API 20)",
      onChange = function(_, v) V.SetShowVigor(v) end },
    dropdownRow("Number background", { id = "vitals_bg", choices = V.BackgroundNames(), value = V.GetBackground(),
      tooltip = "A dark or light panel behind the numbers, in your UI theme's colours",
      onChange = function(_, value) V.SetBackground(value) end }),
    shadeSlider("vitals_shade", V.GetShade(), "the numbers (Dark)", function(n) V.SetShade(n) end),
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
  C.statShownSig, C.statFilled = nil, false     -- new controls: filled by the next Sync
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
      "The combat stats' text as a share of the text size (General page): 100% is the same size",
      function(n) M.SetScale(n) end),
    dropdownRow("Background", { id = "combat_bg", choices = M.BACKGROUNDS, value = (M.GetBackground()),
      tooltip = "A dark panel, or a light one in your UI theme's text colour, behind the combat stats",
      onChange = function(_, value) M.SetBackground(value) end }),
    slider("combat_bg_opacity", "Background opacity (%)", M.OPACITY_MIN, M.OPACITY_MAX, 5,
      select(2, M.GetBackground()), "How solid the panel is; the text stays solid",
      function(n) M.SetBackground((M.GetBackground()), n) end),
    heading("Character stats on the HUD"),
    UI.Label{ id = "combat_stats", text = "", class = "text", style = { whiteSpace = "wrap" } },
    UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
      UI.TextField{ id = "stat_find", text = "", placeholder = "Find a stat: resist, dodge, regen...",
        maxLength = 40, style = { flexGrow = 1, flexShrink = 1 },
        tooltip = "Part of a stat's name, as the game or its internal name spells it",
        onSubmit = function(_, text) C.FindStats(text) end },
      UI.Button{ id = "stat_search", text = "Search", style = { marginLeft = 4 },
        onClick = function() C.FindStats() end },
    } },
    UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.Dropdown{ id = "stat_results", choices = { C.STAT_NONE }, value = C.STAT_NONE,
        style = { flexGrow = 1, flexShrink = 1 }, tooltip = "Matching stats: label (internal name) = your value now",
        onChange = function() setText("stat_msg", "") end },
      UI.Button{ id = "stat_add", text = "Add", style = { marginLeft = 4 },
        onClick = function() C.AddPickedStat() end },
    } },
    UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.Dropdown{ id = "stat_shown", choices = { C.STAT_NONE }, value = C.STAT_NONE,
        style = { flexGrow = 1, flexShrink = 1 }, tooltip = "The stats the combat HUD shows",
        onChange = function() setText("stat_msg", "") end },
      UI.Button{ id = "stat_remove", text = "Remove", style = { marginLeft = 4 },
        onClick = function() C.RemovePickedStat() end },
    } },
    UI.Label{ id = "stat_msg", text = "", class = "dim", style = { whiteSpace = "wrap" } },
    UI.Label{ text = "Also in chat: /toolbox stats <word>, /toolbox combat stat add|remove <Name>.",
      class = "dim", style = { whiteSpace = "wrap" } },
    UI.Row{ style = { justifyContent = "end", marginTop = 2 }, children = {
      UI.Button{ id = "combat_reset", text = "Reset fight", onClick = function() M.Reset() end },
    } },
    C.ShoutSection(),
  } }
end

-- Block, parry & dodge (Toolbox.CombatShout), at the end of the Combat page.
function C.ShoutSection()
  local CS = T.CombatShout
  local children = {
    heading("Block, parry & dodge"),
    UI.Label{ text = "When you block, parry or dodge an attack, the word pops up over the middle of the Toolbelt"
      .. " for a moment, with a sound. Pick each sound on the Sounds page.", class = "dim",
      style = { whiteSpace = "wrap" } },
    UI.Toggle{ id = "shout_on", text = "Shout blocks, parries and dodges", value = CS.GetOn(),
      tooltip = "Needs the Toolbelt (the buff bar) showing for the words; the sounds play either way",
      onChange = function(_, v) CS.SetOn(v) end },
    slider("shout_size", "Text size", CS.SIZE_MIN, CS.SIZE_MAX, 1, CS.GetSize(), "The words' size in pixels",
      function(n) CS.SetSize(n) end),
  }
  for _, kind in ipairs(CS.ORDER) do
    local word = CS.WORDS[kind]
    children[#children + 1] = UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
      UI.Toggle{ id = "shout_" .. kind .. "_text", text = "Show " .. word, value = CS.GetText(kind),
        style = { flexGrow = 1 }, tooltip = "\"" .. word .. "\" over the Toolbelt when you " .. kind,
        onChange = function(_, v) CS.SetText(kind, v) end },
      UI.Dropdown{ id = "shout_" .. kind .. "_color", choices = CS.ColorLabels(),
        value = CS.ColorLabel(CS.GetColor(kind)), tooltip = "Its colour (your UI theme's)",
        onChange = function(_, label) CS.SetColor(kind, label) end },
    } }
    children[#children + 1] = UI.Row{ style = { alignItems = "center", marginLeft = 16 }, children = {
      UI.Toggle{ id = "shout_" .. kind .. "_sound", text = CS.LABELS[kind] .. " sound", value = CS.GetSound(kind),
        style = { flexGrow = 1 }, onChange = function(_, v) CS.SetSound(kind, v) end },
      UI.Button{ id = "shout_" .. kind .. "_test", text = "Test",
        tooltip = "Show it over the Toolbelt and play its sound now",
        onClick = function() CS.Shout(kind, true) end },
    } }
  end
  return UI.Column{ children = children }
end

-- The combat HUD's stat picker (owner, 2026-09-29): a search over the readable character stats
-- (T.StatMatches), a results dropdown (label (internal name) = value), Add, and a Remove dropdown of the
-- shown stats. With an empty search the results are C.STAT_SUGGESTIONS (the ones worth starting with).
C.STAT_NONE = "(none)"
C.STAT_RESULTS_MAX = 30
C.STAT_SUGGESTIONS = { "MagicResistance", "CombatHealthRegen", "CombatFocusRegen" }
local statPicks = {}            -- a results label -> the stat's internal name

local function statChoice(st)
  local v = st.value
  local shown = type(v) == "number" and string.format("%g", v) or tostring(v)
  if st.label ~= "" and st.label ~= st.name then return st.label .. " (" .. st.name .. ") = " .. shown end
  return st.name .. " = " .. shown
end

-- Fills the results dropdown for `filter` ("" = the suggestions) and says what it found.
function C.FindStats(filter)
  local field = el.stat_find
  if filter == nil then filter = field and field:GetText() or "" end
  filter = T.Trim(filter)
  local list, total, hidden = {}, 0, 0
  if filter == "" then
    for _, name in ipairs(C.STAT_SUGGESTIONS) do
      local found = T.StatMatches(name, 1)
      if found[1] and found[1].name == name then list[#list + 1] = found[1] end
    end
    total = #list
  else
    list, total, hidden = T.StatMatches(filter, C.STAT_RESULTS_MAX)
  end
  statPicks = {}
  local labels = {}
  for _, st in ipairs(list) do
    local label = statChoice(st)
    labels[#labels + 1] = label
    statPicks[label] = st.name
  end
  local msg = nil
  if filter == "" then
    msg = #labels > 0 and "Suggestions. Search for more." or "Search for a stat by part of its name."
  elseif total == 0 then
    msg = "No readable stat matches '" .. filter .. "'"
      .. (hidden > 0 and (" (" .. hidden .. " hidden from add-ons).") or ".")
  else
    msg = total .. (total == 1 and " stat matches" or " stats match") .. " '" .. filter .. "'"
      .. (total > #labels and (": the first " .. #labels .. "; narrow it down.") or ".")
  end
  if #labels == 0 then labels[1] = C.STAT_NONE end
  local drop = el.stat_results
  if drop then
    drop:SetChoices(labels)
    drop:SetValue(labels[1])
  end
  setEnabled("stat_add", statPicks[labels[1]] ~= nil)
  setText("stat_msg", msg)
end

function C.AddPickedStat()
  local drop = el.stat_results
  local name = drop and statPicks[drop:GetValue()]
  if not name then
    setText("stat_msg", "Search for a stat first, then pick it.")
    return
  end
  local _, msg = T.Combat.AddStat(name)
  setText("stat_msg", msg or "")
  C.Sync()
end

function C.RemovePickedStat()
  local drop = el.stat_shown
  local name = drop and drop:GetValue()
  if not name or name == C.STAT_NONE then return end
  local _, msg = T.Combat.RemoveStat(name)
  setText("stat_msg", msg or "")
  C.Sync()
end

-- The Remove dropdown follows the shown stats (only when they change: SetChoices is a UI call).
local function syncShownStats(list)
  local drop = el.stat_shown
  if not drop then return end
  if not C.statFilled then            -- the Combat page was just built: the suggestions first
    C.statFilled = true
    C.FindStats("")
  end
  local sig = table.concat(list, ",")
  if sig == C.statShownSig then return end
  C.statShownSig = sig
  local choices = #list > 0 and list or { C.STAT_NONE }
  drop:SetChoices(choices)
  drop:SetValue(choices[1])
  setEnabled("stat_remove", #list > 0)
end

-- The "Notifications" category: one toggle and delivery dropdown per source (Toolbox.Notify.SOURCES).
function C.NotifySection()
  local children = {
    heading("Notifications", true),
    UI.Label{ text = "Tells you what's new since you last saw it: in a window, on the notification HUD or in"
      .. " chat, with a sound if you like.",
      class = "dim", style = { whiteSpace = "wrap" } },
    UI.Toggle{ id = "notify_compact", text = "Compact Notifications window", value = T.Notify.GetCompact(),
      tooltip = "Its title bar shows only while the pointer is on it, over the top of the text",
      onChange = function(_, v) T.Notify.SetCompact(v) end },
    slider("notify_font", "Window text size", T.Window.FONT_MIN, T.Window.FONT_MAX, 1, T.Notify.GetFont(),
      "The Notifications window's text size (headings a little larger)",
      function(n) T.Notify.SetFont(n) end),
  }
  for _, src in ipairs(T.Notify.Sources()) do
    local key = src.key
    local vias = T.Notify.Choices(key)
    children[#children + 1] = UI.Row{ style = { alignItems = "center" }, children = {
      UI.Toggle{ id = "notify_" .. key, text = src.label, value = T.Notify.IsOn(key), style = { flexGrow = 1 },
        tooltip = src.tip, onChange = function(_, v) T.Notify.SetOn(key, v) end },
      UI.Dropdown{ id = "notify_" .. key .. "_via", choices = vias,
        value = T.Notify.ChoiceLabel(key),
        tooltip = "Where it shows: the Notifications window, the notification HUD or a chat line; \"+ sound\""
          .. " also plays the notification sound (Sounds)",
        onChange = function(_, label) C.OnNotifyVia(key, label) end },
    } }
  end
  -- The sound itself is picked on the Sounds page (this window is too narrow for a third column per row):
  -- say so here, where "+ sound" is chosen (review, 2026-09-30).
  children[#children + 1] = UI.Label{ id = "notify_sound_hint", text = "Pick which sound each one plays ("
    .. table.concat(T.Notify.SoundLabels(), ", ") .. ") on the Sounds page.", class = "dim",
    style = { whiteSpace = "wrap", marginTop = 4 } }
  local NH = T.Notify.Hud
  local hides = {}
  for i, c in ipairs(NH.HIDE_CHOICES) do hides[i] = c[2] end
  children[#children + 1] = heading("Notification HUD")
  children[#children + 1] = dropdownRow("Hide after", { id = "nhud_hide", choices = hides,
    value = NH.HideLabel(NH.GetHideAfter()) or hides[1],
    tooltip = "The notification HUD shows when something arrives and hides after this (Never: always shown)."
      .. " It keeps the latest 20; the ones new since it last hid are bright",
    onChange = function(_, label) C.OnNotifyHide(label) end })
  children[#children + 1] = slider("nhud_font", "Text size", T.Window.FONT_MIN, T.Window.FONT_MAX, 1, NH.GetFont(),
    "The notification HUD's text size (until you set it, the XP windows' size)",
    function(n) NH.SetFont(n) end)
  children[#children + 1] = slider("nhud_spacing", "Line spacing", T.Window.SPACING_MIN, T.Window.SPACING_MAX, 1,
    NH.GetSpacing(), "Extra pixels between the notification HUD's lines (until you set it, the XP windows')",
    function(n) NH.SetSpacing(n) end)
  children[#children + 1] = shadeSlider("nhud_shade", NH.GetShade(), "the notification HUD",
    function(n) NH.SetShade(n) end)
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
  -- A sound for one effect is set where the effect is picked (the Buffs page); owner, 2026-10-08: looked for here.
  children[#children + 1] = heading("Sounds for one buff or debuff")
  children[#children + 1] = UI.Label{ text = "Any buff or debuff can play your own file (a recording of its name,"
    .. " say) when you get it or when it's about to run out. They're set on the Buffs page, under Muted effects.",
    class = "dim", style = { whiteSpace = "wrap" } }
  children[#children + 1] = UI.Row{ style = { marginTop = 2 }, children = {
    UI.Button{ id = "fx_goto", text = "Go to effect sounds", tooltip = "Opens the Buffs page where they're set",
      onClick = function() C.GoToControl("fx_path") end },
  } }
  -- Which sound each notification plays (when its delivery says "+ sound", on the Notifications page).
  children[#children + 1] = heading("Notification sounds")
  children[#children + 1] = UI.Label{ text = "Played when a notification set to \"+ sound\" arrives"
    .. " (Notifications page).", class = "dim", style = { whiteSpace = "wrap" } }
  local labels = T.Notify.SoundLabels()
  for _, src in ipairs(T.Notify.Sources()) do
    local key = src.key
    children[#children + 1] = dropdownRow(src.label, { id = "notify_" .. key .. "_snd", choices = labels,
      value = T.Notify.SoundLabel(T.Notify.GetSoundKey(key)), tooltip = "The sound for " .. src.label:lower(),
      onChange = function(_, label) T.Notify.SetSoundKey(key, label) end })
  end
  return UI.Column{ children = children }
end

-- The HUD strips with Position rows, in the order the HUD layout category lists them:
-- { id prefix, module, label, the page holding them when not HUD layout }. Built once (config.lua loads last, so
-- every module exists here).
local POSITIONED = {
  { "buff", T.BuffBar, "Buff bar" }, { "vitals", T.Vitals, "Health bars" },
  { "consumables", T.Consumables, "Consumables bar" }, { "gear", T.Gear, "Equipment bar" },
  { "combat", T.Combat, "Combat stats" }, { "nhud", T.Notify.Hud, "Notification HUD" },
  { "target", T.Target, "Target HUD" }, { "buffblock", T.BuffBlock, "Buff block" },
  { "location", T.Location, "Location strip", "map" }, { "launcher", T.Launcher, "Menu" },
  { "plhud", T.Planner.Strip, T.Planner.HUD_NAME, "crafting" },
}
if T.SkillBar then POSITIONED[#POSITIONED + 1] = { "skills", T.SkillBar, T.SkillBar.PAGE } end

-- The "Toolbelt" category: the buff bar with the health bars, consumables and gear repair joined to it,
-- one strip moved as one (owner, 2026-09-29: "this combined bar will be the main selling point").
-- Underneath it is the glue machinery: Hud.SetGlued (health bars beside the buffs) and the consumables
-- and equipment bars' glue (rows under the buffs).
-- The Toolbelt's parts: each is Off, on its Own strip, or In Toolbelt (joined to the buff bar).
C.PLACES = { "Off", "Own strip", "In Toolbelt" }
C.TOOLBELT_PARTS = {
  { key = "vitals", label = "Health, focus & Vigor", tip = "On the left of the buffs",
    shown = function() return T.Vitals.IsShown() end, show = function(on) return T.Vitals.SetShown(on) end,
    glued = function() return T.Hud.IsGlued() end, glue = function(on) return T.Hud.SetGlued(on) end },
  { key = "consumables", label = "Consumables", tip = "Food, potions and combat items: a row under the debuffs",
    shown = function() return T.Consumables.GetShow() end, show = function(on) return T.Consumables.SetShow(on) end,
    glued = function() return T.Consumables.GetGlue() end, glue = function(on) return T.Consumables.SetGlue(on) end },
  { key = "gear", label = "Equipment", tip = "Worn items needing repair: a row under the consumables",
    shown = function() return T.Gear.GetShow() end, show = function(on) return T.Gear.SetShow(on) end,
    glued = function() return T.Gear.GetGlue() end, glue = function(on) return T.Gear.SetGlue(on) end },
  { key = "target", label = "Target", tip = "Your target's health and effects: the last row",
    shown = function() return T.Target.GetShow() end, show = function(on) return T.Target.SetShow(on) end,
    glued = function() return T.Target.GetGlue() end, glue = function(on) return T.Target.SetGlue(on) end },
}

function C.PlaceOf(part)
  if not part.shown() then return "Off" end
  return part.glued() and "In Toolbelt" or "Own strip"
end

-- Puts a part where the player chose. "In Toolbelt" also shows the Toolbelt (the buff bar is its base).
function C.SetPlace(part, label)
  if label == "Off" then
    part.show(false)
  elseif label == "Own strip" or label == "In Toolbelt" then
    local inBelt = label == "In Toolbelt"
    if part.glued() ~= inBelt then part.glue(inBelt) end
    if not part.shown() then part.show(true) end
    if inBelt and not T.BuffBar.IsEnabled() then T.BuffBar.SetShown(true) end
  end
  C.Sync()
end

function C.ToolbeltSection()
  local children = {
    heading("Toolbelt", true),
    UI.Label{ text = "Everything you watch in a fight in one strip, moved as one: your buffs and debuffs, with"
      .. " your health, focus and Vigor beside them, and your consumables, gear repair and target under them.",
      class = "text", style = { whiteSpace = "wrap" } },
    UI.Toggle{ id = "toolbelt_show", text = "Show the Toolbelt", value = T.BuffBar.IsEnabled(),
      style = { marginTop = 6 }, tooltip = "Its base is the buff bar (the same as Buffs: Show buff bar)",
      onChange = function(_, v) T.BuffBar.SetShown(v) end },
    UI.Toggle{ id = "toolbelt_combat", text = "Only during combat", value = T.BuffBar.GetCombatOnly(),
      tooltip = "The whole Toolbelt shows only in combat (and a few seconds after), and while this window is open",
      onChange = function(_, v) T.BuffBar.SetCombatOnly(v) end },
    heading("What goes where"),
    -- the buff bar is always there: "Toolbelt" read as "only what is set to In Toolbelt" (owner, 2026-09-30)
    UI.Label{ id = "toolbelt_base", text = "The Toolbelt is the buff bar; the parts set to In Toolbelt join it.",
      class = "dim", style = { whiteSpace = "wrap" } },
  }
  for _, part in ipairs(C.TOOLBELT_PARTS) do
    children[#children + 1] = dropdownRow(part.label, { id = "toolbelt_" .. part.key, choices = C.PLACES,
      value = C.PlaceOf(part), tooltip = "Off, on its own strip, or in the Toolbelt (" .. part.tip:lower() .. ")",
      onChange = function(_, label) C.SetPlace(part, label) end })
  end
  local placeLabels = {}
  for i, key in ipairs(T.Target.PLACE_ORDER) do placeLabels[i] = T.Target.PLACES[key] end
  children[#children + 1] = dropdownRow("Target row", { id = "target_place", choices = placeLabels,
    value = T.Target.PLACES[T.Target.GetPlace()] or T.Target.PLACES.top,
    tooltip = "In the Toolbelt: above the buffs (its space is kept with no target, so nothing jumps) or under"
      .. " everything (hidden with no target). Not used while Mirrored puts it left of your health bars",
    onChange = function(_, label)
      for key, l in pairs(T.Target.PLACES) do if l == label then T.Target.SetPlace(key) end end
    end })
  children[#children + 1] = UI.Toggle{ id = "target_mirror", text = "Mirrored",
    value = T.Target.GetMirror(), style = { marginLeft = 16 },
    tooltip = "Bars filling from the right and up to 5 icons running left, at a fixed width. In the Toolbelt it"
      .. " goes left of your health bars (they must be in the Toolbelt too; its space is kept, a blank area"
      .. " between the grip and your bars); on its own strip, the strip is mirrored",
    onChange = function(_, v) T.Target.SetMirror(v) end }
  local effectLabels = {}
  for i, key in ipairs(T.Target.EFFECTS) do effectLabels[i] = T.Target.EFFECT_LABELS[key] end
  children[#children + 1] = dropdownRow("Target effects", { id = "target_effects", choices = effectLabels,
    value = T.Target.EFFECT_LABELS[T.Target.GetEffects()],
    tooltip = "Which of your target's effects show as icons: all, debuffs only, or none (just the bars)",
    onChange = function(_, label)
      for key, l in pairs(T.Target.EFFECT_LABELS) do if l == label then T.Target.SetEffects(key) end end
    end })
  children[#children + 1] = slider("target_icons", "Most target icons", 1, T.Target.SLOTS, 1, T.Target.GetIcons(),
    "How many of your target's effects show at once (mirrored, its width is kept for this many)",
    function(n) T.Target.SetIcons(n) end)
  -- The target's bars: the health bars' look options, its own (their Size and Bar length it shares)
  local TG = T.Target
  children[#children + 1] = heading("Target bars")
  children[#children + 1] = UI.Toggle{ id = "target_show_bars", text = "Show bars", value = TG.GetShowBars(),
    tooltip = "With the numbers off too, the target HUD is just its effect icons",
    onChange = function(_, v) TG.SetShowBars(v) end }
  children[#children + 1] = UI.Toggle{ id = "target_show_text", text = "Show numbers", value = TG.GetShowText(),
    tooltip = "Health and focus as numbers beside the bars (large ones shortened: 12.5k; the tooltip has them all)",
    onChange = function(_, v) TG.SetShowText(v) end }
  children[#children + 1] = dropdownRow("Number background", { id = "target_bg", choices = T.Vitals.BackgroundNames(),
    value = TG.GetBackground(), tooltip = "A dark or light panel behind the target's numbers",
    onChange = function(_, value) TG.SetBackground(value) end })
  children[#children + 1] = shadeSlider("target_shade", TG.GetShade(), "the target's numbers (Dark)",
    function(n) TG.SetShade(n) end)
  children[#children + 1] = UI.Toggle{ id = "target_hide_pet", text = "Leave out your pet", value = TG.GetHidePet(),
    tooltip = "Once the fight is over the game targets your pet; with this, the target HUD stays empty instead",
    onChange = function(_, v) TG.SetHidePet(v) end }
  children[#children + 1] = UI.Toggle{ id = "target_flash", text = "Flash when low", value = TG.GetFlash(),
    tooltip = "Your target's health or focus flashes below the percentage under this",
    onChange = function(_, v) TG.SetFlash(v) end }
  children[#children + 1] = slider("target_flash_below", "Flash below (%)", T.Vitals.FLASH_MIN, T.Vitals.FLASH_MAX, 1,
    TG.GetFlashBelow(), "The target's health or focus under this percentage flashes",
    function(n) TG.SetFlashBelow(n) end)
  children[#children + 1] = UI.Row{ style = { justifyContent = "end", marginTop = 2 }, children = {
    UI.Button{ id = "target_flash_test", text = "Test flash",
      tooltip = "Flash the target's bars for " .. T.Vitals.PREVIEW_SECONDS .. " seconds to see what it looks like",
      onClick = function() TG.PreviewFlash() end },
  } }
  children[#children + 1] = UI.Label{ text = "Their size follows your health bars' Size and Bar length (Health bars"
    .. " page).", class = "dim", style = { whiteSpace = "wrap", marginTop = 4 } }
  children[#children + 1] = UI.Label{ id = "hud_summary", text = "", class = "dim",
    style = { whiteSpace = "wrap", marginTop = 6 } }
  children[#children + 1] = UI.Label{ text = "Place it under HUD layout (Buff bar), or drag its grip. Each bar's"
    .. " own options are on its page (Buffs, Consumables & gear, Health bars).", class = "dim",
    style = { whiteSpace = "wrap", marginTop = 4 } }
  return UI.Column{ children = children }
end

-- The "Map & location" category (owner, 2026-10-13: map features to come get their own page): the location strip, with
-- its place, and the Loot Tracker's runs on the map.
function C.MapSection()
  local loc = T.Location
  local children = {
    heading("Map & location", true),
    heading("Location strip"),
    UI.Toggle{ id = "loc_show", text = "Show where you are", value = loc.GetShow(),
      tooltip = "A strip with the scene you're in, your position (x, height, z, as /loc gives it) and which way"
        .. " you face. Hover it for the whole /loc line",
      onChange = function(_, v) loc.SetShow(v) end },
    UI.Toggle{ id = "loc_facing", text = "Which way you face", value = loc.GetFacing(),
      tooltip = "The compass direction and degrees (0 north, 90 east)",
      onChange = function(_, v) loc.SetFacing(v) end },
    UI.Toggle{ id = "loc_water", text = "Fishable water in this scene", value = loc.GetWater(),
      enabled = loc.HasWater(),
      tooltip = loc.HasWater() and "The kinds of water you can fish in here (salt, fresh...): what to expect"
        .. " on your line" or "Needs a newer game client (Lua API 32)",
      onChange = function(_, v) loc.SetWater(v) end },
    shadeSlider("loc_shade", loc.GetShade(), "the location strip", function(n) loc.SetShade(n) end),
    UI.Toggle{ id = "loc_pin", text = "Map overlays button", value = loc.GetPin(),
      tooltip = "A pin beside the scene's name: a click opens the Map overlays window (mark where you stand)",
      onChange = function(_, v) loc.SetPin(v) end },
    UI.Toggle{ id = "loc_overlay", text = "The overlay shown on the map", value = loc.GetOverlay(),
      tooltip = "A line naming the map overlay this scene shows, with arrows to step through its overlays (yours,"
        .. " Gathering, Fights)",
      onChange = function(_, v) loc.SetOverlay(v) end },
    C.PositionRows("location", loc, "Location strip"),
    C.OverlayRows(),
    heading("Loot Tracker runs"),
    UI.Toggle{ id = "dd_markers", text = "Show runs on the map", value = T.DailyDetail.GetMarkers(),
      enabled = T.DailyDetail.HasMarkers(),
      tooltip = T.DailyDetail.HasMarkers() and "A flag on your map and minimap where each Loot Tracker run was played"
        .. " most, in its scene; hover it for what the run brought in" or "Needs a newer game client (Lua API 30)",
      onChange = function(_, value) T.DailyDetail.SetMarkers(value) end },
  }
  return UI.Column{ children = children }
end

-- Map overlays (Toolbox.Overlays, hud.lua): only the button opening the Map overlays window, where every overlay
-- control is (owner, 2026-10-13: marking without the whole settings page up).
function C.OverlayRows()
  local OV = T.Overlays
  return UI.Column{ children = {
    heading("Map overlays"),
    UI.Label{ text = "Sets of places you mark in a scene, one set on its map at a time: one for loot, one for"
      .. " gathering... Each scene has its own: up to " .. OV.MAX .. ", " .. OV.SCENE_MAX .. " places each. Make"
      .. " them, mark and pick the one shown in the Map overlays window (also the pin on the location strip)."
      .. (OV.HasMarkers() and "" or " Your game client can't show them on the map yet (Lua API 30): Compass points"
        .. " you to a place."),
      class = "dim", style = { whiteSpace = "wrap", marginTop = 6 } },
    UI.Row{ style = { marginTop = 4 }, children = {
      UI.Button{ id = "ov_window", text = "Open the Map overlays window",
        tooltip = "Make, show, rename and delete overlays, mark where you stand and this scene's places (or /"
          .. T.commands[1] .. " overlay window)", onClick = function() T.Overlays.ToggleWindow() end },
    } },
    UI.Toggle{ id = "ov_death", text = "Show your last death on the map", value = T.Location.GetDeath(),
      enabled = OV.HasMarkers(), style = { marginTop = 4 },
      tooltip = OV.HasMarkers() and ("A magenta diamond where you last died, in its scene, beside any overlay (/"
        .. T.commands[1] .. " death compass points you back)") or "Needs a newer game client (Lua API 30)",
      onChange = function(_, v) T.Location.SetDeath(v) end },
    UI.Toggle{ id = "ov_auto_new", text = "Auto map adventure areas", value = T.Location.GetAutoNew(),
      style = { marginTop = 4 },
      tooltip = "Mark the nodes you gather and the creatures you kill in every adventure area, unless you switch it"
        .. " off there; never in towns, player towns and basements unless you switch it on there (the Map overlays"
        .. " window's Gathering and Fights)",
      onChange = function(_, v) T.Location.SetAutoNew(v) end },
  } }
end

-- The "HUD layout" category: the strips' positions, in one place (but Location's, on Map & location).
function C.HudSection()
  local children = {
    heading("HUD layout", true),
    UI.Label{ text = "Strips show while this window is open, so you can place them. Drag a strip's grip"
      .. " (untick Options > Interface > Nameplates & Chat Bubbles > Lock Status Movement to see it) or"
      .. " use the buttons.", class = "dim", style = { whiteSpace = "wrap", marginTop = 6 } },
    UI.Label{ text = "The location strip is placed on the Map & location page, the " .. T.Planner.HUD_NAME
      .. " on the Crafting page.", class = "dim",
      style = { whiteSpace = "wrap", marginTop = 4 } },
  }
  for _, p in ipairs(POSITIONED) do
    if not p[4] then children[#children + 1] = C.PositionRows(p[1], p[2], p[3]) end
  end
  return UI.Column{ children = children }
end

-- The "Backup & reset" category: where the settings files are (the player copies them), and Reset, which
-- takes a second click within C.CONFIRM_SECONDS (there is no window slot for a dialog) and waits for the
-- next start (Toolbox.Backup).
C.CONFIRM_SECONDS = 5
local resetArmedAt = nil
local RESET_TEXT = "Reset all settings"

-- Puts the Reset button's text back once its confirmation time is up (from SyncLive, every second).
local function disarm()
  if resetArmedAt and T.Now() - resetArmedAt > C.CONFIRM_SECONDS then
    resetArmedAt = nil
    setText("settings_reset", RESET_TEXT)
  end
end

function C.SaveSettingsNow()
  setText("backup_msg", T.Backup.SaveNow() == false and "The game refused to write the files."
    or "Saved: the files are up to date. Copy them now.")
end

function C.ResetSettings()
  if not (resetArmedAt and T.Now() - resetArmedAt <= C.CONFIRM_SECONDS) then
    resetArmedAt = T.Now()
    setText("settings_reset", "Click again to confirm")
    return
  end
  resetArmedAt = nil
  setText("settings_reset", RESET_TEXT)
  local ok, why = T.Backup.RequestReset()
  setText("backup_msg", ok and ("Reset waiting: type /lua reload to apply it." .. T.Backup.BackupNote(why))
    or ("Couldn't ask for a reset: " .. why .. "."))
  C.restoreDirty = true                -- the copy made for it
  C.Sync()
end

function C.CancelPending()
  local had, written = T.Backup.Cancel()
  setText("backup_msg", (had and "Dropped." or "Nothing was waiting.")
    .. (written and "" or " The game couldn't write that to disk."))
  C.Sync()
end

-- Back up now and Restore (Toolbox.Backup, API 39; owner, 2026-10-16): this character's file's copies in a
-- dropdown, read from the game when the page is built, for another character and after Back up now / Restore (a
-- disk listing: not every Sync); Restore takes a second click within C.CONFIRM_SECONDS on the same copy.
C.RESTORE_NONE = "No copies yet"
local RESTORE_TEXT = "Restore"
local restorePicks = {}              -- dropdown label -> backup { name, label }
local restoreArmed = nil             -- { at = T.Now(), name = the copy it was armed for }
C.restoreDirty = true

local function disarmRestore(staleOnly)
  if restoreArmed and (not staleOnly or T.Now() - restoreArmed.at > C.CONFIRM_SECONDS) then
    restoreArmed = nil
    setText("bk_restore", RESTORE_TEXT)
  end
end

local function syncRestore()
  local drop = el.bk_pick
  if not drop then return end
  if C.restoreFor ~= T.settingsFor then
    C.restoreFor = T.settingsFor
    C.restoreDirty = true
  end
  if not C.restoreDirty then return end
  C.restoreDirty = false
  disarmRestore()
  restorePicks = {}
  local labels = {}
  for _, b in ipairs(T.Backup.BackupList()) do
    local label = b.label
    if restorePicks[label] then label = label .. " (" .. (#labels + 1) .. ")" end   -- two in one minute
    restorePicks[label] = b
    labels[#labels + 1] = label
  end
  drop:SetChoices(#labels > 0 and labels or { C.RESTORE_NONE })
  drop:SetValue(labels[1] or C.RESTORE_NONE)
  setEnabled("bk_restore", #labels > 0)
end

-- Back up now and Restore say it in chat too (owner, 2026-10-16: the page's line alone went unnoticed).
local function backupSay(text)
  setText("backup_msg", text)
  T.Print(text)
end

function C.BackupNow()
  local name, why, account = T.Backup.BackupNow()
  C.restoreDirty = true
  syncRestore()
  if name then
    backupSay("Kept a copy of this character's file: " .. name .. (account and (", and of the"
      .. " account file: " .. account) or "") .. " (in Lua/SavedVariables).")
  else
    local word = tostring(why):match("^false (%a+)$")
    backupSay("The game kept no copy: " .. (word and T.Backup.BACKUP_REASONS[word] or tostring(why)) .. ".")
  end
end

function C.RestoreBackup()
  local drop = el.bk_pick
  local b = drop and restorePicks[drop:GetValue()]
  if not b then
    setText("backup_msg", "Pick a copy first.")
    return
  end
  if not (restoreArmed and restoreArmed.name == b.name and T.Now() - restoreArmed.at <= C.CONFIRM_SECONDS) then
    disarmRestore()
    restoreArmed = { at = T.Now(), name = b.name }
    setText("bk_restore", "Click again to confirm")
    setText("backup_msg", "Restoring puts this character's settings and positions back as they were at "
      .. b.label .. ". The file as it is now is kept as a copy too. Click Restore again to go ahead.")
    return
  end
  disarmRestore()
  local ok, kept, warn = T.Backup.Restore(b.name)
  C.restoreDirty = true
  syncRestore()
  backupSay(ok and ("Restored the settings and positions from " .. b.label
    .. (warn and (", " .. warn) or "") .. "." .. (kept and (" The file it replaced was kept as a copy: " .. kept
    .. ".") or " The file already held that copy's settings.")) or ("Couldn't restore: " .. tostring(kept) .. "."))
  C.Sync()
end

-- Muted effects (Toolbox.BuffBar): no expiry or debuff sound for the effects picked. Both lists are dropdowns
-- (owner, 2026-10-04: names are hard to type): recent alerts, what's on you and every effect seen cast; and
-- the muted ones, to unmute.
C.QUIET_NONE = "Nothing to pick yet"
C.MUTED_NONE = "None muted"
local quietPicks = {}                -- dropdown label -> effect name
local mutedPicks = {}                -- the muted list's label -> effect name

-- Refills both dropdowns when what they'd offer changed (SetChoices is a UI call; only then). From Sync and,
-- while the window shows, SyncLive (alerts and effects come and go).
local function syncQuiet()
  local pick, muted = el.quiet_pick, el.quiet_list
  if not (pick and muted) then return end
  local choices = T.BuffBar.QuietChoices()
  local labels = {}
  for i, c in ipairs(choices) do labels[i] = c.label end
  local list = {}
  local mchoices = T.BuffBar.MutedChoices()
  for i, c in ipairs(mchoices) do list[i] = c.label end
  local sig = table.concat(labels, "|") .. "||" .. table.concat(list, "|")
  if sig == C.quietSig then return end
  C.quietSig = sig
  quietPicks, mutedPicks = {}, {}
  for _, c in ipairs(choices) do quietPicks[c.label] = c.name end
  for _, c in ipairs(mchoices) do mutedPicks[c.label] = c.name end
  local keep = pick:GetValue()
  local shown = #labels > 0 and labels or { C.QUIET_NONE }
  pick:SetChoices(shown)
  pick:SetValue(quietPicks[keep] and keep or shown[1])
  local keepMuted = muted:GetValue()
  local mshown = #list > 0 and list or { C.MUTED_NONE }
  muted:SetChoices(mshown)
  local still = false
  for _, n in ipairs(list) do if n == keepMuted then still = true end end
  muted:SetValue(still and keepMuted or mshown[1])
  setEnabled("quiet_mute", #labels > 0)
  setEnabled("quiet_unmute", #list > 0)
end

function C.MutePicked()
  local drop = el.quiet_pick
  local name = drop and quietPicks[drop:GetValue()]
  local _, msg = T.BuffBar.Mute(name)
  setText("quiet_msg", msg or "")
end

function C.UnmutePicked()
  local drop = el.quiet_list
  local name = drop and mutedPicks[drop:GetValue()]
  local _, msg = T.BuffBar.Unmute(name)
  setText("quiet_msg", msg or "")
end

function C.QuietRows()
  C.quietSig = nil                     -- new controls: filled by the next Sync
  return UI.Column{ style = { marginTop = 6 }, children = {
    UI.Label{ text = "Muted effects: no sound for these, though their icons still flash. Pick from recent alerts,"
      .. " what's on you, or anything you've cast.", class = "dim", style = { whiteSpace = "wrap" } },
    UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.Dropdown{ id = "quiet_pick", choices = { C.QUIET_NONE }, value = C.QUIET_NONE,
        style = { flexGrow = 1, flexShrink = 1 },
        tooltip = "Recent alerts first (alerted), then your effects now (on you), then every effect seen cast",
        onChange = function() setText("quiet_msg", "") end },
      UI.Button{ id = "quiet_mute", text = "Mute", style = { marginLeft = 4 },
        tooltip = "No expiry or debuff sound for this effect", onClick = function() C.MutePicked() end },
    } },
    UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.Dropdown{ id = "quiet_list", choices = { C.MUTED_NONE }, value = C.MUTED_NONE,
        style = { flexGrow = 1, flexShrink = 1 }, tooltip = "The muted effects",
        onChange = function() setText("quiet_msg", "") end },
      UI.Button{ id = "quiet_unmute", text = "Unmute", style = { marginLeft = 4 },
        tooltip = "Its sounds come back", onClick = function() C.UnmutePicked() end },
    } },
    UI.Label{ id = "quiet_msg", text = "", class = "dim", style = { whiteSpace = "wrap" } },
  } }
end

-- Effect sounds (Toolbox.BuffBar; owner, 2026-10-08): a player's own file for an effect, instead of the usual
-- expiry or debuff sound. The effect is picked in Muted effects' dropdown (one list of up to BB.CHOICES_MAX names on
-- screen, not two: the text budget), the path pasted, Set; the list below has Test and Remove.
C.FX_NONE = "No effect sounds yet"
local fxSet = {}                     -- the list's label -> { name, when }

local function syncEffectSounds()
  local list = el.fx_list
  if not list then return end
  local set = T.BuffBar.EffectSoundChoices()
  local setLabels = {}
  for i, c in ipairs(set) do setLabels[i] = c.label end
  setEnabled("fx_set", next(quietPicks) ~= nil)
  setEnabled("fx_choose", next(quietPicks) ~= nil)
  local sig = table.concat(setLabels, "|")
  if sig == C.fxSig then return end
  C.fxSig = sig
  fxSet = {}
  for _, c in ipairs(set) do fxSet[c.label] = c end
  local keepSet = list:GetValue()
  local sshown = #setLabels > 0 and setLabels or { C.FX_NONE }
  list:SetChoices(sshown)
  list:SetValue(fxSet[keepSet] and keepSet or sshown[1])
  setEnabled("fx_test", #setLabels > 0)
  setEnabled("fx_remove", #setLabels > 0)
end

-- The effect and when, as picked on the page now.
local function effectPicked()
  local drop, whenDrop = el.quiet_pick, el.fx_when
  local name = drop and quietPicks[drop:GetValue()]
  local when = nil
  for _, w in ipairs(T.BuffBar.SOUND_WHEN) do
    if whenDrop and whenDrop:GetValue() == w[2] then when = w[1] end
  end
  return name, when or "end"
end

-- `name` / `when`: as picked when the file list opened (C.ChooseEffectSound), else as picked now.
function C.SetEffectSound(text, name, when)
  local field = el.fx_path
  if name == nil then name, when = effectPicked() end
  local path = text
  if path == nil and field then path = field:GetText() end
  local ok, msg = T.BuffBar.SetEffectSound(name, path, when)
  setText("fx_msg", msg or "")
  if ok and field then field:SetText("") end
end

-- Picks the file from the game's list (API 33) for the effect and time picked now.
function C.ChooseEffectSound()
  local name, when = effectPicked()
  if not name then
    setText("fx_msg", "Pick the effect first (the list above).")
    return
  end
  local ok, why = T.Sounds.Pick("A sound for " .. T.BuffBar.ShownName(name), function(path, bad)
    if not path then
      setText("fx_msg", tostring(bad))
      if not el.fx_msg then T.Print(tostring(bad)) end
      return
    end
    C.SetEffectSound(path, name, when)
    if not el.fx_msg then T.Print("Sound set: " .. path) end
  end)
  if not ok then setText("fx_msg", "Can't choose a file now: " .. why .. ".") end
end

local function pickedSound()
  local drop = el.fx_list
  return drop and fxSet[drop:GetValue()]
end

function C.TestEffectSound()
  local c = pickedSound()
  local _, msg = T.BuffBar.TestEffectSound(c and c.name, c and c.when)
  setText("fx_msg", msg or "")
end

function C.RemoveEffectSound()
  local c = pickedSound()
  if not c then return end
  local _, msg = T.BuffBar.RemoveEffectSound(c.name, c.when)
  setText("fx_msg", msg or "")
end

local function whenLabels()
  local out = {}
  for i, w in ipairs(T.BuffBar.SOUND_WHEN) do out[i] = w[2] end
  return out
end

function C.EffectSoundRows()
  C.fxSig = nil                        -- new controls: filled by the next Sync
  local rows = {
    UI.Label{ text = "Or give the effect picked above its own sound (record its name, say), when you get it or when"
      .. " it's about to run out: a file inside your Lua folder, not the toolbox folder.", class = "dim",
      style = { whiteSpace = "wrap" } },
    UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.Dropdown{ id = "fx_when", choices = whenLabels(), value = T.BuffBar.WhenLabel("end"),
        style = { flexGrow = 1, flexShrink = 1 }, tooltip = "When this file plays",
        onChange = function() setText("fx_msg", "") end },
    } },
    UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.TextField{ id = "fx_path", text = "", placeholder = "toolbox_sounds/atos.ogg", maxLength = 200,
        style = { flexGrow = 1, flexShrink = 1 },
        tooltip = "A .ogg/.wav/.mp3 inside your Lua folder (a full path is cut after Lua); Enter sets it",
        onSubmit = function(_, text) C.SetEffectSound(text) end },
      UI.Button{ id = "fx_set", text = "Set", style = { marginLeft = 4 },
        tooltip = "The effect picked above plays this file instead of the usual sound",
        onClick = function() C.SetEffectSound() end },
    } },
    UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.Dropdown{ id = "fx_list", choices = { C.FX_NONE }, value = C.FX_NONE,
        style = { flexGrow = 1, flexShrink = 1 }, tooltip = "The effects with a sound of their own",
        onChange = function() setText("fx_msg", "") end },
      UI.Button{ id = "fx_test", text = "Test", style = { marginLeft = 4 },
        tooltip = "Play it now", onClick = function() C.TestEffectSound() end },
      UI.Button{ id = "fx_remove", text = "Remove", style = { marginLeft = 4 },
        tooltip = "It plays the usual sound again", onClick = function() C.RemoveEffectSound() end },
    } },
    UI.Label{ id = "fx_msg", text = "", class = "dim", style = { whiteSpace = "wrap" } },
  }
  if T.Sounds.CanPick() then             -- API 33: the game's file list, under the path's row
    table.insert(rows, 4, UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.Button{ id = "fx_choose", text = "Choose a file...", style = { flexGrow = 1, flexShrink = 1 },
        tooltip = "Pick the sound from your Lua folder in the game's file list, for the effect and time picked above",
        onClick = function() C.ChooseEffectSound() end },
    } })
  end
  return UI.Column{ style = { marginTop = 6 }, children = rows }
end

-- Setups (Toolbox.Backup): import another character's settings and positions, export yours under a name.
-- Import and Delete take a second click within C.CONFIRM_SECONDS, like Reset.
C.SETUP_NONE = "No setups yet"
local setupPicks = {}                -- dropdown label -> setup
-- The armed button: { at = T.Now(), id = the setup it was armed for } (review, 2026-10-04: a second click on
-- another setup must not act on it).
local setupArmed = { import = nil, delete = nil }
local SETUP_BUTTONS = { import = { "setup_import", "Import" }, delete = { "setup_delete", "Delete" } }

local function pickedSetup()
  local drop = el.setup_pick
  return drop and setupPicks[drop:GetValue()]
end

-- Who armed it is part of it (review, 2026-10-07, 12): a click after a character switch only asks again.
local function setupId(s) return tostring(T.settingsFor) .. ">" .. (s.character and "c:" or "n:") .. s.name:lower() end

-- Puts both buttons back (another pick, another list, an action done, or their time up when `stale` only).
local function disarmSetups(staleOnly)
  for which, b in pairs(SETUP_BUTTONS) do
    local armed = setupArmed[which]
    if armed and (not staleOnly or T.Now() - armed.at > C.CONFIRM_SECONDS) then
      setupArmed[which] = nil
      setText(b[1], b[2])
    end
  end
end

-- Fills the dropdown when the setups change (SetChoices is a UI call: only then).
local function syncSetups()
  local drop = el.setup_pick
  if not drop then return end
  if C.setupOwner ~= T.settingsFor then  -- another character: the buttons it armed go back
    C.setupOwner = T.settingsFor
    disarmSetups()
  end
  local list = T.Backup.Setups()
  local labels = {}
  for _, s in ipairs(list) do labels[#labels + 1] = s.label end
  local sig = table.concat(labels, "|")
  if sig == C.setupSig then return end
  C.setupSig = sig
  setupPicks = {}
  for _, s in ipairs(list) do setupPicks[s.label] = s end
  local choices = #labels > 0 and labels or { C.SETUP_NONE }
  local keep = drop:GetValue()
  disarmSetups()
  drop:SetChoices(choices)
  drop:SetValue(setupPicks[keep] and keep or choices[1])
  setEnabled("setup_import", #labels > 0)
  setEnabled("setup_delete", #labels > 0)
end

-- A button that acts on its second click within C.CONFIRM_SECONDS, on the same setup `s`.
local function confirmed(which, s)
  local armed = setupArmed[which]
  if armed and armed.id == setupId(s) and T.Now() - armed.at <= C.CONFIRM_SECONDS then
    disarmSetups()
    return true
  end
  disarmSetups()
  setupArmed[which] = { at = T.Now(), id = setupId(s) }
  setText(SETUP_BUTTONS[which][1], "Click again to confirm")
  return false
end

function C.ImportSetup()
  local s = pickedSetup()
  if not s then
    setText("setup_msg", "Pick a setup first.")
    return
  end
  if not confirmed("import", s) then
    setText("setup_msg", "Importing replaces this character's settings and positions with a copy of '"
      .. s.name .. "'. Click Import again to go ahead.")
    return
  end
  local ok, why = T.Backup.Import(s)
  C.restoreDirty = true                -- the game's copy from before it
  setText("setup_msg", ok and ("Imported '" .. s.name .. "'. Later changes stay this character's own."
    .. (why and (" (" .. why .. ")") or "") .. T.Backup.BackupNote(T.Backup.lastBackup))
    or ("Couldn't import: " .. tostring(why) .. "."))
  C.Sync()
end

function C.DeleteSetup()
  local s = pickedSetup()
  if not s then
    setText("setup_msg", "Pick a setup first.")
    return
  end
  if not confirmed("delete", s) then
    setText("setup_msg", "Click Delete again to delete '" .. s.name .. "'.")
    return
  end
  local ok, why = T.Backup.DeleteSetup(s)
  setText("setup_msg", ok and ("Deleted '" .. s.name .. "'." .. (s.character
    and " That character's copy comes back when it next plays, if it still lists its setup." or ""))
    or ("Couldn't delete '" .. s.name .. "': " .. tostring(why) .. "."))
  C.Sync()
end

function C.ExportSetup(text)
  local field = el.setup_name
  if text == nil then text = field and field:GetText() or "" end
  local ok, name = T.Backup.Export(text)
  setText("setup_msg", ok and ("Exported as '" .. name .. "'. Any character on this computer can import it.")
    or ("Couldn't export: " .. name .. "."))
  C.Sync()
end

function C.SetupSection()
  C.setupSig = nil                     -- new controls: filled by the next Sync
  setupArmed.import, setupArmed.delete = nil, nil
  return UI.Column{ children = {
    heading("Setups"),
    UI.Label{ text = "Copy the settings and positions of another character on this computer, yours or"
      .. " someone else's. A character's setup is listed once its player ticks the box below; Export saves"
      .. " yours under a name. An import is a copy: later changes stay each character's own.", class = "dim",
      style = { whiteSpace = "wrap", marginTop = 6 } },
    UI.Toggle{ id = "setup_share", text = "List this character's setup for other characters",
      value = T.Backup.GetShare(), style = { marginTop = 4 },
      tooltip = "Off: nobody can import this character's settings and positions (named exports still work)",
      onChange = function(_, v)
        local ok, why = T.Backup.SetShare(v)
        local fail = v and "Couldn't list your setup: " or "Couldn't take your setup off the list: "
        setText("setup_msg", ok and "" or (fail .. tostring(why) .. "."))
      end },
    UI.Row{ style = { alignItems = "center", marginTop = 4 }, children = {
      UI.Dropdown{ id = "setup_pick", choices = { C.SETUP_NONE }, value = C.SETUP_NONE,
        style = { flexGrow = 1, flexShrink = 1 }, tooltip = "Named setups, then other characters' setups",
        onChange = function()
          disarmSetups()
          setText("setup_msg", "")
        end },
      UI.Button{ id = "setup_import", text = "Import", style = { marginLeft = 4 },
        tooltip = "Replace this character's settings and positions with a copy of this setup",
        onClick = function() C.ImportSetup() end },
      UI.Button{ id = "setup_delete", text = "Delete", style = { marginLeft = 4 },
        tooltip = "Remove this setup from the list", onClick = function() C.DeleteSetup() end },
    } },
    UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.TextField{ id = "setup_name", text = "", placeholder = "A name: Raid layout, Mom...",
        maxLength = T.Backup.NAME_MAX, style = { flexGrow = 1, flexShrink = 1 },
        tooltip = "Save this character's settings and positions under this name",
        onSubmit = function(_, text) C.ExportSetup(text) end },
      UI.Button{ id = "setup_export", text = "Export", style = { marginLeft = 4 },
        tooltip = "Save this character's settings and positions under the name, for any character to import",
        onClick = function() C.ExportSetup() end },
    } },
    UI.Label{ id = "setup_msg", text = "", class = "dim", style = { whiteSpace = "wrap", marginTop = 4 } },
  } }
end

-- The menu (Toolbox.Launcher, hud.lua; owner, 2026-10-10): its options lead this page.
function C.MenuRows(children)
  local L = T.Launcher
  local function add(e) children[#children + 1] = e end
  add(heading("Menu", true))
  add(UI.Label{ text = "Buttons that open Toolbox's windows (or show the location strip) with one click, bright while"
    .. " a window is open. Move it by its grip (or under HUD layout).", class = "dim",
    style = { whiteSpace = "wrap", marginTop = 6 } })
  add(UI.Toggle{ id = "ln_show", text = "Show the menu", value = L.GetShow(),
    tooltip = "Off: open the windows from these settings, as before", onChange = function(_, v) L.SetShow(v) end })
  add(UI.Toggle{ id = "ln_vertical", text = "Vertical", value = L.GetVertical(),
    tooltip = "Off: the buttons in a row", onChange = function(_, v) L.SetVertical(v) end })
  add(UI.Toggle{ id = "ln_combat", text = "Hide during combat", value = L.GetHideInCombat(),
    tooltip = "Out of the way in a fight; back a few seconds after",
    onChange = function(_, v) L.SetHideInCombat(v) end })
  add(slider("ln_size", "Icon size", L.SIZE_MIN, L.SIZE_MAX, 2, L.GetSize(), "The buttons' size in pixels",
    function(n) L.SetSize(n) end))
  local colors = {}
  for i, col in ipairs(L.COLORS) do colors[i] = col[2] end
  add(dropdownRow("Icon color", { id = "ln_color", choices = colors, value = L.ColorName(L.GetColor()),
    tooltip = "The buttons' color (the theme's, so it follows your UI skin)",
    onChange = function(_, v) L.SetColor(v) end }))
  add(slider("ln_shade", "Background shade (%)", 0, L.SHADE_MAX, 5, L.GetShade(),
    "How dark the panel behind the buttons is, so they stand out; 0: none", function(n) L.SetShade(n) end))
  add(UI.Label{ text = "Buttons:", class = "text", style = { marginTop = 6 } })
  local cells = {}
  for i, b in ipairs(L.BUTTONS) do        -- two to a row
    local key = b.key
    cells[#cells + 1] = UI.Toggle{ id = "ln_btn_" .. key, text = b.name, value = L.GetButton(key),
      style = { flexGrow = 1, width = "50%" }, tooltip = "Show the " .. b.name .. " button",
      onChange = function(_, v)
        local ok, why = L.SetButton(key, v)
        if not ok then
          T.Print(why)
          C.Sync()
        end
      end }
    if i % 2 == 0 or i == #L.BUTTONS then
      add(UI.Row{ children = cells })
      cells = {}
    end
  end
end

function C.BackupSection()
  local children = {}
  C.MenuRows(children)
  children[#children + 1] = heading("Backup")
  for i, line in ipairs(T.Backup.HowTo()) do
    local spec = { text = line, class = "dim", style = { whiteSpace = "wrap", marginTop = 3 } }
    if i == 1 then
      spec.id, spec.class, spec.style.marginTop = "backup_where", "text", 6
    end
    children[#children + 1] = UI.Label(spec)
  end
  local saveRow = {
    UI.Button{ id = "backup_save", text = "Save now", tooltip = "Write the settings files now, ready to copy",
      onClick = function() C.SaveSettingsNow() end },
  }
  if T.Backup.CanRestore() then          -- API 39: the game's copies
    C.restoreDirty, restoreArmed = true, nil
    saveRow[2] = UI.Button{ id = "bk_now", text = "Back up now", style = { marginLeft = 4 },
      tooltip = "The game keeps a dated copy of this character's file and the account file (one a minute)",
      onClick = function() C.BackupNow() end }
  end
  children[#children + 1] = UI.Row{ style = { marginTop = 4 }, children = saveRow }
  if T.Backup.CanRestore() then
    children[#children + 1] = UI.Label{ text = "Copies of this character's file, newest first. The game keeps"
      .. " the last five, made by Back up now and before a reset, an import or a new version.", class = "dim",
      style = { whiteSpace = "wrap", marginTop = 6 } }
    children[#children + 1] = UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
      UI.Dropdown{ id = "bk_pick", choices = { C.RESTORE_NONE }, value = C.RESTORE_NONE,
        style = { flexGrow = 1, flexShrink = 1 }, tooltip = "The copy to put back",
        onChange = function() disarmRestore() end },
      UI.Button{ id = "bk_restore", text = RESTORE_TEXT, style = { marginLeft = 4 },
        tooltip = "Put this character's settings and positions back as they were in this copy",
        onClick = function() C.RestoreBackup() end },
    } }
  end
  children[#children + 1] = C.SetupSection()
  children[#children + 1] = heading("Reset")
  children[#children + 1] = UI.Label{ text = "Every setting and position goes back to its default at the next"
    .. " /lua reload. Your stats, XP session and learned buff lengths are kept.", class = "dim",
    style = { whiteSpace = "wrap", marginTop = 6 } }
  children[#children + 1] = UI.Row{ style = { marginTop = 4 }, children = {
    UI.Button{ id = "settings_reset", text = RESET_TEXT,
      tooltip = "Back to the defaults at the next /lua reload; copy the files first to keep these",
      onClick = function() C.ResetSettings() end },
    UI.Button{ id = "backup_cancel", text = "Cancel", style = { marginLeft = 4 },
      tooltip = "Drop the waiting reset", onClick = function() C.CancelPending() end },
  } }
  children[#children + 1] = UI.Label{ id = "backup_pending", text = "A reset is waiting: type /lua reload to"
    .. " apply it.", class = "warning", visible = false, style = { whiteSpace = "wrap", marginTop = 6 } }
  children[#children + 1] = UI.Label{ id = "backup_msg", text = "", class = "dim",
    style = { whiteSpace = "wrap", marginTop = 4 } }
  return UI.Column{ children = children }
end

-- key, label, builder. The first is shown when the window first opens.
C.CATEGORIES = {
  { key = "general", label = "General", build = function() return C.GeneralSection() end },
  { key = "toolbelt", label = "Toolbelt", build = function() return C.ToolbeltSection() end },
  { key = "xp", label = "XP & Loot", build = function() return C.XPSection() end },
  { key = "crafting", label = "Crafting", build = function() return C.CraftingSection() end },
  { key = "buffs", label = "Buffs", build = function() return C.BuffBarSection() end },
  { key = "gear", label = "Consumables & gear", build = function() return C.ConsumablesGearSection() end },
  { key = "vitals", label = "Health bars", build = function() return C.VitalsSection() end },
  { key = "combat", label = "Combat", build = function() return C.CombatSection() end },
  { key = "map", label = "Map & location", build = function() return C.MapSection() end },
  { key = "notify", label = "Notifications", build = function() return C.NotifySection() end },
  { key = "sounds", label = "Sounds", build = function() return C.SoundsSection() end },
  { key = "hud", label = "HUD layout", build = function() return C.HudSection() end },
  { key = "backup", label = "Menu, setups, backup & reset", build = function() return C.BackupSection() end },
}
-- skills.lua, when present: its page after Combat
if T.SkillBar then
  local at = #C.CATEGORIES + 1
  for i, c in ipairs(C.CATEGORIES) do if c.key == "combat" then at = i + 1 end end
  table.insert(C.CATEGORIES, at, { key = "skills", label = T.SkillBar.PAGE,
                                  build = function() return T.SkillBar.ConfigSection(C.Helpers) end })
end

local function category(keyOrLabel)
  for _, c in ipairs(C.CATEGORIES) do
    if c.key == keyOrLabel or c.label == keyOrLabel then return c end
  end
  return nil
end

-- Every control id Sync and the handlers look up (found in whichever categories are built).
local ALL_IDS = { "loc_show", "loc_facing", "loc_water", "loc_pin", "loc_overlay", "ov_window", "ov_death",
  "ov_auto_new",
  "pl_open", "pl_hud_close",
  "pl_cfg_scratch", "pl_book_when", "pl_book_status", "pl_book_read", "pl_book_stop", "pl_hud_show", "pl_hud_start",
  "pl_hud_auto", "pl_hud_shade", "pl_hud_shade_value",
  "xp_shade", "xp_shade_value", "daily_shade", "daily_shade_value", "nhud_shade", "nhud_shade_value",
  "vitals_shade", "vitals_shade_value", "target_shade", "target_shade_value", "loc_shade", "loc_shade_value",
  "ln_show", "ln_vertical", "ln_combat", "ln_size", "ln_size_value", "ln_color", "ln_shade", "ln_shade_value",
  "ln_btn_xp", "ln_btn_xpdetail", "ln_btn_today", "ln_btn_loot", "ln_btn_combat", "ln_btn_notify",
  "ln_btn_location", "ln_btn_docs", "ln_btn_settings",
  "font", "font_value", "spacing", "spacing_value", "xp_net", "xp_mode", "daily_mode", "show_xp",
  "show_daily_detail", "dd_values", "dd_each", "dd_values_msg", "dd_include", "dd_markers", "hover_popup",
  "hover_daily",
  "show_buffs", "buffs_combat_only", "buff_replace", "buff_dismiss", "buff_size", "buff_size_value",
  "show_buffblock", "buffblock_combat", "buffblock_width", "buffblock_width_value", "buffblock_size",
  "buffblock_size_value",
  "expire_alert", "expire_seconds", "expire_seconds_value", "buff_flash", "debuff_alert", "buff_group_after",
  "buff_repeat",
  "buff_group", "show_consumables", "consumables_extra", "show_gear", "gear_threshold",
  "show_vitals", "vitals_scale", "vitals_scale_value", "vitals_width", "vitals_width_value", "vitals_show_bars",
  "vitals_show_text", "vitals_replace", "vitals_vigor", "vitals_bg", "vitals_flash", "vitals_flash_below",
  "vitals_flash_below_value",
  "vitals_flash_test", "show_combat", "combat_detail", "combat_detail_hover", "combat_pet", "combat_scale",
  "shout_on", "shout_size", "shout_size_value",
  "combat_scale_value", "combat_bg", "combat_bg_opacity", "combat_bg_opacity_value", "combat_stats",
  "stat_find", "stat_results", "stat_add", "stat_shown", "stat_remove", "stat_msg",
  "nhud_hide", "notify_compact", "notify_font", "notify_font_value", "nhud_font", "nhud_font_value",
  "volume", "volume_value", "hud_summary", "toolbelt_show",
  "toolbelt_vitals", "toolbelt_consumables", "toolbelt_gear", "toolbelt_target", "target_place", "target_mirror",
  "target_effects", "target_icons", "target_icons_value", "target_show_bars", "target_show_text", "target_bg",
  "target_hide_pet", "target_flash_test", "nhud_spacing", "nhud_spacing_value",
  "target_flash", "target_flash_below", "target_flash_below_value",
  "toolbelt_combat", "cons_combat", "cons_max", "cons_max_value", "buff_countdown", "buff_countdown_secs",
  "buff_countdown_secs_value", "backup_where", "backup_save", "bk_now", "bk_pick", "bk_restore", "settings_reset",
  "backup_pending",
  "backup_cancel", "backup_msg", "quiet_pick", "quiet_mute", "quiet_list", "quiet_unmute", "quiet_msg",
  "fx_when", "fx_path", "fx_set", "fx_choose", "fx_list", "fx_test", "fx_remove", "fx_msg",
  "setup_share", "setup_pick", "setup_import", "setup_delete", "setup_name",
  "setup_export", "setup_msg" }
for _, def in ipairs(T.Sounds.DEFS) do
  ALL_IDS[#ALL_IDS + 1] = "snd_" .. def.key .. "_status"
  ALL_IDS[#ALL_IDS + 1] = "snd_" .. def.key .. "_path"
  ALL_IDS[#ALL_IDS + 1] = "snd_" .. def.key .. "_choose"
  ALL_IDS[#ALL_IDS + 1] = "snd_" .. def.key .. "_vol"
  ALL_IDS[#ALL_IDS + 1] = "snd_" .. def.key .. "_vol_value"
end
for _, src in ipairs(T.Notify.Sources()) do
  ALL_IDS[#ALL_IDS + 1] = "notify_" .. src.key
  ALL_IDS[#ALL_IDS + 1] = "notify_" .. src.key .. "_via"
  ALL_IDS[#ALL_IDS + 1] = "notify_" .. src.key .. "_snd"
end
for _, p in ipairs(POSITIONED) do ALL_IDS[#ALL_IDS + 1] = p[1] .. "_pos" end
for _, kind in ipairs(T.CombatShout.ORDER) do
  for _, part in ipairs({ "_text", "_color", "_sound", "_test" }) do
    ALL_IDS[#ALL_IDS + 1] = "shout_" .. kind .. part
  end
end
if T.SkillBar then
  for _, id in ipairs(T.SkillBar.CONFIG_IDS) do ALL_IDS[#ALL_IDS + 1] = id end
end
for _, key in ipairs(T.Consumables.Categories()) do
  ALL_IDS[#ALL_IDS + 1] = "cons_cat_" .. key
  ALL_IDS[#ALL_IDS + 1] = "buff_cat_" .. key
end
for _, list in ipairs({ "buff_group", "cons_exclude", "consumables_extra" }) do
  for _, suffix in ipairs({ "", "_field", "_msg" }) do ALL_IDS[#ALL_IDS + 1] = list .. suffix end
end

-- Shows one category (by key or label), building it. Only the one shown is kept: every page built once
-- and kept took ~420 of the add-on's 2,000 elements, and with a busy Loot Tracker and the rest open the
-- HUD layout page couldn't be built ("this add-on already has 2000 elements", found in game 2026-09-30).
-- So the page left is destroyed first (freeing its elements before the next is made), and its controls
-- leave `el`. Returns true when it shows.
local buildFocused = nil       -- (settings search, below) builds a page with one control's part at the top
local focusHidden = {}         -- ... the page's parts it built hidden ("Show the whole page" shows them)

local function dropCategory(key)
  focusHidden = {}
  local col = built[key]
  built[key] = nil
  if col then pcall(function() col:Destroy() end) end
  local keepShortcut, keepCategory = el.shortcut, el.category
  el = { shortcut = keepShortcut, category = keepCategory }
end

-- `focusId` (the settings search): build the page with that control's part at the top (built again even if
-- shown: the UI can't scroll to it).
function C.ShowCategory(which, focusId)
  T.Ran("settings page")
  local cat = category(which)
  if not cat or not win then return false end
  for key in pairs(built) do
    if key ~= cat.key or focusId then dropCategory(key) end
  end
  if not built[cat.key] then
    -- the game limits how fast elements are created: a category that can't be built now can be
    -- picked again in a moment
    local ok, col = pcall(function()
      if focusId then return body:Add(buildFocused(cat, focusId)) end
      return body:Add(cat.build())
    end)
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
  current = cat.key
  setValue("category", cat.label)
  C.Sync()
  return true
end

function C.CurrentCategory() return current end

-- Shows the category holding control `id` (for the tests, which look controls up by id): the one shown
-- if it has it, else each in turn. Returns the control, or nil.
-- Shows the page holding control `id`, its part at the top (as a search result does). Returns whether it did.
function C.GoToControl(id)
  local key = C.PageOf(id)
  if not key then return false end
  local shown = C.ShowCategory(key, id)
  return shown ~= nil and shown ~= false
end

function C.ShowControl(id)
  if not win then return nil end
  local hit = el[id] or win:Find(id)
  if hit then return hit end
  local key = C.PageOf(id)                      -- from the pages' recordings: no element made to look
  if key and C.ShowCategory(key) then
    hit = win:Find(id)
    if hit then return hit end
  end
  for _, cat in ipairs(C.CATEGORIES) do
    if C.ShowCategory(cat.key) then
      hit = win:Find(id)
      if hit then return hit end
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Settings search (owner, 2026-10-03: "it can be hard to find a setting")
-- ---------------------------------------------------------------------------
-- A box at the top: as you type, the settings whose label, section, tooltip or choices hold every word (or a
-- word's synonym, C.SEARCH_SYNONYMS) are listed as "Page > Section > Setting"; picking one shows its page and
-- blinks the control (its opacity, C.SEARCH_BLINKS times): an outline couldn't be undone safely (no style
-- getter: a control's own themed border would be lost; review, 2026-10-03), and full opacity is the default.
-- One control blinks at a time. The UI has no way to scroll to it.
-- The index (C.SearchIndex) is built by running each page's builder with `recording` on (see UI above): only
-- the page shown is ever built for real, so there is nothing else to search. Rebuilt each time the window
-- opens (labels can change). Buttons of one character (the nudge arrows) are left out; a short one is named
-- after its row ("Buff block (Reset)").

C.SEARCH_MAX = 15
C.SEARCH_BLINKS = 4                     -- times the found control fades and comes back
C.SEARCH_BLINK_EVERY = 0.25             -- seconds per half blink
C.SEARCH_DIM = 0.25                     -- opacity at the faded half
C.SEARCH_PROMPT = "Type above to search the settings"
C.SEARCH_SYNONYMS = {
  toolbar = { "toolbelt" }, chime = { "sound" }, width = { "wide", "length" }, wide = { "width" },
  alert = { "sound", "flash" }, alarm = { "sound" },
  audio = { "sound" }, volume = { "sound" }, hp = { "health" }, mana = { "focus" }, stamina = { "vigor" },
  cooldown = { "sweep" }, timer = { "sweep", "seconds" }, font = { "text size" }, big = { "size" },
  small = { "size" }, hide = { "show" }, position = { "move", "layout" }, location = { "layout" },
  loot = { "today" }, xp = { "experience" }, exp = { "xp" }, dps = { "combat" },
  potion = { "consumable" }, food = { "consumable" }, repair = { "gear", "equipment" },
}

local searchIndex = nil       -- the entries, built on the first search after the window opens
local searchPicks = {}        -- a results-dropdown label -> its entry
local searchDrop = nil
local SEARCHABLE = { Toggle = true, Slider = true, Dropdown = true, Button = true, TextField = true }

local function hasClass(class, name)
  if type(class) == "table" then
    for _, c in ipairs(class) do if c == name then return true end end
    return false
  end
  return class == name
end

local function endsWith(s, tail) return #s >= #tail and s:sub(-#tail) == tail end

-- Walks a recorded page ({ kind, spec } nodes) in build order, adding an entry per control: a heading label
-- names the section; a plain label names the control after it (a slider's or a dropdown's).
local function walk(node, ctx, out, seen)
  if type(node) ~= "table" or type(node.spec) ~= "table" then return end
  local kind, spec = node.kind, node.spec
  local id = type(spec.id) == "string" and spec.id or nil
  if kind == "Label" then
    local text = type(spec.text) == "string" and spec.text or ""
    if hasClass(spec.class, "heading") then
      ctx.section, ctx.label = text, nil
    elseif text ~= "" and not (id and (endsWith(id, "_value") or endsWith(id, "_pos"))) then
      ctx.label = text
    end
  elseif id and SEARCHABLE[kind] then
    local label = nil
    if kind == "Toggle" then
      label = spec.text
    elseif kind == "Button" then
      if type(spec.text) == "string" and #spec.text > 1 then
        label = spec.text
        if #label <= 6 and ctx.label then label = ctx.label .. " (" .. label .. ")" end
      end
    elseif kind == "TextField" then
      label = ctx.label or spec.placeholder
    else
      label = ctx.label or spec.tooltip                -- a dropdown with no label in front: its tooltip
    end
    if type(label) == "string" and label ~= "" then
      local where = ctx.page
      if ctx.section and ctx.section ~= ctx.page then where = where .. " > " .. ctx.section end
      local show = where .. " > " .. label
      if #show > 120 then show = show:sub(1, 117) .. "..." end
      if seen[show] then                             -- a toggle's dropdown beside it: one entry for both
        local also = seen[show].also
        also[#also + 1] = id
      else
        local hay = { label, ctx.section or "", ctx.page, type(spec.tooltip) == "string" and spec.tooltip or "" }
        if type(spec.choices) == "table" then
          for _, c in ipairs(spec.choices) do hay[#hay + 1] = tostring(c) end
        end
        out[#out + 1] = { key = ctx.key, id = id, also = {}, show = show, text = table.concat(hay, " "):lower(),
                          name = (label .. " " .. (ctx.section or "")):lower() }
        seen[show] = out[#out]
      end
    end
    -- a toggle names the control beside it; a slider or dropdown uses its label up (a text box and buttons
    -- share their row's)
    if kind == "Toggle" then
      ctx.label = spec.text
    elseif kind == "Slider" or kind == "Dropdown" then
      ctx.label = nil
    end
  end
  for _, c in ipairs(spec.children or {}) do walk(c, ctx, out, seen) end
end

-- The page holding element `id` (any element, searchable or not), from the pages' recordings; nil if none.
local function holds(node, id)
  if type(node) ~= "table" or type(node.spec) ~= "table" then return false end
  if node.spec.id == id then return true end
  for _, c in ipairs(node.spec.children or {}) do
    if holds(c, id) then return true end
  end
  return false
end
function C.PageOf(id)
  for _, cat in ipairs(C.CATEGORIES) do
    recording = true
    local ok, root = pcall(cat.build)
    recording = false
    if ok and holds(root, id) then return cat.key end
  end
  return nil
end

-- Every setting on every page: { key = page key, id, also = { ids of controls with the same name beside it },
-- show = "Page > Section > Label", text, name }.
function C.SearchIndex()
  if searchIndex then return searchIndex end
  local out = {}
  for _, cat in ipairs(C.CATEGORIES) do
    recording = true
    local ok, root = pcall(cat.build)
    recording = false
    if ok then walk(root, { key = cat.key, page = cat.label, section = cat.label }, out, {}) end
  end
  searchIndex = out
  return out
end

-- Whether `word` (or one of its synonyms) is in `text`.
local function hasWord(text, word)
  if text:find(word, 1, true) then return true end
  for _, alt in ipairs(C.SEARCH_SYNONYMS[word] or {}) do
    if text:find(alt, 1, true) then return true end
  end
  return false
end

-- The entries holding every word of `query`, those whose label or section has them all first; at most
-- `max`. Returns the list and how many matched in all. Pure over the index.
function C.SearchMatches(query, max)
  local words = {}
  for w in T.Trim(query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
  local best, rest = {}, {}
  if #words == 0 then return best, 0 end
  for _, e in ipairs(C.SearchIndex()) do
    local all, named = true, true
    for _, w in ipairs(words) do
      if not hasWord(e.text, w) then all = false end
      if not hasWord(e.name, w) then named = false end
    end
    if all then
      if named then best[#best + 1] = e else rest[#rest + 1] = e end
    end
  end
  local total = #best + #rest
  for _, e in ipairs(rest) do best[#best + 1] = e end
  for i = #best, (max or C.SEARCH_MAX) + 1, -1 do best[i] = nil end
  return best, total
end

-- The search box changed: the results dropdown lists the matches.
function C.Search(query)
  if not searchDrop then return end
  local list, total = C.SearchMatches(query)
  searchPicks = {}
  local labels = {}
  for _, e in ipairs(list) do
    labels[#labels + 1] = e.show
    searchPicks[e.show] = e
  end
  local q = T.Trim(query or "")
  if q == "" then
    labels = { C.SEARCH_PROMPT }
  elseif #labels == 0 then
    labels = { "No setting matches '" .. q:sub(1, 40) .. "'" }
  elseif total > #list then
    labels[#labels + 1] = "(" .. (total - #list) .. " more: add a word)"
  end
  searchDrop:SetChoices(labels)
  searchDrop:SetValue(labels[1])
end

-- The control blinking now, and its blink's number (a newer search's timer never touches an older control).
local blink = { el = nil, gen = 0, left = 0 }
local BLINK = "toolbox_search_blink"

local function stopBlink()
  if blink.el then
    local e = blink.el
    pcall(function() e:SetStyle{ opacity = 1 } end)       -- gone already if the page was switched
  end
  blink.el, blink.left = nil, 0
  T.RemovePeriodic(BLINK)
end

-- A page built from its recording (C.SearchIndex's way), with the part holding control `id` at the top:
-- the parts before it, from the nearest heading above it, are built hidden, under a line saying so with a
-- "Show the whole page" button (owner, 2026-10-03: a blink further down was over before you scrolled to
-- it). The builders find their controls by id, never by a kept reference, so a replayed page works the same.
local function containsId(node, id)
  if type(node) ~= "table" or type(node.spec) ~= "table" then return false end
  if node.spec.id == id then return true end
  for _, c in ipairs(node.spec.children or {}) do
    if containsId(c, id) then return true end
  end
  return false
end

local function replay(node, made)
  if type(node) ~= "table" or not node.kind or type(node.spec) ~= "table" then return node end
  local spec = {}
  for k, v in pairs(node.spec) do spec[k] = v end
  if type(node.spec.children) == "table" then
    spec.children = {}
    for i, c in ipairs(node.spec.children) do spec.children[i] = replay(c, made) end
  end
  local e = realUI(node.kind)(spec)
  made[node] = e
  return e
end

buildFocused = function(cat, id)
  recording = true
  local ok, root = pcall(cat.build)
  recording = false
  local kids = ok and type(root) == "table" and type(root.spec) == "table" and root.spec.children
  if type(kids) ~= "table" then return cat.build() end           -- (not a recordable page: the whole page)
  local at = nil
  for i, c in ipairs(kids) do
    if not at and containsId(c, id) then at = i end
  end
  local section = nil
  for i = (at or 1) - 1, 1, -1 do                                   -- from the heading above it
    local c = kids[i]
    if type(c) == "table" and c.kind == "Label" and type(c.spec) == "table" and hasClass(c.spec.class, "heading") then
      at, section = i, c.spec.text
      break
    end
  end
  local hidden = {}
  for i = 1, (at or 1) - 1 do
    if type(kids[i]) == "table" and type(kids[i].spec) == "table" then
      kids[i].spec.visible = false
      hidden[#hidden + 1] = kids[i]
    end
  end
  if #hidden > 0 then
    table.insert(kids, 1, { kind = "Row", spec = { id = "search_focus", style = { alignItems = "center",
      marginBottom = 6 }, children = {
      { kind = "Label", spec = { text = "The settings above " .. (section and ("\"" .. section .. "\"") or "it")
        .. " are hidden.", class = "dim", style = { flexGrow = 1, flexShrink = 1, whiteSpace = "wrap" } } },
      { kind = "Button", spec = { id = "search_showall", text = "Show the whole page", style = { marginLeft = 4 },
        onClick = function() C.ShowWholePage() end } },
    } } })
  end
  local made = {}
  local page = replay(root, made)
  focusHidden = {}
  for _, n in ipairs(hidden) do focusHidden[#focusHidden + 1] = made[n] end
  return page
end

-- "Show the whole page": the parts a search result's page hid come back, and the line goes.
function C.ShowWholePage()
  for _, e in ipairs(focusHidden) do pcall(function() e:SetVisible(true) end) end
  focusHidden = {}
  local line = win and win:Find("search_focus")
  if line then pcall(function() line:SetVisible(false) end) end
end

-- Shows a result's page and blinks its control (by its dropdown label; nil: the one picked now).
function C.SearchGo(label)
  if label == nil and searchDrop then label = searchDrop:GetValue() end
  local e = searchPicks[label]
  if not e then return false end
  stopBlink()                                              -- one at a time, back to full opacity first
  if not C.ShowCategory(e.key, e.id) then return false end   -- its part at the top
  local hit = el[e.id] or (win and win:Find(e.id))
  if hit then
    blink.gen = blink.gen + 1
    blink.el, blink.left = hit, 2 * C.SEARCH_BLINKS
    local gen = blink.gen
    T.RegisterPeriodic(BLINK, function()
      if gen ~= blink.gen or not blink.el then return end
      blink.left = blink.left - 1
      if blink.left <= 0 then
        stopBlink()
        return
      end
      local faded = blink.left % 2 == 1
      pcall(function() hit:SetStyle{ opacity = faded and C.SEARCH_DIM or 1 } end)
    end, C.SEARCH_BLINK_EVERY, true)
    pcall(function() hit:SetStyle{ opacity = C.SEARCH_DIM } end)   -- the first fade now
  end
  return true
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
        dropdownRow("Settings", { id = "category", choices = labels, value = labels[1],
          tooltip = "Which settings to show",
          onChange = function(_, label) C.ShowCategory(label) end }),
        UI.TextField{ id = "search", text = "", placeholder = "Search: sound, size, target, combat...",
          maxLength = 40, style = { marginTop = 4 },
          tooltip = "Finds settings on every page: pick one below to go to it (Enter: the first)",
          onChange = function(_, text) C.Search(text) end,
          onSubmit = function(_, text)
            C.Search(text)
            local first = C.SearchMatches(text, 1)[1]
            if first then C.SearchGo(first.show) end
          end },
        UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = {
          UI.Dropdown{ id = "search_results", choices = { C.SEARCH_PROMPT }, value = C.SEARCH_PROMPT,
            style = { flexGrow = 1, flexShrink = 1 }, tooltip = "Settings matching the search: pick one to go to it",
            onChange = function(_, label) C.SearchGo(label) end },
          UI.Button{ id = "search_go", text = "Go", style = { marginLeft = 4 },
            tooltip = "Show the setting picked above", onClick = function() C.SearchGo() end },
        } },
      } },
      UI.Scroll{ style = { flexGrow = 1 }, children = { body } },
    },
  }
  el, built = {}, {}
  el.shortcut, el.category = win:Find("shortcut"), win:Find("category")
  searchDrop, searchPicks, searchIndex = win:Find("search_results"), {}, nil
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
  local via, sound = T.Notify.ParseChoice(label)
  if not via then return end
  T.Notify.SetVia(key, via)
  T.Notify.SetSound(key, sound)
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

function C.RepeatLabels()
  local out = {}
  for i, ch in ipairs(T.BuffBar.REPEAT_CHOICES) do out[i] = ch[2] end
  return out
end

function C.OnRepeat(label)
  for _, ch in ipairs(T.BuffBar.REPEAT_CHOICES) do
    if ch[2] == label then T.BuffBar.SetRepeat(ch[1]) return end
  end
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
    if T.Target.Glued() then parts[#parts + 1] = "Target" end
    if #parts > 1 then
      lines[#lines + 1] = "Toolbelt: " .. table.concat(parts, " + ") .. "."
    else
      lines[#lines + 1] = "Toolbelt: just the buff bar so far. Add bars above."
    end
  else
    local waiting = {}
    if K.GetGlue() and K.GetShow() then waiting[#waiting + 1] = "Consumables" end
    if G.GetGlue() and G.GetShow() then waiting[#waiting + 1] = "Equipment" end
    if T.Target.GetGlue() and T.Target.GetShow() then waiting[#waiting + 1] = "Target" end
    if #waiting > 0 then
      local list = #waiting > 1 and (table.concat(waiting, ", ", 1, #waiting - 1) .. " and " .. waiting[#waiting])
        or waiting[1]
      lines[#lines + 1] = "The Toolbelt is off, so " .. list
        .. (#waiting > 1 and " use their own strips." or " uses its own strip.")
    else
      lines[#lines + 1] = "The Toolbelt is off (Show the Toolbelt)."
    end
  end
  if V.IsShown() and not (T.Hud.IsGlued() and B.IsEnabled()) then own[#own + 1] = "Health bars" end
  if K.GetShow() and not K.Glued() then own[#own + 1] = "Consumables" end
  if G.GetShow() and not G.Glued() then own[#own + 1] = "Equipment" end
  if T.Target.GetShow() and not T.Target.Glued() then own[#own + 1] = "Target" end
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
  -- XP & Loot
  sliderValue("font", W.GetFont())
  sliderValue("spacing", W.GetSpacing())
  setValue("xp_net", W.GetNet())
  setValue("show_xp", W.IsOpen())
  setValue("xp_mode", C.ModeOf(T.Compact))
  setValue("daily_mode", C.ModeOf(T.Daily))
  setValue("show_daily_detail", T.DailyDetail.IsOpen())
  setValue("dd_values", T.DailyDetail.GetValues())
  setValue("dd_each", T.DailyDetail.GetEach())
  setEnabled("dd_each", T.DailyDetail.GetValues())
  setText("dd_values_msg", T.Prices.testStatus)
  setValue("dd_include", T.DailyDetail.GetInclude())
  setValue("dd_markers", T.DailyDetail.GetMarkers())
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
  setValue("buff_repeat", B.RepeatLabel(B.GetRepeat()) or "Off")
  setEnabled("buff_repeat", B.GetExpireAlert() or B.GetDebuffAlert())
  setValue("buff_countdown", B.GetCountdown())
  sliderValue("buff_countdown_secs", B.GetCountdownSeconds())
  setEnabled("buff_countdown_secs", B.GetCountdown())
  setValue("buff_group_after", B.GroupAfterLabel(B.GetGroupAfter()) or "15 minutes")
  local parts = B.GroupParts()
  setText("buff_group", "Always group by name: " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
  -- (not the icon size: the consumables and equipment bars use it too)
  for _, id in ipairs({ "buffs_combat_only", "buff_group_after" }) do   -- the buff bar's own
    setEnabled(id, buffsOn)
  end
  setEnabled("buff_flash", buffsOn or T.BuffBlock.GetShow())          -- the buff block flashes too
  setEnabled("buff_replace", (buffsOn or T.BuffBlock.GetShow()) and B.CanReplace())
  for _, key in ipairs(T.Consumables.Categories()) do
    setValue("buff_cat_" .. key, B.GetGroupCategory(key))
    setEnabled("buff_cat_" .. key, buffsOn and T.Consumables.HasCategories())
  end
  setEnabled("buff_dismiss", (buffsOn or T.BuffBlock.GetShow()) and B.CanDismiss())
  -- the buff block
  local MB = T.BuffBlock
  setValue("show_buffblock", MB.GetShow())
  setValue("buffblock_combat", MB.GetCombatOnly())
  sliderValue("buffblock_width", MB.GetWidth())
  sliderValue("buffblock_size", MB.GetSize())
  for _, id in ipairs({ "buffblock_combat", "buffblock_width", "buffblock_size" }) do setEnabled(id, MB.GetShow()) end
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
  setText("cons_exclude", "Left out by name: " .. (#left > 0 and table.concat(left, ", ") or "none"))
  local extra = T.Consumables.Extra()
  setText("consumables_extra", "Always on it by name: " .. (#extra > 0 and table.concat(extra, ", ") or "none"))
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
  setValue("vitals_replace", V.GetReplace())
  setValue("vitals_bg", V.GetBackground())
  sliderValue("vitals_shade", V.GetShade())
  setEnabled("vitals_shade", vitalsOn and V.GetShowText() and V.GetBackground() == "Dark")
  setValue("vitals_flash", V.GetFlash())
  sliderValue("vitals_flash_below", V.GetFlashBelow())
  for _, id in ipairs({ "vitals_scale", "vitals_width", "vitals_show_bars", "vitals_show_text", "vitals_bg",
                        "vitals_flash", "vitals_flash_below", "vitals_flash_test" }) do
    setEnabled(id, vitalsOn)
  end
  setEnabled("vitals_vigor", vitalsOn and V.HasVigor())
  setValue("notify_compact", T.Notify.GetCompact())
  -- Combat
  local combatOn = M.IsShown()
  setValue("show_combat", combatOn)
  setValue("combat_pet", M.GetPet())
  setValue("combat_detail", M.Detail.IsOpen())
  setValue("combat_detail_hover", M.Detail.GetHover())
  sliderValue("combat_scale", M.GetScale())
  local CS = T.CombatShout
  setValue("shout_on", CS.GetOn())
  sliderValue("shout_size", CS.GetSize())
  setEnabled("shout_size", CS.GetOn())
  for _, kind in ipairs(CS.ORDER) do
    setValue("shout_" .. kind .. "_text", CS.GetText(kind))
    setValue("shout_" .. kind .. "_color", CS.ColorLabel(CS.GetColor(kind)))
    setValue("shout_" .. kind .. "_sound", CS.GetSound(kind))
    for _, part in ipairs({ "_text", "_color", "_sound" }) do setEnabled("shout_" .. kind .. part, CS.GetOn()) end
  end
  local shownStats = M.Stats()
  setText("combat_stats", "Shown: " .. (#shownStats > 0 and table.concat(shownStats, ", ") or "none"))
  syncShownStats(shownStats)
  local cbg, cop = M.GetBackground()
  setValue("combat_bg", cbg)
  sliderValue("combat_bg_opacity", cop)
  for _, id in ipairs({ "combat_detail_hover", "combat_scale", "combat_bg", "combat_bg_opacity" }) do
    setEnabled(id, combatOn)
  end
  -- Notifications
  for _, src in ipairs(T.Notify.Sources()) do
    setValue("notify_" .. src.key, T.Notify.IsOn(src.key))
    setValue("notify_" .. src.key .. "_via", T.Notify.ChoiceLabel(src.key))
    setValue("notify_" .. src.key .. "_snd", T.Notify.SoundLabel(T.Notify.GetSoundKey(src.key)))
    setEnabled("notify_" .. src.key .. "_snd", T.Notify.GetSound(src.key))
  end
  sliderValue("notify_font", T.Notify.GetFont())
  sliderValue("nhud_font", T.Notify.Hud.GetFont())
  sliderValue("nhud_spacing", T.Notify.Hud.GetSpacing())
  setValue("nhud_hide", T.Notify.Hud.HideLabel(T.Notify.Hud.GetHideAfter()) or "Never")
  sliderValue("nhud_shade", T.Notify.Hud.GetShade())
  -- Sounds
  sliderValue("volume", S.GetVolume())
  for _, def in ipairs(S.DEFS) do sliderValue("snd_" .. def.key .. "_vol", S.GetLevel(def.key)) end
  -- Toolbelt
  setValue("toolbelt_combat", B.GetCombatOnly())
  setEnabled("toolbelt_combat", buffsOn)
  setValue("toolbelt_show", B.IsEnabled())
  for _, part in ipairs(C.TOOLBELT_PARTS) do setValue("toolbelt_" .. part.key, C.PlaceOf(part)) end
  setValue("target_place", T.Target.PLACES[T.Target.GetPlace()] or T.Target.PLACES.top)
  setEnabled("target_place", T.Target.GetShow() and T.Target.GetGlue() and not T.Target.Mirrored())
  setValue("target_mirror", T.Target.GetMirror())
  setValue("target_effects", T.Target.EFFECT_LABELS[T.Target.GetEffects()])
  sliderValue("target_icons", T.Target.GetIcons())
  setEnabled("target_effects", T.Target.GetShow())
  setEnabled("target_icons", T.Target.GetShow() and T.Target.GetEffects() ~= "none")
  setEnabled("target_mirror", T.Target.GetShow() and T.Target.CanMirror())
  setValue("target_show_bars", T.Target.GetShowBars())
  setValue("target_show_text", T.Target.GetShowText())
  setValue("target_bg", T.Target.GetBackground())
  sliderValue("target_shade", T.Target.GetShade())
  setEnabled("target_shade", T.Target.GetShow() and T.Target.GetShowText() and T.Target.GetBackground() == "Dark")
  setValue("target_flash", T.Target.GetFlash())
  setValue("target_hide_pet", T.Target.GetHidePet())
  sliderValue("target_flash_below", T.Target.GetFlashBelow())
  for _, id in ipairs({ "target_show_bars", "target_show_text", "target_flash", "target_hide_pet" }) do
    setEnabled(id, T.Target.GetShow())
  end
  setEnabled("target_bg", T.Target.GetShow() and T.Target.GetShowText())
  setEnabled("target_flash_below", T.Target.GetShow() and T.Target.GetFlash())
  setEnabled("target_flash_test", T.Target.GetShow())
  setText("hud_summary", C.HudSummary())
  -- Backup & reset
  local pending = T.Backup.Pending() ~= nil
  setEnabled("backup_cancel", pending)
  local p = el.backup_pending
  if p and p:IsVisible() ~= pending then p:SetVisible(pending) end
  syncSetups()
  syncRestore()
  syncQuiet()
  syncEffectSounds()
  setValue("setup_share", T.Backup.GetShare())
  -- the menu (on the Menu, setups, backup & reset page)
  local L = T.Launcher
  setValue("ln_show", L.GetShow())
  setValue("ln_vertical", L.GetVertical())
  setValue("ln_combat", L.GetHideInCombat())
  sliderValue("ln_size", L.GetSize())
  sliderValue("ln_shade", L.GetShade())
  setValue("ln_color", L.ColorName(L.GetColor()))
  setValue("pl_hud_close", T.Planner.HudCloseName(T.Planner.GetHudClose()))
  setValue("pl_cfg_scratch", T.Planner.GetScratch())
  setValue("pl_book_when", T.Planner.BookWhenName(T.Planner.GetBookWhen()))
  setValue("pl_hud_show", T.Planner.GetHud())
  setValue("pl_hud_start", T.Planner.HudStartName(T.Planner.GetHudStart()))
  setValue("pl_hud_auto", T.Planner.GetHudAuto())
  sliderValue("pl_hud_shade", T.Planner.GetHudShade())
  C.SyncBook()
  for _, id in ipairs({ "ln_vertical", "ln_combat", "ln_size", "ln_color", "ln_shade" }) do
    setEnabled(id, L.GetShow())
  end
  for _, b in ipairs(L.BUTTONS) do
    setValue("ln_btn_" .. b.key, L.GetButton(b.key))
    setEnabled("ln_btn_" .. b.key, L.GetShow())
  end
  setValue("loc_show", T.Location.GetShow())
  setValue("loc_facing", T.Location.GetFacing())
  setEnabled("loc_facing", T.Location.GetShow())
  setValue("loc_water", T.Location.GetWater())
  setValue("loc_pin", T.Location.GetPin())
  setValue("loc_overlay", T.Location.GetOverlay())
  setEnabled("loc_overlay", T.Location.GetShow())
  setValue("ov_death", T.Location.GetDeath())
  setValue("ov_auto_new", T.Location.GetAutoNew())
  setEnabled("loc_water", T.Location.GetShow() and T.Location.HasWater())
  sliderValue("loc_shade", T.Location.GetShade())
  setEnabled("loc_shade", T.Location.GetShow())
  sliderValue("xp_shade", T.Compact.GetShade())
  setEnabled("xp_shade", T.Compact.GetHud())
  sliderValue("daily_shade", T.Daily.GetShade())
  setEnabled("daily_shade", T.Daily.GetHud())
  if T.SkillBar then T.SkillBar.ConfigSync(C.Helpers) end   -- skills.lua, when present
  C.SyncLive()
end

-- Things that change without a setter being called (sound loads settling, a strip being dragged
-- by its grip); called once a tick from Toolbox.Tick, and from Sync (so opening the window brings
-- them up to date). Only while the window is shown: once built, the window stays built while
-- hidden, and refreshing it then cost ~9 UI calls a second for nothing (review, 2026-09-29).
-- The recipe book's line and buttons (Sync, and every second from SyncLive while it's read).
function C.SyncBook()
  local reading = T.Daily.ReadingRecipes()
  setText("pl_book_status", T.Planner.BookStatus())
  setText("pl_book_read", T.Daily.recipeIndex and "Read it again" or "Read it now")
  setEnabled("pl_book_read", T.Daily.HasResults() and not reading)
  setEnabled("pl_book_stop", reading)
end

function C.SyncLive()
  if not C.IsShown() then return end
  disarm()
  disarmSetups(true)
  disarmRestore(true)
  syncQuiet()
  syncEffectSounds()
  C.SyncSounds()
  C.SyncBook()
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
    searchIndex = nil                  -- read the pages again at the next search (labels can change)
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
    searchIndex = nil
    C.Sync()
  else
    T.Print("The settings window can't reopen right now; try again in a few seconds.")
  end
end
