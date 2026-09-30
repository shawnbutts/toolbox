-- Stress: a long-played character with every list at its maximum, full bars and heavy combat. The
-- idle / combat budgets in test_perf.lua use light fixtures; these check that a veteran's saved
-- data and a busy screen don't cost dramatically more (review, 2026-09-29). They also count
-- elements created and container Add/Clear calls.
local H = require("harness")

return function(t)
  -- Measured 2026-09-29 (Lua 5.4 / LuaJIT), after the fixes these tests prompted (the gear notification
  -- read the equipment every check; BB.Track made a closure per buff per tick; Today Detailed redrew
  -- 250 names every second):
  --   veteran idle   2 calls/s,  3.3 / 4.6 KB/s,  0 made/s
  --   full bars      0 calls/s,  8.3 / 18.2 KB/s, 0 made/s (2026-09-30: the game runs the sweeps; before,
  --                  16 calls/s and 8 made/s replacing sweep pictures)
  --   heavy combat  67 calls/s, 61 / 75 KB/s (incl. the test's own 50 event tables a second), 0 made/s
  -- STRESS_PRINT=1 lua tests/run.lua stress prints them. Limits leave headroom.
  local LIMITS = {
    veteran = { calls = 10, kb = 12, made = 1 },
    bars = { calls = 10, kb = 30, made = 1 },
    combat = { calls = 90, kb = 120, made = 2 },
  }

  local CHAR = "character:Tester"
  local DAY = "local:2026-09-27"                 -- the harness's default date

  -- UI calls, KB of garbage and elements created per second over `secs` seconds (`each` before
  -- every second).
  local function measure(secs, each)
    local calls = 0
    local mt = getmetatable(H.S.windows.toolbox_config or H.S.windows.toolbox_compact or H.S.frames.toolbox_buffs)
    local saved = {}
    for _, m in ipairs({ "SetText", "SetStyle", "SetTooltip", "SetValue", "SetVisible", "SetUV", "SetTexture",
                         "SetSize", "SetColor", "Add", "Clear" }) do
      saved[m] = mt[m]
      mt[m] = function(self, ...)
        calls = calls + 1
        return saved[m](self, ...)
      end
    end
    local made0 = H.S.constructed or 0
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
    return calls / secs, kb / secs, ((H.S.constructed or 0) - made0) / secs
  end

  local function within(what, limit, calls, kb, made)
    if os.getenv("STRESS_PRINT") then
      print(string.format("  %s: %.1f calls/s, %.1f KB/s, %.1f made/s", what, calls, kb, made))
    end
    t.ok(calls <= limit.calls, string.format("%s: %.1f UI calls/s (limit %d)", what, calls, limit.calls))
    -- garbage only under standard Lua: LuaJIT's count includes its compiler's own allocations and
    -- varied 17-38 KB/s run to run for the same scenario (2026-09-29)
    if not rawget(_G, "jit") then
      t.ok(kb <= limit.kb, string.format("%s: %.1f KB/s of garbage (limit %d)", what, kb, limit.kb))
    end
    t.ok(made <= limit.made, string.format("%s: %.1f elements created/s (limit %d)", what, made, limit.made))
  end

  local function noErrors(what)
    for _, l in ipairs(H.logs()) do
      t.no(l:find("Couldn't") or l:find("error") or l:find("too fast"), what .. ": " .. l)
    end
  end

  -- Saved data of a character that has played a lot: every list at its cap. `corrupt` mixes in
  -- wrong types and out-of-range values alongside.
  local function veteranDisk(corrupt)
    local items = {}
    for i = 1, 250 do items[string.format("Loot Item %03d", i)] = i end   -- Daily.MAX_KINDS
    local history = {}
    for i = 1, 20 do
      history[i] = { when = string.format("%02d:%02d", 10 + i % 10, i), title = "Notice " .. i,
        text = "A long notice text that goes on for a while so that it needs its tooltip " .. i .. ". "
          .. string.rep("More words. ", 10) }
    end
    local parts, extra = {}, {}
    for i = 1, 20 do
      parts[i] = "GroupPart" .. i
      extra[i] = "ExtraName" .. i
    end
    local prices = {}
    for i = 1, 250 do
      prices[string.format("loot item %03d", i)] = { avg = i * 3, sold = i, last = "2026-09-20", day = DAY }
    end
    local disk = {
      [CHAR] = {
        daily = { v = 1, key = DAY, gold = 123456, kills = 900, a = 5000000, p = 2000000, items = items, dropped = 3,
                  last = {} },
        daily_detail = { open = false, values = true },
        notify_history = { v = 1, list = history },
        buffbar = { show = true, group = parts },
        consumables = { show = true, extra = extra },
        combat = { show = true, stats = { "MagicResistance", "CombatHealthRegen", "CombatFocusRegen", "Dodge",
                                          "Parry", "Block", "Strength", "Dexterity" } },
      },
      account = { prices = { v = 1, items = prices } },
    }
    if corrupt then
      local c = disk[CHAR]
      c.daily.items["Bad Count"] = -5                       -- invalid: the whole day is discarded
      c.notify_history.list[5] = "not a table"
      c.notify_history.list[25] = { title = "past the cap", text = "x" }
      c.buffbar.group[21] = 42
      c.buffbar.size = 9999
      c.consumables.extra[3] = false
      c.consumables.x = "left"
      c.combat.stats[9] = { "table" }
      c.gear = { threshold = 7, show = "yes" }
      c.vitals = { width = -3, scale = "big", bg = 12 }
      disk.account.prices.items["weird"] = { avg = "cheap", day = DAY }
      c.buff_durations = { v = 2, durations = { Light = "long", Heal = -1 } }
      c.session = { v = 1, broken = true }
    end
    return disk
  end

  local function openEverything()
    for _, c in ipairs({ "/tbx xp", "/tbx xpdetailed", "/tbx daily", "/tbx dd", "/tbx buffs", "/tbx vitals",
                         "/tbx combat", "/tbx combat detail", "/tbx notify via hud" }) do
      H.chat(c)
    end
  end

  t.test("a veteran character (every saved list at its cap) logs in cleanly and idles within budget", function()
    H.boot(veteranDisk(false))
    H.advance(70)
    noErrors("login")
    t.eq(#(function() local n = {} for k in pairs(Toolbox.Daily.day.items) do n[#n + 1] = k end return n end)(),
      250, "the day's 250 item names kept")
    openEverything()
    H.advance(10)
    noErrors("opening everything")
    t.eq(#H.detailRows(), Toolbox.DailyDetail.MAX_ROWS, "Today Detailed shows its maximum rows")
    t.eq(#(H.S.requests or {}), 0, "cached prices: no lookups")
    within("veteran idle", LIMITS.veteran, measure(60))
  end)

  -- The harness's stand-ins for the buff getters build tables and strings on every call, which the
  -- game doesn't do on the Lua side; for a measurement of Toolbox's own garbage, swap in ones that
  -- return the same values without allocating (the list must not change while they're in place).
  local function quietBuffGetters()
    local names, tips, left, n = {}, {}, {}, ShroudGetBuffCount()
    for i = 0, n - 1 do
      names[i], tips[i], left[i] = ShroudGetBuffName(i), ShroudGetBuffTooltip(i), ShroudGetBuffTimeRemaining(i)
    end
    local t0 = ShroudTime
    ShroudGetBuffCount = function() return n end
    ShroudGetBuffName = function(i) return names[i] or "Invalid" end
    ShroudGetBuffTooltip = function(i) return tips[i] or "" end
    ShroudGetBuffTimeRemaining = function(i)
      local l = left[i]
      if not l then return -1 end
      if l <= 0 then return l end                         -- permanent
      return math.max(0, l - (ShroudTime - t0))
    end
  end

  t.test("full bars (30 buffs and debuffs, consumables, 12 worn items to repair) within budget", function()
    H.boot()
    H.S.durationMode = "remaining"
    H.advance(Toolbox.BuffBar.SETTLE + 1)
    H.chat("/tbx buffs")
    H.chat("/tbx vitals")
    H.chat("/tbx notify via hud")
    H.chat("/tbx buffs group after off")               -- all 20 on the bar, none grouped
    -- long enough that none runs out during the measurement
    local list = {}
    for i = 1, 20 do list[#list + 1] = { name = "Buff" .. i, remaining = 90 + i * 60, icon = i } end
    for i = 1, 10 do list[#list + 1] = { name = "Bane" .. i, remaining = 80 + i * 10, icon = 40 + i, debuff = true } end
    for i = 1, 4 do
      list[#list + 1] = { name = "RuneFood_Dish" .. i, remaining = 600 * i, total = 29088, icon = 60 + i }
    end
    list[#list + 1] = { name = "BlessingOfStamina", remaining = 300000, total = 604800, icon = 70 }
    H.addBuffs(list)
    local gear = {}
    for i = 1, 12 do gear[i] = { name = "Worn Piece " .. i, durability = i, maxDurability = 100 } end
    H.setGear(gear)
    H.advance(12)
    noErrors("full bars")
    t.eq(#H.slots("buffs"), 20)
    t.eq(#H.slots("debuffs"), 10)
    t.eq(#H.gearSlots(), 12)
    quietBuffGetters()
    local calls, kb, made = measure(60)
    within("full bars", LIMITS.bars, calls, kb, made)
    t.ok(made < 0.5, string.format("sweeps make no elements (the game runs them): %.1f/s", made))
  end)

  t.test("heavy combat (50 lines a second, 6 targets, a full fight history) within budget", function()
    H.boot()
    for _, c in ipairs({ "/tbx combat", "/tbx combat detail", "/tbx buffs", "/tbx vitals", "/tbx xp", "/tbx daily" }) do
      H.chat(c)
    end
    H.advance(70)
    -- ten finished fights first (the session keeps C.HISTORY)
    for f = 1, Toolbox.Combat.HISTORY + 2 do
      H.setCombat(true)
      H.combat({ { kind = "hit", fromYou = true, amount = 100 + f, rune = "Thrust", runeId = 10, target = "Wolf",
                   targetKey = f, damageType = "blade", time = ShroudTime },
                 { kind = "death", fromYou = true, target = "Wolf", targetKey = f, time = ShroudTime } })
      H.advance(2)
      H.setCombat(false)
      H.advance(14)
    end
    H.setCombat(true)
    local types = { "blade", "fire", "earth", "poison", "bludgeon", "air" }
    local calls, kb, made = measure(60, function()
      local batch = {}
      for i = 1, 50 do
        local k = i % 6 + 1
        if i % 5 == 0 then
          batch[i] = { kind = "hit", toYou = true, amount = 30, rune = "Bite", runeId = 900 + k, source = "Wolf " .. k,
                       sourceKey = 100 + k, damageType = types[k], time = ShroudTime }
        elseif i % 7 == 0 then
          batch[i] = { kind = "heal", fromYou = true, amount = 80, overheal = 20, rune = "Heal", runeId = 7,
                       time = ShroudTime }
        else
          batch[i] = { kind = i % 3 == 0 and "critical" or "hit", fromYou = true, amount = 50 + i,
                       rune = "Skill " .. (i % 10), runeId = 200 + i % 10, target = "Wolf " .. k, targetKey = 100 + k,
                       damageType = types[k],
                       time = ShroudTime }
        end
      end
      H.combat(batch)
      H.gain(300, 0)
    end)
    noErrors("heavy combat")
    within("heavy combat", LIMITS.combat, calls, kb, made)
  end)

  t.test("maximum saved data with corrupted entries: loads, keeps what is valid, drops the rest", function()
    H.boot(veteranDisk(true))
    H.advance(70)
    noErrors("login with corrupted data")
    t.eq(next(Toolbox.Daily.day.items), nil, "an invalid day is started afresh")
    t.eq(#Toolbox.BuffBar.GroupParts(), 20, "grouping names kept, the number dropped")
    t.eq(Toolbox.BuffBar.GetSize(), Toolbox.BuffBar.SIZE_DEFAULT, "an impossible icon size falls back")
    local extra = Toolbox.Consumables.Extra()
    t.eq(#extra, 19, "extra names kept, the bad entry skipped")
    t.eq(Toolbox.Gear.Threshold(), 20, "an unknown threshold falls back")
    t.eq(Toolbox.Vitals.GetWidth(), Toolbox.Vitals.WIDTH_DEFAULT)
    openEverything()
    H.advance(5)
    noErrors("opening everything")
    local rows = 0
    for i = 1, Toolbox.Notify.Hud.KEEP do
      if H.nhudRow(i) then rows = rows + 1 end
    end
    t.ok(rows >= 1 and rows <= Toolbox.Notify.Hud.KEEP, "notification history rows: " .. rows)
  end)
end
