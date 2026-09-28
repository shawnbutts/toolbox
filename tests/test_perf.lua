-- Budgets: how much Toolbox asks of the game each second, so it leaves room for other add-ons.
-- Counts UI calls (each one crosses into the game's UI) and garbage (collected on the heap every
-- add-on shares) over a minute with every window and strip open, idle and in combat. Measured
-- 2026-09-28 after the performance pass: idle ~4 UI calls/s and ~6 KB/s, combat ~28 and ~31 KB/s
-- (they were ~100 / 39 KB and ~127 / 74 KB). The limits leave headroom; a feature that trips one
-- should update only what changed and reuse its tables (see Toolbox.SetText etc. in core.lua).
local H = require("harness")

return function(t)
  local LIMITS = { idle = { calls = 20, kb = 15 }, combat = { calls = 60, kb = 60 } }

  local function everythingOpen()
    H.boot()
    for _, c in ipairs({ "/tbx xp", "/tbx xp hud", "/tbx xpdetailed", "/tbx daily", "/tbx dd", "/tbx buffs",
                         "/tbx vitals", "/tbx combat", "/tbx combat detail", "/tbx notify via hud" }) do
      H.chat(c)
    end
    H.addBuffs({ { name = "Light", remaining = 900, icon = 1 }, { name = "Ward", remaining = 300, icon = 2 },
                 { name = "Potion", remaining = 500000, icon = 3 },
                 { name = "Aura", remaining = -1, permanent = true } })
    H.advance(70)                                -- past start-up and the early notification polling
  end

  -- UI calls and KB allocated per second over `secs` seconds, `each` run before every second.
  local function measure(secs, each)
    local calls = 0
    local mt = getmetatable(H.S.windows.toolbox_compact)
    local saved = {}
    for _, m in ipairs({ "SetText", "SetStyle", "SetTooltip", "SetValue", "SetVisible", "SetUV", "SetTexture",
                         "SetSize" }) do
      saved[m] = mt[m]
      mt[m] = function(self, ...)
        calls = calls + 1
        return saved[m](self, ...)
      end
    end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for s = 1, secs do
      if each then each(s) end
      H.advance(1)
    end
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    for m, f in pairs(saved) do mt[m] = f end
    return calls / secs, kb / secs
  end

  t.test("idle with every window open stays within its budget", function()
    everythingOpen()
    local calls, kb = measure(60)
    t.ok(calls <= LIMITS.idle.calls, string.format("%.1f UI calls/s (limit %d)", calls, LIMITS.idle.calls))
    t.ok(kb <= LIMITS.idle.kb, string.format("%.1f KB/s of garbage (limit %d)", kb, LIMITS.idle.kb))
  end)

  t.test("combat with every window open stays within its budget", function()
    everythingOpen()
    H.setCombat(true)
    local calls, kb = measure(60, function()
      H.combat({
        { kind = "hit", fromYou = true, amount = 100, rune = "Thrust", runeId = 10, target = "Bear", targetKey = 5,
          damageType = "blade", time = ShroudTime },
        { kind = "hit", fromYou = true, amount = 40, rune = "Bladed Combat", runeId = 222, target = "Bear",
          targetKey = 5, damageType = "blade", time = ShroudTime },
        { kind = "hit", toYou = true, amount = 20, rune = "Bite", runeId = 9, source = "Bear", sourceKey = 5,
          damageType = "handToHand", time = ShroudTime },
        { kind = "heal", fromYou = true, amount = 50, overheal = 10, rune = "Heal", runeId = 7, time = ShroudTime },
        { kind = "dodge", toYou = true, source = "Bear", time = ShroudTime } })
      H.gain(500, 0)
    end)
    t.ok(calls <= LIMITS.combat.calls, string.format("%.1f UI calls/s (limit %d)", calls, LIMITS.combat.calls))
    t.ok(kb <= LIMITS.combat.kb, string.format("%.1f KB/s of garbage (limit %d)", kb, LIMITS.combat.kb))
  end)
end
