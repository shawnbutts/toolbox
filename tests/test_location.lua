-- The location strip (Toolbox.Location, end of hud.lua): the scene, your position and which way you face.
local H = require("harness")

return function(t)
  local function strip() return H.S.frames.toolbox_location end
  local function text(id) return strip():Find(id).text end

  t.test("off by default; /toolbox location shows the scene, position and facing", function()
    H.boot()
    t.eq(strip(), nil, "no strip until it's switched on")
    H.S.scene = "Northern Lowlands"
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
    H.advance(1)
    t.eq(text("loc_water"), "Salt water, 12 m")
    t.ok(strip():Find("loc_water").visible ~= false)
    local _, h1 = Toolbox.Location.ContentSize()
    t.ok(h1 > h0, "the strip takes the line")
    H.S.water = { "fresh", 0 }
    H.advance(1)
    t.eq(text("loc_water"), "In fresh water")
    t.eq(Toolbox.Location.WaterText("lava", 3), "Lava, 3 m")
    t.no(strip():Find("loc_strip").tooltip:find("Fishable water"), "the scene's list isn't read yet")
    H.S.sceneWater = { "salt", "fresh" }
    H.advance(Toolbox.Location.WATER_EVERY + 1)
    local tip = strip():Find("loc_strip").tooltip
    t.ok(tip:find("Fishable water in this scene: salt water, fresh water%.$"), tip)
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

  t.test("the move command and position buttons", function()
    H.boot()
    H.chat("/tbx location on")
    H.chat("/tbx location move 300 50")
    t.ok(H.lastLog():find("The location strip at"), H.lastLog())
  end)
end
