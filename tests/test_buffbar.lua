-- Buff bar, clock overlay, expiry / debuff alerts and sound loading.
local H = require("harness")

return function(t)
  local B = function() return Toolbox.BuffBar end

  -- With both alert files in the default place, booted and loaded.
  local function bootWithSounds()
    H.boot()
    H.S.files["toolbox_buff_expiring.ogg"] = true
    H.S.files["toolbox_debuff_landed.ogg"] = true
    H.reload()
    H.advance(1)
    H.advance(Toolbox.BuffBar.DEBUFF_SUPPRESS)       -- past the start-up quiet period
  end

  -- model -------------------------------------------------------------------

  t.test("timer: fires once when crossing the threshold", function()
    H.boot()
    local st, frac, fire = B().Track(nil, 30, 10)
    t.near(frac, 1)
    t.no(fire)
    t.ok(st.armed)
    st, frac, fire = B().Track(st, 11, 10)
    t.no(fire)
    t.near(frac, 11 / 30)
    st, frac, fire = B().Track(st, 10, 10)
    t.ok(fire, "crossed")
    t.near(frac, 10 / 30)
    st, frac, fire = B().Track(st, 9, 10)
    t.no(fire, "only once")
    t.ok(st and frac)
  end)

  t.test("timer: a buff that starts below the threshold never fires", function()
    H.boot()
    local st, _, fire = B().Track(nil, 6, 10)
    t.no(fire)
    for rem = 5.5, 0.5, -0.5 do st, _, fire = B().Track(st, rem, 10); t.no(fire, "at " .. rem) end
  end)

  t.test("timer: a refresh starts a new run and re-arms", function()
    H.boot()
    local st, _, fire = B().Track(nil, 20, 10)
    t.no(fire)
    st, _, fire = B().Track(st, 9, 10)
    t.ok(fire)
    st, _, fire = B().Track(st, 30, 10)                 -- recast
    t.no(fire)
    t.eq(st.total, 30)
    _, _, fire = B().Track(st, 10, 10)
    t.ok(fire, "fires again after the refresh")
  end)

  t.test("timer: no timer for permanent or ended effects", function()
    H.boot()
    local _, frac = B().Track(nil, -1, 10)
    t.eq(frac, nil)
    _, frac = B().Track(nil, 0, 10)
    t.eq(frac, nil)
  end)

  t.test("clock frames and their UVs", function()
    H.boot()
    t.eq(B().Frame(1), 0, "full time: no shading")
    t.eq(B().Frame(0.5), 12)
    t.eq(B().Frame(0.01), 23)
    t.eq(B().Frame(0), 23, "clamped")
    local x, y, w, h = B().FrameUV(7)                  -- column 1, row 1 of 6 x 4, of 8 rows in all
    t.near(x, 1 / 6); t.near(y, 1 / 8); t.near(w, 1 / 6); t.near(h, 1 / 8)
    x, y = B().FrameUV(7, true)                         -- the same frame in the red set below
    t.near(x, 1 / 6); t.near(y, 5 / 8)
  end)

  t.test("new debuff names", function()
    H.boot()
    t.eq(table.concat(B().NewNames({ A = true }, { A = true, B = true, C = true }), ","), "B,C")
    t.eq(#B().NewNames({ A = true }, {}), 0)
  end)

  -- the bar -----------------------------------------------------------------

  t.test("hidden by default; /tbx buffs shows it and it is remembered", function()
    H.boot()
    t.eq(H.frame().visible, false)
    H.chat("/tbx buffs")
    t.eq(H.frame().visible, true)
    H.reload()
    t.eq(H.frame().visible, true)
  end)

  t.test("buffs and debuffs fill their own rows with the real icons", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Heal", remaining = 30, icon = 101 }, { name = "Shield", remaining = 60, icon = 102 },
                 { name = "Poison", remaining = 12, icon = 201, debuff = true } })
    H.advance(1)
    local buffs, debuffs = H.slots("buffs"), H.slots("debuffs")
    t.eq(#buffs, 2)
    t.eq(#debuffs, 1)
    t.eq(buffs[1].children[1].texture, 101)
    t.eq(debuffs[1].children[1].texture, 201)
    t.eq(debuffs[1].style.borderColor, "@red", "debuffs are outlined")
    t.ok(buffs[1].children[1].tooltip:find("Heal"), "the game's tooltip")
  end)

  t.test("the clock overlay sweeps as time runs down; none for permanent buffs", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Heal", remaining = 24, icon = 101 }, { name = "Aura", remaining = -1, permanent = true } })
    H.advance(0.5, 0.5)
    local heal, aura = H.slots("buffs")[1], H.slots("buffs")[2]
    t.eq(heal.children[2].visible, false, "full time: no shading yet")
    H.advance(12, 0.5)                                  -- half gone
    t.eq(heal.children[2].visible, true)
    local uv = heal.children[2].uv
    t.near(uv[1], (12 % 6) / 6); t.near(uv[2], math.floor(12 / 6) / 8)
    t.eq(aura.children[2].visible, false, "no timer, no clock")
  end)

  t.test("the sweep turns red when the expiry alert fires, and back after a recast", function()
    bootWithSounds()
    H.chat("/tbx buffs")
    H.chat("/tbx buffalert 5")
    H.addBuffs({ { name = "Heal", remaining = 12, icon = 101 } })
    local overlay = function() return H.slots("buffs")[1].children[2] end
    H.advance(4, 0.5)
    t.ok(overlay().uv[2] < 0.5, "normal (top) set before the alert")
    H.advance(3.5, 0.5)                                 -- crosses 5 s
    t.eq(H.playedNames(), "toolbox_buff_expiring")
    t.ok(overlay().uv[2] >= 0.5, "red (bottom) set once it fired")
    H.S.buffs[1].remaining = 30                         -- recast
    H.advance(1, 0.5)
    t.ok(not overlay().visible or overlay().uv[2] < 0.5, "back to normal after the recast")
  end)

  t.test("red only follows the alert: short buffs and debuffs never turn red", function()
    bootWithSounds()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Quick", remaining = 6, icon = 1 }, { name = "Bleed", remaining = 20, debuff = true } })
    H.advance(4, 0.5)
    t.ok(H.slots("buffs")[1].children[2].uv[2] < 0.5, "a buff that started under the threshold")
    H.advance(12, 0.5)
    t.ok(H.slots("debuffs")[1].children[2].uv[2] < 0.5, "debuffs keep the normal sweep")
  end)

  t.test("the icon pool is built once; buff changes create no elements", function()
    H.boot()
    H.chat("/tbx buffs")
    local made = H.S.constructed
    for i = 1, 30 do
      H.addBuffs({ { name = "B" .. i, remaining = 100 + i, icon = i } })
      H.advance(0.5, 0.5)
    end
    H.advance(10, 0.5)
    t.eq(H.S.constructed, made)
    t.eq(#H.slots("buffs"), B().BUFF_SLOTS, "extra buffs beyond the pool are not shown")
  end)

  t.test("icon size setting resizes the slots and is remembered", function()
    H.boot()
    H.chat("/tbx buffs")
    B().SetSize(24)
    local slot = H.frame():Find("buffs").children[1]
    t.eq(slot.style.width, 24)
    t.eq(slot.children[2].style.marginLeft, -24, "overlay still sits on the icon")
    t.no(B().SetSize(100), "out of range")
    H.reload()
    t.eq(B().GetSize(), 24)
  end)

  t.test("a missing clock picture just means no overlay", function()
    H.boot()
    H.S.files["toolbox/clock.png"] = nil
    H.reload()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Heal", remaining = 10, icon = 101 } })
    H.advance(6, 0.5)
    t.eq(H.slots("buffs")[1].children[2].visible, false)
  end)

  -- alerts ------------------------------------------------------------------

  t.test("expiry alert plays once when a buff crosses the setting", function()
    bootWithSounds()
    H.chat("/tbx buffalert 5")
    H.addBuffs({ { name = "Heal", remaining = 12, icon = 101 } })
    H.advance(6, 0.5)
    t.eq(H.playedNames(), "", "not yet")
    H.advance(1.5, 0.5)
    t.eq(H.playedNames(), "toolbox_buff_expiring")
    H.advance(5, 0.5)
    t.eq(#H.S.played, 1, "once")
  end)

  t.test("expiry alert works with the bar hidden, and not for short buffs or debuffs", function()
    bootWithSounds()
    t.eq(H.frame().visible, false)
    H.addBuffs({ { name = "Quick", remaining = 4 }, { name = "Bleed", remaining = 20, debuff = true } })
    H.advance(1)                                        -- let the debuff alert pass
    H.S.played = {}
    H.advance(25, 0.5)
    t.eq(H.playedNames(), "", "Quick started under 10 s; Bleed is a debuff")
    H.addBuffs({ { name = "Long", remaining = 12 } })
    H.advance(3, 0.5)
    t.eq(H.playedNames(), "toolbox_buff_expiring", "bar hidden, alert still plays")
  end)

  t.test("expiry alert off, and the seconds setting", function()
    bootWithSounds()
    H.clearLogs()
    H.chat("/tbx buffalert off")
    t.ok(H.logged("alert: off"))
    H.addBuffs({ { name = "Heal", remaining = 12 } })
    H.advance(13, 0.5)
    t.eq(#H.S.played, 0)
    H.clearLogs()
    H.chat("/tbx buffalert 30")
    t.ok(H.logged("on, 30 s before"), "a number turns it back on")
    H.chat("/tbx buffalert 99")
    t.ok(H.logged("from 1 to 60"))
    t.eq(B().GetExpireSeconds(), 30)
    H.reload()
    t.eq(B().GetExpireSeconds(), 30)
  end)

  t.test("debuff alert: a new debuff plays, once per second at most", function()
    bootWithSounds()
    H.addBuffs({ { name = "Poison", remaining = 20, debuff = true } })
    t.eq(H.playedNames(), "toolbox_debuff_landed")
    H.addBuffs({ { name = "Slow", remaining = 20, debuff = true } })
    t.eq(#H.S.played, 1, "cooldown")
    H.advance(1)
    H.addBuffs({ { name = "Curse", remaining = 20, debuff = true } })
    t.eq(#H.S.played, 2)
    H.addBuffs({ { name = "Heal", remaining = 20 } })
    H.advance(1)
    t.eq(#H.S.played, 2, "buffs don't trigger it")
  end)

  t.test("debuff alert: quiet at start and after a scene change", function()
    H.boot()
    H.S.files["toolbox_debuff_landed.ogg"] = true
    H.S.buffs = { { name = "Old", remaining = 60, debuff = true } }
    H.reload()
    H.advance(1)
    t.eq(#H.S.played, 0, "existing debuff at start")
    H.advance(5)
    H.callback("ShroudOnSceneUnloaded")
    H.S.buffs = { { name = "Other", remaining = 60, debuff = true } }
    H.callback("ShroudOnSceneLoaded", "Town")
    H.callback("ShroudOnBuffsChanged")
    t.eq(#H.S.played, 0, "rebuilt list after a scene change")
    H.advance(5)
    H.addBuffs({ { name = "New", remaining = 20, debuff = true } })
    t.eq(#H.S.played, 1, "a real new one afterwards")
  end)

  t.test("debuff alert off", function()
    bootWithSounds()
    H.chat("/tbx debuffalert off")
    H.addBuffs({ { name = "Poison", remaining = 20, debuff = true } })
    t.eq(#H.S.played, 0)
    t.eq(B().GetDebuffAlert(), false)
  end)

  -- sounds ------------------------------------------------------------------

  t.test("sounds: missing files are fine; nothing plays and it says where to put them", function()
    H.boot()
    H.advance(20)
    t.eq(Toolbox.Sounds.Status("buff_expiring"), "missing")
    t.no(Toolbox.Sounds.Play("buff_expiring"))
    H.clearLogs()
    H.chat("/tbx sounds")
    t.ok(H.logged("put one at Lua/toolbox_buff_expiring.ogg"))
  end)

  t.test("sounds: the loose default location is found", function()
    bootWithSounds()
    local status, path = Toolbox.Sounds.Status("buff_expiring")
    t.eq(status, "ready")
    t.eq(path, "toolbox_buff_expiring.ogg")
  end)

  t.test("sounds: the package location works too (for when audio can ship)", function()
    H.boot()
    H.S.files["toolbox/debuff_landed.ogg"] = true
    H.reload()
    H.advance(2)
    local status, path = Toolbox.Sounds.Status("debuff_landed")
    t.eq(status, "ready")
    t.eq(path, "toolbox/debuff_landed.ogg")
  end)

  t.test("sounds: a custom path wins, and clearing it falls back", function()
    bootWithSounds()
    H.S.files["my sounds/ding.ogg"] = true
    H.chat("/tbx config")
    H.submit("toolbox_config", "snd_buff_expiring_path", "my sounds/ding.ogg")
    H.advance(2)
    local _, path = Toolbox.Sounds.Status("buff_expiring")
    t.eq(path, "my sounds/ding.ogg")
    t.ok(Toolbox.Sounds.Play("buff_expiring"))
    t.eq(H.S.played[#H.S.played].name, "ding")
    H.reload()
    t.eq(Toolbox.Sounds.GetPath("buff_expiring"), "my sounds/ding.ogg", "remembered")
    H.chat("/tbx config")
    H.submit("toolbox_config", "snd_buff_expiring_path", "  ")
    H.advance(2)
    _, path = Toolbox.Sounds.Status("buff_expiring")
    t.eq(path, "toolbox_buff_expiring.ogg")
  end)

  t.test("sounds: a request that is accepted but never loads times out to the next place", function()
    H.boot()
    H.S.acceptMissing = true                       -- the game accepts paths it can't load
    H.S.files["toolbox/buff_expiring.ogg"] = true
    H.reload()
    t.eq(Toolbox.Sounds.Status("buff_expiring"), "loading")
    H.advance(Toolbox.Sounds.LOAD_TIMEOUT + 2)
    local status, path = Toolbox.Sounds.Status("buff_expiring")
    t.eq(status, "ready")
    t.eq(path, "toolbox/buff_expiring.ogg")
  end)

  t.test("sounds: a cleared clip list is reloaded rather than playing the wrong clip", function()
    bootWithSounds()
    ShroudListSoundReset()
    t.no(Toolbox.Sounds.Play("buff_expiring"), "gone")
    H.advance(2)
    t.ok(Toolbox.Sounds.Play("buff_expiring"), "reloaded")
  end)

  t.test("sounds: volume, and 0 mutes", function()
    bootWithSounds()
    H.chat("/tbx sounds 40")
    t.ok(Toolbox.Sounds.Play("debuff_landed"))
    t.eq(H.S.played[#H.S.played].volume, 40)
    H.chat("/tbx sounds 0")
    t.no(Toolbox.Sounds.Play("debuff_landed"))
    H.clearLogs()
    H.chat("/tbx sounds 101")
    t.ok(H.logged("from 0 to 100"))
  end)

  -- settings ----------------------------------------------------------------

  t.test("settings: buff bar controls work and follow the commands", function()
    bootWithSounds()
    H.chat("/tbx config")
    local find = function(id) return H.config():Find(id) end
    H.change("toolbox_config", "show_buffs", true)
    t.eq(H.frame().visible, true)
    H.change("toolbox_config", "expire_seconds", 20.4)
    t.eq(B().GetExpireSeconds(), 20)
    t.eq(find("expire_seconds_value").text, "20")
    H.chat("/tbx buffalert 7")
    t.eq(find("expire_seconds").value, 7, "slider follows the command")
    H.change("toolbox_config", "debuff_alert", false)
    t.eq(B().GetDebuffAlert(), false)
    H.change("toolbox_config", "volume", 55)
    t.eq(Toolbox.Sounds.GetVolume(), 55)
    H.advance(1)
    t.eq(find("snd_buff_expiring_status").text, "Buff expiring: toolbox_buff_expiring.ogg")
    local before = #H.S.played
    H.clearLogs()
    H.click("toolbox_config", "snd_buff_expiring_test")
    t.eq(#H.S.played, before + 1, "Test button plays it")
    t.ok(H.logged("playing 'toolbox_buff_expiring' %(clip %d+%) on channel 1 at volume 55"), H.lastLog())
    H.S.files["toolbox_debuff_landed.ogg"] = nil
    Toolbox.Sounds.SetPath("debuff_landed", "nowhere.ogg")
    H.advance(20)
    H.clearLogs()
    H.click("toolbox_config", "snd_debuff_landed_test")
    t.ok(H.logged("no sound loaded"), "Test explains a missing file")
  end)

  t.test("help lists the buff commands", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx help")
    for _, c in ipairs({ "buffs", "buffalert", "debuffalert", "sounds" }) do
      t.ok(H.logged("/toolbox " .. c), c)
    end
  end)

  t.test("sound test: reports a clip that plays", function()
    bootWithSounds()
    H.clearLogs()
    H.chat("/tbx sounds test")
    H.advance(0.2, 0.1)
    t.ok(H.logged("Buff expiring: channel 1 is playing") or H.logged("Debuff landed: channel 1 is playing"),
      H.lastLog())
  end)

  t.test("sound test: a clip that loads but doesn't decode is called out", function()
    bootWithSounds()
    H.S.undecodable = true
    H.clearLogs()
    Toolbox.Sounds.Test("debuff_landed")
    H.advance(0.2, 0.1)
    t.ok(H.logged("already silent, so the file most likely didn't decode"), H.lastLog())
  end)

  t.test("sound test: refused, muted and not loaded each say why", function()
    bootWithSounds()
    H.S.channelsBusy = true
    H.clearLogs()
    Toolbox.Sounds.Test("buff_expiring")
    t.ok(H.logged("refused to play clip"), H.lastLog())
    H.S.channelsBusy = nil
    H.chat("/tbx sounds 0")
    H.clearLogs()
    Toolbox.Sounds.Test("buff_expiring")
    t.ok(H.logged("volume is 0"))
    H.chat("/tbx sounds 70")
    ShroudListSoundReset()
    H.clearLogs()
    Toolbox.Sounds.Test("buff_expiring")
    t.ok(H.logged("list was cleared; reloading"))
  end)

  -- buffs already running when the add-on starts ------------------------------

  t.test("full duration: trusted only when it agrees with the time remaining", function()
    H.boot()
    local F = B().TotalFromEffects
    t.eq(F(15, { { TotalDuration = 60, CurrentDuration = 45 } }), 60, "current = elapsed, seconds")
    t.eq(F(15, { { TotalDuration = 60, CurrentDuration = 15 } }), 60, "current = remaining, seconds")
    t.eq(F(15, { { TotalDuration = 60000, CurrentDuration = 45000 } }), 60, "milliseconds")
    t.eq(F(15, { { TotalDuration = 60, CurrentDuration = 30 } }), nil, "disagrees: not trusted")
    t.eq(F(15, { { TotalDuration = 10, CurrentDuration = 0 } }), nil, "shorter than what's left")
    t.eq(F(15, { { TotalDuration = 0, CurrentDuration = 0 } }), nil)
    t.eq(F(-1, { { TotalDuration = 60, CurrentDuration = 45 } }), nil, "permanent")
    t.eq(F(15, nil), nil)
  end)

  -- A 40 s buff with 10 s left (75 % done) when the add-on starts.
  local function startMidBuff(mode)
    H.boot()
    H.S.durationMode = mode
    H.S.buffs = { { name = "Light", remaining = 10, total = 40, icon = 5 } }
    local saved = H.S.memory["character:Tester"]
    saved.buffbar = { show = true }
    H.reload()
    H.advance(0.5, 0.5)
    return H.slots("buffs")[1].children[2]
  end

  for _, mode in ipairs({ "elapsed", "remaining", "ms" }) do
    t.test("a buff already running at start shows its real progress (durations as " .. mode .. ")", function()
      local overlay = startMidBuff(mode)
      t.eq(overlay.visible, true)
      -- 9.5 of 40 s left: frame floor((1 - 9.5/40) * 24) = 18
      t.near(overlay.uv[1], (18 % 6) / 6)
      t.near(overlay.uv[2], math.floor(18 / 6) / 8)
    end)
  end

  t.test("unusable durations fall back to treating the buff as new", function()
    local overlay = startMidBuff("nonsense")
    -- 9.5 of an assumed 10 s: frame 1, the first sliver
    t.near(overlay.uv[1], 1 / 6, 1e-6, "shown as nearly full")
    t.near(overlay.uv[2], 0)
  end)

  t.test("without durations, a /lua reload keeps each buff's progress", function()
    H.boot()                                         -- no durations reported (mode nil)
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Light", remaining = 40, icon = 5 } })
    H.advance(30, 0.5)                               -- 10 s left, 75 % done
    H.reload()
    H.advance(0.5, 0.5)
    local overlay = H.slots("buffs")[1].children[2]
    t.near(overlay.uv[1], (18 % 6) / 6)
    t.near(overlay.uv[2], math.floor(18 / 6) / 8)
  end)

  t.test("a remembered duration is ignored when the buff doesn't line up (recast meanwhile)", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Light", remaining = 40, icon = 5 } })
    H.advance(30, 0.5)
    H.S.buffs[1].remaining = 20                      -- recast to a different length during the reload
    H.reload()
    H.advance(0.5, 0.5)
    t.eq(H.slots("buffs")[1].children[2].visible, false, "treated as a fresh 20 s buff")
  end)

  t.test("after a restart remembered durations are not used", function()
    H.boot()
    H.addBuffs({ { name = "Light", remaining = 40, icon = 5 } })
    H.advance(40)                                    -- flushed; Light ran out
    H.addBuffs({ { name = "Light", remaining = 40, icon = 5 } })
    H.advance(30, 0.5)
    ShroudFlushSavedVars()
    H.restart(5)                                     -- the clock starts again
    t.eq(Toolbox.BuffBar.Recall("Light", 10), nil)
  end)

  t.test("/tbx buffs debug lists each buff's timing data", function()
    H.boot()
    H.S.durationMode = "elapsed"
    H.addBuffs({ { name = "Light", remaining = 40, icon = 5 }, { name = "Bleed", remaining = 8, debuff = true } })
    H.advance(1, 0.5)
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("^Light: 39 s left; TotalDuration 40, CurrentDuration 1; full duration 40 s %(from the game%)$"),
      H.logs()[1])
    t.ok(H.logged("^Bleed %(debuff%): 7 s left"), H.logs()[2])
    t.eq(H.frame().visible, false, "debug doesn't toggle the bar")
  end)
end
