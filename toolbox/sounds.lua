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
S.DEFS = {
  { key = "buff_expiring", file = "buff_expiring.ogg", label = "Buff expiring" },
  { key = "debuff_landed", file = "debuff_landed.ogg", label = "Debuff landed" },
}

-- state[key] = { candidates = {...}, at = index, since = t, before = n, clip = name|nil,
--               path = path|nil, status = "loading"|"ready"|"missing" }
local state = {}
local prefs = { volume = S.VOLUME_DEFAULT, paths = {} }

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

local function candidates(def)
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
end

local function startLoad(def)
  local st = { candidates = candidates(def), at = 1, status = "loading" }
  state[def.key] = st
  tryNext(st)
end

-- Checks pending loads (from Toolbox.Tick, once a second).
function S.Poll()
  for _, def in ipairs(S.DEFS) do
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
      if not found and #list == st.before + 1 and list[#list] ~= "" then found = list[#list] end   -- name didn't say
      if type(found) == "string" and found ~= "" then
        st.status, st.clip, st.path = "ready", found, st.candidates[st.at]
      elseif T.Now() - st.since >= S.LOAD_TIMEOUT then
        st.at = st.at + 1
        tryNext(st)
      end
    end
  end
end

function S.Init()
  local saved = T.Load("sounds")
  prefs = { volume = S.VOLUME_DEFAULT, paths = {} }
  if type(saved) == "table" then
    if type(saved.volume) == "number" and saved.volume >= 0 and saved.volume <= 100 then
      prefs.volume = math.floor(saved.volume)
    end
    if type(saved.paths) == "table" then
      for _, def in ipairs(S.DEFS) do
        if type(saved.paths[def.key]) == "string" then prefs.paths[def.key] = saved.paths[def.key] end
      end
    end
  end
  for _, def in ipairs(S.DEFS) do startLoad(def) end
end

local function save()
  T.Save("sounds", prefs)
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
    if type(name) == "string" and name:find(stem, 1, true) then return i, name end
  end
  return nil
end

local function defFor(key)
  for _, def in ipairs(S.DEFS) do if def.key == key then return def end end
end

function S.Play(key)
  local st = state[key]
  if not st or st.status ~= "ready" then return false, { reason = "notLoaded" } end
  if prefs.volume <= 0 then return false, { reason = "muted" } end
  local index, name = findClip(st, defFor(key))
  if not index then
    -- Not in the game's list any more (ShroudListSoundReset, from any add-on, clears it):
    -- load it again for next time.
    startLoad(defFor(key))
    return false, { reason = "cleared" }
  end
  if type(name) == "string" then st.clip = name end
  local ok, channel = pcall(ShroudPlaySoundChannel, index, prefs.volume)
  local info = { clip = name, index = index }
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
function S.Test(key)
  local label = key
  for _, def in ipairs(S.DEFS) do if def.key == key then label = def.label end end
  local ok, info = S.Play(key)
  if not ok then
    local why = {
      notLoaded = "no sound loaded (see /toolbox sounds)",
      muted = "the alert volume is 0",
      cleared = "the game's sound list was cleared; reloading, try again in a few seconds",
      refused = "the game refused to play clip " .. tostring(info.index) .. " (returned "
        .. tostring(info.channel) .. "; all 5 channels busy, or a bad clip id)",
    }
    T.Print(label .. ": " .. (why[info.reason] or info.reason) .. ".")
    return false
  end
  T.Print(string.format("%s: playing '%s' (clip %d) on channel %d at volume %d.",
    label, info.clip, info.index, info.channel, prefs.volume))
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
      startLoad(def)
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
  for _, def in ipairs(S.DEFS) do
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
