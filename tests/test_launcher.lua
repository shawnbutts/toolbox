-- The menu (Toolbox.Launcher, end of hud.lua): buttons opening Toolbox's windows with one click.
local H = require("harness")

return function(t)
  local function strip() return H.S.frames.toolbox_launcher end
  local function button(key) return strip():Find("ln_" .. key) end
  local function click(key)
    local b = button(key)
    H.call(b.onClick, b)
  end
  local function lit(key) return button(key).style.opacity == Toolbox.Launcher.LIT end

  t.test("on by default: vertical, at the top left, said once in chat", function()
    H.firstBoot()
    t.ok(strip() and strip().visible ~= false, "shown")
    local x, y = Toolbox.Launcher.GetPosition()
    t.eq(x, 0)
    t.eq(y, 0)
    t.ok(H.logged("New: the menu, top left"), table.concat(H.logs(), "\n"))
    local w, h = Toolbox.Launcher.ContentSize()
    t.ok(h > w, "a column")
    t.eq(#Toolbox.Launcher.BUTTONS, 8)
    for _, b in ipairs(Toolbox.Launcher.BUTTONS) do
      t.ok(button(b.key), b.key)
      t.ok(button(b.key).tooltip:find(b.name, 1, true), b.key)
    end
    H.clearLogs()
    H.reload()
    t.no(H.logged("New: the menu"), "once")
    t.ok(strip(), "still on")
  end)

  t.test("a click opens its window and lights the button; another closes it and dims it", function()
    H.boot()
    H.advance(1)
    for _, key in ipairs({ "xp", "xpdetail", "today", "loot", "combat", "docs", "settings" }) do
      t.no(lit(key), key .. " starts dimmed")
      click(key)
      t.ok(lit(key), key .. " lit once open")
      H.advance(4)                       -- the game refuses a Show within 3 s of a close
      click(key)
      t.no(lit(key), key .. " dimmed once closed")
      H.advance(4)
    end
    click("xp")
    t.ok(Toolbox.Compact.IsShown(), "the XP window itself")
    click("loot")
    t.ok(Toolbox.DailyDetail.IsOpen(), "the Loot Tracker pinned")
    H.closeWindow("toolbox_compact")
    H.advance(1)
    t.no(lit("xp"), "follows a window closed another way")
  end)

  t.test("Notifications: the current news in the window, or a word in chat when there's none", function()
    H.boot()
    H.advance(Toolbox.Notify.SETTLE + 1)
    H.clearLogs()
    click("notify")
    t.ok(H.logged("No notifications right now"), table.concat(H.logs(), "\n"))
    t.no(lit("notify"))
    H.chat("/tbx notify via hud")         -- delivered elsewhere: the button still shows it in the window
    H.setNotes{ unreadMail = 2 }
    H.advance(1)
    click("notify")
    t.ok(Toolbox.Notify.IsShown(), "the window")
    t.ok(lit("notify"))
    click("notify")
    t.no(Toolbox.Notify.IsShown(), "closed again")
  end)

  t.test("off, horizontal and size: from settings and chat, kept over a restart", function()
    H.boot()
    H.chat("/tbx config")
    H.change("toolbox_config", "ln_vertical", false)
    local w, h = Toolbox.Launcher.ContentSize()
    t.ok(w > h, "a row")
    H.change("toolbox_config", "ln_size", 48)
    t.eq(Toolbox.Launcher.GetSize(), 48)
    t.eq(button("xp").style.width or button("xp").width, 48, "rebuilt at the new size")
    t.no(Toolbox.Launcher.SetSize(66), "past the most")
    H.change("toolbox_config", "ln_show", false)
    t.eq(strip(), nil, "no strip: the old way")
    t.eq(H.configRaw():Find("ln_size").enabled, false, "its options greyed out")
    H.restart(nil, true)
    t.eq(strip(), nil, "stays off")
    H.chat("/tbx menu on")
    t.ok(strip())
    t.eq(Toolbox.Launcher.GetSize(), 48)
    t.eq(Toolbox.Launcher.GetVertical(), false)
    H.chat("/tbx launcher vertical")
    t.ok(Toolbox.Launcher.GetVertical())
    H.chat("/tbx menu size 99")
    t.ok(H.logged("menu size 20%-64"), H.lastLog())
  end)

  t.test("pictures from launcher.png, tinted gold, one frame a button; text buttons without it", function()
    H.boot()
    H.S.files["toolbox/launcher.png"] = true
    H.reload()
    local n = #Toolbox.Launcher.BUTTONS
    for i, b in ipairs(Toolbox.Launcher.BUTTONS) do
      local e = button(b.key)
      t.ok(e.texture, b.key .. ": a picture")
      t.eq(e.tint, "@gold")
      t.near(e.uv[1], (i - 1) / n)
      t.near(e.uv[3], 1 / n)
    end
    H.S.files["toolbox/launcher.png"] = nil
    H.reload()
    t.eq(button("loot").text, "Loot", "a word instead")
  end)

  t.test("Settings last with Docs above it; the picture frames follow the order", function()
    H.boot()
    local keys = {}
    for _, b in ipairs(Toolbox.Launcher.BUTTONS) do keys[#keys + 1] = b.key end
    t.eq(table.concat(keys, " "), "xp xpdetail today loot combat notify docs settings")
    local kids = strip():Find("launcher").children
    t.eq(kids[#kids].id, "ln_settings")
    t.eq(kids[#kids - 1].id, "ln_docs")
  end)

  t.test("a shade behind the buttons, changed in place; 0 for none", function()
    H.boot()
    local box = strip():Find("launcher")
    t.eq(box.style.backgroundColor, "#00000066", "40% by default")
    local made = H.S.constructed
    H.chat("/tbx config")
    H.change("toolbox_config", "ln_shade", 70)
    t.eq(strip():Find("launcher").style.backgroundColor, "#000000b3")
    H.chat("/tbx menu shade 0")
    t.eq(strip():Find("launcher").style.backgroundColor, "#00000000")
    t.no(H.call(Toolbox.Launcher.SetShade, 95), "past the most")
    t.eq(Toolbox.Launcher.ShadeColor(100), "#000000ff")
    t.ok(H.S.constructed - made < 400, "no rebuild of the strip (only the settings page)")
  end)

  t.test("its settings lead the Menu, setups, backup & reset page", function()
    H.boot()
    H.chat("/tbx config")
    t.eq(Toolbox.Config.PageOf("ln_size"), "backup")
    local label = nil
    for _, c in ipairs(Toolbox.Config.CATEGORIES) do if c.key == "backup" then label = c.label end end
    t.eq(label, "Menu, setups, backup & reset")
  end)

  t.test("pick its buttons; the last one can't go", function()
    H.boot()
    H.chat("/tbx config")
    H.change("toolbox_config", "ln_btn_combat", false)
    t.eq(strip():Find("ln_combat"), nil, "left out")
    local _, h = Toolbox.Launcher.ContentSize()
    t.ok(h < 8 * 32, "shorter")
    for _, b in ipairs(Toolbox.Launcher.BUTTONS) do
      if b.key ~= "settings" then H.call(Toolbox.Launcher.SetButton, b.key, false) end
    end
    local ok, why = H.call(Toolbox.Launcher.SetButton, "settings", false)
    t.no(ok)
    t.ok(why:find("at least one", 1, true), why)
    t.ok(strip():Find("ln_settings"), "still there")
    H.restart(nil, true)
    t.eq(strip():Find("ln_xp"), nil, "kept")
    t.ok(strip():Find("ln_settings"))
  end)

  t.test("hide during combat: gone in a fight, back after; shown while settings are open", function()
    H.boot()
    H.chat("/tbx menu combat hide")
    H.setCombat(true)
    H.advance(1)
    t.eq(strip().visible, false, "hidden in combat")
    H.chat("/tbx config")
    H.advance(1)
    t.ok(strip().visible ~= false, "settings open: to place it")
    H.closeWindow("toolbox_config")
    H.setCombat(false)
    H.advance(30)
    t.ok(strip().visible ~= false, "back after the fight")
  end)

  t.test("a reset brings it back with the defaults", function()
    H.boot()
    H.chat("/tbx menu off")
    H.chat("/tbx settings reset")
    H.chat("/tbx settings reset")
    H.reload()
    t.ok(strip(), "on again")
  end)
end
