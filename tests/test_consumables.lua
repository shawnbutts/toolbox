-- The consumables bar (Toolbox.Consumables, in buffbar.lua): food and potions on their own bar.
local H = require("harness")

return function(t)
  local B = function() return Toolbox.BuffBar end

  local function bootWithSounds()
    H.boot()
    H.S.files["toolbox_buff_expiring.ogg"] = true
    H.reload()
    H.advance(Toolbox.BuffBar.SETTLE)
  end

  local function strip() return H.S.frames.toolbox_consumables end
  -- Visible slots of the consumables row (own strip, or inside the buff bar's strip when glued).
  local function consSlots()
    local frame = strip() or H.S.frames.toolbox_buffs or H.S.frames.toolbox_hud
    local out = {}
    for _, slot in ipairs(frame:Find("consumables").children) do
      if slot.visible ~= false and slot.id ~= "consumables_placeholder" then out[#out + 1] = slot end
    end
    return out
  end
  local function textures(list)
    local out = {}
    for i, slot in ipairs(list) do out[i] = tostring(slot.children[1].texture) end
    return table.concat(out, ",")
  end

  -- In game (2026-09-28): food, an Obsidian potion, and shrine blessings (not consumables).
  local function sample()
    H.addBuffs({ { name = "RuneFood_Stew_Dragon", remaining = 600, total = 29088, icon = 590 },
                 { name = "BlessingOfCapacity", remaining = 565672, total = 604800, icon = 592 },
                 { name = "POT_Blessing_Love_Large", remaining = 393227, total = 432000, icon = 599 },
                 { name = "Rune_Reward_Blessing_Shrine_Gaism", remaining = 220435, total = 259200, icon = 602 },
                 { name = "Light", remaining = 100, total = 127, icon = 5 } })
  end

  t.test("ConsumableKind: food and Obsidian potions by name; shrine blessings aren't", function()
    H.boot()
    local K = B().ConsumableKind
    t.eq(K("RuneFood_Stew_Dragon"), "food")
    t.eq(K("BlessingOfStamina"), "potion")
    t.eq(K("POT_Blessing_Love_Large"), nil, "a shrine blessing (owner)")
    t.eq(K("Rune_Reward_Blessing_Shrine_Gaism"), nil)
    t.eq(K("Light"), nil)
    t.eq(K("VenomCoating", "Poisoned Blade", { "poison" }), "extra", "an added name part, in the label")
    t.eq(K("VenomCoating", "", { "VENOM" }), "extra", "any case, in the rune name")
    t.eq(K(nil), nil)
  end)

  t.test("food and potions go on their own bar, soonest first; everything else stays on the buff bar", function()
    H.boot()
    H.S.durationMode = "remaining"
    H.chat("/tbx buffs")
    H.chat("/tbx buffs group after off")
    sample()
    H.advance(1)
    t.ok(strip(), "its own strip")
    t.eq(strip().visible, true)
    t.eq(textures(consSlots()), "590,592", "food (10 min left) before the potion (6.5 days)")
    local onBar = {}
    for _, slot in ipairs(H.slots("buffs")) do onBar[#onBar + 1] = tostring(slot.children[1].texture) end
    table.sort(onBar)
    t.eq(table.concat(onBar, ","), "5,599,602", "Light and the shrine blessings stay")
  end)

  t.test("a consumable's sweep uses its full duration from the game", function()
    H.boot()
    H.S.durationMode = "remaining"
    H.chat("/tbx buffs group after off")               -- 4 h left would be grouped
    H.addBuffs({ { name = "RuneFood_Stew_Dragon", remaining = 14544, total = 29088, icon = 590 } })  -- half gone
    H.advance(1)
    local done = consSlots()[1].children[1]:SweepNow()
    t.ok(done and math.abs(done - 0.5) < 0.01, "half the stew's 8 h: " .. tostring(done))
  end)

  t.test("about to run out: flashes red and sounds like any buff; then it's gone", function()
    bootWithSounds()
    H.S.durationMode = "remaining"
    H.addBuffs({ { name = "RuneFood_Stew_Dragon", remaining = 20, total = 29088, icon = 590 } })
    H.advance(1, 0.5)
    H.S.played = {}
    H.advance(16, 0.5)                                -- past the 5 s alert
    t.eq(H.playedNames(), "toolbox_buff_expiring")
    local slot = consSlots()[1]
    local _, red = slot.children[1]:SweepNow()
    local flashed = false
    for _ = 1, 4 do
      H.advance(0.5, 0.5)
      if (slot.style.borderWidth or 0) > 0 then flashed = true end
    end
    t.ok(red, "the red sweep")
    t.ok(flashed, "the red border flashes")
    H.advance(5, 0.5)                                 -- ran out
    t.eq(#consSlots(), 0, "removed once it has run out")
    t.eq(strip().visible, false, "an empty bar hides")
  end)

  t.test("bar off: food and potions stay on the buff bar, and no strip is built", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs group after off")
    H.chat("/tbx consumables bar off")
    t.eq(H.saved("consumables").show, false)
    t.eq(strip(), nil, "no HUD frame used (8 per add-on)")
    sample()
    H.advance(1)
    t.eq(#H.slots("buffs"), 5)
    H.chat("/tbx consumables bar on")
    H.advance(1)
    t.eq(#H.slots("buffs"), 3)
    t.eq(#consSlots(), 2)
  end)

  t.test("glued: a row of the buff bar under the debuffs, above the equipment bar", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx consumables glue on")
    H.chat("/tbx gear glue on")
    t.eq(H.saved("consumables").glue, true)
    t.eq(strip(), nil, "no strip of its own")
    H.setGear{ { name = "Sword", durability = 10, maxDurability = 100 } }
    sample()
    H.advance(Toolbox.Gear.POLL)
    local ids = {}
    for i, row in ipairs(H.frame():Find("buffbar").children) do ids[i] = row.id end
    t.eq(table.concat(ids, ","), "buffs,debuffs,consumables,gear")
    t.eq(#consSlots(), 2)
    local cell = B().GetSize() + B().GAP
    t.eq(H.frame().height, 3 * cell + 8, "buffs, consumables and gear (no debuffs)")
    H.chat("/tbx consumables glue off")
    t.ok(strip(), "back on its own strip")
    H.advance(1)
    t.eq(#consSlots(), 2)
  end)

  t.test("more names: add and remove", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "VenomCoating", label = "Poisoned Blade", remaining = 300, icon = 77 } })
    H.advance(1)
    t.eq(#H.slots("buffs"), 1)
    H.chat("/tbx consumables add poison")
    t.eq(H.saved("consumables").extra[1], "poison")
    H.advance(1)
    t.eq(#H.slots("buffs"), 0)
    t.eq(#consSlots(), 1)
    H.clearLogs()
    H.chat("/tbx consumables add Poison")
    t.ok(H.logged("Already in the list"))
    H.chat("/tbx consumables remove POISON")
    H.advance(1)
    t.eq(#H.slots("buffs"), 1, "back on the buff bar")
  end)

  t.test("/tbx consumables lists what is in effect", function()
    H.boot()
    sample()
    H.advance(1)
    H.clearLogs()
    H.chat("/tbx consumables")
    t.ok(H.logged("^Consumables bar: on%. Kinds: Food, Potion, Poison, Consumable%."), H.logs()[1])
    t.ok(H.logged("^Left out: names containing Scroll, Torch, Bait%."))
    t.ok(H.logged("%(Food, RuneFood_Stew_Dragon%): "))
    t.ok(H.logged("%(Potion, BlessingOfCapacity%)"))
    t.no(H.logged("POT_Blessing"))
  end)

  t.test("settings: show and glue toggles, and the extra names", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx config")
    H.change("toolbox_config", "toolbelt_consumables", "In Toolbelt")
    t.ok(Toolbox.Consumables.GetGlue())
    H.change("toolbox_config", "show_consumables", false)
    t.no(Toolbox.Consumables.GetShow())
    H.chat("/tbx consumables bar on")
    t.eq(H.config():Find("show_consumables").value, true, "follows the command")
    H.chat("/tbx consumables add venom")
    t.ok(H.config():Find("consumables_extra").text:find("venom"))
  end)

  t.test("every strip at once stays within the 8 HUD frames", function()
    H.boot()
    for _, cmd in ipairs({ "/tbx buffs", "/tbx vitals", "/tbx combat", "/tbx xp", "/tbx xp hud", "/tbx daily",
                           "/tbx daily hud", "/tbx notify via hud" }) do
      H.chat(cmd)
    end
    local n = 0
    for _ in pairs(H.S.frames) do n = n + 1 end
    t.ok(n <= 8, n .. " HUD frames")
    t.ok(strip(), "the consumables bar has one")
  end)

  -- buff categories (API 23) ----------------------------------------------------

  t.test("TakesConsumable: by category, with names left out, extra names, and names on older clients", function()
    H.boot()
    local take = B().TakesConsumable
    local cats = { Food = true, Potion = true, Poison = true, Consumable = true }
    local ex, extra = { "Scroll", "Torch", "Bait" }, { "Venom" }
    t.ok(take("Stew", "", "Food", false, cats, ex, extra))
    t.ok(take("Caltrops", "Caltrops", "Consumable", false, cats, ex, extra), "a combat item")
    t.no(take("ScrollOfProtection", "Scroll of Protection", "Consumable", false, cats, ex, extra), "a scroll")
    t.no(take("TorchLight", "Lit torch", "Consumable", false, cats, ex, extra), "any case, in the label too")
    t.ok(take("WeaponPoison", "", "Poison", false, cats, ex, extra), "a poison on your weapon")
    t.no(take("WeaponPoison", "", "Poison", true, cats, ex, extra), "a poison on you is a debuff")
    t.no(take("POT_Blessing_Love_Large", "", "Blessing", false, cats, ex, extra), "blessings: off by default")
    t.no(take("NewThing", "", "Mystery", false, cats, ex, extra), "an unknown category counts as Other")
    t.ok(take("NewThing", "", "Mystery", false, { Other = true }, ex, extra))
    t.ok(take("VenomCoating", "", "Skill", false, cats, ex, extra), "an extra name wins over its category")
    t.ok(take("RuneFood_Stew", "", nil, false, cats, ex, extra), "no category: food by name")
    t.no(take("RuneFood_Stew", "", nil, false, { Potion = true }, ex, extra), "and only if Food is ticked")
    t.no(take("Caltrops", "", nil, false, cats, ex, extra), "no category: nothing but the name rules")
  end)

  t.test("in the bar: caltrops and a weapon poison yes, a scroll no, a poison on you stays a debuff", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs group after off")
    H.addBuffs({ { name = "Caltrops", category = "Consumable", remaining = 60, icon = 81 },
                 { name = "ScrollOfProtection", label = "Scroll of Protection", category = "Consumable",
                   remaining = 300, icon = 82 },
                 { name = "WeaponPoisonDeadly", category = "Poison", remaining = 600, icon = 83 },
                 { name = "SpiderVenom", category = "Poison", debuff = true, remaining = 10, icon = 84 } })
    H.advance(1)
    t.eq(textures(consSlots()), "81,83", "caltrops and the weapon poison, soonest first")
    local bar = {}
    for _, slot in ipairs(H.slots("buffs")) do bar[#bar + 1] = tostring(slot.children[1].texture) end
    t.eq(table.concat(bar, ","), "82", "the scroll stays on the buff bar")
    t.eq(#H.slots("debuffs"), 1, "the poison on you is a debuff")
  end)

  t.test("categories on and off: by command and in settings; saved", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs group after off")
    sample()
    H.advance(1)
    t.eq(textures(consSlots()), "590,592")
    H.chat("/tbx consumables cat blessing on")
    H.advance(1)
    t.eq(textures(consSlots()), "590,602,599,592", "the shrine blessings join them")
    t.eq(H.saved("consumables").cats.Blessing, true)
    H.chat("/tbx config")
    H.change("toolbox_config", "cons_cat_Food", false)
    H.advance(1)
    t.eq(textures(consSlots()), "602,599,592", "food back on the buff bar")
    H.reload()
    t.no(Toolbox.Consumables.GetCategory("Food"), "kept across a reload")
    t.ok(Toolbox.Consumables.GetCategory("Blessing"))
    H.clearLogs()
    H.chat("/tbx consumables cat mystery on")
    t.ok(H.logged("Categories: Other, Food"))
  end)

  t.test("left-out names: add and remove", function()
    H.boot()
    H.addBuffs({ { name = "Caltrops", category = "Consumable", remaining = 60, icon = 81 } })
    H.advance(1)
    t.eq(#consSlots(), 1)
    H.chat("/tbx consumables exclude add caltrop")
    H.advance(1)
    t.eq(#consSlots(), 0)
    t.eq(H.saved("consumables").exclude[4], "caltrop")
    H.chat("/tbx consumables exclude remove CALTROP")
    H.advance(1)
    t.eq(#consSlots(), 1)
    H.chat("/tbx config")
    t.ok(H.config():Find("cons_exclude").text:find("Scroll, Torch, Bait"))
  end)

  t.test("the settings edit the left-out and always-on names", function()
    H.boot()
    H.addBuffs({ { name = "Caltrops", category = "Consumable", remaining = 60, icon = 9 } })
    H.advance(1)
    t.eq(#consSlots(), 1)
    H.chat("/tbx config")
    H.submit("toolbox_config", "cons_exclude_field", "caltrop")
    H.advance(1)
    t.eq(#consSlots(), 0, "left out from the settings")
    t.eq(H.config():Find("cons_exclude").text, "Left out by name: Scroll, Torch, Bait, caltrop")
    H.config():Find("cons_exclude_field"):SetText("caltrop")
    H.click("toolbox_config", "cons_exclude_remove")
    H.advance(1)
    t.eq(#consSlots(), 1, "back on it")
    H.config():Find("consumables_extra_field"):SetText("Light")
    H.click("toolbox_config", "consumables_extra_add")
    t.eq(Toolbox.Consumables.Extra()[#Toolbox.Consumables.Extra()], "Light")
    t.ok(H.config():Find("consumables_extra").text:find("^Always on it by name: .*Light"))
    H.click("toolbox_config", "consumables_extra_add")
    t.ok(H.config():Find("consumables_extra_msg").text ~= "", "an empty add says why")
  end)

  t.test("an older client without categories: food and potions by name; other kinds greyed out", function()
    H.boot()
    H.S.noCategories = true
    H.reload()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "RuneFood_Stew_Dragon", remaining = 600, icon = 590 },
                 { name = "Caltrops", remaining = 60, icon = 81 } })
    H.advance(1)
    t.eq(textures(consSlots()), "590")
    t.eq(#H.slots("buffs"), 1, "caltrops can't be told apart without categories")
    H.chat("/tbx config")
    t.eq(H.config():Find("cons_cat_Consumable").enabled, false)
    t.ok(H.config():Find("cons_cat_Food").enabled ~= false)
  end)

  t.test("a save from before categories keeps the defaults", function()
    H.boot({ ["character:Tester"] = { consumables = { show = true, extra = { "Venom" } } } })
    for _, key in ipairs({ "Food", "Potion", "Poison", "Consumable" }) do
      t.ok(Toolbox.Consumables.GetCategory(key), key)
    end
    t.no(Toolbox.Consumables.GetCategory("Blessing"))
    t.eq(Toolbox.Consumables.Exclude()[1], "Scroll")
    t.eq(Toolbox.Consumables.Extra()[1], "Venom")
  end)

  -- grouping, cap, combat only (like the buff bar) ----------------------------------

  -- The group slot: the row's last child (a count label over the first grouped icon).
  local function groupSlot()
    local frame = strip() or H.S.frames.toolbox_buffs or H.S.frames.toolbox_hud
    local kids = frame:Find("consumables").children
    return kids[#kids]
  end

  local function obsidian(n)
    local list = {}
    for i = 1, n do
      list[i] = { name = "BlessingOf" .. i, remaining = 500000 + i, total = 604800, icon = 300 + i }
    end
    return list
  end

  t.test("long-lasting ones share one slot with a count, like the buff bar's", function()
    H.boot()
    H.S.durationMode = "remaining"
    local list = obsidian(7)
    list[8] = { name = "RuneFood_Pie", remaining = 300, total = 14544, icon = 46 }     -- 5 min: its own icon
    H.addBuffs(list)
    H.advance(1)
    local slots = consSlots()
    t.eq(#slots, 2, "the pie, then the group")
    t.eq(slots[1].children[1].texture, 46)
    local g = groupSlot()
    t.ok(g.visible ~= false)
    t.eq(g.children[#g.children].text, "7", "the count")
    t.ok(g.children[1].tooltip:find("Long%-lasting buffs %(7%)"), g.children[1].tooltip)
    local cell = B().GetSize() + B().GAP
    t.eq(strip().width, Toolbox.Window.GRIP + 2 * cell + 8, "sized for the icon and the group slot")
  end)

  t.test("past the icon cap the rest share the group slot too", function()
    H.boot()
    H.S.durationMode = "remaining"
    local list = {}
    for i = 1, 4 do list[i] = { name = "RuneFood_Dish" .. i, remaining = 100 * i, total = 14544, icon = 60 + i } end
    H.addBuffs(list)
    H.chat("/tbx consumables max 2")
    t.eq(H.saved("consumables").max, 2)
    H.advance(1)
    t.eq(textures(consSlots()), "61,62,63", "two icons (soonest first), then the group (showing the 3rd)")
    t.eq(groupSlot().children[#groupSlot().children].text, "2")
    H.clearLogs()
    H.chat("/tbx consumables max 11")
    t.ok(H.logged("max <1%-10>"))
  end)

  t.test("its own strip can show only during combat; in the Toolbelt it follows the Toolbelt", function()
    H.boot()
    H.addBuffs({ { name = "RuneFood_Pie", remaining = 300, total = 14544, icon = 46 } })
    H.chat("/tbx consumables combat on")
    t.eq(H.saved("consumables").combatOnly, true)
    H.advance(1)
    t.eq(strip().visible, false, "out of combat")
    H.setCombat(true)
    H.advance(1)
    t.eq(strip().visible, true, "in combat")
    H.setCombat(false)
    H.advance(Toolbox.BuffBar.COMBAT_LINGER + 1)
    t.eq(strip().visible, false, "a few seconds after")
    H.chat("/tbx buffs")
    H.chat("/tbx config")
    t.ok(H.config():Find("cons_combat").enabled ~= false)
    H.chat("/tbx consumables glue on")
    t.eq(H.config():Find("cons_combat").enabled, false, "greyed out in the Toolbelt")
  end)

  -- the Toolbelt ---------------------------------------------------------------------

  t.test("/tbx toolbelt: what's in it, which bars join, combat only, move", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.clearLogs()
    H.chat("/tbx toolbelt")
    t.ok(H.logged("^Toolbelt: just the buff bar so far"), H.logs()[1])
    H.chat("/tbx toolbelt vitals on")
    H.chat("/tbx toolbelt consumables on")
    H.chat("/tbx toolbelt gear on")
    t.ok(Toolbox.Hud.IsGlued())
    t.ok(Toolbox.Consumables.Glued())
    t.ok(Toolbox.Gear.Glued())
    H.clearLogs()
    H.chat("/tbx toolbelt")
    t.ok(H.logged("^Toolbelt: Health bars %+ Buffs %+ Consumables %+ Equipment%.$"), H.logs()[1])
    H.chat("/tbx toolbelt combat on")
    t.ok(Toolbox.BuffBar.GetCombatOnly())
    H.chat("/tbx config")
    t.eq(H.config():Find("toolbelt_combat").value, true, "the Toolbelt's checkbox is the buff bar's setting")
    t.eq(H.config():Find("buffs_combat_only").value, true)
    H.chat("/tbx toolbelt move 500 300")
    t.eq(H.hud().x, 500, "the whole Toolbelt moves")
    H.clearLogs()
    H.chat("/tbx toolbelt sideways")
    t.ok(H.logged("^Use /toolbox toolbelt vitals"))
  end)

  -- empty strips, to place them --------------------------------------------------------

  t.test("empty strips show their name while settings are open, and are sized for it", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx config")
    H.advance(1)
    local cell = B().GetSize() + B().GAP
    local label = H.frame():Find("buffs_placeholder")
    t.eq(label.visible, true)
    t.eq(label.text, "Buff bar")
    t.eq(H.frame().width, Toolbox.Window.GRIP + B().PLACEHOLDER_CELLS * cell + 8, "sized for the name")
    local cons = strip():Find("consumables_placeholder")
    t.eq(cons.visible, true)
    t.eq(cons.text, "Consumables")
    t.eq(strip().width, Toolbox.Window.GRIP + B().PLACEHOLDER_CELLS * cell + 8)
    H.chat("/tbx toolbelt gear on")
    H.advance(1)
    t.eq(H.frame():Find("buffs_placeholder").text, "Toolbelt", "named after what it is now")
    H.addBuffs({ { name = "Light", remaining = 100, icon = 5 },
                 { name = "RuneFood_Pie", remaining = 300, total = 14544, icon = 46 } })
    H.advance(1)
    t.eq(H.frame():Find("buffs_placeholder").visible, false, "not once something is on it")
    t.eq(strip():Find("consumables_placeholder").visible, false)
    H.removeBuff("Light")
    H.removeBuff("RuneFood_Pie")
    H.advance(1)
    H.closeWindow("toolbox_config")
    H.advance(1)
    t.eq(H.frame():Find("buffs_placeholder").visible, false, "not with settings closed")
    t.eq(strip().visible, false, "an empty consumables bar hides again")
  end)
end

