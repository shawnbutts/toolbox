-- The buff block (Toolbox.BuffBlock, end of buffbar.lua): every buff and debuff on a strip of its own,
-- soonest to run out first, rows of the chosen width, nothing grouped.
local H = require("harness")

return function(t)
  local MB = function() return Toolbox.BuffBlock end

  local function frame() return H.S.frames.toolbox_buffblock end
  -- the visible icons, row by row: { { name, debuff outlined, tooltip }, ... } per row
  local function rows()
    local out = {}
    local box = frame() and frame():Find("buffblock")
    for _, row in ipairs(box and box.children or {}) do
      if row.id ~= "buffblock_placeholder" and row.visible ~= false then
        local r = {}
        for _, slot in ipairs(row.children) do
          if slot.visible ~= false then
            local tip = slot.children[1].tooltip or ""
            r[#r + 1] = { name = tip:match("^[^\n]+"), outlined = slot.style.borderWidth == 2, tip = tip, slot = slot }
          end
        end
        out[#out + 1] = r
      end
    end
    return out
  end
  local function names(r)
    local out = {}
    for i, x in ipairs(r) do out[i] = x.name end
    return table.concat(out, ",")
  end

  local function settled()
    H.boot()
    H.advance(Toolbox.BuffBar.SETTLE + 1)
  end
  local function buffs(n, extra)
    local list = {}
    for i = 1, n do list[#list + 1] = { name = "Buff" .. i, remaining = 100 + i * 50, icon = i } end
    for _, e in ipairs(extra or {}) do list[#list + 1] = e end
    H.addBuffs(list)
  end

  t.test("off by default: no strip, no frame", function()
    settled()
    buffs(3)
    t.eq(MB().GetShow(), false)
    t.eq(frame(), nil)
  end)

  t.test("every effect, soonest first, debuffs outlined; nothing grouped, consumables included", function()
    settled()
    buffs(12, { { name = "Bane", remaining = 120, icon = 40, debuff = true },
                { name = "BlessingOfStamina", remaining = 300000, total = 604800, icon = 70 },
                { name = "RuneFood_Stew", remaining = 600, total = 3600, icon = 71 },
                { name = "Stillness", remaining = -1, permanent = true, icon = 72 } })
    H.chat("/tbx buffs block on")
    H.advance(1)
    t.ok(frame().visible ~= false, "shown")
    local r = rows()
    t.eq(#r, 2, "16 effects, 10 a row")
    t.eq(names(r[1]), "Bane,Buff1,Buff2,Buff3,Buff4,Buff5,Buff6,Buff7,Buff8,Buff9")
    t.eq(names(r[2]), "Buff10,RuneFood_Stew,Buff11,Buff12,BlessingOfStamina,Stillness",
      "the food and the 7-day potion each have their own icon; the permanent one last")
    t.eq(r[1][1].outlined, true, "the debuff outlined in red")
    t.eq(r[1][2].outlined, false)
    t.eq(Toolbox.BuffBar.GetGroupAfter() > 0, true, "the buff bar still groups (it isn't affected)")
  end)

  t.test("short tooltips: name, debuff and the time left to the minute", function()
    settled()
    buffs(1, { { name = "Bane", remaining = 125, icon = 40, debuff = true,
                 tooltip = "Bane\n" .. string.rep("Long text. ", 40) } })
    H.chat("/tbx buffs block on")
    H.advance(1)
    local r = rows()[1]
    t.eq(r[1].tip, "Bane\nDebuff\n3 min left")
    t.eq(r[2].tip, "Buff1\n3 min left")
    t.eq(Toolbox.BuffBar.CoarseLeft(30), "Under a minute left")
    t.eq(Toolbox.BuffBar.CoarseLeft(5400), "1h 30m left")
    t.eq(Toolbox.BuffBar.CoarseLeft(0), "", "permanent")
  end)

  t.test("the width: icons a row; changing it rebuilds the rows; at most MB.SLOTS (40) icons", function()
    settled()
    buffs(16)
    H.chat("/tbx buffs block on")
    H.chat("/tbx buffs block width 4")
    H.advance(1)
    local r = rows()
    t.eq(#r, 4)
    t.eq(#r[4], 4)
    local cell = MB().GetSize() + Toolbox.BuffBar.GAP
    local w, h = MB().ContentSize()
    t.eq(w, 4 * cell)
    t.eq(h, 4 * cell)
    H.clearLogs()
    H.chat("/tbx buffs block width 99")
    t.ok(H.logged("width <1%-30>"), H.lastLog())
    H.chat("/tbx buffs block width 30")
    buffs(70)
    H.advance(1)
    local n = 0
    for _, row in ipairs(rows()) do n = n + #row end
    t.eq(n, MB().SLOTS, "capped")
  end)

  t.test("icon size: its own, resized in place", function()
    settled()
    buffs(3)
    H.chat("/tbx buffs block on")
    H.advance(1)
    local slot = rows()[1][1].slot
    H.chat("/tbx config")
    H.change("toolbox_config", "buffblock_size", 40)
    t.eq(rows()[1][1].slot, slot, "not rebuilt")
    t.eq(slot.style.width, 40)
    t.eq(Toolbox.BuffBar.GetSize(), Toolbox.BuffBar.SIZE_DEFAULT, "the buff bar keeps its size")
  end)

  t.test("only during combat; shown while settings are open, empty or not", function()
    settled()
    buffs(2)
    H.chat("/tbx buffs block on")
    H.chat("/tbx buffs block combat on")
    H.advance(1)
    t.eq(frame().visible, false, "out of combat")
    H.setCombat(true)
    H.advance(1)
    t.ok(frame().visible ~= false, "in combat")
    H.setCombat(false)
    H.advance(Toolbox.BuffBar.COMBAT_LINGER + 2)
    t.eq(frame().visible, false, "a little after")
    H.chat("/tbx config")
    H.advance(1)
    t.ok(frame().visible ~= false, "settings open: to place it")
    H.closeWindow("toolbox_config")
    H.S.buffs = {}
    H.callback("ShroudOnBuffsChanged")
    H.chat("/tbx buffs block combat off")
    H.advance(1)
    t.eq(frame().visible, false, "nothing to show: hidden")
    H.chat("/tbx config")
    H.advance(1)
    t.eq(frame():Find("buffblock_placeholder").visible, true, "its name, while settings are open")
  end)

  t.test("the buff bar's settings: replace the game's bar, click to dismiss", function()
    settled()
    buffs(1, { { name = "Shield", remaining = 60, icon = 102, dismissable = true } })
    H.chat("/tbx buffs replace on")
    t.no(H.S.stockHidden, "nothing of ours showing")
    H.chat("/tbx buffs block on")
    H.advance(1)
    t.ok(H.S.stockHidden, "the block replaces the game's bar too")
    H.chat("/tbx buffs dismiss on")
    H.advance(1)
    local shield = rows()[1][1]
    t.eq(shield.name, "Shield")
    t.ok(shield.tip:find("Click to dismiss$"), shield.tip)
    local icon = shield.slot.children[1]
    H.S.gesture = true
    H.call(icon.onClick, icon)
    H.S.gesture = false
    t.eq(H.S.dismissed and H.S.dismissed[1], "Shield")
    H.chat("/tbx buffs block off")
    H.advance(1)
    t.no(H.S.stockHidden, "off: the game's bar is back")
    t.eq(frame(), nil, "its frame freed")
  end)

  t.test("settings: the shared options stay usable with only the block on", function()
    settled()
    H.chat("/tbx config")
    t.eq(H.config():Find("buff_flash").enabled, false, "nothing showing: greyed out")
    H.chat("/tbx buffs block on")
    t.ok(H.config():Find("buff_flash").enabled ~= false, "the block flashes too")
    t.ok(H.config():Find("buff_replace").enabled ~= false)
    t.ok(H.config():Find("buff_dismiss").enabled ~= false)
    t.eq(H.config():Find("buffs_combat_only").enabled, false, "the buff bar's own: still greyed out")
    t.eq(H.config():Find("buff_group_after").enabled, false)
    H.change("toolbox_config", "buff_flash", false)
    t.eq(Toolbox.BuffBar.GetFlash(), false)
  end)

  t.test("saved and read back; a Position row; the command", function()
    settled()
    H.chat("/tbx buffs block on")
    H.chat("/tbx buffs block width 6")
    H.chat("/tbx buffs block size 28")
    H.reload()
    t.eq(MB().GetShow(), true)
    t.eq(MB().GetWidth(), 6)
    t.eq(MB().GetSize(), 28)
    H.chat("/tbx config")
    t.ok(H.config():Find("buffblock_pos"), "HUD layout has it")
    t.eq(H.config():Find("show_buffblock").value, true)
    H.clearLogs()
    H.chat("/tbx buffs block")
    t.ok(H.logged("Buff block: off, 6 icons a row, size 28%."), H.lastLog())
    H.chat("/tbx buffs block move 300 200")
    t.eq(H.saved("buffblock").show, false)
  end)
end
