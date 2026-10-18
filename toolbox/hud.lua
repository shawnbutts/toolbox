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
local sized = {}                      -- frame -> { key = "w,h", w, h }: the size last applied
local wasShown = {}                   -- frame -> shown at the last Refresh (fitShown)
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
  frames, contents, sized, wasShown = {}, {}, {}, {}
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
  T.Ran("HUD build")
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
  Hud.FitBuilt()                       -- a strip built after the window shrank (review 31)
  if retryWanted then
    retries = retries + 1
    T.RegisterPeriodic("toolbox_hud_retry", function() Hud.Build(true) end, Hud.RETRY_DELAY, false)
  else
    retries = 0
  end
end

-- True when the size changed.
local function setSize(frame, w, h)
  local key = w .. "," .. h
  if sized[frame] and sized[frame].key == key then return false end
  sized[frame] = { key = key, w = w, h = h }
  pcall(function() frame:SetSize(w, h) end)   -- refused past the HUD area limit: keep the old size
  return true
end

-- A strip just shown or resized is fitted inside the UI as last read (Hud.screen, from Hud.FitBuilt: no read here):
-- one built hidden had no size to fit by (review 31, the notification HUD's first notice).
local fitFrame = nil                   -- (defined with Hud.FitScreen)
local function fitShown(key, frame, resized)
  local was = wasShown[frame]
  wasShown[frame] = true
  if (resized or not was) and Hud.screen then fitFrame(key, frame, Hud.screen.w, Hud.screen.h) end
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
      fitShown(Hud.GLUED_ID, frame, setSize(frame, T.Window.GRIP + w + Hud.PAD, h + Hud.PAD))
      fitOverlay(Hud.GLUED_ID, w, h, T.Window.GRIP)
    else
      wasShown[frame] = nil
    end
  end
  for key, own in pairs(frames) do
    if modules[key] and contents[key] then
      local shown = modules[key].IsShown()
      T.SetVisible(own, shown)
      if shown then
        local cw, ch = modules[key].ContentSize()
        fitShown(key, own, setSize(own, T.Window.GRIP + cw + Hud.PAD, ch + Hud.PAD))
        fitOverlay(key, cw, ch, 0)
      else
        wasShown[own] = nil
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

-- The UI's size (API 31's uiWidth / uiHeight), or nil on an older client or a bad reading.
local function screenSize()
  if type(ShroudGetScreenInfo) ~= "function" then return nil end
  local ok, info = pcall(ShroudGetScreenInfo)
  if not ok then return nil end
  local sw, sh = T.Field(info, "uiWidth"), T.Field(info, "uiHeight")
  if type(sw) ~= "number" or type(sh) ~= "number" or sw <= 0 or sh <= 0 then return nil end
  return sw, sh
end

-- Moves one built strip inside sw x sh and saves the new place through its owner. True when it moved. A shown strip
-- is measured where it is, by the larger of its laid-out size and the size given it; a hidden one (combat-only,
-- switched on later, not laid out yet) by its saved place and the size last given it, since a hidden strip can report
-- the top-left corner (review 31). Fitted again as it first shows (fitShown).
fitFrame = function(key, frame, sw, sh)
  local m = modules[key]
  local x, y, w, h = nil, nil, 0, 0
  if sized[frame] then w, h = sized[frame].w, sized[frame].h end
  if onScreen(frame) then
    x, y = Hud.Position(frame)
    local ok, gw, gh = pcall(frame.GetSize, frame)   -- laid out, perhaps larger than asked (or not yet laid out)
    if ok and type(gw) == "number" and type(gh) == "number" then w, h = math.max(w, gw), math.max(h, gh) end
  else
    if m then x, y = m.GetSavedPosition() else x, y = prefs.x, prefs.y end
  end
  if type(x) ~= "number" or type(y) ~= "number" then return false end
  local nx = math.floor(math.max(0, math.min(x, sw - w)))
  local ny = math.floor(math.max(0, math.min(y, sh - h)))
  if nx == math.floor(x) and ny == math.floor(y) then return false end
  if not pcall(frame.SetPosition, frame, nx, ny) then return false end
  if m then
    m.SavePosition(nx, ny)
  elseif key == Hud.GLUED_ID then
    prefs.x, prefs.y = nx, ny
    T.Save("hud", prefs)
  end
  return true
end

-- Every built strip, shown or hidden, moved inside the UI. Returns how many moved.
function Hud.FitBuilt()
  local sw, sh = screenSize()
  if not sw then return 0 end
  Hud.screen = { w = sw, h = sh }
  local moved = 0
  for key, frame in pairs(frames) do
    if fitFrame(key, frame, sw, sh) then moved = moved + 1 end
  end
  return moved
end

-- The game window changed (API 31, ShroudOnScreenChanged; it also fires once after loading): a strip now past the
-- right or bottom edge (a smaller window or a bigger UI scale) is moved back inside, and its place saved. A strip
-- built later is fitted as it is built (Hud.Build). Returns how many moved.
function Hud.FitScreen()
  local moved = Hud.FitBuilt()
  if moved > 0 then
    T.Print("The game window changed: " .. moved .. (moved == 1 and " strip" or " strips")
      .. " moved back on screen.")
  end
  return moved
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
  local column = nil                  -- the panel, shaded (owner, 2026-10-15: `shade`, the module's saved prefs)
  function strip.Unbuilt() strip.el, styled, column = {}, {}, nil end

  function strip.GetShade() return T.ShadeOf(spec.prefs.shade) end
  -- 0..T.SHADE_MAX %, set in place; false for anything else. The module saves its prefs.
  function strip.SetShade(n)
    if type(n) ~= "number" or T.ShadeOf(n) ~= n then return false end
    spec.prefs.shade = n
    spec.save()
    if column then T.SetStyle(column, { backgroundColor = T.ShadeColor(n) }) end
    return true
  end

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
    local built = UI.Column{ id = "strip",
      onHover = function(_, over) spec.hover:Report("t:hud", over) end,
      style = { paddingLeft = m.pad, paddingRight = m.pad, paddingTop = m.pad, paddingBottom = m.pad,
                marginLeft = 0, marginRight = 0, marginTop = 0, marginBottom = 0, borderRadius = 3,
                backgroundColor = T.ShadeColor(strip.GetShade()) },
      children = rows }
    strip.el, styled, column = building, buildingStyled, built
    return built
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

-- ---------------------------------------------------------------------------
-- The location strip (Toolbox.Location; owner, 2026-10-08): where your character is, on a strip of its own: the
-- scene, the position in whole numbers (x, y, z, as /loc gives them) and, optionally, which way you face (the
-- HUD compass's heading, API 10). Read every LOC.TICK s while it shows; a label is set only when its text
-- changes. Hovering shows /loc's whole line (API 29; else the scene and the position to two decimals). Its width
-- follows the scene's name (the strip is refitted when the scene changes), so the numbers don't make it jump.
-- Fishable water (API 32, our request 25; setting `water`): a line with the scene's kinds ("Fishable water: salt,
-- fresh"; owner, 2026-10-15: for players who fish, what water to expect here), hidden when there is none (the strip
-- refits). Read at a scene change, again every LOC.WATER_EMPTY_EVERY s while empty for LOC.WATER_SETTLE s (the game may
-- still be reading the scene), then every LOC.WATER_EVERY s (a town's water decoration changes it, review 32). The
-- nearest water (ShroudGetNearestWaterType: up to 28 ms a call in game, 2026-10-14) isn't asked.
-- The shown map overlay (owner, 2026-10-18; setting `overlay`): a line naming the overlay this scene's map shows, with
-- arrows stepping through the scene's overlays (OV.Step); in a scene with none it says so, without the arrows (hidden,
-- the owner looked for it in a town with none and thought it missing).
-- Saved var "location": { show = bool (default false), facing = bool (default true), water = bool (default true),
-- overlay = bool (default true), autoNew = bool (the auto map on by default in adventure areas; default true), x, y }.
-- ---------------------------------------------------------------------------
local LOC = { FRAME_ID = "toolbox_location", HOME = { 600, 40 }, PAGE = "Location" }
Toolbox.Location = LOC
LOC.TICK = 0.5
LOC.POINTS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
LOC.CHAR_W = 0.6                      -- a character's width, as a share of the text size
LOC.MIN_CHARS = 19                    -- "-12345, 123, -12345"
-- s between reads of the scene's water kinds (5 before the owner's /toolbox perf found location near 9 hitches a
-- minute, 2026-10-14, with the nearest water asked too); a scene change reads them at once
LOC.WATER_EVERY = 30
LOC.WATER_EMPTY_EVERY = 5
LOC.WATER_SETTLE = 60
LOC.NO_OVERLAYS = "Map: no overlays here"   -- the overlay line in a scene with none
LOC.WATER_NAMES = { fresh = "Fresh water", fetid = "Fetid water", salt = "Salt water", lava = "Lava" }
local LOC_PERIODIC = "toolbox_location"
local locPrefs = { show = false, facing = true, water = true }
local locEl = {}                      -- column, scene, coords, facing (empty until built)
local locScene = ""                   -- the scene the width is fitted to
local locLast = {}                    -- the last rounded reading: x, y, z, heading
local locWater = { scene = nil, since = -math.huge, at = -math.huge, line = nil }   -- the line shown (nil: none)
local locOv = { key = nil, line = nil }   -- the shown overlay's line (nil: hidden) and what it was made from

function LOC.HasWater()
  return type(ShroudGetSceneWaterTypes) == "function"
end

-- A kind as players say it ("Salt water"; an unknown one as the game names it).
function LOC.WaterName(kind)
  return LOC.WATER_NAMES[kind] or (tostring(kind):gsub("^%l", string.upper) .. " water")
end

-- The scene's fishable water as the strip's line ("Fishable water: salt, fresh"), nil when none (or still reading).
function LOC.SceneWaterLine(list)
  local names = {}
  for _, k in ipairs(T.List(list)) do
    if type(k) == "string" and k ~= "" then names[#names + 1] = (LOC.WaterName(k):gsub(" water$", "")):lower() end
  end
  if #names == 0 then return nil end
  return "Fishable water: " .. table.concat(names, ", ")
end

local function locSave()
  T.Save("location", locPrefs)
  if T.Config then T.Config.Sync() end
end

-- The scene's name ("" while loading), the position (nil when unknown) and the compass heading (nil without).
function LOC.Read()
  local t0 = T.PerfT()
  local okS, scene = pcall(T.SceneName)
  if not okS or type(scene) ~= "string" then scene = "" end
  T.PerfAdd("location:scene name", t0)
  local x, y, z = ShroudPlayerX, ShroudPlayerY, ShroudPlayerZ
  if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or x ~= x or y ~= y or z ~= z then
    x, y, z = nil, nil, nil
  end
  local heading = nil
  if type(ShroudGetPlayerCompassHeading) == "function" then
    t0 = T.PerfT()
    local okH, h = pcall(ShroudGetPlayerCompassHeading)
    T.PerfAdd("location:compass", t0)
    if okH and type(h) == "number" and h == h then heading = h end
  end
  return scene, x, y, z, heading
end

-- "2014, 30, -3015"
function LOC.CoordsText(x, y, z)
  if not x then return "--" end
  return string.format("%d, %d, %d", math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5))
end

-- "Facing NE (45)", or "" without a heading.
function LOC.FacingText(deg)
  if type(deg) ~= "number" then return "" end
  local d = math.floor(deg + 0.5) % 360
  return "Facing " .. LOC.POINTS[math.floor((d + 22.5) / 45) % 8 + 1] .. " (" .. d .. ")"
end

-- The hover text: /loc's line (API 29), else the scene and the position.
function LOC.LocLine(scene, x, y, z)
  if type(ShroudGetLocationText) == "function" then
    local ok, line = pcall(ShroudGetLocationText)
    if ok and type(line) == "string" and line ~= "" then return line end
  end
  if not x then return scene end
  return scene .. " (" .. string.format("%.2f, %.2f, %.2f", x, y, z) .. ")"
end

local function locWidth()
  return math.ceil(math.max(LOC.MIN_CHARS, #locScene, #(locWater.line or ""), #(locOv.line or ""))
    * T.Window.GetFont() * LOC.CHAR_W)
end

local function locStyle()
  return T.Window.TextStyle{ width = locWidth(), marginLeft = 0, marginRight = 0, paddingLeft = 0,
    paddingRight = 0, whiteSpace = "nowrap" }
end

function LOC.Wanted() return locPrefs.show == true end
function LOC.IsShown() return locPrefs.show == true end
function LOC.Unbuilt() locEl, locLast = {}, {} end
local LOC_LABELS = { "scene", "coords", "facing", "water", "overlay" }

-- The pin beside the scene's name (owner, 2026-10-13): opens the Map overlays window. The menu's map-pin picture.
LOC.PIN_GAP = 4
local locTex = -1
local function pinSize() return T.Window.LineHeight() end
local function pinShown() return locPrefs.pin ~= false end

function LOC.ContentSize()
  local lines = 2 + (locPrefs.facing and 1 or 0) + (locWater.line and 1 or 0) + (locOv.line and 1 or 0)
  local right = pinShown() and (pinSize() + LOC.PIN_GAP) or 0
  if locOv.line and locOv.line ~= LOC.NO_OVERLAYS then               -- the overlay line's arrows
    right = math.max(right, 2 * (pinSize() + LOC.PIN_GAP))
  end
  return locWidth() + right + 2 * Hud.STRIP_PAD, lines * T.Window.LineHeight() + 2 * Hud.STRIP_PAD
end

-- An arrow of the overlay line: steps to the next overlay (dir 1) or the one before (-1).
local function stepButton(id, text, dir)
  local s = pinSize()
  return UI.Button{ id = id, text = text,
    tooltip = dir > 0 and "Show the next overlay on this scene's map" or "Show the overlay before",
    onClick = function() T.Overlays.Step(dir) end,
    style = { marginLeft = LOC.PIN_GAP, marginRight = 0, marginTop = 0, marginBottom = 0, width = s, height = s,
              minHeight = s, paddingLeft = 0, paddingRight = 0, fontSize = math.max(9, math.floor(s * 0.6)) } }
end

local function pinElement()
  local LN = T.Launcher
  local frame, count = 1, #LN.BUTTONS
  for i, b in ipairs(LN.BUTTONS) do
    if b.key == "location" then frame = i end
  end
  if locTex < 0 then
    local ok, tex = pcall(ShroudLoadTexture, LN.PATH)
    if ok and type(tex) == "number" and tex >= 0 then locTex = tex end
  end
  local s = pinSize()
  local tip = "Map overlays: mark where you stand, pick the overlay shown (/" .. T.commands[1] .. " overlay window)"
  local click = function() T.Overlays.ToggleWindow() end
  local style = { marginLeft = LOC.PIN_GAP, marginRight = 0, marginTop = 0, marginBottom = 0 }
  if locTex >= 0 then
    return UI.Image{ id = "loc_pin", width = s, height = s, texture = locTex, uv = { (frame - 1) / count, 0,
      1 / count, 1 }, tint = LN.COLOR, tooltip = tip, onClick = click, style = style }
  end
  style.width, style.height, style.minHeight, style.paddingLeft, style.paddingRight = s, s, s, 0, 0
  style.fontSize = math.max(9, math.floor(s * 0.6))
  return UI.Button{ id = "loc_pin", text = "+", tooltip = tip, onClick = click, style = style }
end

function LOC.BuildContent()
  locScene = LOC.Read()
  local pad = Hud.STRIP_PAD
  local built = {
    scene = UI.Label{ id = "loc_scene", text = locScene, class = "title", style = locStyle() },
    coords = UI.Label{ id = "loc_coords", text = "", class = "text", style = locStyle() },
    facing = UI.Label{ id = "loc_facing", text = "", class = "text", visible = locPrefs.facing == true,
      style = locStyle() },
    water = UI.Label{ id = "loc_water", text = "", class = "text", visible = false, style = locStyle() },
    overlay = UI.Label{ id = "loc_overlay", text = "", class = "text", style = locStyle(),
      tooltip = "The overlay shown on this scene's map. The arrows step through them: yours, then Gathering and"
        .. " its kinds, then Fights and its creatures, then none. The pin opens the Map overlays window" },
  }
  built.ovPrev, built.ovNext = stepButton("loc_ov_prev", "<", -1), stepButton("loc_ov_next", ">", 1)
  built.ovRow = UI.Row{ id = "loc_ov_row", visible = false,
    style = { alignItems = "center", marginLeft = 0, marginRight = 0 },
    children = { built.overlay, built.ovPrev, built.ovNext } }
  local top = built.scene
  if pinShown() then
    top = UI.Row{ style = { alignItems = "center", marginLeft = 0, marginRight = 0 },
      children = { built.scene, pinElement() } }
  end
  built.column = UI.Column{ id = "loc_strip", tooltip = "",
    style = { paddingLeft = pad, paddingRight = pad, paddingTop = pad, paddingBottom = pad,
              marginLeft = 0, marginRight = 0, marginTop = 0, marginBottom = 0, borderRadius = 3,
              backgroundColor = T.ShadeColor(T.ShadeOf(locPrefs.shade)) },
    children = { top, built.coords, built.facing, built.water, built.ovRow } }
  locEl, locLast = built, {}
  locWater.line, locWater.scene = nil, nil
  locOv.line, locOv.key = nil, nil
  return built.column
end

-- Every LOC.TICK s: the labels, set only when what they show changed.
function LOC.Update()
  if not (locPrefs.show and locEl.column) then return end
  local t0 = T.PerfT()
  local scene, x, y, z, heading = LOC.Read()
  T.PerfAdd("location:read", t0)
  t0 = T.PerfT()
  if scene ~= locScene then
    locScene = scene
    for _, key in ipairs(LOC_LABELS) do T.SetStyle(locEl[key], locStyle()) end
    Hud.Refresh()                      -- the strip's width follows the name
    locLast = {}
  end
  LOC.UpdateWater(scene)
  LOC.UpdateOverlay()
  T.PerfAdd("location:water", t0)
  t0 = T.PerfT()
  T.SetText(locEl.scene, scene ~= "" and scene or "--")
  local rx, ry, rz = nil, nil, nil
  if x then rx, ry, rz = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5) end
  if rx ~= locLast.x or ry ~= locLast.y or rz ~= locLast.z or locLast.x == nil then
    locLast.x, locLast.y, locLast.z = rx, ry, rz
    T.SetText(locEl.coords, LOC.CoordsText(x, y, z))
  end
  -- The hover has /loc's decimals: it follows any move, not just a whole unit (review 21).
  if x ~= locLast.px or y ~= locLast.py or z ~= locLast.pz or locLast.px == nil then
    locLast.px, locLast.py, locLast.pz = x, y, z
    T.SetTooltip(locEl.column, LOC.LocLine(scene, x, y, z) .. "\nWhere you are: the scene and your position (x,"
      .. " height, z). Type /loc for a line to paste in chat.")
  end
  local rh = heading and (math.floor(heading + 0.5) % 360) or nil
  if locPrefs.facing and (rh ~= locLast.h or locLast.hSet == nil) then
    locLast.h, locLast.hSet = rh, true
    T.SetText(locEl.facing, LOC.FacingText(heading))
  end
  T.PerfAdd("location:show", t0)
end

-- The water line: the scene's kinds (API 32, with `water` on). The strip refits when the line comes, goes or changes.
function LOC.UpdateWater(scene)
  local line = locWater.line
  if not (LOC.HasWater() and locPrefs.water ~= false) then
    line = nil
  else
    local now = T.Now()
    if scene ~= locWater.scene then locWater.scene, locWater.since, locWater.at = scene, now, -math.huge end
    local every = (line == nil and now - locWater.since < LOC.WATER_SETTLE) and LOC.WATER_EMPTY_EVERY or LOC.WATER_EVERY
    if now - locWater.at >= every then
      locWater.at = now
      local ok, list = pcall(ShroudGetSceneWaterTypes)
      line = ok and LOC.SceneWaterLine(list) or nil
    end
  end
  if line == locWater.line then return false end
  local resized = line == nil or locWater.line == nil or #line ~= #locWater.line
  locWater.line = line
  if line then T.SetText(locEl.water, line) end
  T.SetVisible(locEl.water, line ~= nil)
  if resized then
    for _, key in ipairs(LOC_LABELS) do T.SetStyle(locEl[key], locStyle()) end
    Hud.Refresh()                      -- the strip's size follows the line
  end
  return true
end

-- The overlay line's text: "Map: Iron Ore (4 places)", "Map: none (3 overlays)" or "Map: no overlays here".
function LOC.OverlayLine()
  local OV = T.Overlays
  local n = #OV.List()
  if n == 0 then return LOC.NO_OVERLAYS end
  local ov = OV.Shown()
  if not ov then return "Map: none (" .. n .. " overlay" .. (n == 1 and "" or "s") .. ")" end
  local k = #OV.Places(ov)
  return "Map: " .. ov.name .. " (" .. k .. " place" .. (k == 1 and "" or "s") .. ")"
end

-- The overlay line, made again only when the overlays, the scene or the character changed.
function LOC.UpdateOverlay()
  local line = nil
  if locPrefs.overlay ~= false then
    local okRaw, raw = pcall(T.SceneRaw)
    local key = T.Overlays.version .. ">" .. tostring(okRaw and raw) .. ">" .. tostring(T.CharacterName())
    if key == locOv.key then return false end
    locOv.key = key
    line = LOC.OverlayLine()
  end
  if line == locOv.line then return false end
  local resized = line == nil or locOv.line == nil or #line ~= #locOv.line
  locOv.line = line
  if line then T.SetText(locEl.overlay, line) end
  T.SetVisible(locEl.ovRow, line ~= nil)
  T.SetVisible(locEl.ovPrev, line ~= LOC.NO_OVERLAYS)
  T.SetVisible(locEl.ovNext, line ~= LOC.NO_OVERLAYS)
  if resized then
    for _, key in ipairs(LOC_LABELS) do T.SetStyle(locEl[key], locStyle()) end
    Hud.Refresh()
  end
  return true
end

-- The background shade (0..T.SHADE_MAX %; owner, 2026-10-15), set in place.
function LOC.GetShade() return T.ShadeOf(locPrefs.shade) end
function LOC.SetShade(n)
  if type(n) ~= "number" or T.ShadeOf(n) ~= n then return false end
  locPrefs.shade = n
  locSave()
  if locEl.column then T.SetStyle(locEl.column, { backgroundColor = T.ShadeColor(n) }) end
  T.Config.Sync()
  return true
end

function LOC.GetWater() return locPrefs.water ~= false end
function LOC.SetWater(on)
  locPrefs.water = on == true
  locWater.at = -math.huge             -- read again at once
  locSave()
  if locEl.column then LOC.Update() end
end

-- The auto map on by default in adventure areas, off in towns (Toolbox.Overlays.AutoByDefault); a scene's own
-- switch wins.
function LOC.GetAutoNew() return locPrefs.autoNew ~= false end
function LOC.SetAutoNew(on)
  locPrefs.autoNew = on == true
  locSave()
  if Toolbox.Overlays then Toolbox.Overlays.Changed() end
end

function LOC.GetOverlay() return locPrefs.overlay ~= false end
function LOC.SetOverlay(on)
  locPrefs.overlay = on == true
  locOv.key = nil                      -- made again at once
  locSave()
  if locEl.column then LOC.Update() end
end

function LOC.GetShow() return locPrefs.show == true end
function LOC.SetShow(on)
  locPrefs.show = on == true
  locSave()
  Hud.Build(true)                      -- its frame exists only while it is in use (HUD frames are limited)
  Hud.Refresh()
  LOC.Update()
end

function LOC.GetFacing() return locPrefs.facing ~= false end
function LOC.SetFacing(on)
  locPrefs.facing = on == true
  locSave()
  if locEl.facing then
    T.SetVisible(locEl.facing, locPrefs.facing)
    locLast.hSet = nil
    Hud.Refresh()
    LOC.Update()
  end
end

-- Your last death on the map (Toolbox.Overlays draws it).
function LOC.GetDeath() return locPrefs.death ~= false end
function LOC.SetDeath(on)
  locPrefs.death = on == true
  locSave()
  if Toolbox.Overlays then Toolbox.Overlays.Changed() end
end

-- The pin opening the Map overlays window (a rebuild: an element more or less).
function LOC.GetPin() return locPrefs.pin ~= false end
function LOC.SetPin(on)
  locPrefs.pin = on == true
  locSave()
  if locEl.column then Hud.Rebuild("location") end
end

-- Follows the text size and line spacing settings (Toolbox.Window.ApplyText).
function LOC.ApplyText()
  if not locEl.column then return end
  for _, key in ipairs(LOC_LABELS) do T.SetStyle(locEl[key], locStyle()) end
  Hud.Refresh()
end

function LOC.GetSavedPosition() return locPrefs.x, locPrefs.y end
function LOC.SavePosition(x, y)
  if x ~= locPrefs.x or y ~= locPrefs.y then
    locPrefs.x, locPrefs.y = x, y
    T.Save("location", locPrefs)
  end
end

local locMover = Hud.MoverFor("location", LOC.HOME)
LOC.GetPosition, LOC.MoveTo, LOC.Nudge, LOC.ResetPosition = locMover.Get, locMover.MoveTo, locMover.Nudge,
  locMover.Reset

-- Re-runnable (another character's settings): before Toolbox.Hud.Init builds the strips.
function LOC.Init()
  local saved = T.ReadSaved("location")
  locPrefs = { show = false, facing = true, water = true, pin = true, death = true, overlay = true, autoNew = true }
  if type(saved) == "table" then
    locPrefs.death = saved.death ~= false
    locPrefs.show = saved.show == true
    locPrefs.facing = saved.facing ~= false
    locPrefs.water = saved.water ~= false
    if type(saved.shade) == "number" then locPrefs.shade = T.ShadeOf(saved.shade) end
    locPrefs.pin = saved.pin ~= false
    locPrefs.overlay = saved.overlay ~= false
    locPrefs.autoNew = saved.autoNew ~= false
    if type(saved.x) == "number" and type(saved.y) == "number" then locPrefs.x, locPrefs.y = saved.x, saved.y end
  end
  locEl, locLast = {}, {}
  Hud.Register("location", LOC)
  T.RegisterPeriodic(LOC_PERIODIC, LOC.Update, LOC.TICK, true)
end

-- The strip goes before the target (built last); a reset clears its settings.
table.insert(Hud.ORDER, #Hud.ORDER, "location")
Hud.NAMES.location = "location"
T.Backup.KEYS[#T.Backup.KEYS + 1] = "location"

-- /toolbox location
T.AddCommand("location", "the location strip: your scene, position, facing and its fishable water (on|off;"
  .. " facing on|off; water on|off; pin on|off: its Map overlays button; overlay on|off: the shown map overlay's"
  .. " line; move [x y])",
  function(rest)
    local word, args = T.ParseArgs(rest)
    word = word:lower()
    if word == "" then
      LOC.SetShow(not locPrefs.show)
    elseif word == "on" or word == "off" then
      LOC.SetShow(word == "on")
    elseif word == "facing" and (args:lower() == "on" or args:lower() == "off") then
      LOC.SetFacing(args:lower() == "on")
    elseif word == "water" and (args:lower() == "on" or args:lower() == "off") then
      LOC.SetWater(args:lower() == "on")
    elseif word == "pin" and (args:lower() == "on" or args:lower() == "off") then
      LOC.SetPin(args:lower() == "on")
    elseif word == "overlay" and (args:lower() == "on" or args:lower() == "off") then
      LOC.SetOverlay(args:lower() == "on")
    elseif word == "move" then
      T.MoveCommand(LOC, "location", "The location strip", args)
      return
    else
      T.Print("Use /" .. T.commands[1] .. " location [on|off], facing on|off, water on|off, pin on|off, overlay"
        .. " on|off or move [x y].")
      return
    end
    T.Print("Location strip: " .. (locPrefs.show and "on" or "off") .. "; facing "
      .. (LOC.GetFacing() and "shown" or "hidden") .. ".")
  end)

-- ---------------------------------------------------------------------------
-- Map overlays (Toolbox.Overlays, OV; owner, 2026-10-13): named sets of places the player marks ("Loot", "Gathering"),
-- each belonging to ONE scene (a place is only good on its own map): a scene's overlays are listed only there, it
-- shows ONE at a time (the game allows an add-on 50 markers a scene; with the Loot Tracker's run flags, at most DD's
-- 10, and your last death, an overlay's OV.SCENE_MAX fits beside them), and each scene remembers its own shown one. Per
-- character. The run flags stay their own toggle. The auto map and the last death fill themselves (below). Later (not
-- built): sharing an overlay as a text string.
-- Room (owner, 2026-10-13): the game keeps 256 KB a FILE (core.lua's T.FILE_MAX), so the overlays have OV.BUDGET of
-- the character file, all scenes together: a place is packed into a few characters of text (packPlaces: its id, name,
-- position to the metre, shape and color numbers), and a scene's places are read (unpacked) only when the player is
-- there. A change that wouldn't fit is refused before anything is saved, naming what was refused (owner: a failed mark
-- must say it was the mark); the window shows how full it is (OV.StorageUse).
-- Markers (API 30): OV.Sync (from T.Tick and after each change) acts only when the scene, the character, the
-- overlays (OV.version) or the shown one change: the shown overlay's places get a marker each, id
-- "ov<overlay id>-<place id>" (each overlay its own ids, so a switch moves none: a move within 10 s is refused),
-- ours no longer wanted ("ov" ids) come down, and one already up as wanted isn't set again (a refusal, "rate" after a
-- big switch, is retried after OV.RETRY s, and only what's missing is sent). Without markers, the places still list
-- and Beacon works.
-- Each place has its own look (owner, 2026-10-13: changing the shape for a new spot restyled the ones before):
-- an overlay's icon and color are what its next marks get; "Set look" restyles one place.
-- Saved vars (character; kept by a reset; not in the recovery copy), one key a scene (owner, 2026-10-18: a save
-- writes only the scenes that changed): "map_overlays" is the index, { v = 3, nextId, nextKey, ignore, death,
-- scenes = { [scene id] = n } }, and "map_scene:<n>" each scene's, { raw = scene id, scene = its name, shown = overlay
-- id or 0, auto, fights, list = { { id, name, icon, color (an OV.COLORS name; for its next marks), nextPlace, places
-- = packed text, auto } } }. v = 2 (every scene in "map_overlays", 1.8.0) and v = 1 (one list, places carrying their
-- scene; never released) are converted at the first read.
-- ---------------------------------------------------------------------------
local OV = {}
Toolbox.Overlays = OV
OV.KEY = "map_overlays"
OV.SCENE_KEY = "map_scene:"           -- and a number: one scene's overlays
OV.MAX = 10                           -- overlays a scene (owner: a short list to pick from), the auto map's apart
OV.SCENE_MAX = 39                     -- places an overlay (50 markers a scene, less 10 run flags and the last death)
OV.BUDGET = 150000                    -- the saved overlays' estimated size: their share of the character file
OV.WARN = 0.9                         -- past this share of OV.BUDGET a mark says how full it is
OV.NAME_MAX = 24
OV.NEAR = 15                          -- m: "mark remove" with no name takes the nearest place this close
OV.RETRY = 30
OV.ICONS = { "pin", "diamond", "circle", "square", "star", "flag" }
-- The game takes #rgb only (no theme token). Gold is the run flags'.
OV.COLORS = {
  { "Green", "#70c860" }, { "Blue", "#60a0f0" }, { "Purple", "#b878e8" }, { "Red", "#e86050" },
  { "Orange", "#f09840" }, { "Cyan", "#50d0d0" }, { "White", "#ffffff" }, { "Gold", "#e8c060" },
}
OV.FULL = "map storage is full"
OV.REFUSED = "the game refused to save it"
OV.version = 0
local ovData = { scenes = {}, nextId = 1, ignore = {} }
local ovFor = nil
local ovSize = 0                      -- the saved form's estimated size (at the last read or save): every key's
-- What each key holds on disk, as read or last written (plain, before T.ForSaving): ovSaved[raw] = { key = n, form,
-- size }, ovSaved.index = { form, size }. A write compares each scene's form with it and writes only those changed.
local ovSaved = { scenes = {} }
-- The auto map's marks not saved yet (owner, 2026-10-18: a save walks every scene's overlays, slow once many are
-- mapped, and a fight's kill mustn't pay for it): { bytes = their estimated room, since = T.Now() of the first,
-- items = { { ov, place } or { sc, made = ov, shownWas } } }, saved together by OV.SavePending.
local ovPending = nil
local ovWrite = nil                   -- (below)
local ovOld = nil                     -- an older form's saved value, until a write has converted it
-- holdUntil: the location strip's arrows wait OV.STEP_SETTLE s after the last click before the markers follow
local ovMarks = { raw = nil, who = nil, version = nil, retryAt = -math.huge, holdUntil = -math.huge }

function OV.HasMarkers() return T.DailyDetail.HasMarkers() end

local function knownColor(name)
  for _, c in ipairs(OV.COLORS) do
    if c[1] == name then return c[2] end
  end
  return nil
end
local function ovColor(name) return knownColor(name) or OV.COLORS[1][2] end

local function ovIcon(name)
  for _, i in ipairs(OV.ICONS) do
    if i == name then return i end
  end
  return OV.ICONS[1]
end

local function iconNumber(name)
  for i, v in ipairs(OV.ICONS) do
    if v == name then return i end
  end
  return 1
end

local function colorNumber(name)
  for i, c in ipairs(OV.COLORS) do
    if c[1] == name then return i end
  end
  return 1
end

local function ovNumber(v) return type(v) == "number" and v == v and math.abs(v) <= 100000 end

-- A name as typed, made plain and short (as setups' names), without the packed text's separators: nil when nothing
-- is left.
function OV.CleanName(text)
  if type(text) == "string" then text = text:gsub("[|;]", " ") end
  local name = T.Backup.CleanName(text)
  if name and #name > OV.NAME_MAX then name = T.Trim(name:sub(1, OV.NAME_MAX)) end
  return name
end

-- The scene you're in (its id), or nil while loading.
local function hereRaw()
  local ok, raw = pcall(T.SceneRaw)
  if ok and type(raw) == "string" and raw ~= "" then return raw end
  return nil
end

-- Places as saved: "id|name|x|y|z|shape|color;..." (whole metres; the shape and color by their place in OV.ICONS /
-- OV.COLORS).
local function packPlaces(places)
  local parts = {}
  for i, p in ipairs(places) do
    parts[i] = string.format("%d|%s|%d|%d|%d|%d|%d", math.floor(p.id), p.name, math.floor(p.x + 0.5),
      math.floor(p.y + 0.5), math.floor(p.z + 0.5), iconNumber(p.icon), colorNumber(p.color))
  end
  return table.concat(parts, ";")
end

local function unpackPlaces(text, ov, sc)
  local places, ids, names = {}, {}, {}
  for item in (type(text) == "string" and text or ""):gmatch("[^;]+") do
    local f = {}
    for field in (item .. "|"):gmatch("([^|]*)|") do f[#f + 1] = field end
    local id, name = tonumber(f[1]), OV.CleanName(f[2])
    local x, y, z = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if id and id >= 1 and not ids[math.floor(id)] and name and not names[name:lower()] and ovNumber(x) and ovNumber(z)
        and #places < OV.SCENE_MAX then
      id = math.floor(id)
      ids[id], names[name:lower()] = true, true
      local icon, color = OV.ICONS[tonumber(f[6]) or 0], OV.COLORS[tonumber(f[7]) or 0]
      places[#places + 1] = { id = id, name = name, x = x, y = ovNumber(y) and y or 0, z = z,
                              icon = icon or ov.icon, color = color and color[1] or ov.color,
                              raw = ov.raw, scene = sc.scene }
      if id >= ov.nextPlace then ov.nextPlace = id + 1 end
    end
  end
  return places
end

-- An overlay's places, read from their packed text the first time they're needed.
function OV.Places(ov)
  if not ov then return {} end
  if not ov.places then ov.places = unpackPlaces(ov.packed, ov, ovData.scenes[ov.raw] or { scene = ov.raw }) end
  return ov.places
end

-- How many places an overlay has, without reading them.
local function placeCount(ov)
  if ov.places then return #ov.places end
  local n = 0
  for _ in (ov.packed or ""):gmatch("[^;]+") do n = n + 1 end
  return n
end

local function newOverlay(raw, id, name, icon, color, nextPlace)
  return { id = id, raw = raw, name = name, icon = ovIcon(icon), color = knownColor(color) and color or OV.COLORS[1][1],
           nextPlace = type(nextPlace) == "number" and math.max(1, math.floor(nextPlace)) or 1, packed = "" }
end

-- 1.8.0 development saves (v = 1: one list, each place with its scene): each overlay becomes one per scene it has
-- places in, shown where it was shown.
local function readV1(saved)
  local names = {}
  for _, o in ipairs(type(saved.list) == "table" and saved.list or {}) do
    local name = type(o) == "table" and type(o.id) == "number" and OV.CleanName(o.name)
    if name and not names[name:lower()] then
      names[name:lower()] = true
      local byScene, order = {}, {}
      for _, p in ipairs(type(o.places) == "table" and o.places or {}) do
        local pname = type(p) == "table" and OV.CleanName(p.name)
        if pname and type(p.raw) == "string" and p.raw ~= "" and type(p.id) == "number" and ovNumber(p.x)
            and ovNumber(p.z) then
          if not byScene[p.raw] then
            byScene[p.raw] = { scene = type(p.scene) == "string" and p.scene ~= "" and p.scene or p.raw, places = {} }
            order[#order + 1] = p.raw
          end
          local list = byScene[p.raw].places
          if #list < OV.SCENE_MAX then
            list[#list + 1] = { id = math.floor(p.id), name = pname, x = p.x, y = ovNumber(p.y) and p.y or 0, z = p.z,
                                icon = ovIcon(p.icon or o.icon), color = knownColor(p.color) and p.color or o.color }
          end
        end
      end
      for _, raw in ipairs(order) do
        local sc = ovData.scenes[raw]
        if not sc then
          sc = { scene = byScene[raw].scene, shown = 0, list = {} }
          ovData.scenes[raw] = sc
        end
        if #sc.list < OV.MAX then
          local ov = newOverlay(raw, ovData.nextId, name, o.icon, o.color, o.nextPlace)
          ovData.nextId = ovData.nextId + 1
          ov.packed = packPlaces(byScene[raw].places)
          sc.list[#sc.list + 1] = ov
          if o.id == saved.shown then sc.shown = ov.id end
        end
      end
    end
  end
end

-- One scene's saved overlays (`s`, a v = 2 scene entry or a v = 3 scene key) into ovData; `ids`: overlay ids taken.
-- Returns its scene, or nil (nothing worth keeping).
local function readScene(raw, s, ids)
  do
    do
      local sc = { scene = type(s.scene) == "string" and s.scene ~= "" and s.scene or raw, shown = 0, list = {} }
      if type(s.auto) == "boolean" then sc.auto = s.auto end        -- false: off in a scene on by default
      if type(s.fights) == "boolean" then sc.fights = s.fights end
      local names, own, auto = {}, 0, { g = 0, f = 0 }
      for _, o in ipairs(type(s.list) == "table" and s.list or {}) do
        local name = type(o) == "table" and type(o.id) == "number" and OV.CleanName(o.name)
        local key = name and type(o.auto) == "string" and o.auto ~= "" and o.auto or nil
        local group = key and (OV.AutoFight(key) and "f" or "g")
        local room = key and auto[group] < OV.AUTO_MAX or (not key and own < OV.MAX)
        if name and not ids[o.id] and not names[name:lower()] and room then
          ids[o.id], names[name:lower()] = true, true
          if key then auto[group] = auto[group] + 1 else own = own + 1 end
          local ov = newOverlay(raw, math.floor(o.id), name, o.icon, o.color, o.nextPlace)
          if key then ov.auto = key end
          ov.packed = type(o.places) == "string" and o.places or ""
          sc.list[#sc.list + 1] = ov
          if ov.id >= ovData.nextId then ovData.nextId = ov.id + 1 end
          if o.id == s.shown then sc.shown = ov.id end
        end
      end
      if #sc.list > 0 or sc.auto ~= nil or sc.fights ~= nil then
        ovData.scenes[raw] = sc
        return sc
      end
    end
  end
  return nil
end

-- What every version's index holds besides the scenes: the next ids, your last death, the ignore list.
local function readCommon(saved)
  if type(saved.nextId) == "number" and saved.nextId > ovData.nextId then ovData.nextId = math.floor(saved.nextId) end
  local d = saved.death
  if type(d) == "table" and type(d.raw) == "string" and d.raw ~= "" and type(d.x) == "number"
    and type(d.y) == "number" and type(d.z) == "number" then
    ovData.death = { raw = d.raw, scene = type(d.scene) == "string" and d.scene ~= "" and d.scene or d.raw,
                     x = d.x, y = d.y, z = d.z, at = type(d.at) == "string" and d.at or "",
                     date = type(d.date) == "string" and d.date or "" }
    if type(d.clock) == "number" then ovData.death.clock = d.clock end
    if d.away == true then ovData.death.away = true end
  end
  local seen = {}
  for _, part in ipairs(type(saved.ignore) == "table" and saved.ignore or {}) do
    local name = OV.CleanName(part)
    if name and not seen[name:lower()] and #ovData.ignore < OV.IGNORE_MAX then
      seen[name:lower()] = true
      ovData.ignore[#ovData.ignore + 1] = name
    end
  end
end

-- 1.8.0's form: every scene in the one key.
local function readV2(saved)
  local ids = {}
  for raw, s in pairs(type(saved.scenes) == "table" and saved.scenes or {}) do
    if type(raw) == "string" and raw ~= "" and type(s) == "table" then readScene(raw, s, ids) end
  end
  readCommon(saved)
end

local function sceneKey(n) return OV.SCENE_KEY .. n end

-- Today's: the index, and a key a scene. A scene whose key is gone or isn't its own is left out (the index drops it
-- at the next write).
local function readV3(saved)
  local ids = {}
  readCommon(saved)
  if type(saved.nextKey) == "number" and saved.nextKey > ovData.nextKey then
    ovData.nextKey = math.floor(saved.nextKey)
  end
  for raw, n in pairs(type(saved.scenes) == "table" and saved.scenes or {}) do
    if type(raw) == "string" and raw ~= "" and type(n) == "number" and n >= 1 and n == math.floor(n) then
      local s = T.ReadSaved(sceneKey(n))
      if type(s) == "table" and s.raw == raw then
        local sc = readScene(raw, s, ids)
        if sc then sc.key = n end
        -- (kept with nothing in it: deleted at the next write)
        ovSaved.scenes[raw] = { key = n, size = T.SavedSize(ShroudGetSavedVar(sceneKey(n))) }
      end
      if n >= ovData.nextKey then ovData.nextKey = n + 1 end
    end
  end
end

-- Whether scene `sc` is saved at all (overlays, or the auto map on there).
local function sceneKept(sc) return #sc.list > 0 or sc.auto ~= nil or sc.fights ~= nil end

-- A scene's saved form (each overlay changed since it was packed packed again, `dirty`; the others as they were:
-- packing every overlay read this session took a fair share of each save once a lot of scenes were mapped).
local function sceneForm(raw, sc)
  local list = {}
  for i, ov in ipairs(sc.list) do
    if ov.places and ov.dirty then
      ov.packed, ov.dirty = packPlaces(ov.places), nil
    end
    list[i] = { id = ov.id, name = ov.name, icon = ov.icon, color = ov.color, nextPlace = ov.nextPlace,
                places = ov.packed, auto = ov.auto }
  end
  return { raw = raw, scene = sc.scene, shown = sc.shown, list = list, auto = sc.auto, fights = sc.fights }
end

local OV_FIELDS = { "id", "name", "icon", "color", "nextPlace", "places", "auto" }
local SCENE_FIELDS = { "raw", "scene", "shown", "auto", "fights" }
local DEATH_FIELDS = { "raw", "scene", "x", "y", "z", "at", "date", "clock", "away" }

local function sameFields(a, b, fields)
  for _, f in ipairs(fields) do
    if a[f] ~= b[f] then return false end
  end
  return true
end

local function sameScene(a, b)
  if not (a and b and sameFields(a, b, SCENE_FIELDS) and #a.list == #b.list) then return false end
  for i, o in ipairs(a.list) do
    if not sameFields(o, b.list[i], OV_FIELDS) then return false end
  end
  return true
end

-- The index's saved form (the scenes kept, each with its key).
local function indexForm()
  local scenes, ignore, death = {}, {}, nil
  for raw, sc in pairs(ovData.scenes) do
    if sceneKept(sc) then scenes[raw] = sc.key end
  end
  for i, part in ipairs(ovData.ignore) do ignore[i] = part end
  if ovData.death then
    death = {}
    for _, f in ipairs(DEATH_FIELDS) do death[f] = ovData.death[f] end
  end
  return { v = 3, nextId = ovData.nextId, nextKey = ovData.nextKey, scenes = scenes, ignore = ignore, death = death }
end

local function sameIndex(a, b)
  if not (a and b and a.nextId == b.nextId and a.nextKey == b.nextKey and #a.ignore == #b.ignore) then return false end
  for i, part in ipairs(a.ignore) do
    if part ~= b.ignore[i] then return false end
  end
  if (a.death == nil) ~= (b.death == nil) or (a.death and not sameFields(a.death, b.death, DEATH_FIELDS)) then
    return false
  end
  for raw, n in pairs(a.scenes) do
    if b.scenes[raw] ~= n then return false end
  end
  for raw in pairs(b.scenes) do
    if a.scenes[raw] == nil then return false end
  end
  return true
end

-- This character's overlays (read once per character; re-runnable). A scene's places are read when needed.
function OV.Init()
  ovFor = T.CharacterName()
  ovData = { scenes = {}, nextId = 1, nextKey = 1, ignore = {} }
  ovPending, ovSaved, ovOld = nil, { scenes = {} }, nil
  ovMarks.holdUntil = -math.huge
  local saved = T.ReadSaved(OV.KEY)
  local old = type(saved) == "table" and (saved.v == 2 or saved.v == 1)
  if type(saved) == "table" and saved.v == 3 then
    readV3(saved)
    ovSaved.index = { size = T.SavedSize(ShroudGetSavedVar(OV.KEY)) }   -- as saved: its text escaped (review 37)
    -- the forms to compare with, as read (a scene or an index dropped or cut on the way in differs: written again)
    for raw, sc in pairs(ovData.scenes) do
      if ovSaved.scenes[raw] then ovSaved.scenes[raw].form = sceneForm(raw, sc) end
    end
    local form = indexForm()
    local same = true
    for raw, n in pairs(type(saved.scenes) == "table" and saved.scenes or {}) do
      if form.scenes[raw] ~= n then same = false end
    end
    if same then ovSaved.index.form = form end
  elseif type(saved) == "table" and saved.v == 2 then
    readV2(saved)
  elseif type(saved) == "table" and saved.v == 1 then
    readV1(saved)
  end
  ovSize = 0
  for _, e in pairs(ovSaved.scenes) do ovSize = ovSize + e.size end
  ovSize = ovSize + (ovSaved.index and ovSaved.index.size or (old and T.SavedSize(ShroudGetSavedVar(OV.KEY)) or 0))
  if old then
    -- into today's form now: every scene written, then the index over the old key (refused: the old key stays,
    -- read the same way next time)
    ovSaved.index = { size = ovSize }
    ovOld = ShroudGetSavedVar(OV.KEY)
    ovWrite()
  end
  OV.version = OV.version + 1
  ovMarks.retryAt = -math.huge
end

-- What a change can touch, kept by value with the tables it belongs to: a refused save puts it all back (review
-- 34: a refused Create stayed in the list, and the next save that worked wrote it).
local function ovSnapshot()
  local scenes = {}
  for raw, sc in pairs(ovData.scenes) do
    local list = {}
    for i, ov in ipairs(sc.list) do
      local places = nil
      if ov.places then
        places = {}
        for k, p in ipairs(ov.places) do places[k] = { p = p, icon = p.icon, color = p.color } end
      end
      list[i] = { ov = ov, name = ov.name, icon = ov.icon, color = ov.color, nextPlace = ov.nextPlace, places = places }
    end
    scenes[raw] = { sc = sc, shown = sc.shown, auto = sc.auto, fights = sc.fights, list = list }
  end
  local ignore = {}
  for i, part in ipairs(ovData.ignore) do ignore[i] = part end
  return { nextId = ovData.nextId, scenes = scenes, ignore = ignore, death = ovData.death }
end

local function ovRestore(snap)
  local scenes = {}
  for raw, k in pairs(snap.scenes) do
    local list = {}
    for i, ko in ipairs(k.list) do
      local ov = ko.ov
      ov.name, ov.icon, ov.color, ov.nextPlace = ko.name, ko.icon, ko.color, ko.nextPlace
      if ko.places then
        local places = {}
        for j, kp in ipairs(ko.places) do
          kp.p.icon, kp.p.color = kp.icon, kp.color
          places[j] = kp.p
        end
        ov.places, ov.dirty = places, true            -- its packed text may be the refused one
      end
      list[i] = ov
    end
    k.sc.shown, k.sc.list, k.sc.auto, k.sc.fights = k.shown, list, k.auto, k.fights
    scenes[raw] = k.sc
  end
  ovData.scenes, ovData.nextId, ovData.ignore, ovData.death = scenes, snap.nextId, snap.ignore, snap.death
end

-- Saves the overlays as changed since `snap` (ovSnapshot() taken before the change), or puts `snap` back when it
-- doesn't fit (OV.BUDGET; a change that frees room always fits) or the game refuses the write. Returns true, or
-- false and why.
-- Writes what changed (the auto map's unsaved marks with it): each scene changed into its own key, then the index
-- when it changed, then the keys of scenes gone are deleted. Refused part way, the scenes written are put back as
-- they were. An older form being converted (ovOld; past the budget too): the index goes over it FIRST, so the file
-- never holds both (it could pass 256 KB), and it's put back if a scene is refused. Returns true, or false and why.
local function refusedWhy(kind) return kind == "full" and "this character's save file is full" or OV.REFUSED end

ovWrite = function()
  local convert = ovOld                       -- (until a write converts it)
  local changed, gone, size = {}, {}, ovSize
  for raw, sc in pairs(ovData.scenes) do
    if sceneKept(sc) then
      local was = ovSaved.scenes[raw]
      local form = sceneForm(raw, sc)
      if not (was and was.key == sc.key and sameScene(was.form, form)) then
        if not sc.key then
          sc.key = ovData.nextKey
          ovData.nextKey = ovData.nextKey + 1
        end
        local enc = T.ForSaving(form)           -- measured as saved: escaped text can be longer (review 37)
        local e = { raw = raw, key = sc.key, form = form, enc = enc, size = T.SavedSize(enc), was = was }
        changed[#changed + 1] = e
        size = size - (was and was.size or 0) + e.size
      end
    end
  end
  for raw, was in pairs(ovSaved.scenes) do
    local sc = ovData.scenes[raw]
    if not (sc and sceneKept(sc) and sc.key == was.key) then
      gone[#gone + 1] = { raw = raw, was = was }
      size = size - was.size
    end
  end
  local index = indexForm()
  local indexEnc, indexSize = nil, ovSaved.index and ovSaved.index.size or 0
  if not (ovSaved.index and sameIndex(ovSaved.index.form, index)) then
    indexEnc = T.ForSaving(index)
    size = size - indexSize + T.SavedSize(indexEnc)
    indexSize = T.SavedSize(indexEnc)
  end
  if not convert and size > OV.BUDGET and size > ovSize then return false, OV.FULL end
  if convert then
    local ok, _, kind = T.SetSavedVar(OV.KEY, indexEnc or T.ForSaving(index))
    if not ok then return false, refusedWhy(kind) end
  end
  -- What's been done, undone newest first when a step is refused (the file as it was before: a converted one's new
  -- scene keys out BEFORE the old value goes back, review 60, or both could pass 256 KB). Each undo is checked.
  local done = {}
  local function undo()
    local undone = true
    for i = #done, 1, -1 do
      local d, ok = done[i], true
      local was = d.was
      if was and was.key == d.key and was.form then
        ok = T.SetSavedVar(sceneKey(d.key), T.ForSaving(was.form))
      elseif d.wrote then
        ok = T.DeleteSaved(sceneKey(d.key))
      end
      undone = undone and ok
    end
    if convert then undone = T.SetSavedVar(OV.KEY, convert) and undone end
    if not undone then
      T.Print("Map overlays: a save was refused and couldn't be fully undone; your overlays are fine for now, but"
        .. " make room (/" .. T.commands[1] .. " overlay scenes) and change one to save them again.")
    end
  end
  for _, e in ipairs(changed) do
    local ok, _, kind = T.SetSavedVar(sceneKey(e.key), e.enc)
    if not ok then
      undo()
      return false, refusedWhy(kind)
    end
    done[#done + 1] = { key = e.key, was = e.was, wrote = true }
  end
  -- scenes gone: their keys deleted before the index stops naming them (refused, nothing changes: review 61)
  for _, g in ipairs(gone) do
    local reused = false
    for _, e in ipairs(changed) do reused = reused or e.key == g.was.key end
    if not reused then
      if not T.DeleteSaved(sceneKey(g.was.key)) and ShroudGetSavedVar(sceneKey(g.was.key)) ~= nil then
        undo()
        return false, OV.REFUSED
      end
      done[#done + 1] = { key = g.was.key, was = g.was }
    end
  end
  if indexEnc and not convert then
    local ok, _, kind = T.SetSavedVar(OV.KEY, indexEnc)
    if not ok then
      undo()
      return false, refusedWhy(kind)
    end
  end
  if indexEnc or convert then ovSaved.index = { form = index, size = indexSize } end
  for _, g in ipairs(gone) do
    if ovSaved.scenes[g.raw] == g.was then ovSaved.scenes[g.raw] = nil end
  end
  for _, e in ipairs(changed) do ovSaved.scenes[e.raw] = { key = e.key, form = e.form, size = e.size } end
  ovSize, ovPending, ovOld = size, nil, nil
  T.unflushed = true                          -- to disk with the next periodic flush
  return true
end

local function ovSave(snap)
  OV.version = OV.version + 1
  local ok, why = ovWrite()
  if not ok then ovRestore(snap) end
  ovMarks.retryAt = -math.huge
  OV.Sync()
  T.Config.Sync()
  OV.SyncWindow()
  return ok, why
end

-- How full the overlays' room is: 0..1 (and more, for a file saved before the budget).
function OV.StorageUse() return (ovSize + (ovPending and ovPending.bytes or 0)) / OV.BUDGET end

local function ovFollow()
  if ovFor ~= T.CharacterName() then OV.Init() end
end

-- The overlays of the scene you're in (`raw`: another's), in the order made.
function OV.List(raw)
  ovFollow()
  local sc = ovData.scenes[raw or hereRaw() or ""]
  return sc and sc.list or {}
end

function OV.Find(name)
  local want = OV.CleanName(name)
  if not want then return nil end
  for _, ov in ipairs(OV.List()) do
    if ov.name:lower() == want:lower() then return ov end
  end
  return nil
end

-- The overlay shown on this scene's map, or nil.
function OV.Shown()
  ovFollow()
  local sc = ovData.scenes[hereRaw() or ""]
  if not sc then return nil end
  for _, ov in ipairs(sc.list) do
    if ov.id == sc.shown then return ov end
  end
  return nil
end

-- Shows `ov` on this scene's map (the only one), or none (nil).
function OV.Show(ov)
  local sc = ovData.scenes[ov and ov.raw or hereRaw() or ""]
  if not sc then return true end
  local snap = ovSnapshot()
  sc.shown = ov and ov.id or 0
  return ovSave(snap)
end

-- The order the location strip's arrows go through: your own overlays, then Gathering and its kinds, then Fights and
-- its creatures, each in the order made.
function OV.StepOrder(raw)
  local groups = { {}, {}, {}, {}, {} }
  for _, ov in ipairs(OV.List(raw)) do
    local g = 1
    if ov.auto == OV.AUTO_ALL then
      g = 2
    elseif ov.auto == OV.AUTO_FIGHTS then
      g = 4
    elseif ov.auto then
      g = OV.AutoFight(ov.auto) and 5 or 3
    end
    local list = groups[g]
    list[#list + 1] = ov
  end
  local order = {}
  for _, list in ipairs(groups) do
    for _, ov in ipairs(list) do order[#order + 1] = ov end
  end
  return order
end

-- Shows the next overlay of this scene (dir 1; -1 the one before), past the last none, then the first again. Clicked
-- through quickly, so not saved at once (with the auto map's next batch, OV.SavePending, or at a scene unload) and
-- the markers follow OV.STEP_SETTLE s after the last step (each switch moves up to 39 of them; the game allows 20 a
-- minute after a burst). Returns the overlay shown (nil: none), or false and why.
OV.STEP_SETTLE = 1.5
function OV.Step(dir)
  local order = OV.StepOrder()
  local sc = ovData.scenes[hereRaw() or ""]
  if not sc or #order == 0 then return false, "this scene has no overlays" end
  local at = #order + 1                       -- none shown
  for i, ov in ipairs(order) do
    if ov.id == sc.shown then at = i end
  end
  at = (at - 1 + (dir < 0 and -1 or 1)) % (#order + 1) + 1
  local ov = order[at]
  sc.shown = ov and ov.id or 0
  ovPending = ovPending or { bytes = 0, since = T.Now(), items = {} }
  ovMarks.holdUntil = T.Now() + OV.STEP_SETTLE
  OV.version = OV.version + 1
  T.Config.Sync()
  OV.SyncWindow()
  return ov
end

-- Adds overlay `name` to the scene at `here` and shows it, unsaved (Create's and an implicit first mark's).
local function addOverlay(here, name)
  local sc = ovData.scenes[here.raw]
  if not sc then
    sc = { scene = here.scene, shown = 0, list = {} }
    ovData.scenes[here.raw] = sc
  end
  local color = OV.COLORS[#sc.list % (#OV.COLORS - 1) + 1][1]
  local ov = newOverlay(here.raw, ovData.nextId, name, OV.ICONS[1], color, 1)
  ov.places, ov.dirty = {}, true
  ovData.nextId = ovData.nextId + 1
  sc.list[#sc.list + 1] = ov
  sc.shown = ov.id
  return ov
end

-- How many of this scene's overlays are the player's own (the auto map's have their own OV.AUTO_MAX).
function OV.OwnCount(raw)
  local n = 0
  for _, ov in ipairs(OV.List(raw)) do
    if not ov.auto then n = n + 1 end
  end
  return n
end

-- Makes overlay `text` in this scene and shows it. Returns it, or nil and why.
function OV.Create(text)
  local name = OV.CleanName(text)
  if not name then return nil, "give it a name" end
  local here = OV.Here()
  if not here then return nil, "the scene you're in can't be read right now" end
  if OV.Find(name) then return nil, "there's already an overlay called " .. name .. " here" end
  if OV.OwnCount() >= OV.MAX then return nil, "this scene has " .. OV.MAX .. " overlays: delete one first" end
  local snap = ovSnapshot()
  local ov = addOverlay(here, name)
  local ok, why = ovSave(snap)
  if not ok then return nil, why end
  return ov
end

function OV.Rename(ov, text)
  local name = OV.CleanName(text)
  if not name then return false, "give it a name" end
  for _, other in ipairs(OV.List(ov.raw)) do
    if other ~= ov and other.name:lower() == name:lower() then
      return false, "there's already an overlay called " .. name .. " here"
    end
  end
  local snap = ovSnapshot()
  ov.name = name
  local ok, why = ovSave(snap)
  if not ok then return false, why end
  return true, name
end

function OV.Delete(ov)
  local sc = ovData.scenes[ov.raw]
  if not sc then return true end
  local snap = ovSnapshot()
  local kept = {}
  for _, o in ipairs(sc.list) do
    if o ~= ov then kept[#kept + 1] = o end
  end
  sc.list = kept
  if sc.shown == ov.id then sc.shown = 0 end
  if #kept == 0 and sc.auto == nil and sc.fights == nil then ovData.scenes[ov.raw] = nil end
  return ovSave(snap)
end

-- The look of the overlay's next marks (places made before keep theirs).
function OV.SetIcon(ov, icon)
  local snap = ovSnapshot()
  ov.icon = ovIcon(icon)
  return ovSave(snap)
end

function OV.SetColor(ov, name)
  local snap = ovSnapshot()
  ov.color = knownColor(name) and name or OV.COLORS[1][1]
  return ovSave(snap)
end

-- Gives place `p` the overlay's look for next marks (its icon and color now).
function OV.SetPlaceLook(ov, p)
  OV.Places(ov)
  local snap = ovSnapshot()
  p.icon, p.color = ov.icon, ov.color
  ov.dirty = true
  return ovSave(snap)
end

-- Where you stand: { raw, scene, x, y, z }, or nil (loading, no character).
function OV.Here()
  local raw = hereRaw()
  local scene, x, y, z = LOC.Read()
  if not (raw and x) then return nil end
  return { raw = raw, scene = scene ~= "" and scene or raw, x = x, y = y, z = z }
end

function OV.FindPlace(ov, name)
  local want = OV.CleanName(name)
  if not (ov and want) then return nil end
  for _, p in ipairs(OV.Places(ov)) do
    if p.name:lower() == want:lower() then return p end
  end
  return nil
end

-- Marks where you stand in this scene's shown overlay (made, as "Places", when the scene has none at all), named
-- `text` or "Place <n>". Returns the place and the overlay, or nil, why and the name it would have had (a refusal
-- names the mark: owner, 2026-10-13).
function OV.Mark(text)
  local here = OV.Here()
  if not here then return nil, "your position can't be read right now", OV.CleanName(text) end
  local snap = ovSnapshot()                -- the overlay a first mark makes is saved with it, or not at all (review 38)
  local ov = OV.Shown()
  if not ov then
    if #OV.List() > 0 then
      return nil, "show one of this scene's overlays first (/" .. T.commands[1] .. " overlay <name>)",
        OV.CleanName(text)
    end
    ov = addOverlay(here, "Places")
  end
  local places = OV.Places(ov)
  local name = OV.CleanName(text)
  if not name then
    local n = ov.nextPlace
    while OV.FindPlace(ov, "Place " .. n) do n = n + 1 end
    name = "Place " .. n
  end
  if OV.FindPlace(ov, name) then                -- a name taken: "Wolf 2", "Wolf 3"... (owner, 2026-10-14)
    local n = 2
    while true do
      local suffix = " " .. n
      local numbered = T.Trim(name:sub(1, OV.NAME_MAX - #suffix)) .. suffix
      if not OV.FindPlace(ov, numbered) then
        name = numbered
        break
      end
      n = n + 1
    end
  end
  if #places >= OV.SCENE_MAX then
    return nil, ov.name .. " has " .. OV.SCENE_MAX .. " places (the map's limit in a scene): remove one first", name
  end
  local place = { id = ov.nextPlace, name = name, raw = here.raw, scene = here.scene, x = here.x, y = here.y,
                  z = here.z, icon = ov.icon, color = ov.color }
  ov.nextPlace = ov.nextPlace + 1
  places[#places + 1] = place
  ov.dirty = true
  local ok, why = ovSave(snap)
  if not ok then return nil, why, name end
  return place, ov
end

-- ---------------------------------------------------------------------------
-- Auto map (owner, 2026-10-14): resource nodes don't move (though not all are up at once), so while it's on in a
-- scene, each node you finish (ShroudOnGatherResults: its name) is marked where you stand: in an overlay of its
-- kind ("Iron Ore", made the first time, the next look in turn) and in the scene's "Gathering" overlay (every kind,
-- each in its kind's look, so the map shows them all), unless one of its kind is within OV.AUTO_NEAR m there (the
-- same node, gathered from another side). At most OV.AUTO_MAX automatic overlays a scene, Gathering among them,
-- apart from the player's own OV.MAX. One chat line a node; no room is told once a kind a session.
-- Fights (owner, 2026-10-18: "I can see the gather spots, but not where I fight"), their own switch a scene
-- (`sc.fights`): each creature you or your pet kill (a combat "death" line, D.IsKill) is marked where you stand (the
-- API gives no creature's position: a ranged kill marks you) in an overlay of its name (`auto` "!" .. name) and in the
-- scene's "Fights" (OV.AUTO_FIGHTS), unless one of its kind is within OV.FIGHT_NEAR m (creatures roam their camp).
-- Gathering and fights have OV.AUTO_MAX automatic overlays a scene each; the ignore list serves both.
-- ---------------------------------------------------------------------------
OV.AUTO_MAX = 10
OV.AUTO_NEAR = 6                      -- m: a node gathered again from its other side
OV.FIGHT_NEAR = 20                    -- m: the same camp
OV.KIND_MAX = OV.NAME_MAX - 4         -- a kind's name, room for " 12" after it
OV.GATHERING = "Gathering"
OV.FIGHTS = "Fights"
OV.AUTO_ALL = "*"                     -- the Gathering overlay's `auto`; a kind's overlay has its kind
OV.AUTO_FIGHTS = "!"                  -- the Fights overlay's; a creature's overlay has "!" and its name

-- Whether an automatic overlay's `auto` key is the fights' (Fights or a creature's).
function OV.AutoFight(key) return type(key) == "string" and key:sub(1, 1) == OV.AUTO_FIGHTS end

-- Whether `key` is an all-kinds overlay's (Gathering, Fights).
local function autoIsAll(key) return key == OV.AUTO_ALL or key == OV.AUTO_FIGHTS end

-- The kind an automatic overlay is of ("Iron Ore", "Elf Fighter"), or nil (Gathering, Fights, the player's own).
function OV.AutoKind(ov)
  local key = ov and ov.auto
  if not key or autoIsAll(key) then return nil end
  return OV.AutoFight(key) and key:sub(2) or key
end
OV.IGNORE_MAX = 40                    -- name parts the auto map skips (owner, 2026-10-14: dozens of kinds a scene)
local autoTold = {}                   -- "raw>kind" -> true: no room told this session

-- The kind a node's name names ("Iron Ore"), or nil.
function OV.NodeKind(node)
  if type(node) ~= "string" then return nil end
  local kind = OV.CleanName(node)
  if kind and #kind > OV.KIND_MAX then kind = T.Trim(kind:sub(1, OV.KIND_MAX)) end
  return kind
end

-- The kind an automatic place's name names ("Iron Ore 3" -> "Iron Ore"), or nil (one the player renamed).
function OV.PlaceKind(name)
  return type(name) == "string" and name:match("^(.*) %d+$") or nil
end

-- The ignore list's entry that `kind` matches, or nil: an entry is whole words of the kind ("Corpse" matches "Wolf
-- Corpse", "Ore" doesn't match "Forest Mushroom"), any case.
function OV.IgnoredBy(kind)
  ovFollow()
  if type(kind) ~= "string" then return nil end
  local words = " " .. kind:lower() .. " "
  for _, part in ipairs(ovData.ignore) do
    if words:find(" " .. part:lower() .. " ", 1, true) then return part end
  end
  return nil
end

-- The kinds the auto map skips, in every scene (this character's), in the order added.
function OV.IgnoreList()
  ovFollow()
  return ovData.ignore
end

-- Adds `text` (a kind or whole words of one) to the ignore list, and drops what the auto map made of it in the
-- scene you're in (its overlay, its places in Gathering; other scenes keep theirs). Returns true, overlays and
-- places dropped, or false and why.
function OV.Ignore(text)
  ovFollow()
  local part = OV.CleanName(text)
  if not part then return false, "name a kind, or a word of one" end
  for _, p in ipairs(ovData.ignore) do
    if p:lower() == part:lower() then return false, p .. " is already ignored" end
  end
  if #ovData.ignore >= OV.IGNORE_MAX then
    return false, "the list holds " .. OV.IGNORE_MAX .. ": take one off first"
  end
  local snap = ovSnapshot()
  ovData.ignore[#ovData.ignore + 1] = part
  local overlays, places = 0, 0
  local raw = hereRaw()
  local sc = raw and ovData.scenes[raw]
  if sc then
    local kept = {}
    for _, ov in ipairs(sc.list) do
      if OV.AutoKind(ov) and OV.IgnoredBy(OV.AutoKind(ov)) then
        overlays = overlays + 1
        if sc.shown == ov.id then sc.shown = 0 end
      else
        kept[#kept + 1] = ov
        if autoIsAll(ov.auto) then
          local left = {}
          for _, p in ipairs(OV.Places(ov)) do
            if OV.IgnoredBy(OV.PlaceKind(p.name)) then places = places + 1 else left[#left + 1] = p end
          end
          ov.places, ov.dirty = left, true
        end
      end
    end
    sc.list = kept
  end
  local ok, why = ovSave(snap)
  if not ok then return false, why end
  return true, overlays, places
end

-- Takes `text` off the ignore list. Returns true, or false and why.
function OV.Unignore(text)
  ovFollow()
  local part = OV.CleanName(text)
  local snap = ovSnapshot()
  local kept, found = {}, nil
  for _, p in ipairs(ovData.ignore) do
    if part and p:lower() == part:lower() then found = p else kept[#kept + 1] = p end
  end
  if not found then return false, "'" .. tostring(part or "") .. "' isn't on the list" end
  ovData.ignore = kept
  local ok, why = ovSave(snap)
  if not ok then return false, why end
  return true, found
end

-- Whether the auto map is on in the scene you're in (`raw`: another): for gathering, or for fights with `fights`.
function OV.AutoOn(raw, fights)
  ovFollow()
  local here = hereRaw()
  raw = raw or here
  local sc = ovData.scenes[raw or ""]
  local set = nil
  if sc then
    if fights then set = sc.fights else set = sc.auto end
  end
  if set ~= nil then return set end
  return raw ~= nil and raw == here and OV.AutoByDefault()
end

-- Whether the auto map is on in the scene you're in without being switched there (owner, 2026-10-18: crafting in a
-- town marked its trunks and stations): on in adventure areas, off in towns, while the setting is on.
function OV.AutoByDefault()
  return T.Location.GetAutoNew() and OV.SceneKind() == "adventure"
end

-- What the scene you're in is, for the auto map's default: "town" or "adventure" (nil while unknown, loading), and
-- for a town why ("a player-owned town"). ShroudGetSceneInfo (API 14) flags player towns, basements and the
-- overworld; the NPC towns have no flag, so their scene id's words (Novia_R4_City_Ardoris: OV.TOWN_WORDS). Kept for
-- the scene.
OV.TOWN_WORDS = { city = true, town = true, village = true }
local ovKind = { raw = nil, kind = nil, why = nil }
function OV.SceneKind()
  local raw = hereRaw()
  if not raw then return nil end
  if ovKind.raw == raw then return ovKind.kind, ovKind.why end
  local why = nil
  local ok, info = pcall(ShroudGetSceneInfo)
  if ok and type(info) == "table" then
    if T.Field(info, "loaded") == false then return nil end
    if T.Field(info, "isPot") == true then
      why = "a player-owned town"
    elseif T.Field(info, "isBasement") == true then
      why = "a basement"
    elseif T.Field(info, "isOverworld") == true then
      why = "the overworld map"
    end
  end
  if not why then
    for word in raw:lower():gmatch("%a+") do
      if OV.TOWN_WORDS[word] then why = "a town" end
    end
  end
  ovKind.raw, ovKind.kind, ovKind.why = raw, why and "town" or "adventure", why
  return ovKind.kind, why
end

-- The Map overlays window's line over the auto map's switches (owner, 2026-10-18: make it clear they're the scene's;
-- short, some town names are long): "Auto map (Crossroads):", and its hover: what the scene counts as.
function OV.AutoSceneLine()
  local okName, name = pcall(T.SceneName)
  name = okName and type(name) == "string" and name ~= "" and name or "this scene"
  local kind, why = OV.SceneKind()
  local about = "Switched on or off here, Gathering and Fights stay that way in this scene only."
  if not T.Location.GetAutoNew() then
    about = "Off unless you switch it on (Settings, Map & location: Auto map adventure areas is off). " .. about
  elseif kind == "town" then
    about = name .. " is " .. why .. ": off unless you switch it on. " .. about
  elseif kind == "adventure" then
    about = name .. " is an adventure area: on unless you switch it off. " .. about
  end
  return "Auto map (" .. name .. "):", about
end

-- "on in this scene (an adventure area: on unless you turn it off)": the state and where it comes from.
function OV.AutoText(fights)
  local sc = ovData.scenes[hereRaw() or ""]
  local set = nil
  if sc then
    if fights then set = sc.fights else set = sc.auto end
  end
  local on = OV.AutoOn(nil, fights)
  local text = (on and "on" or "off") .. " in this scene"
  if set ~= nil then return text .. " (you switched it " .. (on and "on" or "off") .. " here)" end
  local kind, why = OV.SceneKind()
  if not T.Location.GetAutoNew() then return text .. " (off unless you switch it on here)" end
  if kind == "town" then return text .. " (" .. why .. ": off unless you switch it on)" end
  if kind == "adventure" then return text .. " (an adventure area: on unless you switch it off)" end
  return text
end

-- Turns the auto map on or off in the scene you're in (its fights with `fights`). Returns true, or false and why.
function OV.SetAuto(on, fights)
  ovFollow()
  local here = OV.Here()
  if not here then return false, "the scene you're in can't be read right now" end
  local snap = ovSnapshot()
  local sc = ovData.scenes[here.raw]
  if not sc then
    sc = { scene = here.scene, shown = 0, list = {} }
    ovData.scenes[here.raw] = sc
  end
  if fights then sc.fights = on == true else sc.auto = on == true end   -- kept either way: the default may differ
  return ovSave(snap)
end

local function autoFind(sc, key)
  for _, ov in ipairs(sc.list) do
    if ov.auto == key then return ov end
  end
  return nil
end

-- Whether `ov` has a place within `near` m of `here` (of `kind` only, when given: "Iron Ore 3").
local function autoNear(ov, kind, here, near)
  local prefix = kind and (kind .. " ")
  for _, p in ipairs(OV.Places(ov)) do
    if not prefix or p.name:sub(1, #prefix) == prefix then
      local dx, dy, dz = p.x - here.x, p.y - here.y, p.z - here.z
      if dx * dx + dy * dy + dz * dz <= near * near then return true end
    end
  end
  return false
end

-- The scene's automatic overlay `key` (a kind, "!" and a creature's name, OV.AUTO_ALL or OV.AUTO_FIGHTS), made when
-- missing and there's room (OV.AUTO_MAX each for gathering and fights, one kept for Gathering / Fights); nil when
-- there isn't. Unsaved.
local function autoOverlay(sc, here, key)
  local found = autoFind(sc, key)
  if found then return found end
  local fight = OV.AutoFight(key)
  local n, kinds, looks = 0, 0, 0
  for _, ov in ipairs(sc.list) do
    if ov.auto and OV.AutoFight(ov.auto) == fight then
      n = n + 1
      if not autoIsAll(ov.auto) then kinds = kinds + 1 end
    end
    if ov.auto and not autoIsAll(ov.auto) then looks = looks + 1 end
  end
  if n >= OV.AUTO_MAX or (not autoIsAll(key) and kinds >= OV.AUTO_MAX - 1) then return nil end
  local base = key == OV.AUTO_ALL and OV.GATHERING or key == OV.AUTO_FIGHTS and OV.FIGHTS
    or (fight and key:sub(2)) or key
  local taken = {}
  for _, ov in ipairs(sc.list) do taken[ov.name:lower()] = true end
  local name, tries = base, 1                    -- one of the player's own has it: "(auto)", "(auto 2)"... (review 44)
  while taken[name:lower()] do
    local suffix = tries == 1 and " (auto)" or (" (auto " .. tries .. ")")
    name = T.Trim(base:sub(1, OV.NAME_MAX - #suffix)) .. suffix
    tries = tries + 1
  end
  local icon, color = OV.ICONS[1], OV.COLORS[1][1]
  if not autoIsAll(key) then                     -- each kind the next look in turn (Gold is the run flags')
    icon = OV.ICONS[looks % #OV.ICONS + 1]
    color = OV.COLORS[looks % (#OV.COLORS - 1) + 1][1]
  end
  local ov = newOverlay(here.raw, ovData.nextId, name, icon, color, 1)
  ov.places, ov.auto, ov.dirty = {}, key, true
  ovData.nextId = ovData.nextId + 1
  sc.list[#sc.list + 1] = ov
  if sc.shown == 0 and autoIsAll(key) then sc.shown = ov.id end
  return ov
end

-- Adds "<kind> <n>" where you stand to `ov` (the name `want` when free), in the given look; nil when it's full.
local function autoPlace(ov, kind, here, icon, color, want)
  local places = OV.Places(ov)
  if #places >= OV.SCENE_MAX then return nil end
  local name = want
  if not name or OV.FindPlace(ov, name) then
    local n = 1
    while OV.FindPlace(ov, kind .. " " .. n) do n = n + 1 end
    name = kind .. " " .. n
  end
  local p = { id = ov.nextPlace, name = name, raw = here.raw, scene = here.scene, x = here.x, y = here.y, z = here.z,
              icon = icon, color = color }
  ov.nextPlace = ov.nextPlace + 1
  places[#places + 1] = p
  ov.dirty = true
  return p
end

-- Takes the auto map's marks `items` (see ovPending) back out: their places, then the overlays made for them.
local function autoUndo(items)
  for _, it in ipairs(items) do
    if it.place and it.ov.places then
      for i = #it.ov.places, 1, -1 do
        if it.ov.places[i] == it.place then table.remove(it.ov.places, i) end
      end
      it.ov.dirty = true
    end
  end
  for _, it in ipairs(items) do
    if it.made then
      for i = #it.sc.list, 1, -1 do
        if it.sc.list[i] == it.made then table.remove(it.sc.list, i) end
      end
      if it.sc.shown == it.made.id then it.sc.shown = it.shownWas or 0 end
    end
  end
end

OV.SAVE_AFTER = 30                    -- s: the auto map's marks saved together this long after the first, out of combat

-- Saves the auto map's unsaved marks: `now`, or (from OV.Tick) OV.SAVE_AFTER s after the first and out of combat (a
-- save walks every scene's overlays). Refused (the file full, say), they're taken back out and chat says so.
function OV.SavePending(now)
  if not ovPending then return true end
  if not now and (T.Now() - ovPending.since < OV.SAVE_AFTER or T.BuffBar.InCombatWindow()) then return true end
  if ovFor ~= T.CharacterName() or T.NoCharacter() then return true end   -- not this character's file to write
  local pending = ovPending
  local ok, why = ovWrite()
  if not ok then
    ovPending = nil
    autoUndo(pending.items)
    local n = 0
    for _, it in ipairs(pending.items) do
      if it.place then n = n + 1 end
    end
    if n > 0 then
      T.Print("Auto map: " .. n .. " new mark" .. (n == 1 and "" or "s") .. " couldn't be saved (" .. why
        .. "), so they're taken off.")
    else
      T.Print("Map overlays: the overlay shown couldn't be saved (" .. why .. ").")
    end
  end
  OV.version = OV.version + 1
  ovMarks.retryAt = -math.huge
  OV.Sync()
  T.Config.Sync()
  OV.SyncWindow()
  return ok, why
end

-- Marks a node of `kind` where you stand (the auto map is on in `sc`), or with `fight` a creature killed. Returns
-- the place's name, or nil.
function OV.AutoMark(sc, here, kind, fight)
  local key, allKey = kind, OV.AUTO_ALL
  local near = fight and OV.FIGHT_NEAR or OV.AUTO_NEAR
  if fight then key, allKey = OV.AUTO_FIGHTS .. kind, OV.AUTO_FIGHTS end
  local mine, all = autoFind(sc, key), autoFind(sc, allKey)
  if (mine and autoNear(mine, nil, here, near)) or (all and autoNear(all, kind, here, near)) then return nil end
  local hadMine, hadAll, shownWas = mine, all, sc.shown
  all = all or autoOverlay(sc, here, allKey)
  mine = mine or autoOverlay(sc, here, key)
  local icon = mine and mine.icon or OV.ICONS[1]
  local color = mine and mine.color or OV.COLORS[1][1]
  local p = mine and autoPlace(mine, kind, here, icon, color)
  local q = all and autoPlace(all, kind, here, icon, color, p and p.name)
  local name = (p or q) and (p or q).name
  -- kept in memory, saved with the next batch (OV.SavePending); the room it takes estimated, not measured
  local items, bytes = {}, 0
  for _, made in ipairs({ (all and not hadAll) and all or false, (mine and not hadMine) and mine or false }) do
    if made then
      items[#items + 1] = { sc = sc, made = made, shownWas = shownWas }
      bytes = bytes + T.SavedSize(T.ForSaving({ id = made.id, name = made.name, icon = made.icon, color = made.color,
        nextPlace = made.nextPlace, places = "", auto = made.auto })) + 4
    end
  end
  for _, pair in ipairs({ { mine, p }, { all, q } }) do
    if pair[2] then
      items[#items + 1] = { ov = pair[1], place = pair[2] }
      bytes = bytes + #T.ForSaving(packPlaces({ pair[2] })) + 1
    end
  end
  if not name or ovSize + (ovPending and ovPending.bytes or 0) + bytes > OV.BUDGET then
    autoUndo(items)
    if name then
      T.Print("Auto map couldn't mark " .. kind .. ": " .. OV.FULL .. ".")
      return nil
    end
  else
    ovPending = ovPending or { bytes = 0, since = T.Now(), items = {} }
    ovPending.bytes = ovPending.bytes + bytes
    for _, it in ipairs(items) do ovPending.items[#ovPending.items + 1] = it end
    OV.version = OV.version + 1
    OV.Sync()
    OV.SyncWindow()
    T.Print("Auto map: " .. name .. " marked" .. ((p and q) and "" or (" in " .. (p and mine.name or all.name)
      .. " only")) .. ".")
  end
  if p and q then return name end
  local told = here.raw .. ">" .. kind
  if not autoTold[told] then
    autoTold[told] = true
    T.Print("Auto map: no room for " .. kind .. (mine == nil and (" in an overlay of its own (" .. OV.AUTO_MAX
      .. " automatic overlays a scene)") or "") .. ((mine ~= nil and p == nil) and (" in " .. mine.name .. " ("
      .. OV.SCENE_MAX .. " places)") or "") .. ((all ~= nil and q == nil) and (" in " .. all.name .. " ("
      .. OV.SCENE_MAX .. " places)") or "") .. ". /" .. T.commands[1] .. " overlay auto ignore " .. kind
      .. " stops marking it.")
  end
  return name
end

-- From ShroudOnGatherResults (core.lua): each node finished, while the auto map is on here.
-- The scene at `here`, made (unsaved: kept only once it holds an overlay) when the auto map is on there by default.
local function autoScene(here)
  if not here then return nil end
  local sc = ovData.scenes[here.raw]
  if not sc then
    sc = { scene = here.scene, shown = 0, list = {} }
    ovData.scenes[here.raw] = sc
  end
  return sc
end

function OV.OnGathered(results)
  if not OV.AutoOn() then return end
  local here = OV.Here()
  local sc = autoScene(here)
  if not sc then return end
  for _, r in ipairs(T.List(results)) do
    local kind = OV.NodeKind(T.Field(r, "node"))
    if kind and not OV.IgnoredBy(kind) then OV.AutoMark(sc, here, kind) end
  end
end

-- From ShroudOnCombatEvents (core.lua, plain tables): each creature you or your pet killed, while fights are auto
-- mapped here. Nothing is read unless a line is a kill.
function OV.OnCombat(events)
  if type(events) ~= "table" then return end
  local sc, here = nil, nil
  for _, e in ipairs(events) do
    if T.Daily.IsKill(e) then
      if not sc then
        if not OV.AutoOn(nil, true) then return end
        here = OV.Here()
        sc = autoScene(here)
        if not sc then return end
      end
      local kind = OV.NodeKind(e.target)
      if kind and not OV.IgnoredBy(kind) then OV.AutoMark(sc, here, kind, true) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Your last death (owner, 2026-10-14: "just show the last death"): where you stood when you died
-- (ShroudOnDeathChanged(true)), one for the character, its own marker in its scene beside any overlay (id
-- OV.DEATH_ID, an "ov" id so OV.Sync keeps it), while the location setting `death` is on; mark/compass from the
-- Map overlays window's Last death and /toolbox death.
-- ---------------------------------------------------------------------------
-- It clears itself (owner, 2026-10-14): back within OV.DEATH_NEAR m of it once you've been OV.DEATH_AWAY m off (or out
-- of the scene; `away`, saved), or OV.DEATH_KEEP s old (`clock`, T.Clock; without one, another day) while you're in
-- another scene. Its look: the game has six shapes, none body-like (a shape asked of the developers: picked up from
-- ShroudListMapMarkerIcons when it comes, OV.DEATH_SHAPES), so a diamond in a color no place can have.
OV.DEATH_ID = "ovdeath"
OV.DEATH_LABEL = "Last death"
OV.DEATH_SHAPES = { "skull", "grave", "tombstone", "corpse", "body", "death" }
OV.DEATH_ICON = "diamond"
OV.DEATH_HEX = "#ff30d0"              -- magenta: not one of OV.COLORS
OV.DEATH_NEAR = 8
OV.DEATH_AWAY = 30
OV.DEATH_KEEP = 3600
OV.DEATH_EVERY = 2
local deathShape = nil
local deathCheckAt = -math.huge

-- The death marker's shape: a death-like one the game offers, else OV.DEATH_ICON (read once).
function OV.DeathIcon()
  if deathShape then return deathShape end
  deathShape = OV.DEATH_ICON
  local ok, list = false, nil
  if type(ShroudListMapMarkerIcons) == "function" then ok, list = pcall(ShroudListMapMarkerIcons) end
  local offered = {}
  for _, name in ipairs(ok and T.List(list) or {}) do
    if type(name) == "string" then offered[name:lower()] = name end
  end
  for _, want in ipairs(OV.DEATH_SHAPES) do
    if offered[want] then
      deathShape = offered[want]
      break
    end
  end
  return deathShape
end

-- Your last death as a place ({ raw, scene, x, y, z, at, date, name }), or nil.
function OV.LastDeath()
  ovFollow()
  local d = ovData.death
  if d then d.name = "your last death" end
  return d
end

-- The marker's hover note: "You died here at 14:32 on 2026-10-14".
function OV.DeathNote(d)
  local when = (d.at ~= "" and (" at " .. d.at) or "") .. (d.date ~= "" and (" on " .. d.date) or "")
  return "You died here" .. when
end

-- Anything the markers and the window show changed outside a save (a setting).
function OV.Changed()
  OV.version = OV.version + 1
  ovMarks.retryAt = -math.huge
  OV.Sync()
  OV.SyncWindow()
end

-- From ShroudOnDeathChanged (core.lua): you died (true) where you stand. Returns the death, or nil.
function OV.OnDeath(isDead)
  if isDead ~= true then return nil end
  ovFollow()
  local here = OV.Here()
  if not here then return nil end
  local snap = ovSnapshot()
  local _, date = T.Today()
  ovData.death = { raw = here.raw, scene = here.scene, x = math.floor(here.x * 10 + 0.5) / 10,
                   y = math.floor(here.y * 10 + 0.5) / 10, z = math.floor(here.z * 10 + 0.5) / 10,
                   at = T.ClockText(), date = type(date) == "string" and date or "", clock = T.Clock() }
  local ok, why = ovSave(snap)
  if not ok then
    T.Print("Couldn't keep where you died: " .. why .. ".")
    return nil
  end
  if LOC.GetDeath() and OV.HasMarkers() then
    T.Print("Your death is marked on the map (" .. OV.DEATH_LABEL .. "): /" .. T.commands[1]
      .. " death compass points you back.")
  end
  return ovData.death
end

function OV.ClearDeath()
  ovFollow()
  if not ovData.death then return true end
  local snap = ovSnapshot()
  ovData.death = nil
  return ovSave(snap)
end

-- Whether a death has had its time (OV.DEATH_KEEP s; without a clock, from another day).
local function deathOld(d)
  local now = T.Clock()
  if type(d.clock) == "number" and now then return now - d.clock >= OV.DEATH_KEEP end
  local _, today = T.Today()
  return d.date ~= "" and type(today) == "string" and today ~= d.date
end

-- From T.Tick, every OV.DEATH_EVERY s: your last death clears itself (above). Returns why when it did, or nil.
function OV.DeathTick()
  if T.Now() - deathCheckAt < OV.DEATH_EVERY then return nil end
  deathCheckAt = T.Now()
  ovFollow()
  local d = ovData.death
  if not d then return nil end
  local here = OV.Here()
  if not here then return nil end
  local why = nil
  if here.raw ~= d.raw then
    if deathOld(d) then why = "old" end
  else
    local dx, dz = here.x - d.x, here.z - d.z
    local far = dx * dx + dz * dz
    if d.away and far <= OV.DEATH_NEAR * OV.DEATH_NEAR then why = "back" end
    if far < OV.DEATH_AWAY * OV.DEATH_AWAY and not d.away then return nil end
  end
  if not why then
    if d.away then return nil end
    local snap, moved = ovSnapshot(), {}
    for k, v in pairs(d) do moved[k] = v end
    moved.away = true
    ovData.death = moved
    ovSave(snap)
    return nil
  end
  if not OV.ClearDeath() then return nil end
  if why == "back" then
    T.Print("You're back where you died: " .. OV.DEATH_LABEL .. " is off the map.")
  else
    T.Print(OV.DEATH_LABEL .. " in " .. d.scene .. " is off the map (an hour old).")
  end
  return why
end

-- After a mark: a word on the room left, past OV.WARN (or "").
function OV.RoomNote()
  local use = OV.StorageUse()
  if use < OV.WARN then return "" end
  return string.format(" Map storage is %d%% full: remove places you don't need to make room.",
    math.floor(math.min(use, 1) * 100))
end

-- Why a mark failed, naming it (owner, 2026-10-13): "Couldn't mark Iron vein: map storage is full. ..."
function OV.MarkFailed(name, why)
  local text = "Couldn't mark " .. (name or "it") .. ": " .. tostring(why) .. "."
  if why == OV.FULL then
    text = text .. " Nothing was saved, and your other places are safe. Remove places, or a scene's overlays (/"
      .. T.commands[1] .. " overlay scenes), to make room."
  end
  return text
end

-- The shown overlay's place called `text`, or with no name the nearest within OV.NEAR m.
function OV.PlaceFor(text)
  local ov = OV.Shown()
  if not ov then return nil, nil, "no overlay is shown in this scene" end
  if T.Trim(text or "") ~= "" then
    local p = OV.FindPlace(ov, text)
    if not p then return nil, ov, ov.name .. " has no place called " .. T.Trim(text) end
    return p, ov
  end
  local here = OV.Here()
  local best, bestD = nil, OV.NEAR
  for _, p in ipairs(here and OV.Places(ov) or {}) do
    local d = math.sqrt((p.x - here.x) ^ 2 + (p.z - here.z) ^ 2)
    if d <= bestD then best, bestD = p, d end
  end
  if not best then return nil, ov, "no place of " .. ov.name .. " within " .. OV.NEAR .. " m" end
  return best, ov
end

function OV.RemovePlace(ov, place)
  local places = OV.Places(ov)
  local snap = ovSnapshot()
  local kept = {}
  for _, p in ipairs(places) do
    if p ~= place then kept[#kept + 1] = p end
  end
  ov.places, ov.dirty = kept, true
  return ovSave(snap)
end

-- The game's beacon at a place (a click: it replaces the player's own), in its scene only.
function OV.Beacon(place)
  if hereRaw() ~= place.raw then
    return false, place.name .. " is in " .. place.scene .. ". A beacon marks a spot in the scene you're in."
  end
  local ok, set = pcall(ShroudSetBeacon, place.x, place.y, place.z, place.name)
  if not (ok and set) then return false, "the game didn't set the beacon right now; try again in a moment" end
  return true, "Your compass points at " .. place.name .. " " .. T.DailyDetail.LocText(place)
    .. " (the game's beacon: /beacon clear removes it)."
end

-- An overlay's places by name.
function OV.SortedPlaces(ov)
  local list = {}
  for i, p in ipairs(OV.Places(ov)) do list[i] = p end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  return list
end

-- Every scene with overlays: { { raw, scene, overlays, places, size } }, the biggest first.
function OV.Scenes()
  ovFollow()
  local out = {}
  for raw, sc in pairs(ovData.scenes) do
    if sceneKept(sc) then                       -- (not an adventure area visited with nothing marked)
      local places, size = 0, 0
      for _, ov in ipairs(sc.list) do
        places = places + placeCount(ov)
        size = size + T.SavedSize(T.ForSaving((ov.places and ov.dirty) and packPlaces(ov.places) or ov.packed))
          + T.SavedSize(T.ForSaving(ov.name)) + 60
      end
      out[#out + 1] = { raw = raw, scene = sc.scene, overlays = #sc.list, places = places, size = size }
    end
  end
  table.sort(out, function(a, b)
    if a.size ~= b.size then return a.size > b.size end
    return a.scene < b.scene
  end)
  return out
end

-- Deletes every overlay of scene `raw` (its places with them). Returns true, or false and why.
function OV.Forget(raw)
  if not ovData.scenes[raw] then return false, "no overlays there" end
  local snap = ovSnapshot()
  ovData.scenes[raw] = nil
  return ovSave(snap)
end

function OV.MarkerId(ov, p) return "ov" .. ov.id .. "-" .. p.id end

function OV.Sync()
  if not OV.HasMarkers() then return end
  local raw = hereRaw()
  if not raw or T.Now() < ovMarks.holdUntil then return end
  local who = T.CharacterName()
  if raw == ovMarks.raw and who == ovMarks.who and OV.version == ovMarks.version then return end
  if T.Now() < ovMarks.retryAt then return end
  ovMarks.raw, ovMarks.who, ovMarks.version = raw, who, OV.version
  local ov = OV.Shown()
  local want, ids = {}, {}
  for _, p in ipairs(OV.Places(ov)) do
    if #want < OV.SCENE_MAX then                          -- (a file edited past it: the first ones)
      local id = OV.MarkerId(ov, p)
      ids[id] = true
      want[#want + 1] = { id = id, p = p, o = { label = p.name, icon = p.icon, color = ovColor(p.color),
                                                note = ov.name } }
    end
  end
  local death = ovData.death
  if death and death.raw == raw and LOC.GetDeath() then
    ids[OV.DEATH_ID] = true
    want[#want + 1] = { id = OV.DEATH_ID, p = death, o = { label = OV.DEATH_LABEL, icon = OV.DeathIcon(),
      color = OV.DEATH_HEX, note = OV.DeathNote(death) } }
  end
  local okList, have = pcall(ShroudGetMapMarkers)
  local up = {}
  for _, m in ipairs(okList and T.List(have) or {}) do
    local id = T.Field(m, "id")
    if type(id) == "string" and id:sub(1, 2) == "ov" then
      if not ids[id] then
        pcall(ShroudRemoveMapMarker, id)
      else
        up[id] = { x = T.Field(m, "x"), y = T.Field(m, "y"), z = T.Field(m, "z"), label = T.Field(m, "label"),
                   icon = T.Field(m, "icon"), color = T.Field(m, "color"), note = T.Field(m, "note") }
      end
    end
  end
  local refused = nil
  for _, w in ipairs(want) do
    local u = up[w.id]
    local same = u and u.x == w.p.x and u.y == w.p.y and u.z == w.p.z and u.label == w.o.label
      and u.icon == w.o.icon and u.note == w.o.note           -- the note is the overlay's name (review 35: a rename)
      and type(u.color) == "string" and u.color:lower() == w.o.color:lower()
    if not same then
      local ok, set, reason = pcall(ShroudSetMapMarker, w.id, w.p.x, w.p.y, w.p.z, w.o)
      if not (ok and set == true) then refused = ok and tostring(reason) or "error" end
    end
  end
  OV.markerFailed = refused
  if refused then
    ovMarks.raw, ovMarks.retryAt = nil, T.Now() + OV.RETRY
  else
    ovMarks.retryAt = -math.huge
  end
end

-- The map title (API 40; the owner's request #13082): one line in the full map's corner naming Toolbox's markers in
-- this scene ("Toolbox: Gathering, loot runs, last death"), set from T.ViewsTick after the markers, only when its text
-- changes (the game takes 10 changes, then 20 a minute: a refusal is retried after OV.RETRY s) or the scene does (a
-- title belongs to its scene); taken down when there's nothing. Nothing saved: the game drops it at a reload.
OV.TITLE_MAX = 60
local ovTitle = { raw = nil, text = nil, retryAt = -math.huge }

function OV.HasTitle() return type(ShroudSetMapTitle) == "function" end

-- The title for scene `raw`: the shown overlay (with places), the run flags and your last death, or nil.
function OV.TitleText(raw)
  local parts = {}
  local ov = OV.Shown()
  if ov and #OV.Places(ov) > 0 then parts[#parts + 1] = ov.name end
  if T.DailyDetail.MarkersIn(raw) > 0 then parts[#parts + 1] = "loot runs" end
  local death = ovData.death
  if death and death.raw == raw and LOC.GetDeath() then parts[#parts + 1] = "last death" end
  if #parts == 0 then return nil end
  local text = table.concat(parts, ", ")
  if #text > OV.TITLE_MAX then text = text:sub(1, OV.TITLE_MAX) end
  return text
end

function OV.SyncTitle()
  if not (OV.HasTitle() and OV.HasMarkers()) then return end
  local raw = hereRaw()
  if not raw or T.Now() < ovTitle.retryAt or T.Now() < ovMarks.holdUntil then return end
  local text = OV.TitleText(raw)
  if raw == ovTitle.raw and text == ovTitle.text then return end
  local ok, set, why = pcall(ShroudSetMapTitle, text)
  if ok and set == true then
    ovTitle.raw, ovTitle.text, ovTitle.retryAt = raw, text, -math.huge
  else
    OV.titleFailed = ok and tostring(why) or "error"
    ovTitle.raw, ovTitle.retryAt = nil, T.Now() + OV.RETRY
  end
end

-- Kept by a reset (the player's own places, like the runs). Not in the recovery copy (owner, 2026-10-13): the account
-- file's 256 KB is every character's copy together, and a full set of overlays is most of it.
T.Backup.OTHER_KEYS[#T.Backup.OTHER_KEYS + 1] = OV.KEY
-- each scene's key, as the index on disk lists them (the file measured whole before OV.Init reads it)
T.Backup.KEY_LISTS[#T.Backup.KEY_LISTS + 1] = function()
  local keys = {}
  local index = ShroudGetSavedVar(OV.KEY)
  if type(index) == "table" and index.v == 3 and type(index.scenes) == "table" then
    for _, n in pairs(index.scenes) do
      if type(n) == "number" then keys[#keys + 1] = OV.SCENE_KEY .. math.floor(n) end
    end
  end
  return keys
end

local function ovSummary(ov)
  local n = #OV.Places(ov)
  return ov.name .. " (" .. n .. " place" .. (n == 1 and "" or "s") .. ")"
end

-- "Map storage: 12% used" (the overlays' share of the character file).
function OV.StorageText()
  return string.format("Map storage: %d%% used", math.floor(math.min(OV.StorageUse(), 1) * 100 + 0.5))
end

OV.FORGET_CONFIRM = 10                -- s: "overlay forget <scene>" typed again within it deletes
local forgetArmed = nil               -- { raw, at }

-- A scene with overlays, by its name or id (`text`), from OV.Scenes().
local function findScene(text)
  local want = T.Trim(text or ""):lower()
  for _, s in ipairs(OV.Scenes()) do
    if s.scene:lower() == want or s.raw:lower() == want then return s end
  end
  return nil
end

-- /toolbox overlay
T.AddCommand("overlay", "map overlays, sets of places you mark in a scene, one shown at a time: <name> shows one;"
  .. " off; next, prev (step through them); new <name>; rename <old> = <new>; delete <name>; places; icon <shape>,"
  .. " color <name> (your next marks');"
  .. " window (the Map overlays window); auto [on|off] (mark the nodes you gather here); auto fights [on|off]"
  .. " (mark the creatures you kill here); auto ignore [kind],"
  .. " auto unignore <kind> (kinds it skips); scenes (every scene's, and the room they take);"
  .. " forget <scene> (alone: this scene's)",
  function(rest)
    local word, args = T.ParseArgs(rest)
    local c = "/" .. T.commands[1] .. " "
    if word == "" then
      local names = {}
      for _, ov in ipairs(OV.List()) do names[#names + 1] = ovSummary(ov) .. (ov == OV.Shown() and " shown" or "") end
      T.Print((#names > 0 and ("This scene's overlays: " .. table.concat(names, "; ") .. ".")
        or ("No overlays in this scene yet: " .. c .. "overlay new <name> makes one, " .. c
          .. "mark <name> marks where you stand.")) .. " " .. OV.StorageText() .. ".")
      return
    end
    local ov = OV.Shown()
    if word == "window" then
      OV.ToggleWindow()
    elseif word == "auto" then
      local sub, what = T.ParseArgs(args)
      if sub == "ignore" and what == "" then
        local list = OV.IgnoreList()
        T.Print(#list > 0 and ("The auto map skips: " .. table.concat(list, ", ") .. " (" .. c
          .. "overlay auto unignore <name> takes one off).")
          or ("The auto map skips nothing: " .. c .. "overlay auto ignore <kind or word> adds one (a word, such as"
            .. " Corpse, skips every kind with it)."))
        return
      elseif sub == "ignore" then
        local ok, overlays, places = OV.Ignore(what)
        if not ok then
          T.Print("Couldn't add it: " .. overlays .. ".")
          return
        end
        T.Print("The auto map skips " .. OV.CleanName(what) .. " now, in every scene." .. ((overlays + places > 0)
          and (" Here it took out " .. overlays .. " overlay" .. (overlays == 1 and "" or "s") .. " and " .. places
            .. " place" .. (places == 1 and "" or "s") .. " in " .. OV.GATHERING .. " and " .. OV.FIGHTS .. ".")
          or ""))
        return
      elseif sub == "unignore" then
        local ok, why = OV.Unignore(what)
        T.Print(ok and ("The auto map marks " .. why .. " again.") or ("Couldn't take it off: " .. why .. "."))
        return
      elseif sub == "fights" then
        local turn = what:lower()
        if turn ~= "on" and turn ~= "off" then
          T.Print("Auto map of fights is " .. OV.AutoText(true) .. ": " .. c
            .. "overlay auto fights on marks each creature you kill here, by name, and in " .. OV.FIGHTS .. ".")
          return
        end
        local ok, why = OV.SetAuto(turn == "on", true)
        T.Print(ok and ("Auto map of fights " .. turn .. " in this scene." .. (turn == "on" and (" Each creature you"
          .. " kill is marked where you stand, in an overlay of its name and in " .. OV.FIGHTS .. ".") or ""))
          or ("Couldn't change it: " .. why .. "."))
        return
      end
      local want = args:lower()
      if want ~= "on" and want ~= "off" then
        T.Print("Auto map is " .. OV.AutoText() .. ": " .. c .. "overlay auto on"
          .. " marks each resource node you gather here, by kind, and in " .. OV.GATHERING .. ".")
        return
      end
      local ok, why = OV.SetAuto(want == "on")
      T.Print(ok and ("Auto map " .. want .. " in this scene." .. (want == "on" and (" Each node you gather is"
        .. " marked in an overlay of its kind and in " .. OV.GATHERING .. ".") or ""))
        or ("Couldn't change it: " .. why .. "."))
    elseif word == "off" then
      local ok, why = OV.Show(nil)
      T.Print(ok and "No overlay shown." or ("Couldn't hide it: " .. why .. "."))
    elseif word == "next" or word == "prev" then
      local shown, why = OV.Step(word == "next" and 1 or -1)
      T.Print(shown == false and ("Nothing to show: " .. why .. ".")
        or (shown and ("Showing " .. shown.name .. ".") or "No overlay shown."))
    elseif word == "new" then
      local made, why = OV.Create(args)
      T.Print(made and ("Made " .. made.name .. ", shown now. " .. c .. "mark <name> marks where you stand.")
        or ("Couldn't make it: " .. why .. "."))
    elseif word == "rename" then
      local eq = args:find("=", 1, true)
      local target = eq and OV.Find(args:sub(1, eq - 1)) or nil
      if not target then
        T.Print("Use " .. c .. "overlay rename <old> = <new> (one of this scene's).")
        return
      end
      local ok, why = OV.Rename(target, args:sub(eq + 1))
      T.Print(ok and ("Renamed it " .. why .. ".") or ("Couldn't rename it: " .. tostring(why) .. "."))
    elseif word == "delete" then
      local target = OV.Find(args)
      if not target then
        T.Print("No overlay called '" .. args .. "' in this scene.")
        return
      end
      local n = #OV.Places(target)
      local ok, why = OV.Delete(target)
      T.Print(ok and ("Deleted " .. target.name .. " and its " .. n .. " places.")
        or ("Couldn't delete it: " .. why .. "."))
    elseif word == "places" then
      if not ov then
        T.Print("No overlay is shown in this scene.")
        return
      end
      T.Print(ovSummary(ov) .. ":")
      for _, p in ipairs(OV.SortedPlaces(ov)) do T.Print("  " .. p.name .. ": " .. T.DailyDetail.LocText(p)) end
    elseif word == "scenes" then
      local list = OV.Scenes()
      T.Print(OV.StorageText() .. (#list > 0 and (", in " .. #list .. " scene" .. (#list == 1 and "" or "s") .. ":")
        or ": no overlays yet."))
      for _, s in ipairs(list) do
        T.Print(string.format("  %s: %d overlay%s, %d place%s (%.1f KB)", s.scene, s.overlays,
          s.overlays == 1 and "" or "s", s.places, s.places == 1 and "" or "s", s.size / 1024))
      end
      if #list > 0 then T.Print("  " .. c .. "overlay forget <scene> deletes a scene's overlays.") end
    elseif word == "forget" then
      local s = findScene(args)
      if not s then
        T.Print("No overlays in a scene called '" .. T.Trim(args) .. "' (" .. c .. "overlay scenes lists them).")
        return
      end
      if not (forgetArmed and forgetArmed.raw == s.raw and T.Now() - forgetArmed.at <= OV.FORGET_CONFIRM) then
        forgetArmed = { raw = s.raw, at = T.Now() }
        T.Print("This deletes " .. s.scene .. "'s " .. s.overlays .. " overlay" .. (s.overlays == 1 and "" or "s")
          .. " and " .. s.places .. " place" .. (s.places == 1 and "" or "s") .. ". Type it again within "
          .. OV.FORGET_CONFIRM .. " s to go ahead.")
        return
      end
      forgetArmed = nil
      local ok, why = OV.Forget(s.raw)
      T.Print(ok and ("Deleted " .. s.scene .. "'s overlays. " .. OV.StorageText() .. ".")
        or ("Couldn't delete them: " .. why .. "."))
    elseif word == "icon" or word == "color" then
      if not ov then
        T.Print("Show one of this scene's overlays first.")
        return
      end
      local names = {}
      for i, v in ipairs(word == "icon" and OV.ICONS or OV.COLORS) do names[i] = word == "icon" and v or v[1] end
      local pick = nil
      for _, n in ipairs(names) do
        if n:lower() == args:lower() then pick = n end
      end
      if not pick then
        T.Print("Use " .. c .. "overlay " .. word .. " " .. table.concat(names, "|") .. ".")
        return
      end
      local ok, why = nil, nil
      if word == "icon" then ok, why = OV.SetIcon(ov, pick) else ok, why = OV.SetColor(ov, pick) end
      T.Print(ok and (ov.name .. ": your next marks' " .. word .. " " .. pick
        .. " (mark look [name] gives a place it).") or ("Couldn't change it: " .. why .. "."))
    else
      local target = OV.Find(word == "show" and args or rest)
      if not target then
        T.Print("No overlay called '" .. T.Trim(word == "show" and args or rest) .. "' in this scene. " .. c
          .. "overlay new <name> makes one.")
        return
      end
      local ok, why = OV.Show(target)
      T.Print(ok and ("Showing " .. ovSummary(target) .. " on your map.") or ("Couldn't show it: " .. why .. "."))
    end
  end)

-- /toolbox death
T.AddCommand("death", "your last death: where it was; death compass (point your compass back to it); death clear",
  function(rest)
    local word = T.ParseArgs(rest)
    local d = OV.LastDeath()
    if word == "clear" then
      local ok, why = OV.ClearDeath()
      T.Print(ok and "Your last death is cleared from the map." or ("Couldn't clear it: " .. why .. "."))
      return
    end
    if not d then
      T.Print("No death recorded for this character" .. (word == "compass" and "." or " (since 1.8.0)."))
      return
    end
    if word == "compass" then
      local _, said = OV.Beacon(d)
      T.Print(said)
      return
    end
    T.Print("Your last death: " .. d.scene .. " " .. T.DailyDetail.LocText(d) .. (d.at ~= "" and (" at " .. d.at)
      or "") .. (d.date ~= "" and (" on " .. d.date) or "") .. ". /" .. T.commands[1] .. " death compass points you"
      .. " back; death clear takes it off the map.")
  end)

-- /toolbox mark
T.AddCommand("mark", "mark where you stand in this scene's shown map overlay: mark [name]; mark remove [name] (no"
  .. " name: the nearest within " .. OV.NEAR .. " m); mark compass [name] (the game's beacon); mark look [name] (the"
  .. " overlay's shape and color now)",
  function(rest)
    local word, args = T.ParseArgs(rest)
    if word == "beacon" then word = "compass" end   -- its name before 1.8.0
    if word == "remove" or word == "compass" or word == "look" then
      local p, ov, why = OV.PlaceFor(args)
      if not p then
        T.Print("Couldn't find it: " .. why .. ".")
        return
      end
      if word == "remove" then
        local ok, refusal = OV.RemovePlace(ov, p)
        T.Print(ok and ("Removed " .. p.name .. " from " .. ov.name .. ".")
          or ("Couldn't remove it: " .. refusal .. "."))
      elseif word == "look" then
        local ok, refusal = OV.SetPlaceLook(ov, p)
        T.Print(ok and (p.name .. ": " .. p.icon .. ", " .. p.color .. ".")
          or ("Couldn't change it: " .. refusal .. "."))
      else
        local _, msg = OV.Beacon(p)
        T.Print(msg)
      end
      return
    end
    local p, ov, name = OV.Mark(rest)
    if not p then
      T.Print(OV.MarkFailed(name, ov))
      return
    end
    T.Print("Marked " .. p.name .. " in " .. ov.name .. ": " .. p.scene .. " " .. T.DailyDetail.LocText(p) .. "."
      .. (OV.HasMarkers() and "" or " (Your game client can't show it on the map yet; mark compass points you to it.)")
      .. OV.RoomNote())
  end)

-- The Marks window (owner, 2026-10-13: "i don't like having the whole settings page up while making marks"; then
-- every overlay control moved here): the overlay shown; New, Rename, Delete (a second click within OV.CONFIRM s);
-- the next marks' look; Mark here; the shown overlay's places (Compass, Set look, Remove); how full the map storage
-- is. Only this scene's overlays (an overlay belongs to its scene). It shares the 8th window with Docs and the
-- version window (T.TakeSharedWindow), built when opened; opened from the location strip's pin, /toolbox overlay
-- window, or the settings page's button.
local MW_ID = "toolbox_marks"
local mw, mwEl, mwPicks, mwPlaces = nil, {}, {}, {}
local mwKey = nil                     -- what the lists were filled from (OV.version and the scene)
local mwArmed = nil                   -- { at, id }: Delete clicked once
OV.CONFIRM = 5
OV.MW_NONE = "None (no overlay shown)"
OV.MW_NO_PLACES = "No places here yet"

local function mwMsg(text) T.SetText(mwEl.msg, text or "") end

local function mwDrop()
  if mw then pcall(function() mw:Destroy() end) end
  mw, mwEl, mwKey, mwArmed = nil, {}, nil, nil
end

local function mwDisarm()
  if mwArmed then
    mwArmed = nil
    T.SetText(mwEl.delete, "Delete")
    T.SetText(mwEl.ignore, "Ignore kind")
  end
end

local function mwPicked() return mwEl.places and mwPlaces[mwEl.places:GetValue()] end

-- The kind Ignore kind would skip: the shown automatic overlay's, or in Gathering the picked place's; or nil.
local function mwKind()
  local ov = OV.Shown()
  if not (ov and ov.auto) then return nil end
  if OV.AutoKind(ov) then return OV.AutoKind(ov) end
  local p = mwPicked()
  return p and OV.PlaceKind(p.name)
end

-- Fills the window from the overlays, when they or the scene changed (from every change and OV.Tick).
function OV.SyncWindow()
  if not (mw and mwEl.pick) then return end
  local okRaw, raw = pcall(T.SceneRaw)
  raw = okRaw and raw or ""
  local key = OV.version .. ">" .. tostring(raw) .. ">" .. tostring(T.CharacterName())
  if key == mwKey then return end
  mwKey = key
  local shown = OV.Shown()
  local names = { OV.MW_NONE }
  mwPicks = {}
  for _, ov in ipairs(OV.List()) do
    names[#names + 1] = ov.name
    mwPicks[ov.name] = ov
  end
  local places = {}
  mwPlaces = {}
  for _, p in ipairs(OV.SortedPlaces(shown)) do
    places[#places + 1] = p.name
    mwPlaces[p.name] = p
  end
  T.SetText(mwEl.storage, OV.StorageText())
  local any = #places > 0
  if not any then places[1] = OV.MW_NO_PLACES end
  pcall(function()
    mwEl.pick:SetChoices(names)
    mwEl.pick:SetValue(shown and shown.name or OV.MW_NONE)
    local keep = mwEl.places:GetValue()
    mwEl.places:SetChoices(places)
    mwEl.places:SetValue(mwPlaces[keep] and keep or places[1])
    mwEl.icon:SetValue(shown and shown.icon or OV.ICONS[1])
    mwEl.color:SetValue(shown and shown.color or OV.COLORS[1][1])
    local line, about = OV.AutoSceneLine()
    T.SetText(mwEl.autoLine, line)
    T.SetTooltip(mwEl.autoLine, about)
    mwEl.auto:SetValue(OV.AutoOn())
    mwEl.fights:SetValue(OV.AutoOn(nil, true))
    for _, k in ipairs({ "icon", "color", "rename", "delete" }) do mwEl[k]:SetEnabled(shown ~= nil) end
    for _, k in ipairs({ "beacon", "look", "remove" }) do mwEl[k]:SetEnabled(any) end
    mwEl.ignore:SetEnabled(mwKind() ~= nil)
    local d = OV.LastDeath()
    mwEl.death:SetEnabled(d ~= nil and d.raw == raw)
  end)
end

local function mwIgnore()
  local kind = mwKind()
  if not kind then return end
  local id = "ignore>" .. tostring(T.settingsFor) .. ">" .. kind
  if not (mwArmed and mwArmed.id == id and T.Now() - mwArmed.at <= OV.CONFIRM) then
    mwDisarm()
    mwArmed = { at = T.Now(), id = id }
    T.SetText(mwEl.ignore, "Click again to confirm")
    mwMsg("Click again: the auto map stops marking " .. kind .. " in every scene, and its places here go.")
    return
  end
  mwDisarm()
  local ok, why = OV.Ignore(kind)
  local said = ok and ("The auto map skips " .. kind .. " now (/" .. T.commands[1] .. " overlay auto unignore "
    .. kind .. " undoes it).") or ("Couldn't ignore it: " .. why .. ".")
  mwMsg(said)
  T.Print(said)
end

local function mwOverlayName()
  local field = mwEl.ovname
  return field and field:GetText() or ""
end

local function mwClearOverlayName()
  if mwEl.ovname then mwEl.ovname:SetText("") end
end

local function mwNew(text)
  mwDisarm()
  local made, why = OV.Create(text or mwOverlayName())
  if made then mwClearOverlayName() end
  mwMsg(made and ("Made " .. made.name .. ", shown now: Mark here adds where you stand.")
    or ("Couldn't make it: " .. why .. "."))
end

local function mwRename()
  mwDisarm()
  local ov = OV.Shown()
  if not ov then return end
  local ok, why = OV.Rename(ov, mwOverlayName())
  if ok then mwClearOverlayName() end
  mwMsg(ok and ("Renamed it " .. why .. ".") or ("Couldn't rename it: " .. tostring(why) .. "."))
end

local function mwDelete()
  local ov = OV.Shown()
  if not ov then return end
  local id = tostring(T.settingsFor) .. ">" .. ov.id
  if not (mwArmed and mwArmed.id == id and T.Now() - mwArmed.at <= OV.CONFIRM) then
    mwArmed = { at = T.Now(), id = id }
    T.SetText(mwEl.delete, "Click again to confirm")
    mwMsg("Click Delete again to delete " .. ov.name .. " and its " .. #OV.Places(ov) .. " places.")
    return
  end
  mwDisarm()
  local ok, why = OV.Delete(ov)
  mwMsg(ok and ("Deleted " .. ov.name .. ".") or ("Couldn't delete it: " .. why .. "."))
end

local function mwMark(text)
  local field = mwEl.name
  local p, ov, name = OV.Mark(text or (field and field:GetText()) or "")
  if p and field then field:SetText("") end
  if p then
    mwMsg("Marked " .. p.name .. " in " .. ov.name .. "." .. OV.RoomNote())
    return
  end
  local refused = OV.MarkFailed(name, ov)
  mwMsg(refused)
  T.Print(refused)                      -- in chat too: the window's last line can be cut off (owner, 2026-10-14)
end

local function mwBuild()
  local colors = {}
  for i, c in ipairs(OV.COLORS) do colors[i] = c[1] end
  local function row(children, top)
    return UI.Row{ style = { alignItems = "center", marginTop = top or 4 }, children = children }
  end
  mwEl = {
    pick = UI.Dropdown{ id = "mw_pick", choices = { OV.MW_NONE }, value = OV.MW_NONE,
      style = { flexGrow = 1, flexShrink = 1 }, tooltip = "The overlay shown on your map (only one at a time)",
      onChange = function(_, name)
        mwDisarm()
        local ok, why = OV.Show(mwPicks[name])
        mwMsg(ok and "" or ("Couldn't show it: " .. why .. "."))
      end },
    ovname = T.TextField{ id = "mw_ovname", text = "", placeholder = "An overlay's name: Gathering, XP farming...",
      maxLength = OV.NAME_MAX, style = { flexGrow = 1, flexShrink = 1 },
      tooltip = "A name for a new overlay (New), or the shown one's new name (Rename)",
      onSubmit = function(_, text) mwNew(text) end },
    rename = UI.Button{ id = "mw_rename", text = "Rename", style = { marginLeft = 2 },
      tooltip = "Give the shown overlay this name", onClick = function() mwRename() end },
    delete = UI.Button{ id = "mw_delete", text = "Delete", style = { marginLeft = 2 },
      tooltip = "Delete the shown overlay and its places (click twice)", onClick = function() mwDelete() end },
    icon = UI.Dropdown{ id = "mw_icon", choices = OV.ICONS, value = OV.ICONS[1],
      tooltip = "The shape of the marks you make next (marks made before keep theirs: Set look changes one)",
      onChange = function(_, v)
        local ov = OV.Shown()
        local ok, why = true, nil
        if ov then ok, why = OV.SetIcon(ov, v) end
        mwMsg(ok and "" or ("Couldn't change it: " .. why .. "."))
      end },
    color = UI.Dropdown{ id = "mw_color", choices = colors, value = colors[1], style = { marginLeft = 4 },
      tooltip = "The color of the marks you make next (Gold is the Loot Tracker runs')",
      onChange = function(_, v)
        local ov = OV.Shown()
        local ok, why = true, nil
        if ov then ok, why = OV.SetColor(ov, v) end
        mwMsg(ok and "" or ("Couldn't change it: " .. why .. "."))
      end },
    name = T.TextField{ id = "mw_name", text = "", placeholder = "Name this spot: Iron vein, Bank...",
      maxLength = OV.NAME_MAX, style = { flexGrow = 1, flexShrink = 1 },
      tooltip = "Empty: Place 1, Place 2... (a name used: Wolf 2)",
      onSubmit = function(_, text) mwMark(text) end },
    places = UI.Dropdown{ id = "mw_places", choices = { OV.MW_NO_PLACES }, value = OV.MW_NO_PLACES,
      style = { flexGrow = 1, flexShrink = 1 }, tooltip = "The shown overlay's places in this scene",
      onChange = function()
        mwMsg("")
        mwDisarm()
        pcall(function() mwEl.ignore:SetEnabled(mwKind() ~= nil) end)
      end },
    beacon = UI.Button{ id = "mw_beacon", text = "Compass", style = { marginLeft = 4 },
      tooltip = "Point the game's compass at this place (it's the game's beacon: it replaces your own /beacon)",
      onClick = function()
        local p = mwPicked()
        if not p then return end
        local _, said = OV.Beacon(p)
        mwMsg(said)
        T.Print(said)                    -- in chat too: the window's last line can be cut off
      end },
    look = UI.Button{ id = "mw_look", text = "Set look", style = { marginLeft = 2 },
      tooltip = "Give this place the shape and color above",
      onClick = function()
        local p, ov = mwPicked(), OV.Shown()
        if not (p and ov) then return end
        local ok, why = OV.SetPlaceLook(ov, p)
        mwMsg(ok and (p.name .. " is now a " .. p.color:lower() .. " " .. p.icon .. ".")
          or ("Couldn't change it: " .. why .. "."))
      end },
    remove = UI.Button{ id = "mw_remove", text = "Remove", style = { marginLeft = 2 },
      tooltip = "Take this place out of the overlay",
      onClick = function()
        local p, ov = mwPicked(), OV.Shown()
        if not (p and ov) then return end
        local ok, why = OV.RemovePlace(ov, p)
        mwMsg(ok and ("Removed " .. p.name .. ".") or ("Couldn't remove it: " .. why .. "."))
      end },
    autoLine = UI.Label{ id = "mw_autoline", text = "", class = "text", style = { whiteSpace = "wrap", flexGrow = 1,
      flexShrink = 1 },
      tooltip = "" },
    auto = UI.Toggle{ id = "mw_auto", text = "Gathering", value = false,
      tooltip = "In this scene only: each resource node you gather here is marked where you stand, in an"
        .. " overlay of its kind and in " .. OV.GATHERING .. " (all kinds); a node already marked within "
        .. OV.AUTO_NEAR .. " m isn't marked again",
      onChange = function(_, on)
        local ok, why = OV.SetAuto(on == true)
        mwMsg(ok and (on and ("Gathering on in this scene: each node you gather here is marked.")
          or "Gathering off in this scene.") or ("Couldn't change it: " .. why .. "."))
      end },
    fights = UI.Toggle{ id = "mw_fights", text = "Fights", value = false, style = { marginLeft = 4 },
      tooltip = "In this scene only: each creature you kill here is marked where you stand, in an overlay"
        .. " of its name and in " .. OV.FIGHTS .. " (all of them); one already marked within " .. OV.FIGHT_NEAR
        .. " m isn't marked again",
      onChange = function(_, on)
        local ok, why = OV.SetAuto(on == true, true)
        mwMsg(ok and (on and ("Fights on in this scene: each creature you kill here is marked.")
          or "Fights off in this scene.") or ("Couldn't change it: " .. why .. "."))
      end },
    ignore = UI.Button{ id = "mw_ignore", text = "Ignore kind", style = { marginLeft = 4 },
      tooltip = "Stop auto mapping this kind, in every scene (the shown automatic overlay's, or in " .. OV.GATHERING
        .. " or " .. OV.FIGHTS .. " the picked place's), and take its places here out (click twice)",
      onClick = function() mwIgnore() end },
    death = UI.Button{ id = "mw_death", text = "Last death", style = { marginLeft = 2 },
      tooltip = "Point your compass at where you last died, in this scene (the game's beacon: it replaces your own"
        .. " /beacon)",
      onClick = function()
        local d = OV.LastDeath()
        if not d then return end
        local _, said = OV.Beacon(d)
        mwMsg(said)
        T.Print(said)
      end },
    msg = UI.Label{ id = "mw_msg", text = "", class = "dim", style = { whiteSpace = "wrap", flexGrow = 1,
      flexShrink = 1 } },
    storage = UI.Label{ id = "mw_storage", text = "", class = "dim", style = { marginLeft = 6 },
      tooltip = "Your map overlays' share of this character's saved file (the game keeps at most 256 KB a file):"
        .. " /" .. T.commands[1] .. " overlay scenes shows what each scene takes" },
  }
  mw = UI.Window{
    id = MW_ID, title = "Map overlays", width = 420, height = 335, minWidth = 340, minHeight = 295,
    x = T.Window.DEFAULT_X, y = T.Window.DEFAULT_Y, escCloses = true,
    style = { paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 6 },
    children = {
      row({ UI.Label{ text = "Shown", class = "text", style = { marginRight = 6 } }, mwEl.pick }, 0),
      row({ mwEl.ovname, UI.Button{ id = "mw_new", text = "New", style = { marginLeft = 4 },
        tooltip = "Make an overlay with this name and show it", onClick = function() mwNew() end },
        mwEl.rename, mwEl.delete }),
      row({ UI.Label{ text = "New marks", class = "text", style = { flexGrow = 1 } }, mwEl.icon, mwEl.color }),
      row({ mwEl.name, UI.Button{ id = "mw_mark", text = "Mark here", style = { marginLeft = 4 },
        tooltip = "Add where you stand to the shown overlay, in the shape and color above (or to a new overlay,"
          .. " Places, if you have none)", onClick = function() mwMark() end } }),
      row({ mwEl.places, mwEl.beacon, mwEl.look, mwEl.remove }),
      row({ mwEl.autoLine }),
      row({ mwEl.auto, mwEl.fights, UI.Label{ text = "", style = { flexGrow = 1 } }, mwEl.ignore, mwEl.death }, 2),
      row({ mwEl.msg, mwEl.storage }),
    },
  }
end

function OV.IsWindowShown() return mw ~= nil and mw:IsShown() end

-- Opens the Marks window, or closes it when it's open. Returns true when it shows.
function OV.ToggleWindow()
  if OV.IsWindowShown() then
    mw:Hide()
    return false
  end
  if not mw then
    T.TakeSharedWindow("marks", mwDrop)
    local ok, err = pcall(mwBuild)
    if not ok then
      mwDrop()
      T.Print("The Map overlays window can't open right now; try again in a moment. (" .. tostring(err) .. ")")
      return false
    end
  end
  if not mw:Show() then
    T.Print("The Map overlays window can't reopen right now; try again in a few seconds.")
    return false
  end
  mwKey = nil
  OV.SyncWindow()
  return true
end

-- Every tick (T.Tick): the window follows a scene change (its list is this scene's places).
function OV.Tick()
  OV.SavePending()                    -- the auto map's marks, together, out of combat
  if not mw then return end
  if mwArmed and T.Now() - mwArmed.at > OV.CONFIRM then mwDisarm() end
  OV.SyncWindow()
end

-- ---------------------------------------------------------------------------
-- The launcher (Toolbox.Launcher, LN; owner, 2026-10-10; "the menu" to players): a strip of buttons opening
-- Toolbox's windows with one click, where Settings' tick boxes were the only way. Pictures: toolbox/launcher.png
-- (art/launcher.py: one frame a button, in LN.BUTTONS order), tinted LN.COLOR: lit while its window is open, dimmed
-- while it's closed, on a black shade of the player's darkness (`shade`, % alpha; 0 = none). On by default,
-- vertical, at the top-left corner; "Show the menu" off gives the old way back. Without the picture, text buttons.
-- Its own LN.TICK periodic follows the windows (they open and close from many places) and the combat hiding,
-- setting an opacity only when it changes.
-- Saved var "launcher": { show = bool (default true), vertical = bool (default true), size = LN.SIZE_MIN..MAX,
-- shade = 0..LN.SHADE_MAX (default LN.SHADE_DEFAULT), combat = bool (hide during combat, default false),
-- hide = { [button key] = true } (buttons left out; never all), x, y }.
-- ---------------------------------------------------------------------------
local LN = { FRAME_ID = "toolbox_launcher", HOME = { 0, 0 }, PAGE = "Menu" }
Toolbox.Launcher = LN
LN.TICK = 0.5
LN.PATH = "toolbox/launcher.png"
LN.SIZE_MIN, LN.SIZE_MAX, LN.SIZE_DEFAULT = 20, 64, 32
LN.SHADE_MAX, LN.SHADE_DEFAULT = T.SHADE_MAX, T.SHADE_DEFAULT
LN.GAP, LN.PAD = 4, 3
LN.COLOR = "@gold"                    -- the pictures' tint unless the player picks another (`color`)
-- The colors offered (owner, 2026-10-16): theme tokens, so each follows the player's skin; as the shout's.
LN.COLORS = { { "@gold", "Gold" }, { "@red", "Red" }, { "@green", "Green" }, { "@blue", "Blue" },
              { "@text-bright", "White" }, { "@text", "Text" } }
LN.LIT, LN.DIM = 1, 0.4               -- opacity: its window open, closed
-- Each button: the window, a short word for the text form, its command (for the tooltip), whether it's open and
-- what a click does. The pop-up windows count as open when pinned (a click pins or unpins them). Settings last,
-- Docs above it (owner).
LN.BUTTONS = {
  { key = "xp", name = "XP", short = "XP", cmd = " xp",
    open = function() return T.Compact.IsShown() end, toggle = function() T.Compact.Toggle() end },
  { key = "xpdetail", name = "XP Detailed", short = "XPD", cmd = " xpd",
    open = function() return T.Window.IsOpen() end, toggle = function() T.Window.Toggle() end },
  { key = "today", name = "Today", short = "Day", cmd = " daily",
    open = function() return T.Daily.IsShown() end, toggle = function() T.Daily.Toggle() end },
  { key = "loot", name = "Loot Tracker", short = "Loot", cmd = " loot",
    open = function() return T.DailyDetail.IsOpen() end, toggle = function() T.DailyDetail.Toggle() end },
  { key = "planner", name = "Crafting planner", short = "Plan", cmd = " plan",
    open = function() return T.Planner.IsShown() end, toggle = function() T.Planner.Open() end },
  { key = "combat", name = "Combat Detailed", short = "Fight", cmd = " combat detail",
    open = function() return T.Combat.Detail.IsOpen() end, toggle = function() T.Combat.Detail.Toggle() end },
  { key = "notify", name = "Notifications", short = "News", cmd = " notify show",
    open = function() return T.Notify.IsShown() end, toggle = function() T.Notify.ToggleWindow() end },
  -- A strip, not a window: lit while it shows (owner, 2026-10-13: the map features' place in the menu).
  { key = "location", name = "Location", short = "Loc", cmd = " location", strip = true,
    open = function() return LOC.GetShow() end, toggle = function() LOC.SetShow(not LOC.GetShow()) end },
  { key = "docs", name = "Docs", short = "Doc", cmd = " help",
    open = function() return T.Docs.IsShown() end, toggle = function() T.Docs.Toggle() end },
  { key = "settings", name = "Settings", short = "Set", cmd = "",
    open = function() return T.Config.IsShown() end, toggle = function() T.Config.Toggle() end },
}
local LN_PERIODIC = "toolbox_launcher"
local function lnDefaults()
  return { show = true, vertical = true, size = LN.SIZE_DEFAULT, shade = LN.SHADE_DEFAULT, combat = false, hide = {},
           color = LN.COLOR }
end
local lnPrefs = lnDefaults()
local lnEl = {}                       -- [i] = button i's element, nil while it's left out (empty until built)
local lnBox = nil                     -- the strip's content
local lnLit = {}                      -- [i] = the opacity set on it
local lnTex = -1
local lnShown = nil                   -- IsShown() at the last update (combat hiding)

local function lnSave()
  T.Save("launcher", lnPrefs)
  if T.Config then T.Config.Sync() end
end

local function lnCount()
  local n = 0
  for _, b in ipairs(LN.BUTTONS) do if not lnPrefs.hide[b.key] then n = n + 1 end end
  return n
end

function LN.Wanted() return lnPrefs.show == true end
function LN.IsShown()
  if lnPrefs.show ~= true then return false end
  if lnPrefs.combat and not T.Config.IsShown() and T.BuffBar.InCombatWindow() then return false end
  return true
end
function LN.Unbuilt() lnEl, lnLit, lnBox = {}, {}, nil end

function LN.ContentSize()
  local s, n = lnPrefs.size, lnCount()
  local long = n * s + (n - 1) * LN.GAP + 2 * LN.PAD
  if lnPrefs.vertical then return s + 2 * LN.PAD, long end
  return long, s + 2 * LN.PAD
end

-- The shade behind the buttons: black at `shade` % ("#00000066"), or none. A colour's alpha doesn't fade the
-- buttons (opacity would).
function LN.ShadeColor(pct) return T.ShadeColor(pct) end

local function lnTooltip(b)
  return b.name .. (b.strip and "\nClick to show or hide the strip (/" or "\nClick to open or close it (/")
    .. T.commands[1] .. b.cmd .. ")"
end

function LN.BuildContent()
  local s, pictures, n = lnPrefs.size, #LN.BUTTONS, lnCount()
  if lnTex < 0 then
    local ok, tex = pcall(ShroudLoadTexture, LN.PATH)
    if ok and type(tex) == "number" and tex >= 0 then lnTex = tex end
  end
  local kids, built, at = {}, {}, 0
  for i, b in ipairs(LN.BUTTONS) do
    if not lnPrefs.hide[b.key] then
      at = at + 1
      local index = i
      local gap = at < n and LN.GAP or 0
      local style = { opacity = LN.DIM, marginLeft = 0, marginTop = 0,
                      marginRight = lnPrefs.vertical and 0 or gap, marginBottom = lnPrefs.vertical and gap or 0 }
      local click = function() LN.Click(index) end
      local e = nil
      if lnTex >= 0 then
        e = UI.Image{ id = "ln_" .. b.key, width = s, height = s, texture = lnTex,
          uv = { (i - 1) / pictures, 0, 1 / pictures, 1 }, tint = lnPrefs.color, tooltip = lnTooltip(b),
          onClick = click,
          style = style }
      else
        style.width, style.height, style.minHeight = s, s, s
        style.fontSize, style.paddingLeft, style.paddingRight = math.max(9, math.floor(s * 0.3)), 0, 0
        e = UI.Button{ id = "ln_" .. b.key, text = b.short, tooltip = lnTooltip(b), onClick = click, style = style }
      end
      kids[#kids + 1], built[i] = e, e
    end
  end
  -- Its exact size, the buttons centred across it: unsized, the column was as wide as the strip's frame and its
  -- buttons sat to the left (owner, 2026-10-10).
  local w, h = LN.ContentSize()
  local boxStyle = { backgroundColor = LN.ShadeColor(lnPrefs.shade), borderRadius = 4, paddingLeft = LN.PAD,
    paddingRight = LN.PAD, paddingTop = LN.PAD, paddingBottom = LN.PAD, marginLeft = 0, marginRight = 0,
    marginTop = 0, marginBottom = 0, width = w, minWidth = w, maxWidth = w, height = h, minHeight = h,
    maxHeight = h, alignItems = "center" }
  if lnPrefs.vertical then
    lnBox = UI.Column{ id = "launcher", style = boxStyle, children = kids }
  else
    lnBox = UI.Row{ id = "launcher", style = boxStyle, children = kids }
  end
  lnEl, lnLit = built, {}
  LN.Update()
  return lnBox
end

-- Every LN.TICK s and after a click: lit or dimmed as its window is open or closed; hidden in combat if chosen.
function LN.Update()
  if not lnPrefs.show then return end
  local shown = LN.IsShown()
  if shown ~= lnShown then
    lnShown = shown
    Hud.Refresh()
  end
  if not lnBox then return end
  for i, b in ipairs(LN.BUTTONS) do
    local e = lnEl[i]
    if e then
      local ok, open = pcall(b.open)
      local op = (ok and open) and LN.LIT or LN.DIM
      if lnLit[i] ~= op then
        lnLit[i] = op
        T.SetStyle(e, { opacity = op })
      end
    end
  end
end

function LN.Click(i)
  local b = LN.BUTTONS[i]
  if not b then return end
  local ok, err = pcall(b.toggle)
  if not ok then T.Print("Couldn't open " .. b.name .. ": " .. tostring(err)) end
  LN.Update()
end

local function lnRebuild()
  lnSave()
  if lnPrefs.show then Hud.Rebuild("launcher") end
end

function LN.GetShow() return lnPrefs.show == true end
function LN.SetShow(on)
  lnPrefs.show = on == true
  lnSave()
  Hud.Build(true)                      -- its frame exists only while it is in use (HUD frames are limited)
  Hud.Refresh()
end

function LN.GetVertical() return lnPrefs.vertical ~= false end
function LN.SetVertical(on)
  lnPrefs.vertical = on == true
  lnRebuild()
end

function LN.GetSize() return lnPrefs.size end
function LN.SetSize(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < LN.SIZE_MIN or n > LN.SIZE_MAX then return false end
  if n == lnPrefs.size then return true end
  lnPrefs.size = n
  lnRebuild()
  return true
end

function LN.GetShade() return lnPrefs.shade end
function LN.SetShade(n)
  if type(n) ~= "number" or n ~= math.floor(n) or n < 0 or n > LN.SHADE_MAX then return false end
  lnPrefs.shade = n
  lnSave()
  if lnBox then T.SetStyle(lnBox, { backgroundColor = LN.ShadeColor(n) }) end     -- in place
  return true
end

-- The pictures' color: a token from LN.COLORS, or its name ("Gold"); false when it's neither. Set in place.
function LN.ColorToken(v)
  if type(v) ~= "string" then return nil end
  for _, c in ipairs(LN.COLORS) do
    if v == c[1] or v:lower() == c[2]:lower() then return c[1] end
  end
  return nil
end
function LN.ColorName(token)
  for _, c in ipairs(LN.COLORS) do if c[1] == token then return c[2] end end
  return LN.COLORS[1][2]
end
function LN.GetColor() return lnPrefs.color end
function LN.SetColor(v)
  local token = LN.ColorToken(v)
  if not token then return false end
  lnPrefs.color = token
  lnSave()
  for _, e in pairs(lnEl) do
    if e.SetTint then pcall(e.SetTint, e, token) end      -- the text form (no picture) has no tint
  end
  return true
end

function LN.GetHideInCombat() return lnPrefs.combat == true end
function LN.SetHideInCombat(on)
  lnPrefs.combat = on == true
  lnSave()
  LN.Update()
end

-- Whether button `key` shows; switching off the last one is refused (false, why).
function LN.GetButton(key) return not lnPrefs.hide[key] end
function LN.SetButton(key, on)
  local known = false
  for _, b in ipairs(LN.BUTTONS) do if b.key == key then known = true end end
  if not known then return false, "No such button." end
  if on then
    lnPrefs.hide[key] = nil
  elseif not lnPrefs.hide[key] then
    if lnCount() <= 1 then return false, "Keep at least one button (or switch the menu off)." end
    lnPrefs.hide[key] = true
  end
  lnRebuild()
  return true
end

function LN.GetSavedPosition() return lnPrefs.x, lnPrefs.y end
function LN.SavePosition(x, y)
  if x ~= lnPrefs.x or y ~= lnPrefs.y then
    lnPrefs.x, lnPrefs.y = x, y
    T.Save("launcher", lnPrefs)
  end
end

local lnMover = Hud.MoverFor("launcher", LN.HOME)
LN.GetPosition, LN.MoveTo, LN.Nudge, LN.ResetPosition = lnMover.Get, lnMover.MoveTo, lnMover.Nudge, lnMover.Reset

-- Re-runnable (another character's settings): before Toolbox.Hud.Init builds the strips. The first time a
-- character has none saved (a new install, or an update to the version that brought it), chat says where it is.
function LN.Init()
  local saved = T.ReadSaved("launcher")
  lnPrefs = lnDefaults()
  if type(saved) == "table" then
    lnPrefs.show = saved.show ~= false
    lnPrefs.vertical = saved.vertical ~= false
    lnPrefs.combat = saved.combat == true
    local function whole(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end
    if whole(saved.size, LN.SIZE_MIN, LN.SIZE_MAX) then lnPrefs.size = saved.size end
    if whole(saved.shade, 0, LN.SHADE_MAX) then lnPrefs.shade = saved.shade end
    lnPrefs.color = LN.ColorToken(saved.color) or LN.COLOR
    if type(saved.hide) == "table" then
      for _, b in ipairs(LN.BUTTONS) do
        if saved.hide[b.key] == true then lnPrefs.hide[b.key] = true end
      end
      if lnCount() == 0 then lnPrefs.hide = {} end
    end
    if type(saved.x) == "number" and type(saved.y) == "number" then lnPrefs.x, lnPrefs.y = saved.x, saved.y end
  else
    if not (T.settingsFor and T.Backup.resetApplied == T.settingsFor) then   -- not after this character's reset,
      -- which cleared it (owner, 2026-10-16); another character in the same run still gets it (review 55)
      T.Print("New: the menu, top left: one click opens a Toolbox window. Move it by its grip; change or switch it"
        .. " off in Settings, Menu, setups, backup & reset (or /" .. T.commands[1] .. " menu off).")
    end
    T.Save("launcher", lnPrefs)
  end
  lnEl, lnLit, lnBox, lnShown = {}, {}, nil, nil
  Hud.Register("launcher", LN)
  T.RegisterPeriodic(LN_PERIODIC, LN.Update, LN.TICK, true)
end

-- The strip goes before the target (built last); a reset clears its settings.
table.insert(Hud.ORDER, #Hud.ORDER, "launcher")
Hud.NAMES.launcher = "menu"
T.Backup.KEYS[#T.Backup.KEYS + 1] = "launcher"

-- /toolbox menu (or launcher)
T.AddCommand("menu", "the menu: buttons opening Toolbox's windows (on|off; vertical|horizontal; size <n>; shade <0-"
    .. LN.SHADE_MAX .. ">; color <name>; combat hide|show; move [x y])", function(rest)
  local word, args = T.ParseArgs(rest)
  word, args = word:lower(), args:lower()
  local c = "/" .. T.commands[1] .. " menu"
  if word == "" then
    LN.SetShow(not lnPrefs.show)
  elseif word == "on" or word == "off" then
    LN.SetShow(word == "on")
  elseif word == "vertical" or word == "horizontal" then
    LN.SetVertical(word == "vertical")
  elseif word == "size" then
    if not LN.SetSize(tonumber(args)) then
      T.Print("Use " .. c .. " size " .. LN.SIZE_MIN .. "-" .. LN.SIZE_MAX .. ".")
      return
    end
  elseif word == "shade" then
    if not LN.SetShade(tonumber(args)) then
      T.Print("Use " .. c .. " shade 0-" .. LN.SHADE_MAX .. " (0: none).")
      return
    end
  elseif word == "color" or word == "colour" then
    if not LN.SetColor(args) then
      local names = {}
      for i, col in ipairs(LN.COLORS) do names[i] = col[2]:lower() end
      T.Print("Use " .. c .. " color " .. table.concat(names, "|") .. ".")
      return
    end
  elseif word == "combat" and (args == "hide" or args == "show") then
    LN.SetHideInCombat(args == "hide")
  elseif word == "move" then
    T.MoveCommand(LN, "menu", "The menu", args)
    return
  else
    T.Print("Use " .. c .. " [on|off], vertical|horizontal, size <n>, shade <n>, color <name>, combat hide|show or"
      .. " move [x y].")
    return
  end
  T.Print("Menu: " .. (lnPrefs.show and "on" or "off") .. ", " .. (lnPrefs.vertical and "vertical" or "horizontal")
    .. ", " .. lnPrefs.size .. " px, " .. LN.ColorName(lnPrefs.color):lower() .. ", shade " .. lnPrefs.shade .. "%"
    .. (lnPrefs.combat and ", hidden in combat" or "") .. ".")
end, { "launcher" })
