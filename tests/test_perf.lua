-- Budgets: how much Toolbox asks of the game each second, so it leaves room for other add-ons.
-- Counts UI calls (each one crosses into the game's UI) and garbage (collected on the heap every
-- add-on shares) over a minute with every window and strip open, idle and in combat. Measured
-- 2026-09-28 after the performance pass: idle ~4 UI calls/s and ~6 KB/s, combat ~28 and ~31 KB/s
-- (they were ~100 / 39 KB and ~127 / 74 KB); 2026-10-14, the 1.8.0 pass (Lua 5.5): idle 4.0 and 3.6 KB/s, combat
-- 27.5 and 22.6 KB/s, an hour into a fight 14.1 KB/s (63 before: the XP session stored with every gain). The
-- limits leave headroom; a feature that trips one should update only what changed and reuse its tables (see
-- Toolbox.SetText etc. in core.lua).
local H = require("harness")

return function(t)
  local LIMITS = { idle = { calls = 20, kb = 15 }, combat = { calls = 60, kb = 60 }, long = { kb = 30 } }

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
    -- garbage only under standard Lua, as in test_stress: LuaJIT's count includes its compiler's own
    -- allocations (idle read 15.2 against 15 once in four runs, 2026-09-30)
    if not rawget(_G, "jit") then
      t.ok(kb <= LIMITS.idle.kb, string.format("%.1f KB/s of garbage (limit %d)", kb, LIMITS.idle.kb))
    end
  end)

  t.test("settings opened and closed again costs nothing while hidden", function()
    everythingOpen()
    local base = measure(30)
    H.chat("/tbx config")                        -- built (as the first-run welcome does), then closed
    H.advance(2)
    H.closeWindow("toolbox_config")
    H.advance(2)                                 -- strips shown only while settings is open settle
    local after = measure(30)
    t.ok(after - base <= 0.2, string.format("%.1f UI calls/s more than never opened (%.1f vs %.1f)",
      after - base, after, base))
  end)

  t.test("the XP totals are read once a second, not twice", function()
    everythingOpen()
    local reads, get = 0, ShroudGetTotalAdventurerExperience   -- read only through Toolbox.ReadTotals
    ShroudGetTotalAdventurerExperience = function(...)
      reads = reads + 1
      return get(...)
    end
    H.advance(10)
    ShroudGetTotalAdventurerExperience = get
    t.ok(reads <= 10, reads .. " reads in 10 s")
  end)

  t.test("an hour into a fight, XP gains store the session only at the flush; garbage stays flat", function()
    H.boot()
    local function fight(sec)
      if sec % 3 == 0 then
        H.gain(700, 50)
        H.combat({ { kind = "death", fromYou = true, target = "Bear", time = ShroudTime } })
      end
    end
    for sec = 1, 3600 do                         -- an hour of samples in the session
      fight(sec)
      H.advance(1)
    end
    local stores, set = 0, ShroudSetSavedVar
    ShroudSetSavedVar = function(k, ...)
      if k == "session" then stores = stores + 1 end
      return set(k, ...)
    end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for sec = 1, 60 do
      fight(sec)
      H.advance(1)
    end
    local kb = (collectgarbage("count") - before) / 60
    collectgarbage("restart")
    ShroudSetSavedVar = set
    t.ok(stores <= 2, stores .. " stores of the session in a minute (one a flush)")
    if not rawget(_G, "jit") then       -- standard Lua only (see the idle test)
      t.ok(kb <= LIMITS.long.kb, string.format("%.1f KB/s of garbage an hour in (limit %d; 63 before 1.8.0)", kb,
        LIMITS.long.kb))
    end
  end)

  t.test("the flush's work is spread: no tick stores both the session and the day; the write still comes", function()
    H.boot()
    local at, set, flushes, flush = {}, ShroudSetSavedVar, 0, ShroudFlushSavedVars
    ShroudSetSavedVar = function(k, ...)
      if k == "session" or k == "daily" then
        at[ShroudTime] = at[ShroudTime] or {}
        at[ShroudTime][k] = true
      end
      return set(k, ...)
    end
    ShroudFlushSavedVars = function(...)
      flushes = flushes + 1
      return flush(...)
    end
    for sec = 1, 90 do
      H.gain(100, 0)
      if sec % 3 == 0 then H.items({ { "Wyvern Meat", 2 } }) end
      H.advance(1)
    end
    ShroudSetSavedVar, ShroudFlushSavedVars = set, flush
    local both = 0
    for _, keys in pairs(at) do if keys.session and keys.daily then both = both + 1 end end
    t.eq(both, 0, "the session and the day in different ticks")
    t.ok(flushes >= 2, flushes .. " flushes in 90 s")
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
    if not rawget(_G, "jit") then       -- standard Lua only (see the idle test)
      t.ok(kb <= LIMITS.combat.kb, string.format("%.1f KB/s of garbage (limit %d)", kb, LIMITS.combat.kb))
    end
  end)
end
