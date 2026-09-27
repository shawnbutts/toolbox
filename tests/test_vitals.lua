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

  t.test("width setting, text size, and position", function()
    H.boot()
    H.chat("/tbx vitals")
    H.chat("/tbx config")
    H.change("toolbox_config", "vitals_width", 300)
    t.eq(V().GetWidth(), 300)
    t.eq(H.vitals().width, 308, "frame follows the width")
    t.no(V().SetWidth(5))
    H.chat("/tbx font 16")
    t.eq(H.vitals():Find("focus_text").style.fontSize, 16)
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
    H.chat("/tbx help")
    t.ok(H.logged("/toolbox vitals"))
  end)
end
