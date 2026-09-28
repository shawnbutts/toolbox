-- The equipment bar and the "Gear needs repair" notification (Toolbox.Gear, in buffbar.lua).
local H = require("harness")

return function(t)
  local SWORD = { name = "Iron Longsword", durability = 180, maxDurability = 200 }
  local HELM = { name = "Chain Coif", durability = 90, maxDurability = 100 }

  local function gear(swordDur, helmDur)
    H.setGear{ { name = SWORD.name, durability = swordDur or SWORD.durability, maxDurability = 200 },
               { name = HELM.name, durability = helmDur or HELM.durability, maxDurability = 100 } }
  end

  -- Booted and past the notifications' start-up settling, with the gear read once.
  local function settled()
    H.boot()
    gear()
    H.advance(Toolbox.Notify.SETTLE + Toolbox.Gear.POLL + 1)
  end

  local function seen()
    local saved = H.saved("notify")
    return saved and saved.sources.durability.seen
  end

  -- model ---------------------------------------------------------------------

  t.test("Read: worn items with durability, same names numbered", function()
    H.boot()
    local items = Toolbox.Gear.Read{
      { name = "Ring", durability = 5, maxDurability = 10, icon = 3 },
      { name = "Ring", durability = 10, maxDurability = 10 },
      { name = "Cloak", durability = 0, maxDurability = 0 },         -- no durability: left out
      { name = "Boots", durability = -2, maxDurability = 50 },       -- clamped
      "junk",
    }
    t.eq(#items, 3)
    t.eq(items[1].key, "Ring")
    t.eq(items[1].pct, 0.5)
    t.eq(items[1].icon, 3)
    t.eq(items[2].key, "Ring#2")
    t.eq(items[2].icon, -1, "no icon")
    t.eq(items[3].dur, 0)
    t.eq(items[3].pct, 0)
    t.eq(#Toolbox.Gear.Read(nil), 0)
  end)

  t.test("Stage and Notice: low, then broken, repairs quietly", function()
    H.boot()
    local G = Toolbox.Gear
    local function item(dur) return G.Read{ { name = "Sword", durability = dur, maxDurability = 100 } } end
    t.eq(G.Stage(item(20)[1], 20), nil, "20% isn't below 20%")
    t.eq(G.Stage(item(19)[1], 20), "low")
    t.eq(G.Stage(item(0)[1], 20), "broken")
    local n, quiet = G.Notice(item(50), {}, 20)
    t.eq(n, nil)
    t.eq(quiet, nil, "nothing changed")
    n = G.Notice(item(18), {}, 20)
    t.eq(n.text, "Sword is at 18% durability. Repair it before it breaks.")
    t.eq(n.seen.Sword, "low")
    t.eq(G.Notice(item(10), { Sword = "low" }, 20), nil, "already warned")
    n = G.Notice(item(0), { Sword = "low" }, 20)
    t.eq(n.text, "Sword is broken. Repair it before it breaks.")
    t.eq(n.seen.Sword, "broken")
    n, quiet = G.Notice(item(100), { Sword = "broken" }, 20)
    t.eq(n, nil)
    t.eq(next(quiet), nil, "repaired: forgotten quietly")
  end)

  -- notifications ---------------------------------------------------------------

  t.test("an item wearing below 20% notifies once, and again when it breaks", function()
    settled()
    t.eq(H.notify(), nil, "all fine")
    gear(36)                                          -- the sword at 18%
    H.advance(Toolbox.Gear.POLL)
    t.eq(H.notice("durability").text, "Iron Longsword is at 18% durability. Repair it before it breaks.")
    t.eq(H.notice("durability").title, "Gear needs repair")
    t.eq(seen()["Iron Longsword"], "low")
    H.closeWindow("toolbox_notify")
    gear(20)
    H.advance(Toolbox.Gear.POLL)
    t.no(H.notify():IsShown(), "no second warning while low")
    gear(0)
    H.advance(Toolbox.Gear.POLL)
    t.eq(H.notice("durability").text, "Iron Longsword is broken. Repair it before it breaks.")
    H.closeWindow("toolbox_notify")
    gear(200)                                         -- repaired
    H.advance(Toolbox.Gear.POLL)
    t.no(H.notify():IsShown())
    t.eq(seen()["Iron Longsword"], nil)
    gear(30)
    H.advance(Toolbox.Gear.POLL)
    t.ok(H.notice("durability").shown, "warns again after a repair")
  end)

  t.test("warnings survive a restart; an empty list (not loaded) forgets nothing", function()
    settled()
    gear(30)
    H.advance(Toolbox.Gear.POLL)
    t.ok(H.notice("durability").shown)
    H.restart(nil, true)
    H.S.gear = {}                                     -- not loaded yet
    H.advance(Toolbox.Notify.SETTLE + 5)
    gear(30)
    H.advance(Toolbox.Gear.POLL)
    t.eq(H.notify(), nil, "already warned about it")
    t.eq(seen()["Iron Longsword"], "low")
  end)

  t.test("the threshold setting moves the warning point", function()
    settled()
    H.chat("/tbx gear repair 50")
    t.eq(Toolbox.Gear.Threshold(), 50)
    t.eq(H.saved("gear").threshold, 50)
    gear(90)                                          -- 45%
    H.advance(Toolbox.Gear.POLL)
    t.ok(H.notice("durability").shown)
    H.chat("/tbx gear repair 12")
    t.ok(H.logged("one of 5, 10, 15, 20, 25, 30, 50"))
    t.eq(Toolbox.Gear.Threshold(), 50)
  end)

  -- the bar -------------------------------------------------------------------

  t.test("the bar shows only items below the threshold, lowest first", function()
    settled()
    t.no(H.gearFrame():IsVisible(), "nothing low: hidden")
    gear(30, 5)                                       -- 15% and 5%
    H.advance(Toolbox.Gear.POLL)
    t.ok(H.gearFrame():IsVisible())
    local slots = H.gearSlots()
    t.eq(#slots, 2)
    t.ok(slots[1].children[1].tooltip:find("^Chain Coif\nDurability 5 / 100 %(5%%%)"), "lowest first")
    t.ok(slots[2].children[1].tooltip:find("Iron Longsword"))
    t.ok(slots[1].children[2].visible ~= false, "the sweep")
    gear(0, 100)
    H.advance(Toolbox.Gear.POLL)
    slots = H.gearSlots()
    t.eq(#slots, 1)
    t.ok(slots[1].children[1].tooltip:find("Broken"))
    H.chat("/tbx gear bar off")
    t.no(H.gearFrame():IsVisible())
    t.eq(H.saved("gear").show, false)
  end)

  t.test("every worn item shows while settings are open", function()
    settled()
    H.chat("/tbx config")
    H.advance(1)
    t.ok(H.gearFrame():IsVisible())
    t.eq(#H.gearSlots(), 2)
    H.closeWindow("toolbox_config")
    H.advance(1)
    t.no(H.gearFrame():IsVisible())
  end)

  t.test("settings: the toggle and the threshold dropdown", function()
    settled()
    H.chat("/tbx config")
    H.change("toolbox_config", "gear_threshold", "30%")
    t.eq(Toolbox.Gear.Threshold(), 30)
    H.change("toolbox_config", "show_gear", false)
    t.no(Toolbox.Gear.GetShow())
    H.chat("/tbx gear bar on")
    t.eq(H.config():Find("show_gear").value, true, "follows the command")
    H.chat("/tbx gear repair 10")
    t.eq(H.config():Find("gear_threshold").value, "10%")
  end)

  t.test("/toolbox gear lists worn items, lowest first", function()
    settled()
    gear(30)
    H.clearLogs()
    H.chat("/tbx gear")
    t.ok(H.logged("Worn gear %(repair below 20%%%)"))
    t.ok(H.logged("Iron Longsword: 15%% %(30 / 200%) needs repair"))
    t.ok(H.logged("Chain Coif: 90%%"))
    H.setGear{}
    H.chat("/tbx gear")
    t.ok(H.logged("No worn items"))
  end)

  -- size and glue -------------------------------------------------------------

  local function slotSize(slot) return slot.style.width end

  t.test("the icons follow the buff bar's icon size", function()
    settled()
    gear(30)
    H.advance(Toolbox.Gear.POLL)
    t.eq(slotSize(H.gearSlots()[1]), Toolbox.BuffBar.GetSize())
    H.chat("/tbx config")
    H.change("toolbox_config", "buff_size", 40)
    H.closeWindow("toolbox_config")
    H.advance(1)
    local slot = H.gearSlots()[1]
    t.eq(slotSize(slot), 40)
    t.eq(slot.children[1].width, 40, "the icon")
    t.eq(slot.children[2].style.marginLeft, -40, "the sweep still covers it")
    t.eq(H.gearFrame().width, Toolbox.Window.GRIP + 40 + Toolbox.BuffBar.GAP + 8, "the strip re-fits")
  end)

  t.test("glued: a third row of the buff bar, under the debuffs", function()
    settled()
    H.chat("/tbx buffs")
    H.chat("/tbx gear glue on")
    t.eq(H.saved("gear").glue, true)
    t.eq(H.gearFrame(), nil, "no strip of its own")
    local cell = Toolbox.BuffBar.GetSize() + Toolbox.BuffBar.GAP
    H.advance(1)
    t.eq(H.frame().height, cell + 8, "nothing low: one row")
    gear(30, 5)
    H.addBuffs({ { name = "Poison", remaining = 60, debuff = true } })
    H.advance(Toolbox.Gear.POLL)
    local rows = H.frame():Find("buffbar").children
    t.eq(rows[3].id, "gear", "third row")
    t.eq(#H.gearSlots(), 2)
    t.eq(H.frame().height, 3 * cell + 8, "buffs, debuffs and gear")
    t.eq(H.frame().width, Toolbox.Window.GRIP + 2 * cell + 8, "as wide as the gear row")
    H.chat("/tbx gear glue off")
    t.ok(H.gearFrame():IsVisible(), "back on its own strip")
    t.eq(H.frame():Find("gear"), nil)
    t.eq(H.frame().height, 2 * cell + 8)
  end)

  t.test("glued with the buff bar off: its own strip; the setting survives a reload", function()
    settled()
    H.chat("/tbx gear glue on")
    gear(30)
    H.advance(Toolbox.Gear.POLL)
    t.ok(H.gearFrame():IsVisible(), "the buff bar is off")
    H.chat("/tbx buffs")                          -- on: the row moves into it
    H.advance(1)
    t.eq(H.gearFrame(), nil)
    t.eq(#H.gearSlots(), 1)
    H.reload()
    H.advance(Toolbox.Gear.POLL)
    t.eq(H.gearFrame(), nil, "still glued")
    t.eq(#H.gearSlots(), 1)
    H.chat("/tbx buffs")                          -- off again
    H.advance(1)
    t.ok(H.gearFrame():IsVisible())
  end)

  t.test("glued, with the health bars glued too: in the shared strip", function()
    settled()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")
    H.chat("/tbx gear glue on")
    gear(30)
    H.advance(Toolbox.Gear.POLL)
    t.ok(H.hud():Find("gear"), "in the shared strip")
    t.eq(#H.gearSlots(), 1)
  end)

  t.test("settings: the glue toggle", function()
    settled()
    H.chat("/tbx buffs")
    H.chat("/tbx config")
    H.change("toolbox_config", "gear_glue", true)
    t.ok(Toolbox.Gear.GetGlue())
    H.chat("/tbx gear glue off")
    t.eq(H.config():Find("gear_glue").value, false, "follows the command")
  end)
end
