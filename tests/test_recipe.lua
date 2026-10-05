-- /toolbox recipe <name> (Toolbox.Daily.RecipeLines): a known recipe as the game reports it, and what it takes
-- from raw materials through the recipes you know. A probe for the crafting planner.
local H = require("harness")

return function(t)
  -- A plate piece made from plates, plates from ingots, ingots from ore; a strap from leather (not a known
  -- recipe: raw); a hammer (a tool) and an optional oil left out of the raw materials.
  local function book()
    H.S.recipes = {
      [1] = { id = 1, name = "Iron Plate Chest", category = "Blacksmithy",
              ingredients = { { name = "Iron Plate", quantity = 6, have = 0 },
                              { name = "Leather Strap", quantity = 2, have = 1, choices = { "A", "B" } },
                              { name = "Hammer", quantity = 1, have = 1, tool = true },
                              { name = "Polish", quantity = 1, have = 0, optional = true } },
              results = { { name = "Iron Plate Chest", quantity = 1 } } },
      [2] = { id = 2, name = "Iron Plate", category = "Blacksmithy",
              ingredients = { { name = "Iron Ingot", quantity = 2, have = 0 } },
              results = { { name = "Iron Plate", quantity = 4 } } },
      [3] = { id = 3, name = "Iron Ingot", category = "Smelting",
              ingredients = { { name = "Iron Ore", quantity = 2, have = 30 } },
              results = { { name = "Iron Ingot", quantity = 1 } } },
      [4] = { id = 4, name = "Iron Plate Helm", category = "Blacksmithy", ingredients = {}, results = {} },
    }
  end
  local function all() return table.concat(H.logs(), "\n") end

  t.test("one recipe: its fields as given (undocumented ones too), then from scratch with crafts and raw totals",
      function()
    H.boot()
    book()
    H.clearLogs()
    H.chat("/tbx recipe iron plate chest")
    t.ok(all():find("Reading your recipe book %(4 recipes%)"), all())
    H.advance(2)
    local out = all()
    t.ok(out:find("Recipe 'Iron Plate Chest' %(id 1, Blacksmithy"), out)
    t.ok(out:find("2 x Leather Strap %(have 1%)  {choices=<table of 2>}"), "an undocumented field shows: " .. out)
    t.ok(out:find("1 x Hammer %(have 1%) %[tool%]"))
    t.ok(out:find("6 x Iron Plate  <%- 2 x Iron Plate %(Blacksmithy, makes 4%)"), "6 plates: 2 crafts of 4")
    t.ok(out:find("4 x Iron Ingot  <%- 4 x Iron Ingot"), "2 crafts x 2 ingots")
    t.ok(out:find("8 x Iron Ore\n"), "4 ingots x 2 ore")
    local at = out:find("Raw materials in all", 1, true)
    t.ok(at and out:sub(at):find("\n  8 x Iron Ore\n  2 x Leather Strap", 1, true), out)
    t.no(out:find("x Hammer\n  ") or out:find("x Polish\n"), "tools and optional ones aren't raw materials")
  end)

  t.test("several matches are listed; none, or no recipe book, says so", function()
    H.boot()
    book()
    H.clearLogs()
    H.chat("/tbx recipe iron plate")
    H.advance(2)
    t.ok(all():find("Iron Plate Chest %(Blacksmithy%)") == nil and all():find("Recipe 'Iron Plate'"),
      "an exact name wins: " .. all())
    H.clearLogs()
    H.chat("/tbx recipe helm")
    H.advance(2)
    t.ok(all():find("no fixed yield"), all())
    H.clearLogs()
    H.chat("/tbx recipe iron")
    t.ok(all():find("4 known recipes match 'iron'"), all())
    H.clearLogs()
    H.chat("/tbx recipe mithril")
    t.ok(all():find("No known recipe has 'mithril'"), all())
    H.S.recipes = nil
    H.clearLogs()
    H.chat("/tbx recipe")
    t.ok(all():find("0 known recipes") or all():find("No known recipes yet"), all())
  end)

  -- In game, reading a big recipe book in one call ran past the game's time limit (owner, 2026-10-05).
  t.test("a big recipe book is read a few recipes at a time, once; learning a recipe reads it again", function()
    H.boot()
    book()
    for i = 10, 409 do
      H.S.recipes[i] = { id = i, name = "Filler " .. i, ingredients = {}, results = { { name = "Filler " .. i,
        quantity = 1 } } }
    end
    local calls = 0
    local get = ShroudGetRecipe
    ShroudGetRecipe = function(id) calls = calls + 1 return get(id) end
    H.clearLogs()
    H.chat("/tbx recipe iron plate chest")
    t.ok(calls <= Toolbox.Daily.BOOK_STEP, "not all at once: " .. calls)
    H.advance(6, 0.1)                                    -- 404 recipes, 8 a tenth of a second
    t.ok(all():find("Raw materials in all", 1, true), "answered once read")
    local after = calls
    H.clearLogs()
    H.chat("/tbx recipe iron plate chest")
    t.ok(all():find("Raw materials in all", 1, true), "at once the second time")
    t.ok(calls - after <= 1, "the book isn't read again (only the recipe itself, for current counts)")
    H.callback("ShroudOnRecipesChanged")
    H.clearLogs()
    H.chat("/tbx recipe iron plate chest")
    t.ok(all():find("Reading your recipe book", 1, true), "read again after learning a recipe")
    ShroudGetRecipe = get
  end)
end
