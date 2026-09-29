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
      if slot.visible ~= false then out[#out + 1] = slot end
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
    H.addBuffs({ { name = "RuneFood_Stew_Dragon", remaining = 14544, total = 29088, icon = 590 } })  -- half gone
    H.advance(1)
    local holder = consSlots()[1].children[2]
    t.eq(holder.visible, true)
    local c, uv = B().CLOCK, holder.children[1].uv
    local k = math.floor(uv[1] * c.COLS + 0.5) + math.floor(uv[2] * c.ROWS * c.SETS + 0.5) * c.COLS
    t.ok(k >= 59 and k <= 61, "half the stew's 8 h: frame " .. k)
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
    local red, flashed = slot.children[2].children[1].uv[2] >= 0.5, false
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
    t.ok(H.logged("Already tracked"))
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
    t.ok(H.logged("^Consumables bar: on%. Tracked: food"))
    t.ok(H.logged("RuneFood_Stew_Dragon%): "))
    t.ok(H.logged("%(potion, BlessingOfCapacity%)"))
    t.no(H.logged("POT_Blessing"))
  end)

  t.test("settings: show and glue toggles, and the extra names", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx config")
    H.change("toolbox_config", "consumables_glue", true)
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
end
