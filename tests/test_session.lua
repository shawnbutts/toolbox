-- Session lifecycle: start, sampling, reload persistence, logout, restarts, window prefs.
local H = require("harness")

return function(t)
  local function gained(key) return Toolbox.XP.Gained(Toolbox.session, key) end

  t.test("session starts from current totals and is flushed", function()
    H.boot(nil, 500)
    local s = Toolbox.session
    t.ok(s, "session exists")
    t.eq(s.start, 500)
    t.eq(s.base.a, 1000000)
    t.eq(s.base.p, 500000)
    t.eq(s.player, "Tester")
    t.ok(H.S.flushes >= 1, "flushed at start")
    t.ok(H.S.disk["character:Tester"].session, "on disk")
  end)

  t.test("periodic sampling picks up XP without the callback", function()
    H.boot()
    H.gain(1200, 300, false)     -- no ShroudOnExperienceGain
    t.eq(gained("a"), 0)
    H.advance(1)
    t.eq(gained("a"), 1200)
    t.eq(gained("p"), 300)
  end)

  t.test("the XP callback resamples immediately", function()
    H.boot()
    H.gain(700, 0)
    t.eq(gained("a"), 700)
  end)

  t.test("session survives /lua reload", function()
    H.boot(nil, 1000)
    H.gain(10000, 2000)
    H.advance(300)
    H.reload()
    t.eq(Toolbox.session.start, 1000, "same start")
    t.eq(gained("a"), 10000)
    t.eq(gained("p"), 2000)
    H.gain(5000, 0)
    H.advance(300)
    t.eq(gained("a"), 15000)
    t.near(Toolbox.XP.SessionRate(Toolbox.session, "a", ShroudTime), 15000 * 6, 1e-6)
  end)

  t.test("rolling window survives /lua reload", function()
    H.boot(nil, 0)
    for _ = 1, 20 do H.advance(30); H.gain(1000, 0) end    -- 20000 over 600 s
    H.reload()
    t.near(Toolbox.XP.WindowRate(Toolbox.session, "a", ShroudTime), 20000 * 6, 1)
  end)

  t.test("XP gained during a reload is still counted", function()
    H.boot()
    H.gain(100, 0)
    ShroudFlushSavedVars()
    H.S.char.adv = H.S.char.adv + 900     -- gained while the add-on was unloaded
    H.reload()
    H.advance(1)
    t.eq(gained("a"), 1000)
  end)

  t.test("logout ends the session; logging back in starts a new one", function()
    H.boot(nil, 100)
    H.gain(4000, 0)
    H.advance(10)
    H.S.char.present = false
    H.callback("ShroudOnLogOut")
    t.ok(H.S.disk["character:Tester"].session.ended, "ended flag flushed")
    H.advance(5)                          -- login screen: no character, nothing happens
    t.ok(Toolbox.session.ended)
    H.S.char.present = true
    H.advance(1)
    t.no(Toolbox.session.ended)
    t.eq(gained("a"), 0, "fresh session")
    t.eq(Toolbox.session.reason, "login")
  end)

  t.test("an ended session is not resumed on the next start", function()
    H.boot(nil, 100)
    H.gain(4000, 0)
    H.callback("ShroudOnLogOut")
    H.restart(20)
    t.eq(gained("a"), 0)
    t.eq(Toolbox.session.start, 20)
  end)

  t.test("a client restart (crash, no logout) starts a new session", function()
    H.boot(nil, 5000)
    H.gain(4000, 0)
    H.advance(40)                          -- periodic save + flush at 30 s
    H.restart(60)                          -- ShroudTime went backwards
    t.eq(Toolbox.session.start, 60)
    t.eq(gained("a"), 0)
  end)

  t.test("no character at start: waits, then starts", function()
    H.boot()
    H.S.char.present = false
    H.reload()
    -- the previous session was resumed from saved vars? only with character data
    t.eq(Toolbox.session, nil)
    H.advance(3)
    t.eq(Toolbox.session, nil)
    H.S.char.present = true
    H.advance(1)
    t.ok(Toolbox.session)
  end)

  t.test("switching character starts a new session", function()
    H.boot()
    H.gain(100, 0)
    H.S.char.name = "Other"
    H.advance(1)
    t.eq(Toolbox.session.player, "Other")
    t.eq(gained("a"), 0)
  end)

  t.test("a bad zero reading is ignored", function()
    H.boot()
    H.gain(500, 0)
    H.S.char.adv, H.S.char.prod = 0, 0
    H.advance(1)
    t.eq(gained("a"), 500)
  end)

  t.test("corrupt saved session is replaced", function()
    local fresh_disk = { ["character:Tester"] = { session = { v = 1, player = "Tester", start = "x" } } }
    H.boot(fresh_disk, 100)
    t.eq(Toolbox.session.start, 100)
    t.ok(Toolbox.XP.IsValid(Toolbox.session))
  end)

  t.test("active session is saved periodically, not every tick", function()
    H.boot()
    local before = H.S.flushes
    H.gain(10, 0)
    H.advance(5)
    t.eq(H.S.flushes, before, "no flush within 30 s")
    H.advance(30)
    t.eq(H.S.flushes, before + 1)
    H.advance(60)
    t.eq(H.S.flushes, before + 1, "nothing new, nothing written")
  end)

  t.test("window shows the numbers", function()
    H.boot(nil, 0)
    H.chat("/tbx xpdetailed")
    H.gain(36000, 1800)
    H.advance(1800)
    t.eq(H.text("elapsed"), "Session 30m 00s")
    t.eq(H.text("a_head"), "Adventurer  Lv 50  20.0%")
    t.eq(H.text("a_gain"), "+36,000  72,000/h  (10m 0/h)")
    t.eq(H.text("p_head"), "Producer  Lv 40  10.0%")
    t.eq(H.text("p_gain"), "+1,800  3,600/h  (10m 0/h)")
    t.near(H.window():Find("a_bar").value, 0.2)
    -- 80,000 to go at 72,000/h = 1h 06m 40s
    t.eq(H.text("a_eta"), "Next level: 80,000 XP (about 1h 06m 40s at 72,000/h)")
  end)

  t.test("sections have a side gutter so bars don't touch the window edge", function()
    H.boot()
    H.chat("/tbx xpdetailed")
    local w = H.window()
    local header = w.children[1]
    local scroll = w.children[2]
    t.eq(header.style.paddingLeft, Toolbox.Window.GUTTER)
    t.eq(header.style.paddingRight, Toolbox.Window.GUTTER)
    for _, column in ipairs(scroll.children) do
      t.eq(column.style.paddingLeft, Toolbox.Window.GUTTER)
      t.eq(column.style.paddingRight, Toolbox.Window.GUTTER)
    end
  end)

  t.test("next level line explains a missing estimate", function()
    H.boot()
    H.chat("/tbx xpdetailed")
    H.gain(3600, 0)
    H.advance(10)
    t.eq(H.text("p_eta"), "Next level: 45,000 XP (no XP gained yet)", "producer, no gains")
    t.ok(H.text("a_eta"):find("^Next level: 80,000 XP %(about "), H.text("a_eta"))
    H.S.char.progress.adventurer = { level = 100, intoLevel = 5000, forLevel = 100000, percent = 0 }
    H.advance(1)
    t.eq(H.text("a_eta"), "Next level: max level")
    t.eq(H.text("a_head"), "Adventurer  Lv 100  0.0%")
  end)

  t.test("window without level data", function()
    H.boot()
    H.chat("/tbx xpdetailed")
    H.S.char.progress = { adventurer = {}, producer = {} }
    H.advance(1)
    t.eq(H.text("a_head"), "Adventurer  Lv --")
    t.eq(H.text("a_eta"), "Next level: --")
  end)

  t.test("font size: default, set, persisted, applied after reload", function()
    H.boot()
    H.chat("/tbx xpdetailed")
    local label = function() return H.window():Find("a_gain") end
    t.eq(label().style.fontSize, 12, "default")
    H.clearLogs()
    H.chat("/tbx font 10")
    t.ok(H.logged("set to 10"))
    t.eq(label().style.fontSize, 10, "applied live")
    t.eq(H.window():Find("reset").style.fontSize, 10, "button too")
    t.eq(H.saved("window").font, 10)
    H.reload()
    t.eq(label().style.fontSize, 10, "rebuilt with saved size")
    H.clearLogs()
    H.chat("/tbx font")
    t.ok(H.logged("size is 10"))
  end)

  t.test("font size: out of range or not a number is refused", function()
    H.boot()
    for _, bad in ipairs({ "8", "33", "11.5", "big" }) do
      H.clearLogs()
      H.chat("/tbx font " .. bad)
      t.ok(H.logged("whole number from 9 to 32"), bad)
    end
    t.eq(Toolbox.Window.GetFont(), 12)
  end)

  t.test("a corrupt saved font size falls back to the default", function()
    H.boot({ ["character:Tester"] = { window = { open = true, font = 99 } } })
    t.eq(Toolbox.Window.GetFont(), 12)
  end)

  t.test("reset button starts a new session", function()
    H.boot()
    H.chat("/tbx xpdetailed")
    H.gain(999, 0)
    H.click("toolbox_xp", "reset")
    t.eq(gained("a"), 0)
  end)

  t.test("window open state and position survive reload", function()
    H.boot()
    H.chat("/tbx xpdetailed")
    H.moveWindow("toolbox_xp", 640, 222)
    H.advance(1)
    H.reload()
    t.ok(H.window():IsShown(), "reopened")
    t.eq(H.window().x, 640)
    t.eq(H.window().y, 222)
  end)

  t.test("closing the window is remembered", function()
    H.boot()
    H.chat("/tbx xpdetailed")
    H.closeWindow("toolbox_xp")
    t.eq(H.saved("window").open, false)
    H.reload()
    t.no(H.window():IsShown())
  end)

  t.test("a refused Show() is reported", function()
    H.boot()
    H.S.showRefused = true
    H.clearLogs()
    H.chat("/tbx xpdetailed")
    t.no(H.window():IsShown())
    t.ok(H.logged("can't reopen"))
    t.eq(H.saved("window").open, false)
  end)

  t.test("window prefs are per character scope", function()
    H.firstBoot()
    H.chat("/tbx xpdetailed")
    t.eq(H.S.memory["character:Tester"].window.open, true)
    local account = H.S.memory.account or {}
    t.eq(account.window, nil, "window prefs aren't account-wide")
    t.eq(account.welcomed, true, "only the one-time welcome flag is")
  end)
end
