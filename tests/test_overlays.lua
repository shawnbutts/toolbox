-- Map overlays (Toolbox.Overlays, hud.lua): named sets of places, one shown on the map at a time.
local H = require("harness")

return function(t)
  local OV = function() return Toolbox.Overlays end
  local function marks(raw)
    local out = {}
    for id, m in pairs(H.S.markers[raw or "Novia"] or {}) do out[id] = m end
    return out
  end
  local function count(list)
    local n = 0
    for _ in pairs(list) do n = n + 1 end
    return n
  end
  -- The overlays as saved, in 1.8.0's shape ({ v, nextId, scenes = { [raw] = scene } }), from the index and each
  -- scene's own key; and their size as saved, every key together.
  local function savedOV()
    local index = H.saved("map_overlays")
    if type(index) ~= "table" then return nil end
    local out = { v = index.v, nextId = index.nextId, scenes = {} }
    for raw, n in pairs(index.scenes or {}) do out.scenes[raw] = H.saved("map_scene:" .. n) end
    return out
  end
  local function savedSize()
    local index = ShroudGetSavedVar("map_overlays")
    local size = Toolbox.SavedSize(index)
    for _, n in pairs(index.scenes or {}) do size = size + Toolbox.SavedSize(ShroudGetSavedVar("map_scene:" .. n)) end
    return size
  end
  -- Every overlay key refused (the index and each scene's).
  local REFUSE_ALL = setmetatable({}, { __index = function(_, key)
    return key == "map_overlays" or key:find("^map_scene:") ~= nil
  end })

  local function goTo(scene, pos)
    H.S.scene, H.S.sceneRaw = scene, scene:gsub(" ", "")
    if pos then H.S.pos = pos end
    H.callback("ShroudOnSceneLoaded", scene)
    H.advance(1)
  end

  t.test("the first mark makes an overlay, Places, shown; its place is a marker here", function()
    H.boot()
    H.S.pos = { 120.4, 30, -45.5 }
    H.advance(1)
    H.chat("/tbx mark Bank")
    t.ok(H.logged("Marked Bank in Places: Novia"), H.lastLog())
    local ov = OV().Shown()
    t.eq(ov.name, "Places")
    local m = marks()["ov" .. ov.id .. "-1"]
    t.ok(m, "a marker")
    t.eq(m.label, "Bank")
    t.eq(m.x, 120.4)
    t.eq(m.z, -45.5)
    t.eq(m.icon, "pin")
    t.eq(m.note, "Places")
    H.chat("/tbx mark")
    t.ok(H.logged("Marked Place 2 in Places"), "a name of its own: " .. H.lastLog())
    H.chat("/tbx mark bank")
    t.ok(H.logged("Marked bank 2 in Places"), "a taken name is numbered: " .. H.lastLog())
    H.chat("/tbx mark Bank")
    t.ok(H.logged("Marked Bank 3 in Places"), H.lastLog())
    H.chat("/tbx mark " .. string.rep("x", 24))
    H.chat("/tbx mark " .. string.rep("x", 24))
    t.ok(H.logged("Marked " .. string.rep("x", 22) .. " 2 in Places"), "cut to fit: " .. H.lastLog())
  end)

  local function gather(node, pos)
    H.S.pos = pos
    ShroudPlayerX, ShroudPlayerY, ShroudPlayerZ = pos[1], pos[2], pos[3]   -- where you stand now (as each step sets)
    H.gatherResults({ { node = node, failed = false, experience = 5, items = {} } })
  end
  local function byName(name)
    for _, ov in ipairs(OV().List()) do
      if ov.name == name then return ov end
    end
    return nil
  end

  t.test("auto map: off in a town until turned on there; then each node is marked by kind and in Gathering", function()
    H.boot()
    H.S.sceneInfo = { isPot = true }
    H.advance(1)
    gather("Iron Ore", { 10, 0, 10 })
    t.eq(#OV().List(), 0, "off: nothing marked")
    H.chat("/tbx overlay auto on")
    t.ok(H.logged("Auto map on in this scene"), H.lastLog())
    gather("Iron Ore", { 10, 0, 10 })
    t.ok(H.logged("Auto map: Iron Ore 1 marked%.$"), H.lastLog())
    gather("Iron Ore", { 14, 0, 12 })                   -- the same node from its other side
    t.ok(H.logged("Iron Ore 1 marked%.$"), "not marked again: " .. H.lastLog())
    gather("Iron Ore", { 40, 0, 10 })
    t.ok(H.logged("Auto map: Iron Ore 2 marked"))
    gather("Oak Tree", { 12, 0, 10 })                   -- near an iron node, but another kind
    local iron, oak, all = byName("Iron Ore"), byName("Oak Tree"), byName("Gathering")
    t.eq(#OV().Places(iron), 2)
    t.eq(#OV().Places(oak), 1)
    t.eq(#OV().Places(all), 3, "Gathering has every kind")
    t.eq(OV().Shown(), all, "Gathering shown, the scene showing none before")
    t.ok(iron.icon ~= oak.icon or iron.color ~= oak.color, "each kind its own look")
    local oakInAll = OV().FindPlace(all, "Oak Tree 1")
    t.eq(oakInAll.icon, oak.icon, "in Gathering, the kind's look")
    t.eq(oakInAll.color, oak.color)
    t.eq(count(marks()), 3, "on the map")
    H.advance(OV().SAVE_AFTER + 31)     -- the auto map's marks saved, then flushed
    H.restart()
    H.advance(2)
    t.ok(OV().AutoOn(), "kept on")
    t.eq(#OV().Places(byName("Gathering")), 3, "kept")
    H.S.sceneInfo = { isPot = true }                    -- another town
    goTo("Elsewhere", { 0, 0, 0 })
    gather("Iron Ore", { 10, 0, 10 })
    t.eq(#OV().List(), 0, "on per scene")
    goTo("Novia", { 0, 0, 0 })
    H.chat("/tbx overlay auto off")
    gather("Iron Ore", { 80, 0, 80 })
    t.eq(#OV().Places(byName("Iron Ore")), 2, "off again")
  end)

  local function kill(target, pos, extra)
    H.S.pos = pos
    ShroudPlayerX, ShroudPlayerY, ShroudPlayerZ = pos[1], pos[2], pos[3]
    local e = { kind = "death", fromYou = true, source = "shawn", target = target }
    for k, v in pairs(extra or {}) do e[k] = v end
    H.combat({ e })
  end

  t.test("auto map, fights: their own switch; each creature killed is marked by name and in Fights", function()
    H.boot()
    H.S.sceneInfo = { isPot = true }
    H.advance(1)
    H.chat("/tbx overlay auto on")
    kill("Elf Fighter", { 10, 0, 10 })
    t.eq(#OV().List(), 0, "gathering on, fights off: nothing marked")
    H.chat("/tbx overlay auto fights")
    t.ok(H.logged("Auto map of fights is off in this scene"), H.lastLog())
    H.chat("/tbx overlay auto fights on")
    t.ok(H.logged("Auto map of fights on in this scene"), H.lastLog())
    kill("Elf Fighter", { 10, 0, 10 })
    t.ok(H.logged("Auto map: Elf Fighter 1 marked%.$"), H.lastLog())
    kill("Elf Fighter", { 25, 0, 15 })                  -- the same camp
    t.ok(H.logged("Elf Fighter 1 marked%.$"), "not marked again: " .. H.lastLog())
    kill("Elf Fighter", { 60, 0, 10 })
    t.ok(H.logged("Auto map: Elf Fighter 2 marked"), H.lastLog())
    kill("Reaper", { 12, 0, 10 }, { fromYou = false, fromYourPet = true })   -- your pet's kill counts
    kill("Wolf", { 200, 0, 0 }, { fromYou = false })                         -- someone else's doesn't
    kill("shawn", { 300, 0, 0 }, { toYou = true })                           -- nor your own death
    gather("Iron Ore", { 10, 0, 10 })
    local elf, reaper, fights = byName("Elf Fighter"), byName("Reaper"), byName("Fights")
    t.eq(#OV().Places(elf), 2)
    t.eq(#OV().Places(reaper), 1)
    t.eq(#OV().Places(fights), 3, "Fights has every creature")
    t.no(byName("Wolf"))
    t.eq(#OV().Places(byName("Gathering")), 1, "gathering apart")
    t.eq(OV().Shown(), fights, "Fights shown, the scene showing none before")
    t.ok(elf.icon ~= reaper.icon or elf.color ~= reaper.color, "each creature its own look")
    H.chat("/tbx overlay auto ignore reaper")
    t.no(byName("Reaper"), "ignored: its overlay goes")
    t.eq(#OV().Places(fights), 2, "and its places in Fights")
    kill("Reaper", { 400, 0, 0 })
    t.no(byName("Reaper"), "not marked again")
    H.chat("/tbx overlay window")
    H.advance(1)
    t.eq(H.S.windows.toolbox_marks:Find("mw_fights").value, true, "the window's switch follows")
    H.change("toolbox_marks", "mw_fights", false)
    t.no(OV().AutoOn(nil, true), "off from the window")
    t.ok(OV().AutoOn(), "gathering still on")
    H.change("toolbox_marks", "mw_fights", true)
    H.advance(31)
    H.restart()
    H.advance(2)
    t.ok(OV().AutoOn(nil, true), "kept on")
    t.eq(#OV().Places(byName("Fights")), 2, "kept")
    H.chat("/tbx overlay auto off")
    kill("Troll", { 500, 0, 0 })
    t.ok(byName("Troll"), "fights stay on with gathering off")
  end)

  t.test("auto map, fights: their own 10 automatic overlays, beside gathering's", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay auto on")
    H.chat("/tbx overlay auto fights on")
    for i = 1, 10 do gather("Kind " .. i, { i * 20, 0, 0 }) end
    for i = 1, 10 do kill("Beast " .. i, { i * 30, 0, 100 }) end
    t.eq(#OV().List(), 2 * OV().AUTO_MAX, "10 each")
    t.ok(OV().FindPlace(byName("Fights"), "Beast 10 1"), "the 10th in Fights only")
    H.callback("ShroudOnDisableScript")      -- /lua reload as the game does it: saved at shutdown
    H.reload()
    t.eq(#OV().List(), 2 * OV().AUTO_MAX, "read back whole")
  end)

  t.test("auto map: on by default in adventure areas, off in towns; a scene's own switch wins; the setting", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay auto")
    t.ok(H.logged("Auto map is on in this scene %(an adventure area: on unless you switch it off%)"), H.lastLog())
    gather("Iron Ore", { 10, 0, 10 })
    kill("Elf Mage", { 30, 0, 30 })
    t.ok(byName("Iron Ore") and byName("Elf Mage"), "both marked without switching anything on")
    H.chat("/tbx overlay auto off")
    gather("Copper Ore", { 100, 0, 100 })
    t.no(byName("Copper Ore"), "switched off here")
    H.chat("/tbx overlay auto")
    t.ok(H.logged("off in this scene %(you switched it off here%)"), H.lastLog())
    H.advance(31)
    H.callback("ShroudOnDisableScript")
    H.restart()
    H.advance(2)
    t.no(OV().AutoOn(), "off is kept, though the scene is on by default")
    t.ok(OV().AutoOn(nil, true), "its fights still on by default")
    goTo("Ardoris", { 0, 0, 0 })
    H.S.sceneRaw = "Novia_R4_City_Ardoris"
    H.callback("ShroudOnSceneLoaded", "Ardoris")
    H.advance(1)
    H.chat("/tbx overlay auto fights")
    t.ok(H.logged("Auto map of fights is off in this scene %(a town: off unless you switch it on%)"), H.lastLog())
    gather("Trunk", { 5, 0, 5 })
    t.eq(#OV().List(), 0, "a town's trunks and stations aren't marked")
    goTo("Crossroads", { 0, 0, 0 })
    H.S.sceneInfo = { isPot = true }
    gather("Trunk", { 5, 0, 5 })
    t.eq(#OV().List(), 0, "nor a player town's")
    H.chat("/tbx overlay auto")
    t.ok(H.logged("%(a player%-owned town: off unless you switch it on%)"), H.lastLog())
    H.chat("/tbx overlay window")
    H.advance(1)
    local line = H.S.windows.toolbox_marks:Find("mw_autoline").text
    t.eq(line, "Auto map in Crossroads only (a player-owned town: off unless you switch it on)")
    t.eq(H.S.windows.toolbox_marks:Find("mw_auto").value, false)
    H.change("toolbox_marks", "mw_auto", true)
    t.eq(H.S.windows.toolbox_marks:Find("mw_msg").text, "Gathering on in this scene: each node you gather here is"
      .. " marked.")
    gather("Maple Tree", { 5, 0, 5 })
    t.ok(byName("Maple Tree"), "switched on there, it marks")
    H.chat("/tbx overlay window")
    H.S.sceneInfo = nil
    goTo("Spectral Forest", { 0, 0, 0 })
    H.chat("/tbx overlay window")
    H.advance(1)
    t.eq(H.S.windows.toolbox_marks:Find("mw_autoline").text,
      "Auto map in Spectral Forest only (an adventure area: on unless you switch it off)")
    t.eq(H.S.windows.toolbox_marks:Find("mw_auto").value, true, "on by default here")
    H.chat("/tbx overlay window")
    H.chat("/tbx config")
    H.change("toolbox_config", "ov_auto_new", false)
    t.eq(H.saved("location").autoNew, false)
    gather("Iron Ore", { 10, 0, 10 })
    t.eq(#OV().List(), 0, "the setting off: adventure areas wait to be switched on too")
    goTo("Crossroads", { 0, 0, 0 })
    t.ok(OV().AutoOn(), "a scene's own switch stays")
  end)

  local function savedPlaces(name)
    local saved = savedOV()
    for _, sc in pairs(saved and saved.scenes or {}) do
      for _, o in ipairs(sc.list) do
        if o.name == name then return o.places end
      end
    end
    return nil
  end

  t.test("auto map: marks are saved together, never in a fight; at shutdown too; a crash loses only those", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay auto on")
    H.chat("/tbx overlay auto fights on")
    H.setCombat(true)
    kill("Elf Fighter", { 10, 0, 10 })
    t.ok(OV().FindPlace(byName("Fights"), "Elf Fighter 1"), "on the map at once")
    t.eq(count(marks()), 1)
    t.eq(savedPlaces("Fights"), nil, "but not saved: a save walks every scene's overlays")
    H.advance(OV().SAVE_AFTER + 5)
    t.eq(savedPlaces("Fights"), nil, "never during a fight")
    kill("Elf Mage", { 60, 0, 10 })
    H.setCombat(false)
    H.advance(1)
    t.eq(savedPlaces("Fights"), nil, "nor just after it (the combat linger)")
    H.advance(Toolbox.BuffBar.COMBAT_LINGER + 1)
    t.ok((savedPlaces("Fights") or ""):find("Elf Mage 1", 1, true), "saved once out of combat: "
      .. tostring(savedPlaces("Fights")))
    gather("Iron Ore", { 10, 0, 10 })
    H.advance(5)
    t.eq(savedPlaces("Gathering"), nil, "gathering's wait for the batch too")
    H.callback("ShroudOnDisableScript")            -- a reload or quit: everything goes
    t.ok((savedPlaces("Gathering") or ""):find("Iron Ore 1", 1, true), "saved at shutdown")
    H.restart(nil, true)
    H.advance(2)
    t.eq(#OV().Places(byName("Fights")), 2, "kept")
    t.eq(#OV().Places(byName("Gathering")), 1)
    gather("Oak Tree", { 40, 0, 10 })
    H.restart()                                    -- a crash before the save: that mark only is lost
    H.advance(2)
    t.eq(#OV().Places(byName("Gathering")), 1, "the unsaved one gone, the rest kept")
  end)

  t.test("auto map: a batch the game refuses is taken off the map, and chat says so", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay auto on")
    gather("Iron Ore", { 10, 0, 10 })
    gather("Oak Tree", { 40, 0, 10 })
    t.eq(#OV().List(), 3)
    H.S.refuseKeys = REFUSE_ALL
    H.advance(OV().SAVE_AFTER + 1)
    t.ok(H.logged("Auto map: 4 new marks couldn't be saved %(the game refused to save it%), so they're taken off"),
      H.lastLog())
    t.eq(#OV().List(), 0, "the overlays made for them go too")
    t.eq(count(marks()), 0, "and their markers")
    H.S.refuseKeys = nil
    gather("Iron Ore", { 10, 0, 10 })
    t.ok(H.logged("Auto map: Iron Ore 1 marked"), "marked again: " .. H.lastLog())
  end)

  t.test("auto map: a mark's room is estimated: past the budget it's refused without a save", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay auto on")
    local budget = OV().BUDGET
    OV().BUDGET = math.floor(OV().StorageUse() * budget) + 150    -- room for a few places, not a new kind
    gather("Iron Ore", { 10, 0, 10 })
    local n = 0
    for i = 1, 20 do
      gather("Iron Ore", { 10 + i * 10, 0, 10 })
      if H.logged("Auto map couldn't mark Iron Ore: ") then break end
      n = i
    end
    t.ok(H.logged("Auto map couldn't mark Iron Ore: "), H.lastLog())
    t.ok(n < 20, "refused once full: " .. n)
    t.ok(OV().StorageUse() <= 1, "never past it: " .. OV().StorageUse())
    H.callback("ShroudOnDisableScript")
    t.ok(H.saved("map_overlays"), "what fitted is saved")
    OV().BUDGET = budget
  end)

  t.test("auto map: at most 10 automatic overlays a scene, apart from your own; told once", function()
    H.boot()
    H.advance(1)
    for i = 1, OV().MAX do H.chat("/tbx overlay new Mine " .. i) end
    t.eq(#OV().List(), OV().MAX)
    H.chat("/tbx overlay auto on")
    for i = 1, 10 do gather("Kind " .. i, { i * 20, 0, 0 }) end
    t.eq(#OV().List(), OV().MAX + OV().AUTO_MAX, "Gathering and 9 kinds beside the player's 10")
    t.ok(H.logged("no room for Kind 10 in an overlay of its own"), H.lastLog())
    t.ok(OV().FindPlace(byName("Gathering"), "Kind 10 1"), "still in Gathering")
    H.clearLogs()
    gather("Kind 10", { 500, 0, 0 })
    t.no(H.logged("no room"), "told once")
    t.eq(OV().Create("Mine 11"), nil, "your own still capped at 10")
    H.callback("ShroudOnDisableScript")      -- /lua reload as the game does it: saved at shutdown
    H.reload()
    t.eq(#OV().List(), OV().MAX + OV().AUTO_MAX, "read back whole")
  end)

  t.test("auto map: a kind named like one of your overlays gets (auto); the window's toggle", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay new Iron Ore")
    H.chat("/tbx overlay window")
    H.change("toolbox_marks", "mw_auto", true)
    t.ok(OV().AutoOn())
    gather("Iron Ore", { 10, 0, 10 })
    t.ok(byName("Iron Ore (auto)"), "its own name")
    t.eq(#OV().Places(byName("Iron Ore")), 0, "yours untouched")
    H.change("toolbox_marks", "mw_auto", false)
    t.no(OV().AutoOn())
  end)

  t.test("auto map: ignored kinds aren't marked, in any scene; ignoring drops this scene's; whole words", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay auto on")
    gather("Wolf Corpse", { 10, 0, 10 })
    gather("Iron Ore", { 40, 0, 10 })
    gather("Bear Corpse", { 70, 0, 10 })
    t.eq(#OV().Places(byName("Gathering")), 3)
    H.chat("/tbx overlay auto ignore corpse")
    t.ok(H.logged("skips corpse now, in every scene%. Here it took out 2 overlays and 2 places"), H.lastLog())
    t.no(byName("Wolf Corpse"), "its overlay gone")
    t.eq(#OV().Places(byName("Gathering")), 1, "only the ore left")
    H.clearLogs()
    gather("Deer Corpse", { 100, 0, 10 })
    t.no(H.logged("Auto map"), "not marked: " .. tostring(H.lastLog()))
    gather("Forest Mushroom", { 130, 0, 10 })
    H.chat("/tbx overlay auto ignore ore")
    gather("Copper Ore", { 160, 0, 10 })
    t.ok(byName("Forest Mushroom"), "whole words: 'ore' isn't in Forest")
    t.no(byName("Copper Ore"))
    H.chat("/tbx overlay auto ignore Corpse")
    t.ok(H.logged("already ignored"), H.lastLog())
    H.chat("/tbx overlay auto ignore")
    t.ok(H.logged("skips: corpse, ore"), H.lastLog())
    H.advance(31)
    H.restart()
    H.advance(2)
    goTo("Elsewhere", { 0, 0, 0 })
    H.chat("/tbx overlay auto on")
    gather("Wolf Corpse", { 10, 0, 10 })
    t.eq(#OV().List(), 0, "kept, and in every scene")
    H.chat("/tbx overlay auto unignore CORPSE")
    t.ok(H.logged("marks corpse again"), H.lastLog())
    gather("Wolf Corpse", { 10, 0, 10 })
    t.ok(byName("Wolf Corpse"))
  end)

  t.test("auto map: the window's Ignore kind (two clicks): the shown kind, or Gathering's picked place's", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay auto on")
    gather("Wolf Corpse", { 10, 0, 10 })
    gather("Iron Ore", { 40, 0, 10 })
    H.chat("/tbx overlay window")
    local w = H.S.windows.toolbox_marks
    t.eq(OV().Shown().name, "Gathering")
    H.change("toolbox_marks", "mw_places", "Wolf Corpse 1")
    t.ok(w:Find("mw_ignore"):IsEnabled(), "a place of a kind picked")
    H.click("toolbox_marks", "mw_ignore")
    t.eq(#OV().IgnoreList(), 0, "the first click only asks")
    H.click("toolbox_marks", "mw_ignore")
    t.eq(OV().IgnoreList()[1], "Wolf Corpse")
    t.ok(H.logged("skips Wolf Corpse now"), H.lastLog())
    t.no(byName("Wolf Corpse"))
    H.change("toolbox_marks", "mw_pick", "Iron Ore")
    H.click("toolbox_marks", "mw_ignore")
    H.click("toolbox_marks", "mw_ignore")
    t.no(byName("Iron Ore"), "the shown kind's overlay")
    H.chat("/tbx overlay new Mine")
    H.advance(1)
    t.no(w:Find("mw_ignore"):IsEnabled(), "not for your own")
  end)

  t.test("auto map: a second clash gets (auto 2), every name unique, and it survives a restart (review 44)", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay new Iron Ore")
    H.chat("/tbx overlay new Iron Ore (auto)")
    H.chat("/tbx overlay auto on")
    gather("Iron Ore", { 10, 0, 10 })
    local ov = byName("Iron Ore (auto 2)")
    t.ok(ov, "a name of its own")
    t.eq(ov.auto, "Iron Ore")
    local names = {}
    for _, o in ipairs(OV().List()) do
      t.no(names[o.name:lower()], "unique: " .. o.name)
      names[o.name:lower()] = true
    end
    H.advance(OV().SAVE_AFTER + 31)     -- the auto map's marks saved, then flushed
    H.restart()
    H.advance(2)
    ov = byName("Iron Ore (auto 2)")
    t.ok(ov, "kept")
    t.eq(#OV().Places(ov), 1, "with its place")
    local long = string.rep("y", OV().KIND_MAX)        -- a long kind is cut to fit its suffix
    H.chat("/tbx overlay new " .. long)
    H.chat("/tbx overlay new " .. string.rep("y", OV().NAME_MAX - 7) .. " (auto)")
    gather(long, { 90, 0, 10 })
    local made = byName(string.rep("y", OV().NAME_MAX - 9) .. " (auto 2)")
    t.ok(made, "cut to " .. OV().NAME_MAX)
  end)

  t.test("your last death: its own marker beside any overlay, in its scene only; kept; moved by the next", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx death")
    t.ok(H.logged("No death recorded"), H.lastLog())
    H.chat("/tbx mark Bank")
    H.S.pos = { -120.46, 30, 45 }
    H.advance(1)
    H.setDead(true)
    t.ok(H.logged("Your death is marked on the map %(Last death%)"), H.lastLog())
    H.setDead(false)
    local m = marks()[OV().DEATH_ID]
    t.ok(m, "a marker")
    t.eq(m.label, "Last death")
    t.eq(m.x, -120.5)
    t.ok(m.note:find("^You died here at %d%d:%d%d on %d+%-%d+%-%d+$"), m.note)
    t.ok(marks()["ov" .. OV().Shown().id .. "-1"], "beside the shown overlay")
    H.chat("/tbx overlay off")
    H.advance(1)
    t.ok(marks()[OV().DEATH_ID], "with no overlay shown too")
    H.chat("/tbx death")
    t.ok(H.logged("Your last death: Novia %(%-120%.5, 30, 45%)"), H.lastLog())
    H.chat("/tbx death compass")
    t.eq(H.S.beacon[1], -120.5)
    t.ok(H.logged("Your compass points at your last death"), H.lastLog())
    H.advance(31)
    H.restart()
    H.advance(2)
    t.ok(marks()[OV().DEATH_ID], "kept across a relaunch")
    goTo("Elsewhere", { 5, 0, 5 })
    t.no(marks("Elsewhere")[OV().DEATH_ID], "only in its scene")
    H.chat("/tbx death compass")
    t.ok(H.logged("is in Novia"), H.lastLog())
    H.setDead(true)
    t.ok(marks("Elsewhere")[OV().DEATH_ID], "the next death moves it")
    goTo("Novia", { 0, 0, 0 })
    t.no(marks()[OV().DEATH_ID], "gone from the old scene")
    goTo("Elsewhere", { 5, 0, 5 })
    H.chat("/tbx death clear")
    H.advance(1)
    t.no(marks("Elsewhere")[OV().DEATH_ID], "cleared")
    H.chat("/tbx death")
    t.ok(H.logged("No death recorded"), H.lastLog())
  end)

  t.test("your last death: its own look; cleared back at the spot after going away, or old in another scene", function()
    H.boot()
    H.S.clock = 1000000
    H.S.pos = { 10, 0, 10 }
    H.advance(1)
    H.setDead(true)
    H.setDead(false)
    local m = marks()[OV().DEATH_ID]
    t.eq(m.icon, "diamond")
    t.eq(m.color, OV().DEATH_HEX)
    for _, c in ipairs(OV().COLORS) do t.ok(c[2] ~= OV().DEATH_HEX, "no place has its color") end
    H.advance(5)
    t.ok(marks()[OV().DEATH_ID], "standing where you died keeps it")
    H.S.pos = { 10, 0, 60 }
    H.advance(3)
    t.ok(marks()[OV().DEATH_ID], "away: still there")
    H.S.pos = { 12, 0, 13 }
    H.advance(3)
    t.ok(H.logged("You're back where you died"), H.lastLog())
    t.no(marks()[OV().DEATH_ID], "back at it: cleared")
    t.no(OV().LastDeath())

    H.setDead(true)                                    -- old, but only cleared from another scene
    H.S.clock = H.S.clock + OV().DEATH_KEEP + 1
    H.advance(3)
    t.ok(marks()[OV().DEATH_ID], "in its scene: kept")
    goTo("Elsewhere", { 5, 0, 5 })
    H.advance(3)
    t.ok(H.logged("Last death in Novia is off the map"), H.lastLog())
    t.no(OV().LastDeath())

    H.setDead(true)                                    -- away is kept across a relaunch
    H.S.pos = { 5, 0, 60 }
    H.advance(3)
    H.advance(31)
    H.restart()
    goTo("Elsewhere", { 6, 0, 6 })
    H.advance(3)
    t.no(OV().LastDeath(), "back at it after the relaunch")

    H.S.markerIcons = { "pin", "diamond", "Skull" }
    H.reload()
    H.advance(1)
    H.setDead(true)
    H.advance(1)
    t.eq(marks("Elsewhere")[OV().DEATH_ID].icon, "Skull", "a death shape when the game has one")
    H.S.markerIcons = nil
  end)

  t.test("your last death: the setting hides it; the window's Last death points the compass, in its scene", function()
    H.boot()
    H.advance(1)
    H.S.pos = { 50, 0, 60 }
    H.advance(1)
    H.setDead(true)
    H.chat("/tbx overlay window")
    local w = H.S.windows.toolbox_marks
    t.ok(w:Find("mw_death"):IsEnabled())
    H.click("toolbox_marks", "mw_death")
    t.eq(H.S.beacon[1], 50)
    Toolbox.Location.SetDeath(false)
    t.no(marks()[OV().DEATH_ID], "the setting off takes it down")
    H.advance(31)
    H.restart()
    H.advance(2)
    t.no(Toolbox.Location.GetDeath(), "kept off")
    t.no(marks()[OV().DEATH_ID])
    H.chat("/tbx config")
    H.change("toolbox_config", "ov_death", true)
    t.ok(marks()[OV().DEATH_ID], "on again")
    goTo("Elsewhere", { 5, 0, 5 })
    H.chat("/tbx overlay window")
    H.advance(1)
    t.no(H.S.windows.toolbox_marks:Find("mw_death"):IsEnabled(), "not in another scene")
  end)

  t.test("a full overlay and your last death fit the scene's markers together", function()
    H.boot()
    H.advance(1)
    for i = 1, OV().SCENE_MAX do
      H.S.pos = { i * 3, 0, 0 }
      H.advance(1)
      H.chat("/tbx mark Spot " .. i)
    end
    H.setDead(true)
    H.advance(1)
    t.eq(count(marks()), OV().SCENE_MAX + 1)
    t.eq(OV().SCENE_MAX + 1 + Toolbox.Daily.RUNS_KEEP, 50, "with every run flag, the game's 50")
  end)

  t.test("a mark the window can't make says so in chat too (its last line can be cut off)", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay window")
    H.submit("toolbox_marks", "mw_name", "Wolf")
    H.advance(1)                                 -- a second press: a later frame
    H.submit("toolbox_marks", "mw_name", "Wolf")
    local msg = H.S.windows.toolbox_marks:Find("mw_msg"):GetText()
    t.ok(msg:find("Marked Wolf 2 in Places", 1, true), "a second Wolf is numbered: " .. msg)
    H.chat("/tbx overlay new Other")
    H.chat("/tbx overlay off")
    H.clearLogs()
    H.advance(1)
    H.submit("toolbox_marks", "mw_name", "Wolf")
    msg = H.S.windows.toolbox_marks:Find("mw_msg"):GetText()
    t.ok(msg:find("Couldn't mark Wolf: show one of this scene's overlays first", 1, true), msg)
    t.ok(H.logged("Couldn't mark Wolf: show one of this scene's overlays first"), "in chat: " .. H.lastLog())
  end)

  -- API 40, the owner's request #13082: a line in the full map's corner saying what Toolbox's markers here are.
  t.test("the map title names the shown overlay, the loot runs and your last death here; down when none", function()
    local function title() return H.call(function() return ShroudGetMapTitle() end) end
    H.boot()
    H.advance(1)
    t.eq(title(), nil, "nothing marked")
    H.chat("/tbx mark Bank")
    H.advance(1)
    t.eq(title(), "Places")
    H.setDead(true)
    H.setDead(false)
    H.advance(1)
    t.eq(title(), "Places, last death")
    local sets = H.S.titleSets
    H.advance(10)
    t.eq(H.S.titleSets, sets, "set only when it changes")
    H.chat("/tbx overlay off")
    H.advance(1)
    t.eq(title(), "last death")
    H.chat("/tbx loot reset")
    H.advance(300)
    H.chat("/tbx loot reset")                            -- a run filed here: its flag
    H.advance(2)
    t.eq(title(), "loot runs, last death")
    H.chat("/tbx death clear")
    H.call(Toolbox.DailyDetail.SetMarkers, false)      -- the Map & location page's toggle
    H.advance(2)
    t.eq(title(), nil, "nothing left: taken down")
    H.S.titleRefuse = "rate"
    H.chat("/tbx overlay show places")
    t.ok(H.logged("Showing Places"), H.lastLog())
    H.advance(1)
    t.eq(title(), nil, "refused")
    H.S.titleRefuse = nil
    H.advance(5)
    t.eq(title(), nil, "not asked again at once")
    H.advance(Toolbox.Overlays.RETRY)
    t.eq(title(), "Places", "tried again later")
    goTo("Elsewhere")
    t.eq(title(), nil, "another scene: its own")
    goTo("Novia")
    t.eq(title(), "Places")
    H.S.noMapTitle = true
    H.reload()
    H.advance(2)
    t.ok(true, "an older client: no title, no error")
    H.S.noMapTitle = nil
  end)

  t.test("the location strip names the shown overlay; arrows step: yours, Gathering, Fights, none", function()
    H.boot()
    H.chat("/tbx location on")
    H.advance(1)
    local function loc() return H.S.frames.toolbox_location end
    local function step(id)
      local b = loc():Find(id)
      H.call(function() b.onClick(b) end)
    end
    t.eq(loc():Find("loc_overlay").text, "Map: no overlays here", "no overlays here: it says so")
    t.eq(loc():Find("loc_ov_next").visible, false, "without the arrows")
    local _, h0 = Toolbox.Location.ContentSize()
    H.chat("/tbx location overlay off")
    H.advance(1)
    local _, hOff = Toolbox.Location.ContentSize()
    t.ok(h0 > hOff, "a line less with the setting off")
    H.chat("/tbx location overlay on")
    H.chat("/tbx overlay new Bank")
    H.chat("/tbx mark Vault")
    H.chat("/tbx overlay auto on")
    H.chat("/tbx overlay auto fights on")
    gather("Iron Ore", { 100, 0, 100 })
    kill("Elf Mage", { 300, 0, 300 })
    H.advance(31)                                         -- the marks saved
    H.chat("/tbx overlay bank")
    H.advance(2)
    t.eq(loc():Find("loc_overlay").text, "Map: Bank (1 place)")
    t.ok(loc():Find("loc_ov_next").visible ~= false, "the arrows now")
    local seen = {}
    for _ = 1, 5 do
      step("loc_ov_next")
      local shown = OV().Shown()
      seen[#seen + 1] = shown and shown.name or "none"
    end
    t.eq(table.concat(seen, ", "), "Gathering, Iron Ore, Fights, Elf Mage, none")
    H.advance(1)
    t.eq(loc():Find("loc_overlay").text, "Map: none (5 overlays)")
    step("loc_ov_next")
    t.eq(OV().Shown().name, "Bank", "round to the first again")
    step("loc_ov_prev")
    step("loc_ov_prev")
    t.eq(OV().Shown().name, "Elf Mage", "and back")
    -- clicked through quickly: the markers wait for the last click, then follow
    t.ok(marks()["ov1-1"], "Bank's marker still up right after the clicks")
    H.advance(3)
    t.no(marks()["ov1-1"], "then down")
    t.eq(marks()["ov" .. OV().Shown().id .. "-1"].label, "Elf Mage 1", "the shown one's up")
    t.eq(loc():Find("loc_overlay").text, "Map: Elf Mage (1 place)")
    -- not saved at each click: with the next batch, or at shutdown
    local function savedShown()
      local index = H.saved("map_overlays")
      return H.saved("map_scene:" .. index.scenes.Novia).shown
    end
    t.eq(savedShown(), byName("Bank").id, "not saved yet")
    H.advance(31)
    t.eq(savedShown(), OV().Shown().id, "saved with the batch")
    H.chat("/tbx overlay next")
    t.ok(H.logged("No overlay shown"), H.lastLog())
    H.chat("/tbx overlay prev")
    H.chat("/tbx overlay prev")
    t.ok(H.logged("Showing Fights"), H.lastLog())
    H.callback("ShroudOnDisableScript")
    H.restart()
    H.advance(2)
    t.eq(OV().Shown().name, "Fights", "the shutdown save keeps it")
    H.chat("/tbx location overlay off")
    H.advance(1)
    t.eq(loc():Find("loc_ov_row").visible, false, "the setting hides it")
    t.eq(H.saved("location").overlay, false)
  end)

  t.test("one overlay at a time: a switch takes the last one's marks down; other marks stay", function()
    H.boot()
    H.call(function() ShroudSetMapMarker("x-1", 1, 0, 1, { label = "Not ours" }) end)
    H.chat("/tbx overlay new Gathering")
    H.chat("/tbx mark Iron vein")
    H.chat("/tbx overlay new XP farming")
    t.ok(H.logged("Made XP farming, shown now"), H.lastLog())
    H.S.pos = { 50, 0, 50 }
    H.advance(1)
    H.chat("/tbx mark Skeletons")
    local now = marks()
    t.eq(count(now), 2, "the other mark and XP farming's one")
    t.ok(now["x-1"], "a mark not an overlay's left alone (the run flags')")
    t.eq(now["ov2-1"].label, "Skeletons")
    H.chat("/tbx overlay gathering")
    t.ok(H.logged("Showing Gathering"), H.lastLog())
    now = marks()
    t.eq(now["ov1-1"].label, "Iron vein")
    t.no(now["ov2-1"], "XP farming's down")
    H.chat("/tbx overlay off")
    t.eq(count(marks()), 1, "only the other one")
    t.eq(OV().Shown(), nil)
    H.chat("/tbx mark Here")
    t.ok(H.logged("Couldn't mark Here: show one of this scene's overlays first"),
      "no overlay made while others exist: " .. H.lastLog())
  end)

  t.test("each scene its own overlays: listed and shown only there, each scene's shown one remembered", function()
    H.boot()
    H.chat("/tbx overlay new Loot")
    H.chat("/tbx mark Novia bank")
    goTo("Owl's Head", { 10, 0, 10 })
    t.eq(#OV().List(), 0, "Novia's overlays aren't listed here")
    t.eq(OV().Shown(), nil)
    t.eq(count(marks("Owl'sHead")), 0)
    H.chat("/tbx overlay loot")
    t.ok(H.logged("No overlay called 'loot' in this scene"), H.lastLog())
    H.chat("/tbx overlay new Loot")
    t.ok(H.logged("Made Loot, shown now"), "the same name in another scene: " .. H.lastLog())
    H.chat("/tbx mark Owl bank")
    H.chat("/tbx overlay new Gathering")
    H.chat("/tbx mark Tree")
    local here = marks("Owl'sHead")
    t.eq(count(here), 1, "only the shown one's")
    goTo("Novia", { 0, 0, 0 })
    t.eq(OV().Shown().name, "Loot", "Novia's own shown overlay")
    t.eq(#OV().List(), 1)
    t.ok(marks("Novia")["ov1-1"], "Novia's place")
    H.chat("/tbx overlay")
    t.ok(H.logged("This scene's overlays: Loot %(1 place%) shown%."), H.lastLog())
    goTo("Owl's Head", { 10, 0, 10 })
    t.eq(OV().Shown().name, "Gathering", "Owl's Head kept its own")
  end)

  t.test("limits: 10 overlays, 39 places a scene (beside the run flags and the last death), unique names", function()
    H.boot()
    for i = 1, 10 do H.chat("/tbx overlay new Set " .. i) end
    H.chat("/tbx overlay new Set 11")
    t.ok(H.logged("this scene has 10 overlays"), H.lastLog())
    H.chat("/tbx overlay new set 3")
    t.ok(H.logged("already an overlay called set 3 here"), H.lastLog())
    for i = 1, 39 do H.chat("/tbx mark Spot " .. i) end
    H.chat("/tbx mark Spot 40")
    t.ok(H.logged("Couldn't mark Spot 40: Set 10 has 39 places %(the map's limit"), H.lastLog())
    t.eq(count(marks()), 39)
    goTo("Owl's Head")
    H.chat("/tbx mark Elsewhere")
    t.ok(H.logged("Marked Elsewhere"), "another scene has room: " .. H.lastLog())
  end)

  t.test("a refused change is tried again later; only what's missing is sent", function()
    H.boot()
    H.chat("/tbx overlay new Big")
    for i = 1, 30 do H.chat("/tbx mark Spot " .. i) end
    H.chat("/tbx overlay off")
    H.S.markerAllow = 10
    H.chat("/tbx overlay big")
    t.eq(count(marks()), 10, "ten up, then 'rate'")
    t.eq(OV().markerFailed, "rate")
    H.S.markerAllow = nil
    H.advance(5)
    t.eq(count(marks()), 10, "not before the retry")
    local sets = H.S.markerSets
    H.advance(OV().RETRY)
    t.eq(count(marks()), 30, "the rest")
    t.eq(H.S.markerSets - sets, 20, "the ten already up not sent again")
  end)

  t.test("kept across a reload and a relaunch; each character its own; a reset keeps them", function()
    H.boot()
    H.S.pos = { -2014.5, 12, -3015 }                -- negative numbers save (as text)
    H.advance(1)
    H.chat("/tbx overlay new Mining")
    H.chat("/tbx overlay icon star")
    H.chat("/tbx overlay color Red")
    H.chat("/tbx mark Deep vein")
    H.advance(31)
    H.restart()
    H.advance(2)
    local ov = OV().Shown()
    t.eq(ov and ov.name, "Mining")
    t.eq(OV().Places(ov)[1].x, -2014, "kept to the metre")
    local m = marks()["ov1-1"]
    t.eq(m.icon, "star")
    t.eq(m.color, "#e86050")
    H.logout()
    H.S.char.name = "Alt"
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(1)
    t.eq(#OV().List(), 0, "Alt has none")
    t.eq(count(marks()), 0, "and Mining's marks came down")
    H.logout()
    H.S.char.name = "Tester"
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(1)
    t.eq(OV().Shown().name, "Mining")
    H.chat("/tbx settings reset")
    H.reload()
    H.advance(2)
    t.eq(OV().Shown() and OV().Shown().name, "Mining", "a reset keeps them")
  end)

  t.test("mark remove / beacon: by name or the nearest; a beacon only in the place's scene", function()
    H.boot()
    H.S.pos = { 0, 0, 0 }
    H.advance(1)
    H.chat("/tbx mark Gate")
    H.S.pos = { 100, 0, 0 }
    H.advance(1)
    H.chat("/tbx mark Well")
    H.S.pos = { 95, 0, 5 }
    H.advance(1)
    H.chat("/tbx mark beacon")
    t.ok(H.logged("Your compass points at Well"), H.lastLog())
    t.eq(H.S.beacon[1], 100)
    H.chat("/tbx mark remove")
    t.ok(H.logged("Removed Well from Places"), H.lastLog())
    t.no(marks()["ov1-2"], "its marker down")
    H.chat("/tbx mark remove")
    t.ok(H.logged("no place of Places within 15 m"), H.lastLog())
    goTo("Owl's Head")
    H.chat("/tbx mark beacon gate")
    t.ok(H.logged("no overlay is shown in this scene"), "Novia's places aren't here: " .. H.lastLog())
    goTo("Novia")
    H.chat("/tbx overlay rename places = Town")
    t.ok(H.logged("Renamed it Town"), H.lastLog())
    H.chat("/tbx overlay delete town")
    t.ok(H.logged("Deleted Town and its 1 places"), H.lastLog())
    t.eq(#OV().List(), 0)
  end)

  t.test("the window: New, pick the one shown, Rename, Delete (second click)", function()
    H.boot()
    H.chat("/tbx overlay window")
    local w = H.S.windows.toolbox_marks
    t.eq(w:Find("mw_delete").enabled, false, "nothing shown: nothing to delete")
    H.submit("toolbox_marks", "mw_ovname", "Fishing")
    t.eq(w:Find("mw_pick").value, "Fishing", "made and shown")
    t.eq(w:Find("mw_ovname").text, "", "the box emptied")
    t.eq(w:Find("mw_delete").enabled, true)
    H.chat("/tbx mark Salt pier")
    t.ok(marks()["ov1-1"])
    H.change("toolbox_marks", "mw_pick", Toolbox.Overlays.MW_NONE)
    t.eq(OV().Shown(), nil)
    t.eq(count(marks()), 0)
    t.eq(w:Find("mw_rename").enabled, false)
    H.change("toolbox_marks", "mw_pick", "Fishing")
    w:Find("mw_ovname").text = "Sea fishing"
    H.click("toolbox_marks", "mw_rename")
    t.eq(w:Find("mw_pick").value, "Sea fishing")
    w:Find("mw_ovname").text = "Mining"
    H.click("toolbox_marks", "mw_new")
    t.eq(#OV().List(), 2)
    H.change("toolbox_marks", "mw_pick", "Sea fishing")
    H.click("toolbox_marks", "mw_delete")
    t.eq(#OV().List(), 2, "the first click only asks")
    t.eq(w:Find("mw_delete").text, "Click again to confirm")
    H.advance(Toolbox.Overlays.CONFIRM + 2)
    t.eq(w:Find("mw_delete").text, "Delete", "too late: back to Delete")
    H.click("toolbox_marks", "mw_delete")
    H.click("toolbox_marks", "mw_delete")
    t.eq(#OV().List(), 1)
    t.eq(OV().List()[1].name, "Mining")
  end)

  -- Owner, 2026-10-13: changing the shape and color for a new spot restyled the mark before it.
  t.test("each place keeps its own look: the shape and color apply to the next marks; Set look changes one", function()
    H.boot()
    H.chat("/tbx overlay new Gathering")
    H.chat("/tbx overlay window")
    H.change("toolbox_marks", "mw_icon", "star")
    H.change("toolbox_marks", "mw_color", "Red")
    H.submit("toolbox_marks", "mw_name", "Iron")
    H.change("toolbox_marks", "mw_icon", "circle")
    H.change("toolbox_marks", "mw_color", "Cyan")
    H.S.pos = { 30, 0, 30 }
    H.advance(1)
    H.submit("toolbox_marks", "mw_name", "Copper")
    local iron, copper = marks()["ov1-1"], marks()["ov1-2"]
    t.eq(iron.icon, "star", "the first keeps its shape")
    t.eq(iron.color, "#e86050", "and its color")
    t.eq(copper.icon, "circle")
    t.eq(copper.color, "#50d0d0")
    H.change("toolbox_marks", "mw_places", "Iron")
    H.click("toolbox_marks", "mw_look")
    t.eq(marks()["ov1-1"].icon, "circle", "Set look gives it the shape above")
    t.eq(marks()["ov1-1"].color, "#50d0d0")
    H.clearLogs()
    H.click("toolbox_marks", "mw_beacon")
    t.eq(H.S.beacon[4], "Iron")
    t.ok(H.logged("Your compass points at Iron"), "said in chat too: " .. H.lastLog())
    t.eq(H.S.windows.toolbox_marks:Find("mw_beacon"):GetText(), "Compass")
    H.S.beacon = nil
    H.chat("/tbx mark beacon copper")
    t.eq(H.S.beacon and H.S.beacon[4], "Copper", "the word before 1.8.0 still works")
    H.chat("/tbx overlay icon square")
    H.chat("/tbx mark look copper")
    t.eq(marks()["ov1-2"].icon, "square", "and mark look in chat")
    H.advance(31)
    H.restart()
    H.advance(2)
    t.eq(marks()["ov1-1"].icon, "circle", "kept")
    t.eq(marks()["ov1-2"].icon, "square")
  end)

  t.test("places saved without a look of their own take their overlay's", function()
    H.boot({ ["character:Tester"] = { map_overlays = { v = 1, shown = 1, nextId = 2, list = {
      { id = 1, name = "Old", icon = "diamond", color = "Purple", nextPlace = 2,
        places = { { id = 1, name = "Spot", raw = "Novia", scene = "Novia", x = 5, y = 0, z = 5 } } } } } } })
    H.advance(2)
    t.eq(marks()["ov1-1"].icon, "diamond")
    t.eq(marks()["ov1-1"].color, "#b878e8")
  end)

  -- The Map overlays window (owner, 2026-10-13: marking without the whole settings page up).
  local function pin() return H.S.frames.toolbox_location:Find("loc_pin") end
  local function clickPin()
    local b = pin()
    H.S.gesture = true
    H.call(b.onClick, b)
    H.S.gesture = false
  end
  local function mw() return H.S.windows.toolbox_marks end

  t.test("the location strip's pin opens the Map overlays window: mark, this scene's places, look, remove", function()
    H.boot()
    H.chat("/tbx location on")
    H.advance(1)
    t.ok(pin(), "a pin on the strip")
    clickPin()
    t.ok(mw() and mw():IsShown(), "the window")
    t.eq(mw():Find("mw_pick").value, Toolbox.Overlays.MW_NONE)
    t.eq(mw():Find("mw_beacon").enabled, false, "no places yet")
    H.submit("toolbox_marks", "mw_name", "Iron")
    t.eq(mw():Find("mw_pick").value, "Places", "the first mark made Places, shown")
    t.eq(mw():Find("mw_places").value, "Iron")
    t.ok(marks()["ov1-1"], "on the map")
    H.change("toolbox_marks", "mw_icon", "star")
    H.S.pos = { 40, 0, 40 }
    H.advance(1)
    H.click("toolbox_marks", "mw_mark")
    t.ok(H.S.windows.toolbox_marks:Find("mw_msg").text:find("Marked Place 2", 1, true), "an unnamed one")
    t.eq(marks()["ov1-2"].icon, "star")
    t.eq(marks()["ov1-1"].icon, "pin", "the first kept its look")
    H.change("toolbox_marks", "mw_places", "Iron")
    H.click("toolbox_marks", "mw_look")
    t.eq(marks()["ov1-1"].icon, "star")
    goTo("Owl's Head")
    t.eq(mw():Find("mw_places").value, Toolbox.Overlays.MW_NO_PLACES, "only this scene's places")
    t.eq(mw():Find("mw_remove").enabled, false)
    goTo("Novia")
    H.change("toolbox_marks", "mw_places", "Iron")
    H.click("toolbox_marks", "mw_remove")
    t.eq(#Toolbox.Overlays.Shown().places, 1)
    clickPin()
    t.no(mw():IsShown(), "the pin closes it again")
  end)

  t.test("the window shares the 8th window with Docs and the version window", function()
    H.boot()
    for _, c in ipairs({ "/tbx xp", "/tbx xpdetailed", "/tbx daily", "/tbx dd", "/tbx combat detail",
                         "/tbx notify show", "/tbx config" }) do H.chat(c) end
    H.chat("/tbx docs")
    H.chat("/tbx overlay window")
    t.ok(mw():IsShown())
    t.eq(H.S.windows.toolbox_docs, nil, "Docs gave its place")
    H.chat("/tbx version")
    t.eq(H.S.windows.toolbox_marks, nil, "and the window gave it to the version window")
    H.chat("/tbx overlay window")
    t.ok(mw():IsShown(), "back")
  end)

  t.test("the pin can be switched off; the settings page opens the window too", function()
    H.boot()
    H.chat("/tbx location on")
    H.chat("/tbx location pin off")
    H.advance(1)
    t.eq(pin(), nil, "no pin")
    H.chat("/tbx location pin on")
    H.advance(1)
    t.ok(pin())
    H.chat("/tbx config")
    H.click("toolbox_config", "ov_window")
    t.ok(mw() and mw():IsShown())
    H.reload()
    H.advance(1)
    t.ok(pin(), "kept")
  end)

  t.test("an older client without map markers: places still kept, the beacon finds them", function()
    H.boot()
    H.S.noMarkers = true
    H.reload()
    H.chat("/tbx mark Camp")
    t.ok(H.logged("can't show it on the map yet"), H.lastLog())
    H.chat("/tbx mark beacon camp")
    t.ok(H.logged("Your compass points at Camp"), H.lastLog())
  end)

  t.test("a refused save changes nothing: not live, and not smuggled in by the next save that works", function()
    H.boot()
    H.chat("/tbx overlay new Real")
    H.chat("/tbx mark Bank")
    local real = OV().Shown()
    H.S.refuseKeys = REFUSE_ALL
    H.chat("/tbx overlay new Ghost")
    t.ok(H.logged("Couldn't make it: the game refused to save it"), H.lastLog())
    t.eq(#OV().List(), 1, "Ghost isn't kept")
    t.eq(OV().Shown(), real, "Real still shown")
    H.chat("/tbx overlay rename Real = Fake")
    t.ok(H.logged("Couldn't rename it: the game refused to save it"), H.lastLog())
    t.eq(real.name, "Real")
    H.chat("/tbx overlay color red")
    t.ok(H.logged("Couldn't change it"), H.lastLog())
    H.chat("/tbx mark look bank")
    t.ok(H.logged("Couldn't change it"), H.lastLog())
    H.chat("/tbx mark Vein")
    t.ok(H.logged("Couldn't mark Vein: the game refused to save it"), H.lastLog())
    H.chat("/tbx mark remove bank")
    t.ok(H.logged("Couldn't remove it"), H.lastLog())
    H.chat("/tbx overlay off")
    t.ok(H.logged("Couldn't hide it"), H.lastLog())
    H.chat("/tbx overlay delete real")
    t.ok(H.logged("Couldn't delete it"), H.lastLog())
    t.eq(#real.places, 1, "Bank kept")
    t.eq(real.places[1].color, "Green")
    t.ok(marks()["ov" .. real.id .. "-1"], "its marker still up")
    H.S.refuseKeys = nil
    H.chat("/tbx overlay icon star")              -- a save that works: only this change goes with it
    local saved = savedOV().scenes.Novia
    t.eq(#saved.list, 1)
    t.eq(saved.list[1].name, "Real")
    t.eq(saved.list[1].icon, "star")
    t.eq(saved.list[1].color, "Green")
    t.ok(saved.list[1].places:find("^1|Bank|"), "Bank, packed: " .. saved.list[1].places)
    t.no(saved.list[1].places:find(";"), "one place")
    t.eq(saved.shown, real.id)
    H.reload()
    t.eq(#OV().List(), 1)
    t.eq(OV().Shown().name, "Real")
  end)

  t.test("a refused save in the window says so; the controls show what is kept", function()
    H.boot()
    H.chat("/tbx overlay new Real")
    H.chat("/tbx mark Bank")
    H.chat("/tbx overlay window")
    H.S.refuseKeys = REFUSE_ALL
    H.change("toolbox_marks", "mw_color", "Red")
    t.ok(mw():Find("mw_msg"):GetText():find("Couldn't change it", 1, true), mw():Find("mw_msg"):GetText())
    t.eq(mw():Find("mw_color"):GetValue(), "Green", "put back")
    H.click("toolbox_marks", "mw_delete")
    H.click("toolbox_marks", "mw_delete")
    t.ok(mw():Find("mw_msg"):GetText():find("Couldn't delete it", 1, true), mw():Find("mw_msg"):GetText())
    t.eq(OV().Shown().name, "Real")
    H.click("toolbox_marks", "mw_remove")
    t.ok(mw():Find("mw_msg"):GetText():find("Couldn't remove it", 1, true), mw():Find("mw_msg"):GetText())
    t.eq(#OV().Shown().places, 1)
    H.S.refuseKeys = nil
  end)

  t.test("renaming an overlay renames its markers' note at once (and after a reload)", function()
    H.boot()
    H.chat("/tbx overlay new Places")
    H.chat("/tbx mark Bank")
    local id = "ov" .. OV().Shown().id .. "-1"
    t.eq(marks()[id].note, "Places")
    H.chat("/tbx overlay rename Places = Town")
    t.eq(marks()[id].note, "Town")
    H.reload()
    H.advance(1)
    t.eq(marks()[id].note, "Town")
  end)

  t.test("a mark past the map storage is refused, naming the mark; nothing saved; the window says so too", function()
    H.boot()
    H.chat("/tbx mark Bank")
    local budget = OV().BUDGET
    OV().BUDGET = math.floor(OV().StorageUse() * budget) + 10      -- room for nothing more
    local before = savedOV()
    H.chat("/tbx mark Iron vein")
    t.ok(H.logged("Couldn't mark Iron vein: map storage is full%. Nothing was saved, and your other places are"
      .. " safe%. Remove places, or a scene's overlays %(/toolbox overlay scenes%), to make room%."), H.lastLog())
    t.eq(#OV().Places(OV().Shown()), 1, "only Bank")
    t.eq(savedOV().scenes.Novia.list[1].places, before.scenes.Novia.list[1].places, "not saved")
    H.chat("/tbx overlay window")
    H.submit("toolbox_marks", "mw_name", "Iron vein")
    t.ok(mw():Find("mw_msg"):GetText():find("Couldn't mark Iron vein: map storage is full", 1, true),
      mw():Find("mw_msg"):GetText())
    t.ok(mw():Find("mw_storage"):GetText():find("^Map storage: %d+%% used$"), mw():Find("mw_storage"):GetText())
    H.chat("/tbx mark remove bank")
    t.ok(H.logged("Removed Bank"), "a change that frees room still saves: " .. H.lastLog())
    OV().BUDGET = budget
    H.chat("/tbx mark Gate")
    local size = OV().StorageUse() * budget                -- with Gate
    H.chat("/tbx mark remove gate")
    OV().BUDGET = math.floor(size / 0.95)                  -- Gate again takes it to 95%
    H.chat("/tbx mark Gate")
    t.ok(H.logged("Marked Gate in Places.*Map storage is %d+%% full: remove places you don't need"), H.lastLog())
    OV().BUDGET = budget
  end)

  t.test("1.8.0 development saves (one list, places with their scene) become one overlay per scene", function()
    H.boot({ ["character:Tester"] = { map_overlays = { v = 1, shown = 7, nextId = 9, list = {
      { id = 7, name = "Loot", icon = "star", color = "Red", nextPlace = 3, places = {
        { id = 1, name = "Bank", raw = "Novia", scene = "Novia", x = 10.4, y = 1, z = "%N-20.6", icon = "flag",
          color = "Blue" },
        { id = 2, name = "Camp", raw = "Owl'sHead", scene = "Owl's Head", x = 5, y = 0, z = 5 } } },
      { id = 8, name = "Empty", icon = "pin", color = "Green", nextPlace = 1, places = {} } }, ["%E"] = 1 } } })
    H.advance(1)
    local ov = OV().Shown()
    t.eq(ov and ov.name, "Loot", "shown in Novia")
    local places = OV().Places(ov)
    t.eq(#places, 1)
    t.eq(places[1].name, "Bank")
    t.eq(places[1].icon, "flag")
    t.eq(H.saved("map_overlays").v, 3, "saved in the new form at once")
    t.eq(#OV().List(), 1, "an overlay with no places has no scene: left out")
    goTo("Owl's Head")
    t.eq(OV().Shown().name, "Loot", "its Owl's Head part, shown there too")
    t.eq(OV().Places(OV().Shown())[1].name, "Camp")
    t.eq(OV().Places(OV().Shown())[1].icon, "star", "the overlay's look for a place without its own")
  end)

  t.test("overlay scenes lists every scene's room; forget deletes a scene's overlays after a second time", function()
    H.boot()
    H.chat("/tbx mark Bank")
    goTo("Owl's Head")
    H.chat("/tbx mark Camp")
    H.chat("/tbx mark Well")
    H.chat("/tbx overlay scenes")
    t.ok(H.logged("^Map storage: %d+%% used, in 2 scenes:"), H.logs()[#H.logs() - 3])
    t.ok(H.logged("  Owl's Head: 1 overlay, 2 places"), "the biggest first")
    t.ok(H.logged("  Novia: 1 overlay, 1 place "))
    H.chat("/tbx overlay forget novia")
    t.ok(H.logged("This deletes Novia's 1 overlay and 1 place%. Type it again within 10 s"), H.lastLog())
    H.advance(11)
    H.chat("/tbx overlay forget novia")
    t.ok(H.logged("Type it again"), "too late: asked again")
    H.chat("/tbx overlay forget novia")
    t.ok(H.logged("Deleted Novia's overlays"), H.lastLog())
    goTo("Novia")
    t.eq(#OV().List(), 0)
    t.eq(savedOV().scenes.Novia, nil)
    H.chat("/tbx overlay forget Atlantis")
    t.ok(H.logged("No overlays in a scene called 'Atlantis'"), H.lastLog())
  end)

  t.test("a scene's places are read only when you're there", function()
    H.boot()
    H.chat("/tbx mark Bank")
    goTo("Owl's Head")
    H.chat("/tbx mark Camp")
    H.restart(nil, true)                         -- back in Novia
    H.advance(1)
    t.eq(rawget(OV().List("Owl'sHead")[1], "places"), nil, "Owl's Head's still packed")
    t.ok(rawget(OV().Shown(), "places"), "Novia's read: its markers are up")
    goTo("Owl's Head")
    t.ok(marks("Owl'sHead")["ov2-1"], "read on arriving")
  end)

  t.test("map storage is measured as saved: escaped names count at their saved length (review 37)", function()
    H.boot()
    H.chat("/tbx overlay new %%%%%%%%%%%%")
    for i = 1, 5 do H.chat("/tbx mark %%%%%%%%%%%% " .. i) end
    t.near(OV().StorageUse() * OV().BUDGET, savedSize(), 1e-6, "the saved form's size")
    H.restart(nil, true)
    H.advance(1)
    t.near(OV().StorageUse() * OV().BUDGET, savedSize(), 1e-6,
      "read back the same")
  end)

  t.test("a first mark that won't fit saves nothing, not even its overlay, and names the mark (review 38)", function()
    H.boot()
    H.chat("/tbx mark Bank")                          -- Novia's, so storage has something
    goTo("Owl's Head")
    local budget = OV().BUDGET
    OV().BUDGET = math.floor(OV().StorageUse() * budget) + 90        -- an empty overlay fits, a place with it not
    H.chat("/tbx mark Iron vein")
    t.ok(H.logged("Couldn't mark Iron vein: map storage is full"), H.lastLog())
    t.eq(#OV().List(), 0, "no Places overlay left behind")
    t.eq(savedOV().scenes["Owl'sHead"], nil, "nor saved")
    H.chat("/tbx overlay window")
    H.submit("toolbox_marks", "mw_name", "Camp")
    t.ok(mw():Find("mw_msg"):GetText():find("Couldn't mark Camp: map storage is full", 1, true),
      mw():Find("mw_msg"):GetText())
    t.eq(#OV().List(), 0)
    OV().BUDGET = budget
    H.chat("/tbx mark Iron vein")
    t.ok(H.logged("Marked Iron vein in Places"), H.lastLog())
  end)

  -- one key a scene ------------------------------------------------------------

  -- The overlay keys written while `fn` runs.
  local function writes(fn)
    local keys, real = {}, ShroudSetSavedVar
    ShroudSetSavedVar = function(key, ...)
      if key == "map_overlays" or key:find("^map_scene:") then keys[#keys + 1] = key end
      return real(key, ...)
    end
    local ok, err = pcall(fn)
    ShroudSetSavedVar = real
    if not ok then error(err, 0) end
    return keys
  end

  t.test("one key a scene: a change writes only its scene's key (and the index when that changes)", function()
    H.boot()
    H.chat("/tbx mark Bank")
    goTo("Owl's Head")
    H.chat("/tbx mark Camp")
    local index = H.saved("map_overlays")
    t.eq(index.v, 3)
    local novia, owls = index.scenes.Novia, index.scenes["Owl'sHead"]
    t.ok(novia and owls and novia ~= owls, "a key each")
    local keys = writes(function() H.chat("/tbx mark Well") end)
    t.eq(table.concat(keys, ","), "map_scene:" .. owls, "only Owl's Head's: " .. table.concat(keys, ","))
    keys = writes(function() H.chat("/tbx overlay new Mine") end)      -- a new overlay id: the index too
    t.eq(table.concat(keys, ","), "map_scene:" .. owls .. ",map_overlays", table.concat(keys, ","))
    t.eq(savedOV().scenes.Novia.list[1].places:match("^1|Bank|") ~= nil, true, "Novia's untouched")
    H.restart(nil, true)
    H.advance(1)
    t.eq(Toolbox.fileUse.character.keys["map_scene:" .. owls] ~= nil, true, "each scene's key measured at start")
    goTo("Owl's Head")
    t.eq(#OV().List(), 2, "read back")
    t.ok(OV().FindPlace(OV().Find("Places"), "Well"))
    H.chat("/tbx overlay forget owl's head")
    H.chat("/tbx overlay forget owl's head")
    t.eq(ShroudGetSavedVar("map_scene:" .. owls), nil, "a scene forgotten: its key deleted")
    t.eq(H.saved("map_overlays").scenes["Owl'sHead"], nil, "and out of the index")
  end)

  t.test("one key a scene: 1.8.0's single key is converted at the first start; refused, it stays as it was", function()
    local v2 = { v = 2, nextId = 3, ignore = { "Corpse" }, scenes = {
      Novia = { scene = "Novia", shown = 1, auto = true, list = {
        { id = 1, name = "Loot", icon = "star", color = "Red", nextPlace = 2, places = "1|Bank|10|1|-20|5|4" } } },
      ["Owl'sHead"] = { scene = "Owl's Head", shown = 0, fights = true, list = {
        { id = 2, name = "Camps", icon = "pin", color = "Blue", nextPlace = 2, places = "1|Camp|5|0|5|1|2" } } } },
      ["%E"] = 1 }
    H.boot()
    ShroudSetSavedVar("map_overlays", v2)          -- a 1.8.0 file, read at the next start
    H.S.refuseKeys = setmetatable({}, { __index = function(_, key) return key:find("^map_scene:") ~= nil end })
    H.reload()
    H.advance(1)
    t.eq(H.saved("map_overlays").v, 2, "a scene refused: the old key put back")
    t.eq(OV().Shown().name, "Loot", "and the overlays work meanwhile")
    H.S.refuseKeys = nil
    H.restart(nil, true)
    H.advance(1)
    local index = H.saved("map_overlays")
    t.eq(index.v, 3, "converted")
    t.eq(index.ignore[1], "Corpse")
    local saved = savedOV()
    t.eq(saved.scenes.Novia.list[1].places, "1|Bank|10|1|-20|5|4")
    t.eq(saved.scenes.Novia.auto, true)
    t.eq(saved.scenes["Owl'sHead"].fights, true)
    H.restart(nil, true)
    H.advance(1)
    t.eq(OV().Places(OV().Shown())[1].name, "Bank", "read back from today's form")
    t.ok(OV().AutoOn())
    goTo("Owl's Head")
    t.ok(OV().AutoOn(nil, true))
    t.eq(OV().Places(OV().Find("Camps"))[1].name, "Camp")
  end)

  t.test("one key a scene: a batch over two scenes, one refused, puts the other back as it was", function()
    H.boot()
    H.advance(1)
    H.chat("/tbx overlay auto on")
    gather("Iron Ore", { 10, 0, 10 })
    goTo("Owl's Head", { 0, 0, 0 })
    H.chat("/tbx overlay auto on")
    H.callback("ShroudOnDisableScript")
    local index = H.saved("map_overlays")
    local novia, owls = index.scenes.Novia, index.scenes["Owl'sHead"]
    local before = savedOV().scenes.Novia.list
    gather("Oak Tree", { 30, 0, 10 })
    goTo("Novia", { 0, 0, 0 })
    gather("Iron Ore", { 90, 0, 10 })
    H.S.refuseKeys = { ["map_scene:" .. math.max(novia, owls)] = true }
    H.advance(OV().SAVE_AFTER + 1)
    t.ok(H.logged("couldn't be saved"), H.lastLog())
    H.S.refuseKeys = nil
    local after = savedOV().scenes
    t.eq(#after.Novia.list, #before, "Novia's key as it was")
    for i, o in ipairs(before) do t.eq(after.Novia.list[i].places, o.places) end
    t.eq(after["Owl'sHead"].list[1], nil, "Owl's Head's too")
  end)

  t.test("one key a scene: a big 1.8.0 key whose conversion is refused part way survives whole (review 60)", function()
    local function bigPlaces(tag)
      local each = {}
      for i = 1, 2300 do each[i] = string.format("%d|%s place number %04d|%d|0|%d|1|1", i, tag, i, i, i) end
      return table.concat(each, ";")
    end
    local v2 = { v = 2, nextId = 3, ignore = {}, scenes = {
      Novia = { scene = "Novia", shown = 1, list = {
        { id = 1, name = "North", icon = "pin", color = "Red", nextPlace = 2301, places = bigPlaces("North") } } },
      ["Owl'sHead"] = { scene = "Owl's Head", shown = 2, list = {
        { id = 2, name = "South", icon = "pin", color = "Blue", nextPlace = 2301, places = bigPlaces("South") } } } },
      ["%E"] = 1 }
    H.boot()
    t.ok(Toolbox.SavedSize(v2) > 200000, "near the file's limit: " .. Toolbox.SavedSize(v2))
    ShroudSetSavedVar("map_overlays", v2)
    H.callback("ShroudOnDisableScript")
    local n = 0
    H.S.refuseKeys = setmetatable({}, { __index = function(_, key)
      if key:find("^map_scene:") then
        n = n + 1
        return n >= 2                                -- the second scene refused, after the first was written
      end
      return false
    end })
    H.reload()
    H.advance(1)
    H.S.refuseKeys = nil
    t.ok(n >= 2, "a scene was refused")
    t.eq(H.saved("map_overlays").v, 2, "the old key back")
    t.eq(next(Toolbox.saveRefused), nil, "every undo taken: " .. tostring(next(Toolbox.saveRefused)))
    H.restart(nil, true)                             -- flushed: what reached the disk
    H.advance(1)
    local saved = savedOV()
    t.eq(saved.v, 3, "converted at the next start")
    t.eq(saved.scenes.Novia.list[1].places, v2.scenes.Novia.list[1].places, "Novia's whole")
    t.eq(saved.scenes["Owl'sHead"].list[1].places, v2.scenes["Owl'sHead"].list[1].places, "Owl's Head's whole")
  end)

  t.test("one key a scene: a scene's key the game won't delete keeps the scene, measured (review 61)", function()
    H.boot()
    H.chat("/tbx mark Bank")
    local key = "map_scene:" .. H.saved("map_overlays").scenes.Novia
    H.S.deleteRefuse = { [key] = true }
    H.chat("/tbx overlay forget novia")
    H.chat("/tbx overlay forget novia")
    t.ok(H.logged("Couldn't"), H.lastLog())
    t.ok(H.saved("map_overlays").scenes.Novia, "still in the index")
    t.ok(Toolbox.fileUse.character.keys[key], "and measured")
    t.eq(#OV().List(), 1, "and kept")
    H.S.deleteRefuse = nil
    H.chat("/tbx overlay forget novia")
    H.chat("/tbx overlay forget novia")
    t.eq(ShroudGetSavedVar(key), nil, "deleted")
    t.eq(Toolbox.fileUse.character.keys[key], nil)
    t.eq(H.saved("map_overlays").scenes.Novia, nil)
  end)
end
