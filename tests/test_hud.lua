-- Gluing the health & focus bars to the buff bar: one HUD strip.
local H = require("harness")

return function(t)
  local Hud = function() return Toolbox.Hud end

  local function gluedWithBoth()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")
    H.advance(1)
  end

  t.test("unglued: two strips, as before", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    t.ok(H.frame() and H.vitals(), "two strips")
    t.eq(H.hud(), nil)
  end)

  t.test("glued: one strip, health & focus on the left, buffs on the right", function()
    gluedWithBoth()
    t.eq(H.frame(), nil, "the buff strip is gone")
    t.eq(H.vitals(), nil, "the vitals strip is gone")
    local hud = H.hud()
    t.ok(hud and hud.visible, "one shared strip")
    local parts = hud.children[1].children
    t.eq(parts[1].id, "vitals", "health & focus first")
    t.eq(parts[2].id, "buffbar", "then the buffs")
    t.eq(hud.children[1].style.paddingLeft, Toolbox.Window.GRIP, "clear of the grip")
    local vw, vh = Toolbox.Vitals.ContentSize()
    local bw, bh = Toolbox.BuffBar.ContentSize()
    t.eq(hud.width, Toolbox.Window.GRIP + vw + Hud().GAP + bw + Hud().PAD)
    t.eq(hud.height, math.max(vh, bh) + Hud().PAD)
    t.eq(parts[2].style.marginLeft, Hud().GAP)
  end)

  t.test("glued strip grows with buffs and fits whichever parts are shown", function()
    gluedWithBoth()
    local w0 = H.hud().width
    H.addBuffs({ { name = "A", remaining = 60, icon = 1 }, { name = "B", remaining = 60, icon = 2 } })
    H.advance(0.5, 0.5)
    t.ok(H.hud().width > w0, "wider with more buffs")
    t.eq(#H.slots("buffs"), 2, "icons still fill in")
    H.chat("/tbx vitals")                              -- hide health & focus
    local bw = Toolbox.BuffBar.ContentSize()
    t.eq(H.hud().width, Toolbox.Window.GRIP + bw + Hud().PAD, "buffs only")
    t.eq(H.hud().children[1].children[1].visible, false)
    t.eq(H.hud().children[1].children[2].style.marginLeft, 0, "no gap before the first shown part")
    H.chat("/tbx buffs")                               -- hide buffs too
    t.eq(H.hud().visible, false, "nothing shown: the strip hides")
    H.chat("/tbx vitals")
    t.eq(H.hud().visible, true)
  end)

  t.test("either section's move commands and buttons move the whole HUD", function()
    gluedWithBoth()
    H.chat("/tbx buffs move 500 60")
    t.eq(H.hud().x, 500)
    H.chat("/tbx vitals move 300 70")
    t.eq(H.hud().x, 300)
    t.eq(H.hud().y, 70)
    H.chat("/tbx config")
    H.click("toolbox_config", "buff_right")
    t.eq(H.hud().x, 310)
    H.click("toolbox_config", "vitals_reset")
    t.eq(H.hud().x, Hud().GLUED_HOME[1])
  end)

  t.test("the glued position is remembered; each strip keeps its own when unglued", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx buffs move 900 40")
    H.chat("/tbx vitals move 100 500")
    H.advance(1)
    H.chat("/tbx vitals glue on")
    H.chat("/tbx buffs move 640 200")
    H.advance(1)
    H.reload()
    t.eq(Hud().IsGlued(), true, "glue remembered")
    t.eq(H.hud().x, 640)
    t.eq(H.hud().y, 200)
    H.chat("/tbx vitals glue off")
    t.eq(H.hud(), nil)
    t.eq(H.frame().x, 900, "the buff bar back where it was")
    t.eq(H.vitals().x, 100, "the vitals too")
    t.eq(H.vitals().y, 500)
  end)

  t.test("glued: sweeps, alerts, flashing and resizing still work", function()
    gluedWithBoth()
    H.S.files["toolbox_buff_expiring.ogg"] = true
    H.reload()
    H.advance(Toolbox.BuffBar.SETTLE)    -- a buff added next counts as cast
    H.chat("/tbx buffalert 5")
    H.addBuffs({ { name = "Ward", remaining = 12, icon = 9 } })
    H.advance(8, 0.5)
    t.eq(H.playedNames(), "toolbox_buff_expiring")
    t.ok(H.slots("buffs")[1].children[2]:SweepNow() ~= nil, "the sweep shows")
    local w = H.hud().width
    H.chat("/tbx vitals size 200")
    t.ok(H.hud().width > w, "a bigger vitals part widens the shared strip")
    H.chat("/tbx vitals flash test")
    local seen = {}
    for _ = 1, 10 do
      H.advance(0.2, 0.2)
      seen[H.hud():Find("health_bar").color] = true
    end
    t.ok(seen[Toolbox.Vitals.FLASH_COLOR], "flashes inside the shared strip")
  end)

  t.test("settings checkbox and chat for glue", function()
    H.boot()
    H.chat("/tbx config")
    H.change("toolbox_config", "toolbelt_vitals", "In Toolbelt")
    t.eq(Hud().IsGlued(), true)
    H.clearLogs()
    H.chat("/tbx vitals glue")
    t.ok(H.logged("in the Toolbelt"))
    H.chat("/tbx vitals glue off")
    t.eq(H.config():Find("toolbelt_vitals").value, "Own strip", "the dropdown follows the command")
    H.clearLogs()
    H.chat("/tbx vitals glue maybe")
    t.ok(H.logged("glue on|off"))
  end)

  t.test("a strip that fails to build is reported and doesn't stop the others", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx combat")
    local real = Toolbox.Combat.BuildContent
    Toolbox.Combat.BuildContent = function() error("boom") end
    H.clearLogs()
    H.call(Toolbox.Hud.Build)                          -- as from a callback
    Toolbox.Combat.BuildContent = real
    t.ok(H.logged("Couldn't build the combat HUD: .*boom"), H.lastLog())
    t.eq(H.frame().visible, true, "the buff bar still shows")
    t.eq(H.vitals().visible, true, "the vitals still show")
    H.clearLogs()
    H.chat("/tbx combat debug")
    t.ok(H.logged("combat: shown setting true; build error: .*boom; content missing; no strip"), H.lastLog())
  end)

  t.test("/tbx combat debug describes a working strip", function()
    H.boot()
    H.chat("/tbx combat")
    H.clearLogs()
    H.chat("/tbx combat debug")
    t.ok(H.logged("^combat: shown setting true; content built; strip own, visible true, size %d+ x %d+, at 40, 380"),
      H.lastLog())
  end)

  t.test("a strip that hits the creation cap at start-up is built again a moment later, quietly", function()
    local burst = H.CREATE_BURST
    H.CREATE_BURST = 250                         -- a tighter budget than a real start-up needs
    local ok, err = pcall(function()
      H.boot()
      H.chat("/tbx buffs")
      H.chat("/tbx vitals")
      H.chat("/tbx combat")
      H.chat("/tbx notify via hud")
      H.clearLogs()
      H.S.createBucket.tokens = 0                -- as if start-up had just used up the budget
      H.reload()
      t.no(H.logged("Couldn't build"), "no error in chat for the cap")
      H.advance(Toolbox.Hud.RETRY_DELAY * 2 + 1)
      t.ok(H.frame(), "the buff bar strip")
      t.ok(H.vitals(), "the health bars strip")
      t.ok(H.combatHud(), "the combat strip")
      t.ok(H.nhud(), "the notification HUD")
      t.no(H.logged("Couldn't build"), "still quiet")
    end)
    H.CREATE_BURST = burst
    if not ok then error(err, 0) end
  end)

  -- rebuilds never leave a module holding destroyed elements ---------------------

  -- Every glue / on / off change, with buffs and a consumable running, then ticks: nothing may touch
  -- an element the rebuild destroyed ("this Row was destroyed", reported 2026-09-29).
  local SEQUENCES = {
    { "/tbx buffs", "/tbx consumables glue on", "/tbx consumables bar off" },
    { "/tbx buffs", "/tbx consumables bar off", "/tbx consumables bar on", "/tbx consumables glue on" },
    { "/tbx buffs", "/tbx consumables glue on", "/tbx gear glue on", "/tbx buffs", "/tbx buffs" },
    { "/tbx buffs", "/tbx vitals", "/tbx vitals glue on", "/tbx consumables glue on", "/tbx vitals glue off",
      "/tbx consumables bar off" },
    { "/tbx buffs", "/tbx gear glue on", "/tbx gear bar off", "/tbx gear bar on", "/tbx gear glue off" },
    { "/tbx combat", "/tbx notify via hud", "/tbx xp", "/tbx xp hud", "/tbx vitals", "/tbx vitals glue on",
      "/tbx xp window", "/tbx combat" },
  }
  for n, seq in ipairs(SEQUENCES) do
    t.test("rebuilds leave no destroyed elements behind (sequence " .. n .. ")", function()
      H.boot()
      H.S.durationMode = "remaining"
      H.setGear{ { name = "Sword", durability = 5, maxDurability = 100 } }
      H.addBuffs({ { name = "RuneFood_Pie", remaining = 2700, total = 14544, icon = 46 },
                   { name = "Light", remaining = 100, total = 127, icon = 5 } })
      H.advance(2)
      for _, cmd in ipairs(seq) do
        H.chat(cmd)
        H.advance(1.5, 0.5)
      end
      H.advance(12)
      t.no(H.logged("destroyed"), "no chat error")
    end)
  end

  t.test("strips that fail at the creation cap mid-rebuild don't break the updates meanwhile", function()
    H.boot()
    H.S.durationMode = "remaining"
    for _, c in ipairs({ "/tbx buffs", "/tbx vitals", "/tbx combat", "/tbx notify via hud" }) do H.chat(c) end
    H.addBuffs({ { name = "RuneFood_Pie", remaining = 2700, total = 14544, icon = 46 },
                 { name = "Light", remaining = 100, total = 127, icon = 5 } })
    H.advance(2)
    H.S.createBucket.tokens = 20                         -- the next rebuild runs out part way
    H.call(function() Toolbox.Hud.Build() end)
    H.advance(Toolbox.Hud.RETRY_DELAY * (Toolbox.Hud.RETRY_MAX + 1) + 2, 0.5)   -- ticks while it retries
    t.no(H.logged("destroyed"))
    t.ok(H.frame() and H.frame().visible, "the buff bar is back")
    t.eq(#H.slots("buffs"), 1, "with its buff")
  end)
end

