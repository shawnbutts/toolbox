-- The aggro list (Toolbox.Aggro, in vitals.lua): API 54's ShroudGetTargetAggro as a Toolbelt line or its own strip.
local H = require("harness")

return function(t)
  local AG = function() return Toolbox.Aggro end
  local function boot()
    H.apiVersion = 54
    H.boot()
  end
  local function done() H.apiVersion = nil end

  -- a skeleton on phil, you second
  local function onPhil()
    return { target = "phil", entries = {
      { name = "phil", value = 1000, share = 1, unreachable = false, you = false },
      { name = "Tester", value = 640, share = 0.64, unreachable = false, you = true },
      { name = "Ann[PVP]", value = 200, share = 0.2, unreachable = true, you = false },
    } }
  end
  local function onYou()
    return { target = "Tester", entries = {
      { name = "Tester", value = 1000, share = 1, unreachable = false, you = true },
      { name = "phil", value = 820, share = 0.82, unreachable = false, you = false },
    } }
  end
  local function target(aggro)
    return H.setTarget{ id = 7, name = "Skeleton", hp = 500, maxHp = 500, focus = 0, maxFocus = 0, aggro = aggro }
  end
  local function line()
    local f = H.hud() or H.frame()
    local row = f and f:Find("aggro")
    if not row or row.visible == false then return nil end
    return f:Find("aggro_line").text, f:Find("aggro_bar").value, f:Find("aggro_bar").tooltip
  end

  t.test("model: the read, whether it says anything, the line and the list", function()
    boot()
    local a = { n = 0, entries = {} }
    t.ok(AG().Read(onPhil(), a, "tester"))
    t.eq(a.n, 3)
    t.eq(a.entries[3].name, "Ann", "names plain")
    t.ok(a.entries[3].unreachable)
    t.ok(AG().Worth(a))
    local text, fill, color = AG().Line(a)
    t.eq(text, "On phil; you 2nd, 64%")
    t.eq(fill, 0.64)
    t.eq(color, AG().YOURS_COLOR)
    t.ok(AG().Read(onYou(), a, "tester"))
    t.eq(a.n, 2, "the reused list shrinks")
    text, fill = AG().Line(a)
    t.eq(text, "On you; next phil 82%")
    t.eq(fill, 0.82)
    t.ok(AG().Tooltip(a, "Skeleton"):find("1. Tester (you) 100%", 1, true))
    -- alone: nothing to say
    t.ok(AG().Read({ entries = { { name = "Tester", value = 5, share = 1, you = true } } }, a, "tester"))
    t.no(AG().Worth(a), "only you")
    t.no(AG().Read(nil, a, "tester"), "no list yet")
    -- the game doesn't say who: the top; you named but not flagged
    t.ok(AG().Read({ entries = { { name = "Tester[AFK]", share = 1 }, { name = "phil", share = 0.5 } } }, a, "tester"))
    local who, you = AG().Holder(a)
    t.eq(who, "Tester")
    t.ok(you)
    local O = AG().Ordinal
    t.eq(O(1) .. O(2) .. O(3) .. O(4) .. O(11) .. O(22), "1st2nd3rd4th11th22nd")
    t.eq(AG().Change(false, true), "pulled")
    t.eq(AG().Change(true, false), "lost")
    t.eq(AG().Change(nil, true), nil, "the first read of a target")
    done()
  end)

  t.test("an older client: no calls, the setting greyed out, the command says why", function()
    H.boot()
    t.no(AG().Has())
    H.chat("/tbx aggro on")
    t.ok(H.logged("Lua API 54"))
    t.no(AG().GetShow())
    H.chat("/tbx config")
    local c = H.config()
    t.ok(c:Find("toolbelt_aggro").enabled == false)
  end)

  t.test("in the Toolbelt: the last row, shown in a group fight, hidden alone or without a list", function()
    boot()
    H.chat("/tbx aggro on")
    t.ok(AG().GetShow())
    t.ok(AG().GetGlue(), "in the Toolbelt by default")
    H.chat("/tbx aggro toolbelt on")
    t.ok(AG().Glued(), "the Toolbelt switched on with it")
    H.advance(5)                      -- the strips' rebuild past the creation cap
    t.eq(line(), nil, "no target: hidden")
    target(nil)
    H.advance(1)
    t.eq(line(), nil, "no list yet")
    target(onPhil())
    H.advance(1)
    local text, fill, tip = line()
    t.eq(text, "On phil; you 2nd, 64%")
    t.eq(fill, 0.64)
    t.ok(tip:find("Attacking phil", 1, true))
    t.ok(tip:find("Ann 20%, can't reach", 1, true))
    target({ entries = { { name = "Tester", value = 5, share = 1, you = true } } })
    H.advance(1)
    t.eq(line(), nil, "alone: hidden")
    H.setTarget(nil)
    H.advance(1)
    t.eq(line(), nil)
    t.no(H.S.frames.toolbox_aggro, "no strip of its own")
    done()
  end)

  t.test("its own strip: the creature, a row a name, who it's on", function()
    boot()
    H.chat("/tbx aggro on")
    H.chat("/tbx aggro toolbelt off")
    t.no(AG().Glued())
    target(onPhil())
    H.advance(1)
    local f = H.S.frames.toolbox_aggro
    t.ok(f, "the meter's strip")
    t.ok(f.visible ~= false)
    t.eq(f:Find("ag_head").text, "Skeleton: on phil")
    t.eq(f:Find("ag_name_1").text, "phil")
    t.eq(f:Find("ag_name_1").style.color, AG().ON_COLOR, "who it's on")
    t.eq(f:Find("ag_name_2").text, "Tester (you)")
    t.eq(f:Find("ag_pct_2").text, "64%")
    t.eq(f:Find("ag_row_3").style.opacity, AG().UNREACHABLE, "can't reach: dimmed")
    t.ok(f:Find("ag_row_4").visible == false)
    t.eq(line(), nil, "not in the Toolbelt")
    H.setTarget(nil)
    H.advance(1)
    t.ok(f.visible == false, "hidden with no list")
    done()
  end)

  t.test("alerts: pulled (on by default) and lost (off), once a turn, not on a new target's first read", function()
    boot()
    H.chat("/tbx notify aggro via chat")
    H.chat("/tbx aggro on")
    target(onYou())
    H.advance(1)
    t.no(H.logged("pulled aggro"), "the first read of a target")
    H.S.target.aggro = onPhil()
    H.advance(4)
    t.no(H.logged("Aggro lost"), "lost is off by default")
    H.S.target.aggro = onYou()
    H.advance(1)
    t.ok(H.logged("You pulled aggro: Skeleton is on you."))
    H.chat("/tbx aggro alert lost on")
    t.ok(H.logged("lost on"))
    H.S.target.aggro = onPhil()
    H.advance(1)
    t.ok(H.logged("Aggro lost: Skeleton is on phil."))
    H.chat("/tbx aggro alert pulled off")
    H.S.target.aggro = onYou()
    H.advance(5)
    local n = 0
    for _, l in ipairs(H.logs()) do if l:find("You pulled aggro", 1, true) then n = n + 1 end end
    t.eq(n, 1, "pulled off: not again")
    done()
  end)

  t.test("the Party Toolbelt marks who your target is attacking, with the aggro part off too", function()
    H.apiVersion = 55
    H.boot()
    H.chat("/tbx party on")
    H.setParty{ { name = "Tester", hp = 900, maxHp = 1000 }, { name = "phil", hp = 500, maxHp = 1000 },
                { name = "Ann[PVP]", hp = 800, maxHp = 1000 } }
    H.advance(1)
    local f = H.S.frames.toolbox_party
    local function names()
      local out = {}
      for i = 1, 3 do
        local r = f:Find("pt_row_" .. i)
        if r and r.visible ~= false then out[#out + 1] = f:Find("pt_name_" .. i).text end
      end
      return table.concat(out, ",")
    end
    t.eq(names(), "phil,Ann")
    t.no(AG().GetShow(), "the aggro part off")
    target(onPhil())
    H.advance(1)
    t.eq(names(), "> phil,Ann", "phil's row marked")
    H.S.target.aggro = { target = "Ann", entries = { { name = "Ann", share = 1 }, { name = "phil", share = 0.5 } } }
    H.advance(1)
    t.eq(names(), "phil,> Ann", "the mark follows")
    H.chat("/tbx party aggro off")
    H.advance(1)
    t.eq(names(), "phil,Ann", "switched off")
    t.eq(H.saved("party").aggro, false)
    H.chat("/tbx party aggro on")
    H.setTarget(nil)
    H.advance(1)
    t.eq(names(), "phil,Ann", "no target: no mark")
    done()
  end)

  -- Review 81: the Party Toolbelt's 0.5 s poll asked the game for the list twice a second; it changes once a second.
  t.test("the game's list read once a second: the party marker alone, and with the meter; fresh for a new target",
      function()
    H.apiVersion = 55
    H.boot()
    H.chat("/tbx party on")
    H.setParty{ { name = "Tester", hp = 900, maxHp = 1000 }, { name = "phil", hp = 500, maxHp = 1000 } }
    target(onPhil())
    H.advance(2)
    local function calls(seconds)
      local from = H.S.aggroCalls or 0
      H.advance(seconds)
      return (H.S.aggroCalls or 0) - from
    end
    local n = calls(4)
    t.ok(n >= 3 and n <= 4, "the marker alone: " .. n .. " in 4 s")
    H.chat("/tbx aggro on")
    H.chat("/tbx aggro toolbelt off")
    H.advance(2)
    n = calls(4)
    t.ok(n >= 3 and n <= 4, "the marker and the meter together: " .. n .. " in 4 s")
    local from = H.S.aggroCalls
    H.setTarget{ id = 8, name = "Wolf", hp = 50, maxHp = 50, focus = 0, maxFocus = 0, aggro = onYou() }
    t.eq(H.S.aggroCalls, from + 1, "a new target is read at once")
    t.eq(AG().AttackingNow(), "tester", "the new target's list, not the last one's")
    done()
  end)

  t.test("settings: the place dropdown, the alerts and the shade; the meter's position row", function()
    boot()
    H.chat("/tbx config")
    local c = H.config()
    H.change("toolbox_config", "toolbelt_aggro", "Own strip")
    t.ok(AG().GetShow())
    t.no(AG().Glued())
    H.change("toolbox_config", "toolbelt_aggro", "In Toolbelt")
    t.ok(AG().Glued())
    H.change("toolbox_config", "ag_lost", true)
    t.ok(AG().GetLost())
    t.eq(H.saved("aggro").lost, true)
    H.change("toolbox_config", "toolbelt_aggro", "Off")
    t.no(AG().GetShow())
    t.ok(c:Find("ag_pulled").enabled == false, "greyed out while off")
    t.ok(c:Find("aggro_pos"), "a Position row on HUD layout")
    done()
  end)
end
