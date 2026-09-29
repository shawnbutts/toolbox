-- The target HUD (Toolbox.Target, in vitals.lua): the target's health and effects, on its own strip or
-- as the Toolbelt's last row.
local H = require("harness")

return function(t)
  local TG = function() return Toolbox.Target end

  local WOLF = { id = 7, name = "Wolf", hp = 750, maxHp = 1000, focus = 0, maxFocus = 0, effects = {
    { name = "Poisoned", remaining = 10, total = 20, icon = 41, debuff = true, category = "Poison" },
    { name = "Bleed", remaining = 4, total = 8, icon = 42, debuff = true },
    { name = "Enraged", remaining = 30, total = 60, icon = 43 },
    { name = "Poisoned", remaining = 6, total = 20, icon = 41, debuff = true },     -- a second component
  } }

  local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
  end

  local function slotNames()
    local out = {}
    for _, slot in ipairs(H.targetSlots()) do out[#out + 1] = tostring(slot.children[1].tooltip):match("^[^\n]+") end
    return table.concat(out, ",")
  end

  -- model ---------------------------------------------------------------------

  t.test("HealthText: percent, hidden, dead", function()
    H.boot()
    t.eq(TG().HealthText(750, 1000, false, false), "75%")
    t.eq(TG().HealthText(1000, 1000, true, false), "health hidden")
    t.eq(TG().HealthText(0, 1000, false, true), "dead")
    t.eq(TG().HealthText(-1, -1, false, false), "", "no target: nothing")
  end)

  t.test("CleanName: the game's 'no name' fallback becomes a readable name", function()
    H.boot()
    t.eq(TG().CleanName("Wolf"), "Wolf", "real names untouched")
    t.eq(TG().CleanName("Entity with no name (Stag_04_Large(Clone))"), "Stag Large")
    t.eq(TG().CleanName("entity with no name (Stag_04_Large(Clone)"), "Stag Large", "any case, a missing bracket")
    t.eq(TG().CleanName("Entity with no name"), "Unnamed")
    t.eq(TG().CleanName("Entity with no name (_01_(Clone))"), "Unnamed")
    t.eq(TG().CleanName(nil), "")
  end)

  t.test("an unnamed creature shows the tidied name, with the game's text in the tooltip", function()
    H.boot()
    H.chat("/tbx target on")
    H.setTarget({ id = 9, name = "Entity with no name (Stag_04_Large(Clone))", hp = 100, maxHp = 100, effects = {} })
    t.eq(H.targetRow():Find("target_name").text, "Stag Large  100%")
    t.ok(H.targetRow():Find("target_info").tooltip:find("(Entity with no name (Stag_04_Large(Clone)))", 1, true))
  end)

  t.test("Collect: one per name (the longest left), debuffs first, then soonest, capped", function()
    H.boot()
    local raw = { { name = "B", remaining = 5, index = 0 }, { name = "A", remaining = 9, index = 1 },
                  { name = "B", remaining = 7, index = 2 }, { name = "C", remaining = 0, index = 3 },
                  { name = "D", remaining = 2, index = 4 } }
    local info = { A = { debuff = true, total = 10 }, B = { debuff = false, total = 8 } }
    local out = {}
    t.eq(TG().Collect(raw, #raw, info, out, 8), 4)
    t.eq(out[1].name, "A", "the debuff first")
    t.eq(out[2].name, "D", "then the soonest")
    t.eq(out[3].name, "B")
    t.eq(out[3].remaining, 7, "the longest-lasting component")
    t.eq(out[3].index, 2)
    t.eq(out[4].name, "C", "permanent (0 left) last")
    t.eq(TG().Collect(raw, #raw, info, out, 2), 2)
    t.eq(#out, 2, "capped")
  end)

  -- the strip -----------------------------------------------------------------

  t.test("off by default; on its own strip it shows the target's name, health and effects", function()
    H.boot()
    t.eq(TG().GetShow(), false)
    t.eq(H.targetFrame(), nil, "no strip while off")
    H.chat("/tbx target on")
    H.setTarget(copy(WOLF))
    t.ok(H.targetFrame(), "its own strip (the Toolbelt is off)")
    t.eq(H.targetFrame().visible, true)
    t.eq(H.targetRow():Find("target_name").text, "Wolf  75%")
    t.eq(H.targetRow():Find("target_health").value, 0.75)
    t.eq(H.targetRow():Find("target_focus").visible, false, "no focus bar for a creature without focus")
    t.eq(slotNames(), "Bleed,Poisoned,Enraged", "debuffs first (soonest first), one per name")
    t.eq(H.targetSlots()[1].style.borderWidth, 2, "debuffs outlined")
    t.eq(H.targetSlots()[3].style.borderWidth, 0)
    t.ok(H.targetRow():Find("target_info").tooltip:find("Health 750 / 1,000", 1, true))
  end)

  t.test("health follows the target; hidden and dead read as the game shows them", function()
    H.boot()
    H.chat("/tbx target on")
    H.setTarget(copy(WOLF))
    H.S.target.hp = 300
    H.advance(1)
    t.eq(H.targetRow():Find("target_name").text, "Wolf  30%")
    t.eq(H.targetRow():Find("target_health").value, 0.3)
    H.S.target.hidden = true
    H.advance(1)
    t.eq(H.targetRow():Find("target_name").text, "Wolf  health hidden")
    t.eq(H.targetRow():Find("target_health").value, 1, "a full bar, like the game's target frame")
    H.S.target.hidden, H.S.target.dead = false, true
    H.advance(1)
    t.eq(H.targetRow():Find("target_name").text, "Wolf  dead")
    t.eq(H.targetRow():Find("target_health").value, 0)
    H.setTarget({ id = 8, name = "Mage", hp = 500, maxHp = 500, focus = 200, maxFocus = 400, effects = {} })
    t.eq(H.targetRow():Find("target_name").text, "Mage  100%", "a new target at once, from the event")
    t.eq(H.targetRow():Find("target_focus").visible, true)
    t.eq(H.targetRow():Find("target_focus").value, 0.5)
    t.eq(#H.targetSlots(), 0)
  end)

  t.test("no target: the strip hides (it shows while settings are open, to place it)", function()
    H.boot()
    H.chat("/tbx target on")
    H.setTarget(copy(WOLF))
    t.eq(H.targetFrame().visible, true)
    H.setTarget(nil)
    t.eq(H.targetFrame().visible, false)
    H.chat("/tbx config")
    H.advance(1)
    t.eq(H.targetFrame().visible, true, "while settings are open")
    t.eq(H.targetRow():Find("target_name").text, "Target (none)")
  end)

  t.test("effect sweeps show the time left, and use the buff bar's shared drawing budget", function()
    H.boot()
    H.chat("/tbx target on")
    H.setTarget(copy(WOLF))
    local bleed = H.targetSlots()[1]
    t.eq(bleed.children[2].visible, true, "a sweep")
    local img = bleed.children[2].children[1]
    t.ok(img and img.uv, "drawn as a clock frame")
    local k = Toolbox.BuffBar.Frame(4 / 8)
    local x, y = Toolbox.BuffBar.FrameUV(k, false)
    t.eq(img.uv[1], x)
    t.eq(img.uv[2], y)
  end)

  t.test("in the Toolbelt: the last row of the buff bar's strip, and it fits the strip", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx target on")                      -- joins the Toolbelt by default
    t.eq(TG().Glued(), true)
    t.eq(H.targetFrame(), nil, "no strip of its own")
    H.setTarget(copy(WOLF))
    local row = H.targetRow()
    t.ok(row, "a row in the buff bar's strip")
    t.eq(row.visible, true)
    local cell = Toolbox.BuffBar.GetSize() + Toolbox.BuffBar.GAP
    t.eq(row:Find("target_name"), nil, "no name in the Toolbelt (it's in the tooltip)")
    t.eq(row:Find("target_pct"), nil, "no percent either")
    t.ok(row:Find("target_info").tooltip:find("^Wolf"), "the name in the tooltip")
    t.ok(row:Find("target_info").tooltip:find("Health 750 / 1,000", 1, true), "and the numbers")
    local V = Toolbox.Vitals
    t.eq(row:Find("target_health").style.width, V.Metrics().barW, "the player's bar length")
    t.eq(row:Find("target_health").style.height, V.Metrics().barH, "and thickness")
    local cells = math.ceil((V.Metrics().barW + Toolbox.BuffBar.GAP) / cell)
    t.ok(H.frame().width >= Toolbox.Window.GRIP + (cells + 3) * cell, "wide enough: " .. H.frame().width)
    V.SetWidth(100)
    V.SetScale(150)
    t.eq(row:Find("target_health").style.width, 150, "follows the health bars' Bar length and Size")
    H.setTarget(nil)
    H.advance(1)
    t.eq(H.targetRow().visible, true, "on top (the default) it keeps its space with no target")
    t.eq(H.targetRow():Find("target_info").visible, false, "empty, not a bar at 0")
    t.eq(#H.targetSlots(), 0)
    H.chat("/tbx target toolbelt off")
    t.ok(H.targetFrame(), "its own strip again")
    H.chat("/tbx buffs")                          -- the Toolbelt off: a glued target falls back to its strip
    H.chat("/tbx target toolbelt on")
    t.ok(H.targetFrame(), "own strip while the Toolbelt is off")
    H.clearLogs()
    H.chat("/tbx target")
    t.ok(H.logged("Target HUD: on, its own strip %(the Toolbelt is off%)%."), H.lastLog())
  end)

  t.test("with the health bars in the Toolbelt: under both columns, lined up with the health bars", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")
    H.chat("/tbx target on")
    t.eq(TG().Below(), true)
    H.setTarget(copy(WOLF))
    local glued = H.hud()
    t.ok(glued, "the shared strip")
    local row = H.targetRow()
    t.eq(row.style.marginLeft, Toolbox.Window.GRIP, "starts where the health bars start")
    local vitalsRow = glued:Find("vitals")
    t.ok(vitalsRow, "the health bars' column is in the same strip")
    t.eq(row:Find("target_health").style.width, Toolbox.Vitals.Metrics().barW, "your bars' length")
    local vw = Toolbox.Vitals.ContentSize()
    t.eq(row:Find("target_info").style.width + Toolbox.BuffBar.GAP, vw + Toolbox.Hud.GAP,
      "the icons start where the buff icons start")
    t.eq(#H.targetSlots(), 3)
    local n = 0
    local function count(e)
      if e.id == "target" then n = n + 1 end
      for _, c in ipairs(e.children or {}) do count(c) end
    end
    count(glued)
    t.eq(n, 1, "one target row, not also in the buff column")
    H.setTarget(nil)
    H.advance(1)
    t.eq(row.visible, true, "on top: its space kept")
    H.chat("/tbx vitals glue off")                -- health bars on their own: back to the buff column
    t.eq(TG().Below(), false)
    t.ok(H.targetRow(), "rebuilt in the buff column")
  end)

  t.test("in the Toolbelt: on top of the buffs by default, or under everything", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")
    H.chat("/tbx target on")
    H.setTarget(copy(WOLF))
    local column = H.hud().children[1]
    t.eq(TG().Place(), "top")
    t.eq(column.children[1].id, "target", "above the columns")
    H.chat("/tbx target place bottom")
    column = H.hud().children[1]
    t.eq(column.children[#column.children].id, "target", "under them")
    H.setTarget(nil)
    H.advance(1)
    t.eq(H.targetRow().visible, false, "at the bottom it hides with no target (nothing under it moves)")
    H.chat("/tbx vitals glue off")                -- the buff column: first row or last
    local buffCol = H.frame():Find("buffbar")
    t.eq(buffCol.children[#buffCol.children].id, "target")
    H.chat("/tbx target place top")
    buffCol = H.frame():Find("buffbar")
    t.eq(buffCol.children[1].id, "target")
    t.eq(H.saved("target").place, "top")
    H.clearLogs()
    H.chat("/tbx target place middle")
    t.ok(H.logged("place top|bottom"), H.lastLog())
    H.chat("/tbx config")
    t.eq(H.config():Find("target_place").value, "Above the buffs")
    H.change("toolbox_config", "target_place", "Under everything")
    t.eq(TG().Place(), "bottom")
  end)

  t.test("mirrored on the left of the health bars: bars filling from the right, icons outward, space kept", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")
    H.chat("/tbx target on")
    H.chat("/tbx target place left")
    t.eq(TG().Place(), "left")
    H.setTarget(copy(WOLF))
    local columns = H.hud().children[1]
    local row = H.targetRow()
    t.eq(columns.children[1].id, "target", "first, left of the health bars")
    t.eq(columns.children[2].id, "vitals")
    t.eq(row:Find("target_health").style.rotate, 180, "a mirror of your bars")
    t.eq(row:Find("target_health").style.width, Toolbox.Vitals.Metrics().barW)
    local kids = row.children
    t.eq(kids[#kids].id, "target_info", "the bars against yours")
    t.eq(#H.targetSlots(), 3)
    t.eq(kids[#kids - 1].visible, true, "the most urgent icon nearest the bars")
    t.eq(tostring(kids[#kids - 1].children[1].tooltip):match("^[^\n]+"), "Bleed")
    local cell = Toolbox.BuffBar.GetSize() + Toolbox.BuffBar.GAP
    local width = row.style.width
    t.eq(width, TG().LEFT_SLOTS * cell + Toolbox.Vitals.Metrics().barW, "a fixed width")
    H.setTarget(nil)
    H.advance(1)
    t.eq(row.visible, true, "kept with no target, so your bars don't move")
    t.eq(row.style.width, width)
    H.chat("/tbx vitals glue off")                -- no health bars in the Toolbelt: works like "top"
    t.eq(TG().Place(), "top")
    t.eq(TG().GetPlace(), "left", "the choice is kept for when they come back")
    t.eq(H.frame():Find("buffbar").children[1].id, "target")
    H.chat("/tbx vitals glue on")
    t.eq(H.hud().children[1].children[1].id, "target", "and back on the left")
    Toolbox.Vitals.SetScale(150)
    t.eq(H.targetRow():Find("target_health").style.width, Toolbox.Vitals.Metrics().barW, "follows your bars' size")
    H.chat("/tbx config")
    t.eq(H.config():Find("target_place").value, "Left of your bars (mirrored)")
  end)

  t.test("rebuilding the Toolbelt lets go of the old row (no 'this Row was destroyed')", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx target on")
    H.setTarget(copy(WOLF))
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")                 -- a full rebuild
    H.chat("/tbx consumables glue on")
    H.S.target.hp = 100
    H.advance(1)
    t.eq(H.targetRow():Find("target_health").value, 0.1)
    H.chat("/tbx target off")
    H.advance(1)
    t.eq(H.targetRow(), nil)
    H.chat("/tbx buffs size 40")
    H.chat("/tbx target on")
    H.advance(1)
    t.ok(H.targetRow())
  end)

  t.test("settings: Off / Own strip / In Toolbelt, the summary and the position rows", function()
    H.boot()
    H.chat("/tbx config")
    local w = H.config()
    t.eq(w:Find("toolbelt_target").value, "Off")
    H.change("toolbox_config", "toolbelt_target", "In Toolbelt")
    t.eq(TG().GetShow(), true)
    t.eq(Toolbox.BuffBar.IsEnabled(), true, "the Toolbelt too")
    t.ok(w:Find("hud_summary").text:find("Buffs %+ Target"), w:Find("hud_summary").text)
    H.change("toolbox_config", "toolbelt_target", "Own strip")
    t.ok(H.targetFrame())
    t.ok(w:Find("target_pos"), "placed under HUD layout")
    H.chat("/tbx target move 300 200")
    t.eq(select(1, TG().GetPosition()), 300)
  end)

  t.test("debug lists what the game reports", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx target debug")
    t.ok(H.logged("^No target"), H.lastLog())
    H.chat("/tbx target on")
    H.setTarget(copy(WOLF))
    H.clearLogs()
    H.chat("/tbx target debug")
    t.ok(H.logged('^Target "Wolf" %(id 7%): health 750 / 1000'), H.logs()[1])
    t.ok(H.logged("Effects %(flat%): 4"))
    t.ok(H.logged("Bleed: 4 s left, icon 42, debuff, of 8 s"))
  end)

  t.test("a ninth HUD strip isn't built: the player is told once", function()
    H.boot()
    for _, cmd in ipairs({ "/tbx buffs", "/tbx vitals", "/tbx combat", "/tbx xp", "/tbx xp hud", "/tbx daily",
                           "/tbx daily hud", "/tbx notify via hud", "/tbx gear bar on" }) do
      H.chat(cmd)
    end
    H.clearLogs()
    H.chat("/tbx target on")
    H.chat("/tbx target toolbelt off")
    local n = 0
    for _ in pairs(H.S.frames) do n = n + 1 end
    t.ok(n <= 8, n .. " HUD frames")
    t.ok(H.logged("No room for the target strip"), H.lastLog())
    H.clearLogs()
    H.advance(2)
    t.no(H.logged("No room"), "said once")
    H.chat("/tbx target toolbelt on")
    t.ok(H.targetRow(), "in the Toolbelt it fits")
  end)

  -- UI calls and garbage per second over `secs` seconds (as test_perf.lua measures them).
  local function measure(secs)
    local calls = 0
    local mt = getmetatable(H.targetRow())
    local saved = {}
    for _, m in ipairs({ "SetText", "SetStyle", "SetTooltip", "SetValue", "SetVisible", "SetUV", "SetTexture",
                         "SetSize" }) do
      saved[m] = mt[m]
      mt[m] = function(self, ...)
        calls = calls + 1
        return saved[m](self, ...)
      end
    end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    H.advance(secs)
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    for m, f in pairs(saved) do mt[m] = f end
    return calls / secs, kb / secs
  end

  t.test("cheap per tick: nothing without a target, a few calls a second with one", function()
    H.boot()
    H.chat("/tbx target on")
    H.advance(2)
    local reads = H.S.targetBuffReads or 0
    local calls = measure(30)
    t.eq(H.S.targetBuffReads or 0, reads, "the grouped list isn't read without a target")
    t.ok(calls <= 0.2, string.format("no target: %.1f UI calls/s", calls))
    local wolf = copy(WOLF)
    for _, e in ipairs(wolf.effects) do e.remaining = e.remaining + 1000 end   -- lasting the whole minute
    H.setTarget(wolf)
    H.advance(2)
    local withCalls, kb = measure(30)
    if os.getenv("STRESS_PRINT") then print(string.format("  target: %.1f calls/s, %.1f KB/s", withCalls, kb)) end
    t.ok(withCalls <= 8, string.format("with a target: %.1f UI calls/s", withCalls))
    if not rawget(_G, "jit") then t.ok(kb <= 12, string.format("with a target: %.1f KB/s of garbage", kb)) end
    t.ok((H.S.targetBuffReads or 0) - reads <= 17, "the grouped list every few seconds, not every poll")
  end)
end
