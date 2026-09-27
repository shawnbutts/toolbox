-- The settings window (/toolbox config).
local H = require("harness")

return function(t)
  local function open()
    H.boot()
    H.chat("/tbx config")
    return H.config()
  end
  local function find(id) return H.config():Find(id) end

  t.test("config toggles the settings window", function()
    H.boot()
    t.eq(H.config(), nil, "built on first use")
    H.chat("/tbx config")
    t.ok(H.config():IsShown())
    H.chat("/toolbox CONFIG")
    t.no(H.config():IsShown())
  end)

  t.test("controls start from the current settings", function()
    H.boot()
    H.chat("/tbx font 14")
    H.chat("/tbx xpdetailed")
    H.chat("/tbx config")
    t.eq(find("font").value, 14)
    t.eq(find("font_value").text, "14")
    t.eq(find("show_xp").value, true)
  end)

  t.test("slider sets the text size live and saves it", function()
    open()
    H.change("toolbox_config", "font", 17.0)
    t.eq(Toolbox.Window.GetFont(), 17)
    t.eq(H.window():Find("a_gain").style.fontSize, 17, "XP window updated")
    t.eq(find("font_value").text, "17")
    t.eq(H.saved("window").font, 17)
  end)

  t.test("slider values are rounded to whole sizes", function()
    open()
    H.change("toolbox_config", "font", 10.6)
    t.eq(Toolbox.Window.GetFont(), 11)
  end)

  t.test("checkbox opens and closes the Session XP window", function()
    open()
    H.change("toolbox_config", "show_xp", true)
    t.ok(H.window():IsShown())
    t.eq(H.saved("window").open, true)
    H.change("toolbox_config", "show_xp", false)
    t.no(H.window():IsShown())
    t.eq(H.saved("window").open, false)
  end)

  t.test("checkbox follows /tbx xpdetailed and the close button", function()
    open()
    H.chat("/tbx xpdetailed")
    t.eq(find("show_xp").value, true)
    H.closeWindow("toolbox_xp")
    t.eq(find("show_xp").value, false)
  end)

  t.test("a refused Show() puts the checkbox back", function()
    open()
    H.S.showRefused = true
    H.change("toolbox_config", "show_xp", true)
    t.eq(find("show_xp").value, false)
    t.no(H.window():IsShown())
  end)

  t.test("/tbx font updates an open settings window", function()
    open()
    H.chat("/tbx font 9")
    t.eq(find("font").value, 9)
    t.eq(find("font_value").text, "9")
  end)

  t.test("labels get a fixed line height and no vertical margins", function()
    H.boot()
    H.chat("/tbx xp")
    local lh = math.ceil(12 * 1.15) + 2           -- default font 12, spacing 2
    t.eq(Toolbox.Window.LineHeight(), lh)
    for _, pair in ipairs({ { H.window, "a_gain" }, { H.window, "elapsed" }, { H.compact, "p_hour" },
                            { H.compact, "a_pool_label" } }) do
      local style = pair[1]():Find(pair[2]).style
      t.eq(style.height, lh, pair[2])
      t.eq(style.marginTop, 0, pair[2])
      t.eq(style.paddingBottom, 0, pair[2])
    end
    t.eq(H.compact():Find("a_hour_label").style.paddingLeft, 10, "indent kept")
  end)

  t.test("/tbx spacing changes both windows live and is saved", function()
    H.boot()
    H.chat("/tbx xp")
    H.chat("/tbx font 9")
    H.clearLogs()
    H.chat("/tbx spacing 0")
    t.ok(H.logged("set to 0"))
    local lh = math.ceil(9 * 1.15)
    t.eq(H.window():Find("a_eta").style.height, lh)
    t.eq(H.compact():Find("a_pool").style.height, lh)
    t.eq(H.saved("window").spacing, 0)
    H.reload()
    t.eq(H.compact():Find("a_pool").style.height, lh, "rebuilt with saved spacing")
    H.clearLogs()
    H.chat("/tbx spacing")
    t.ok(H.logged("spacing is 0"))
  end)

  t.test("font changes also update the line height", function()
    H.boot()
    H.chat("/tbx font 20")
    t.eq(H.window():Find("a_head").style.height, math.ceil(20 * 1.15) + 2)
  end)

  t.test("bad spacing values are refused", function()
    H.boot()
    for _, bad in ipairs({ "-1", "13", "1.5", "wide" }) do
      H.clearLogs()
      H.chat("/tbx spacing " .. bad)
      t.ok(H.logged("whole number from 0 to 12"), bad)
    end
    t.eq(Toolbox.Window.GetSpacing(), 2)
  end)

  t.test("spacing slider in settings", function()
    open()
    t.eq(find("spacing").value, 2)
    H.change("toolbox_config", "spacing", 5.2)
    t.eq(Toolbox.Window.GetSpacing(), 5)
    t.eq(find("spacing_value").text, "5")
    H.chat("/tbx spacing 1")
    t.eq(find("spacing").value, 1, "slider follows the command")
  end)

  t.test("a corrupt saved spacing falls back to the default", function()
    H.boot({ ["character:Tester"] = { window = { spacing = 40 } } })
    t.eq(Toolbox.Window.GetSpacing(), 2)
  end)

  t.test("every checkbox follows its window when changed outside settings", function()
    H.boot()
    H.chat("/tbx config")
    local cases = {
      { "show_compact", "/tbx xp", "toolbox_compact" },
      { "show_xp", "/tbx xpdetailed", "toolbox_xp" },
      { "show_daily", "/tbx daily", "toolbox_daily" },
      { "show_daily_detail", "/tbx dailydetailed", "toolbox_daily_detail" },
    }
    for _, c in ipairs(cases) do
      H.chat(c[2])
      t.eq(find(c[1]).value, true, c[1] .. " after " .. c[2])
      H.closeWindow(c[3])
      t.eq(find(c[1]).value, false, c[1] .. " after closing")
    end
  end)

  t.test("a refused Show() only resets its own checkbox", function()
    H.boot()
    H.chat("/tbx daily")
    H.chat("/tbx config")
    H.S.showRefused = true
    H.change("toolbox_config", "show_compact", true)
    t.eq(find("show_compact").value, false)
    t.eq(find("show_daily").value, true, "daily checkbox untouched")
  end)

  t.test("line height is pinned with min/max height so a theme minimum can't override it", function()
    H.boot()
    H.S.themeMinHeight = 22               -- a theme class asking for taller lines
    H.chat("/tbx xp")
    H.chat("/tbx spacing 0")
    local lh = Toolbox.Window.LineHeight()
    t.ok(lh < 22, "line height below the theme minimum: " .. lh)
    local label = H.compact():Find("a_pool")
    t.eq(label.style.minHeight, lh)
    t.eq(label.style.maxHeight, lh)
    t.eq(select(2, label:GetSize()), lh, "laid out at the requested height")
  end)

  t.test("/tbx spacing measures the laid-out height", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx spacing")
    t.ok(H.logged("open a window to measure"), "nothing shown yet")
    H.chat("/tbx daily")
    H.clearLogs()
    H.chat("/tbx spacing")
    local lh = Toolbox.Window.LineHeight()
    t.ok(H.logged("lines should be " .. lh .. " px; in Today they measure " .. lh .. " px%."), H.lastLog())
    -- a game that ignored the height would be called out
    H.daily():Find("date").style.maxHeight = nil
    H.daily():Find("date").style.minHeight = 30
    H.clearLogs()
    H.chat("/tbx spacing")
    t.ok(H.logged("the game is not applying the height"), H.lastLog())
  end)

  t.test("setting spacing reports the new height and how to measure", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx spacing 5")
    t.ok(H.logged("set to 5 %(lines " .. Toolbox.Window.LineHeight() .. " px%)"), H.lastLog())
  end)

  t.test("spacing changes reach already-open windows of every kind", function()
    H.boot()
    H.items({ { "Ore", 1 } })
    for _, c in ipairs({ "/tbx xp", "/tbx xpdetailed", "/tbx daily", "/tbx dd" }) do H.chat(c) end
    H.chat("/tbx spacing 9")
    local lh = Toolbox.Window.LineHeight()
    local probes = {
      { H.compact, "p_hour" }, { H.window, "a_eta" }, { H.daily, "kills" }, { H.detail, "summary" },
    }
    for _, pr in ipairs(probes) do
      t.eq(select(2, pr[1]():Find(pr[2]):GetSize()), lh, pr[2])
    end
    t.eq(select(2, H.detail():Find("list").children[1].children[1]:GetSize()), lh, "item row")
  end)

  -- shortcut key -------------------------------------------------------------

  t.test("a shortcut (Ctrl+Shift+; suggested) toggles the settings window", function()
    H.boot()
    t.eq(H.S.keybinds.settings.key, "Ctrl+Shift+Semicolon")
    H.press("settings")
    t.ok(H.config():IsShown())
    H.press("settings")
    t.no(H.config():IsShown())
  end)

  t.test("the settings window and /tbx key show the shortcut and where to change it", function()
    H.boot()
    H.chat("/tbx")
    H.advance(1)
    t.eq(find("shortcut").text, "Shortcut: Ctrl+Shift+Semicolon")
    H.clearLogs()
    H.chat("/tbx key")
    t.ok(H.logged("Settings shortcut: Ctrl%+Shift%+Semicolon%. Change it in the add%-on manager, "
      .. "on Toolbox's row under Keys%."), H.lastLog())
    H.S.gameKeys = { ["Ctrl+Shift+Semicolon"] = true }
    H.advance(1)
    t.eq(find("shortcut").text, "Shortcut: Ctrl+Shift+Semicolon (the game uses it, so it doesn't reach Toolbox)")
  end)

  t.test("a refused suggestion falls back to the next, then to none, and says why", function()
    H.boot()
    H.S.badKeys = { ["Ctrl+Shift+Semicolon"] = true }
    H.reload()
    t.eq(H.S.keybinds.settings.key, "Ctrl+Semicolon", "the next suggestion")
    H.clearLogs()
    H.chat("/tbx key")
    t.ok(H.logged("not accepted: Ctrl%+Shift%+Semicolon"), H.lastLog())
    H.S.badKeys = { ["Ctrl+Shift+Semicolon"] = true, ["Ctrl+Semicolon"] = true }
    H.reload()
    t.eq(H.S.keybinds.settings.key, "", "no suggestion")
    H.clearLogs()
    H.chat("/tbx key")
    t.ok(H.logged("Settings shortcut: none set%."), H.lastLog())
    t.ok(H.logged("no suggested key was accepted"), H.lastLog())
  end)

  t.test("/tbx key counts presses, to tell a key that never arrives from one that does", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx key")
    t.ok(H.logged("Pressed 0 time%(s%) since the last reload %(0 means the game hasn't delivered the key"), H.lastLog())
    H.press("settings")
    H.press("settings")
    H.clearLogs()
    H.chat("/tbx key")
    t.ok(H.logged("Pressed 2 time%(s%) since the last reload%.$"), H.lastLog())
  end)
end
