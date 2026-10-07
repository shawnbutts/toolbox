-- Toolbox: hud.lua
-- The HUD strips (Toolbox.Hud). HUD modules (the buff bar, the health & focus bars) build
-- only their content; this puts it in strips:
--   * unglued: one HUD frame per module, as before;
--   * glued:   one shared HUD frame "[grip | health & focus | buffs]" for the modules in
--              Hud.GLUE, moved and remembered as one (the owner's "glue the health bars to the
--              buff bar"); other modules (the combat HUD) keep their own frame either way.
-- Frames are sized to what they show (the game keeps HUD frames on screen by their full
-- size), re-fitted when a module's content size changes, and hidden when nothing in them is.
--
-- A module registers with Hud.Register(key, module), where module has:
--   FRAME_ID, HOME = { x, y }
--   BuildContent() -> element     (creates its elements; called on every (re)build)
--   ContentSize() -> w, h          (the content's size, without grip or padding)
--   IsShown() -> bool
--   HidesGlued() -> bool   (optional) true to hide the whole glued strip, not just this part
--                          (the buff bar's "only during combat" takes the health bars with it)
--   GetSavedPosition() -> x, y | nil ; SavePosition(x, y)   (its own strip's spot)

local T = Toolbox
local Hud = {}
Toolbox.Hud = Hud

Hud.GLUED_ID = "toolbox_hud"
Hud.GLUED_HOME = { 40, 260 }
Hud.ORDER = { "vitals", "buffs", "consumables", "combat", "gear", "xp", "daily", "notify", "target" }   -- build order
-- HUD frames per add-on: the work log (2026-10-01) raised it from 8 to 25 (the reference still said 8). The
-- real limit is learned from the game: when it refuses a frame for want of room (frames or the 35% screen
-- area), the strips built so far are the limit for the session (`frameCap`). Strips past it aren't built.
Hud.MAX_FRAMES = 25
Hud.GLUE = { vitals = true, buffs = true }     -- the ones that share a strip when glued (left to right as in ORDER)
-- Parts that go ABOVE or UNDER the glued strip's columns, full width from its left edge, when their
-- module's Below() says so; its Place() says "top" or "bottom" (the target's bars line up with the health
-- bars' left end; owner, 2026-09-29: on top by default).
Hud.BELOW = { target = true }
Hud.GAP = 6                           -- between the parts of the glued strip
Hud.PAD = 8                           -- the strip's own padding

local UI = Shroud.UI
local modules = {}                    -- key -> module
local frames = {}                     -- key -> HudFrame (unglued), or [GLUED_ID] -> the shared one
local contents = {}                   -- key -> content element
local sized = {}                      -- frame id -> "w,h" last applied
local prefs = { glued = false }
Hud.errors = {}                       -- key -> error text from the last build, for debug

function Hud.Register(key, module)
  modules[key] = module
end

function Hud.IsGlued() return prefs.glued == true end

-- The frame that holds module `key` right now (its own, or the shared one), or nil.
function Hud.FrameFor(key)
  if prefs.glued and Hud.GLUE[key] then return frames[Hud.GLUED_ID] end
  return frames[key]
end

local function below(key)
  local m = modules[key]
  return prefs.glued and Hud.BELOW[key] and m ~= nil and m.Below ~= nil and m.Below() == true
end
local function gluedHere(key) return prefs.glued and (Hud.GLUE[key] or below(key)) end
local function placeOf(key)
  local m = modules[key]
  local p = m and m.Place and m.Place()
  if p == "bottom" or p == "left" then return p end
  return "top"
end

-- Registered, and wanted as a strip (optional module method `Wanted`: the equipment bar glued
-- into the buff bar has no strip of its own).
local function present(key)
  local m = modules[key]
  return m ~= nil and (m.Wanted == nil or m.Wanted())
end

-- The game's element-creation cap ("elements are being created too fast") can still be hit while
-- start-up or a login builds everything (2026-09-28: the notification HUD at login). A strip that
-- fails that way is built again quietly Hud.RETRY_DELAY seconds later, when the budget has
-- refilled; only a failure that persists (or any other error) is reported in chat.
Hud.RETRY_DELAY, Hud.RETRY_MAX = 1.5, 4
local retries = 0
local retryWanted = false

local function tooFast(err) return tostring(err):find("too fast", 1, true) ~= nil end

-- A refusal for want of room: too many HUD frames, or their screen area. The game's wording isn't documented
-- (the harness says "too many HUD frames"), so any mention of HUD frames with a limit word counts.
function Hud.OutOfRoom(err)
  local e = tostring(err):lower()
  if not e:find("hud frame", 1, true) then return false end
  for _, w in ipairs({ "too many", "per add-on", "at most", "screen", "area", "limit" }) do
    if e:find(w, 1, true) then return true end
  end
  return false
end

local function failed(what, err)
  Hud.errors[what] = tostring(err)
  if tooFast(err) and retries < Hud.RETRY_MAX then
    retryWanted = true
  else
    T.Print("Couldn't build the " .. what .. " HUD: " .. tostring(err))
  end
end

-- Tells a module its content is gone (optional method Unbuilt): it must drop every element it holds
-- and skip its updates until built again. Otherwise its next update touches a destroyed element
-- ("Shroud.UI: this Row was destroyed", reported 2026-09-29 after switching the consumables bar off).
local function unbuilt(key)
  local m = modules[key]
  if m and m.Unbuilt then pcall(m.Unbuilt) end
end

-- A module's content, or nil when building it raised (so one broken strip doesn't stop the others
-- from being built and shown).
local function build(key)
  local ok, result = pcall(modules[key].BuildContent)
  if ok then return result end
  unbuilt(key)                        -- a half-built content (the creation cap) isn't used either
  failed(key, result)
  return nil
end

local frameCap = nil      -- the frame limit learned from a refusal this session (see Hud.MAX_FRAMES)
local function frameCount()
  local n = 0
  for _ in pairs(frames) do n = n + 1 end
  return n
end
function Hud.FrameCap() return frameCap or Hud.MAX_FRAMES end

-- A HUD frame, or nil and "room" when the game had no room for it (then frameCap is learned), or nil when
-- the constructor raised for another reason.
local function newFrame(what, spec)
  local ok, result = pcall(UI.HudFrame, spec)
  if ok then return result end
  if Hud.OutOfRoom(result) then
    frameCap = frameCount()
    return nil, "room"
  end
  failed(what, result)
  return nil
end

-- An overlay over the Toolbelt (Hud.SetOverlay: the combat shout): one provider with OverlayBuild() (an element,
-- or nil), OverlayUnbuilt() (its element was destroyed) and OverlayFit(w, h, left) (the Toolbelt's content is
-- w x h, starting `left` px in). Built as the last child of the Toolbelt's frame (the shared strip, or the buff
-- bar's own strip), so it draws over the rows; it lays itself out with negative margins (no net size).
local overlayIn = nil          -- the frame key holding it now
function Hud.SetOverlay(provider) Hud.overlay = provider end
local function overlayElement(frameKey)
  if not Hud.overlay then return nil end
  local ok, e = pcall(Hud.overlay.OverlayBuild)
  if not ok or not e then return nil end
  overlayIn = frameKey
  return e
end
local function dropOverlay(frameKey)
  if overlayIn and (frameKey == nil or frameKey == overlayIn) then
    overlayIn = nil
    if Hud.overlay then pcall(Hud.overlay.OverlayUnbuilt) end
  end
end
local function fitOverlay(frameKey, w, h, left)
  if overlayIn == frameKey and Hud.overlay then pcall(Hud.overlay.OverlayFit, w, h, left) end
end

local function destroyAll()
  for _, frame in pairs(frames) do pcall(function() frame:Destroy() end) end
  for key in pairs(contents) do unbuilt(key) end
  frames, contents, sized = {}, {}, {}
  dropOverlay(nil)
end

-- Strips past the frame limit (Hud.FrameCap) aren't built; the player is told once (until it fits again).
Hud.NAMES = { glued = "Toolbelt", vitals = "health bars", buffs = "buff bar", consumables = "consumables bar",
              combat = "combat stats",
              gear = "equipment bar", xp = "XP", daily = "Today", notify = "notification", target = "target" }
local noRoomSaid = {}
local function noRoom(key)
  Hud.errors[key] = "no room: at most " .. Hud.FrameCap() .. " HUD strips"
  if noRoomSaid[key] then return end
  noRoomSaid[key] = true
  T.Print("No room for the " .. (Hud.NAMES[key] or key) .. " strip: Toolbox can show " .. Hud.FrameCap()
    .. " HUD strips at once. Put some bars in the Toolbelt, or switch a strip off.")
end

-- (Re)builds every strip for the current glue setting.
-- `missingOnly` (the retry after the creation cap, or a module's Wanted() changing): keep the strips
-- that were built, remove the ones no longer wanted, and build only the missing ones, so it costs what
-- changed, not everything again.
function Hud.Build(missingOnly)
  if not missingOnly then destroyAll() end
  for key, frame in pairs(frames) do
    if modules[key] and not present(key) then     -- a HUD frame slot is freed (8 per add-on)
      pcall(function() frame:Destroy() end)
      dropOverlay(key)
      unbuilt(key)
      frames[key], contents[key], sized[frame] = nil, nil, nil
    end
  end
  Hud.errors = {}
  retryWanted = false
  if prefs.glued and not frames[Hud.GLUED_ID] then
    local parts = {}
    for _, key in ipairs(Hud.ORDER) do
      if present(key) and Hud.GLUE[key] then
        contents[key] = build(key)
        parts[#parts + 1] = contents[key]
      end
    end
    local over, under = {}, {}
    for _, key in ipairs(Hud.ORDER) do
      if present(key) and below(key) then
        contents[key] = build(key)
        if contents[key] then
          if placeOf(key) == "left" then           -- first in the columns' row, against the health bars
            contents[key]:SetStyle{ marginRight = Hud.GAP }
            table.insert(parts, 1, contents[key])
          elseif placeOf(key) == "bottom" then
            contents[key]:SetStyle{ marginLeft = T.Window.GRIP, marginTop = Hud.GAP }
            under[#under + 1] = contents[key]
          else
            contents[key]:SetStyle{ marginLeft = T.Window.GRIP, marginBottom = Hud.GAP }
            over[#over + 1] = contents[key]
          end
        end
      end
    end
    local ok, row = pcall(UI.Row, { style = { paddingLeft = T.Window.GRIP, alignItems = "start" }, children = parts })
    if ok and #over + #under > 0 then
      local column = {}
      for _, c in ipairs(over) do column[#column + 1] = c end
      column[#column + 1] = row
      for _, c in ipairs(under) do column[#column + 1] = c end
      ok, row = pcall(UI.Column, { children = column })
    end
    local glued = { row }
    if ok then glued[2] = overlayElement(Hud.GLUED_ID) end      -- after the row: drawn over it
    if ok then
      local frame, why = newFrame("glued", { id = Hud.GLUED_ID, x = prefs.x or Hud.GLUED_HOME[1],
        y = prefs.y or Hud.GLUED_HOME[2], width = 100, height = 40, visible = false,
        -- start past the drag grip; parts side by side, tops aligned
        children = glued })
      frames[Hud.GLUED_ID] = frame
      if why == "room" then                    -- its content goes too (it would hold elements for nothing)
        pcall(function() row:Destroy() end)
        dropOverlay(Hud.GLUED_ID)
        for _, key in ipairs(Hud.ORDER) do
          if contents[key] and (Hud.GLUE[key] or below(key)) then
            unbuilt(key)
            contents[key] = nil
          end
        end
        noRoom("glued")
      end
    else
      failed("glued", row)
    end
  end
  for _, key in ipairs(Hud.ORDER) do
    local have = frames[key] ~= nil
    if present(key) and not gluedHere(key) and not have then
      if frameCount() >= Hud.FrameCap() then
        noRoom(key)
      else
        noRoomSaid[key] = nil
        contents[key] = build(key)
      end
    end
    if contents[key] and not gluedHere(key) and not have then
      local m = modules[key]
      local x, y = m.GetSavedPosition()
      local kids = { contents[key] }
      if key == "buffs" then kids[2] = overlayElement(key) end   -- the Toolbelt on its own: over the buffs
      local ok, column = pcall(UI.Column, { style = { paddingLeft = T.Window.GRIP }, children = kids })
      if ok then
        local frame, why = newFrame(key, { id = m.FRAME_ID, x = x or m.HOME[1], y = y or m.HOME[2],
          width = 100, height = 40, visible = false, children = { column } })
        frames[key] = frame
        if why == "room" then
          pcall(function() column:Destroy() end)
          dropOverlay(key)
          unbuilt(key)
          contents[key] = nil
          noRoom(key)
        end
      else
        failed(key, column)
      end
    end
  end
  Hud.Refresh()
  if retryWanted then
    retries = retries + 1
    ShroudRegisterPeriodic("toolbox_hud_retry", function() Hud.Build(true) end, Hud.RETRY_DELAY, false)
  else
    retries = 0
  end
end

local function setSize(frame, w, h)
  local key = w .. "," .. h
  if sized[frame] == key then return end
  sized[frame] = key
  pcall(function() frame:SetSize(w, h) end)   -- refused past the HUD area limit: keep the old size
end

-- Rebuilds one module's own strip and leaves the others alone (a setting that changes its elements, such as
-- the buff block's width): a full Hud.Build would create every strip's elements again at once, past the
-- game's creation cap for a big one. In the Toolbelt, the shared strip is rebuilt as before.
function Hud.Rebuild(key)
  if gluedHere(key) then
    Hud.Build()
    return
  end
  local frame = frames[key]
  if frame then
    pcall(function() frame:Destroy() end)
    dropOverlay(key)
    unbuilt(key)
    frames[key], contents[key], sized[frame] = nil, nil, nil
  end
  Hud.Build(true)
end

-- Sizes and shows/hides the strips (call when a module's content size or shown state changes).
function Hud.Refresh()
  local frame = prefs.glued and frames[Hud.GLUED_ID]
  if frame then
    local w, h, any, hideAll = 0, 0, false, false
    for _, key in ipairs(Hud.ORDER) do
      local content = Hud.GLUE[key] and contents[key]
      if content and modules[key].HidesGlued and modules[key].HidesGlued() then hideAll = true end
      if content then
        local shown = modules[key].IsShown()
        T.SetVisible(content, shown)
        if shown then
          local cw, ch = modules[key].ContentSize()
          content:SetStyle{ marginLeft = any and Hud.GAP or 0 }
          w, h, any = w + (any and Hud.GAP or 0) + cw, math.max(h, ch), true
        end
      end
    end
    for _, key in ipairs(Hud.ORDER) do          -- the parts above, under or left of the columns
      local content = Hud.BELOW[key] and below(key) and contents[key]
      if content then
        local shown = any and modules[key].IsShown()
        T.SetVisible(content, shown)
        if shown then
          local cw, ch = modules[key].ContentSize()
          if placeOf(key) == "left" then
            w, h = w + Hud.GAP + cw, math.max(h, ch)
          else
            w, h = math.max(w, cw), h + Hud.GAP + ch
          end
        end
      end
    end
    if hideAll then any = false end
    T.SetVisible(frame, any)
    if any then
      setSize(frame, T.Window.GRIP + w + Hud.PAD, h + Hud.PAD)
      fitOverlay(Hud.GLUED_ID, w, h, T.Window.GRIP)
    end
  end
  for key, own in pairs(frames) do
    if modules[key] and contents[key] then
      local shown = modules[key].IsShown()
      T.SetVisible(own, shown)
      if shown then
        local cw, ch = modules[key].ContentSize()
        setSize(own, T.Window.GRIP + cw + Hud.PAD, ch + Hud.PAD)
        fitOverlay(key, cw, ch, 0)
      end
    end
  end
end

-- Remembers where the player put the strips (grip drags included); from Toolbox.Tick.
-- Whether a strip is on screen now. Only those are measured: a hidden strip can't be dragged, and one never
-- shown may not be laid out yet (the notification HUD, hidden until a notice comes, was sent back to the top-left
-- corner after client restarts and account switches; owner, 2026-10-05).
local function onScreen(frame)
  if not frame then return false end
  local ok, v = pcall(frame.IsVisible, frame)
  return ok and v == true
end

-- Whether a module's part is on screen now: built, shown, and its strip (its own, or the Toolbelt's) showing. A
-- combat-only Toolbelt hides the whole strip with the parts still built and shown (review, 2026-10-07, 17).
function Hud.PartOnScreen(key)
  local content = contents[key]
  if not content or not onScreen(content) then return false end
  local frame = frames[key]
  if prefs.glued and Hud.GLUE[key] and frames[Hud.GLUED_ID] then frame = frames[Hud.GLUED_ID] end
  return onScreen(frame)
end

-- Remembers where the player put the strips (grip drags included); from Toolbox.Tick. Nothing while no character
-- is in the world (the login screen, a loading screen): what the strips report then isn't the player's.
function Hud.Tick()
  if not T.CharacterName() then return end
  if prefs.glued and onScreen(frames[Hud.GLUED_ID]) then
    local x, y = Hud.Position(frames[Hud.GLUED_ID])
    if x and (x ~= prefs.x or y ~= prefs.y) then
      prefs.x, prefs.y = x, y
      T.Save("hud", prefs)
    end
  end
  for key, frame in pairs(frames) do
    if modules[key] and onScreen(frame) then
      local x, y = Hud.Position(frame)
      if x then modules[key].SavePosition(x, y) end
    end
  end
end

function Hud.Position(frame)
  if not frame then return nil end
  local ok, x, y = pcall(frame.GetPosition, frame)
  if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
  return math.floor(x + 0.5), math.floor(y + 0.5)
end

-- A mover (Get / MoveTo / Nudge / Reset) for module `key`: it moves whichever strip holds it.
function Hud.MoverFor(key, home)
  return T.Window.HudMover(function() return Hud.FrameFor(key) end, home, function()
    return gluedHere(key) and Hud.GLUED_HOME or home
  end)
end

-- One chat line about module `key`'s strip, for /toolbox <module> debug.
function Hud.Debug(key)
  local m = modules[key]
  if not m then return key .. ": not registered" end
  local frame = Hud.FrameFor(key)
  local parts = { key .. ": shown setting " .. tostring(m.IsShown()) }
  if Hud.errors[key] then parts[#parts + 1] = "build error: " .. Hud.errors[key] end
  parts[#parts + 1] = "content " .. (contents[key] and "built" or "missing")
  if frame then
    local ok, vis = pcall(frame.IsVisible, frame)
    local okS, w, h = pcall(frame.GetSize, frame)
    local x, y = Hud.Position(frame)
    parts[#parts + 1] = string.format("strip %s, visible %s, size %s x %s, at %s, %s",
      frame == frames[Hud.GLUED_ID] and "shared (glued)" or "own", ok and tostring(vis) or "?",
      okS and tostring(w) or "?", okS and tostring(h) or "?", tostring(x), tostring(y))
  else
    parts[#parts + 1] = "no strip"
  end
  local cw, ch = m.ContentSize()
  parts[#parts + 1] = "content size " .. tostring(cw) .. " x " .. tostring(ch)
  return table.concat(parts, "; ")
end

function Hud.SetGlued(on)
  on = on == true
  if on == prefs.glued then return end
  Hud.Tick()                           -- keep where things are before rebuilding
  prefs.glued = on
  T.Save("hud", prefs)
  Hud.Build()
  T.Config.Sync()
end

-- Where each strip is now, by its key (Hud.GLUED_ID for the Toolbelt): { x, y }. Taken before another
-- character's settings are read (T.FollowCharacter), for Hud.Init to keep.
function Hud.Places()
  local out = {}
  for key, frame in pairs(frames) do
    local x, y = nil, nil
    if onScreen(frame) then x, y = Hud.Position(frame) end
    if x then out[key] = { x, y } end
  end
  return out
end

-- Builds every strip. `places` (Hud.Places, on a character switch): a strip this character never placed stays
-- where it was instead of going to its corner (owner, 2026-10-03), and that becomes its place.
function Hud.Init(places)
  local saved = T.ReadSaved("hud")
  prefs = { glued = false }
  if type(saved) == "table" then
    prefs.glued = saved.glued == true
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
  end
  for key, p in pairs(places or {}) do
    local m = modules[key]
    if key == Hud.GLUED_ID then
      if not prefs.x then prefs.x, prefs.y = p[1], p[2] end
    elseif m and m.GetSavedPosition() == nil then
      m.SavePosition(p[1], p[2])
    end
  end
  Hud.Build()
end

-- ---------------------------------------------------------------------------
-- Text strips: the XP and Today windows' "HUD strip" form
-- ---------------------------------------------------------------------------

-- A HUD module showing a title line and "label ..... value" rows on the theme's dark panel,
-- sized from the text size and line spacing settings (Toolbox.Window). Hovering it reports to
-- the owner's hover controller, so the detail pop-up works as it does over the window.
--
-- spec = {
--   key, FRAME_ID, HOME = { x, y },
--   titleId = "elapsed",                               -- the title line's element key
--   lines = { { id, label, indent = bool, tooltip }, ... },   -- elements <id>_label and <id>
--   isShown = function() -> bool,
--   hover = a Toolbox.Hover controller,
--   prefs = the owner's prefs table (the strip keeps hx / hy there), save = function(),
-- }
-- strip.el holds the labels by id (empty until built). Every label's side margins are zeroed:
-- the theme's defaults made combat rows wider than their panel in game.
Hud.STRIP_PAD = 5
Hud.STRIP_INDENT = 10

function Hud.TextStrip(spec)
  local strip = { FRAME_ID = spec.FRAME_ID, HOME = spec.HOME, el = {} }
  -- Built only while the HUD form is in use: HUD frames per add-on are limited (Hud.FrameCap).
  function strip.Wanted() return spec.prefs.hud == true end
  local styled = {}                   -- { element, function() -> style }, re-applied by ApplyText
  -- The strip was destroyed: drop its labels AND the restyle list (ApplyText after a switch to a window
  -- touched a destroyed label: "this Label was destroyed", 2026-09-29). The refresh skips an empty strip.
  function strip.Unbuilt() strip.el, styled = {}, {} end

  function strip.Metrics()
    local font = T.Window.GetFont()
    local labelW, valueW = math.ceil(font * 8), math.ceil(font * 6)
    return { labelW = labelW, valueW = valueW, w = labelW + valueW, line = T.Window.LineHeight(),
             pad = Hud.STRIP_PAD }
  end

  local function style(width, align, indent)
    return function()
      return T.Window.TextStyle{ width = width() - indent, marginLeft = indent, marginRight = 0,
        paddingLeft = 0, paddingRight = 0, textAlign = align }
    end
  end

  -- Labels go into `building` and only become strip.el once the whole strip is built: a build that
  -- raised halfway (the element-creation cap) left strip.el with only the title, and the XP window's
  -- refresh then failed every second until the game turned Toolbox off (2026-09-28).
  local building, buildingStyled = {}, {}
  local function label(key, text, class, fn)
    local e = UI.Label{ id = key, text = text, class = class, style = fn() }   -- ids as in the window form
    building[key] = e
    buildingStyled[#buildingStyled + 1] = { e, fn }
    return e
  end

  function strip.BuildContent()
    local m = strip.Metrics()
    strip.el, styled = {}, {}
    building, buildingStyled = {}, {}
    local function full() return strip.Metrics().w end
    local function names() return strip.Metrics().labelW end
    local function values() return strip.Metrics().valueW end
    local rows = { label(spec.titleId, "", "title", style(full, "left", 0)) }
    for _, line in ipairs(spec.lines) do
      local indent = line.indent and Hud.STRIP_INDENT or 0
      rows[#rows + 1] = UI.Row{ tooltip = line.tooltip or line.label,
        onHover = function(_, over) spec.hover:Report("t:hud_" .. line.id, over) end,
        children = {
          label(line.id .. "_label", line.label, "text", style(names, "left", indent)),
          label(line.id, "", "text", style(values, "right", 0)),
        } }
    end
    local column = UI.Column{ id = "strip", class = "inset",
      onHover = function(_, over) spec.hover:Report("t:hud", over) end,
      style = { paddingLeft = m.pad, paddingRight = m.pad, paddingTop = m.pad, paddingBottom = m.pad,
                marginLeft = 0, marginRight = 0, marginTop = 0, marginBottom = 0 },
      children = rows }
    strip.el, styled = building, buildingStyled
    return column
  end

  function strip.ContentSize()
    local m = strip.Metrics()
    return m.w + 2 * m.pad, (1 + #spec.lines) * m.line + 2 * m.pad
  end

  function strip.IsShown() return spec.isShown() end

  function strip.GetSavedPosition() return spec.prefs.hx, spec.prefs.hy end
  function strip.SavePosition(x, y)
    if x ~= spec.prefs.hx or y ~= spec.prefs.hy then
      spec.prefs.hx, spec.prefs.hy = x, y
      spec.save()
    end
  end

  -- Follows text size and line spacing changes.
  function strip.ApplyText()
    for _, pair in ipairs(styled) do pair[1]:SetStyle(pair[2]()) end
    Hud.Refresh()
  end

  local mover = Hud.MoverFor(spec.key, spec.HOME)
  strip.GetPosition, strip.MoveTo, strip.Nudge, strip.ResetPosition = mover.Get, mover.MoveTo, mover.Nudge,
    mover.Reset
  return strip
end
