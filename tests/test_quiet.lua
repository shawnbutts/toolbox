-- Muted effects (Toolbox.BuffBar.Mute / Unmute): no expiry or debuff sound for chosen effects, picked from
-- dropdowns of recent alerts, effects on you and effects seen cast. Their icons still flash and turn red.
local H = require("harness")

return function(t)
  local B = function() return Toolbox.BuffBar end
  local function bootWithSounds()
    H.boot()
    H.S.files["toolbox_buff_expiring.ogg"] = true
    H.S.files["toolbox_debuff_landed.ogg"] = true
    H.reload()
    H.advance(Toolbox.BuffBar.SETTLE)
    H.S.played = {}
  end
  local function choices()
    local out = {}
    for _, c in ipairs(B().QuietChoices()) do out[#out + 1] = c.label end
    return table.concat(out, ", ")
  end

  t.test("a muted buff's expiry plays no sound; others still sound", function()
    bootWithSounds()
    H.chat("/tbx buffs")
    H.chat("/tbx buffalert 5")
    B().Mute("Heal")
    H.addBuffs({ { name = "Heal", remaining = 12, icon = 101 }, { name = "Shield", remaining = 14, icon = 102 } })
    H.advance(8, 0.5)
    t.eq(H.playedNames(), "", "Heal muted")
    H.advance(2, 0.5)
    t.eq(H.playedNames(), "toolbox_buff_expiring", "Shield still sounds")
    t.ok(B().IsMuted("Heal"))
  end)

  t.test("a muted debuff plays no sound; another debuff landing with it still does", function()
    bootWithSounds()
    B().Mute("Bleed")
    H.addBuffs({ { name = "Bleed", remaining = 20, debuff = true } })
    t.eq(H.playedNames(), "")
    t.ok(B().lastDebuff.result:find("muted"), B().lastDebuff.result)
    H.advance(2)
    H.addBuffs({ { name = "Poison", remaining = 20, debuff = true } })
    t.eq(H.playedNames(), "toolbox_debuff_landed")
  end)

  t.test("the choices: recent alerts first, then what's on you, then effects seen cast; muted ones left out", function()
    bootWithSounds()
    H.chat("/tbx buffalert off")                      -- Light runs out without alerting
    H.addBuffs({ { name = "Light", remaining = 30 } })
    H.advance(31, 0.5)                                -- seen cast and run out: learned
    H.addBuffs({ { name = "Bleed", remaining = 20, debuff = true }, { name = "Stillness", remaining = 600 } })
    H.advance(1)
    t.eq(choices(), "Bleed (alerted), Stillness (on you), Light", choices())
    B().Mute("Bleed")
    t.eq(choices(), "Stillness (on you), Light", "muted ones aren't offered")
  end)

  t.test("settings: pick and Mute, pick and Unmute; kept across a reload", function()
    bootWithSounds()
    H.addBuffs({ { name = "Bleed", remaining = 20, debuff = true } })
    H.advance(1)
    H.chat("/tbx config")
    local w = H.config()
    t.eq(w:Find("quiet_pick").value, "Bleed (alerted)")
    H.click("toolbox_config", "quiet_mute")
    t.ok(w:Find("quiet_msg").text:find("'Bleed' is muted"), w:Find("quiet_msg").text)
    t.eq(w:Find("quiet_list").value, "Bleed")
    H.reload()
    t.ok(B().IsMuted("Bleed"), "saved")
    H.chat("/tbx config")
    w = H.config()
    H.click("toolbox_config", "quiet_unmute")
    t.no(B().IsMuted("Bleed"))
    t.eq(w:Find("quiet_list").value, "None muted")
  end)

  t.test("chat: /tbx buffs quiet lists; add and remove by name", function()
    bootWithSounds()
    H.addBuffs({ { name = "Bleed", remaining = 20, debuff = true } })
    H.clearLogs()
    H.chat("/tbx buffs quiet")
    t.ok(H.logged("^Muted %(no sound%): none%."), H.logs()[1])
    t.ok(H.logged("^Recent alerts: Bleed%."))
    H.chat("/tbx buffs quiet add Bleed")
    t.ok(B().IsMuted("Bleed"))
    H.clearLogs()
    H.chat("/tbx buffs quiet add Bleed")
    t.ok(H.logged("already muted"))
    H.chat("/tbx buffs quiet remove bleed")
    t.no(B().IsMuted("Bleed"))
  end)
end
