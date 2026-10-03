-- Toolbox: skills.lua
-- The skill activity strip (/toolbox skills): like the game's bar of skills along the right, the icons of
-- the skills that just levelled (or changed mode, or, if chosen, gained any experience) pop up on a HUD
-- strip of their own, newest first, each with its level over the icon (outlined, like the buff bar's count),
-- a progress bar to the next level (green while it rises, red while it falls) and its mode as the colour of
-- its frame; they go a while after their last change (or stay: "Always"). Vertical or horizontal. Plus a
-- "Skill level changes" notification (a level gained or lost), on the notification HUD only (never a window to
-- close; owner, 2026-10-02).
--
-- Training markers (API 27, ShroudSetSkillMode; owner, 2026-10-03): each icon's LEFT half opens the game's
-- Skills window (ShroudToggleWindow, on the click's gesture); its RIGHT half holds three click areas, top to
-- bottom TRAIN (green arrow up), MAINTAIN (yellow square), UNLEARN (red arrow down). A click sets that mode
-- directly (no cycling: one click too many would land on Unlearn). The skill's mode lit, the others faded;
-- ShroudCanSetSkillMode fades further (SK.MARK_NO) a mode the game wouldn't take, whose click does nothing.
-- "Off" (NotLearning) has no marker: all three faded. A sound per mode set. The click areas are pictures laid
-- over the icon after its level labels (so a click can't land on a label); the markers are toolbox/skillmarks.png
-- (art/marks.py), tinted and turned. Without API 27, or with the setting off, the whole icon opens the window.
--
-- ShroudOnSkillsChanged fires on every experience gain, which in combat is constantly: an event only marks
-- the skills to be read, and the periodic (SK.TICK) reads them at most every SK.QUIET_EVERY s for experience
-- alone (SK.XP_EVERY with "Any experience"), at once for a level. Early on levels come often (owner): a skill
-- has one slot, refreshed in place, in a fixed pool; the one quiet longest makes room.
--
-- Built to be easy to take out (owner, 2026-10-02: "not 100% sure"): everything is in this file, which
-- registers itself (its strip, command, settings page, guide topic, notification source, saved-var key);
-- the other files only call it where `Toolbox.SkillBar` exists. To remove: delete this file and its
-- manifest entry (and the README.md load-order line), toolbox/skill_up.ogg, skill_down.ogg, skill_train.ogg,
-- skill_maintain.ogg and skill_unlearn.ogg (and their entries in art/alerts.py), toolbox/skillmarks.png and
-- art/marks.py, tests/test_skills.lua and its line in tests/run.lua, and the "Skill activity"
-- parts of both READMEs, CHANGELOG and AGENTS.md. The guarded lines elsewhere can stay.
--
-- Sounds (owner, 2026-10-02): a short celebration when a skill gains a level (skill_up) and a sad one when it
-- loses one (skill_down), each optional, played with the strip on (with it off, only the notification's own
-- "+ sound"), at most one of each per SK.SOUND_GAP s (early levels come in bursts). They are Toolbox.Sounds
-- definitions, so a player's own file works as for the other alerts.
--
-- Saved var "skills": { show = bool (default false), vertical = bool (default true), slots = 1..12,
-- stay = seconds (SK.STAY_CHOICES; 0 = always), trigger = "levels" | "xp", size = 20..48, number = bool
-- (the level on the icon, default true), marks = bool (the training markers, default true), soundUp = bool
-- (default true), soundDown = bool (default true), x, y }.

local T = Toolbox
local SK = {}
Toolbox.SkillBar = SK

local UI = Shroud.UI
local PERIODIC = "toolbox_skills"

SK.PAGE = "Skill activity"            -- the settings page, the Position row and the guide topic
SK.FRAME_ID = "toolbox_skills"
SK.HOME = { 1200, 200 }
SK.TICK = 0.5
SK.QUIET_EVERY = 5                    -- seconds between reads for experience alone ("levels")
SK.XP_EVERY = 1                       -- ... with "Any experience"
SK.SLOTS_MIN, SK.SLOTS_MAX, SK.SLOTS_DEFAULT = 1, 12, 6
SK.SIZE_MIN, SK.SIZE_MAX, SK.SIZE_DEFAULT = 20, 48, 32
SK.STAY_CHOICES = { { 10, "10 seconds" }, { 20, "20 seconds" }, { 30, "30 seconds" }, { 60, "1 minute" },
                    { 120, "2 minutes" }, { 300, "5 minutes" }, { 0, "Always" } }   -- 0: never goes
-- The progress bar's colour by the way the skill last moved (none yet: gold).
SK.DIR_COLORS = { up = "@green", down = "@red" }
SK.BAR_COLOR = "@gold"
SK.NUMBER_COLOR = "@text-bright"
SK.STAY_DEFAULT = 30
SK.NEW_FOR = 10                       -- seconds a new level shows in gold
SK.GAP = 3
SK.TRIGGERS = { "levels", "xp" }
SK.TRIGGER_LABELS = { levels = "Level ups and mode changes", xp = "Any experience" }
-- A skill's mode, as its frame's colour and in words (the game's triangle; ShroudGetSkills `mode`).
SK.MODES = {
  Learning = { color = "@green", label = "Training" },
  Maintaining = { color = "@blue", label = "Maintaining" },
  Unlearning = { color = "@red", label = "Unlearning" },
  NotLearning = { color = "#00000000", label = "Not training" },
}
SK.PLACEHOLDER = "Skills"
SK.SOUND_GAP = 3                      -- seconds: at most one level-up (and one level-down) sound in this time
-- A level gained: the icon flashes for SK.FLASH_SECONDS (owner, 2026-10-03: "help it stand out"), its frame
-- turning SK.FLASH_COLOR and the icon dimming to SK.FLASH_DIM every other SK.FLASH_HALF s.
SK.FLASH_SECONDS, SK.FLASH_HALF, SK.FLASH_COLOR, SK.FLASH_DIM = 4, 0.25, "@gold", 0.5
local FLASH = "toolbox_skills_flash"
-- The training markers, top to bottom: the mode each sets, its colour, its frame of skillmarks.png (two 3:2
-- frames: an arrow up, a square), its turn, its sound and the word for chat and tooltips.
SK.MARK_PATH = "toolbox/skillmarks.png"
SK.MARKS = {
  { mode = "Learning", color = "@green", uv = { 0, 0, 0.5, 1 }, rotation = 0, sound = "skill_train", word = "train" },
  { mode = "Maintaining", color = "@gold", uv = { 0.5, 0, 0.5, 1 }, rotation = 0, sound = "skill_maintain",
    word = "maintain" },
  { mode = "Unlearning", color = "@red", uv = { 0, 0, 0.5, 1 }, rotation = 180, sound = "skill_unlearn",
    word = "unlearn" },
}
SK.MARK_ON, SK.MARK_OFF, SK.MARK_NO = 1, 0.35, 0.12   -- opacity: the mode now, another, one the game won't take
-- What ShroudSetSkillMode's reasons mean, for chat.
SK.MODE_REASONS = {
  notSpecialized = "not one of your specializations, so it maintains instead",
  belowFloor = "too low to maintain or unlearn, so it stops training instead",
  specialRule = "an elixir skill: it only changes in the game's Skills window",
  unknownSkill = "not a skill you have trained",
  notNow = "not right now (loading, talking, crafting, looting or in a menu)",
  needsGesture = "it needs a click",
  gestureSpent = "too many changes from one click",
  tooOften = "too many changes in a short time; wait a few seconds",
}

local prefs = { show = false }
local state = nil                     -- the model (SK.NewState)
local content, slots, placeholder = nil, {}, nil
local shownCount = nil                -- slots shown when the strip was last fitted
local needRead, xpDirty, lastRead = true, false, -math.huge
local readFor = nil                   -- the character the state belongs to
local wasInUse = false                -- read last tick: off and on again takes a new baseline

-- ---------------------------------------------------------------------------
-- Model (pure): what changed between two readings, and the skills on the strip
-- ---------------------------------------------------------------------------

-- A fresh model: `prev` = the last reading by skill id, `active` = the skills on the strip, newest first
-- ({ id, at = last change, levelAt = last level change, data = the reading }), `changes` = levels gained or
-- lost, for the notification ({ n, list = { { id = n, name, from, to } } }). `changes` carries over a new
-- baseline: the notification remembers the last number it delivered, so the numbering must not start again.
function SK.NewState(changes)
  return { prev = {}, active = {}, based = false, changes = changes or { n = 0, list = {} }, ups = 0, downs = 0 }
end

-- The game's skill list as plain readings { id, name, level, trained, exp, progress, mode, icon }.
function SK.Read(list)
  local out = {}
  for _, s in ipairs(T.List(list)) do
    local id = T.Field(s, "id")
    local level = T.Field(s, "level")
    if id ~= nil and type(level) == "number" then
      local name = T.Field(s, "name")
      local exp, progress = T.Field(s, "experience"), T.Field(s, "progress")
      local trained, mode, icon = T.Field(s, "trainedLevel"), T.Field(s, "mode"), T.Field(s, "icon")
      local key = T.Field(s, "key")
      out[#out + 1] = {
        id = id, key = type(key) == "string" and key or nil,
        name = type(name) == "string" and name or tostring(key or id), level = level,
        trained = type(trained) == "number" and trained or level, exp = type(exp) == "number" and exp or 0,
        progress = type(progress) == "number" and math.max(0, math.min(1, progress)) or 0,
        mode = SK.MODES[mode] and mode or "NotLearning", icon = type(icon) == "number" and icon or -1,
      }
    end
  end
  return out
end

local function touch(st, r, now, levelled, keep, dir)
  local entry = nil
  for i, e in ipairs(st.active) do
    if e.id == r.id then
      entry = table.remove(st.active, i)
      break
    end
  end
  entry = entry or { id = r.id, levelAt = -math.huge }
  entry.at, entry.data = now, r
  if levelled then entry.levelAt = now end
  if levelled and dir == "up" then entry.flashUntil = now + SK.FLASH_SECONDS end   -- a level gained: it flashes
  if dir then entry.dir = dir end
  table.insert(st.active, 1, entry)
  for i = #st.active, keep + 1, -1 do st.active[i] = nil end
end

-- Takes a reading (SK.Read) at `now`: a skill whose level or mode changed (or, with trigger "xp", whose
-- experience changed) goes on top of `active`; one already there gets the new reading. The first reading only
-- sets the baseline. A level gained or lost is queued in `changes` and counted in `ups` / `downs`; a level gained
-- sets the entry's `flashUntil`. Returns true when `active` changed. Pure.
function SK.Update(st, readings, now, trigger, keep)
  local changed = false
  for _, r in ipairs(readings) do
    local p = st.prev[r.id]
    if p then
      -- Levels are the TRAINED level: `level` is the tile's, capped in some scenes, and a capped scene would
      -- read as every skill losing levels (review, 2026-10-02).
      local levelled, moded = r.trained ~= p.trained, r.mode ~= p.mode
      -- which way it moved: up (a level, or experience at the same level) or down
      local dir = nil
      if r.trained > p.trained or (r.trained == p.trained and r.exp > p.exp) then
        dir = "up"
      elseif r.trained < p.trained or (r.trained == p.trained and r.exp < p.exp) then
        dir = "down"
      end
      if levelled or moded or (trigger == "xp" and r.exp ~= p.exp) then
        touch(st, r, now, levelled, keep, dir)
        changed = true
      else
        for _, e in ipairs(st.active) do
          local d = e.data
          if e.id == r.id and (d.progress ~= r.progress or d.level ~= r.level or d.exp ~= r.exp) then
            e.data, changed = r, true          -- on the strip already: its progress moves
            if dir then e.dir = dir end
          end
        end
      end
      if levelled then
        if r.trained > p.trained then st.ups = st.ups + 1 else st.downs = st.downs + 1 end   -- for the sounds
        local ch = st.changes
        ch.n = ch.n + 1
        ch.list[#ch.list + 1] = { id = ch.n, name = r.name, from = p.trained, to = r.trained }
        if #ch.list > 20 then table.remove(ch.list, 1) end
      end
      p.trained, p.mode, p.exp = r.trained, r.mode, r.exp
    else
      st.prev[r.id] = { trained = r.trained, mode = r.mode, exp = r.exp }
      if st.based then                         -- a skill learned just now
        touch(st, r, now, true, keep)
        changed = true
      end
    end
  end
  st.based = true
  return changed
end

-- Drops the skills quiet for longer than `stay` seconds (0: none ever). True when any went. Pure.
function SK.Expire(st, now, stay)
  if stay <= 0 then return false end
  local gone = false
  for i = #st.active, 1, -1 do
    if now - st.active[i].at > stay then
      table.remove(st.active, i)
      gone = true
    end
  end
  return gone
end

-- The level changes after `seen` as one notice text ("Fireball up to 42, Archery down to 9."): each skill
-- once, from where it was before the first to where the last left it ("back to" when that is where it
-- started); the newest number; and whether every one went down. nil when there are none. Pure.
function SK.ChangesText(changes, seen)
  local last = type(seen) == "number" and seen or 0
  if changes.n <= last then return nil end
  local order, from, to = {}, {}, {}
  for _, c in ipairs(changes.list) do
    if c.id > last then
      if from[c.name] == nil then
        order[#order + 1] = c.name
        from[c.name] = c.from
      end
      to[c.name] = c.to
    end
  end
  if #order == 0 then return nil end
  local parts, allDown = {}, true
  for i, name in ipairs(order) do
    local way = "back to"
    if to[name] > from[name] then way = "up to" elseif to[name] < from[name] then way = "down to" end
    if to[name] >= from[name] then allDown = false end
    parts[i] = name .. " " .. way .. " " .. math.floor(to[name])
  end
  return table.concat(parts, ", ") .. ".", changes.n, allDown
end

-- A slot's tooltip (pure).
-- The level shown is the trained one (the skill's own); a scene's cap is mentioned when it applies.
function SK.Tooltip(r)
  local mode = SK.MODES[r.mode] or SK.MODES.NotLearning
  local line = string.format("Level %d", math.floor(r.trained))
  if r.level ~= r.trained then line = line .. string.format(" (%d in this scene)", math.floor(r.level)) end
  return r.name .. "\n" .. line .. string.format(", %d%% to the next", math.floor(r.progress * 100))
    .. "\n" .. mode.label .. "\nClick: open the Skills window"
end

-- ---------------------------------------------------------------------------
-- The strip (a Toolbox.Hud module)
-- ---------------------------------------------------------------------------

local function size() return prefs.size or SK.SIZE_DEFAULT end
local function slotCount() return prefs.slots or SK.SLOTS_DEFAULT end
local function stay() return prefs.stay or SK.STAY_DEFAULT end
local function trigger() return prefs.trigger or "levels" end
local function font(s) return math.max(9, math.min(32, math.floor(s * 0.36 + 0.5))) end
local function numberShown() return prefs.number ~= false end
local BAR_H = 3
local function slotH(s) return s + 1 + BAR_H end

-- How many skills the strip shows now.
local function showing()
  return math.min(#(state and state.active or {}), slotCount())
end

function SK.Wanted() return prefs.show == true end
function SK.IsShown()
  if prefs.show ~= true then return false end
  return showing() > 0 or T.Config.IsShown()       -- empty while settings are open: its name, to place it
end

local function slotStyles(s)
  return { width = s, marginRight = prefs.vertical == false and SK.GAP or 0,
           marginBottom = prefs.vertical == false and 0 or SK.GAP },
         { width = s, height = s, minHeight = s, borderWidth = 2, borderColor = "#00000000",
           backgroundColor = "#00000066" },
         { width = s, height = BAR_H, minHeight = BAR_H, maxHeight = BAR_H, marginTop = 1 }
end

-- The level over the icon: the buff bar's count style (BB.CountStyle), a dark copy nudged each way
-- (BB.COUNT_OUTLINE) under the bright one, so it reads on any icon. Index #outline + 1 is the bright one,
-- whose colour Fill sets (gold when new); `sizeOnly` leaves the outline's colour out too (a resize).
-- With the training markers on the right half, the level is SK.MARKED_FONT of its size and left-aligned,
-- SK.MARKED_INSET of the icon in, so three digits stay clear of the markers (owner, 2026-10-03).
SK.MARKED_FONT, SK.MARKED_INSET = 0.8, 0.06
local function numberStyle(s, i, sizeOnly)
  local BB = T.BuffBar
  local d = BB.COUNT_OUTLINE[i] or { 0, 0 }
  local marked = SK.ShowMarks()
  local f = BB.CountFont(s)
  if marked then f = math.max(9, math.floor(f * SK.MARKED_FONT)) end
  local style = BB.CountStyle(s, f, d[1], d[2])
  if marked then              -- left-aligned: a nudge moves the text by itself, not by half (as when centred)
    style.textAlign = "left"
    style.paddingLeft = math.max(1, math.floor(s * SK.MARKED_INSET)) + 1 + d[1]
    style.paddingRight = 0
  end
  if BB.COUNT_OUTLINE[i] and not sizeOnly then style.color = BB.OUTLINE_COLOR end
  return style
end

local function placeholderStyle(s)
  return { width = 3 * s, height = s, minHeight = s, fontSize = font(s), textAlign = "center",
           paddingTop = math.max(0, math.floor((s - font(s) * 1.2) / 2)) }
end

local function openSkills()
  if type(ShroudToggleWindow) ~= "function" then return end   -- (an Image's click passes it; unused)
  local ok, done, reason = pcall(ShroudToggleWindow, "skills", true)
  if ok and not done and reason ~= "ok" then
    T.Print("The Skills window can't open right now (" .. tostring(reason) .. ").")
  end
end

-- Training markers ---------------------------------------------------------------

local markTex = -1
-- Whether this client can set a skill's mode (API 27).
function SK.HasModes() return type(ShroudSetSkillMode) == "function" and type(ShroudCanSetSkillMode) == "function" end
function SK.ShowMarks() return prefs.marks ~= false and SK.HasModes() end

-- The click areas' sizes for icon size s: the left half, the right half, and the three bands' heights.
local function markSizes(s)
  local left = math.floor(s / 2)
  local third = math.floor(s / 3)
  return left, s - left, { third, third, s - 2 * third }
end

-- A picture spec without nil entries: `texture` only once it has loaded.
local function picture(w, h, extra)
  local spec = { width = w, height = h }
  if markTex >= 0 then spec.texture = markTex end
  for k, v in pairs(extra) do spec[k] = v end
  return spec
end

-- Sets slot `i`'s skill to `mark`'s mode (a click on that marker: the gesture).
function SK.SetMode(i, mark)
  local slot = slots[i]
  local e = slot and state.active[slot.at or i]
  if not e or not SK.HasModes() then return end
  local r = e.data
  if r.mode == mark.mode then return end                       -- already: nothing to do
  if slot.can and slot.can[mark.mode] == false then return end  -- the game won't take it (a rule, not "not now")
  local ok, okSet, reason, mode = pcall(ShroudSetSkillMode, r.key or r.id, mark.mode)
  if not ok then return end
  if okSet and type(mode) == "string" and SK.MODES[mode] then
    r.mode = mode                                              -- at once; the game's event confirms it
    local played = mark
    for _, m in ipairs(SK.MARKS) do if m.mode == mode then played = m end end
    if mode ~= "NotLearning" then T.Sounds.Play(played.sound) end
    if reason ~= "ok" then
      T.Print(r.name .. ": " .. (SK.MODE_REASONS[reason] or tostring(reason)) .. ".")
    end
    slot.can = nil
    SK.Fill()
  else
    T.Print("Can't " .. mark.word .. " " .. r.name .. ": " .. (SK.MODE_REASONS[reason] or tostring(reason)) .. ".")
  end
end

-- ShroudCanSetSkillMode's refusals that pass (outside normal play, the gesture limits): not a rule about the
-- skill, so not remembered (review, 2026-10-03: a "notNow" at the first look left the markers refused all session).
SK.PASSING = { notNow = true, needsGesture = true, gestureSpent = true, tooOften = true }

-- Lights the skill's mode, fades the others (further those the game won't take). Per skill and mode, a firm
-- answer is remembered until the skill or its mode changes: true, or false for a rule (an elixir skill...); a
-- passing refusal or an error is unknown (nil), asked again at the next fill, and its click left to the game.
local function fillMarks(slot, r, tip)
  if not slot.marks then return end
  local sig = tostring(r.id) .. ":" .. r.mode
  if slot.can == nil or slot.canFor ~= sig then slot.can, slot.canFor = {}, sig end
  for _, m in ipairs(SK.MARKS) do
    if m.mode ~= r.mode and slot.can[m.mode] == nil then
      local ok, can, reason = pcall(ShroudCanSetSkillMode, r.key or r.id, m.mode)
      if ok and can == true then
        slot.can[m.mode] = true
      elseif ok and not SK.PASSING[reason] then
        slot.can[m.mode] = false
      end                                   -- else unknown: asked again next time
    end
  end
  for j, m in ipairs(SK.MARKS) do
    local now = m.mode == r.mode
    local op = SK.MARK_OFF
    if now then op = SK.MARK_ON elseif slot.can[m.mode] == false then op = SK.MARK_NO end
    T.SetStyle(slot.marks[j], { opacity = op })
    local how = "Click: " .. m.word
    if now then how = "Now: " .. m.word .. "ing" elseif slot.can[m.mode] == false then how = "Can't " .. m.word end
    T.SetTooltip(slot.marks[j], r.name .. "\n" .. how)
  end
  T.SetTooltip(slot.open, tip)
end

function SK.BuildContent()
  local s = size()
  local slotS, frameS, barS = slotStyles(s)
  if SK.ShowMarks() and markTex < 0 then
    local ok, tex = pcall(ShroudLoadTexture, SK.MARK_PATH)
    if ok and type(tex) == "number" then markTex = tex end
  end
  slots = {}
  local children = {}
  placeholder = UI.Label{ id = "sk_placeholder", text = SK.PLACEHOLDER, class = "dim", visible = false,
    style = placeholderStyle(s) }
  children[1] = placeholder
  for i = 1, slotCount() do
    local icon = UI.Image{ width = s, height = s, onClick = openSkills }   -- a click handler: its tooltip shows
    local kids, numbers = { icon }, {}
    for j = 1, #T.BuffBar.COUNT_OUTLINE + 1 do                            -- the outline, then the bright one
      numbers[j] = UI.Label{ text = "", class = "bright", visible = numberShown(), style = numberStyle(s, j) }
      kids[#kids + 1] = numbers[j]
    end
    local open, marks, overlay = nil, nil, nil
    if SK.ShowMarks() then        -- over the icon, after the labels: the left half opens Skills, the right sets modes
      local lw, rw, bands = markSizes(s)
      open = UI.Image(picture(lw, s, { tint = "#ffffff00", onClick = openSkills }))
      marks = {}
      for j, m in ipairs(SK.MARKS) do
        local slotIndex = i
        marks[j] = UI.Image(picture(rw, bands[j], { tint = m.color, uv = m.uv, rotation = m.rotation,
          onClick = function() SK.SetMode(slotIndex, m) end }))
      end
      overlay = UI.Row{ style = { width = s, height = s, minHeight = s, marginLeft = -s, alignItems = "start" },
        children = { open, UI.Column{ children = marks } } }
      kids[#kids + 1] = overlay
    end
    local frame = UI.Row{ children = kids, style = frameS }
    local bar = UI.Bar{ value = 0, color = SK.BAR_COLOR, style = barS }
    local col = UI.Column{ id = "sk_" .. i, visible = false, style = slotS, children = { frame, bar } }
    slots[i] = { col = col, icon = icon, frame = frame, bar = bar, numbers = numbers, label = numbers[#numbers],
                 barColor = SK.BAR_COLOR, open = open, marks = marks, overlay = overlay, at = i }
    children[#children + 1] = col
  end
  if prefs.vertical == false then
    content = UI.Row{ id = "skills", style = { alignItems = "start" }, children = children }
  else
    content = UI.Column{ id = "skills", children = children }
  end
  shownCount = showing()               -- Toolbox.Hud is building: it fits the strip itself afterwards
  SK.Fill()
  return content
end

function SK.Unbuilt()
  content, placeholder, slots, shownCount = nil, nil, {}, nil
  if SK.flashing then
    SK.flashing = false
    pcall(ShroudRemovePeriodic, FLASH)
  end
end

function SK.ContentSize()
  local s = size()
  local n = showing()
  if n == 0 then return 3 * s, s end              -- the placeholder (settings open)
  if prefs.vertical == false then return n * (s + SK.GAP), slotH(s) end
  return s, n * (slotH(s) + SK.GAP)
end

-- Puts the active skills into the slots (and re-fits the strip when how many show changed).
function SK.Fill()
  if not content then return end
  local now = T.Now()
  local n = showing()
  local flashing = false
  for i, slot in ipairs(slots) do
    local e = i <= n and state.active[i] or nil
    if e then
      local r = e.data
      if r.icon ~= slot.tex then
        slot.tex = r.icon
        if r.icon >= 0 then slot.icon:SetTexture(r.icon) end
      end
      T.SetVisible(slot.icon, r.icon >= 0)
      local flash = now < (e.flashUntil or -math.huge)
      local lit = flash and math.floor(now / SK.FLASH_HALF) % 2 == 0
      if flash then flashing = true end
      local border = (SK.MODES[r.mode] or SK.MODES.NotLearning).color
      if lit then border = SK.FLASH_COLOR end
      T.SetStyle(slot.frame, { borderColor = border })
      local dim = 1
      if flash and not lit then dim = SK.FLASH_DIM end
      T.SetStyle(slot.icon, { opacity = dim })
      T.SetValue(slot.bar, r.progress)
      local barColor = SK.DIR_COLORS[e.dir] or SK.BAR_COLOR
      if barColor ~= slot.barColor then
        slot.barColor = barColor
        slot.bar:SetColor(barColor)
      end
      local level = tostring(math.floor(r.trained))   -- the skill's own level, not the scene's cap
      local tip = SK.Tooltip(r)
      for _, label in ipairs(slot.numbers) do
        T.SetText(label, level)
        T.SetTooltip(label, tip)                     -- the level covers the icon: the pointer may be on it
      end
      local fresh = now - e.levelAt < SK.NEW_FOR
      T.SetStyle(slot.label, { color = fresh and "@gold" or SK.NUMBER_COLOR })
      T.SetTooltip(slot.icon, tip)
      fillMarks(slot, r, tip)
    end
    T.SetVisible(slot.col, e ~= nil)
  end
  T.SetVisible(placeholder, n == 0)
  if n ~= shownCount then
    shownCount = n
    T.Hud.Refresh()
  end
  -- a quick periodic only while an icon flashes (the strip's own runs every SK.TICK)
  if flashing and not SK.flashing then
    SK.flashing = true
    ShroudRegisterPeriodic(FLASH, SK.Fill, SK.FLASH_HALF, true)
  elseif not flashing and SK.flashing then
    SK.flashing = false
    pcall(ShroudRemovePeriodic, FLASH)
  end
end

-- Resizes in place (the Size slider fires many changes).
local function applySize()
  if not content then return end
  local s = size()
  local slotS, frameS, barS = slotStyles(s)
  for _, slot in ipairs(slots) do
    slot.col:SetStyle(slotS)
    slot.frame:SetStyle{ width = frameS.width, height = frameS.height, minHeight = frameS.minHeight }
    slot.icon:SetSize(s, s)
    slot.bar:SetStyle(barS)
    for j, label in ipairs(slot.numbers) do label:SetStyle(numberStyle(s, j, true)) end
    if slot.marks then
      local lw, rw, bands = markSizes(s)
      slot.open:SetSize(lw, s)
      for j, m in ipairs(slot.marks) do m:SetSize(rw, bands[j]) end
      slot.overlay:SetStyle{ width = s, height = s, minHeight = s, marginLeft = -s }
    end
  end
  placeholder:SetStyle(placeholderStyle(s))
  T.Hud.Refresh()
end

function SK.GetSavedPosition() return prefs.x, prefs.y end
function SK.SavePosition(x, y)
  if x ~= prefs.x or y ~= prefs.y then
    prefs.x, prefs.y = x, y
    T.Save("skills", prefs)
  end
end

local mover = T.Hud.MoverFor("skills", SK.HOME)
SK.GetPosition, SK.MoveTo, SK.Nudge, SK.ResetPosition = mover.Get, mover.MoveTo, mover.Nudge, mover.Reset

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

-- Whether anything uses the readings: the strip, or the level change notification.
local function inUse() return prefs.show == true or T.Notify.IsOn("skills") end

-- ShroudOnSkillsChanged (core.lua): a level (read at the next tick) or experience only (read soon).
function SK.OnSkillsChanged(levelsChanged)
  if levelsChanged == false then xpDirty = true else needRead = true end
end

local function readNow(now)
  local ok, list = pcall(ShroudGetSkills)
  if not ok or list == nil then return end
  local who = ShroudGetPlayerName()
  if who ~= readFor then                            -- another character: a new baseline AND a new sequence:
    readFor, state = who, SK.NewState()             -- the notification's memory is per character too
    SK.Fill()
  end
  lastRead, needRead, xpDirty = now, false, false
  local before, upsBefore, downsBefore = state.changes.n, state.ups, state.downs
  if SK.Update(state, SK.Read(list), now, trigger(), SK.SLOTS_MAX) then SK.Fill() end
  if state.changes.n ~= before then
    -- The strip's own sounds belong to the strip: with it off, only the notification's "+ sound" plays
    -- (review, 2026-10-02); and with that on, the notification's sound alone, not both.
    local notifySound = T.Notify.IsOn("skills") and T.Notify.GetSound("skills")
    if prefs.show == true and not notifySound then
      if state.ups ~= upsBefore and prefs.soundUp ~= false then SK.PlaySound("skill_up", now) end
      if state.downs ~= downsBefore and prefs.soundDown ~= false then SK.PlaySound("skill_down", now) end
    end
    T.Notify.Check()
  end
end

-- Plays a skill sound unless the same one played in the last SK.SOUND_GAP seconds.
local soundAt = {}
function SK.PlaySound(key, now)
  if now - (soundAt[key] or -math.huge) < SK.SOUND_GAP then return end
  soundAt[key] = now
  T.Sounds.Play(key)
end

function SK.Tick()
  if not inUse() then
    wasInUse = false
    return
  end
  if not wasInUse then                               -- (back) in use: levels from while it was off aren't news
    wasInUse, needRead = true, true
    state = SK.NewState(state.changes)
    SK.Fill()                                        -- nothing on the strip from before
  end
  local now = T.Now()
  local every = SK.QUIET_EVERY
  if trigger() == "xp" then every = SK.XP_EVERY end
  if needRead or (xpDirty and now - lastRead >= every) then readNow(now) end
  local fading = false                                -- a new level's gold due to fade
  for i = 1, showing() do
    local age = now - state.active[i].levelAt
    if age >= SK.NEW_FOR and age < SK.NEW_FOR + 2 * SK.TICK then fading = true end
  end
  if SK.Expire(state, now, stay()) or fading then SK.Fill() end
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function save()
  T.Save("skills", prefs)
  T.Config.Sync()
end

function SK.GetShow() return prefs.show == true end
function SK.SetShow(on)
  prefs.show = on == true
  needRead = true
  save()
  T.Hud.Build(true)                  -- its frame exists only while it is in use (HUD frames are limited)
  T.Hud.Refresh()
end

function SK.GetVertical() return prefs.vertical ~= false end
function SK.SetVertical(on)
  prefs.vertical = on == true
  save()
  if prefs.show then T.Hud.Rebuild("skills") end   -- a Row or a Column: its strip rebuilt (rare)
end

function SK.GetSlots() return slotCount() end
function SK.SetSlots(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < SK.SLOTS_MIN or n > SK.SLOTS_MAX then return false end
  prefs.slots = n
  save()
  if prefs.show then T.Hud.Rebuild("skills") end   -- other elements: its strip rebuilt (rare)
  return true
end

function SK.GetSize() return size() end
function SK.SetSize(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < SK.SIZE_MIN or n > SK.SIZE_MAX then return false end
  prefs.size = n
  save()
  applySize()
  return true
end

function SK.GetStay() return stay() end
function SK.StayLabel(seconds)
  for _, c in ipairs(SK.STAY_CHOICES) do if c[1] == seconds then return c[2] end end
  return nil
end
function SK.SetStay(seconds)
  if not SK.StayLabel(seconds) then return false end
  prefs.stay = seconds
  save()
  return true
end

-- The level-up / level-down sounds (each on by default).
function SK.GetSoundUp() return prefs.soundUp ~= false end
function SK.GetSoundDown() return prefs.soundDown ~= false end
function SK.SetSoundUp(on)
  prefs.soundUp = on == true
  save()
end
function SK.SetSoundDown(on)
  prefs.soundDown = on == true
  save()
end

-- The level over the icon.
function SK.GetNumber() return numberShown() end
-- The training markers on the icons (API 27; on by default). A change rebuilds the strip (other elements).
function SK.GetMarks() return prefs.marks ~= false end
function SK.SetMarks(on)
  prefs.marks = on == true
  save()
  if prefs.show then T.Hud.Rebuild("skills") end
end

function SK.SetNumber(on)
  prefs.number = on == true
  save()
  for _, slot in ipairs(slots) do
    for _, n in ipairs(slot.numbers) do T.SetVisible(n, prefs.number) end
  end
end

function SK.GetTrigger() return trigger() end
function SK.SetTrigger(which)
  if not SK.TRIGGER_LABELS[which] then return false end
  prefs.trigger = which
  save()
  return true
end

function SK.Init()
  local saved = T.Load("skills")
  prefs = { show = false }
  if type(saved) == "table" then
    prefs.show = saved.show == true
    prefs.vertical = saved.vertical ~= false
    local function int(v, lo, hi)
      if type(v) == "number" and v >= lo and v <= hi then return math.floor(v) end
      return nil
    end
    prefs.slots = int(saved.slots, SK.SLOTS_MIN, SK.SLOTS_MAX)
    prefs.size = int(saved.size, SK.SIZE_MIN, SK.SIZE_MAX)
    if SK.StayLabel(saved.stay) then prefs.stay = saved.stay end
    if SK.TRIGGER_LABELS[saved.trigger] then prefs.trigger = saved.trigger end
    prefs.number = saved.number ~= false
    prefs.marks = saved.marks ~= false
    prefs.soundUp = saved.soundUp ~= false
    prefs.soundDown = saved.soundDown ~= false
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
  end
  state, readFor, wasInUse = SK.NewState(), nil, false
  needRead, xpDirty, lastRead = true, false, -math.huge
  T.Hud.Register("skills", SK)
  ShroudRegisterPeriodic(PERIODIC, SK.Tick, SK.TICK, true)
end

-- /toolbox skills debug
function SK.DebugLines()
  local lines = {}
  local ok, list = pcall(ShroudGetSkills)
  local readings = ok and SK.Read(list) or {}
  lines[1] = string.format("Skills read: %d; on the strip: %d; setting %s, %s, %s; %s", #readings,
    #(state and state.active or {}), prefs.show and "on" or "off", SK.GetVertical() and "vertical" or "horizontal",
    trigger(), T.Hud.Debug("skills"))
  for i, e in ipairs(state and state.active or {}) do
    if i > 5 then break end
    local r = e.data
    lines[#lines + 1] = string.format("  %s: level %s, trained %s, %d%%, %s, icon %s", r.name, tostring(r.level),
      tostring(r.trained), math.floor(r.progress * 100), r.mode, tostring(r.icon))
  end
  return lines
end

-- The settings page (config.lua builds it with its helpers `h`): the controls' ids in CONFIG_IDS.
SK.CONFIG_IDS = { "skills_show", "skills_vertical", "skills_trigger", "skills_stay", "skills_slots",
                  "skills_slots_value", "skills_size", "skills_size_value", "skills_number", "skills_sound_up",
                  "skills_sound_down", "skills_marks" }

function SK.ConfigSection(h)
  local ui = h.UI                      -- config's: the settings search reads the page through it
  local stays, triggers = {}, {}
  for i, c in ipairs(SK.STAY_CHOICES) do stays[i] = c[2] end
  for i, key in ipairs(SK.TRIGGERS) do triggers[i] = SK.TRIGGER_LABELS[key] end
  return ui.Column{ children = {
    h.heading(SK.PAGE, true),
    ui.Label{ text = "Your skills' icons pop up on a strip of their own as they level, with the level on the"
      .. " icon, a bar of the progress to the next (green rising, red falling) and the mode as the colour of the"
      .. " frame: green training, blue maintaining, red unlearning. Click one to open the game's Skills window.",
      class = "dim",
      style = { whiteSpace = "wrap" } },
    ui.Toggle{ id = "skills_show", text = "Show the skill activity strip", value = SK.GetShow(),
      onChange = function(_, v) SK.SetShow(v) end },
    ui.Toggle{ id = "skills_vertical", text = "Vertical (off: horizontal)", value = SK.GetVertical(),
      onChange = function(_, v) SK.SetVertical(v) end },
    h.dropdownRow("Show a skill on", { id = "skills_trigger", choices = triggers,
      value = SK.TRIGGER_LABELS[trigger()],
      tooltip = "Level ups and mode changes (quieter), or any experience it gains (everything you're training)",
      onChange = function(_, label)
        for key, l in pairs(SK.TRIGGER_LABELS) do if l == label then SK.SetTrigger(key) end end
      end }),
    h.dropdownRow("Keep it for", { id = "skills_stay", choices = stays, value = SK.StayLabel(stay()) or stays[1],
      tooltip = "How long a skill stays after its last change (Always: until newer ones need its place)",
      onChange = function(_, label)
        for _, c in ipairs(SK.STAY_CHOICES) do if c[2] == label then SK.SetStay(c[1]) end end
      end }),
    h.slider("skills_slots", "Most skills shown", SK.SLOTS_MIN, SK.SLOTS_MAX, 1, slotCount(),
      "When more are active, the one quiet longest makes room", function(n) SK.SetSlots(n) end),
    h.slider("skills_size", "Icon size", SK.SIZE_MIN, SK.SIZE_MAX, 2, size(), "The icons' size in pixels",
      function(n) SK.SetSize(n) end),
    ui.Toggle{ id = "skills_marks", text = "Training controls on the icons", value = SK.GetMarks(),
      enabled = SK.HasModes(),
      tooltip = SK.HasModes() and ("The right half of each icon: train (green), maintain (yellow), unlearn (red);"
        .. " click one to set it. The left half opens the Skills window") or "Needs a newer game client (Lua API 27)",
      onChange = function(_, v) SK.SetMarks(v) end },
    ui.Toggle{ id = "skills_number", text = "Show the level on the icon", value = SK.GetNumber(),
      tooltip = "The skill's level over its icon (gold just after it levels); its tooltip has it either way",
      onChange = function(_, v) SK.SetNumber(v) end },
    ui.Toggle{ id = "skills_sound_up", text = "Sound when a skill gains a level", value = SK.GetSoundUp(),
      style = { marginTop = 6 },
      tooltip = "A short celebration (at most one every few seconds), while the strip is on. Pick your own file"
        .. " on the Sounds page",
      onChange = function(_, v) SK.SetSoundUp(v) end },
    ui.Toggle{ id = "skills_sound_down", text = "Sound when a skill loses a level", value = SK.GetSoundDown(),
      tooltip = "A sad one, for unlearning or decay, while the strip is on. Pick your own file on the Sounds page",
      onChange = function(_, v) SK.SetSoundDown(v) end },
    ui.Label{ text = "A \"Skill level changes\" notification (Notifications page) can list them on the"
      .. " notification HUD too. Move the strip under HUD layout, or by its grip.", class = "dim",
      style = { whiteSpace = "wrap", marginTop = 6 } },
  } }
end

function SK.ConfigSync(h)
  h.setValue("skills_show", SK.GetShow())
  h.setValue("skills_vertical", SK.GetVertical())
  h.setValue("skills_trigger", SK.TRIGGER_LABELS[trigger()])
  h.setValue("skills_stay", SK.StayLabel(stay()))
  h.sliderValue("skills_slots", slotCount())
  h.sliderValue("skills_size", size())
  h.setValue("skills_number", SK.GetNumber())
  h.setValue("skills_marks", SK.GetMarks())
  h.setEnabled("skills_marks", prefs.show == true and SK.HasModes())
  h.setValue("skills_sound_up", SK.GetSoundUp())
  h.setValue("skills_sound_down", SK.GetSoundDown())
  for _, id in ipairs({ "skills_vertical", "skills_trigger", "skills_stay", "skills_slots", "skills_size",
                        "skills_number" }) do
    h.setEnabled(id, prefs.show == true)
  end
end

-- ---------------------------------------------------------------------------
-- Registration with the rest of Toolbox (top level: every file before this one is loaded)
-- ---------------------------------------------------------------------------

-- the strip: built after the others, before the target (which goes last)
table.insert(T.Hud.ORDER, #T.Hud.ORDER, "skills")
-- its settings are cleared by Backup & reset
T.Backup.KEYS[#T.Backup.KEYS + 1] = "skills"
-- its sounds: the Sounds page lists them (Test, a custom file), and Lua/toolbox_skill_up.ogg replaces one
T.Sounds.DEFS[#T.Sounds.DEFS + 1] = { key = "skill_up", file = "skill_up.ogg", label = "Skill level up" }
T.Sounds.DEFS[#T.Sounds.DEFS + 1] = { key = "skill_down", file = "skill_down.ogg", label = "Skill level down" }
T.Sounds.DEFS[#T.Sounds.DEFS + 1] = { key = "skill_train", file = "skill_train.ogg", label = "Skill set to train" }
T.Sounds.DEFS[#T.Sounds.DEFS + 1] = { key = "skill_maintain", file = "skill_maintain.ogg",
                                      label = "Skill set to maintain" }
T.Sounds.DEFS[#T.Sounds.DEFS + 1] = { key = "skill_unlearn", file = "skill_unlearn.ogg",
                                      label = "Skill set to unlearn" }
-- ... and any notification can play them (Sounds page, Notification sounds)
T.Notify.SOUNDS[#T.Notify.SOUNDS + 1] = { "skill_up", "Celebration" }
T.Notify.SOUNDS[#T.Notify.SOUNDS + 1] = { "skill_down", "Sad notes" }

-- "Skill level changes": a level gained or lost, on the notification HUD only (owner, 2026-10-02: levels down
-- too), off by default. Transient: the numbers restart with the add-on. With the default sound (Celebration),
-- a notice of levels lost only plays the Sad notes.
T.Notify.SOURCES[#T.Notify.SOURCES + 1] = {
  key = "skills", label = "Skill level changes", default = false, via = "hud", vias = { "hud" }, transient = true,
  soundKey = "skill_up",                       -- "+ sound" plays the celebration (any other can be picked)
  tip = "When your skills gain or lose a level, on the notification HUD (never a window)",
  Check = function(seen)
    -- only this character's changes (a switch is noticed at the next reading, maybe after this check)
    if not state or readFor == nil or readFor ~= ShroudGetPlayerName() then return nil end
    local text, n, allDown = SK.ChangesText(state.changes, seen)
    if not text then return nil end
    local notice = { title = "Skill level changes", text = text, seen = n }
    if allDown and T.Notify.GetSoundKey("skills") == "skill_up" then notice.soundKey = "skill_down" end
    return notice
  end,
}

-- the guide topic, before "Moving the HUD strips"
do
  local topic = { SK.PAGE,
    "/toolbox skills shows a strip of the skills you're levelling, like the game's own along the right: "
      .. "each icon pops up as the skill levels (or changes mode, or with \"Any experience\", gains any), with"
      .. " its level on it (gold when new; the icon flashes for 4 seconds), a bar of its progress to the next "
      .. "(green while it rises, red while it falls) and its mode as the frame's colour: green training, blue "
      .. "maintaining, red unlearning. It goes after a while with no change (Keep it for; Always keeps it). "
      .. "Hover for details. Click the left half of an icon to open the game's Skills window; its right half "
      .. "has the training controls (newer clients): green arrow up train, yellow square maintain, red arrow "
      .. "down unlearn, the one in use lit. Click one to set it, with a sound for each (Off is set in the "
      .. "Skills window).",
    "Settings, Skill activity: vertical or horizontal, what shows a skill, how long it stays, how many show, "
      .. "the icon size and whether the level shows on it. Notifications has \"Skill level changes\" for the "
      .. "notification HUD (off by default): levels gained and lost.",
    "A short celebration plays when a skill gains a level, a sad one when it loses one (each can be switched "
      .. "off; /toolbox skills sound off for both). Any notification can use them too (Sounds page: Celebration, "
      .. "Sad notes); Skill level changes uses Celebration (Sad notes for levels lost). Your own file: the "
      .. "Sounds page, or toolbox_skill_up.ogg / toolbox_skill_down.ogg (or .wav) in your Lua folder." }
  local at = #T.Docs.SECTIONS + 1
  for i, s in ipairs(T.Docs.SECTIONS) do
    if s[1] == "Moving the HUD strips" then at = i end
  end
  table.insert(T.Docs.SECTIONS, at, topic)
end

-- /toolbox skills
T.AddCommand("skills", "the skill activity strip (on|off; vertical|horizontal; xp|levels; sound on|off; move [x y]; "
  .. "debug)",
  function(rest)
    local word, args = T.ParseArgs(rest)
    word = word:lower()
    if word == "" then
      SK.SetShow(not prefs.show)
    elseif word == "on" or word == "off" then
      SK.SetShow(word == "on")
    elseif word == "vertical" or word == "horizontal" then
      SK.SetVertical(word == "vertical")
    elseif word == "xp" or word == "levels" then
      SK.SetTrigger(word)
    elseif word == "sound" then
      local a = args:lower()
      if a ~= "on" and a ~= "off" then
        T.Print("Use /" .. T.commands[1] .. " skills sound on|off (both the level-up and level-down sounds).")
        return
      end
      SK.SetSoundUp(a == "on")
      SK.SetSoundDown(a == "on")
    elseif word == "move" then
      T.MoveCommand(SK, "skills", SK.PAGE, args)
      return
    elseif word == "debug" then
      for _, line in ipairs(SK.DebugLines()) do T.Print(line) end
      return
    else
      T.Print("Use /" .. T.commands[1] .. " skills [on|off], vertical|horizontal, xp|levels, sound on|off, "
        .. "move [x y] or debug.")
      return
    end
    T.Print(SK.PAGE .. ": " .. (prefs.show and "on" or "off") .. ", " .. (SK.GetVertical() and "vertical" or
      "horizontal") .. "; shows a skill on " .. SK.TRIGGER_LABELS[trigger()]:lower() .. "; sounds: "
      .. (SK.GetSoundUp() and "up" or "") .. ((SK.GetSoundUp() and SK.GetSoundDown()) and " and " or "")
      .. (SK.GetSoundDown() and "down" or "") .. ((SK.GetSoundUp() or SK.GetSoundDown()) and "" or "off") .. ".")
  end)
