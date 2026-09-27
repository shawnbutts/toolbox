-- Toolbox: sounds.lua
-- Alert sounds (Toolbox.Sounds). Each sound is looked for in order:
--   1. the player's custom path (settings), anywhere inside the Lua folder;
--   2. "toolbox_<file>" loose in the Lua folder (the default place to drop a file: store
--      updates replace the package folder, not loose files), then the same name as .wav;
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

-- A clip's name from one list entry: the docs say entries are name strings, but in game they
-- came back as tables, so a table's name / Name / clip field is used too.
local function entryName(v)
  if type(v) == "string" then return v end
  if type(v) == "table" then
    for _, k in ipairs({ "name", "Name", "clip", "Clip", "clipName" }) do
      if type(v[k]) == "string" then return v[k] end
    end
  end
  return nil
end

-- The game's loaded clips as a flat list of names, in clip-id order (the id is the 1-based
-- position). Handles the documented list of strings, entries that are tables with a name,
-- and a list wrapped in one more table (in game every entry looked like the same table).
local function listSounds()
  local ok, raw = pcall(ShroudListSound)
  if not ok or type(raw) ~= "table" then return {} end
  if #raw == 1 and type(raw[1]) == "table" and not entryName(raw[1]) then
    raw = raw[1]                       -- wrapped: { { "a", "b" } }, or { {} } before any load
  end
  local out = {}
  for i, v in ipairs(raw) do out[i] = entryName(v) or "" end
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
  list[#list + 1] = "toolbox_" .. def.file
  -- A .wav beside it: in game the .ogg files (ffmpeg's experimental Vorbis encoder) never showed
  -- up in ShroudListSound(), i.e. didn't decode; tools/install.py copies .wav versions too.
  list[#list + 1] = "toolbox_" .. def.file:gsub("%.ogg$", ".wav")
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

-- /toolbox sounds debug: the game's raw sound list and what each alert recorded.
function S.DebugLines()
  local lines = { "Toolbox build " .. T.build .. ", copies loaded: " .. tostring(ToolboxCopies) }
  local ok, raw = pcall(ShroudListSound)
  local n = type(raw) == "table" and #raw or 0
  local kind = ok and type(raw) or ("error " .. tostring(raw))
  lines[#lines + 1] = "ShroudListSound(): " .. kind .. ", " .. n .. " entries"
  -- What a value holds, one level deep: "string abc", "table {name=abc, 2 items: x, y}".
  local function describe(v)
    if type(v) ~= "table" then return type(v) .. " " .. tostring(v) end
    local fields = {}
    for k, x in pairs(v) do
      if type(k) ~= "number" and #fields < 6 then fields[#fields + 1] = tostring(k) .. "=" .. tostring(x) end
    end
    local items = {}
    for i = 1, math.min(#v, 6) do items[#items + 1] = tostring(v[i]) end
    return "table {" .. table.concat(fields, ", ") .. (#v > 0 and ((#fields > 0 and "; " or "") .. #v
      .. " items: " .. table.concat(items, ", ")) or "") .. "}"
  end
  if type(raw) == "table" then
    -- every key, not only 1..n: a keyed table would count as "0 entries"
    local shown = 0
    for k, v in pairs(raw) do
      shown = shown + 1
      if shown <= 20 then lines[#lines + 1] = "  [" .. type(k) .. " " .. tostring(k) .. "] " .. describe(v) end
    end
    lines[#lines + 1] = "  (" .. shown .. " keys in all)"
  end
  lines[#lines + 1] = "Names used: " .. table.concat(listSounds(), ", ")
  for _, def in ipairs(S.DEFS) do
    local st = state[def.key] or {}
    lines[#lines + 1] = string.format("%s: status %s, path %s, recorded clip %s (%s), tried %s of %s",
      def.label, tostring(st.status), tostring(st.path), tostring(st.clip), type(st.clip),
      tostring(st.at), st.candidates and #st.candidates or 0)
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
      or ("no file found; put one at Lua/toolbox_" .. def.file .. " or set a path in /toolbox config")
    lines[#lines + 1] = def.label .. ": " .. where
  end
  lines[#lines + 1] = "Volume " .. prefs.volume .. "."
  return lines
end
