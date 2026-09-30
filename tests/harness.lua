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
  "ShroudOnSocialChanged", "ShroudOnHttpResponse", "ShroudOnGuildMotdChanged", "ShroudOnTargetChanged",
  "ShroudOnSkillsChanged", "ShroudOnDeathChanged", "ShroudOnFriendStatusChanged", "ShroudOnGuildMemberStatusChanged",
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

H.CREATE_BURST, H.CREATE_RATE = 500, 200
H.MAX_WINDOWS = 8
H.MAX_HUD_FRAMES = 8          -- docs: HUD frames per add-on

-- A player action (typing a command, clicking, changing a control) happens at human speed, long
-- after start-up, so the creation budget has refilled by then.
local function humanPace()
  if S and S.createBucket then S.createBucket.tokens = H.CREATE_BURST end
end

local function fresh(disk)
  S = {
    char = { name = "Tester", adv = 1000000, prod = 500000, advPool = 25000, prodPool = 4000, gold = 5000,
             hp = 943, focus = 700,
             present = true,
             progress = {
               adventurer = { level = 50, experience = 1000000, intoLevel = 20000, forLevel = 100000, percent = 0.2 },
               producer = { level = 40, experience = 500000, intoLevel = 5000, forLevel = 50000, percent = 0.1 },
             } },
    memory = copy(disk or {}),   -- saved vars cache: [scope][key]
    disk = copy(disk or {}),
    date = "2026-09-27",               -- what os.date("%Y-%m-%d") returns
    serverTime = "2026-09-27 12:00:00",
    files = { ["toolbox/clock.png"] = true },   -- files that exist, relative to the Lua folder
    clips = {}, pendingClips = {}, played = {},
    buffs = {},                        -- { name, remaining, icon, debuff, tooltip } per effect
    -- ShroudGetSocialSummary(); H.setGuild / H.setMotd change it
    social = { inGuild = false, guildName = "", guildRole = "", guildMotd = "",
               guildMembers = 0, guildOnline = 0, friends = 0, friendsOnline = 0 },
    -- ShroudGetNotifications(); H.setNotes changes it
    notes = { unreadMail = 0, mailExpiring = false, ransoms = 0, newRewards = false, guildApplications = -1 },
    stats = {},                        -- { name, label, value, hidden }
    gear = {},                         -- worn items, ShroudGetEquipmentItems() fields; H.setGear
    vigor = nil,                       -- ShroudGetVigor() (API 20); nil = below Vigor's level; H.setVigor
    frames = {},
    logs = {},
    commands = {},
    keybinds = {},
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

-- The game's MoonSharp raises "pattern too complex" for a lazy ".-" pattern over long text (a
-- buff description, 2026-09-28), where standard Lua copes. Model it, so tests catch it.
local LAZY_LIMIT = 120
local realFind = string.find
for _, fname in ipairs({ "match", "find", "gmatch", "gsub" }) do
  local real = string[fname]
  string[fname] = function(s, pattern, ...)
    if type(s) == "string" and #s > LAZY_LIMIT and type(pattern) == "string" and realFind(pattern, "%.%-") then
      error("pattern too complex", 2)
    end
    return real(s, pattern, ...)
  end
end

local realDate = os.date
local realTime = os.time

local function install_api()
  ShroudLuaApiVersion = 25
  InvalidStatResult = -999
  ShroudTime = S.time or 100
  ShroudPlayerGold = S.char.gold
  ShroudPlayerCurrentHealth, ShroudPlayerCurrentFocus = S.char.hp, S.char.focus
  ShroudServerTime = S.serverTime
  -- The local clock the add-on reads for the daily reset.
  os.date = function(fmt, ...)
    if fmt == "%Y-%m-%d" and S.date then return S.date end
    return realDate(fmt, ...)
  end
  -- The local clock (Toolbox.Clock): H.S.clock when set; H.S.noClock = true: none.
  os.time = function(...)
    if S.noClock then return nil end
    if S.clock and select("#", ...) == 0 then return S.clock end
    return realTime(...)
  end

  ShroudConsoleLog = function(msg)
    S.logs[#S.logs + 1] = tostring(msg)
    return msg
  end

  ShroudGetPlayerName = function()
    if not S.char.present then return "INVALID" end
    return S.char.name
  end
  -- API 16 buff bar (H.S.noApi16 = true: an older client without it). Hiding is per add-on and
  -- released on reload (see H.reload); dismissing needs a gesture (H.clickSlot).
  if S.noApi16 then
    ShroudSetBuffBarVisible, ShroudIsBuffBarVisible, ShroudCanDismissBuff, ShroudDismissBuff = nil, nil, nil, nil
  else
    ShroudSetBuffBarVisible = function(v)
      S.stockCalls = (S.stockCalls or 0) + 1
      S.stockHidden = v == false
    end
    ShroudIsBuffBarVisible = function() return not S.stockHidden and not S.otherHides end
    ShroudCanDismissBuff = function(i)
      local e = S.char.present and S.buffs[i + 1]
      return e ~= nil and e ~= false and e.dismissable == true
    end
    ShroudDismissBuff = function(i)
      local e = S.char.present and S.buffs[i + 1]
      if type(i) ~= "number" or not e then return false, "badIndex" end
      if not e.dismissable then return false, "notDismissable" end
      if not S.gesture then return false, "needsGesture" end
      S.dismissed = S.dismissed or {}
      S.dismissed[#S.dismissed + 1] = e.name
      local kept = {}
      for _, b in ipairs(S.buffs) do if b.name ~= e.name then kept[#kept + 1] = b end end
      S.buffs = kept                       -- every effect of that rune
      return true, "ok"
    end
  end
  -- Web requests: H.S.httpRefuse = "not_permitted" (etc.) refuses them; H.S.requests records the
  -- accepted ones ({ id, url, done }); H.httpRespond answers one.
  ShroudHttpGet = function(url)
    if S.httpRefuse then return nil, S.httpRefuse end
    if type(url) ~= "string" or not url:match("^https://shroudoftheavatar%.net/") then
      return nil, "host_not_allowed"
    end
    if #url > 2048 then return nil, "url_too_long" end
    S.requests = S.requests or {}
    local id = #S.requests + 1
    S.requests[id] = { id = id, url = url }
    return id
  end
  ShroudGetNotifications = function()
    if not S.char.present then return nil end
    return copy(S.notes)
  end
  -- Vigor (API 20): the documented table, a fresh copy per call; nil below the level where it applies.
  ShroudGetVigor = function()
    if not S.char.present or not S.vigor then return nil end
    return copy(S.vigor)
  end
  -- Crafting window state (API 18; current clients have it). H.S.noCrafting = true: an older client.
  if not S.noCrafting then
    ShroudGetCraftingState = function()
      return copy(S.craftingState or { open = false, station = "", busy = false })
    end
    -- A known recipe by id (H.S.recipes[id] = { name, ingredients = { { name, quantity, tool, optional } } }).
    ShroudGetRecipe = function(id)
      local r = S.recipes and S.recipes[id]
      return r and copy(r) or nil
    end
  else
    ShroudGetCraftingState, ShroudGetRecipe = nil, nil
  end
  -- Worn items (documented fields; empty slots skipped). Game objects when H.S.buffObjects is set.
  ShroudGetEquipmentItems = function()
    if not S.char.present then return {} end
    local out = {}
    for i, it in ipairs(S.gear) do
      local item = { name = it.name, durability = it.durability, primaryDurability = it.primaryDurability or 0,
                     maxDurability = it.maxDurability, weight = 1, quantity = 1, value = 10, icon = it.icon or 7 }
      out[i] = item
    end
    return out
  end
  -- The target (H.S.target, set by H.setTarget): { id, name, hp, maxHp, focus, maxFocus, dead, hidden,
  -- effects = { { name, remaining, total, icon, debuff, category, tooltip } } }. Sentinels as documented.
  local function tg() return S.char.present and S.target or nil end
  local function teff(i) local t = tg(); return t and t.effects and t.effects[i + 1] or nil end
  -- Skills (H.S.skills, set by H.setSkills): { { id, key, name, trainedLevel, level }, ... }; nil = not loaded.
  ShroudGetSkills = function()
    if not S.char.present or not S.skills then return nil end
    return copy(S.skills)
  end
  ShroudHasTarget = function() return tg() ~= nil end
  ShroudGetTargetName = function() local t = tg(); return t and t.name or "None" end
  ShroudGetTargetId = function() local t = tg(); return t and t.id or -1 end
  ShroudIsTargetDead = function() local t = tg(); return t ~= nil and t.dead == true end
  ShroudIsTargetHealthHidden = function() local t = tg(); return t ~= nil and t.hidden == true end
  ShroudGetTargetCurrentHealth = function()
    local t = tg()
    if not t then return -1 end
    if t.hidden then return t.maxHp end
    return t.hp
  end
  ShroudGetTargetMaxHealth = function() local t = tg(); return t and t.maxHp or -1 end
  ShroudGetTargetCurrentFocus = function() local t = tg(); return t and (t.focus or 0) or -1 end
  ShroudGetTargetMaxFocus = function() local t = tg(); return t and (t.maxFocus or 0) or -1 end
  ShroudGetTargetBuffCount = function() local t = tg(); return t and t.effects and #t.effects or 0 end
  ShroudGetTargetBuffName = function(i) local e = teff(i); return e and e.name or "Invalid" end
  ShroudGetTargetBuffDescription = function(i) local e = teff(i); return e and (e.label or e.name) or "Invalid" end
  ShroudGetTargetBuffTimeRemaining = function(i) local e = teff(i); return e and e.remaining or -1 end
  ShroudGetTargetBuffIcon = function(i) local e = teff(i); return e and (e.icon or -1) or -1 end
  ShroudGetTargetBuffTooltip = function(i)
    local e = teff(i)
    return e and (e.tooltip or (e.name .. "\n" .. math.floor(e.remaining or 0) .. "s")) or ""
  end
  ShroudGetTargetBuffCategory = function(i) local e = teff(i); return e and (e.category or "Other") or nil end
  ShroudGetTargetBuff = function()
    local t = tg()
    if not t then return nil end
    S.targetBuffReads = (S.targetBuffReads or 0) + 1
    local out, by = {}, {}
    for _, e in ipairs(t.effects or {}) do
      local r = by[e.name]
      if not r then
        r = { RuneName = e.name, RuneId = #out + 1, IsDebuff = e.debuff == true, Category = e.category or "Other",
              StackCount = 0, Effects = {} }
        by[e.name] = r
        out[#out + 1] = r
      end
      r.StackCount = r.StackCount + 1
      r.Effects[#r.Effects + 1] = { Description = "", Value = 0, CurrentDuration = e.remaining or 0,
                                    TotalDuration = e.total or 0, TotalTick = 0 }
    end
    return out
  end
  ShroudGetSocialSummary = function()
    if not S.char.present then return nil end
    return copy(S.social)
  end
  -- API 18: the guild message ("" outside a guild). H.S.noGuildMotd = true: an older client.
  if S.noGuildMotd then
    ShroudGetGuildMotd = nil
  else
    ShroudGetGuildMotd = function()
      if not S.char.present or not S.social.inGuild then return "" end
      return S.social.motdGetter or S.social.guildMotd or ""
    end
  end
  ShroudGetTotalAdventurerExperience = function() return S.char.present and S.char.adv or 0 end
  ShroudGetTotalProducerExperience = function() return S.char.present and S.char.prod or 0 end
  -- Character stats: { name, label, value, hidden } (H.S.stats).
  ShroudGetStatCount = function() return #S.stats end
  ShroudGetStatNameByNumber = function(i) local st = S.stats[i + 1]; return st and st.name or "INVALID" end
  ShroudGetStatDescriptionByNumber = function(i) local st = S.stats[i + 1]; return st and st.label or "INVALID" end
  ShroudGetStatValueByNumber = function(i)
    local st = S.stats[i + 1]
    if not st then return -999 end
    return st.hidden and 0 or st.value
  end
  ShroudIsStatVisible = function(i)
    local st = type(i) == "number" and S.stats[i + 1]
    if type(i) == "string" then
      for _, x in ipairs(S.stats) do if x.name == i then st = x end end
    end
    return st ~= nil and st ~= false and not st.hidden
  end
  -- API 25: the maximums are the Health / Focus stats (as the docs say), the current values the character's.
  ShroudGetPlayerVitals = function()
    if not S.char.present then return nil end
    local function st(name) for _, x in ipairs(S.stats) do if x.name == name then return x.value end end end
    return { health = S.char.hp, maxHealth = st("Health") or S.char.hp, focus = S.char.focus,
             maxFocus = st("Focus") or S.char.focus }
  end
  ShroudGetStatValueByName = function(name)
    for _, x in ipairs(S.stats) do if x.name == name then return x.hidden and 0 or x.value end end
    return -999
  end
  ShroudGetPooledAdventurerExperience = function() return S.char.present and S.char.advPool or 0 end
  ShroudGetPooledProducerExperience = function() return S.char.present and S.char.prodPool or 0 end
  ShroudGetPlayerCombatMode = function() return S.combat == true end
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
    if S.flushFails then return false end     -- H.S.flushFails: the game refuses the write
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

  -- Textures and sound (async load: a clip shows up in ShroudListSound after a moment).
  AudioType = { WAV = "WAV", OGGVORBIS = "OGGVORBIS", MPEG = "MPEG" }
  ShroudLoadTexture = function(path) return S.files[path] and 7 or -1 end
  ShroudLoadSound = function(path, _)
    if type(path) ~= "string" or path:find("%.%.") then return false end
    if not S.files[path] and not S.acceptMissing then return false end
    if S.files[path] then
      S.pendingClips[#S.pendingClips + 1] = { name = path:match("([^/\\]+)%.%w+$"), due = ShroudTime + 0.5 }
    end
    return true
  end
  ShroudListSound = function()
    local out = {}
    for i, c in ipairs(S.clips) do out[i] = c end
    return out
  end
  ShroudListSoundReset = function()
    local had = #S.clips > 0
    S.clips = {}
    return had
  end
  ShroudPlaySoundChannel = function(id, volume)
    if type(id) ~= "number" or id < 1 or id > #S.clips or S.channelsBusy then return -1 end
    S.played[#S.played + 1] = { name = S.clips[id], volume = volume }
    S.channel = { name = S.clips[id], untilT = ShroudTime + (S.undecodable and 0 or 1) }
    return 1
  end
  -- What channel 1 is playing ("" once finished; at once for a clip that didn't decode).
  ShroudIsChannelPlaying = function(ch)
    if ch ~= 1 or not S.channel or ShroudTime >= S.channel.untilT then return "" end
    return S.channel.name
  end

  -- Buffs: one flat entry per effect; grouped by name for ShroudGetPlayerBuff.
  local function effect(i) return S.char.present and S.buffs[i + 1] or nil end
  ShroudGetBuffCount = function() return S.char.present and #S.buffs or 0 end
  ShroudGetBuffName = function(i) local e = effect(i); return e and e.name or "Invalid" end
  -- H.S.staleEvery = N: the game refreshes the value only every N seconds (holding it in between).
  ShroudGetBuffTimeRemaining = function(i)
    local e = effect(i)
    if not e then return -1 end
    if S.staleEvery and e.remaining and e.remaining > 0 then
      if not e.reportedAt or ShroudTime - e.reportedAt >= S.staleEvery then
        e.reported, e.reportedAt = e.remaining, ShroudTime
      end
      return e.reported
    end
    return e.remaining
  end
  ShroudGetBuffIcon = function(i) local e = effect(i); return e and (e.icon or -1) or -1 end
  -- Buff categories (API 23). H.S.noCategories = true: an older client.
  if not S.noCategories then
    ShroudBuffCategories = { "Other", "Food", "Potion", "Blessing", "Poison", "Skill", "Song", "Pet", "Consumable",
                             "Equipment", "Event", "Environment", "Creature" }
    ShroudGetBuffCategory = function(i) local e = effect(i); return e and H.categoryOf(e) or nil end
  else
    ShroudBuffCategories, ShroudGetBuffCategory = nil, nil
  end
  ShroudGetBuffDescription = function(i) local e = effect(i); return e and (e.label or e.name) or "Invalid" end
  ShroudGetBuffTooltip = function(i)
    local e = effect(i)
    if not e then return "" end
    return e.tooltip or (e.name .. "\n" .. math.floor(e.remaining or 0) .. "s")
  end
  ShroudGetPlayerBuff = function()
    if not S.char.present then return nil end
    local out, by = {}, {}
    for _, e in ipairs(S.buffs) do
      local r = by[e.name]
      if not r then
        r = { RuneName = e.name, RuneId = #out + 1, IsDebuff = e.debuff == true, IconId = e.icon or -1,
              StackCount = 0, Effects = {} }
        if not S.noCategories then r.Category = H.categoryOf(e) end
        by[e.name] = r
        out[#out + 1] = r
      end
      r.StackCount = r.StackCount + 1
      -- Durations by H.S.durationMode: "remaining" is what the game reports (seconds; CurrentDuration = left).
      local total, rem, cur, tot = e.total or e.remaining or 0, e.remaining or 0, 0, 0
      if S.durationMode == "elapsed" then tot, cur = total, total - rem
      elseif S.durationMode == "remaining" then tot, cur = total, rem
      elseif S.durationMode == "ms" then tot, cur = total * 1000, (total - rem) * 1000
      elseif S.durationMode == "nonsense" then tot, cur = 7, 3 end
      if S.durationMode == "absent" then       -- what the game seemed to report while its objects went unread
        r.Effects[#r.Effects + 1] = { Description = "", Value = 0 }
      else
        r.Effects[#r.Effects + 1] = { Description = "", Value = 0, CurrentDuration = cur, TotalDuration = tot,
                                      TotalTick = 0 }
      end
    end
    -- H.S.buffObjects: like the game (2026-09-28), entries are objects whose fields can only be read
    -- by name, not the documented tables: real userdata where the runtime can make it (LuaJIT's
    -- newproxy), else empty tables with an __index.
    if S.buffObjects then
      local proxy = rawget(_G, "newproxy")
      for i, r in ipairs(out) do
        if proxy then
          local u = proxy(true)
          getmetatable(u).__index = r
          out[i] = u
        else
          out[i] = setmetatable({}, { __index = r })
        end
      end
    end
    return out
  end

  Shroud = { UI = H.makeUI(), Command = H.command,
    Keybind = H.keybind, GetKeybind = H.getKeybind, RemoveCommand = function(name)
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

-- Key bindings. H.S.badKeys[key] = true makes a suggested key unusable (raises, as the docs
-- say for "a key it cannot use"); H.S.gameKeys[key] = true makes it a game key.
function H.keybind(spec)
  need_callback("Shroud.Keybind")
  for k in pairs(spec) do
    if k ~= "id" and k ~= "label" and k ~= "key" and k ~= "onPress" then
      error("Shroud.Keybind: unknown field " .. k, 2)
    end
  end
  if type(spec.label) ~= "string" or spec.label == "" or #spec.label > 48 then error("Shroud.Keybind: bad label", 2) end
  if type(spec.onPress) ~= "function" then error("Shroud.Keybind: onPress must be a function", 2) end
  -- (Keys listed in H.S.badKeys are refused, as the game refuses an unusable key.)
  local badKey = type(spec.key) ~= "string" or (S.badKeys or {})[spec.key]
  if spec.key ~= nil and badKey then error("Shroud.Keybind: can't use key " .. tostring(spec.key), 2) end
  S.keybinds[spec.id] = { key = spec.key or "", onPress = spec.onPress }
  return true, "ok"
end

function H.getKeybind(id)
  local b = S.keybinds[id]
  if not b then return nil end
  if b.key == "" then return "", "unbound" end
  if (S.gameKeys or {})[b.key] then return b.key, "gameKey" end
  return b.key, "bound"
end

-- The player presses a binding's key.
function H.press(id)
  humanPace()
  local b = S.keybinds[id]
  assert(b and b.key ~= "", "no key for " .. id)
  return H.call(b.onPress)
end

-- Types a chat command, e.g. H.chat("/tbx reset").
function H.chat(line)
  humanPace()
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
             escCloses = 1, onClose = 1, children = 1, compact = 1 },
  Row = { children = 1 }, Column = { children = 1 }, Scroll = { children = 1 },
  Grid = { columns = 1, children = 1 },
  Label = { text = 1 },
  Button = { text = 1, onClick = 1, enabled = 1 },
  Image = { texture = 1, width = 1, height = 1, onClick = 1, tint = 1, uv = 1, rotation = 1, sweep = 1 },
  IconButton = { texture = 1, onClick = 1, tint = 1, uv = 1, rotation = 1, sweep = 1 },
  HudFrame = { x = 1, y = 1, width = 1, height = 1, children = 1 },
  TextField = { text = 1, placeholder = 1, maxLength = 1, onChange = 1, onSubmit = 1, enabled = 1 },
  Dropdown = { choices = 1, value = 1, onChange = 1, enabled = 1 },
  Bar = { value = 1, color = 1 },
  Slider = { min = 1, max = 1, step = 1, value = 1, onChange = 1, enabled = 1 },
  Toggle = { text = 1, value = 1, onChange = 1, enabled = 1 },
}

-- As in game: destroying an element destroys everything inside it, and using a destroyed element
-- raises "Shroud.UI: this <Kind> was destroyed" (reported 2026-09-29 after gluing a strip).
local function destroyTree(e)
  if type(e) ~= "table" or e.destroyed then return end
  e.destroyed = true
  for _, c in ipairs(e.children or {}) do destroyTree(c) end
end
H.destroyTree = destroyTree

local Element = {}
Element.__index = Element

-- The game clamps margins to -64..256 and paddings to 0..256 (docs: "every value is clamped to
-- a sensible range"); do the same so layouts that rely on a bigger overlap fail here too.
local CLAMP = { margin = { -64, 256 }, marginLeft = { -64, 256 }, marginRight = { -64, 256 },
                marginTop = { -64, 256 }, marginBottom = { -64, 256 }, padding = { 0, 256 },
                paddingLeft = { 0, 256 }, paddingRight = { 0, 256 }, paddingTop = { 0, 256 },
                paddingBottom = { 0, 256 } }
local function clampStyle(style)
  for k, range in pairs(CLAMP) do
    local v = style[k]
    if type(v) == "number" then style[k] = math.max(range[1], math.min(range[2], v)) end
  end
  return style
end

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
  clampStyle(self.style)
end
function Element:Add(child)
  self.children = self.children or {}
  self.children[#self.children + 1] = child
  S.created = (S.created or 0) + 1
  return child
end
function Element:Clear()
  S.destroyed = (S.destroyed or 0) + #(self.children or {})
  for _, c in ipairs(self.children or {}) do destroyTree(c) end   -- cleared children are destroyed
  self.children = {}
end
function Element:SetVisible(v) self.visible = v end
-- Docs: SetEnabled / IsEnabled on every element (a disabled one is greyed out and ignores the pointer).
function Element:SetEnabled(on) self.enabled = on == true end
function Element:IsEnabled() return self.enabled ~= false end
function Element:Destroy()
  destroyTree(self)
  for id, f in pairs(S.frames) do if f == self then S.frames[id] = nil end end
  for id, w in pairs(S.windows) do if w == self then S.windows[id] = nil end end
end
-- Theme classes, as a set (the class field may be a name or a list).
local KNOWN_CLASSES = { button = 1, heading = 1, inset = 1, card = 1, badge = 1, warning = 1, good = 1, bad = 1,
                        bodycopy = 1, text = 1, dim = 1, bright = 1, title = 1, link = 1 }
function Element:Classes()
  if not self.classSet then
    self.classSet = {}
    local c = self.class
    for _, name in ipairs(type(c) == "table" and c or { c }) do self.classSet[name] = true end
  end
  return self.classSet
end
function Element:AddClass(name)
  if not KNOWN_CLASSES[name] then error("unknown class " .. tostring(name), 2) end
  self:Classes()[name] = true
end
function Element:RemoveClass(name) self:Classes()[name] = nil end
function Element:SetTexture(id) self.texture = id end
function Element:SetColor(c) self.color = c end
-- API 25 redraws a picture when SetUV changes it (before, only its first uv was drawn).
function Element:SetUV(x, y, w, h) self.uv = { x, y, w, h } end
-- The cooldown wedge (API 25, Image and IconButton): SetSweep(fraction | nil) sets it and stops a timer;
-- SetSweepTimer(start, duration[, { warnBelow, warnColor }]) lets the game run it on ShroudTime's clock
-- (it clears itself at the end); SetSweepTimer(nil) stops it. Checked like the game: a lone duration
-- is refused ("SetSweepTimer takes a number", seen 2026-09-30). `timerCalls` counts the timers set.
local function isPicture(e) return e.kind == "Image" or e.kind == "IconButton" end
function Element:SetSweep(f)
  if not isPicture(self) then error("Shroud.UI: SetSweep is for an Image or IconButton", 2) end
  if f ~= nil and type(f) ~= "number" then error("Shroud.UI: SetSweep takes a number", 2) end
  self.sweepTimer = nil
  self.sweepAmount = f and math.max(0, math.min(1, f)) or nil
end
function Element:SetSweepTimer(start, duration, options)
  if not isPicture(self) then error("Shroud.UI: SetSweepTimer is for an Image or IconButton", 2) end
  if start == nil then self.sweepTimer = nil return end
  if type(start) ~= "number" or type(duration) ~= "number" then error("Shroud.UI: SetSweepTimer takes a number", 2) end
  if options ~= nil then
    if type(options) ~= "table" then error("Shroud.UI: SetSweepTimer options must be a table", 2) end
    for k in pairs(options) do
      if k ~= "warnBelow" and k ~= "warnColor" then error("Shroud.UI: SetSweepTimer has no option '" .. k .. "'", 2) end
    end
  end
  self.sweepAmount = nil
  self.sweepTimer = { start = start, duration = duration, warnBelow = options and options.warnBelow,
                      warnColor = options and options.warnColor }
  self.timerCalls = (self.timerCalls or 0) + 1
end
-- What the wedge shows now: the fraction covered (nil: none) and whether it is in its warning colour.
function Element:SweepNow()
  local t = self.sweepTimer
  if t then
    local now = type(ShroudTime) == "number" and ShroudTime or 0
    if t.duration <= 0 or now >= t.start + t.duration then return nil, false end
    local f = math.max(0, (now - t.start) / t.duration)
    return f, t.warnBelow ~= nil and (t.start + t.duration - now) < t.warnBelow
  end
  if self.sweepAmount and self.sweepAmount > 0 then return self.sweepAmount, false end
  return nil, false
end
function Element:SetSize(w, h) self.width, self.height = w, h end
-- Laid-out size. Models a theme class with a minimum height (H.S.themeMinHeight):
-- an explicit minHeight overrides it; maxHeight caps the result.
function Element:GetSize()
  if self.laidOut then return self.laidOut[1], self.laidOut[2] end   -- a test sets what the game laid out
  local st = self.style or {}
  local h = st.height or 20
  h = math.max(h, st.minHeight or S.themeMinHeight or 0)
  if st.maxHeight then h = math.min(h, st.maxHeight) end
  return 200, h
end
function Element:IsVisible() return self.visible ~= false end
function Element:SetText(t) self.text = t end
function Element:SetTooltip(t) self.tooltip = t end
function Element:GetText() return self.text end
function Element:SetValue(v) self.value = v end
-- Dropdown (docs): replace or read the choices; the 1-based index of the current one (0 for none).
function Element:SetChoices(list) self.choices = copy(list) end
function Element:GetChoices() return copy(self.choices or {}) end
function Element:GetIndex()
  for i, c in ipairs(self.choices or {}) do if c == self.value then return i end end
  return 0
end
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

-- Every method but Destroy raises on a destroyed element, as the game does.
for name, fn in pairs(Element) do
  if type(fn) == "function" and name ~= "Destroy" then
    Element[name] = function(self, ...)
      if type(self) == "table" and self.destroyed then
        error("Shroud.UI: this " .. tostring(self.kind or "element") .. " was destroyed", 2)
      end
      return fn(self, ...)
    end
  end
end

function H.makeUI()
  local UI = {}
  for kind, fields in pairs(FIELDS) do
    UI[kind] = function(spec)
      need_callback("Shroud.UI." .. kind)
      if type(spec) == "string" then spec = { text = spec } end
      for k in pairs(spec) do
        if not COMMON[k] and not fields[k] then error("UI." .. kind .. ": unknown field " .. k, 2) end
      end
      S.constructed = (S.constructed or 0) + 1
      -- The game's element-creation cap: a burst of CREATE_BURST, refilling CREATE_RATE a second
      -- (AGENTS.md, "Limits"). Exceeding it raises, as in game (2026-09-28, Combat Detailed at start-up).
      local now = type(ShroudTime) == "number" and ShroudTime or 0
      local b = S.createBucket or { tokens = H.CREATE_BURST, at = now }
      b.tokens = math.min(H.CREATE_BURST, b.tokens + math.max(0, now - b.at) * H.CREATE_RATE)
      b.at = now
      if b.tokens < 1 then error("Shroud.UI: elements are being created too fast", 2) end
      b.tokens = b.tokens - 1
      S.createBucket = b
      local e = setmetatable(copy(spec), Element)
      if type(e.style) == "table" then clampStyle(e.style) end
      e.kind = kind
      e.children = spec.children     -- keep the real child objects
      e.onClose = spec.onClose
      e.onClick = spec.onClick
      e.onChange = spec.onChange
      if kind == "HudFrame" then
        assert(type(spec.id) == "string", "HudFrame id required")
        -- Docs: at most 8 HUD frames per add-on (one rebuilt under the same id replaces the old one).
        local live = 0
        for id, f in pairs(S.frames) do
          if id ~= spec.id and not f.destroyed then live = live + 1 end
        end
        if live >= H.MAX_HUD_FRAMES then
          error("Shroud.UI: too many HUD frames (" .. H.MAX_HUD_FRAMES .. " per add-on)", 2)
        end
        S.frames[spec.id] = e
      end
      if kind == "Window" then
        assert(type(spec.id) == "string", "Window id required")
        -- Docs: at most 8 windows per add-on (a window rebuilt under the same id replaces its old one).
        local live = 0
        for id, w in pairs(S.windows) do
          if id ~= spec.id and not w.destroyed then live = live + 1 end
        end
        if live >= H.MAX_WINDOWS then error("Shroud.UI: too many windows (" .. H.MAX_WINDOWS .. " per add-on)", 2) end
        -- Docs (API 19): a compact window can't hold a TextField or a Dropdown.
        if spec.compact then
          local function scan(x)
            if x.kind == "TextField" or x.kind == "Dropdown" then
              error("Shroud.UI: a compact window can't hold a " .. x.kind, 3)
            end
            for _, c in ipairs(x.children or {}) do scan(c) end
          end
          scan(e)
        end
        e.x, e.y = spec.x or 200, spec.y or 120
        e.shown = spec.visible == true
        e.compact = spec.compact == true
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
-- The settings window builds a category the first time it is shown; tests look controls up by id
-- across all of them, so build every category first (as picking each from its dropdown would).
local function allSettings(windowId)
  if windowId == "toolbox_config" and S.windows.toolbox_config and Toolbox and Toolbox.Config.BuildAll then
    H.call(function() Toolbox.Config.BuildAll() end)
  end
end

function H.change(windowId, elementId, value)
  humanPace()
  allSettings(windowId)
  local c = S.windows[windowId]:Find(elementId)
  assert(c, "no element " .. elementId)
  assert(c.enabled ~= false, elementId .. " is greyed out (disabled): a player can't change it")
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

-- The player presses Enter in a text field.
function H.submit(windowId, elementId, text)
  allSettings(windowId)
  local f = S.windows[windowId]:Find(elementId)
  assert(f, "no element " .. elementId)
  f.text = text
  H.call(function() f.onSubmit(f, text) end)
end

function H.click(windowId, elementId)
  humanPace()
  allSettings(windowId)
  local b = S.windows[windowId]:Find(elementId)
  assert(b, "no element " .. elementId)
  assert(b.enabled ~= false, elementId .. " is greyed out (disabled): a player can't click it")
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
  local list = assert(text:match('"files"%s*:%s*%[([^%]]*)%]'), "manifest has no files list")
  local files = {}
  for name in list:gmatch('"([^"]+)"') do files[#files + 1] = name end
  return files
end

-- Loads the package files in manifest order into the shared global env and runs ShroudOnStart.
function H.load()
  Toolbox = nil
  ToolboxCopies = nil                  -- one copy per (re)load, as in the game
  for _, cb in ipairs(CALLBACKS) do _G[cb] = nil end
  for _, file in ipairs(manifest_files()) do
    local chunk = assert(loadfile(H.PACKAGE .. "/" .. file))
    chunk()   -- top level: not in a callback
  end
  H.callback("ShroudOnStart")
end

-- Fresh client with a character in the world. `disk` seeds saved-var files. Boots as a
-- returning player (already welcomed) unless `firstRun` is true.
function H.boot(disk, time, firstRun)
  disk = copy(disk or {})
  if not firstRun then
    disk.account = disk.account or {}
    if disk.account.welcomed == nil then disk.account.welcomed = true end
  end
  fresh(disk)
  S.time = time or 100
  install_api()
  H.load()
end

-- /lua reload: the host unloads (flushing saved vars), tears down UI, commands
-- and timers, then loads the files again. Engine time keeps running.
function H.reload()
  humanPace()                          -- /lua reload is typed by the player
  ShroudFlushSavedVars()
  S.stockHidden = false                -- the game releases an add-on's hide on reload
  S.commands, S.periodics, S.windows, S.keybinds = {}, {}, {}, {}
  local now = ShroudTime
  install_api()
  ShroudTime = now
  H.load()
end

-- Quit and relaunch the client. Only flushed saved vars survive; time restarts.
function H.restart(time, flushFirst)
  if flushFirst then ShroudFlushSavedVars() end
  local disk, char, date, serverTime, buffs, mode = S.disk, S.char, S.date, S.serverTime, S.buffs, S.durationMode
  local social, notes, gear, vigor = S.social, S.notes, S.gear, S.vigor
  fresh(disk)
  -- the character's buffs and guild live on the server: they survive a client restart
  S.char, S.date, S.serverTime, S.buffs, S.durationMode = char, date, serverTime, buffs, mode
  S.social, S.notes, S.gear, S.vigor = social, notes, gear, vigor
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
    ShroudPlayerGold = S.char.present and S.char.gold or 0   -- per-frame globals
    ShroudPlayerCurrentHealth, ShroudPlayerCurrentFocus = S.char.hp, S.char.focus
    ShroudServerTime = S.serverTime
    -- async sound loads finish
    local still = {}
    for _, c in ipairs(S.pendingClips) do
      if ShroudTime >= c.due then S.clips[#S.clips + 1] = c.name else still[#still + 1] = c end
    end
    S.pendingClips = still
    -- buffs count down; expired ones drop off and the change callback fires
    local kept, changed = {}, false
    for _, b in ipairs(S.buffs) do
      if b.remaining and b.remaining > 0 then b.remaining = b.remaining - step end
      if b.remaining and b.remaining <= 0 and not b.permanent then changed = true else kept[#kept + 1] = b end
    end
    S.buffs = kept
    if changed then H.callback("ShroudOnBuffsChanged") end
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
  -- H.S.eventObjects: like the buff list in game, events as objects read by field only (real
  -- userdata on LuaJIT via newproxy).
  if S.eventObjects then
    local proxy = rawget(_G, "newproxy")
    for i, e in ipairs(events) do
      if proxy then
        local u = proxy(true)
        getmetatable(u).__index = e
        events[i] = u
      else
        events[i] = setmetatable({}, { __index = e })
      end
    end
  end
  return H.callback("ShroudOnCombatEvents", events, 0)
end

-- Items arrive in the bags: H.items({ { "Iron Ore", 5 }, { "Wolf Pelt", 1 } }, dropped).
function H.items(list, dropped)
  local items = {}
  for _, it in ipairs(list) do items[#items + 1] = { name = it[1], quantity = it[2], icon = -1 } end
  return H.callback("ShroudOnItemsGained", items, dropped or 0)
end

function H.detail() return S.windows.toolbox_daily_detail end
-- The Today Detailed item list as { { name, count }, ... } in display order.
function H.detailRows()
  local out = {}
  for _, row in ipairs(H.detail():Find("list").children or {}) do
    out[#out + 1] = { row.children[1].text, row.children[2].text, row.children[3] and row.children[3].text,
                      row.children[3] and row.children[3].tooltip }
  end
  return out
end

-- The item names a recorded web request asked SotANET for.
function H.requestedItems(n)
  local out = {}
  for v in S.requests[n].url:gmatch("item=([^&]*)") do
    out[#out + 1] = (v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
  end
  return out
end

-- Answers web request n (ok, status, body, err), as ShroudOnHttpResponse.
function H.httpRespond(n, ok, status, body, err)
  S.requests[n].done = true
  return H.callback("ShroudOnHttpResponse", n, ok, status, body, err)
end

-- Adds effects ({ name = , remaining = , debuff = , icon = , permanent = }) and fires the callback.
-- `silent`: the game doesn't fire ShroudOnBuffsChanged (reported 2026-09-28: no debuff sound).
function H.addBuffs(list, silent)
  for _, b in ipairs(list) do
    b.total = b.total or b.remaining             -- full duration (for H.S.durationMode)
    S.buffs[#S.buffs + 1] = b
  end
  if silent then return end
  return H.callback("ShroudOnBuffsChanged")
end

-- The player clicks the n-th visible icon of a bar row: a gesture while the handler runs.
function H.clickSlot(row, n)
  local slot = H.slots(row)[n]
  assert(slot, "no visible slot " .. n .. " in " .. row)
  S.gesture = true
  local ok, err = pcall(H.call, slot.children[1].onClick, slot.children[1])
  S.gesture = false
  if not ok then error(err, 2) end
end

function H.removeBuff(name)
  local kept = {}
  for _, b in ipairs(S.buffs) do if b.name ~= name then kept[#kept + 1] = b end end
  S.buffs = kept
  return H.callback("ShroudOnBuffsChanged")
end

function H.frame() return S.frames.toolbox_buffs end
function H.vitals() return S.frames.toolbox_vitals end
function H.hud() return S.frames.toolbox_hud end
function H.combatHud() return S.frames.toolbox_combat end
-- The combat HUD's shown rows as "label=value" strings.
function H.combatRows()
  local out = {}
  for _, group in ipairs(S.frames.toolbox_combat:Find("combat_rows").children) do
    local line = group.children[2]                     -- { light slab, the row }
    if line and group.visible ~= false then
      out[#out + 1] = line.children[1].text .. "=" .. line.children[2].text
    end
  end
  return out
end
-- The first shown combat row's group: { light slab, line }.
function H.combatGroup(n)
  local k = 0
  for _, group in ipairs(S.frames.toolbox_combat:Find("combat_rows").children) do
    if group.children[2] and group.visible ~= false then
      k = k + 1
      if k == (n or 1) then return group end
    end
  end
end
function H.setCombat(on)
  S.combat = on
  return H.callback("ShroudOnCombatModeChanged", on)
end
-- Visible slots of a bar row ("buffs" / "debuffs") as their slot tables.
function H.slots(row)
  local out = {}
  local frame = S.frames.toolbox_buffs or S.frames.toolbox_hud     -- own strip, or glued
  for _, slot in ipairs(frame:Find(row).children) do
    if slot.visible ~= false then out[#out + 1] = slot end
  end
  return out
end
-- The equipment bar's strip, and its visible slots (the icon's tooltip is slot.children[1].tooltip).
-- The player targets something (a table as H.S.target describes) or nothing (nil), and the game fires
-- ShroudOnTargetChanged. H.S.target can also be changed without the callback (health going down).
function H.setTarget(t)
  S.target = t
  return H.callback("ShroudOnTargetChanged", t and t.id or -1, t and t.name or "")
end
function H.targetFrame() return S.frames.toolbox_target end

-- The skills sheet changes (levels, when levelsChanged isn't false) and ShroudOnSkillsChanged fires.
-- Entries: { key = "Fireball", trainedLevel = 40 } (id and name filled in).
function H.setSkills(list, levelsChanged)
  for i, sk in ipairs(list or {}) do
    sk.id = sk.id or i
    sk.name = sk.name or sk.key
    sk.level = sk.level or sk.trainedLevel
  end
  S.skills = list
  return H.callback("ShroudOnSkillsChanged", levelsChanged ~= false)
end

-- You die (true) or are resurrected (false): ShroudOnDeathChanged.
function H.setDead(dead)
  S.char.dead = dead == true
  return H.callback("ShroudOnDeathChanged", dead == true)
end
-- The target row (own strip, or in the Toolbelt).
function H.targetRow()
  for _, id in ipairs({ "toolbox_target", "toolbox_buffs", "toolbox_hud" }) do
    local f = S.frames[id]
    local row = f and f:Find("target")
    if row then return row end
  end
  return nil
end
-- Visible effect slots of the target row.
function H.targetSlots()
  local out = {}
  local row = H.targetRow()
  for _, slot in ipairs(row and row.children or {}) do
    if slot.id ~= "target_info" and slot.id ~= "target_hint" and slot.visible ~= false then out[#out + 1] = slot end
  end
  return out
end
function H.gearFrame() return S.frames.toolbox_gear end
function H.gearSlots()
  local out = {}
  local frame = S.frames.toolbox_gear or S.frames.toolbox_buffs or S.frames.toolbox_hud  -- own, or glued
  for _, slot in ipairs(frame:Find("gear").children) do
    if slot.visible ~= false then out[#out + 1] = slot end
  end
  return out
end
function H.playedNames()
  local out = {}
  for _, p in ipairs(S.played) do out[#out + 1] = p.name end
  return table.concat(out, ",")
end

function H.daily() return S.windows.toolbox_daily end
function H.dailyText(id) return H.daily():Find(id).text end

-- A brand-new player: nothing saved, not welcomed yet.
-- Guild membership and message of the day, no callback (as if the guild data just loaded: the
-- next tick sees it). Set it after H.boot; it survives H.reload and H.restart.
function H.setGuild(name, motd)
  S.social.inGuild = name ~= nil
  S.social.guildName = name or ""
  S.social.guildMotd = motd or ""
  S.social.motdGetter = nil
end

-- The guild message changes while playing: the host notices and fires ShroudOnSocialChanged.
function H.setMotd(motd)
  S.social.guildMotd = motd
  S.social.motdGetter = nil
  return H.callback("ShroudOnSocialChanged")
end

-- API 18: only the guild message getter changes, and ShroudOnGuildMotdChanged fires (the social summary
-- keeps its old copy).
function H.guildMotdChanged(motd)
  S.social.motdGetter = motd
  return H.callback("ShroudOnGuildMotdChanged", motd)
end

-- A buff's category as the game gives it (API 23): `category` when a test sets one, otherwise from the
-- names seen in game (food, Obsidian potions, shrine blessings), Creature for a debuff, else Skill.
function H.categoryOf(e)
  if e.category then return e.category end
  local n = e.name or ""
  if n:find("^RuneFood_") then return "Food" end
  if n:find("^BlessingOf") then return "Potion" end
  if n:find("^POT_") or n:find("^Rune_Reward_Blessing") then return "Blessing" end
  if e.debuff then return "Creature" end
  return "Skill"
end

-- API 18 result events, with the documented fields (see the reference): a list of results + dropped.
function H.craftResults(results, dropped) return H.callback("ShroudOnCraftResults", results, dropped or 0) end
function H.gatherResults(results, dropped) return H.callback("ShroudOnGatherResults", results, dropped or 0) end
function H.craftingState(state)
  S.craftingState = state
  return H.callback("ShroudOnCraftingStateChanged", state)
end

-- Worn gear: { { name, durability, maxDurability [, icon] }, ... }. No event: the game has none.
function H.setGear(list) S.gear = list end

-- Vigor changes: { vigor = 64, percent = 64, ... } (missing fields get defaults) or nil, + ShroudOnVigorChanged.
function H.setVigor(v)
  if v then
    v = { vigor = v.vigor, max = v.max or 100, percent = v.percent or math.floor(v.vigor), rested = v.rested == true,
          healthRegenBonus = v.healthRegenBonus or 0, focusRegenBonus = v.focusRegenBonus or 0,
          critBonus = v.critBonus or 0 }
  end
  S.vigor = v
  return H.callback("ShroudOnVigorChanged", v and copy(v) or nil)
end

-- Notification counts / flags change (fields as ShroudGetNotifications), + ShroudOnNotificationsChanged.
function H.setNotes(fields)
  for k, v in pairs(fields) do S.notes[k] = v end
  return H.callback("ShroudOnNotificationsChanged")
end

-- The Notifications window, and one source's section in it ({ shown, title, text }).
function H.notify() return S.windows.toolbox_notify end

-- The notification HUD strip, the text / tooltip of its row i (nil when hidden), and hovering it.
function H.nhud() return S.frames.toolbox_notify_hud end
function H.nhudRow(i)
  local row = S.frames.toolbox_notify_hud:Find("nh_" .. i)
  if row.visible == false then return nil end
  return row.text, row.tooltip
end
function H.nhudHover(over)
  local panel = S.frames.toolbox_notify_hud:Find("nh_panel")
  H.call(function() panel.onHover(panel, over) end)
end
function H.notice(key)
  local w = S.windows.toolbox_notify
  if not w then return nil end
  local sec = w:Find("n_" .. key)
  return { shown = w:IsShown() and sec.visible ~= false, title = w:Find("n_" .. key .. "_title").text,
           text = w:Find("n_" .. key .. "_text").text }
end

function H.firstBoot(time) return H.boot(nil, time, true) end

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

-- XP Detailed, or while it has never been built (it is built on first show) a stand-in that says
-- it isn't shown.
local NOT_BUILT = { IsShown = function() return false end,
                    Find = function() error("XP Detailed isn't built yet: open it first", 2) end }
function H.window() return S.windows.toolbox_xp or NOT_BUILT end
-- The settings window, with every category built (see allSettings); nil before it is first opened.
function H.config()
  allSettings("toolbox_config")
  return S.windows.toolbox_config
end
-- The settings window as the player first sees it (only the categories shown so far built).
function H.configRaw() return S.windows.toolbox_config end
function H.compact() return S.windows.toolbox_compact end
function H.compactText(id) return H.compact():Find(id).text end
function H.text(id) return H.window():Find(id).text end

return H
