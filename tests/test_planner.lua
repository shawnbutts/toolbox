-- The crafting planner (Toolbox.Planner): a recipe's slots and their materials (the first you have enough of, or
-- your pick, with what it adds), I'll craft from scratch, Reset, the shopping list and the build order, in the
-- shared 8th window.
local H = require("harness")

return function(t)
  local function key(c) return "item:" .. string.rep(c, 32) end
  local ARMOR = "stat:ArmorDR"
  -- An Augmented chest: 7 sheets (a group), 2 bindings (a group), 4 straps, a hammer (a tool); sheets from ingots,
  -- ingots from ore (or scraps), straps from leather.
  local function book()
    local function stats(armor, focus, weight)
      local s = { { key = "weight", value = weight or 1 } }
      if armor then s[#s + 1] = { key = ARMOR, value = armor, name = "Armor Damage Resistance" } end
      if focus then s[#s + 1] = { key = "stat:Focus", value = focus, name = "Focus" } end
      return s
    end
    H.S.recipes = {
      [10] = { id = 10, name = "Augmented Plate Chest Armor", category = "Blacksmithy",
               categoryKey = "Crafting_Blacksmithing", station = "Blacksmithing Station",
               ingredients = {
                 { name = "Metal Sheet", quantity = 7, have = 10, group = true, groupKey = "group:33",
                   choosable = true, choiceCount = 3, choices = {
                     { name = "Copper Sheet", key = key("a"), have = 0, carried = 0, stats = stats(nil, nil, 1) },
                     { name = "Iron Sheet", key = key("b"), have = 3, carried = 3, stats = stats(0.2, nil, 2) },
                     { name = "Bronze Sheet", key = key("c"), have = 10, carried = 10, stats = stats(0.1, nil, 1) } } },
                 { name = "Metal Binding", quantity = 2, have = 2, group = true, groupKey = "group:34",
                   choosable = true, choiceCount = 2, choices = {
                     { name = "Copper Binding", key = key("d"), have = 2, carried = 2, stats = stats(nil, 10) },
                     { name = "Iron Binding", key = key("e"), have = 0, carried = 0, stats = stats(nil, 5) } } },
                 { name = "Leather Strap", key = key("f"), quantity = 4, have = 0, carried = 0, stats = stats() },
                 { name = "Smithing Hammer", key = key("g"), quantity = 1, have = 1, tool = true },
               },
               results = { { name = "Augmented Plate Chest Armor", key = key("h"), quantity = 1, carried = 0,
                             stats = { { key = "resistance", value = 9 }, { key = "durability", value = 220 },
                                       { key = "weight", value = 10 } } } } },
      [11] = { id = 11, name = "Iron Sheet", category = "Blacksmithy", categoryKey = "Crafting_Blacksmithing",
               station = "Blacksmithing Station",
               ingredients = { { name = "Iron Ingot", key = key("i"), quantity = 2, have = 2, carried = 2 } },
               results = { { name = "Iron Sheet", key = key("b"), quantity = 1 } } },
      [12] = { id = 12, name = "Iron Ingot", category = "Smelting", categoryKey = "Crafting_Smelting",
               station = "Smelter",
               ingredients = { { name = "Iron Ore", key = key("j"), quantity = 2, have = 30, carried = 30 } },
               results = { { name = "Iron Ingot", key = key("i"), quantity = 1 } } },
      [13] = { id = 13, name = "Iron Ingot from Metal Scraps", category = "Smelting", categoryKey = "Crafting_Smelting",
               station = "Smelter",
               ingredients = { { name = "Metal Scraps", key = key("k"), quantity = 5, have = 0, carried = 0 } },
               results = { { name = "Iron Ingot", key = key("i"), quantity = 1 } } },
      [14] = { id = 14, name = "Leather Strap", category = "Tailoring", categoryKey = "Crafting_Tailoring",
               station = "Tailoring Station",
               ingredients = { { name = "Leather", key = key("l"), quantity = 1, have = 0, carried = 0 } },
               results = { { name = "Leather Strap", key = key("f"), quantity = 4 } } },
    }
  end
  local W = "toolbox_planner"
  local function win() return H.S.windows[W] end
  local function find(id) return win() and win():Find(id) end
  local function text(id) return find(id) and find(id).text or "" end
  local function body()
    local out = {}
    local function walk(e)
      if type(e) ~= "table" or e.destroyed then return end
      if e.kind == "Label" and e.visible ~= false then out[#out + 1] = e.text end
      for _, c in ipairs(e.children or {}) do walk(c) end
    end
    walk(find("pl_body"))
    return table.concat(out, "\n")
  end
  local function open(name)
    H.boot()
    book()
    H.chat("/tbx plan " .. (name or "augmented plate chest"))
    t.eq(find("pl_view").value, "Shopping list", "the shopping list first")
    H.change(W, "pl_view", "Plan")
  end

  t.test("use what I have: each slot takes the first material you have enough of; the shopping list and result",
      function()
    open()
    t.ok(win() and win():IsShown(), "the planner opens")
    t.eq(find("pl_recipe").value, "Augmented Plate Chest Armor")
    t.ok(text("pl_title"):find("at Blacksmithing Station: makes 1", 1, true), text("pl_title"))
    t.ok(find("pl_pick_1").value:find("^Bronze Sheet %(have 10%)"), "10 bronze for 7: " .. find("pl_pick_1").value)
    t.ok(find("pl_pick_2").value:find("^Copper Binding"), "the 2 copper bindings")
    t.eq(text("pl_adds_1"), "Adds Armor Damage Resistance +0.1; weight 1", "what the picked sheet adds")
    t.eq(text("pl_adds_2"), "Adds Focus +10; weight 1")
    t.no(find("pl_adds_3"), "a plain ingredient has no line")
    local b = body()
    t.ok(b:find("4 x Leather Strap: have 0, 4 short", 1, true), b)
    t.ok(b:find("Tool: 1 x Smithing Hammer: have them", 1, true), b)
    t.no(find("pl_make_3"), "no I'll craft without From scratch")
    t.ok(text("pl_result"):find("Resistance 9, Durability 220, Weight 10, Armor Damage Resistance 0 +0.1, Focus 0 +10",
      1, true), text("pl_result"))
    H.change(W, "pl_view", "Shopping list")
    t.eq(body(), "4 x Leather Strap")
    H.change(W, "pl_crafts", "3")
    t.ok(body():find("12 x Leather Strap", 1, true), "three crafts: " .. body())
    t.ok(body():find("11 x Bronze Sheet", 1, true), "21 sheets, 11 short of the bronze (have 10): " .. body())
  end)

  t.test("no modes: the materials come with their counts; a pick shows what it adds", function()
    open()
    t.no(find("pl_mode") or find("pl_stat") or find("pl_watch"), "no pick modes or watched stats")
    t.eq(table.concat(find("pl_pick_1").choices, "; "), "Copper Sheet (have 0); Iron Sheet (have 3); Bronze Sheet"
      .. " (have 10)", "the game's order, with counts")
    H.change(W, "pl_pick_1", "Iron Sheet (have 3)")
    t.eq(text("pl_adds_1"), "Adds Armor Damage Resistance +0.2; weight 2")
    t.ok(text("pl_result"):find("Armor Damage Resistance 0 +0.2", 1, true), text("pl_result"))
    t.eq(Toolbox.Planner.PickChoice(H.S.recipes[10].ingredients[1].choices, 4, Toolbox.Planner.HaveOf).name,
      "Bronze Sheet", "the first with enough")
  end)

  t.test("Reset: the plan's fields cleared, the recipe book kept", function()
    open()
    H.change(W, "pl_pick_1", "Iron Sheet (have 3)")
    H.change(W, "pl_crafts", "5")
    H.change(W, "pl_scratch", true)
    H.advance(8)
    t.ok(Toolbox.Daily.recipeIndex, "the book is read")
    H.change(W, "pl_make_1", true)
    local index = Toolbox.Daily.recipeIndex
    H.click(W, "pl_reset")
    t.eq(find("pl_recipe").value, "Find a recipe first")
    t.eq(find("pl_find").text, "")
    t.eq(find("pl_crafts").value, "1")
    t.ok(text("pl_title"):find("Find it", 1, true), text("pl_title"))
    t.eq(body(), "", "nothing planned")
    t.eq(Toolbox.Daily.recipeIndex, index, "the book isn't read again")
    t.eq(find("pl_scratch").value, true, "From scratch is how you plan: kept")
    H.chat("/tbx plan augmented plate chest")
    H.change(W, "pl_view", "Plan")
    t.ok(find("pl_pick_1").value:find("^Bronze Sheet"), "the pick went: " .. find("pl_pick_1").value)
    t.ok(find("pl_make_3") and find("pl_make_3").value == false, "no ticks left")
  end)

  t.test("a slot you pick yourself keeps your pick, over a reload too", function()
    open()
    H.change(W, "pl_pick_1", find("pl_pick_1").choices[1])
    t.ok(find("pl_pick_1").value:find("^Copper Sheet"), find("pl_pick_1").value)
    t.eq(text("pl_adds_1"), "Adds nothing to the item's stats here; weight 1", "changed in place with the pick")
    H.change(W, "pl_view", "Shopping list")
    t.ok(body():find("7 x Copper Sheet", 1, true), body())
    H.reload()
    book()
    H.chat("/tbx plan")
    t.eq(find("pl_view").value, "Shopping list", "the view is kept")
    t.ok(body():find("7 x Copper Sheet", 1, true), "the pick is kept: " .. body())
  end)

  t.test("from scratch: I'll craft plans the shortfall's recipe below it, the one named like the item first",
      function()
    open()
    H.change(W, "pl_pick_1", "Iron Sheet (have 3)")   -- iron sheets: 4 short
    H.change(W, "pl_scratch", true)
    t.ok(find("pl_make_1"), "I'll craft for the sheets, at once (the recipes named like them)")
    t.eq(find("pl_make_1").kind, "Toggle", "a tick, not a button: nothing is crafted")
    t.ok(find("pl_make_3"), "and the straps")
    t.no(find("pl_make_2"), "nothing short of the bindings")
    H.change(W, "pl_make_1", true)
    local b = body()
    t.ok(b:find("4 short, craft 4", 1, true), b)
    t.ok(b:find("8 x Iron Ingot: have 2, 6 short", 1, true), "4 sheets x 2 ingots: " .. b)
    H.change(W, "pl_make_2", true)                      -- the ingots' row, under the sheets
    b = body()
    t.ok(b:find("12 x Iron Ore: have them", 1, true), "6 ingots x 2 ore, from 30: " .. b)
    t.eq(find("pl_via_2").value, "Iron Ingot", "two recipes make ingots: the one named like them")
    H.change(W, "pl_via_2", "Iron Ingot from Metal Scraps")
    t.ok(body():find("30 x Metal Scraps: have 0, 30 short", 1, true), body())
    H.change(W, "pl_via_2", "Iron Ingot")
    H.change(W, "pl_view", "Shopping list")
    t.eq(body(), "4 x Leather Strap", "the sheets are made, so not bought")
    H.change(W, "pl_view", "Build order")
    b = body()
    local ingot, sheet, chest = b:find("Iron Ingot: 6 crafts", 1, true), b:find("Iron Sheet: 4 crafts", 1, true),
      b:find("Augmented Plate Chest Armor: 1 crafts", 1, true)
    t.ok(ingot and sheet and chest and ingot < sheet and sheet < chest, "deepest first, by station: " .. b)
    t.ok(b:find("Smelter", 1, true) and b:find("Blacksmithing Station", 1, true))
  end)

  t.test("the build order ticks off as you craft: the game's counts, and the crafts made", function()
    open()
    H.change(W, "pl_pick_1", "Iron Sheet (have 3)")
    H.change(W, "pl_scratch", true)
    H.advance(5)
    H.change(W, "pl_make_1", true)
    H.change(W, "pl_view", "Build order")
    t.ok(body():find("[ ] Iron Sheet: 4 crafts", 1, true), body())
    H.craftResults{ { kind = "craft", recipeId = 11, recipeName = "Iron Sheet", item = "Iron Sheet", quantity = 4,
                      crafted = 4, made = 4, outcome = "success" } }
    H.S.recipes[10].ingredients[1].choices[2].have = 7     -- on the table: the game counts them
    H.inventoryChanged()
    H.advance(3)
    t.ok(body():find("[x] Iron Sheet: done (made 4)", 1, true), body())
    t.ok(body():find("[ ] Augmented Plate Chest Armor: 1 crafts", 1, true), body())
    H.craftResults{ { kind = "craft", recipeId = 10, crafted = 1, made = 1, outcome = "success" } }
    H.advance(3)
    t.ok(body():find("[x] Augmented Plate Chest Armor: done (made 1)", 1, true), body())
  end)

  t.test("your bags change: the counts follow at most every few seconds, without rebuilding the rows", function()
    open()
    local label = find("pl_body")
    local made = H.S.created
    H.S.recipes[10].ingredients[3].have = 3
    H.inventoryChanged()
    H.advance(3)
    t.ok(body():find("4 x Leather Strap: have 3, 1 short", 1, true), body())
    t.ok(H.S.created - made < 5, "changed in place: " .. (H.S.created - made) .. " elements made")
    t.eq(find("pl_body"), label)
  end)

  t.test("one search lists the matches; the shared window: the planner and the Docs take turns", function()
    open("iron")
    t.eq(#find("pl_recipe").choices, 3, "every recipe with iron in its name")
    t.ok(text("pl_msg"):find("3 recipes match: pick one in the Recipe list.", 1, true), text("pl_msg"))
    H.change(W, "pl_recipe", "Iron Ingot")
    t.ok(text("pl_title"):find("^Iron Ingot at Smelter"), text("pl_title"))
    H.chat("/tbx docs")
    t.no(win(), "the Docs took the window")
    H.chat("/tbx plan")
    t.ok(win() and win():IsShown())
    t.ok(text("pl_title"):find("^Iron Ingot"), "the recipe is kept")
    H.chat("/tbx plan")
    t.no(win():IsShown(), "closed again")
    H.submit(W, "pl_find", "no such thing")
  end)

  t.test("the book: a recipe at a time, with a bar while it's read; I'll craft knows every maker once it's done",
      function()
    open()
    H.S.recipes[15] = { id = 15, name = "Smelt Scrap Iron", category = "Smelting", categoryKey = "Crafting_Smelting",
      station = "Smelter", ingredients = { { name = "Metal Scraps", key = key("k"), quantity = 3, have = 0 } },
      results = { { name = "Iron Ingot", key = key("i"), quantity = 2 } } }   -- named unlike what it makes
    H.callback("ShroudOnRecipesChanged")         -- learned
    H.change(W, "pl_pick_1", "Iron Sheet (have 3)")
    H.change(W, "pl_scratch", true)
    t.no(find("pl_make_1"), "the known recipes are indexed first, in the background")
    H.advance(0.05, 0.05)                        -- one step: six recipes indexed, one of them read
    t.ok(find("pl_progress").visible ~= false, "the bar shows while the book is read")
    t.ok(text("pl_bar_text"):find("^Reading recipes: %d of 6"), text("pl_bar_text"))
    t.ok(text("pl_bar_note"):find("once a login", 1, true), text("pl_bar_note"))
    H.change(W, "pl_make_1", true)
    H.change(W, "pl_make_2", true)
    t.eq(#find("pl_via_2").choices, 2, "before the book: the two named like ingots")
    local before = find("pl_bar").value
    H.advance(2)
    t.ok(find("pl_bar").value > before, "the bar moves")
    local held = H.S.periodics.toolbox_views
    t.ok(held, "the views tick")
    H.S.periodics.toolbox_views = nil        -- paused (/toolbox perf only): the reader moves the bar
    H.S.recipes[16] = nil
    for i = 20, 80 do
      H.S.recipes[i] = { id = i, name = "Filler " .. i, ingredients = {}, results = {} }
    end
    H.callback("ShroudOnRecipesChanged")
    H.advance(1)
    before = find("pl_bar").value
    H.advance(2, 0.05)
    t.ok(find("pl_bar").value > before, "the bar moves without the views tick: " .. find("pl_bar").value)
    H.S.periodics.toolbox_views = held
    H.advance(8, 0.05)
    H.advance(6)
    t.eq(find("pl_progress").visible, false, "gone once read")
    t.eq(#find("pl_via_2").choices, 3, "then every recipe making them")
    t.eq(#Toolbox.Daily.recipeIndex.byKey[key("i")], 3, "by item key")
    H.chat("/tbx plan")
    H.chat("/tbx plan")
    t.eq(find("pl_progress").visible, false, "kept: not read again while you play")
    H.logout()
    H.S.char.name = "Alt"
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(1)
    t.eq(Toolbox.Daily.recipeIndex, nil, "another character: its own book, read again")
  end)

  t.test("the known recipes are read once a session: search, the names, the book read share them", function()
    H.boot()
    book()
    local calls, get = 0, ShroudGetKnownRecipes
    ShroudGetKnownRecipes = function() calls = calls + 1 return get() end
    H.chat("/tbx plan augmented plate chest")
    H.change(W, "pl_view", "Plan")
    H.change(W, "pl_pick_1", "Iron Sheet (have 3)")
    H.change(W, "pl_scratch", true)
    H.change(W, "pl_make_1", true)
    H.submit(W, "pl_find", "iron")
    H.advance(8)
    t.eq(calls, 1, "one call")
    H.callback("ShroudOnRecipesChanged")
    H.submit(W, "pl_find", "iron")
    t.eq(calls, 2, "again after learning a recipe")
    ShroudGetKnownRecipes = get
  end)

  t.test("a big book is indexed a part at a time from the planner opening; a search finishes it at once", function()
    H.boot()
    book()
    for i = 100, 1299 do
      H.S.recipes[i] = { id = i, name = "Filler " .. i, ingredients = {}, results = {} }
    end
    H.chat("/tbx plan")
    t.eq(Toolbox.Daily.KnownRecipes(), nil, "not all in the opening frame")
    H.advance(0.05, 0.05)
    t.eq(Toolbox.Daily.KnownRecipes(), nil, Toolbox.Daily.KNOWN_STEP .. " a step")
    H.advance(1, 0.05)
    t.eq(#Toolbox.Daily.KnownRecipes(), 1205, "under a second")
    H.callback("ShroudOnRecipesChanged")
    H.submit(W, "pl_find", "filler 1234")
    t.eq(find("pl_recipe").value, "Filler 1234", "a search can't wait: indexed at once")
  end)

  t.test("your bags are shared across the plan, and a recipe is never planned inside itself", function()
    local P = Toolbox.Planner
    H.boot()
    local recipes = {
      [1] = { name = "Kit", ingredients = { { name = "Ore", key = "ore", quantity = 6, have = 8 },
                                            { name = "Bar", key = "bar", quantity = 1, have = 0 } } },
      [2] = { name = "Bar", station = "Smelter", ingredients = { { name = "Ore", key = "ore", quantity = 4, have = 8 },
                                                                 { name = "Kit", key = "kit", quantity = 1 } } },
    }
    local plan = P.Expand(1, 1, {
      recipe = function(id) return recipes[id] end,
      makers = function(k)
        if k == "bar" then return { { id = 2, yield = 1 } } end
        if k == "kit" then return { { id = 1, yield = 1 } } end
        return {}
      end,
      mode = "have", scratch = true, makes = { ["p.2"] = true }, pick = function() return nil end,
      maker = function() return nil end })
    t.eq(plan.rows[3].name, "Ore")
    t.eq(plan.rows[3].have, 2, "8 ore, 6 already used")
    t.eq(plan.rows[3].short, 2)
    t.no(plan.rows[4].canMake, "the kit isn't made inside its own bar")
    t.eq(plan.shop[1].name, "Kit")
    t.eq(plan.shop[2].name, "Ore")
    t.eq(plan.shop[2].n, 2)
  end)

  -- Review 49-50: one hammer was counted as used up by the first recipe, and a craft's extra Part was thrown away.
  t.test("a tool serves every recipe in the plan; what a craft makes past its row is there for the next", function()
    local P = Toolbox.Planner
    H.boot()
    local hammers = 1
    local function recipes(id)
      if id == 1 then
        return { name = "Gadget", ingredients = { { name = "Part", key = "part", quantity = 3, have = 0 },
                                                  { name = "Hammer", key = "hammer", quantity = 1, have = hammers,
                                                    tool = true },
                                                  { name = "Part", key = "part", quantity = 1, have = 0 } } }
      end
      return { name = "Part", station = "Bench", ingredients = {
        { name = "Hammer", key = "hammer", quantity = 1, have = hammers, tool = true },
        { name = "Metal", key = "metal", quantity = 1, have = 0 } } }
    end
    local function plan()
      return P.Expand(1, 1, {
        recipe = recipes,
        makers = function(k) if k == "part" then return { { id = 2, yield = 2 } } end return {} end,
        scratch = true, makes = { ["p.1"] = true, ["p.3"] = true }, pick = function() return nil end,
        maker = function() return nil end })
    end
    local p = plan()
    local parts = nil
    for _, b in ipairs(p.build) do if b.name == "Part" then parts = b end end
    t.eq(parts.crafts, 2, "4 Parts from 2 crafts: the extra one covers the last row")
    t.eq(#p.shop, 1, "only the metal")
    t.eq(p.shop[1].name, "Metal")
    t.eq(p.shop[1].n, 2)
    hammers = 0
    p = plan()
    local hammer = nil
    for _, s in ipairs(p.shop) do if s.name == "Hammer" then hammer = s end end
    t.eq(hammer.n, 1, "one hammer to buy, not one a recipe")
  end)

  t.test("Enter searches: through OnSubmit too (the live client ignored the spec's onSubmit), once a press",
      function()
    H.boot()
    book()
    H.chat("/tbx plan")
    local finds, find0 = 0, Toolbox.Planner.Find
    Toolbox.Planner.Find = function(...) finds = finds + 1 return find0(...) end
    H.submit(W, "pl_find", "chest")
    t.eq(finds, 1, "both ways ran it: once")
    t.eq(find("pl_recipe").value, "Augmented Plate Chest Armor")
    H.S.specSubmitIgnored = true
    H.submit(W, "pl_find", "iron ingot")
    t.eq(find("pl_recipe").value, "Iron Ingot", "the method alone")
    H.advance(1)
    H.submit(W, "pl_find", "iron ingot")
    t.eq(finds, 3, "the same text again, a new press (a later frame): run")
    H.S.specSubmitIgnored = nil
    Toolbox.Planner.Find = find0
  end)

  t.test("as you type: the Recipe list fills from three letters, one match planned at once; plan debug", function()
    H.boot()
    book()
    H.chat("/tbx plan")
    H.change(W, "pl_find", "ir")
    t.eq(find("pl_recipe").value, "Find a recipe first", "two letters: nothing yet")
    H.change(W, "pl_find", "iron")
    t.eq(table.concat(find("pl_recipe").choices, "; "), "3 matches: pick one; Iron Sheet; Iron Ingot; Iron Ingot"
      .. " from Metal Scraps")
    t.eq(find("pl_recipe").value, "3 matches: pick one", "not picked for you")
    t.ok(text("pl_title"):find("Find it", 1, true), "nothing planned yet")
    H.change(W, "pl_recipe", "Iron Ingot")
    t.ok(text("pl_title"):find("^Iron Ingot at Smelter"), text("pl_title"))
    H.change(W, "pl_find", "augmented")
    t.eq(find("pl_recipe").value, "Augmented Plate Chest Armor", "one match: planned")
    H.clearLogs()
    H.chat("/tbx plan debug")
    H.change(W, "pl_find", "lea")
    t.ok(H.logged("^%[plan debug%] the search box changed: 'lea'"), H.lastLog())
    H.chat("/tbx plan debug")
    t.ok(H.logged("^Planner debug off"))
  end)

  t.test("settings: a search for planner finds its button, which opens it", function()
    H.boot()
    book()
    H.chat("/tbx config")
    H.change("toolbox_config", "search", "crafting planner")
    local found = false
    for _, c in ipairs(H.config():Find("search_results").choices) do
      found = found or c:find("Crafting planner", 1, true) ~= nil
    end
    t.ok(found, table.concat(H.config():Find("search_results").choices, " | "))
    H.click("toolbox_config", "pl_open")
    t.ok(Toolbox.Planner.IsShown(), "opened")
  end)

  t.test("an older client: no recipe calls, so no planner", function()
    H.boot()
    H.S.noCrafting = true
    H.reload()
    H.clearLogs()
    H.chat("/tbx plan")
    t.ok(H.logged("no recipe calls for add%-ons"), H.lastLog())
    t.no(win())
    H.S.noCrafting = nil
  end)
end
