-- The combat shout (Toolbox.CombatShout, end of combat.lua): "Block!", "Parry!", "Dodge!" over the Toolbelt
-- when you avoid an attack, with a sound for each.
local H = require("harness")

return function(t)
  local CS = function() return Toolbox.CombatShout end

  local function boot(withSounds)
    H.boot()
    if withSounds then
      for _, f in ipairs({ "block", "parry", "dodge" }) do H.S.files["toolbox/" .. f .. ".ogg"] = true end
      H.reload()
    end
    H.advance(3)
    H.S.played = {}
  end
  local function hit(kind, extra)
    local e = { kind = kind, toYou = true, source = "Wolf", sourceKey = 7, amount = 0, rune = "Bite",
                time = ShroudTime }
    for k, v in pairs(extra or {}) do e[k] = v end
    H.combat({ e })
  end
  local function shout()
    for _, id in ipairs({ "toolbox_buffs", "toolbox_hud" }) do
      local f = H.S.frames[id]
      local box = f and f:Find("combat_shout")
      if box then return box end
    end
    return nil
  end
  local function word(box) return box.children[#box.children] end
  local function played(name)
    local n = 0
    for _, p in ipairs(H.S.played) do if p.name:find(name, 1, true) then n = n + 1 end end
    return n
  end

  t.test("off by default: nothing shown, nothing played", function()
    boot(true)
    H.chat("/tbx buffs")
    hit("block")
    t.eq(CS().GetOn(), false)
    t.eq(shout().visible, false)
    t.eq(#H.S.played, 0)
  end)

  t.test("a block: \"Block!\" over the Toolbelt for a moment, outlined, with its sound", function()
    boot(true)
    H.chat("/tbx buffs")
    H.chat("/tbx combat shout on")
    local frame = H.S.frames.toolbox_buffs
    local w, h = frame.width, frame.height
    hit("block")
    local box = shout()
    t.ok(box.visible ~= false, "shown")
    t.eq(word(box).text, "Block!")
    t.eq(word(box).style.color, "@blue", "its colour")
    t.eq(#box.children, #CS().OUTLINE + 1, "outlined: dark copies under the word")
    t.eq(box.children[1].style.color, CS().OUTLINE_COLOR)
    t.eq(played("block"), 1, H.playedNames())
    t.eq(frame.width, w, "over the Toolbelt: it doesn't change its size")
    t.eq(frame.height, h)
    t.ok(box.style.marginTop < 0, "pulled up over the rows")
    H.advance(2, 0.25)
    t.eq(box.visible, false, "gone after a moment")
  end)

  t.test("only yours: an attack of yours blocked, or a party member's, doesn't shout", function()
    boot(true)
    H.chat("/tbx buffs")
    H.chat("/tbx combat shout on")
    hit("parry", { toYou = false, fromYou = true })
    hit("dodge", { toYou = false, party = true })
    t.eq(shout().visible, false)
    t.eq(#H.S.played, 0)
    hit("parry")
    t.eq(word(shout()).text, "Parry!")
    t.eq(word(shout()).style.color, "@gold")
    t.eq(played("parry"), 1)
  end)

  t.test("in the Toolbelt with the health bars: over the whole strip", function()
    boot(true)
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")
    H.chat("/tbx combat shout on")
    hit("dodge")
    local box = H.hud():Find("combat_shout")
    t.ok(box and box.visible ~= false, "in the shared strip")
    t.eq(word(box).text, "Dodge!")
    t.eq(box.style.marginLeft, Toolbox.Window.GRIP, "starting where the parts start")
    t.ok(box.style.width > Toolbox.Vitals.ContentSize(), "as wide as all of it")
  end)

  t.test("each kind: its text, colour and sound on or off; one sound per kind in a burst", function()
    boot(true)
    H.chat("/tbx buffs")
    H.chat("/tbx combat shout on")
    H.chat("/tbx config")
    H.change("toolbox_config", "shout_block_text", false)
    H.change("toolbox_config", "shout_parry_sound", false)
    H.change("toolbox_config", "shout_dodge_color", "Red")
    hit("block")
    t.eq(shout().visible, false, "Block!: off")
    t.eq(played("block"), 1, "its sound still on")
    hit("parry")
    t.eq(word(shout()).text, "Parry!")
    t.eq(played("parry"), 0, "Parry sound: off")
    H.advance(1)
    hit("dodge")
    t.eq(word(shout()).style.color, "@red")
    hit("dodge")
    t.eq(played("dodge"), 1, "two dodges at once: one sound")
    H.advance(1)
    hit("dodge")
    t.eq(played("dodge"), 2)
  end)

  t.test("text size: in place; Test shows it whatever the settings; saved", function()
    boot(true)
    H.chat("/tbx buffs")
    H.chat("/tbx config")
    H.click("toolbox_config", "shout_parry_test")
    t.eq(word(shout()).text, "Parry!", "Test works with the shout off")
    t.eq(played("parry"), 1)
    H.change("toolbox_config", "shout_on", true)
    local box = shout()
    H.change("toolbox_config", "shout_size", 18)
    t.eq(shout(), box, "not rebuilt")
    t.eq(word(box).style.fontSize, 18)
    H.reload()
    t.eq(CS().GetOn(), true)
    t.eq(CS().GetSize(), 18)
    H.clearLogs()
    H.chat("/tbx combat shout test dodge")
    t.eq(word(shout()).text, "Dodge!")
    H.chat("/tbx combat shout off")
    t.ok(H.logged("shouts: off"), H.lastLog())
  end)

  t.test("Test: its sound every press, and chat says why when it can't play", function()
    boot(true)
    H.chat("/tbx buffs")
    H.chat("/tbx config")
    H.click("toolbox_config", "shout_block_test")
    H.click("toolbox_config", "shout_block_test")
    t.eq(played("block"), 2, "pressed twice in a row: twice (no burst limit for Test)")
    H.chat("/tbx sounds 0")
    H.clearLogs()
    H.click("toolbox_config", "shout_parry_test")
    t.ok(H.logged("Parry sound: the alert volume is 0%."), H.lastLog())
    t.eq(word(shout()).text, "Parry!", "the word still shows")
  end)

  t.test("no Toolbelt: the sounds still play, nothing breaks", function()
    boot(true)
    H.chat("/tbx combat shout on")
    t.eq(Toolbox.BuffBar.IsEnabled(), false, "the Toolbelt off")
    hit("block")
    t.eq(played("block"), 1)
    t.eq(H.S.frames.toolbox_buffs.visible, false, "nothing on screen")
  end)
end
