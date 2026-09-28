-- Buff bar, clock overlay, expiry / debuff alerts and sound loading.
local H = require("harness")

return function(t)
  local B = function() return Toolbox.BuffBar end
  -- The overlay shows the frame for `fraction`, give or take one frame (3 degrees): sampling
  -- lands within a tick (0.5 s) of the exact time.
  local function sameUV(t2, uv, fraction, msg)
    local c = B().CLOCK
    local shown = math.floor(uv[1] * c.COLS + 0.5) + math.floor(uv[2] * c.ROWS * c.SETS + 0.5) * c.COLS
    local want = B().Frame(fraction)
    t2.ok(math.abs(shown - want) <= 1, (msg or "") .. ": frame " .. shown .. ", expected " .. want)
  end

  -- With both alert files in the default place, booted and loaded.
  local function bootWithSounds()
    H.boot()
    H.S.files["toolbox_buff_expiring.ogg"] = true
    H.S.files["toolbox_debuff_landed.ogg"] = true
    H.reload()
    H.advance(Toolbox.BuffBar.SETTLE)                -- past the start-up quiet periods
  end

  -- Boots and waits out the start-up settling, so a buff added next counts as cast.
  local function bootSettled()
    H.boot()
    H.advance(Toolbox.BuffBar.SETTLE)
  end

  -- model -------------------------------------------------------------------

  t.test("timer: fires once when crossing the threshold", function()
    H.boot()
    local st, frac, fire = B().Track(nil, 30, 10, nil, nil, true)
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
    local st, _, fire = B().Track(nil, 6, 10, nil, nil, true)
    t.no(fire)
    for rem = 5.5, 0.5, -0.5 do st, _, fire = B().Track(st, rem, 10); t.no(fire, "at " .. rem) end
  end)

  t.test("timer: a refresh starts a new run and re-arms", function()
    H.boot()
    local st, _, fire = B().Track(nil, 20, 10, nil, nil, true)
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
    local c = B().CLOCK
    t.eq(B().Frame(1), 0, "full time: no shading")
    t.eq(B().Frame(0.5), c.FRAMES / 2)
    t.eq(B().Frame(0.001), c.FRAMES - 1)
    t.eq(B().Frame(0), c.FRAMES - 1, "clamped")
    local k = c.COLS + 1                                -- column 1, row 1
    local rows = c.ROWS * c.SETS
    local x, y, w, h = B().FrameUV(k)
    t.near(x, 1 / c.COLS); t.near(y, 1 / rows); t.near(w, 1 / c.COLS); t.near(h, 1 / rows)
    x, y = B().FrameUV(k, true)                         -- the same frame in the red set below
    t.near(x, 1 / c.COLS); t.near(y, (1 + c.ROWS) / rows)
    x, y = B().FrameUV(c.FRAMES - 1)                    -- the last frame stays inside the normal set
    t.ok(y < 0.5 and x < 1)
  end)

  t.test("a long buff's sweep keeps moving (at most 1/FRAMES of its time per step)", function()
    H.boot()
    H.S.durationMode = "remaining"
    H.chat("/tbx buffs")
    H.chat("/tbx buffs group after off")   -- 20 minutes would be grouped
    H.addBuffs({ { name = "Light", remaining = 1200, icon = 5 } })
    local changes, last = 0, nil
    for _ = 1, 120 do
      H.advance(1, 0.5)
      local ov = H.slots("buffs")[1].children[2]
      local key = ov.visible and (ov.uv[1] .. "," .. ov.uv[2]) or "hidden"
      if key ~= last then changes, last = changes + 1, key end
    end
    t.ok(changes >= 12, "20-minute buff, first 2 minutes: " .. changes .. " steps")
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
    bootSettled()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Aura", remaining = -1, permanent = true } })
    H.advance(0.5, 0.5)
    H.addBuffs({ { name = "Heal", remaining = 24, icon = 101 } })   -- cast on its own
    H.advance(0.5, 0.5)
    local heal, aura = H.slots("buffs")[1], H.slots("buffs")[2]
    t.eq(heal.children[2].visible, false, "full time: no shading yet")
    H.advance(12, 0.5)                                  -- half gone
    t.eq(heal.children[2].visible, true)
    sameUV(t, heal.children[2].uv, 11.5 / 24, "half the time left")
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
    H.addBuffs({ { name = "Quick", remaining = 6, icon = 1 } })
    H.advance(0.5, 0.5)
    H.addBuffs({ { name = "Bleed", remaining = 20, debuff = true } })
    H.advance(3.5, 0.5)
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
    t.ok(H.logged("the default is Lua/toolbox/buff_expiring.ogg; a replacement goes at Lua/toolbox_buff_expiring.ogg"),
      H.lastLog())
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
    H.advance(2 * Toolbox.Sounds.LOAD_TIMEOUT + 2)            -- the loose .ogg, then the .wav, time out
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
    H.chat("/tbx commands")
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
    t.eq(F(15, { { TotalDuration = 60, CurrentDuration = 15 } }), 60, "seconds, CurrentDuration = time left")
    t.eq(F(15, { { TotalDuration = 60, CurrentDuration = 14.2 } }), 60, "a moment apart")
    t.eq(F(15, { { TotalDuration = 60, CurrentDuration = 45 } }), nil, "not 'time elapsed' (a guess, now settled)")
    t.eq(F(15, { { TotalDuration = 60000, CurrentDuration = 15000 } }), nil, "not milliseconds")
    t.eq(F(15, { { TotalDuration = 60, CurrentDuration = 30 } }), nil, "disagrees: not trusted")
    t.eq(F(15, { { TotalDuration = 10, CurrentDuration = 0 } }), nil, "shorter than what's left")
    t.eq(F(15, { { TotalDuration = 0, CurrentDuration = 0 } }), nil)
    t.eq(F(-1, { { TotalDuration = 60, CurrentDuration = 45 } }), nil, "permanent")
    t.eq(F(15, nil), nil)
  end)

  t.test("full duration: a rune with several effects takes the one whose time left matches", function()
    H.boot()
    local F = B().TotalFromEffects
    -- the stat part runs 40 s (15 left); a longer part was 585 s in, so its ELAPSED time is 15:
    -- the old guesses took the longest total (600) and the sweep sat far from the game's
    t.eq(F(15, { { TotalDuration = 600, CurrentDuration = 585 }, { TotalDuration = 40, CurrentDuration = 15 } }), 40)
    t.eq(F(15, { { TotalDuration = 30, CurrentDuration = 14 }, { TotalDuration = 40, CurrentDuration = 15 } }), 40,
      "the closest match")
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

  t.test("a buff already running at start shows its real progress (the game's durations)", function()
    local overlay = startMidBuff("remaining")
    t.eq(overlay.visible, true)
    sameUV(t, overlay.uv, 9.5 / 40, "9.5 of 40 s left")
  end)

  t.test("unknown full duration: no sweep rather than a wrong one", function()
    for _, mode in ipairs({ "nonsense", "absent", "elapsed", "ms" }) do
      t.eq(startMidBuff(mode).visible, false, mode)
    end
  end)

  t.test("a buff seen cast teaches its duration for next time it is already running", function()
    bootSettled()
    H.S.durationMode = "absent"
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Light", remaining = 225, icon = 5 } })   -- cast while running: learned
    H.advance(225, 5)                                                 -- runs out
    H.advance(15, 5)
    H.S.buffs = { { name = "Light", remaining = 112, total = 225, icon = 5 } }
    ShroudFlushSavedVars()
    H.restart(10)                                                     -- already running at login
    H.advance(0.5, 0.5)
    sameUV(t, H.slots("buffs")[1].children[2].uv, 111.5 / 225, "half used, from the learned 225 s")
  end)

  t.test("the expiry alert works for a buff whose duration is unknown", function()
    bootWithSounds()
    H.S.durationMode = "absent"
    H.S.buffs = { { name = "Old", remaining = 14 } }
    H.reload()
    H.advance(2, 0.5)
    H.S.played = {}
    H.advance(4, 0.5)
    t.eq(H.playedNames(), "toolbox_buff_expiring")
  end)

  t.test("a buff that vanishes during a scene load keeps its timer", function()
    bootSettled()
    H.S.durationMode = "absent"
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Light", remaining = 200, icon = 5 } })
    H.advance(100, 5)
    local saved = H.S.buffs
    H.callback("ShroudOnSceneUnloaded")
    H.S.buffs = {}
    H.advance(4)                                                      -- loading: list empty
    saved[1].remaining = saved[1].remaining - 4                       -- the buff kept running meanwhile
    H.S.buffs = saved
    H.callback("ShroudOnSceneLoaded", "Town")
    H.advance(0.5, 0.5)
    sameUV(t, H.slots("buffs")[1].children[2].uv, 95.5 / 200, "still its real progress")
  end)

  t.test("without durations, a /lua reload keeps each buff's progress", function()
    bootSettled()                                    -- no durations reported (mode nil)
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Light", remaining = 40, icon = 5 } })
    H.advance(30, 0.5)                               -- 10 s left, 75 % done
    H.reload()
    H.advance(0.5, 0.5)
    local overlay = H.slots("buffs")[1].children[2]
    sameUV(t, overlay.uv, 9.5 / 40, "progress kept across the reload")
  end)

  t.test("a remembered timer that doesn't line up falls back to the learned duration", function()
    bootSettled()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Light", remaining = 40, icon = 5 } })
    H.advance(30, 0.5)
    H.S.buffs[1].remaining = 20                      -- recast to a different length during the reload
    H.reload()
    H.advance(0.5, 0.5)
    local ov = H.slots("buffs")[1].children[2]
    sameUV(t, ov.uv, 19.5 / 40, "the 40 s learned when it was cast")
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
    H.S.durationMode = "remaining"
    H.addBuffs({ { name = "Light", remaining = 40, icon = 5 }, { name = "Bleed", remaining = 8, debuff = true } })
    H.advance(1, 0.5)
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("^Light: 39 s left; TotalDuration 40, CurrentDuration 39; full duration 40 s %(from the game%)$"),
      H.logs()[1])
    t.ok(H.logged("^Bleed %(debuff%): 7 s left"), H.logs()[2])
    t.eq(H.frame().visible, false, "debug doesn't toggle the bar")
  end)

  -- a game value that only refreshes now and then ---------------------------

  t.test("timer: counts down on its own clock while the game's value is stale", function()
    H.boot()
    local st, frac, _, rem = B().Track(nil, 120, 10, 120, 1000)
    t.near(frac, 1)
    t.near(rem, 120)
    st, frac, _, rem = B().Track(st, 120, 10, 120, 1030)        -- same (stale) value 30 s later
    t.near(rem, 90); t.near(frac, 0.75)
    st, frac, _, rem = B().Track(st, 88, 10, 120, 1031)         -- the game refreshes: follow it
    t.near(rem, 88)
    st, _, _, rem = B().Track(st, 118, 10, 120, 1032)           -- jumps up: a recast
    t.near(rem, 118)
    t.ok(st and frac)
  end)

  t.test("the sweep keeps pace with a game value that refreshes only every 30 s", function()
    H.boot()
    H.S.staleEvery = 30
    H.S.durationMode = "remaining"
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Ward", remaining = 120, icon = 9 } })
    local changes, last = 0, nil
    for _ = 1, 120 do                                             -- 60 s in half-second ticks
      H.advance(0.5, 0.5)
      local ov = H.slots("buffs")[1].children[2]
      local key = ov.visible and (ov.uv[1] .. "," .. ov.uv[2]) or "hidden"
      if key ~= last then changes, last = changes + 1, key end
    end
    t.ok(changes >= 50, "moved smoothly: " .. changes .. " steps in 60 s")
    sameUV(t, H.slots("buffs")[1].children[2].uv, 60 / 120, "half used after 60 s")
  end)

  t.test("the expiry alert fires on time with a stale game value", function()
    bootWithSounds()
    H.S.staleEvery = 30
    H.chat("/tbx buffalert 10")
    H.addBuffs({ { name = "Ward", remaining = 45 } })
    H.advance(34, 0.5)
    t.eq(#H.S.played, 0, "11 s left: not yet")
    H.advance(1.5, 0.5)
    t.eq(H.playedNames(), "toolbox_buff_expiring", "fired at 10 s though the game still said 15")
  end)

  t.test("/tbx buffs trace logs raw and shown values once a second", function()
    H.boot()
    H.S.durationMode = "remaining"
    H.addBuffs({ { name = "Ward", remaining = 60, icon = 9 } })
    H.advance(1, 0.5)
    H.clearLogs()
    H.chat("/tbx buffs trace")
    H.advance(Toolbox.BuffBar.TRACE_SECONDS + 3)
    t.ok(H.logged("^%+1s Ward: game 58"), H.logs()[2])
    t.ok(H.logged("^%+1s Ward: game 58[%d.]* left %(effects left/total: 58[%d.]*/60%)"), H.logs()[2])
    t.ok(H.logged("^%+10s Ward:"), "ten lines")
    t.no(H.logged("^%+11s"), "stops after ten")
  end)

  t.test("/tbx buffs trace <name> follows one buff, matching its displayed name too", function()
    H.boot()
    local list = {}
    for i = 1, 10 do list[#list + 1] = { name = "Rune" .. i, remaining = 600 } end
    list[#list + 1] = { name = "LightRune", label = "Light", remaining = 120 }
    H.addBuffs(list)
    H.advance(1, 0.5)
    H.clearLogs()
    H.chat("/tbx buffs trace LIGHT")
    H.advance(2)
    t.ok(H.logged("^%+1s Light %[LightRune%]: game 11%d left"), H.logs()[2])
    t.no(H.logged("Rune1:"), "only the match")
    H.advance(Toolbox.BuffBar.TRACE_SECONDS)
    H.clearLogs()
    H.chat("/tbx buffs trace")
    H.advance(1)
    local lines = 0
    for _, l in ipairs(H.logs()) do if l:find("^%+1s") then lines = lines + 1 end end
    t.eq(lines, Toolbox.BuffBar.TRACE_MAX, "without a name: the first " .. Toolbox.BuffBar.TRACE_MAX)
    H.advance(Toolbox.BuffBar.TRACE_SECONDS)
    H.clearLogs()
    H.chat("/tbx buffs trace nosuch")
    H.advance(1)
    t.ok(H.logged("no buffs matching 'nosuch'"))
  end)

  t.test("timers saved by the old version (with wrong totals) are ignored", function()
    H.boot()
    H.S.durationMode = "absent"
    H.S.buffs = { { name = "Light", remaining = 112, total = 225, icon = 5 } }
    H.S.memory["character:Tester"].buff_timers = { Light = { total = 130, remaining = 112.5, at = ShroudTime } }
    H.S.memory["character:Tester"].buffbar = { show = true }
    H.reload()
    H.advance(0.5, 0.5)
    t.eq(H.slots("buffs")[1].children[2].visible, false, "unknown, not the stale 130 s")
  end)

  -- position -----------------------------------------------------------------

  t.test("nudge buttons, Reset and the position readout in settings", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx config")
    H.click("toolbox_config", "buff_right")
    H.click("toolbox_config", "buff_down")
    H.click("toolbox_config", "buff_down")
    t.eq(H.frame().x, B().HOME[1] + B().NUDGE)
    t.eq(H.frame().y, B().HOME[2] + 2 * B().NUDGE)
    t.eq(H.config():Find("buff_pos").text, (B().HOME[1] + 10) .. ", " .. (B().HOME[2] + 20))
    H.click("toolbox_config", "buff_left")
    H.click("toolbox_config", "buff_up")
    t.eq(H.frame().y, B().HOME[2] + B().NUDGE)
    H.click("toolbox_config", "buff_reset")
    t.eq(H.frame().x, B().HOME[1])
    t.eq(H.frame().y, B().HOME[2])
  end)

  t.test("/tbx buffs move places it and reports where it is", function()
    H.boot()
    H.chat("/tbx buffs move 600 45")
    t.eq(H.frame().x, 600)
    t.eq(H.frame().y, 45)
    t.ok(H.logged("Buff bar at 600, 45"), H.lastLog())
    H.clearLogs()
    H.chat("/tbx buffs move")
    t.ok(H.logged("Buff bar at 600, 45"))
    H.clearLogs()
    H.chat("/tbx buffs move up")
    t.ok(H.logged("buffs move <x> <y>"))
    t.eq(H.frame().x, 600, "unchanged")
  end)

  t.test("the position is remembered across a reload, including a grip drag", function()
    H.boot()
    H.chat("/tbx buffs")
    H.S.frames.toolbox_buffs.x, H.S.frames.toolbox_buffs.y = 333, 44   -- the player drags the grip
    H.advance(1)
    H.reload()
    t.eq(H.frame().x, 333)
    t.eq(H.frame().y, 44)
    t.eq(H.saved("buffbar").x, 333)
  end)

  t.test("the strip is only as big as the icons showing (so it can reach the right edge)", function()
    H.boot()
    H.chat("/tbx buffs")
    H.advance(1)
    local cell = B().GetSize() + B().GAP
    local empty = H.frame().width
    t.eq(empty, Toolbox.Window.GRIP + cell + 8, "one slot wide with nothing up")
    t.eq(H.frame().height, cell + 8, "one row")
    H.addBuffs({ { name = "A", remaining = 60, icon = 1 }, { name = "B", remaining = 60, icon = 2 },
                 { name = "C", remaining = 60, icon = 3 } })
    H.advance(0.5, 0.5)
    t.eq(H.frame().width, Toolbox.Window.GRIP + 3 * cell + 8, "three buffs wide")
    H.addBuffs({ { name = "Poison", remaining = 60, debuff = true } })
    H.advance(0.5, 0.5)
    t.eq(H.frame().height, 2 * cell + 8, "a second row for debuffs")
    H.removeBuff("A"); H.removeBuff("B"); H.removeBuff("Poison")
    H.advance(0.5, 0.5)
    t.eq(H.frame().width, Toolbox.Window.GRIP + cell + 8, "shrinks back")
    t.eq(H.frame().height, cell + 8)
    t.ok(H.frame().width < 20 * cell, "never the full 20-slot pool when few are up")
  end)

  t.test("changing the icon size re-fits the strip", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "A", remaining = 60, icon = 1 }, { name = "B", remaining = 60, icon = 2 } })
    H.advance(0.5, 0.5)
    B().SetSize(40)
    t.eq(H.frame().width, Toolbox.Window.GRIP + 2 * (40 + B().GAP) + 8)
  end)

  t.test("sounds: a clip whose reported name changed after loading still plays", function()
    bootWithSounds()
    for i, name in ipairs(H.S.clips) do H.S.clips[i] = "Sounds/" .. name .. " (AudioClip)" end
    H.clearLogs()
    t.ok(Toolbox.Sounds.Play("buff_expiring"), "found by its file's base name")
    t.eq(H.S.played[#H.S.played].name, "Sounds/toolbox_buff_expiring (AudioClip)")
  end)

  t.test("sounds: /tbx sounds debug shows the game's list and what was recorded", function()
    bootWithSounds()
    H.clearLogs()
    H.chat("/tbx sounds debug")
    t.ok(H.logged("^Toolbox build dev, copies loaded: 1$"), H.logs()[1])
    t.ok(H.logged("^ShroudLuaPath = "), "paths shown")
    t.ok(H.logged("^Loaded clips %(all add%-ons%): 2: toolbox_buff_expiring, toolbox_debuff_landed$"))
    t.ok(H.logged("^Buff expiring: status ready, path toolbox_buff_expiring.ogg, "
      .. "recorded clip toolbox_buff_expiring %(string%)"))
  end)

  t.test("sounds: when the .ogg never loads, the .wav beside it is used", function()
    H.boot()
    H.S.acceptMissing = true                          -- the .ogg is accepted but never shows up
    H.S.files["toolbox_buff_expiring.wav"] = true
    H.reload()
    H.advance(Toolbox.Sounds.LOAD_TIMEOUT + 2)
    local status, path = Toolbox.Sounds.Status("buff_expiring")
    t.eq(status, "ready")
    t.eq(path, "toolbox_buff_expiring.wav")
    t.ok(Toolbox.Sounds.Play("buff_expiring"))
  end)

  t.test("sounds: never 'ready' without a real clip name", function()
    H.boot()
    H.S.acceptMissing = true                          -- nothing ever loads
    H.reload()
    H.advance(Toolbox.Sounds.LOAD_TIMEOUT * 5 + 2)
    t.eq(Toolbox.Sounds.Status("buff_expiring"), "missing")
    t.eq(Toolbox.Sounds.Status("debuff_landed"), "missing")
  end)

  t.test("sounds: debug lists every path tried and what the game answered", function()
    H.boot()
    H.S.files["toolbox_buff_expiring.wav"] = true     -- only a replacement, and only as .wav
    H.reload()
    H.advance(2 * Toolbox.Sounds.LOAD_TIMEOUT + 2)
    local status, path = Toolbox.Sounds.Status("buff_expiring")
    t.eq(status, "ready")
    t.eq(path, "toolbox_buff_expiring.wav")
    H.clearLogs()
    H.chat("/tbx sounds debug")
    t.ok(H.logged("^    tried toolbox_buff_expiring%.ogg %-> false$"), "paths the game refused")
    t.ok(H.logged("^    tried toolbox_buff_expiring%.wav %-> true$"), "and the one it accepted")
  end)

  t.test("sounds: a replacement beside the package wins over the default in it", function()
    H.boot()
    H.S.files["toolbox/debuff_landed.ogg"] = true      -- the default
    H.S.files["toolbox_debuff_landed.wav"] = true      -- the player's replacement
    H.reload()
    H.advance(2 * Toolbox.Sounds.LOAD_TIMEOUT + 2)
    local _, path = Toolbox.Sounds.Status("debuff_landed")
    t.eq(path, "toolbox_debuff_landed.wav")
  end)

  t.test("Grouped, ShortTime and GroupTooltip", function()
    H.boot()
    local BB = Toolbox.BuffBar
    t.ok(BB.Grouped("BlessingOfStamina", "+75% Sprint Focus Cost Bonus", { "blessingofstamina" }), "any case")
    t.ok(BB.Grouped("PotStr", "Potion of Strength", { "Strength" }), "by the displayed name")
    t.no(BB.Grouped("Heal", "Heal", { "BlessingOfStamina" }))
    t.no(BB.Grouped("Heal", "Heal", { "" }), "an empty part matches nothing")
    t.no(BB.Grouped("Heal", "Heal", {}))
    t.eq(BB.ShortTime(612000), "7d 2h")
    t.eq(BB.ShortTime(7260), "2h 1m")
    t.eq(BB.ShortTime(245), "4m 5s")
    t.eq(BB.ShortTime(9.7), "9s")
    t.eq(BB.ShortTime(-1), "")
    t.eq(BB.ShortTime(nil), "")
    t.eq(BB.GroupTooltip({ { "B", 100 }, { "A", 90000 }, { "C", -1 } }),
      "Long-lasting buffs (3)\nA: 1d 1h\nB: 1m 40s\nC", "longest first; no time for a permanent one")
  end)

  t.test("the Obsidian potion blessings share one slot with a count and a tooltip", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Heal", remaining = 30, icon = 101 },
                 { name = "BlessingOfCapacity", label = "+100% Encumbrance Capacity", remaining = 600000, icon = 301 },
                 { name = "BlessingOfStamina", label = "+75% Sprint Focus Cost Bonus", remaining = 500000, icon = 302 },
                 { name = "BlessingOfSomethingElse", label = "Another blessing", remaining = 900, icon = 303 },
                 { name = "BlessingOfStaminaCurse", label = "A debuff", remaining = 12, icon = 201, debuff = true } })
    H.advance(1)
    local buffs = H.slots("buffs")
    t.eq(#buffs, 3, "Heal, the other blessing, the group slot")
    t.eq(buffs[1].children[1].texture, 101)
    t.eq(buffs[2].children[1].texture, 303, "a blessing that isn't listed stays on the bar")
    local g = buffs[3]
    t.eq(g.children[1].texture, 301, "the first grouped buff's icon")
    t.eq(g.children[2].text, "2")
    t.eq(g.children[1].tooltip, "Long-lasting buffs (2)\n+100% Encumbrance Capacity: 6d 22h\n"
      .. "+75% Sprint Focus Cost Bonus: 5d 18h")
    t.eq(g.children[2].tooltip, g.children[1].tooltip, "the count shows it too")
    t.eq(#H.slots("debuffs"), 1, "debuffs are never grouped")
    H.removeBuff("BlessingOfCapacity")
    H.removeBuff("BlessingOfStamina")
    H.advance(1)
    t.eq(#H.slots("buffs"), 2, "slot hidden when none are left")
  end)

  t.test("/tbx buffs group add, remove and reset change what is grouped", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs group after off")   -- by name only
    H.addBuffs({ { name = "Heal", remaining = 30, icon = 101 }, { name = "Tonic", remaining = 9000, icon = 401 } })
    H.advance(1)
    t.eq(#H.slots("buffs"), 2)
    H.clearLogs()
    H.chat("/tbx buffs group add tonic")
    t.ok(H.logged("now grouped"))
    H.advance(1)
    local buffs = H.slots("buffs")
    t.eq(#buffs, 2, "Heal + group")
    t.eq(buffs[2].children[2].text, "1")
    local saved = H.saved("buffbar").group
    t.eq(#saved, 1)
    t.eq(saved[1], "tonic")
    H.chat("/tbx buffs group add TONIC")
    t.ok(H.logged("already grouped"))
    H.reload()
    H.advance(1)
    t.eq(H.slots("buffs")[2].children[2].text, "1", "kept across a reload")
    H.chat("/tbx buffs group remove Tonic")
    H.advance(1)
    t.eq(H.slots("buffs")[2].children[1].texture, 401, "back on the bar")
    H.clearLogs()
    H.chat("/tbx buffs group remove blessingofstamina")
    t.ok(H.logged("isn't in the list"))
    H.chat("/tbx buffs group add Tonic")
    H.chat("/tbx buffs group reset")
    t.eq(#Toolbox.BuffBar.GroupParts(), 0, "reset: no names (the default)")
    H.clearLogs()
    H.chat("/tbx buffs group")
    t.ok(H.logged("buffs lasting longer than %(off%)%."))
    t.ok(H.logged("Also by name: none%."))
  end)

  t.test("the settings show the grouped names", function()
    H.boot()
    H.chat("/tbx config")
    t.ok(H.config():Find("buff_group").text:find("^Also grouped by name: none"))
    H.chat("/tbx buffs group add Tonic")
    t.ok(H.config():Find("buff_group").text:find("^Also grouped by name: Tonic "))
  end)

  t.test("a saved list that is an earlier default is cleared", function()
    H.boot({ ["character:Tester"] = { buffbar = { show = true, group = { "Obsidian" } } } })
    t.eq(#Toolbox.BuffBar.GroupParts(), 0)
    H.boot({ ["character:Tester"] = { buffbar = { show = true, group = { "BlessingOfCapacity",
      "BlessingOfConservation", "BlessingOfExpedience", "BlessingOfPrecision", "BlessingOfPrevention",
      "BlessingOfReclamation", "BlessingOfStamina" } } } })
    t.eq(#Toolbox.BuffBar.GroupParts(), 0, "the seven potions")
    H.boot({ ["character:Tester"] = { buffbar = { show = true, group = { "Obsidian", "Tonic" } } } })
    t.eq(#Toolbox.BuffBar.GroupParts(), 2, "a list the player changed is kept")
  end)

  t.test("replace hides the game's bar only while ours is showing", function()
    H.boot()
    t.no(H.S.stockHidden, "off by default")
    H.chat("/tbx buffs replace on")
    t.eq(H.saved("buffbar").replaceStock, true)
    t.no(H.S.stockHidden, "our bar isn't showing yet")
    H.chat("/tbx buffs")
    t.ok(H.S.stockHidden, "ours on: the game's hidden")
    H.chat("/tbx buffs")
    t.no(H.S.stockHidden, "ours off: the game's back at once")
    H.chat("/tbx buffs")
    H.chat("/tbx buffs replace off")
    t.no(H.S.stockHidden)
  end)

  t.test("replace is applied again after a reload and a restart", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs replace on")
    local calls = H.S.stockCalls
    H.reload()                         -- the game releases the hide (see H.reload)
    t.ok(H.S.stockHidden, "hidden again at start-up")
    t.eq(H.S.stockCalls, calls + 1)
    H.restart(nil, true)
    H.advance(1)
    t.ok(H.S.stockHidden, "and after a restart")
  end)

  t.test("replace doesn't call the game every tick", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs replace on")
    local calls = H.S.stockCalls
    H.advance(10)
    t.eq(H.S.stockCalls, calls)
  end)

  t.test("an older client: both options refused and disabled in settings", function()
    H.boot()
    H.S.noApi16 = true
    H.reload()
    H.clearLogs()
    H.chat("/tbx buffs replace on")
    t.ok(H.logged("needs Lua API 16"))
    t.no(Toolbox.BuffBar.GetReplace())
    H.chat("/tbx buffs dismiss on")
    t.no(Toolbox.BuffBar.GetClickDismiss())
    H.chat("/tbx config")
    t.eq(H.config():Find("buff_replace").enabled, false)
    t.eq(H.config():Find("buff_dismiss").enabled, false)
    H.change("toolbox_config", "buff_replace", true)
    t.eq(H.config():Find("buff_replace").value, false, "box put back")
  end)

  t.test("the settings toggles follow the commands", function()
    H.boot()
    H.chat("/tbx config")
    t.eq(H.config():Find("buff_replace").enabled, true)
    H.chat("/tbx buffs dismiss on")
    t.eq(H.config():Find("buff_dismiss").value, true)
    H.change("toolbox_config", "buff_replace", true)
    t.eq(Toolbox.BuffBar.GetReplace(), true)
  end)

  t.test("click to dismiss: off by default, then dismisses the clicked buff", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Heal", remaining = 30, icon = 101 },
                 { name = "Shield", remaining = 60, icon = 102, dismissable = true } })
    H.advance(1)
    H.clickSlot("buffs", 2)
    t.eq(H.S.dismissed, nil, "off: a click does nothing")
    t.no(H.slots("buffs")[2].children[1].tooltip:find("Click to dismiss"))
    H.chat("/tbx buffs dismiss on")
    t.eq(H.saved("buffbar").clickDismiss, true)
    H.advance(1)
    t.ok(H.slots("buffs")[2].children[1].tooltip:find("\nClick to dismiss$"), "marked")
    t.no(H.slots("buffs")[1].children[1].tooltip:find("Click to dismiss"), "Heal can't be dismissed")
    H.clickSlot("buffs", 2)
    t.eq(H.S.dismissed[1], "Shield")
    H.advance(1)
    t.eq(#H.slots("buffs"), 1)
  end)

  t.test("dismiss looks the buff up by name at click time", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs dismiss on")
    H.addBuffs({ { name = "Heal", remaining = 30, icon = 101 },
                 { name = "Shield", remaining = 60, icon = 102, dismissable = true } })
    H.advance(1)
    table.remove(H.S.buffs, 1)         -- Heal ends between the tick and the click: indices shift
    H.clickSlot("buffs", 2)
    t.eq(H.S.dismissed[1], "Shield")
  end)

  t.test("a refused dismissal is explained in chat", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs dismiss on")
    H.addBuffs({ { name = "Heal", label = "Healing", remaining = 30, icon = 101 } })
    H.advance(1)
    H.clearLogs()
    H.clickSlot("buffs", 1)
    t.ok(H.logged("Can't dismiss Healing: that buff can't be dismissed"))
    t.eq(H.S.dismissed, nil)
  end)

  t.test("debug reports the game's bar", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs replace on")
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("Game's buff bar: hidden %(Toolbox is hiding it%)"))
  end)

  t.test("SortByExpiry: soonest first, permanent last, ties by name", function()
    H.boot()
    local list = { { name = "C", remaining = 0 }, { name = "B", remaining = 50 }, { name = "A", remaining = -1 },
                   { name = "D", remaining = 10 }, { name = "E", remaining = 50 } }
    Toolbox.BuffBar.SortByExpiry(list)
    local names = {}
    for i, x in ipairs(list) do names[i] = x.name end
    t.eq(table.concat(names, ","), "D,B,E,A,C")
  end)

  t.test("the bar shows buffs soonest-to-expire on the left, the group slot last", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Long", remaining = 600, icon = 1 },
                 { name = "BlessingOfStamina", remaining = 300000, icon = 2 },
                 { name = "Aura", remaining = -1, permanent = true, icon = 3 },
                 { name = "Short", remaining = 20, icon = 4 },
                 { name = "Mid", remaining = 120, icon = 5 },
                 { name = "Bleed", remaining = 30, icon = 6, debuff = true },
                 { name = "Poison", remaining = 8, icon = 7, debuff = true } })
    H.advance(1)
    local function icons(row)
      local out = {}
      for i, s in ipairs(H.slots(row)) do
        out[i] = s.children[2].text and ("group" .. s.children[2].text) or tostring(s.children[1].texture)
      end
      return table.concat(out, ",")
    end
    t.eq(icons("buffs"), "4,5,1,3,group1", "Short, Mid, Long, permanent Aura, then the group")
    t.eq(icons("debuffs"), "7,6", "Poison before Bleed")
    for _, b in ipairs(H.S.buffs) do if b.name == "Short" then b.remaining = 800 end end    -- recast
    H.advance(1)
    t.eq(icons("buffs"), "5,1,4,3,group1", "a refreshed buff moves right")
  end)

  t.test("GroupedByTime and GroupAfterLabel", function()
    H.boot()
    local BB = Toolbox.BuffBar
    t.ok(BB.GroupedByTime(901, 900))
    t.no(BB.GroupedByTime(900, 900), "exactly the limit stays on the bar")
    t.no(BB.GroupedByTime(0, 900), "permanent (0)")
    t.no(BB.GroupedByTime(-1, 900), "no time given")
    t.no(BB.GroupedByTime(99999, 0), "off")
    t.eq(BB.GroupAfterLabel(900), "15 minutes")
    t.eq(BB.GroupAfterLabel(0), "Off")
    t.eq(BB.GroupAfterLabel(123), nil)
  end)

  t.test("by default, buffs with more than 15 minutes left are grouped until they get close", function()
    H.boot()
    H.chat("/tbx buffs")
    t.eq(Toolbox.BuffBar.GetGroupAfter(), 900)
    H.addBuffs({ { name = "Heal", remaining = 30, icon = 101 },
                 { name = "Light", remaining = 905, icon = 102 },
                 { name = "Potion", remaining = 300000, icon = 103 },
                 { name = "Aura", remaining = -1, permanent = true, icon = 104 } })
    H.advance(1)
    local buffs = H.slots("buffs")
    t.eq(#buffs, 3, "Heal, Aura, the group")
    t.eq(buffs[3].children[2].text, "2", "Light and Potion")
    H.advance(10)                      -- Light drops under 15 minutes
    buffs = H.slots("buffs")
    t.eq(#buffs, 4)
    t.eq(buffs[2].children[1].texture, 102, "Light back on the bar, by time left")
    t.eq(buffs[4].children[2].text, "1")
  end)

  t.test("group after: chat and settings change it, and it is saved", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Light", remaining = 1200, icon = 102 } })
    H.chat("/tbx buffs group after 30")
    t.eq(H.saved("buffbar").groupAfter, 1800)
    H.advance(1)
    t.eq(H.slots("buffs")[1].children[1].texture, 102, "20 minutes isn't longer than 30")
    H.clearLogs()
    H.chat("/tbx buffs group after 7")
    t.ok(H.logged("a number of minutes: 5, 10, 15, 30, 60, 120, 240, 720, 1440"))
    t.eq(Toolbox.BuffBar.GetGroupAfter(), 1800, "unchanged")
    H.chat("/tbx config")
    t.eq(H.config():Find("buff_group_after").value, "30 minutes")
    H.change("toolbox_config", "buff_group_after", "10 minutes")
    t.eq(Toolbox.BuffBar.GetGroupAfter(), 600)
    H.advance(1)
    t.eq(H.slots("buffs")[1].children[2].text, "1", "grouped now")
    H.chat("/tbx buffs group after off")
    t.eq(H.config():Find("buff_group_after").value, "Off")
    H.reload()
    t.eq(Toolbox.BuffBar.GetGroupAfter(), 0, "kept across a reload")
  end)

  t.test("buffs that load in after login aren't taken for casts (reported in game)", function()
    H.boot()
    H.S.char.present = false               -- the add-on starts before the character is in
    H.reload()
    H.advance(30)
    H.S.char.present = true                -- logged in: the buff list fills in later, one by one
    H.advance(8)
    H.addBuffs({ { name = "Light", remaining = 500, icon = 5 } })
    H.advance(1)
    t.eq(H.saved("buff_durations"), nil, "time left at login is not a full duration")
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("Light: .*unknown: cast it once"))
  end)

  t.test("buffs showing up together are a load, not casts", function()
    bootSettled()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Light", remaining = 500, icon = 5 }, { name = "Ward", remaining = 400, icon = 6 } })
    H.advance(1)
    t.eq(H.saved("buff_durations"), nil)
    H.addBuffs({ { name = "Heal", remaining = 30, icon = 7 } })   -- then one on its own: a cast
    H.advance(1)
    t.near(H.saved("buff_durations").durations.Heal, 30, 1.01, "learned from the cast")
    t.eq(H.saved("buff_durations").v, 2)
  end)

  t.test("a scene change or another character settles too", function()
    bootSettled()
    H.callback("ShroudOnSceneLoaded", "Town")
    H.advance(5)
    H.addBuffs({ { name = "Light", remaining = 500, icon = 5 } })
    H.advance(1)
    t.eq(H.saved("buff_durations"), nil, "within the settling time after a scene load")
    H.advance(Toolbox.BuffBar.SETTLE)
    H.S.char.name = "Alt"
    H.advance(2)
    H.addBuffs({ { name = "Ward", remaining = 400, icon = 6 } })
    H.advance(1)
    t.eq(H.saved("buff_durations"), nil, "within the settling time after a character change")
  end)

  t.test("durations and timers saved before the settling fix are ignored", function()
    H.boot({ ["character:Tester"] = {
      buff_durations = { BlessingOfStamina = 300435 },                        -- unversioned
      buff_timers = { v = 2, timers = { Light = { total = 50, remaining = 40, at = 90 } } },
    } })
    H.clearLogs()
    H.addBuffs({ { name = "BlessingOfStamina", remaining = 298000, icon = 5 } })
    H.advance(1)
    H.chat("/tbx buffs debug")
    t.ok(H.logged("BlessingOfStamina: .*unknown: cast it once"), "the old learned duration is dropped")
    t.eq(Toolbox.BuffBar.Recall("Light", 30), nil, "v2 timers are dropped")
  end)

  t.test("only during combat: shown in combat, and a few seconds after", function()
    H.boot()
    H.chat("/tbx buffs")
    t.ok(H.frame().visible ~= false, "shown normally")
    H.chat("/tbx buffs combat on")
    t.eq(H.saved("buffbar").combatOnly, true)
    t.eq(H.frame().visible, false, "hidden out of combat")
    H.setCombat(true)
    t.ok(H.frame().visible ~= false, "shown at once in combat")
    H.setCombat(false)
    t.ok(H.frame().visible ~= false, "still shown just after")
    H.advance(Toolbox.BuffBar.COMBAT_LINGER + 1)
    t.eq(H.frame().visible, false, "hidden a few seconds after")
    H.chat("/tbx buffs combat off")
    t.ok(H.frame().visible ~= false)
  end)

  t.test("only during combat: shown while the settings window is open, to place it", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs combat on")
    H.chat("/tbx config")
    H.advance(1)
    t.ok(H.frame().visible ~= false, "settings open")
    t.eq(H.config():Find("buffs_combat_only").value, true)
    t.eq(H.config():Find("show_buffs").value, true, "the Show setting is still on")
    H.closeWindow("toolbox_config")
    H.advance(1)
    t.eq(H.frame().visible, false)
  end)

  t.test("only during combat: alerts still run while hidden, and it starts in combat after a reload", function()
    bootWithSounds()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs combat on")
    H.chat("/tbx buffalert 5")
    H.addBuffs({ { name = "Heal", remaining = 8, icon = 1 } })
    H.advance(4, 0.5)
    t.eq(H.playedNames(), "toolbox_buff_expiring", "alert while the bar is hidden")
    H.S.combat = true
    H.reload()
    t.ok(H.frame().visible ~= false, "in combat at start: shown")
  end)

  t.test("only during combat with replace: the game's bar comes back out of combat", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx buffs replace on")
    H.chat("/tbx buffs combat on")
    t.no(H.S.stockHidden, "ours hidden, so the game's shows")
    H.setCombat(true)
    t.ok(H.S.stockHidden, "in combat ours shows and replaces it")
    H.setCombat(false)
    H.advance(Toolbox.BuffBar.COMBAT_LINGER + 1)
    t.no(H.S.stockHidden)
  end)

  t.test("only during combat: glued to the health bars, the whole strip hides", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")
    H.chat("/tbx buffs combat on")
    t.eq(H.hud().visible, false, "health bars and buffs hidden together out of combat")
    H.setCombat(true)
    t.ok(H.hud().visible ~= false, "both back in combat")
    t.ok(H.hud():Find("buffbar").visible ~= false)
    H.setCombat(false)
    H.advance(Toolbox.BuffBar.COMBAT_LINGER + 1)
    t.eq(H.hud().visible, false)
    H.chat("/tbx vitals glue off")
    t.ok(H.vitals().visible ~= false, "unglued, the health bars show on their own")
    t.eq(H.frame().visible, false, "and the buffs stay hidden")
  end)

  t.test("buff bar switched off while glued: the health bars still show", function()
    H.boot()
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")
    H.chat("/tbx buffs combat on")               -- "only during combat", but the bar itself is off
    t.ok(H.hud().visible ~= false)
  end)

  t.test("a very long buff description doesn't stop the bar (MoonSharp: pattern too complex)", function()
    H.boot()
    H.chat("/tbx buffs")
    local long = "  +5% Spell Critical Chance Bonus " .. string.rep("and a great deal more text ", 12) .. " "
    H.addBuffs({ { name = "LongOne", label = long, remaining = 5000, icon = 9 },     -- grouped: read each tick
                 { name = "Short", label = long, remaining = 60, icon = 8 } })
    H.advance(3)
    t.ok(H.slots("buffs")[2].children[1].tooltip:find("^Long%-lasting buffs %(1%)\n%+5%% Spell Critical"))
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("^%+5%% Spell Critical Chance Bonus and a great deal"))
  end)

  t.test("debuff alert without ShroudOnBuffsChanged: the bar's own check catches it", function()
    bootWithSounds()
    H.S.played = {}
    H.addBuffs({ { name = "Poison", remaining = 20, debuff = true, icon = 7 } }, true)
    H.advance(1)
    t.eq(H.playedNames(), "toolbox_debuff_landed")
    H.chat("/tbx buffs")
    H.advance(1)
    t.eq(#H.slots("debuffs"), 1, "shown in the debuff row")
    H.S.buffs = {}                               -- it wears off, silently too
    H.advance(Toolbox.BuffBar.DEBUFF_COOLDOWN + 1)
    H.S.played = {}
    H.addBuffs({ { name = "Poison", remaining = 20, debuff = true, icon = 7 } }, true)
    H.advance(1)
    t.eq(H.playedNames(), "toolbox_debuff_landed", "again when it lands again")
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("^Buff list changes seen: 0 from ShroudOnBuffsChanged, %d+ by the bar's own check%."))
  end)

  t.test("debuff alert: the callback and the bar's check don't both sound", function()
    bootWithSounds()
    H.S.played = {}
    H.addBuffs({ { name = "Poison", remaining = 20, debuff = true, icon = 7 } })
    H.advance(Toolbox.BuffBar.DEBUFF_COOLDOWN + 2)
    t.eq(H.playedNames(), "toolbox_debuff_landed", "once")
  end)

  t.test("a rune with two effects: one icon, with the longer-lasting effect's tooltip", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Light", remaining = 30, icon = 5, tooltip = "Light\n30s" },
                 { name = "Light", remaining = 600, icon = 5, tooltip = "Light\n10m" } })
    H.advance(1)
    t.eq(#H.slots("buffs"), 1)
    t.eq(H.slots("buffs")[1].children[1].tooltip, "Light\n10m")
  end)

  t.test("PlainLabel: colour codes out, first line only, capped", function()
    H.boot()
    local P = Toolbox.BuffBar.PlainLabel
    t.eq(P("[c][27E833]+5 Dexterity[-][/c]", "x"), "+5 Dexterity")
    t.eq(P("+5% Spell Critical Chance Bonus\nWhile wielding a staff, ...\nmore", "x"),
      "+5% Spell Critical Chance Bonus")
    t.eq(P("\n  \n", "fallback"), "fallback")
    t.eq(P(nil, "fallback"), "fallback")
    t.eq(P("Invalid", "fallback"), "fallback")
    local long = P(string.rep("abcdef ", 20), "x")
    t.eq(#long, Toolbox.BuffBar.LABEL_MAX)
    t.ok(long:find("%.%.%.$"))
  end)

  t.test("/tbx buffs raw lists the game's grouped buff list and how many names match", function()
    H.boot()
    H.addBuffs({ { name = "Light", remaining = 40, icon = 5 },
                 { name = "WolfSpecialAttack2", remaining = 14, icon = 6, debuff = true } })
    H.clearLogs()
    H.chat("/tbx buffs raw")
    t.ok(H.logged("^ShroudGetPlayerBuff%(%): table, 2 entries %(2 read%); 2 RuneNames match the 2 names from "
      .. "ShroudGetBuffName$"))
    t.ok(H.logged("^  %[2%] table: RuneName=WolfSpecialAttack2; RuneId=2; IsDebuff=true; IconId=6; StackCount=1; "
      .. "Effects=1 %[1%] {Description=, Value=0, "))
  end)

  t.test("game objects instead of tables (as in game): debuff flag, icons and durations are read", function()
    H.boot()
    H.S.buffObjects = true
    H.S.durationMode = "remaining"              -- as the game reports the Effects
    H.S.files["toolbox_debuff_landed.ogg"] = true
    H.reload()
    H.advance(Toolbox.BuffBar.SETTLE)
    H.chat("/tbx buffs")
    H.S.played = {}
    H.addBuffs({ { name = "WolfSpecialAttack2", label = "-0.1 Move Speed", remaining = 14, icon = 6, debuff = true } })
    H.advance(1)
    t.eq(H.playedNames(), "toolbox_debuff_landed", "the debuff alert")
    t.eq(#H.slots("debuffs"), 1, "in the debuff row")
    H.S.buffs = { { name = "Light", remaining = 100, total = 400, icon = 5 } }   -- already running
    H.S.durationMode = "remaining"
    H.callback("ShroudOnBuffsChanged")
    H.advance(Toolbox.BuffBar.SETTLE + 1)
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("^Light: .*full duration 400 s %(from the game%)"), "the full duration, from Effects")
  end)

  t.test("debug says what became of the last new debuff", function()
    bootWithSounds()
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("^Last new debuff: none seen since the add%-on started%.$"))
    H.addBuffs({ { name = "WolfSpecialAttack2", remaining = 14, debuff = true, icon = 6 } })
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("^Last new debuff: WolfSpecialAttack2, 0 s ago: played on channel %d+%.$"), H.lastLog())
    H.chat("/tbx debuffalert off")
    H.addBuffs({ { name = "Bleed", remaining = 14, debuff = true, icon = 7 } })
    H.clearLogs()
    H.chat("/tbx buffs debug")
    t.ok(H.logged("^Last new debuff: Bleed, 0 s ago: not played: the debuff alert is off%.$"))
  end)

  t.test("the count has a dark outline: four black copies under the bright number", function()
    H.boot()
    H.chat("/tbx buffs")
    H.addBuffs({ { name = "Potion", remaining = 300000, icon = 3 } })
    H.advance(1)
    local g = H.slots("buffs")[1]
    t.eq(#g.children, 6, "icon, four outline copies, the count")
    local count = g.children[6]
    t.eq(count.text, "1")
    t.eq(count.class, "bright", "the count on top, in the theme's bright colour")
    local nudges = {}
    for i = 2, 5 do
      local c = g.children[i]
      t.eq(c.text, "1")
      t.eq(c.style.color, "#000000")
      t.eq(c.tooltip, count.tooltip, "every copy shows the list on hover")
      nudges[#nudges + 1] = c.style.paddingLeft .. "," .. c.style.paddingRight .. "," .. c.style.paddingTop
    end
    local base = count.style.paddingTop
    t.eq(table.concat(nudges, " "), "2,0," .. base .. " 0,2," .. base .. " 0,0," .. (base + 1) .. " 0,0,"
      .. (base - 1), "right, left, down, up")
    Toolbox.BuffBar.SetSize(40)
    t.eq(g.children[2].style.width, 40, "resized too")
    t.eq(g.children[2].style.paddingLeft, 2, "and still nudged")
  end)

  t.test("a buff about to run out blinks a red border until it ends", function()
    bootWithSounds()
    H.chat("/tbx buffs")
    H.chat("/tbx buffalert 5")
    H.addBuffs({ { name = "Heal", remaining = 12, icon = 101 } })
    local function border() return H.slots("buffs")[1].style.borderWidth end
    H.advance(4, 0.5)
    t.eq(border(), 0, "no flash before the alert time")
    local seen = {}
    for _ = 1, 8 do
      H.advance(0.5, 0.5)
      if H.slots("buffs")[1] then seen[border()] = true end
    end
    t.ok(seen[2] and seen[0], "on and off in the last seconds")
    H.chat("/tbx buffs flash off")
    t.eq(H.saved("buffbar").flash, false)
    H.S.buffs[1].remaining = 4                  -- still in the last seconds
    H.advance(1, 0.5)
    t.eq(border(), 0, "no flash when switched off")
  end)

  t.test("after a red, flashing buff runs out, the next buff in its slot starts clean", function()
    bootWithSounds()
    H.chat("/tbx buffs")
    H.chat("/tbx buffalert 5")
    H.addBuffs({ { name = "Short", remaining = 10, icon = 1 } })
    H.advance(0.5, 0.5)
    H.addBuffs({ { name = "Aura", remaining = -1, permanent = true, icon = 2 } })   -- no sweep of its own
    H.advance(7, 0.5)
    local slot = H.slots("buffs")[1]
    t.ok(slot.children[2].uv[2] >= 0.5, "Short is red")
    H.advance(5, 0.5)                            -- Short runs out; Aura moves into the first slot
    slot = H.slots("buffs")[1]
    t.eq(slot.children[1].texture, 2)
    t.eq(slot.children[2].visible, false, "no sweep left over")
    t.eq(slot.style.borderWidth, 0, "no border left over")
  end)
end
