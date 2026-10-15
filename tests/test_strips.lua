-- The XP and Today windows shown as HUD strips (/toolbox xp hud, /toolbox daily hud).
local H = require("harness")

return function(t)
  local function xpStrip() return H.S.frames.toolbox_xp_hud end
  local function dailyStrip() return H.S.frames.toolbox_daily_hud end
  local function shown(frame) return frame ~= nil and frame.visible == true end
  local function hoverStrip(frame, id, over)
    local e = frame:Find(id)
    H.call(function() e.onHover(e, over) end)
  end

  t.test("xp hud: the window hides, the strip shows the same lines", function()
    H.boot(nil, 0)
    H.chat("/tbx xp")
    H.chat("/tbx xp hud")
    t.no(H.compact():IsShown(), "window hidden")
    t.ok(shown(xpStrip()), "strip shown")
    t.ok(Toolbox.Compact.IsShown(), "still counts as shown")
    H.gain(12000, 300)
    H.advance(125)
    local f = xpStrip()
    t.eq(f:Find("elapsed").text, "Session 2m 05s")
    t.eq(f:Find("a_pool_label").text, "Adv pool")
    t.eq(f:Find("a_hour").text, "+12,000")
    t.eq(f:Find("p_pool").text, "4,300")
    t.eq(H.saved("compact").hud, true)
  end)

  t.test("xp hud: toggling shows and hides the strip; window brings the window back", function()
    H.boot()
    H.chat("/tbx xp hud")
    t.no(shown(xpStrip()), "was closed, stays closed")
    H.chat("/tbx xp")
    t.ok(shown(xpStrip()))
    H.chat("/tbx xp")
    t.no(shown(xpStrip()))
    H.chat("/tbx xp")
    H.chat("/tbx xp window")
    t.no(shown(xpStrip()))
    t.ok(H.compact():IsShown(), "open as a window again")
    t.eq(H.saved("compact").hud, false)
  end)

  t.test("xp hud: form, open state and strip position survive reload", function()
    H.boot()
    H.chat("/tbx xp")
    H.chat("/tbx xp hud")
    H.chat("/tbx xp move 300 50")
    H.advance(1)
    H.reload()
    t.ok(shown(xpStrip()))
    t.no(H.compact():IsShown())
    t.eq(xpStrip().x, 300)
    t.eq(xpStrip().y, 50)
    t.eq(H.saved("compact").hx, 300, "the strip keeps its own spot")
    t.eq(H.saved("compact").x, nil, "the window's spot is untouched")
  end)

  t.test("move only applies to the strip", function()
    H.boot()
    H.chat("/tbx xp")
    H.chat("/tbx xp move 300 50")
    t.ok(H.lastLog():find("title bar", 1, true), H.lastLog())
  end)

  t.test("hovering the strip pops up XP Detailed", function()
    H.boot()
    H.chat("/tbx xp hud")
    H.chat("/tbx xp")
    hoverStrip(xpStrip(), "strip", true)
    H.advance(1, 0.1)
    t.ok(H.window():IsShown(), "popped up")
    hoverStrip(xpStrip(), "strip", false)
    H.advance(2, 0.1)
    t.no(H.window():IsShown(), "gone after leaving")
  end)

  t.test("the strip follows the text size and its labels have no side margins", function()
    H.boot()
    H.chat("/tbx xp hud")
    H.chat("/tbx xp")
    local w1 = xpStrip().width
    H.chat("/tbx font 16")
    t.eq(xpStrip():Find("a_pool").style.fontSize, 16)
    t.ok(xpStrip().width > w1, "strip grew with the text")
    for _, id in ipairs({ "elapsed", "a_pool_label", "a_pool", "a_hour_label" }) do
      local st = xpStrip():Find(id).style
      t.eq(st.marginRight, 0, id)
      t.ok(st.marginLeft == 0 or id == "a_hour_label", id)
    end
    t.eq(xpStrip():Find("a_hour_label").style.marginLeft, Toolbox.Hud.STRIP_INDENT, "indented line")
  end)

  t.test("settings toggles pick the form", function()
    H.boot()
    H.chat("/tbx config")
    H.chat("/tbx xp")
    H.change("toolbox_config", "xp_mode", "HUD strip")
    t.ok(shown(xpStrip()))
    t.no(H.compact():IsShown())
    t.eq(H.config():Find("xp_mode").value, "HUD strip")
    H.chat("/tbx daily")
    H.chat("/tbx daily hud")
    t.eq(H.config():Find("daily_mode").value, "HUD strip", "follows the chat command")
  end)

  t.test("daily hud shows today's numbers and pops up Loot Tracker", function()
    H.boot()
    H.chat("/tbx daily")
    H.chat("/tbx daily hud")
    t.no(H.daily():IsShown())
    t.ok(shown(dailyStrip()))
    H.goldChange(250)
    H.combat{ { kind = "death", fromYou = true } }
    H.advance(1)
    t.eq(dailyStrip():Find("gold").text, "250")
    t.eq(dailyStrip():Find("kills").text, "1")
    t.ok(dailyStrip():Find("date").text:find("^Today"))
    hoverStrip(dailyStrip(), "strip", true)
    H.advance(1, 0.1)
    t.ok(H.detail():IsShown(), "Loot Tracker popped up")
  end)

  t.test("glueing the other strips leaves these alone", function()
    H.boot()
    H.chat("/tbx xp hud")
    H.chat("/tbx xp")
    H.chat("/tbx vitals glue on")
    t.ok(shown(xpStrip()), "own strip after the rebuild")
    H.advance(1)
    t.ok(xpStrip():Find("elapsed").text:find("^Session"))
  end)

  -- Owner, 2026-10-15: every HUD strip's background shade has a slider, all alike at first.
  t.test("background shade: the XP, Today, notification and location strips, alike at first, set in place", function()
    local was = H.MAX_HUD_FRAMES
    H.MAX_HUD_FRAMES = 25                       -- every strip at once (the work log, 2026-10-01)
    H.boot()
    H.chat("/tbx xp")
    H.chat("/tbx xp hud")
    H.chat("/tbx daily")
    H.chat("/tbx daily hud")
    H.chat("/tbx location on")
    H.chat("/tbx notify mail via hud")
    H.setNotes{ unreadMail = 2 }
    H.advance(1)
    local function bg(frame, id) return frame:Find(id).style.backgroundColor end
    local panels = {
      { xpStrip, "strip", "xp_shade", "compact" },
      { dailyStrip, "strip", "daily_shade", "daily_window" },
      { function() return H.nhud() end, "nh_panel", "nhud_shade", "notify_hud" },
      { function() return H.S.frames.toolbox_location end, "loc_strip", "loc_shade", "location" },
    }
    for _, p in ipairs(panels) do
      t.eq(bg(p[1](), p[2]), "#00000099", p[3] .. ": 60% at first")
      t.no(p[1]():Find(p[2]):Classes().inset, p[3] .. ": not the theme's panel (it can't be made lighter)")
    end
    H.chat("/tbx config")
    for i, p in ipairs(panels) do
      local before = p[1]():Find(p[2])
      H.change("toolbox_config", p[3], i * 10)
      t.eq(p[1]():Find(p[2]), before, p[3] .. ": not rebuilt")
      t.eq(bg(p[1](), p[2]), Toolbox.ShadeColor(i * 10), p[3])
      t.eq(H.saved(p[4]).shade, i * 10, p[3] .. " saved")
    end
    H.change("toolbox_config", "xp_shade", 0)
    t.eq(bg(xpStrip(), "strip"), "#00000000", "0: none")
    H.reload()
    H.advance(1)
    t.eq(bg(dailyStrip(), "strip"), Toolbox.ShadeColor(20), "kept")
    t.eq(bg(H.S.frames.toolbox_location, "loc_strip"), Toolbox.ShadeColor(40))
    t.no(Toolbox.Compact.SetShade(95), "past the most")
    t.no(Toolbox.Location.SetShade(-5))
    H.MAX_HUD_FRAMES = was
  end)
end
