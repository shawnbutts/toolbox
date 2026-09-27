-- Toolbox: sounds.lua
-- Alert sounds (Toolbox.Sounds). Each sound is looked for in order:
--   1. the player's custom path (settings), anywhere inside the Lua folder;
--   2. "toolbox_<file>" loose in the Lua folder (the default place to drop a file: store
--      updates replace the package folder, not loose files);
--   3. "toolbox/<file>" and "<file>": inside the package, for when audio files are allowed
--      in packages (the sound docs say paths are relative to "the addon's Lua folder", the
--      texture docs to the Lua root; both readings are tried).
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

S.LOAD_TIMEOUT = 3          -- seconds to wait for a candidate to appear
S.VOLUME_DEFAULT = 70
S.DEFS = {
  { key = "buff_expiring", file = "buff_expiring.ogg", label = "Buff expiring" },
  { key = "debuff_landed", file = "debuff_landed.ogg", label = "Debuff landed" },
}

-- state[key] = { candidates = {...}, at = index, since = t, before = n, clip = name|nil,
--               path = path|nil, status = "loading"|"ready"|"missing" }
local state = {}
local prefs = { volume = S.VOLUME_DEFAULT, paths = {} }

local function listSounds()
  local ok, list = pcall(ShroudListSound)
  if not ok or type(list) ~= "table" then return {} end
  return list
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
  list[#list + 1] = "toolbox_" .. def.file
  list[#list + 1] = "toolbox/" .. def.file
  list[#list + 1] = def.file
  return list
end

-- Starts loading candidate number st.at (or gives up).
local function tryNext(st)
  while st.at <= #st.candidates do
    local path = st.candidates[st.at]
    st.before = #listSounds()
    local ok, accepted = pcall(ShroudLoadSound, path, audioType(path))
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
      local found
      for i = st.before + 1, #list do
        if type(list[i]) == "string" and list[i]:find(stem, 1, true) then found = list[i] end
      end
      if not found and #list == st.before + 1 then found = list[#list] end   -- name didn't say
      if found then
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

-- Plays a sound by key. Returns true when it started.
function S.Play(key)
  local st = state[key]
  if not st or st.status ~= "ready" or prefs.volume <= 0 then return false end
  for i, name in ipairs(listSounds()) do
    if name == st.clip then
      local ok, channel = pcall(ShroudPlaySoundChannel, i, prefs.volume)
      return ok and type(channel) == "number" and channel > 0
    end
  end
  -- The clip list was cleared (ShroudListSoundReset): load it again for next time.
  for _, def in ipairs(S.DEFS) do
    if def.key == key then startLoad(def) end
  end
  return false
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
      path = tostring(path or ""):match("^%s*(.-)%s*$")
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

-- One line per sound for /toolbox sounds.
function S.Report()
  local lines = {}
  for _, def in ipairs(S.DEFS) do
    local status, path = S.Status(def.key)
    local where = status == "ready" and ("playing " .. path)
      or status == "loading" and "still looking..."
      or ("no file found; put one at Lua/toolbox_" .. def.file .. " or set a path in /toolbox config")
    lines[#lines + 1] = def.label .. ": " .. where
  end
  lines[#lines + 1] = "Volume " .. prefs.volume .. "."
  return lines
end
