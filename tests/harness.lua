-- Fake SotA host for headless tests. Runs under Lua 5.1 (LuaJIT) through 5.4+.
--
-- It models only what Toolbox uses, and follows the documented rules where they
-- matter for correctness:
--   * Shroud.UI constructors and Shroud.Command raise outside a callback.
--   * Constructors reject unknown fields.
--   * Saved vars live in memory and reach "disk" on flush, logout, disable/unload.
--   * /lua reload tears down UI, commands and periodics; ShroudTime keeps running.
--   * A client restart resets ShroudTime and keeps only what was flushed to disk.

local H = {}

local ROOT = (arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]")) or "."
H.ROOT = ROOT
H.PACKAGE = ROOT .. "/toolbox"

local CALLBACKS = {
  "ShroudOnStart", "ShroudOnUpdate", "ShroudOnExperienceGain", "ShroudOnExperienceChanged",
  "ShroudOnLogOut", "ShroudOnDisableScript", "ShroudOnSceneLoaded", "ShroudOnSceneUnloaded",
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
H.copy = copy

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local S   -- current host state

local function fresh(disk)
  S = {
    char = { name = "Tester", adv = 1000000, prod = 500000, advPool = 25000, prodPool = 4000, gold = 5000,
             present = true,
             progress = {
               adventurer = { level = 50, experience = 1000000, intoLevel = 20000, forLevel = 100000, percent = 0.2 },
               producer = { level = 40, experience = 500000, intoLevel = 5000, forLevel = 50000, percent = 0.1 },
             } },
    memory = copy(disk or {}),   -- saved vars cache: [scope][key]
    disk = copy(disk or {}),
    date = "2026-09-27",               -- what os.date("%Y-%m-%d") returns
    serverTime = "2026-09-27 12:00:00",
    logs = {},
    commands = {},
    taken = {},
    periodics = {},
    windows = {},
    inCallback = false,
    showRefused = false,
    flushes = 0,
  }
  H.S = S
end

-- ---------------------------------------------------------------------------
-- API stubs
-- ---------------------------------------------------------------------------

local function need_callback(what)
  if not S.inCallback then error(what .. " called outside a callback", 3) end
end

local function scopeOf(scope)
  if type(scope) == "string" and scope:lower() == "account" then return "account" end
  return "character:" .. S.char.name
end

local realDate = os.date

local function install_api()
  ShroudLuaApiVersion = 14
  InvalidStatResult = -999
  ShroudTime = S.time or 100
  ShroudPlayerGold = S.char.gold
  ShroudServerTime = S.serverTime
  -- The local clock the add-on reads for the daily reset.
  os.date = function(fmt, ...)
    if fmt == "%Y-%m-%d" and S.date then return S.date end
    return realDate(fmt, ...)
  end

  ShroudConsoleLog = function(msg)
    S.logs[#S.logs + 1] = tostring(msg)
    return msg
  end

  ShroudGetPlayerName = function()
    if not S.char.present then return "INVALID" end
    return S.char.name
  end
  ShroudGetTotalAdventurerExperience = function() return S.char.present and S.char.adv or 0 end
  ShroudGetTotalProducerExperience = function() return S.char.present and S.char.prod or 0 end
  ShroudGetPooledAdventurerExperience = function() return S.char.present and S.char.advPool or 0 end
  ShroudGetPooledProducerExperience = function() return S.char.present and S.char.prodPool or 0 end
  ShroudGetLevelProgress = function()
    if not S.char.present then return nil end
    return copy(S.char.progress)
  end

  ShroudSetSavedVar = function(key, value, scope)
    if type(key) ~= "string" or key == "" or #key > 128 or key:find("[/\\%c]") then return false end
    local t = type(value)
    if t == "function" or t == "thread" or t == "userdata" then return false end
    local sc = scopeOf(scope)
    S.memory[sc] = S.memory[sc] or {}
    S.memory[sc][key] = copy(value)
    S.dirty = true
    return true
  end
  ShroudGetSavedVar = function(key, scope)
    local t = S.memory[scopeOf(scope)]
    return t and t[key]      -- by reference, as documented
  end
  ShroudDeleteSavedVar = function(key, scope)
    local t = S.memory[scopeOf(scope)]
    if not t or t[key] == nil then return false end
    t[key] = nil
    return true
  end
  ShroudFlushSavedVars = function()
    S.disk = copy(S.memory)
    S.flushes = S.flushes + 1
    S.dirty = false
    return true
  end

  ShroudRegisterPeriodic = function(name, fn, period, repeating)
    if type(fn) ~= "function" or period < 0.01 then return false end
    S.periodics[name] = { fn = fn, period = period, repeating = repeating, due = ShroudTime + period }
    return true
  end
  ShroudRemovePeriodic = function(name)
    local had = S.periodics[name] ~= nil
    S.periodics[name] = nil
    return had
  end

  Shroud = { UI = H.makeUI(), Command = H.command, RemoveCommand = function(name)
    local had = S.commands[name] ~= nil
    S.commands[name] = nil
    return had
  end }
end

-- ---------------------------------------------------------------------------
-- Shroud.Command
-- ---------------------------------------------------------------------------

function H.command(spec)
  need_callback("Shroud.Command")
  for k in pairs(spec) do
    if k ~= "name" and k ~= "help" and k ~= "run" then error("Shroud.Command: unknown field " .. k, 2) end
  end
  if type(spec.help) ~= "string" or spec.help == "" then error("Shroud.Command: help is required", 2) end
  if #spec.help > 120 then error("Shroud.Command: help longer than 120", 2) end
  if type(spec.run) ~= "function" then error("Shroud.Command: run must be a function", 2) end
  local name = tostring(spec.name or ""):gsub("^/", ""):lower()
  if not name:match("^[a-z][a-z0-9]+$") or #name < 3 or #name > 24 then return false, "badName" end
  if S.taken[name] then return false, S.taken[name] end
  S.commands[name] = spec.run
  return true, "ok"
end

-- Types a chat command, e.g. H.chat("/tbx reset").
function H.chat(line)
  local name, args = line:match("^/(%S+)%s?(.*)$")
  local run = S.commands[name:lower()]
  assert(run, "no command /" .. name)
  return H.call(function() return run(args or "") end)
end

-- ---------------------------------------------------------------------------
-- Shroud.UI
-- ---------------------------------------------------------------------------

local COMMON = { id = true, class = true, style = true, visible = true, tooltip = true, onHover = true }
local FIELDS = {
  Window = { title = 1, width = 1, height = 1, x = 1, y = 1, minWidth = 1, minHeight = 1, resizable = 1,
             escCloses = 1, onClose = 1, children = 1 },
  Row = { children = 1 }, Column = { children = 1 }, Scroll = { children = 1 },
  Grid = { columns = 1, children = 1 },
  Label = { text = 1 },
  Button = { text = 1, onClick = 1, enabled = 1 },
  Bar = { value = 1, color = 1 },
  Slider = { min = 1, max = 1, step = 1, value = 1, onChange = 1, enabled = 1 },
  Toggle = { text = 1, value = 1, onChange = 1, enabled = 1 },
}

local Element = {}
Element.__index = Element

function Element:Find(id)
  for _, c in ipairs(self.children or {}) do
    if c.id == id then return c end
    local hit = c.Find and c:Find(id)
    if hit then return hit end
  end
  return nil
end
function Element:SetStyle(style)
  self.style = self.style or {}
  for k, v in pairs(style) do self.style[k] = v end
end
function Element:SetText(t) self.text = t end
function Element:SetTooltip(t) self.tooltip = t end
function Element:GetText() return self.text end
function Element:SetValue(v) self.value = v end
function Element:GetValue() return self.value end
function Element:Show()
  if S.showRefused then return false end
  self.shown = true
  return true
end
function Element:Hide() self.shown = false end
function Element:IsShown() return self.shown == true end
function Element:GetPosition() return self.x, self.y end
function Element:SetPosition(x, y) self.x, self.y = x, y end

function H.makeUI()
  local UI = {}
  for kind, fields in pairs(FIELDS) do
    UI[kind] = function(spec)
      need_callback("Shroud.UI." .. kind)
      if type(spec) == "string" then spec = { text = spec } end
      for k in pairs(spec) do
        if not COMMON[k] and not fields[k] then error("UI." .. kind .. ": unknown field " .. k, 2) end
      end
      local e = setmetatable(copy(spec), Element)
      e.kind = kind
      e.children = spec.children     -- keep the real child objects
      e.onClose = spec.onClose
      e.onClick = spec.onClick
      e.onChange = spec.onChange
      if kind == "Window" then
        assert(type(spec.id) == "string", "Window id required")
        e.x, e.y = spec.x or 200, spec.y or 120
        e.shown = spec.visible == true
        S.windows[spec.id] = e
      end
      return e
    end
  end
  return UI
end

-- The player clicks a window's close button.
function H.closeWindow(id)
  local w = S.windows[id]
  w.shown = false
  if w.onClose then H.call(function() w.onClose(w) end) end
end

-- The player drags a window.
function H.moveWindow(id, x, y)
  S.windows[id].x, S.windows[id].y = x, y
end

-- The player changes a slider, toggle, ... (fires onChange; our own SetValue never does).
function H.change(windowId, elementId, value)
  local c = S.windows[windowId]:Find(elementId)
  c.value = value
  H.call(function() c.onChange(c, value) end)
end

-- The pointer enters (over = true) or leaves an element; nil elementId = the window itself.
function H.hover(windowId, elementId, over)
  local w = S.windows[windowId]
  local e = elementId and w:Find(elementId) or w
  assert(e.onHover, "no onHover on " .. windowId .. "/" .. tostring(elementId))
  H.call(function() e.onHover(e, over) end)
end

function H.click(windowId, elementId)
  local b = S.windows[windowId]:Find(elementId)
  H.call(function() b.onClick(b) end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function H.call(fn, ...)
  local was = S.inCallback
  S.inCallback = true
  local r = { pcall(fn, ...) }
  S.inCallback = was
  if not r[1] then error(r[2], 2) end
  return select(2, (table.unpack or unpack)(r))
end

function H.callback(name, ...)
  local fn = _G[name]
  if fn then return H.call(fn, ...) end
end

local function manifest_files()
  local f = assert(io.open(H.PACKAGE .. "/manifest.json", "r"))
  local text = f:read("*a")
  f:close()
  local list = assert(text:match('"files"%s*:%s*%[(.-)%]'), "manifest has no files list")
  local files = {}
  for name in list:gmatch('"([^"]+)"') do files[#files + 1] = name end
  return files
end

-- Loads the package files in manifest order into the shared global env and runs ShroudOnStart.
function H.load()
  Toolbox = nil
  for _, cb in ipairs(CALLBACKS) do _G[cb] = nil end
  for _, file in ipairs(manifest_files()) do
    local chunk = assert(loadfile(H.PACKAGE .. "/" .. file))
    chunk()   -- top level: not in a callback
  end
  H.callback("ShroudOnStart")
end

-- Fresh client with a character in the world. `disk` seeds saved-var files.
function H.boot(disk, time)
  fresh(disk)
  S.time = time or 100
  install_api()
  H.load()
end

-- /lua reload: the host unloads (flushing saved vars), tears down UI, commands
-- and timers, then loads the files again. Engine time keeps running.
function H.reload()
  ShroudFlushSavedVars()
  S.commands, S.periodics, S.windows = {}, {}, {}
  local now = ShroudTime
  install_api()
  ShroudTime = now
  H.load()
end

-- Quit and relaunch the client. Only flushed saved vars survive; time restarts.
function H.restart(time, flushFirst)
  if flushFirst then ShroudFlushSavedVars() end
  local disk, char, date, serverTime = S.disk, S.char, S.date, S.serverTime
  fresh(disk)
  S.char, S.date, S.serverTime = char, date, serverTime
  S.time = time or 50
  install_api()
  H.load()
end

-- Advance engine time in steps (default 1 s), firing due periodics.
function H.advance(seconds, step)
  step = step or 1
  local target = ShroudTime + seconds
  while ShroudTime < target - 1e-9 do
    ShroudTime = math.min(target, ShroudTime + step)
    ShroudPlayerGold = S.char.present and S.char.gold or 0   -- per-frame global
    ShroudServerTime = S.serverTime
    local due = {}
    for name in pairs(S.periodics) do due[#due + 1] = name end
    table.sort(due)
    for _, name in ipairs(due) do
      local p = S.periodics[name]
      if p and ShroudTime >= p.due - 1e-9 then
        p.due = p.due + p.period
        if not p.repeating then S.periodics[name] = nil end
        H.call(p.fn)
      end
    end
  end
end

-- Gained XP lands in both the total and the pool.
function H.gain(adv, prod, fireCallback)
  S.char.adv = S.char.adv + (adv or 0)
  S.char.prod = S.char.prod + (prod or 0)
  S.char.advPool = S.char.advPool + (adv or 0)
  S.char.prodPool = S.char.prodPool + (prod or 0)
  if fireCallback ~= false then
    if (adv or 0) > 0 then H.callback("ShroudOnExperienceGain", "Adventurer", adv) end
    if (prod or 0) > 0 then H.callback("ShroudOnExperienceGain", "Producer", prod) end
  end
end

-- Gold arrives (positive) or is spent (negative).
function H.goldChange(delta)
  S.char.gold = S.char.gold + delta
end

-- Combat chat lines, e.g. { kind = "death", fromYou = true, target = "Wolf" }.
function H.combat(events)
  for _, e in ipairs(events) do
    for _, k in ipairs({ "fromYou", "toYou", "fromYourPet", "toYourPet", "party" }) do
      if e[k] == nil then e[k] = false end
    end
    e.source, e.target, e.amount, e.skill = e.source or "", e.target or "", e.amount or 0, e.skill or ""
  end
  return H.callback("ShroudOnCombatEvents", events, 0)
end

function H.daily() return S.windows.toolbox_daily end
function H.dailyText(id) return H.daily():Find(id).text end

function H.logs() return S.logs end
function H.clearLogs() S.logs = {} end
function H.lastLog() return S.logs[#S.logs] end
function H.logged(pattern)
  for _, l in ipairs(S.logs) do if l:find(pattern) then return true end end
  return false
end

function H.saved(key, scope)
  local t = S.memory[scopeOf(scope)]
  return t and t[key]
end

function H.window() return S.windows.toolbox_xp end
function H.config() return S.windows.toolbox_config end
function H.compact() return S.windows.toolbox_compact end
function H.compactText(id) return H.compact():Find(id).text end
function H.text(id) return H.window():Find(id).text end

return H
