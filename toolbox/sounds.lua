-- Toolbox: sounds.lua
-- Alert sounds (Toolbox.Sounds). Each sound is looked for in order:
--   1. the player's custom path (settings), anywhere inside the Lua folder;
--   2. a replacement "Lua/toolbox_<file>" beside the package (store updates replace the package
--      folder, not loose files), as .ogg then .wav;
--   3. the default "Lua/toolbox/<file>" in the package folder (.ogg only: that's what ships).
-- Paths are relative to the Lua root (ShroudLuaPath is the Lua folder in game).
-- The first that loads is used; if none do, the sound stays silent.
--
-- ShroudLoadSound is asynchronous and "true" only means the request was accepted, so a
-- candidate counts as loaded when a new clip shows up in ShroudListSound(); after
-- LOAD_TIMEOUT seconds the next candidate is tried. Clip ids are positions in that list
-- (and ShroudListSoundReset clears it), so the clip's name is remembered and looked up
-- just before playing.

local T = Toolbox
local S = {}
Toolbox.Sounds = S

S.LOAD_TIMEOUT = 2          -- seconds to wait for a candidate to appear (local files load fast)
S.VOLUME_DEFAULT = 70
-- Volumes, format 2 (owner, 2026-10-07: some found 100% too quiet; and a volume per sound). The shipped sounds
-- were made twice as loud (art/alerts.py: +7.5 dB into a limiter), so a saved volume from before is halved once
-- (the old 100% is the new 50%: nothing changes for whoever chose it), while the default (70) is now twice as
-- loud. Each sound also has its own level (S.LEVEL_DEFAULT %), applied on top: played at volume x level / 100.
-- A player's own file can't be made louder, so it plays at twice that (capped at the game's 100): as loud as it
-- was before.
S.VOLUME_FORMAT = 2
S.LEVEL_DEFAULT = 100
S.DEFS = {
  { key = "buff_expiring", file = "buff_expiring.ogg", label = "Buff expiring" },
  { key = "debuff_landed", file = "debuff_landed.ogg", label = "Debuff landed" },
  { key = "notify", file = "notify.ogg", label = "Notification chime" },
  { key = "ping", file = "ping.ogg", label = "Notification ping" },
  { key = "tap", file = "tap.ogg", label = "Notification tap" },
  { key = "mail", file = "mail.ogg", label = "Mail doorbell" },     -- the mail notifications' own (owner, 2026-10-08)
}

-- state[key] = { candidates = {...}, at = index, since = t, before = n, clip = name|nil,
--               path = path|nil, status = "loading"|"ready"|"missing" }
local state = {}
local prefs = { v = S.VOLUME_FORMAT, volume = S.VOLUME_DEFAULT, paths = {}, levels = {} }

-- The game's loaded clips as a list of names (the file's base name), in clip-id order: the id
-- is the 1-based position. Confirmed in game 2026-09-28: plain strings, as documented.
local function listSounds()
  local ok, raw = pcall(ShroudListSound)
  if not ok or type(raw) ~= "table" then return {} end
  local out = {}
  for i, v in ipairs(raw) do out[i] = type(v) == "string" and v or "" end
  return out
end

local function audioType(path)
  local ext = (path:match("%.(%w+)$") or ""):lower()
  if ext == "wav" then return AudioType.WAV end
  if ext == "mp3" then return AudioType.MPEG end
  return AudioType.OGGVORBIS
end

-- Effect sounds (owner, 2026-10-08): a player's own file for one buff or debuff (its name said aloud, say), played
-- instead of buff_expiring / debuff_landed for it (buffbar.lua's BB.EffectSound). Loaded like the others, one entry per
-- path (key "file:<path>"), from its path only. A clip can't be unloaded (ShroudListSoundReset clears every add-on's),
-- so at most S.FILES_MAX files a session.
S.FILES_MAX = 60
local files, fileCount = {}, 0          -- path -> its def

local function candidates(def)
  if def.custom then return { def.custom } end
  local list = {}
  local custom = prefs.paths[def.key]
  if type(custom) == "string" and custom ~= "" then list[#list + 1] = custom end
  -- Paths are relative to the Lua root (in game ShroudLuaPath is the Lua folder itself).
  -- A player's replacement sits in the Lua folder, beside the package, and wins; the defaults
  -- ship in the package folder as .ogg. A replacement may also be a .wav.
  local wav = def.file:gsub("%.ogg$", ".wav")
  for _, name in ipairs({ "toolbox_" .. def.file, "toolbox_" .. wav,     -- replacement: Lua/toolbox_<name>
                          "toolbox/" .. def.file }) do                     -- default: Lua/toolbox/<name>
    list[#list + 1] = name
  end
  return list
end

-- Starts loading candidate number st.at (or gives up).
local function tryNext(st)
  while st.at <= #st.candidates do
    local path = st.candidates[st.at]
    st.before = #listSounds()
    local ok, accepted = pcall(ShroudLoadSound, path, audioType(path))
    -- What the game said about each path (docs: true = "the path exists inside the addon folder").
    st.log = st.log or {}
    st.log[#st.log + 1] = path .. " -> " .. (ok and tostring(accepted) or ("error " .. tostring(accepted)))
    if ok and accepted then
      st.since = T.Now()
      st.status = "loading"
      return
    end
    st.at = st.at + 1                    -- refused outright (e.g. escapes the Lua folder)
  end
  st.status, st.path, st.clip = "missing", nil, nil
  local def = st.def
  if def and def.custom and not def.told then
    def.told = true                      -- once a session: the usual sound plays meanwhile
    T.Print("Couldn't load your sound '" .. def.custom .. "' (" .. def.label .. "): the usual sound plays instead."
      .. " The file must be inside your Lua folder, its path starting there (toolbox_sounds/atos.ogg).")
  end
end

local function startLoading(def)
  local st = { candidates = candidates(def), at = 1, status = "loading", def = def }
  state[def.key] = st
  tryNext(st)
end

-- Checks pending loads (from Toolbox.Tick, once a second).
local function poll(def)
  local st = state[def.key]
  if st and st.status == "loading" then
    local list = listSounds()
    local stem = def.file:gsub("%.%w+$", "")
    -- `= nil` matters: in game, a bare `local found` here seemed to keep a table from an earlier
    -- use of the slot (both sounds "ready" with the same table as their clip, the list empty).
    local found = nil
    for i = st.before + 1, #list do
      if type(list[i]) == "string" and list[i]:find(stem, 1, true) then found = list[i] end
    end
    for i = st.before + 1, #list do         -- the exact name first: "heal" isn't "heal on" (effect sounds)
      if list[i] == stem then found = list[i] end
    end
    if not found and #list == st.before + 1 and list[#list] ~= "" then found = list[#list] end   -- name didn't say
    if type(found) == "string" and found ~= "" then
      st.status, st.clip, st.path = "ready", found, st.candidates[st.at]
    elseif T.Now() - st.since >= S.LOAD_TIMEOUT then
      st.at = st.at + 1
      tryNext(st)
    end
  end
end

function S.Poll()
  for _, def in ipairs(S.DEFS) do poll(def) end
  for _, def in pairs(files) do poll(def) end
end

function S.Init()
  local saved = T.ReadSaved("sounds")
  prefs = { v = S.VOLUME_FORMAT, volume = S.VOLUME_DEFAULT, paths = {}, levels = {} }
  local migrate = false
  if type(saved) == "table" then
    if type(saved.volume) == "number" and saved.volume >= 0 and saved.volume <= 100 then
      prefs.volume = math.floor(saved.volume)
      if saved.v ~= S.VOLUME_FORMAT then        -- saved before the louder sounds: the same loudness now
        prefs.volume = math.floor(prefs.volume / 2 + 0.5)
        migrate = true
      end
    end
    if type(saved.levels) == "table" then
      for k, n in pairs(saved.levels) do
        if type(k) == "string" and type(n) == "number" and n >= 0 and n <= 100 then prefs.levels[k] = math.floor(n) end
      end
    end
    if type(saved.paths) == "table" then
      for _, def in ipairs(S.DEFS) do
        if type(saved.paths[def.key]) == "string" then prefs.paths[def.key] = saved.paths[def.key] end
      end
    end
  end
  for _, def in ipairs(S.DEFS) do startLoading(def) end
  if migrate then T.Save("sounds", prefs) end
end

local function save()
  T.Save("sounds", prefs)
end

local function defFor(key)
  for _, def in ipairs(S.DEFS) do if def.key == key then return def end end
  if type(key) == "string" and key:sub(1, 5) == "file:" then return files[key:sub(6)] end
end

-- A path as typed or pasted, made the path the game wants (relative to the Lua folder, "/" between folders), or nil
-- and why. A full path holding a "Lua" folder is cut to what follows it.
function S.CleanPath(text)
  if type(text) ~= "string" then return nil, "Give the file's path." end
  local path = T.Trim(T.Trim(T.Trim(text), "\"'")):gsub("\\", "/")
  local low, cut = path:lower(), nil
  local at = low:find("/lua/", 1, true)
  while at do
    cut = at
    at = low:find("/lua/", at + 1, true)
  end
  if cut then path = path:sub(cut + 5) end
  if path == "" then return nil, "Give the file's path." end
  if path:sub(1, 1) == "/" or path:find("^%a:") or path:find("..", 1, true) then
    return nil, "That file is outside your Lua folder: copy it into the game's Lua folder (or a folder in it) first."
  end
  local ext = (path:match("%.(%w+)$") or ""):lower()
  if ext ~= "ogg" and ext ~= "wav" and ext ~= "mp3" then return nil, "Use a .ogg, .wav or .mp3 file." end
  if path:lower():sub(1, 8) == "toolbox/" then
    return nil, "Not in the toolbox folder: every update replaces it. Put your sounds beside it (toolbox_sounds/...)."
  end
  return path
end

-- The name the game gives a file's clip: its base name without the extension (any case, to be safe).
local function clipName(file) return (file:match("([^/]+)$") or file):gsub("%.%w+$", ""):lower() end

-- Whether another sound's clip would have the same name as `path`'s: the game lists clips by base name only, so
-- two would play one recording (review 25). Returns the other's path or file, or nil.
local function sameName(path)
  local name = clipName(path)
  for other in pairs(files) do
    if other ~= path and clipName(other) == name then return other end
  end
  for _, def in ipairs(S.DEFS) do
    if clipName(def.file) == name or clipName("toolbox_" .. def.file) == name then return def.file end
    local own = prefs.paths[def.key]
    if type(own) == "string" and own ~= "" and clipName(own) == name then return own end
  end
  return nil
end

-- Starts loading a player's file (a path from S.CleanPath) for an effect labelled `label`, unless it already is;
-- `again`: try a file that wasn't found once more. Returns true, or false and why (past S.FILES_MAX, or a file
-- whose name another sound already has).
function S.UseFile(path, label, again)
  local def = files[path]
  if def then
    local st = state[def.key]
    if again and st and st.status == "missing" then
      def.told = false
      startLoading(def)
    end
    return true
  end
  if fileCount >= S.FILES_MAX then
    return false, "Too many sound files loaded this session (" .. S.FILES_MAX .. "): /lua reload, then try again."
  end
  local other = sameName(path)
  if other then
    return false, "Another sound already has a file named like " .. (path:match("([^/]+)$") or path) .. " ("
      .. other .. "), and the game tells sounds apart by name only: rename this one."
  end
  def = { key = "file:" .. path, file = path:match("([^/]+)$") or path, label = label or path, custom = path }
  files[path], fileCount = def, fileCount + 1
  startLoading(def)
  return true
end

-- Plays a player's file at the volume of `levelKey`'s alert (buff_expiring / debuff_landed). Returns S.Play's answer;
-- false while it loads or when it couldn't (the caller plays the usual sound).
function S.PlayFile(path, levelKey)
  if not files[path] then
    S.UseFile(path)
    return false, { reason = "notLoaded" }
  end
  return S.Play("file:" .. path, levelKey)
end

function S.FileStatus(path)
  local def = files[path]
  return def and S.Status(def.key) or "missing"
end

function S.GetLevel(key)
  local n = prefs.levels[key]
  if type(n) == "number" then return n end
  return S.LEVEL_DEFAULT
end

function S.SetLevel(key, n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < 0 or n > 100 then return false end
  prefs.levels[key] = n ~= S.LEVEL_DEFAULT and n or nil
  save()
  T.Config.Sync()
  return true
end

-- The volume a sound plays at (0..100 for the game): the alert volume x its own level, twice that for a file of
-- the player's (the shipped ones were made twice as loud), at most 100.
function S.EffectiveVolume(key, levelKey)
  local v = prefs.volume * S.GetLevel(levelKey or key) / 100
  local st = state[key]
  local def = defFor(key)
  if st and st.path and def and st.path ~= "toolbox/" .. def.file then v = v * 2 end
  if v > 100 then v = 100 end
  return math.floor(v + 0.5)
end

-- Plays a sound by key. Returns true when it started, and a table saying what happened:
-- { reason = "ok" | "notLoaded" | "muted" | "cleared" | "refused", clip, index, channel }.
-- The clip's position in the game's list: the recorded name exactly, else any clip whose name
-- contains the file's base name (loads match that way; in game the exact name went missing).
local function findClip(st, def)
  local list = listSounds()
  for i, name in ipairs(list) do
    if name == st.clip then return i, name end
  end
  local stem = def.file:gsub("%.%w+$", "")
  for i, name in ipairs(list) do
    if name == stem then return i, name end
  end
  for i, name in ipairs(list) do
    if type(name) == "string" and name:find(stem, 1, true) then return i, name end
  end
  return nil
end

function S.Play(key, levelKey)
  local st = state[key]
  if not st or st.status ~= "ready" then return false, { reason = "notLoaded" } end
  if prefs.volume <= 0 then return false, { reason = "muted" } end
  local volume = S.EffectiveVolume(key, levelKey)
  if volume <= 0 then return false, { reason = "soundMuted" } end
  local index, name = findClip(st, defFor(key))
  if not index then
    -- Not in the game's list any more (ShroudListSoundReset, from any add-on, clears it):
    -- load it again for next time.
    startLoading(defFor(key))
    return false, { reason = "cleared" }
  end
  if type(name) == "string" then st.clip = name end
  local ok, channel = pcall(ShroudPlaySoundChannel, index, volume)
  local info = { clip = name, index = index, volume = volume }
  if ok then info.channel = channel end
  if ok and type(channel) == "number" and channel > 0 then
    info.reason = "ok"
    return true, info
  end
  info.reason = "refused"
  return false, info
end

-- Plays a sound and reports in chat what happened, then checks a moment later whether the
-- game is still playing it: a clip that loads but can't be decoded plays as silence.
-- Why S.Play didn't play (its `info`), for chat.
function S.WhyNot(info)
  local why = {
    notLoaded = "no sound loaded (see /toolbox sounds)",
    muted = "the alert volume is 0",
    soundMuted = "its own volume is 0 (Sounds settings)",
    cleared = "the game's sound list was cleared; reloading, try again in a few seconds",
    refused = "the game refused to play clip " .. tostring(info.index) .. " (returned "
      .. tostring(info.channel) .. "; all 5 channels busy, or a bad clip id)",
  }
  return why[info.reason] or tostring(info.reason)
end

-- A sound's label ("Buff expiring"), or its key.
function S.Label(key)
  for _, def in ipairs(S.DEFS) do if def.key == key then return def.label end end
  return key
end

function S.Test(key)
  local label = S.Label(key)
  local ok, info = S.Play(key)
  if not ok then
    T.Print(label .. ": " .. S.WhyNot(info) .. ".")
    return false
  end
  T.Print(string.format("%s: playing '%s' (clip %d) on channel %d at volume %d.",
    label, info.clip, info.index, info.channel, info.volume))
  ShroudRegisterPeriodic("toolbox_soundcheck_" .. key, function()
    local now = ShroudIsChannelPlaying(info.channel)
    if type(now) == "string" and now ~= "" then
      T.Print(label .. ": channel " .. info.channel .. " is playing '" .. now .. "'. If you hear nothing,"
        .. " check the game's sound volume.")
    else
      T.Print(label .. ": channel " .. info.channel .. " is already silent, so the file most likely didn't"
        .. " decode. Try a .wav (set its path in /toolbox config).")
    end
  end, 0.15, false)
  return true
end

function S.Status(key)
  local st = state[key]
  if not st then return "missing" end
  return st.status, st.path
end

function S.SetVolume(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < 0 or n > 100 then return false end
  prefs.volume = n
  save()
  T.Config.Sync()
  return true
end

function S.GetVolume()
  return prefs.volume
end

-- Sets (or with "" clears) a custom path for one sound and reloads it.
function S.SetPath(key, path)
  for _, def in ipairs(S.DEFS) do
    if def.key == key then
      path = T.Trim(path)
      prefs.paths[key] = path ~= "" and path or nil
      save()
      startLoading(def)
      T.Config.Sync()
      return true
    end
  end
  return false
end

function S.GetPath(key)
  return prefs.paths[key] or ""
end

-- /toolbox sounds debug: the game's clip list, and what each alert tried and found.
function S.DebugLines()
  local lines = { "Toolbox build " .. T.build .. ", copies loaded: " .. tostring(ToolboxCopies),
    "ShroudLuaPath = " .. tostring(ShroudLuaPath) .. "; ShroudDataPath = " .. tostring(ShroudDataPath) }
  local names = listSounds()
  lines[#lines + 1] = "Loaded clips (all add-ons): " .. #names
    .. (#names > 0 and (": " .. table.concat(names, ", ")) or "")
  local all = {}
  for _, def in ipairs(S.DEFS) do all[#all + 1] = def end
  for _, def in pairs(files) do all[#all + 1] = def end
  for _, def in ipairs(all) do
    local st = state[def.key] or {}
    lines[#lines + 1] = string.format("%s: status %s, path %s, recorded clip %s (%s), tried %s of %s",
      def.label, tostring(st.status), tostring(st.path), tostring(st.clip), type(st.clip),
      tostring(st.at), st.candidates and #st.candidates or 0)
    for _, entry in ipairs(st.log or {}) do lines[#lines + 1] = "    tried " .. entry end
  end
  return lines
end

-- One line per sound for /toolbox sounds.
function S.Report()
  local lines = {}
  for _, def in ipairs(S.DEFS) do
    local status, path = S.Status(def.key)
    local where = status == "ready" and ("playing " .. path)
      or status == "loading" and "still looking..."
      or ("no file found (the default is Lua/toolbox/" .. def.file .. "; a replacement goes at Lua/toolbox_"
        .. def.file .. ")")
    lines[#lines + 1] = def.label .. ": " .. where
  end
  lines[#lines + 1] = "Volume " .. prefs.volume .. "."
  return lines
end
