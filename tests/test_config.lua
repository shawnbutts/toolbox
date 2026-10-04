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
    H.chat("/tbx xpdetailed")
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
    H.chat("/tbx xpdetailed")
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
    H.chat("/tbx xpdetailed")
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
    H.chat("/tbx xpdetailed")
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
    local cases = {       -- control, command, window, value when open, value when closed
      { "xp_mode", "/tbx xp", "toolbox_compact", "Window", "Hidden" },
      { "show_xp", "/tbx xpdetailed", "toolbox_xp", true, false },
      { "daily_mode", "/tbx daily", "toolbox_daily", "Window", "Hidden" },
      { "show_daily_detail", "/tbx dailydetailed", "toolbox_daily_detail", true, false },
    }
    for _, c in ipairs(cases) do
      H.chat(c[2])
      t.eq(find(c[1]).value, c[4], c[1] .. " after " .. c[2])
      H.closeWindow(c[3])
      t.eq(find(c[1]).value, c[5], c[1] .. " after closing")
    end
  end)

  t.test("a refused Show() only resets its own checkbox", function()
    H.boot()
    H.chat("/tbx daily")
    H.chat("/tbx config")
    H.S.showRefused = true
    H.change("toolbox_config", "xp_mode", "Window")
    t.eq(find("xp_mode").value, "Hidden", "put back: the window was refused")
    t.eq(find("daily_mode").value, "Window", "Today's untouched")
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

  t.test("a shortcut (Ctrl+; suggested) toggles the settings window", function()
    H.boot()
    t.eq(H.S.keybinds.settings.key, "Ctrl+Semicolon")
    H.press("settings")
    t.ok(H.config():IsShown())
    H.press("settings")
    t.no(H.config():IsShown())
  end)

  t.test("the settings window and /tbx key show the shortcut and where to change it", function()
    H.boot()
    H.chat("/tbx")
    H.advance(1)
    t.eq(find("shortcut").text, "Shortcut: Ctrl+Semicolon")
    H.clearLogs()
    H.chat("/tbx key")
    t.ok(H.logged("Settings shortcut: Ctrl%+Semicolon%. Change it in the add%-on manager, "
      .. "on Toolbox's row under Keys%."), H.lastLog())
    H.S.gameKeys = { ["Ctrl+Semicolon"] = true }
    H.advance(1)
    t.eq(find("shortcut").text, "Shortcut: Ctrl+Semicolon (the game uses it, so it doesn't reach Toolbox)")
  end)

  t.test("a refused suggestion falls back to none, and says why", function()
    H.boot()
    H.S.badKeys = { ["Ctrl+Semicolon"] = true }
    H.reload()
    t.eq(H.S.keybinds.settings.key, "", "no suggestion")
    H.clearLogs()
    H.chat("/tbx key")
    t.ok(H.logged("Settings shortcut: none set%."), H.lastLog())
    t.ok(H.logged("no suggested key was accepted: Ctrl%+Semicolon"), H.lastLog())
  end)

  t.test("/tbx key counts presses, to tell a key that never arrives from one that does", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx key")
    t.ok(H.logged("Pressed 0 time%(s%) since Toolbox last started %(0 means the game hasn't delivered the key"),
      H.lastLog())
    H.press("settings")
    H.press("settings")
    H.clearLogs()
    H.chat("/tbx key")
    t.ok(H.logged("Pressed 2 time%(s%) since Toolbox last started%.$"), H.lastLog())
  end)

  -- live values (strip positions, sound status) -------------------------------

  t.test("while settings is open, a strip dragged by its grip updates its Position label", function()
    H.boot()
    H.chat("/tbx vitals")
    H.chat("/tbx config")
    H.advance(1)
    H.S.frames.toolbox_vitals.x, H.S.frames.toolbox_vitals.y = 500, 260     -- the player drags the grip
    H.advance(1)
    t.eq(H.config():Find("vitals_pos").text, "500, 260")
  end)

  t.test("while settings is hidden its live labels aren't touched; opening it brings them up to date", function()
    H.boot()
    H.chat("/tbx vitals")
    H.chat("/tbx config")
    H.advance(1)
    H.closeWindow("toolbox_config")
    local label = H.config():Find("vitals_pos")
    local writes = 0
    local set = label.SetText
    label.SetText = function(self, text)
      writes = writes + 1
      return set(self, text)
    end
    H.S.frames.toolbox_vitals.x, H.S.frames.toolbox_vitals.y = 480, 250
    H.advance(10)
    t.eq(writes, 0, "no updates while hidden")
    H.chat("/tbx config")
    t.eq(label.text, "480, 250", "up to date as soon as it opens")
    label.SetText = nil
  end)

  t.test("a sound that finished loading while settings was hidden shows when it reopens", function()
    H.boot()
    H.chat("/tbx config")
    H.closeWindow("toolbox_config")
    H.S.files["toolbox_buff_expiring.ogg"] = true
    H.reload()
    H.chat("/tbx config")
    H.closeWindow("toolbox_config")
    H.advance(5)                                          -- the clip loads while hidden
    H.chat("/tbx config")
    t.ok(H.config():Find("snd_buff_expiring_status").text:find("toolbox_buff_expiring"),
      H.config():Find("snd_buff_expiring_status").text)
  end)

  -- categories ---------------------------------------------------------------

  t.test("settings open on one category; others are built the first time they are picked", function()
    H.boot()
    local before = H.S.constructed or 0
    H.chat("/tbx config")
    local opened = (H.S.constructed or 0) - before
    local w = H.configRaw()
    t.eq(w:Find("category").value, "Toolbelt", "the Toolbelt first: the quickest start")
    t.eq(#w:Find("category").choices, #Toolbox.Config.CATEGORIES)
    t.ok(w:Find("toolbelt_show"), "the first category is built")
    t.eq(w:Find("show_buffs"), nil, "the others aren't yet")
    t.ok(opened < 90, "elements created when it opens: " .. opened)
    H.change("toolbox_config", "category", "Buffs")          -- (H.change builds all; pick by the handler)
    t.eq(Toolbox.Config.CurrentCategory(), "buffs")
    t.eq(w:Find("show_buffs").visible ~= false, true)
    t.eq(w:Find("toolbelt_show"), nil, "the category shown before is destroyed (the 2,000-element cap)")
    t.eq(#w.children[2].children[1].children, 1, "one category built at a time")
  end)

  t.test("every page visited with everything open and a full day's loot stays inside the 2,000 elements", function()
    H.boot()
    for _, c in ipairs({ "/tbx xp", "/tbx xpdetailed", "/tbx daily", "/tbx dd", "/tbx buffs", "/tbx vitals",
                         "/tbx combat", "/tbx combat detail", "/tbx notify via hud", "/tbx target on",
                         "/tbx toolbelt vitals on", "/tbx toolbelt consumables on", "/tbx toolbelt gear on" }) do
      H.chat(c)
    end
    for i = 1, 250, 20 do                              -- a full day: Loot Tracker's 250 kinds
      local batch = {}
      for j = i, math.min(i + 19, 250) do batch[#batch + 1] = { string.format("Loot Item %03d", j), 1 } end
      H.items(batch)
      H.advance(1)
    end
    H.advance(60)
    H.chat("/tbx config")
    local drop = H.configRaw():Find("category")
    local peak = 0
    for _, cat in ipairs(Toolbox.Config.CATEGORIES) do
      H.advance(2)                                     -- picked one after another, at a player's pace
      H.clearLogs()
      H.call(function() drop.onChange(drop, cat.label) end)
      t.eq(Toolbox.Config.CurrentCategory(), cat.key, cat.label .. " shows")
      t.no(H.logged("can't be shown right now"), cat.label .. ": " .. tostring(H.lastLog()))
      peak = math.max(peak, H.S.live)
    end
    -- 1,058 in the harness (1,393 while every page stayed built, which hit the game's 2,000 in game: the game
    -- counts more than the harness, so keep a wide margin)
    t.ok(peak < 1200, "live elements at the most: " .. peak .. " (the game's cap is 2,000)")
  end)

  t.test("picking a category from the dropdown builds just that one", function()
    H.boot()
    H.chat("/tbx config")
    local w = H.configRaw()
    local drop = w:Find("category")
    H.call(function() drop.onChange(drop, "Health bars") end)
    t.ok(w:Find("show_vitals"), "built on first pick")
    t.eq(w:Find("show_combat"), nil, "the rest still not")
    t.eq(Toolbox.Config.CurrentCategory(), "vitals")
    H.closeWindow("toolbox_config")
    H.chat("/tbx config")
    t.eq(Toolbox.Config.CurrentCategory(), "vitals", "reopens where it was left")
  end)

  t.test("controls whose feature is off are greyed out", function()
    H.boot()
    H.chat("/tbx config")
    local w = H.config()
    t.eq(w:Find("hover_popup").enabled, false, "XP hover while XP is hidden")
    t.eq(w:Find("vitals_scale").enabled, false, "health bar options while the bars are off")
    t.eq(w:Find("buffs_combat_only").enabled, false, "buff bar options while it is off")
    t.ok(w:Find("expire_alert").enabled ~= false, "alerts work with the bar hidden: never greyed")
    t.ok(w:Find("buff_size").enabled ~= false, "icon size: the other bars use it too")
    H.chat("/tbx xp")
    H.chat("/tbx vitals")
    H.chat("/tbx buffs")
    t.ok(w:Find("hover_popup").enabled ~= false)
    t.ok(w:Find("vitals_scale").enabled ~= false)
    t.ok(w:Find("buffs_combat_only").enabled ~= false)
    t.ok(w:Find("toolbelt_combat").enabled ~= false)
    H.chat("/tbx buffs")
    t.eq(w:Find("toolbelt_combat").enabled, false, "only during combat, while the Toolbelt is off")
  end)

  t.test("Toolbelt page: says the buff bar is its base", function()
    H.boot()
    H.chat("/tbx config")
    t.eq(H.config():Find("toolbelt_base").text, "The Toolbelt is the buff bar; the parts set to In Toolbelt join it.")
  end)

  t.test("Toolbelt: a summary of what's in it, and what falls back to its own strip", function()
    H.boot()
    H.chat("/tbx config")
    local summary = function() return H.config():Find("hud_summary").text end
    t.ok(summary():find("The Toolbelt is off %(Show the Toolbelt%)"), summary())
    t.ok(summary():find("On their own strips: Consumables, Equipment"), summary())
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx vitals glue on")
    H.chat("/tbx gear glue on")
    t.ok(summary():find("Toolbelt: Health bars %+ Buffs %+ Equipment%."), summary())
    H.chat("/tbx buffs")                               -- buff bar off: glued gear falls back
    t.ok(summary():find("The Toolbelt is off, so Equipment uses its own strip%."), summary())
  end)

  t.test("Toolbelt: each bar Off, on its own strip or in the Toolbelt, from one page", function()
    H.boot()
    H.chat("/tbx config")
    local w = H.config()
    t.eq(w:Find("toolbelt_show").value, false)
    t.eq(w:Find("toolbelt_vitals").value, "Off")
    t.eq(w:Find("toolbelt_consumables").value, "Own strip")
    H.change("toolbox_config", "toolbelt_vitals", "In Toolbelt")
    t.eq(Toolbox.Vitals.IsShown(), true, "switched on")
    t.eq(Toolbox.Hud.IsGlued(), true, "and joined")
    t.eq(Toolbox.BuffBar.IsEnabled(), true, "which also shows the Toolbelt")
    t.eq(w:Find("toolbelt_show").value, true, "and its checkbox says so")
    t.ok(H.hud(), "one shared strip")
    H.change("toolbox_config", "toolbelt_consumables", "In Toolbelt")
    H.change("toolbox_config", "toolbelt_gear", "In Toolbelt")
    t.ok(w:Find("hud_summary").text:find("Toolbelt: Health bars %+ Buffs %+ Consumables %+ Equipment%."),
      w:Find("hud_summary").text)
    H.change("toolbox_config", "toolbelt_gear", "Own strip")
    t.eq(Toolbox.Gear.GetGlue(), false)
    t.eq(Toolbox.Gear.GetShow(), true)
    H.change("toolbox_config", "toolbelt_consumables", "Off")
    t.eq(Toolbox.Consumables.GetShow(), false)
    t.eq(Toolbox.Consumables.GetGlue(), true, "Off keeps where it goes, for next time")
    H.chat("/tbx vitals glue off")
    t.eq(w:Find("toolbelt_vitals").value, "Own strip", "follows the chat command")
    H.change("toolbox_config", "toolbelt_show", false)
    t.eq(Toolbox.BuffBar.IsEnabled(), false)
    t.eq(w:Find("show_buffs").value, false, "the same setting as Buffs: Show buff bar")
  end)

  -- the settings search -------------------------------------------------------------

  t.test("search: every control on every page can be found (the index is read from the pages)", function()
    H.boot()
    H.chat("/tbx config")
    local C = Toolbox.Config
    local made = H.S.constructed or 0
    local index = C.SearchIndex()
    t.eq(H.S.constructed or 0, made, "reading the pages makes no elements")
    local indexed = {}
    for _, e in ipairs(index) do
      indexed[e.id] = true
      for _, id in ipairs(e.also) do indexed[id] = true end
    end
    local header = { docs = true, category = true, search = true, search_results = true, search_go = true }
    local kinds = { Toggle = true, Slider = true, Dropdown = true, TextField = true, Button = true }
    for _, cat in ipairs(C.CATEGORIES) do
      H.call(function() C.ShowCategory(cat.key) end)
      local function scan(e)
        local arrow = e.kind == "Button" and type(e.text) == "string" and #e.text <= 1   -- the nudge arrows
        if e.id and kinds[e.kind] and not header[e.id] and not arrow then
          t.ok(indexed[e.id], "searchable: " .. cat.label .. " / " .. e.id)
        end
        for _, c in ipairs(e.children or {}) do scan(c) end
      end
      scan(H.configRaw())
    end
  end)

  t.test("search: as you type, matches list as Page > Section > Setting; picking one goes to it", function()
    H.boot()
    H.chat("/tbx config")
    t.eq(H.config():Find("search_results").value, Toolbox.Config.SEARCH_PROMPT)
    H.change("toolbox_config", "search", "icon size")
    local choices = H.config():Find("search_results").choices
    t.eq(choices[1], "Buffs > Buff bar > Icon size", table.concat(choices, " | "))
    t.ok(table.concat(choices, "|"):find("Skill activity > Icon size", 1, true), "every page")
    H.change("toolbox_config", "search_results", "Skill activity > Icon size")
    t.eq(Toolbox.Config.CurrentCategory(), "skills", "its page shown")
    local hit = H.configRaw():Find("skills_size")
    t.eq(hit.style.opacity, Toolbox.Config.SEARCH_DIM, "it blinks")
    t.eq(hit.style.borderWidth, nil, "no outline (it couldn't be undone safely)")
    H.advance(5, 0.25)
    t.eq(hit.style.opacity, 1, "for a moment, then as it was")
  end)

  t.test("search: picking another result while one blinks stops the first; never two at once", function()
    H.boot()
    H.chat("/tbx config")
    H.change("toolbox_config", "search", "icon size")
    H.change("toolbox_config", "search_results", "Buffs > Buff bar > Icon size")
    local first = H.configRaw():Find("buff_size")
    H.advance(0.25, 0.25)
    H.change("toolbox_config", "search_results", "Buffs > Buff block > Icon size")
    local second = H.configRaw():Find("buffblock_size")
    t.eq(first.style.opacity, 1, "the first back at once")
    t.ok(second.style.opacity < 1, "the second blinks")
    H.advance(5, 0.25)
    t.eq(first.style.opacity, 1)
    t.eq(second.style.opacity, 1, "both as they were")
    H.change("toolbox_config", "search_results", "Buffs > Buff bar > Icon size")
    H.change("toolbox_config", "category", "Combat")                 -- another page while it blinks
    H.advance(5, 0.25)
    H.change("toolbox_config", "search_results", "Buffs > Buff bar > Icon size")
    H.advance(5, 0.25)
    t.eq(H.configRaw():Find("buff_size").style.opacity, 1, "picked again: the same")
  end)

  t.test("search: the result's part of the page comes to the top (the UI can't scroll)", function()
    H.boot()
    H.chat("/tbx config")
    H.change("toolbox_config", "search", "icons per row")
    H.change("toolbox_config", "search_results", "Buffs > Buff block > Icons per row")
    local w = H.configRaw()
    t.eq(Toolbox.Config.CurrentCategory(), "buffs")
    t.eq(w:Find("show_buffs").visible, false, "the buff bar's settings above it: hidden")
    t.eq(w:Find("expire_alert").visible, false)
    t.ok(w:Find("show_buffblock").visible ~= false, "its section from its heading: shown")
    t.ok(w:Find("buffblock_width").visible ~= false)
    t.ok(w:Find("search_focus").visible ~= false, "a line saying so")
    t.ok(w:Find("buffblock_width").style.opacity < 1, "and it blinks")
    H.change("toolbox_config", "show_buffblock", true)
    H.change("toolbox_config", "buffblock_width", 7)
    t.eq(Toolbox.BuffBlock.GetWidth(), 7, "the controls work as ever")
    H.click("toolbox_config", "search_showall")
    t.ok(w:Find("show_buffs").visible ~= false, "Show the whole page: all of it")
    t.eq(w:Find("search_focus").visible, false, "and the line goes")
    H.change("toolbox_config", "search", "show buff bar")
    H.change("toolbox_config", "search_results", "Buffs > Buff bar > Show buff bar")
    t.eq(H.configRaw():Find("search_focus"), nil, "at the top already: nothing hidden, no line")
    t.ok(H.configRaw():Find("show_buffs").visible ~= false)
    H.change("toolbox_config", "category", "Combat")
    H.change("toolbox_config", "category", "Buffs")
    t.ok(H.configRaw():Find("show_buffs").visible ~= false, "picked from Settings: the whole page")
  end)

  t.test("search: synonyms, Enter goes to the first, nothing found, too many", function()
    H.boot()
    H.chat("/tbx config")
    H.change("toolbox_config", "search", "toolbar")
    t.ok(H.config():Find("search_results").choices[1]:find("^Toolbelt"), "toolbar finds the Toolbelt")
    H.submit("toolbox_config", "search", "leave out pet")
    t.eq(Toolbox.Config.CurrentCategory(), "toolbelt", "Enter: straight to the first")
    H.change("toolbox_config", "search", "zebra")
    t.eq(H.config():Find("search_results").choices[1], "No setting matches 'zebra'")
    H.click("toolbox_config", "search_go")
    t.eq(Toolbox.Config.CurrentCategory(), "toolbelt", "nothing to go to")
    H.change("toolbox_config", "search", "s")
    local choices = H.config():Find("search_results").choices
    t.eq(#choices, Toolbox.Config.SEARCH_MAX + 1, "the first ones and a line saying how many more")
    t.ok(choices[#choices]:find("more: add a word"), choices[#choices])
    H.change("toolbox_config", "search", "")
    t.eq(H.config():Find("search_results").choices[1], Toolbox.Config.SEARCH_PROMPT)
  end)
end
