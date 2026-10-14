-- The location strip (Toolbox.Location, end of hud.lua): the scene, your position and which way you face.
local H = require("harness")

return function(t)
  local function strip() return H.S.frames.toolbox_location end
  local function text(id) return strip():Find(id).text end

  t.test("off by default; /toolbox location shows the scene, position and facing", function()
    H.boot()
    t.eq(strip(), nil, "no strip until it's switched on")
    H.S.scene = "Northern Lowlands"
    H.callback("ShroudOnSceneLoaded", H.S.scene)   -- a scene change: the game says so
    H.S.pos = { 2014.4, 30.2, -3015.6 }
    H.S.heading = 47
    H.chat("/tbx location")
    t.ok(strip() and strip().visible ~= false, "shown")
    H.advance(1)
    t.eq(text("loc_scene"), "Northern Lowlands")
    t.eq(text("loc_coords"), "2014, 30, -3016")
    t.eq(text("loc_facing"), "Facing NE (47)")
    local tip = strip():Find("loc_strip").tooltip
    t.ok(tip:find("^Area: Northern Lowlands %(NorthernLowlands%) Loc: %(2014%.4, 30%.2, %-3015%.6%)"), tip)
    t.ok(H.saved("location").show == true, "remembered")
  end)

  t.test("follows you: moving, turning and changing scene; the width follows the scene's name", function()
    H.boot()
    H.chat("/tbx location on")
    H.advance(1)
    local w1 = Toolbox.Location.ContentSize()
    H.S.pos = { -5, 0, 12 }
    H.S.heading = 181
    H.advance(1)
    t.eq(text("loc_coords"), "-5, 0, 12")
    t.eq(text("loc_facing"), "Facing S (181)")
    H.S.scene = "The Northern Vertaxis Lowlands Of Some Length"
    H.callback("ShroudOnSceneLoaded", H.S.scene)   -- a scene change: the game says so
    H.advance(1)
    t.eq(text("loc_scene"), "The Northern Vertaxis Lowlands Of Some Length")
    t.ok(Toolbox.Location.ContentSize() > w1, "wider for a long name")
  end)

  t.test("the hover follows a move inside one whole unit (review 21)", function()
    H.boot()
    H.S.pos = { 1.1, 2, 3 }
    H.chat("/tbx location on")
    H.advance(1)
    t.ok(strip():Find("loc_strip").tooltip:find("Loc: %(1%.1, 2, 3%)"), strip():Find("loc_strip").tooltip)
    H.S.pos = { 1.4, 2, 3 }
    H.advance(1)
    t.eq(text("loc_coords"), "1, 2, 3", "the label stays")
    t.ok(strip():Find("loc_strip").tooltip:find("Loc: %(1%.4, 2, 3%)"), strip():Find("loc_strip").tooltip)
  end)

  t.test("facing can be hidden; settings and a restart keep the choices", function()
    H.boot()
    H.chat("/tbx location on")
    local _, h3 = Toolbox.Location.ContentSize()
    H.chat("/tbx location facing off")
    t.eq(strip():Find("loc_facing").visible, false)
    local _, h2 = Toolbox.Location.ContentSize()
    t.ok(h2 < h3, "a line shorter")
    H.restart(nil, true)
    t.eq(Toolbox.Location.GetShow(), true)
    t.eq(Toolbox.Location.GetFacing(), false)
    H.chat("/tbx config")
    local cfg = H.config()
    t.eq(cfg:Find("loc_show").value, true)
    -- Its own page, with its place and the runs on the map (owner, 2026-10-13).
    local C = Toolbox.Config
    for _, id in ipairs({ "loc_show", "loc_facing", "loc_water", "location_pos", "dd_markers" }) do
      t.eq(C.PageOf(id), "map", id)
    end
    t.eq(C.PageOf("launcher_pos"), "hud", "the other strips stay under HUD layout")
    t.ok(H.configRaw():Find("location_pos").text:find("^%d+, %d+$"), "its position shown")
    H.change("toolbox_config", "loc_show", false)
    t.eq(Toolbox.Location.GetShow(), false)
    H.chat("/tbx config")                                -- (closes settings: strips show while they're open)
    t.ok(strip() == nil or strip().visible == false, "gone")
  end)

  t.test("compass points; unknown values; an older client without /loc's line", function()
    local L = Toolbox.Location
    t.eq(L.FacingText(0), "Facing N (0)")
    t.eq(L.FacingText(22), "Facing N (22)")
    t.eq(L.FacingText(23), "Facing NE (23)")
    t.eq(L.FacingText(337), "Facing NW (337)")
    t.eq(L.FacingText(338), "Facing N (338)")
    t.eq(L.FacingText(90), "Facing E (90)")
    t.eq(L.FacingText(359.6), "Facing N (0)")
    t.eq(L.FacingText(nil), "")
    t.eq(L.CoordsText(nil), "--")
    H.boot()
    H.S.noApi29 = true
    H.reload()
    H.S.pos = { 1.234, 2, 3 }
    H.chat("/tbx location on")
    H.advance(1)
    t.ok(strip():Find("loc_strip").tooltip:find("^Novia %(1%.23, 2%.00, 3%.00%)"), strip():Find("loc_strip").tooltip)
  end)

  t.test("fishable water (API 32): the nearest within 30 m, its line hidden without; the scene's kinds", function()
    H.boot()
    H.S.sceneWater = {}                          -- the game is still reading the scene
    H.chat("/tbx location on")
    H.advance(1)
    local _, h0 = Toolbox.Location.ContentSize()
    t.eq(strip():Find("loc_water").visible, false, "no water near")
    H.S.water = { "salt", 12.4 }
    H.S.pos = { 5, 0, 0 }                        -- walked up to it
    H.advance(Toolbox.Location.WATER_NEAR_EVERY)
    t.eq(text("loc_water"), "Salt water, 12 m")
    t.ok(strip():Find("loc_water").visible ~= false)
    local _, h1 = Toolbox.Location.ContentSize()
    t.ok(h1 > h0, "the strip takes the line")
    H.S.water = { "fresh", 0 }
    H.S.pos = { 17, 0, 0 }
    H.advance(Toolbox.Location.WATER_NEAR_EVERY)
    t.eq(text("loc_water"), "In fresh water")
    local asks, ask = 0, ShroudGetNearestWaterType          -- asked every 15 s, not each tick
    ShroudGetNearestWaterType = function(...)
      asks = asks + 1
      return ask(...)
    end
    for i = 1, 30 do                                        -- walking for 30 s
      H.S.pos = { 17 + i, 0, 0 }
      H.advance(1)
    end
    ShroudGetNearestWaterType = ask
    t.ok(asks <= 30 / Toolbox.Location.WATER_NEAR_EVERY + 1, asks .. " asks in 30 s")
    t.eq(Toolbox.Location.WaterText("lava", 3), "Lava, 3 m")
    t.no(strip():Find("loc_strip").tooltip:find("Fishable water"), "the scene's list isn't read yet")
    H.S.sceneWater = { "salt", "fresh" }
    H.advance(Toolbox.Location.WATER_EVERY + 1)
    local tip = strip():Find("loc_strip").tooltip
    t.ok(tip:find("Fishable water in this scene: salt water, fresh water%.$"), tip)
    -- A town's water decoration changes the scene's list: it's read again (review 32).
    H.S.sceneWater = { "fetid" }
    H.advance(Toolbox.Location.WATER_EVERY + 1)
    tip = strip():Find("loc_strip").tooltip
    t.ok(tip:find("Fishable water in this scene: fetid water%.$"), tip)
    H.S.sceneWater = {}
    H.advance(Toolbox.Location.WATER_EVERY + 1)
    t.no(strip():Find("loc_strip").tooltip:find("Fishable water"), "none left")
    H.S.sceneWater = { "salt", "fresh" }
    H.advance(Toolbox.Location.WATER_EVERY + 1)
    H.chat("/tbx location water off")
    t.eq(strip():Find("loc_water").visible, false, "switched off")
    t.eq(H.saved("location").water, false)
    t.no(strip():Find("loc_strip").tooltip:find("Fishable water"))
    H.S.water = nil
    H.chat("/tbx location water on")
    t.eq(strip():Find("loc_water").visible, false, "none near")
    H.S.noWater = true
    H.reload()
    H.chat("/tbx config")
    t.eq(H.config():Find("loc_water").enabled, false, "an older client: greyed out")
  end)

  -- API 31: a smaller game window (or a bigger UI scale) can leave a strip past the edge.
  t.test("the game window shrinks: a strip past the edge comes back on screen, and its place is kept", function()
    H.boot()
    H.chat("/tbx location on")
    H.chat("/tbx location move 1700 900")
    strip().laidOut = { 180, 60 }
    H.clearLogs()
    t.eq(H.screenChanged{ uiWidth = 1920, uiHeight = 1080 }, nil)
    t.eq(strip().x .. "," .. strip().y, "1700,900", "inside: left alone")
    t.eq(#H.logs(), 0, "nothing said")
    H.screenChanged{ uiWidth = 1280, uiHeight = 720 }
    -- By its size: the larger of what the game laid out and what Toolbox gave the strip.
    local x = 1280 - math.max(180, strip().width)
    t.eq(strip().x .. "," .. strip().y, x .. "," .. (720 - math.max(60, strip().height)), "pulled in by its size")
    t.ok(H.logged("The game window changed: 1 strip moved back on screen."), H.lastLog())
    t.eq(H.saved("location").x, x, "kept")
    H.S.noScreen = true
    H.reload()
    t.eq(Toolbox.Hud.FitScreen(), 0, "an older client: nothing to read")
  end)

  -- Review 31: a strip off or hidden while the window shrinks comes back inside when it's built or shown again.
  t.test("the game window shrinks: a strip switched off or hidden then comes back on screen too", function()
    H.boot()
    H.chat("/tbx location on")
    H.chat("/tbx location move 1700 900")
    H.advance(1)
    H.chat("/tbx location off")
    H.clearLogs()
    t.eq(H.screenChanged{ uiWidth = 1280, uiHeight = 720 }, nil)
    t.eq(H.saved("location").x, 1700, "no strip: nothing to move yet")
    H.chat("/tbx location on")
    t.ok(strip().x < 1280 and strip().y < 720, strip().x .. "," .. strip().y)
    t.eq(H.saved("location").x, strip().x, "kept")
    -- The menu hidden in combat while the window shrinks.
    H.screenChanged{ uiWidth = 1920, uiHeight = 1080 }
    H.chat("/tbx menu move 1800 1000")
    H.advance(1)
    t.eq(H.saved("launcher").x, 1800)
    H.chat("/tbx menu combat hide")
    H.setCombat(true)
    H.advance(1)
    local menu = H.S.frames[Toolbox.Launcher.FRAME_ID]
    t.eq(menu.visible, false, "hidden in combat")
    H.screenChanged{ uiWidth = 1280, uiHeight = 720 }
    t.ok(menu.x < 1280 and menu.y < 720, menu.x .. "," .. menu.y)
    t.eq(H.saved("launcher").x, menu.x, "kept while hidden")
    H.setCombat(false)
  end)

  -- Review 31: a strip built hidden (never sized) is fitted when it first shows.
  t.test("the game window shrinks: a strip first shown later at a saved place near the edge comes inside", function()
    H.boot()
    H.chat("/tbx notify mail via hud")
    H.S.screen.uiWidth, H.S.screen.uiHeight = 1280, 720
    Toolbox.Notify.Hud.SavePosition(1200, 600)
    H.reload()
    local f = H.nhud()
    t.ok(f, "built")
    t.eq(f.visible, false, "nothing to show yet")
    H.setNotes{ unreadMail = 2 }
    f = H.nhud()
    t.ok(f.visible ~= false, "shown")
    t.ok(f.x + f.width <= 1280 and f.y + f.height <= 720, f.x .. "," .. f.y .. " " .. f.width .. "x" .. f.height)
    t.eq(H.saved("notify_hud").x, f.x, "kept")
  end)

  t.test("the move command and position buttons", function()
    H.boot()
    H.chat("/tbx location on")
    H.chat("/tbx location move 300 50")
    t.ok(H.lastLog():find("The location strip at"), H.lastLog())
  end)
end
