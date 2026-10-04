-- Today's crafting and gathering (API 18 result events): the day's counts (Toolbox.Daily) and Today
-- Detailed's Looted / Crafted / Gathered views.
local H = require("harness")

return function(t)
  local D = function() return Toolbox.Daily end
  local DD = function() return Toolbox.DailyDetail end
  local function day() return Toolbox.Daily.day end

  -- As in game (2026-09-29): `item` is the recipe's name, `crafted` counts crafts.
  local function craft(recipe, crafted, exc, failed, xp)
    return { kind = "craft", recipeId = 7, recipeName = "Recipe: " .. recipe, item = "Recipe: " .. recipe,
             quantity = crafted + (failed or 0), crafted = crafted, exceptional = exc or 0, failed = failed or 0,
             outcome = "success", experience = xp or 1000, items = {} }
  end

  local function rows()
    local out = {}
    for _, r in ipairs(H.detailRows()) do out[#out + 1] = r[1] .. "=" .. r[2] end
    return table.concat(out, ", ")
  end

  -- model ---------------------------------------------------------------------

  t.test("RecipeName drops only the 'Recipe: ' prefix", function()
    H.boot()
    t.eq(D().RecipeName("Recipe: Crimson Pine Board"), "Crimson Pine Board")
    t.eq(D().RecipeName("Recipe: Crimson Pine Binding (Milling)"), "Crimson Pine Binding (Milling)")
    t.eq(D().RecipeName("Iron Ingot"), "Iron Ingot")
    t.eq(D().RecipeName("Recipe: "), nil)
    t.eq(D().RecipeName(nil), nil)
  end)

  t.test("craft results: crafts, exceptional, failed and XP, per recipe and in total", function()
    H.boot()
    local d = D().New("k")
    t.ok(D().AddCraftResults(d, { craft("Crimson Pine Board", 1, 0, 0, 9000),
                                  craft("Crimson Pine Board", 10, 3, 2, 0),        -- a Quick Craft group
                                  { kind = "refine", recipeName = "Recipe: Iron Ingot", crafted = 5, exceptional = 0,
                                    failed = 0, experience = 500 },
                                  { kind = "salvage", item = "Iron Sword", quantity = 1, experience = 50,
                                    items = { { name = "Iron Ingot", quantity = 2 } } } }))
    t.eq(d.craft.n, 16)
    t.eq(d.craft.exc, 3)
    t.eq(d.craft.fail, 2)
    t.eq(d.craft.salvaged, 1)
    t.eq(d.craft.xp, 9550)
    t.eq(d.recipes["Crimson Pine Board"].n, 11)
    t.eq(d.recipes["Crimson Pine Board"].exc, 3)
    t.eq(d.recipes["Iron Ingot"].n, 5)
    t.eq(next(d.crafted), nil, "what was made is counted as it reaches the bags, not from the result")
    t.no(D().AddCraftResults(d, { { kind = "mystery" } }), "an unknown kind counts nothing")
  end)

  t.test("gather results: nodes, failures, XP and the items the node held", function()
    H.boot()
    local d = D().New("k")
    D().AddGatherResults(d, { { node = "Cotton Plant", failed = false, experience = 2000,
                                items = { { name = "Raw Cotton", quantity = 2 },
                                          { name = "Hopper (Bait)", quantity = 1 } } },
                              { node = "Iron Ore", failed = true, experience = 0, items = {} } })
    t.eq(d.gather.nodes, 2)
    t.eq(d.gather.failed, 1)
    t.eq(d.gather.xp, 2000)
    t.eq(d.gathered["Raw Cotton"], 2)
    t.eq(d.gathered["Hopper (Bait)"], 1)
  end)

  t.test("the looted count leaves out what was made or gathered, never below 0", function()
    H.boot()
    local d = D().New("k")
    d.items = { ["Raw Cotton"] = 5, ["Crimson Pine Board"] = 2, ["Wolf Pelt"] = 1 }
    d.gathered = { ["Raw Cotton"] = 3 }
    d.crafted = { ["Crimson Pine Board"] = 4 }             -- more than gained (taken off a station, then sold)
    t.eq(D().Looted(d, "Raw Cotton"), 2)
    t.eq(D().Looted(d, "Crimson Pine Board"), 0)
    t.eq(D().Looted(d, "Wolf Pelt"), 1)
  end)

  t.test("an older day without the new fields is filled in; bad entries are dropped, not the day", function()
    H.boot({ ["character:Tester"] = { daily = { v = 1, key = "local:2026-09-27", gold = 5, kills = 1, a = 0, p = 0,
      items = { Ore = 2 }, dropped = 0, last = {},
      crafted = { Board = 2, Bad = "x" }, recipes = { Board = { n = 2, exc = "?" }, [5] = {} },
      gather = { nodes = 3, xp = -1 } } } })
    t.eq(day().gold, 5, "the day kept")
    t.eq(day().crafted.Board, 2)
    t.eq(day().crafted.Bad, nil)
    t.eq(day().recipes.Board.exc, 0)
    t.eq(day().gather.nodes, 3)
    t.eq(day().gather.xp, 0)
    t.eq(day().craft.n, 0)
    t.eq(next(day().gathered), nil)
  end)

  t.test("midnight clears the crafting and gathering counts too", function()
    H.boot()
    H.craftResults({ craft("Board", 2) })
    H.gatherResults({ { node = "Tree", failed = false, experience = 5, items = { { name = "Log", quantity = 1 } } } })
    H.S.date = "2026-09-28"
    H.advance(1)
    t.eq(day().craft.n, 0)
    t.eq(day().gather.nodes, 0)
    t.eq(next(day().recipes), nil)
    t.eq(next(day().gathered), nil)
  end)

  t.test("off a station: named like a crafted recipe is made; anything else is kept apart", function()
    H.boot()
    H.craftResults({ craft("Crimson Pine Binding (Milling)", 1) })
    H.craftingState({ open = true, station = "Milling Station +5", busy = false })
    H.items({ { "Crimson Pine Binding", 4 }, { "Crimson Pine Timber", 3 }, { "Wax", 1 } })   -- product + materials back
    H.craftingState({ open = false, station = "", busy = false })
    H.items({ { "Wolf Pelt", 1 } })
    t.eq(day().crafted["Crimson Pine Binding"], 4, "the product (recipe name + station in brackets)")
    t.eq(day().crafted["Crimson Pine Timber"], nil, "a material taken back isn't made")
    t.eq(day().station["Crimson Pine Timber"], 3)
    t.eq(day().station["Wax"], 1)
    t.eq(day().station["Wolf Pelt"], nil, "not at a station")
    t.eq(D().Looted(day(), "Crimson Pine Timber"), 0, "and not loot either")
    t.eq(day().items["Crimson Pine Board"], nil)
  end)

  t.test("a reload at a station reads the crafting window's state", function()
    H.boot()
    H.craftResults({ craft("Iron Ingot", 5) })
    H.advance(1)                                             -- saved with the next tick
    H.S.craftingState = { open = true, station = "Smelter", busy = false }
    H.reload()
    H.items({ { "Iron Ingot", 5 } })
    t.eq(day().crafted["Iron Ingot"], 5)
  end)

  t.test("once the client names the product in `item`, that name counts as made", function()
    H.boot()
    local r = craft("Crimson Pine Binding (Milling)", 1)
    r.item = "Crimson Pine Binding Kit"                      -- a product not named like its recipe
    H.craftResults({ r })
    t.ok(day().products["Crimson Pine Binding Kit"])
    H.craftResults({ craft("Crimson Pine Board", 1) })       -- as today: item = "Recipe: ...", not a product
    t.eq(day().products["Recipe: Crimson Pine Board"], nil)
    H.craftingState({ open = true, station = "Milling Station +5", busy = false })
    H.items({ { "Crimson Pine Binding Kit", 1 } })
    t.eq(day().crafted["Crimson Pine Binding Kit"], 1)
  end)

  t.test("IsProduct and moving earlier miscounted materials out of made", function()
    H.boot()
    local d = D().New("k")
    d.recipes = { ["Crimson Pine Board"] = { n = 1, exc = 0, fail = 0 },
                  ["Crimson Pine Binding (Milling)"] = { n = 1, exc = 0, fail = 0 } }
    t.ok(D().IsProduct(d, "Crimson Pine Board"))
    t.ok(D().IsProduct(d, "Crimson Pine Binding"))
    t.no(D().IsProduct(d, "Crimson Pine"), "a shorter name isn't")
    t.no(D().IsProduct(d, "Wax"))
    d.crafted = { ["Crimson Pine Binding"] = 4, ["Crimson Pine Timber"] = 3 }
    D().Reclassify(d)
    t.eq(d.crafted["Crimson Pine Binding"], 4)
    t.eq(d.crafted["Crimson Pine Timber"], nil)
    t.eq(d.station["Crimson Pine Timber"], 3)
  end)

  t.test("a saved day that counted materials as made is corrected when it loads", function()
    H.boot({ ["character:Tester"] = { daily = { v = 1, key = "local:2026-09-27", gold = 0, kills = 0, a = 0, p = 0,
      items = { ["Crimson Pine Binding"] = 4, Wax = 1 }, dropped = 0, last = {},
      crafted = { ["Crimson Pine Binding"] = 4, Wax = 1 },
      recipes = { ["Crimson Pine Binding (Milling)"] = { n = 1, exc = 0, fail = 0 } } } } })
    t.eq(day().crafted.Wax, nil)
    t.eq(day().station.Wax, 1)
    t.eq(day().crafted["Crimson Pine Binding"], 4)
  end)

  t.test("materials used: the recipe's ingredients times the crafts attempted, not tools or optional ones", function()
    H.boot()
    H.S.recipes = { [7] = { id = 7, name = "Crimson Pine Binding", ingredients = {
      { name = "Crimson Pine Timber", quantity = 2, have = 10, optional = false, tool = false },
      { name = "Wax", quantity = 1, have = 5, optional = false, tool = false },
      { name = "Carpentry Hammer", quantity = 1, have = 1, optional = false, tool = true },
      { name = "Glue", quantity = 1, have = 0, optional = true, tool = false } } } }
    H.craftResults({ craft("Crimson Pine Binding (Milling)", 1) })
    H.craftResults({ craft("Crimson Pine Binding (Milling)", 8, 0, 2) })     -- a Quick Craft group of 10
    t.eq(day().used["Crimson Pine Timber"], 22)
    t.eq(day().used["Wax"], 11)
    t.eq(day().used["Carpentry Hammer"], nil, "a tool isn't used up")
    t.eq(day().used["Glue"], nil, "an optional ingredient: unknown whether it went in")
    H.S.recipes = nil                                         -- a recipe not known: nothing to add
    H.craftResults({ craft("Crimson Pine Binding (Milling)", 1) })
    t.eq(day().used["Wax"], 11)
  end)

  -- API 24: the result names the product (`item`), how many were made (`made`) and everything it put out.
  local function craft24(recipe, product, crafted, made, items, extra)
    local r = { kind = "craft", recipeId = 7, recipeName = recipe, item = product, quantity = crafted,
                crafted = crafted, exceptional = 0, failed = 0, made = made, outcome = "success",
                experience = 1000, items = items or { { name = product, quantity = made } } }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  local function atStation(list)
    H.craftingState({ open = true, station = "Milling Station +5", busy = false })
    H.items(list)
    H.craftingState({ open = false, station = "", busy = false })
  end

  t.test("API 24: made counts at once, and taking it off the station doesn't count it again", function()
    H.boot()
    H.craftResults({ craft24("Crimson Pine Binding (Milling)", "Crimson Pine Binding", 1, 4) })
    t.eq(day().crafted["Crimson Pine Binding"], 4, "4 bindings from one craft, before they're taken")
    t.eq(day().recipes["Crimson Pine Binding (Milling)"].n, 1, "one craft")
    t.eq(D().Looted(day(), "Crimson Pine Binding"), 0)
    H.items({ { "Crimson Pine Binding", 2 } })                  -- the same name looted meanwhile
    t.eq(D().Looted(day(), "Crimson Pine Binding"), 2, "still on the table doesn't hide real loot")
    atStation({ { "Crimson Pine Binding", 4 }, { "Crimson Pine Timber", 3 } })
    t.eq(day().crafted["Crimson Pine Binding"], 4, "not counted twice")
    t.eq(day().station["Crimson Pine Timber"], 3, "materials taken back: apart, as before")
    t.eq(D().Looted(day(), "Crimson Pine Binding"), 2)
    t.eq(next(day().pending), nil, "nothing left waiting")
  end)

  t.test("API 24: leftovers, a failed craft, a Quick Craft group and exceptional results", function()
    H.boot()
    H.craftResults({ craft24("Healing Potion", "Healing Potion", 1, 1,
      { { name = "Healing Potion", quantity = 1 }, { name = "Empty Vial", quantity = 1 } }) })
    t.eq(day().crafted["Healing Potion"], 1)
    t.eq(day().crafted["Empty Vial"], nil, "a leftover isn't made")
    t.eq(day().station["Empty Vial"], 1)
    H.craftResults({ craft24("Iron Ingot", "Iron Ingot", 0, 0, { { name = "Iron Ore", quantity = 1 } },
      { failed = 1, quantity = 1, outcome = "failed" }) })
    t.eq(day().crafted["Iron Ingot"], nil, "a failure made nothing")
    t.eq(day().station["Iron Ore"], 1, "its leftovers are apart")
    t.eq(day().craft.fail, 1)
    H.craftResults({ craft24("Iron Ingot", "Iron Ingot", 10, 13, nil,
      { exceptional = 3, quantity = 10, outcome = "mixed" }) })
    t.eq(day().crafted["Iron Ingot"], 13, "a Quick Craft group: every item made, exceptional included")
    t.eq(day().craft.n, 11)
    t.eq(day().craft.exc, 3)
    atStation({ { "Healing Potion", 1 }, { "Empty Vial", 1 }, { "Iron Ore", 1 }, { "Iron Ingot", 13 } })
    t.eq(day().crafted["Iron Ingot"], 13)
    t.eq(day().station["Empty Vial"], 1)
    t.eq(next(day().pending), nil)
  end)

  t.test("API 24: the recipe's fixed yield marks other products; no items list falls back to item x made", function()
    H.boot()
    H.S.recipes = { [7] = { id = 7, name = "Leather Kit", ingredients = {},
                            results = { { name = "Leather Strap", quantity = 2 },
                                        { name = "Leather Patch", quantity = 1 } } } }
    H.craftResults({ craft24("Leather Kit", "Leather Strap", 1, 3,
      { { name = "Leather Strap", quantity = 2 }, { name = "Leather Patch", quantity = 1 } }) })
    t.eq(day().crafted["Leather Strap"], 2)
    t.eq(day().crafted["Leather Patch"], 1, "named by the recipe's results")
    t.ok(day().products["Leather Patch"])
    H.S.recipes = nil
    H.craftResults({ craft24("Board", "Crimson Pine Board", 1, 2, {}) })
    t.eq(day().crafted["Crimson Pine Board"], 2, "an empty list: item x made")
  end)

  t.test("API 24: taken off the station before its result arrives, still counted once", function()
    H.boot()
    atStation({ { "Crimson Pine Board", 2 } })               -- no recipe crafted yet: kept apart by name
    t.eq(day().station["Crimson Pine Board"], 2)
    H.craftResults({ craft24("Crimson Pine Board", "Crimson Pine Board", 1, 2) })
    t.eq(day().crafted["Crimson Pine Board"], 2, "the result moves it to made")
    t.eq(day().station["Crimson Pine Board"], nil)
    t.eq(day().items["Crimson Pine Board"], 2)
    t.eq(next(day().pending), nil, "nothing waiting: it's already in the bags")
    t.eq(D().Looted(day(), "Crimson Pine Board"), 0)
  end)

  t.test("an older client without made: the name rule, as before", function()
    H.boot()
    H.craftResults({ craft("Crimson Pine Binding (Milling)", 1) })
    t.eq(next(day().crafted), nil, "nothing counted until it reaches the bags")
    t.eq(next(day().pending), nil)
    atStation({ { "Crimson Pine Binding", 4 } })
    t.eq(day().crafted["Crimson Pine Binding"], 4)
  end)

  t.test("results the game didn't list are counted and shown", function()
    H.boot()
    H.craftResults({ craft("Board", 1) }, 3)
    H.gatherResults({ { node = "Tree", failed = false, experience = 5, items = {} } }, 2)
    t.eq(day().craft.dropped, 3)
    t.eq(day().gather.dropped, 2)
    H.advance(1)
    H.reload()
    t.eq(day().craft.dropped, 3, "saved")
    H.chat("/tbx crafted")
    t.ok(H.detail():Find("view_note").text:find("+3 results the game didn't list", 1, true))
    H.chat("/tbx gathered")
    t.ok(H.detail():Find("view_note").text:find("+2 harvests the game didn't list", 1, true))
    H.S.date = "2026-09-28"
    H.advance(1)
    t.eq(day().craft.dropped, 0, "a new day starts at 0")
  end)

  -- Loot Tracker views ---------------------------------------------------------

  -- A day with some of everything.
  local function busyDay()
    H.boot()
    H.items({ { "Wolf Pelt", 3 } })
    H.gatherResults({ { node = "Cotton Plant", failed = false, experience = 2000,
                        items = { { name = "Raw Cotton", quantity = 2 } } } })
    H.items({ { "Raw Cotton", 2 } })
    H.S.recipes = { [7] = { id = 7, name = "Crimson Pine Board", ingredients = {
      { name = "Crimson Pine Log", quantity = 1, have = 4, optional = false, tool = false } } } }
    H.craftResults({ craft("Crimson Pine Board", 1, 1, 0, 9000) })
    H.craftingState({ open = true, station = "Milling Station +5", busy = false })
    H.items({ { "Crimson Pine Board", 2 }, { "Crimson Pine Log", 3 } })   -- the product, and logs taken back
    H.craftingState({ open = false, station = "", busy = false })
    H.chat("/tbx dd")
    H.advance(1)
  end

  t.test("Looted leaves crafted and gathered items out, and says so", function()
    busyDay()
    t.eq(H.detail():Find("dd_view").value, "Looted")
    t.eq(rows(), "Wolf Pelt=3")
    t.eq(H.detail():Find("items_summary").text, "Items looted: 3 (1 kind)")
    t.ok(H.detail():Find("view_note").text:find("left out"))
  end)

  t.test("Include puts them back in", function()
    busyDay()
    H.chat("/tbx dd include on")
    t.eq(H.saved("daily_detail").include, true)
    t.eq(rows(), "Crimson Pine Log=3, Wolf Pelt=3, Crimson Pine Board=2, Raw Cotton=2")
    t.eq(H.detail():Find("items_summary").text, "Items gained: 10 (4 kinds)")
    t.eq(H.detail():Find("view_note").visible, false)
  end)

  t.test("Crafted: what came off the station, crafts per recipe, exceptional and XP", function()
    busyDay()
    H.chat("/tbx crafted")
    t.eq(H.detail():Find("dd_view").value, "Crafted")
    t.eq(rows(), "Crimson Pine Board=2")
    t.eq(H.detail():Find("items_summary").text, "Items made: 2 (1 kind)")
    local note = H.detail():Find("view_note").text
    t.ok(note:find("^Crafts 1 %(1 exceptional, 100%%%)%. XP 9,000%."), note)
    t.ok(note:find("\nCrimson Pine Board: 1 craft %(1 exc%)"), note)
    t.ok(note:find("\nMaterials used: Crimson Pine Log 1"), note)
    t.ok(note:find("\nAlso off stations, not made: Crimson Pine Log 3"), note)
    t.eq(H.saved("daily_detail").view, "crafted", "remembered")
  end)

  t.test("Gathered: the harvested items, nodes and XP", function()
    busyDay()
    H.chat("/tbx gathered")
    t.eq(rows(), "Raw Cotton=2")
    t.eq(H.detail():Find("view_note").text, "Nodes 1. XP 2,000.")
    local pick = H.detail():Find("dd_view")
    H.call(function() pick.onChange(pick, "Looted") end)   -- the dropdown
    t.eq(rows(), "Wolf Pelt=3")
  end)

  t.test("new results show while the window is open", function()
    busyDay()
    H.chat("/tbx gathered")
    H.gatherResults({ { node = "Tree", failed = true, experience = 0, items = {} } })
    H.advance(1)
    t.eq(H.detail():Find("view_note").text, "Nodes 2 (1 failed). XP 2,000.")
  end)

  t.test("an older client: no views, everything in the one list, and the commands say why", function()
    H.boot()
    H.S.noCrafting = true
    H.reload()
    H.items({ { "Wolf Pelt", 3 } })
    H.chat("/tbx dd")
    H.advance(1)
    t.eq(H.detail():Find("view_row").visible, false, "no Show dropdown")
    t.eq(H.detail():Find("items_summary").text, "Items gained: 3 (1 kind)")
    H.clearLogs()
    H.chat("/tbx crafted")
    t.ok(H.logged("needs Lua API 18"))
    H.chat("/tbx config")
    t.eq(H.config():Find("dd_include").enabled, false)
  end)

  t.test("settings: the Include option", function()
    busyDay()
    H.chat("/tbx config")
    H.change("toolbox_config", "dd_include", true)
    t.eq(DD().GetInclude(), true)
    t.eq(rows(), "Crimson Pine Log=3, Wolf Pelt=3, Crimson Pine Board=2, Raw Cotton=2")
  end)

  t.test("the day's crafting survives a reload", function()
    busyDay()
    H.reload()
    t.eq(day().recipes["Crimson Pine Board"].n, 1)
    t.eq(day().crafted["Crimson Pine Board"], 2)
    t.eq(day().gathered["Raw Cotton"], 2)
  end)
end
