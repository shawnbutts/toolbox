-- Health & focus bars.
local H = require("harness")

return function(t)
  local V = function() return Toolbox.Vitals end
  local function withStats()
    H.S.stats = {
      { name = "CurrentHealth", label = "Current Health", value = 943 },
      { name = "Health", value = 942.23 },
      { name = "CurrentFocus", label = "Current Focus", value = 700 },
      { name = "Focus", value = 700 },
    }
  end

  t.test("format: fill and text; the max is never below the current value", function()
    H.boot()
    local fill, text = V().Format(943, 942.23)
    t.near(fill, 1)
    t.eq(text, "943 / 943")
    fill, text = V().Format(471.4, 942.23)
    t.near(fill, 471 / 942)
    t.eq(text, "471 / 942")
    fill, text = V().Format(500, nil)
    t.eq(fill, 1)
    t.eq(text, "500", "no max: just the current value")
    fill, text = V().Format(nil, 900)
    t.eq(fill, 0)
    t.eq(text, "--")
    fill, text = V().Format(10, -999)
    t.eq(text, "10", "the stat's failure sentinel isn't a max")
    t.eq(fill, 1)
  end)

  t.test("hidden by default; /tbx vitals shows it and it is remembered", function()
    H.boot()
    t.eq(H.vitals().visible, false)
    H.chat("/tbx vitals")
    t.eq(H.vitals().visible, true)
    H.reload()
    t.eq(H.vitals().visible, true)
  end)

  t.test("bars follow current health and focus against the Health / Focus stats", function()
    H.boot()
    withStats()
    H.chat("/tbx vitals")
    H.advance(1)
    t.eq(H.vitals():Find("health_text").text, "943 / 943")
    t.eq(H.vitals():Find("focus_text").text, "700 / 700")
    H.S.char.hp, H.S.char.focus = 300, 175
    H.advance(0.2, 0.2)
    t.eq(H.vitals():Find("health_text").text, "300 / 942")
    t.near(H.vitals():Find("health_bar").value, 300 / 942)
    t.near(H.vitals():Find("focus_bar").value, 0.25)
    t.eq(H.vitals():Find("health_bar").color, "@red")
    t.eq(H.vitals():Find("focus_bar").color, "@blue")
  end)

  t.test("a hidden max stat (reads 0) shows the current value only", function()
    H.boot()
    H.S.stats = { { name = "Health", value = 942, hidden = true } }
    H.chat("/tbx vitals")
    H.advance(1)
    t.eq(H.vitals():Find("health_text").text, "943")
    t.eq(H.vitals():Find("health_bar").value, 1)
  end)

  t.test("no UI churn while nothing changes", function()
    H.boot()
    withStats()
    H.chat("/tbx vitals")
    H.advance(1)
    local label = H.vitals():Find("health_text")
    local calls = 0
    local set = label.SetText
    label.SetText = function(self, v) calls = calls + 1; return set(self, v) end
    H.advance(5, 0.2)
    t.eq(calls, 0)
    H.S.char.hp = 900
    H.advance(0.2, 0.2)
    t.eq(calls, 1)
  end)

  t.test("the numbers sit right after the bar, left-aligned, both bars aligned", function()
    H.boot()
    H.chat("/tbx vitals")
    local m = V().Metrics()
    for _, key in ipairs({ "health", "focus" }) do
      local text, bar = H.vitals():Find(key .. "_text"), H.vitals():Find(key .. "_bar")
      t.eq(text.style.textAlign, "left")
      t.eq(H.vitals():Find(key .. "_wrap").style.marginLeft, m.gap, "the gap sits on the number's wrapper")
      t.ok(m.gap <= 4, "small gap at 100%: " .. m.gap)
      t.eq(text.style.width, m.textW, "same number box on both rows")
      t.eq(bar.style.width, m.barW)
    end
  end)

  t.test("size scales text, bars, gap and the strip together", function()
    H.boot()
    H.chat("/tbx vitals")
    local small = V().Metrics()
    H.chat("/tbx vitals size 200")
    local big = V().Metrics()
    t.eq(V().GetScale(), 200)
    t.eq(big.font, 24)
    t.eq(big.barW, 2 * small.barW)
    t.ok(big.barH > small.barH and big.line > small.line and big.gap > small.gap and big.textW > small.textW)
    t.eq(H.vitals():Find("health_text").style.fontSize, 24, "applied live")
    t.eq(H.vitals():Find("health_bar").style.width, big.barW)
    t.eq(H.vitals().width, big.frameW)
    t.eq(H.vitals().height, big.frameH)
    H.clearLogs()
    H.chat("/tbx vitals size 20")
    t.ok(H.logged("from 75 to 250"))
    H.chat("/tbx config")
    H.change("toolbox_config", "vitals_scale", 80)
    t.eq(V().GetScale(), 80)
    t.eq(H.config():Find("vitals_scale_value").text, "80")
    H.reload()
    t.eq(V().GetScale(), 80, "remembered")
    t.eq(H.vitals():Find("focus_text").style.fontSize, 10)
  end)

  t.test("the global text size doesn't change the bars (they have their own size)", function()
    H.boot()
    H.chat("/tbx vitals")
    H.chat("/tbx font 20")
    t.eq(H.vitals():Find("focus_text").style.fontSize, 12)
  end)

  t.test("bar length setting and position", function()
    H.boot()
    H.chat("/tbx vitals")
    H.chat("/tbx config")
    H.change("toolbox_config", "vitals_width", 300)
    t.eq(V().GetWidth(), 300)
    t.eq(H.vitals():Find("health_bar").style.width, 300)
    t.eq(H.vitals().width, V().Metrics().frameW, "frame follows the length")
    t.no(V().SetWidth(5))
    t.no(V().SetWidth(19), "below the minimum")
    t.ok(V().SetWidth(20), "the minimum")
    t.eq(H.vitals():Find("health_bar").style.width, 20)
    t.ok(V().SetWidth(300))
    H.click("toolbox_config", "vitals_right")
    t.eq(H.vitals().x, V().HOME[1] + 10)
    H.chat("/tbx vitals move 700 20")
    t.eq(H.vitals().x, 700)
    t.eq(H.config():Find("vitals_pos").text, "700, 20")
    H.advance(1)
    H.reload()
    t.eq(H.vitals().x, 700, "remembered")
    t.eq(V().GetWidth(), 300)
    H.chat("/tbx config")                       -- a reload closes the settings window
    H.click("toolbox_config", "vitals_reset")
    t.eq(H.vitals().y, V().HOME[2])
  end)

  t.test("settings checkbox and help", function()
    H.boot()
    H.chat("/tbx config")
    H.change("toolbox_config", "show_vitals", true)
    t.eq(H.vitals().visible, true)
    H.chat("/tbx vitals")
    t.eq(H.config():Find("show_vitals").value, false, "follows the command")
    H.clearLogs()
    H.chat("/tbx commands")
    t.ok(H.logged("/toolbox vitals"))
  end)

  t.test("when the per-frame value isn't a number, the CurrentHealth / CurrentFocus stats are used", function()
    H.boot()
    withStats()
    H.S.char.hp, H.S.char.focus = nil, nil
    H.chat("/tbx vitals")
    H.advance(1)
    t.eq(H.vitals():Find("health_text").text, "943 / 943")
    t.eq(H.vitals():Find("focus_text").text, "700 / 700")
    t.near(H.vitals():Find("health_bar").value, 1)
  end)

  t.test("/tbx vitals debug shows each source", function()
    H.boot()
    withStats()
    H.S.char.hp = nil
    H.advance(0.2, 0.2)
    H.clearLogs()
    H.chat("/tbx vitals debug")
    t.ok(H.logged('^Health: ShroudPlayerCurrentHealth = nil nil; stat CurrentHealth = 943; stat Health = 942.23; '
      .. 'using stat %-> "943 / 943", fill 1.00$'), H.logs()[1])
    t.ok(H.logged('^Focus: ShroudPlayerCurrentFocus = 700; .*using global'), H.logs()[2])
    t.ok(H.logged("^Layout: asked bar %d+x11, row 15 high, 5 px between rows; laid out: health bar "), H.lastLog())
  end)

  -- numbers / bars / background ---------------------------------------------

  t.test("bars can be hidden: numbers take the bars' colours and the strip narrows", function()
    H.boot()
    H.chat("/tbx vitals")
    local wide = H.vitals().width
    H.chat("/tbx vitals bars off")
    t.eq(H.vitals():Find("health_bar").visible, false)
    t.eq(H.vitals():Find("health_text").style.color, "@red")
    t.eq(H.vitals():Find("focus_text").style.color, "@blue")
    t.ok(H.vitals().width < wide, "narrower without bars")
    H.chat("/tbx vitals bars on")
    t.eq(H.vitals():Find("health_bar").visible, true)
    t.eq(H.vitals():Find("health_text").style.color, "@text")
  end)

  t.test("numbers can be hidden; not both at once", function()
    H.boot()
    H.chat("/tbx vitals")
    H.chat("/tbx vitals text off")
    t.eq(H.vitals():Find("focus_wrap").visible, false)
    t.eq(H.vitals().width, V().Metrics().frameW)
    H.clearLogs()
    H.chat("/tbx vitals bars off")
    t.ok(H.logged("can't both be off"))
    t.eq(V().GetShowBars(), true)
    H.chat("/tbx vitals text on")
    H.chat("/tbx vitals bars off")
    H.clearLogs()
    H.chat("/tbx vitals text off")                     -- the other order
    t.ok(H.logged("can't both be off"))
    t.eq(V().GetShowText(), true)
    H.chat("/tbx vitals bars on")
    H.chat("/tbx vitals text off")
    H.reload()
    t.eq(V().GetShowText(), false, "remembered")
    t.eq(H.vitals():Find("focus_wrap").visible, false)
  end)

  t.test("dark / light backgrounds use the theme's inset / card classes", function()
    H.boot()
    H.chat("/tbx vitals")
    local label = function() return H.vitals():Find("health_text") end
    t.no(label():Classes().inset or label():Classes().card, "none by default")
    H.chat("/tbx vitals bg dark")
    t.ok(label():Classes().inset)
    t.ok(label():Classes().text, "keeps the text class")
    t.ok(label().style.paddingLeft > 0, "room around the text")
    local wrap = function() return H.vitals():Find("health_wrap") end
    t.eq(wrap().style.backgroundColor, "#00000000", "Dark uses the class, not a panel colour")
    H.chat("/tbx vitals bg LIGHT")
    t.no(label():Classes().inset, "the Dark class is removed")
    t.eq(wrap().style.backgroundColor, "@text", "a panel in the theme's light text colour")
    t.eq(label().style.color, Toolbox.Vitals.DARK_TEXT, "dark numbers on it")
    H.reload()
    t.eq(wrap().style.backgroundColor, "@text", "remembered and built with it")
    H.chat("/tbx vitals bg dark")
    t.eq(wrap().style.backgroundColor, "#00000000", "the panel is cleared again")
    t.ok(label():Classes().inset)
    H.chat("/tbx vitals bg none")
    t.no(label():Classes().inset)
    t.eq(label().style.paddingLeft, 0)
    H.clearLogs()
    H.chat("/tbx vitals bg purple")
    t.ok(H.logged("Backgrounds: None, Dark, Light"))
  end)

  t.test("settings: bars / numbers checkboxes and the background dropdown", function()
    H.boot()
    H.chat("/tbx vitals")
    H.chat("/tbx config")
    H.change("toolbox_config", "vitals_bg", "Dark")
    t.eq(V().GetBackground(), "Dark")
    H.change("toolbox_config", "vitals_show_bars", false)
    t.eq(V().GetShowBars(), false)
    H.change("toolbox_config", "vitals_show_text", false)
    t.eq(V().GetShowText(), true, "refused")
    t.eq(H.config():Find("vitals_show_text").value, true, "checkbox put back")
    H.chat("/tbx vitals bg light")
    t.eq(H.config():Find("vitals_bg").value, "Light", "dropdown follows the command")
  end)

  t.test("contents start past the drag grip, and the strip is wide enough for it", function()
    H.boot()
    H.chat("/tbx vitals")
    H.chat("/tbx vitals bars off")
    local inner = H.vitals().children[1]
    t.eq(inner.style.paddingLeft, Toolbox.Window.GRIP)
    local m = V().Metrics()
    t.eq(m.frameW, Toolbox.Window.GRIP + m.textW + 2 * m.pad + 8)
    t.eq(H.frame().children[1].style.paddingLeft, Toolbox.Window.GRIP, "the buff bar too")
  end)

  -- flash when low -------------------------------------------------------------

  -- The health bar's colour over `seconds`, sampled every tick.
  local function colours(seconds)
    local seen = {}
    for _ = 1, math.floor(seconds / 0.2 + 0.5) do
      H.advance(0.2, 0.2)
      seen[H.vitals():Find("health_bar").color or "?"] = true
    end
    return seen
  end

  t.test("below the threshold the bar and number swap colours; above, they don't", function()
    H.boot()
    withStats()
    H.chat("/tbx vitals")
    H.S.char.hp = 150                                  -- 16% of 942
    local seen = colours(2)
    t.ok(seen["@red"] and seen[Toolbox.Vitals.FLASH_COLOR], "alternates")
    local texts = {}
    for _ = 1, 10 do
      H.advance(0.2, 0.2)
      texts[H.vitals():Find("health_text").style.color] = true
    end
    t.ok(texts["@text"] and texts["@red"], "the number flashes too")
    H.S.char.hp = 900
    H.advance(1, 0.2)
    seen = colours(2)
    t.ok(seen["@red"] and not seen[Toolbox.Vitals.FLASH_COLOR], "steady when healthy again")
    t.eq(H.vitals():Find("focus_bar").color == Toolbox.Vitals.FLASH_COLOR, false, "focus (full) never flashed")
  end)

  t.test("flash threshold and off switch", function()
    H.boot()
    withStats()
    H.chat("/tbx vitals")
    H.S.char.hp = 300                                  -- 32%
    t.no(colours(2)[Toolbox.Vitals.FLASH_COLOR], "not below 20%")
    H.chat("/tbx vitals flash 40")
    t.ok(colours(2)[Toolbox.Vitals.FLASH_COLOR], "below 40%")
    H.chat("/tbx vitals flash off")
    H.advance(0.4, 0.2)
    t.no(colours(2)[Toolbox.Vitals.FLASH_COLOR], "off")
    H.clearLogs()
    H.chat("/tbx vitals flash 99")
    t.ok(H.logged("flash <1%-95>"))
    H.chat("/tbx config")
    H.change("toolbox_config", "vitals_flash_below", 25)
    t.eq(V().GetFlashBelow(), 25)
    H.change("toolbox_config", "vitals_flash", true)
    t.eq(V().GetFlash(), true)
    H.reload()
    t.eq(V().GetFlashBelow(), 25, "remembered")
  end)

  t.test("flash colours suit each display: numbers only, and the Light panel", function()
    H.boot()
    local bar = Toolbox.Vitals.BARS[1]
    H.chat("/tbx vitals bars off")
    local _, normal = V().Colors(bar, false)
    local _, flash = V().Colors(bar, true)
    t.eq(normal, "@red"); t.eq(flash, Toolbox.Vitals.FLASH_COLOR)
    H.chat("/tbx vitals bars on")
    H.chat("/tbx vitals bg light")
    _, normal = V().Colors(bar, false)
    _, flash = V().Colors(bar, true)
    t.eq(normal, Toolbox.Vitals.DARK_TEXT); t.eq(flash, "@red", "readable on the light panel")
  end)

  t.test("test flash: both bars flash for a few seconds at full health, even with flash off", function()
    H.boot()
    withStats()
    H.chat("/tbx vitals")
    H.chat("/tbx vitals flash off")
    H.chat("/tbx config")
    H.clearLogs()
    H.click("toolbox_config", "vitals_flash_test")
    t.ok(H.logged("Flashing the bars for 5 s"))
    local healthSeen, focusSeen = {}, {}
    for _ = 1, 20 do
      H.advance(0.2, 0.2)
      healthSeen[H.vitals():Find("health_bar").color] = true
      focusSeen[H.vitals():Find("focus_bar").color] = true
    end
    t.ok(healthSeen[Toolbox.Vitals.FLASH_COLOR] and healthSeen["@red"], "health flashed")
    t.ok(focusSeen[Toolbox.Vitals.FLASH_COLOR] and focusSeen["@blue"], "focus flashed")
    H.advance(2, 0.2)
    local after = {}
    for _ = 1, 10 do
      H.advance(0.2, 0.2)
      after[H.vitals():Find("health_bar").color] = true
    end
    t.no(after[Toolbox.Vitals.FLASH_COLOR], "stops after the preview")
    t.eq(V().GetFlash(), false, "the setting is untouched")
  end)

  t.test("test flash from chat, and a hint when the strip is hidden", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx vitals flash test")
    t.ok(H.logged("Show the health & focus bars first"))
    H.chat("/tbx vitals")
    H.clearLogs()
    H.chat("/tbx vitals flash test")
    t.ok(H.logged("Flashing the bars"))
  end)

  -- Vigor (API 20) ---------------------------------------------------------------

  local function vigorRow() return H.vitals():Find("vigor_row") end

  t.test("vigor: a gold bar with the percentage, bonuses in the tooltip", function()
    H.boot()
    withStats()
    H.chat("/tbx vitals")
    H.setVigor{ vigor = 64.5, percent = 64, healthRegenBonus = 12, focusRegenBonus = 8, critBonus = 3 }
    H.advance(0.2, 0.2)
    t.ok(vigorRow().visible ~= false)
    t.eq(H.vitals():Find("vigor_text").text, "64%")
    t.near(H.vitals():Find("vigor_bar").value, 0.645)
    t.eq(H.vitals():Find("vigor_bar").color, "@gold")
    t.eq(H.vitals():Find("vigor_bar").tooltip,
      "Vigor 64%\n+12% health regen, +8% focus regen, +3% critical chance")
    H.setVigor{ vigor = 100, rested = true }
    H.advance(0.2, 0.2)
    t.eq(H.vitals():Find("vigor_text").text, "100%")
    t.ok(H.vitals():Find("vigor_text").tooltip:find("(rested)", 1, true))
  end)

  t.test("vigor: the row and the strip's height follow whether there is a reading", function()
    H.boot()
    withStats()
    H.chat("/tbx vitals")
    H.advance(1)
    local two = H.vitals().height
    t.eq(vigorRow().visible, false, "no Vigor (below its level): no row")
    H.setVigor{ vigor = 50 }
    H.advance(0.2, 0.2)
    t.ok(vigorRow().visible ~= false)
    t.ok(H.vitals().height > two, "a third row")
    H.setVigor(nil)
    H.advance(0.2, 0.2)
    t.eq(vigorRow().visible, false)
    t.eq(H.vitals().height, two)
  end)

  t.test("vigor: read at start (the callback fires only on a change) and re-read now and then", function()
    H.boot()
    H.S.vigor = { vigor = 30, max = 100, percent = 30, rested = false, healthRegenBonus = 0, focusRegenBonus = 0,
                  critBonus = 0 }
    H.chat("/tbx vitals")
    H.reload()
    H.advance(0.2, 0.2)
    t.eq(H.vitals():Find("vigor_text").text, "30%", "read in ShroudOnStart")
    H.S.vigor.vigor, H.S.vigor.percent = 40, 40      -- changed without a callback
    H.advance(Toolbox.Vitals.VIGOR_POLL)
    t.eq(H.vitals():Find("vigor_text").text, "40%")
  end)

  t.test("vigor: never flashes, and the setting hides it", function()
    H.boot()
    withStats()
    H.chat("/tbx vitals")
    H.setVigor{ vigor = 2 }
    H.advance(2)
    t.eq(H.vitals():Find("vigor_bar").color, "@gold", "low Vigor isn't an emergency")
    H.chat("/tbx vitals vigor off")
    t.eq(H.saved("vitals").vigor, false)
    H.advance(0.2, 0.2)
    t.eq(vigorRow().visible, false)
    H.chat("/tbx config")
    H.change("toolbox_config", "vitals_vigor", true)
    H.advance(0.2, 0.2)
    t.ok(vigorRow().visible ~= false)
  end)

  t.test("vigor: an older client without it", function()
    H.boot()
    ShroudGetVigor = nil
    H.chat("/tbx vitals")
    H.advance(Toolbox.Vitals.VIGOR_POLL)
    t.eq(vigorRow().visible, false)
    H.clearLogs()
    H.chat("/tbx vitals vigor")
    t.ok(H.logged("needs Lua API 20"))
    H.clearLogs()
    H.chat("/tbx vitals debug")
    t.ok(H.logged("^Vigor: ShroudGetVigor missing"))
  end)
end
