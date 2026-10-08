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

  t.test("muted effects go by their shown name (the blessing's), the rune name only to tell two apart", function()
    bootWithSounds()
    H.addBuffs({ { name = "Reward_Blessing_CastleAtos4_7", label = "+5 Health", remaining = 600,
                   tooltip = "Blessing of Atos\nYou\n+5 Health\n10:00" },
                 { name = "Reward_Blessing_CastleAtos4_7", label = "+5 Health", remaining = 600,
                   tooltip = "Blessing of Atos\nYou\n+5 Focus\n10:00" },
                 { name = "Shrine_Atos", label = "+1 Health", remaining = 600,
                   tooltip = "Blessing of Atos\nYou\n+1 Health\n10:00" },
                 { name = "Stillness", remaining = 600 } })
    H.advance(1)
    t.eq(choices(), "Blessing of Atos [Reward_Blessing_CastleAtos4_7] (on you), Blessing of Atos [Shrine_Atos] "
      .. "(on you), Stillness (on you)", choices())
    H.chat("/tbx config")
    local w = H.config()
    H.change("toolbox_config", "quiet_pick", "Blessing of Atos [Shrine_Atos] (on you)")
    H.click("toolbox_config", "quiet_mute")
    t.ok(B().IsMuted("Shrine_Atos"), "the rune name is what is muted")
    t.ok(w:Find("quiet_msg").text:find("'Blessing of Atos' is muted", 1, true), w:Find("quiet_msg").text)
    t.eq(w:Find("quiet_list").value, "Blessing of Atos")
    H.clearLogs()
    H.chat("/tbx buffs quiet add blessing of atos")    -- typed: the one not muted yet
    t.ok(B().IsMuted("Reward_Blessing_CastleAtos4_7"), H.logs())
    H.chat("/tbx buffs quiet")
    t.ok(H.logged("^Muted %(no sound%): Blessing of Atos %[Reward_Blessing_CastleAtos4_7%], "
      .. "Blessing of Atos %[Shrine_Atos%]%.$"), H.logs())
    H.reload()                                          -- not on you any more: their shown names were kept
    H.clearLogs()
    H.chat("/tbx buffs quiet remove Blessing of Atos")
    t.ok(H.logged("is the name of several effects; use the name in brackets: Reward_Blessing_CastleAtos4_7, "
      .. "Shrine_Atos%.$"), H.logs())
    H.chat("/tbx buffs quiet remove shrine_atos")
    t.ok(H.logged("'Blessing of Atos' sounds again%."), H.logs())
    t.no(B().IsMuted("Shrine_Atos"))
    t.ok(B().IsMuted("Reward_Blessing_CastleAtos4_7"))
    H.chat("/tbx buffs quiet remove Blessing of Atos")   -- now only one muted by that name
    t.no(B().IsMuted("Reward_Blessing_CastleAtos4_7"))
    H.clearLogs()
    H.chat("/tbx buffs quiet add reward_blessing_castleatos4_7")   -- a rune name in another case
    t.ok(B().IsMuted("Reward_Blessing_CastleAtos4_7"), "muted as the game spells it (alerts look that up)")
    t.ok(H.logged("'Blessing of Atos' is muted"), "named by its shown name")
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
  -- Don't repeat (owner, 2026-10-07): an effect alerting again within the quiet time stays quiet; each alert
  -- starts the time again; expiry and debuff counted apart; off by default.
  t.test("don't repeat: the model; each alert starts the time again", function()
    local seen = {}
    t.no(B().Repeats(seen, "Bleed", 0, 120), "the first")
    t.ok(B().Repeats(seen, "Bleed", 100, 120), "100 s later")
    t.ok(B().Repeats(seen, "Bleed", 200, 120), "100 s after that: the time started again")
    t.no(B().Repeats(seen, "Bleed", 321, 120), "121 s with none")
    t.no(B().Repeats(seen, "Poison", 322, 120), "each effect its own")
    t.no(B().Repeats(seen, "Bleed", 330, 0), "off")
  end)

  t.test("don't repeat: a debuff landing all fight sounds once; another still sounds; then again after", function()
    bootWithSounds()
    t.eq(B().GetRepeat(), 0, "off by default")
    H.chat("/tbx buffs repeat 2")
    t.eq(H.saved("buffbar").repeatQuiet, 120)
    local function land(name)
      H.addBuffs({ { name = name, remaining = 10, debuff = true } })
      H.advance(10)
      H.removeBuff(name)
      H.advance(10)
    end
    land("Bleed")
    t.eq(H.playedNames(), "toolbox_debuff_landed")
    H.S.played = {}
    for _ = 1, 9 do land("Bleed") end              -- three minutes of it
    t.eq(H.playedNames(), "", "quiet while it keeps coming")
    t.ok(B().lastDebuff.result:find("Don't repeat"), B().lastDebuff.result)
    land("Poison")
    t.eq(H.playedNames(), "toolbox_debuff_landed", "another debuff still sounds")
    H.S.played = {}
    H.advance(121)
    land("Bleed")
    t.eq(H.playedNames(), "toolbox_debuff_landed", "two minutes without it: sounds again")
  end)

  t.test("don't repeat: a recast buff's expiry sounds once; off, it sounds each time", function()
    bootWithSounds()
    H.chat("/tbx buffs")
    H.chat("/tbx buffalert 5")
    H.chat("/tbx buffs repeat 30s")
    local function cast()
      H.addBuffs({ { name = "Heal", remaining = 12, icon = 101 } })
      H.advance(12, 0.5)
      H.removeBuff("Heal")
      H.advance(Toolbox.BuffBar.GRACE + 1)
    end
    cast()
    t.eq(H.playedNames(), "toolbox_buff_expiring")
    H.S.played = {}
    cast()
    t.eq(H.playedNames(), "", "recast within 30 s of its last alert")
    H.chat("/tbx buffs repeat off")
    cast()
    t.eq(H.playedNames(), "toolbox_buff_expiring", "off: every time")
  end)

  t.test("don't repeat: the settings dropdown and the chat command", function()
    bootWithSounds()
    H.chat("/tbx config")
    local w = H.config()
    t.eq(w:Find("buff_repeat").value, "Off")
    H.change("toolbox_config", "buff_repeat", "5 minutes")
    t.eq(B().GetRepeat(), 300)
    H.clearLogs()
    H.chat("/tbx buffs repeat")
    t.ok(H.logged("within: 5 minutes"), H.lastLog())
    H.chat("/tbx buffs repeat 3")
    t.ok(H.logged("buffs repeat off, 30s or a number of minutes: 30s, 1, 2, 5, 10"), H.lastLog())
    H.chat("/tbx buffs repeat 30s")
    t.eq(w:Find("buff_repeat").value, "30 seconds")
    H.chat("/tbx buffalert off")
    H.chat("/tbx debuffalert off")
    t.eq(w:Find("buff_repeat").enabled, false, "no alerts: nothing to repeat")
  end)

  -- Effect sounds (owner, 2026-10-08): a player's own file for an effect, instead of the usual sound.
  t.test("effect sounds: a path is cut to the Lua folder; outside it, in toolbox/ or not a sound: refused", function()
    H.boot()
    local S = Toolbox.Sounds
    t.eq(S.CleanPath("toolbox_sounds/atos.ogg"), "toolbox_sounds/atos.ogg")
    t.eq(S.CleanPath(' "C:\\Games\\Shroud\\Lua\\my sounds\\Atos.WAV" '), "my sounds/Atos.WAV")
    t.eq(S.CleanPath("/Users/me/Library/Shroud/Lua/atos.mp3"), "atos.mp3")
    t.no(S.CleanPath("C:\\Users\\me\\Desktop\\atos.ogg"), "outside the Lua folder")
    t.no(S.CleanPath("../atos.ogg"))
    t.no(S.CleanPath("toolbox/atos.ogg"), "the toolbox folder: replaced by updates")
    t.no(S.CleanPath("atos.txt"))
    t.no(S.CleanPath(""))
  end)

  t.test("effect sounds: its own file instead of the usual sound, the others unchanged; saved", function()
    bootWithSounds()
    H.S.files["toolbox_sounds/heal said.ogg"] = true
    H.S.files["toolbox_sounds/bleed.wav"] = true
    H.chat("/tbx buffs")
    H.chat("/tbx buffalert 5")
    H.addBuffs({ { name = "Heal", remaining = 12, icon = 101 }, { name = "Shield", remaining = 12, icon = 102 } })
    H.clearLogs()
    H.chat("/tbx buffs sound heal = toolbox_sounds/heal said.ogg")
    t.ok(H.logged("'Heal' plays toolbox_sounds/heal said.ogg instead of the usual sound"), H.lastLog())
    t.eq(B().EffectSound("Heal"), "toolbox_sounds/heal said.ogg")
    H.advance(1)                                      -- loaded
    H.S.played = {}
    H.advance(7, 0.5)
    t.eq(H.playedNames(), "heal said,toolbox_buff_expiring", "both expiring: each its own sound")
    t.eq(H.S.played[1].volume, math.min(100, 2 * Toolbox.Sounds.EffectiveVolume("buff_expiring")),
      "the expiry alert's volume, as a player's own file")
    H.chat("/tbx buffs sound Bleed = toolbox_sounds/bleed.wav")
    H.advance(1)
    H.S.played = {}
    H.addBuffs({ { name = "Bleed", remaining = 20, debuff = true } })
    t.eq(H.playedNames(), "bleed", "a debuff's own sound instead of the usual one")
    H.reload()
    t.eq(B().EffectSound("Bleed"), "toolbox_sounds/bleed.wav", "saved")
    H.clearLogs()
    H.chat("/tbx buffs sound")
    t.ok(H.logged("Effect sounds: Bleed: toolbox_sounds/bleed.wav; Heal: toolbox_sounds/heal said.ogg"), H.logs())
    H.chat("/tbx buffs sound remove bleed")
    t.eq(B().EffectSound("Bleed"), nil)
  end)

  t.test("effect sounds: a file that won't load plays the usual sound and says so once", function()
    bootWithSounds()
    H.addBuffs({ { name = "Bleed", remaining = 20, debuff = true } })
    H.removeBuff("Bleed")
    H.clearLogs()
    H.chat("/tbx buffs sound bleed = toolbox_sounds/typo.ogg")
    t.ok(H.logged("Couldn't load your sound 'toolbox_sounds/typo.ogg' %(Bleed%)"), H.logs())
    H.advance(3)
    H.S.played = {}
    H.addBuffs({ { name = "Bleed", remaining = 20, debuff = true } })
    t.eq(H.playedNames(), "toolbox_debuff_landed", "never silent")
    H.clearLogs()
    H.advance(5)
    t.no(H.logged("Couldn't load"), "said once")
    H.clearLogs()
    H.chat("/tbx buffs sound bleed = toolbox/bleed.ogg")
    t.ok(H.logged("every update replaces it"), H.lastLog())
    t.eq(B().EffectSound("Bleed"), "toolbox_sounds/typo.ogg", "unchanged")
  end)

  t.test("effect sounds in settings: pick, paste a path, Set; Test and Remove from the list", function()
    bootWithSounds()
    H.S.files["toolbox_sounds/heal.ogg"] = true
    H.addBuffs({ { name = "Heal", remaining = 600, icon = 101 } })
    H.advance(1)
    H.chat("/tbx config")
    local w = H.config()
    t.eq(w:Find("fx_list").value, "No effect sounds yet")
    t.eq(w:Find("fx_test").enabled, false)
    H.change("toolbox_config", "quiet_pick", "Heal (on you)")
    H.submit("toolbox_config", "fx_path", "C:\\Shroud\\Lua\\toolbox_sounds\\heal.ogg")
    t.eq(B().EffectSound("Heal"), "toolbox_sounds/heal.ogg", w:Find("fx_msg").text)
    H.advance(1)
    t.eq(w:Find("fx_list").value, "Heal: toolbox_sounds/heal.ogg")
    H.S.played = {}
    H.click("toolbox_config", "fx_test")
    t.eq(H.playedNames(), "heal", w:Find("fx_msg").text)
    H.click("toolbox_config", "fx_remove")
    t.eq(B().EffectSound("Heal"), nil)
    t.eq(w:Find("fx_list").value, "No effect sounds yet")
  end)
end
