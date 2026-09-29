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

  t.test("items gained while a crafting window is open count as made", function()
    H.boot()
    H.craftingState({ open = true, station = "Milling Station +5", busy = false })
    H.items({ { "Crimson Pine Board", 2 } })
    H.craftingState({ open = false, station = "", busy = false })
    H.items({ { "Wolf Pelt", 1 } })
    t.eq(day().crafted["Crimson Pine Board"], 2)
    t.eq(day().crafted["Wolf Pelt"], nil)
    t.eq(day().items["Crimson Pine Board"], 2, "still in the day's items (for Include)")
    H.S.craftingState = { open = true, station = "Smelter", busy = false }
    H.reload()                                               -- a reload at a station: read at start
    H.items({ { "Iron Ingot", 5 } })
    t.eq(day().crafted["Iron Ingot"], 5)
  end)

  -- Today Detailed views ---------------------------------------------------------

  -- A day with some of everything.
  local function busyDay()
    H.boot()
    H.items({ { "Wolf Pelt", 3 } })
    H.gatherResults({ { node = "Cotton Plant", failed = false, experience = 2000,
                        items = { { name = "Raw Cotton", quantity = 2 } } } })
    H.items({ { "Raw Cotton", 2 } })
    H.craftResults({ craft("Crimson Pine Board", 1, 1, 0, 9000) })
    H.craftingState({ open = true, station = "Milling Station +5", busy = false })
    H.items({ { "Crimson Pine Board", 2 } })
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
    t.eq(rows(), "Wolf Pelt=3, Crimson Pine Board=2, Raw Cotton=2")
    t.eq(H.detail():Find("items_summary").text, "Items gained: 7 (3 kinds)")
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
    t.eq(rows(), "Wolf Pelt=3, Crimson Pine Board=2, Raw Cotton=2")
  end)

  t.test("the day's crafting survives a reload", function()
    busyDay()
    H.reload()
    t.eq(day().recipes["Crimson Pine Board"].n, 1)
    t.eq(day().crafted["Crimson Pine Board"], 2)
    t.eq(day().gathered["Raw Cotton"], 2)
  end)
end
