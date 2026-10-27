-- The Party Toolbelt (Toolbox.Party, in vitals.lua): the party's health and focus on a strip of its own.
local H = require("harness")

return function(t)
  local PT = function() return Toolbox.Party end
  -- the party manager is for API 55 clients (owner, 2026-10-27)
  local function boot()
    H.apiVersion = 55
    H.boot()
  end
  local function done() H.apiVersion = nil end

  -- you, then three others; Bob is lowest, Cy elsewhere
  local function party()
    return {
      { name = "Tester", hp = 943, maxHp = 943, focus = 700, maxFocus = 700, leader = true },
      { name = "Ann[PVP]", hp = 800, maxHp = 1000, focus = 300, maxFocus = 400 },
      { name = "Bob", hp = 250, maxHp = 1000, focus = 100, maxFocus = 400 },
      { name = "Cy", inScene = false, scene = "Ardoris" },
    }
  end

  local function frame() return H.S.frames.toolbox_party end
  local function rows()
    local out = {}
    local f = frame()
    if not f then return out end
    for i = 1, Toolbox.Party.MAX do
      local r = f:Find("pt_row_" .. i)
      if r and r.visible ~= false then
        out[#out + 1] = { name = f:Find("pt_name_" .. i).text, text = f:Find("pt_text_" .. i).text,
                          hp = f:Find("pt_hp_" .. i).value, color = f:Find("pt_name_" .. i).style.color,
                          opacity = r.style.opacity, tip = f:Find("pt_hp_" .. i).tooltip }
      end
    end
    return out
  end
  local function names()
    local out = {}
    for _, r in ipairs(rows()) do out[#out + 1] = r.name end
    return table.concat(out, ",")
  end

  t.test("model: the order (yourself left out, lowest first), the lowest, the text after the bars", function()
    boot()
    local list = {
      { slot = 0, plain = "Me", inScene = true, hp = 100, maxHp = 100 },
      { slot = 1, plain = "A", inScene = true, hp = 80, maxHp = 100 },
      { slot = 2, plain = "B", inScene = false, online = true },
      { slot = 3, plain = "C", inScene = true, hp = 0, maxHp = 100, dead = true },
      { slot = 4, plain = "D", inScene = true, hp = 30, maxHp = 100 },
    }
    local out = {}
    t.eq(PT().Order(list, 5, false, "party", out), 4)
    t.eq(out[1].plain .. out[2].plain .. out[3].plain .. out[4].plain, "ABCD", "party order, no you")
    t.eq(PT().Order(list, 5, true, "health", out), 5)
    local s = ""
    for _, m in ipairs(out) do s = s .. m.plain end
    t.eq(s, "DAMeBC", "the living here lowest first, then the rest in party order")
    t.eq(PT().Lowest(list, 5).plain, "D", "the dead aren't the lowest")
    t.eq(PT().StateText(list[2]), "80%")
    t.eq(PT().StateText(list[3]), "away")
    t.eq(PT().StateText(list[4]), "dead")
    t.eq(PT().StateText({ slot = 5, inScene = false, online = false }), "offline")
    t.eq(PT().Lowest({ list[1] }, 1), nil, "nobody hurt: nobody flagged")
    done()
  end)

  t.test("off by default; on, a strip only while in a party", function()
    boot()
    t.eq(PT().GetShow(), false)
    H.setParty(party())
    t.eq(frame(), nil, "off: no strip")
    H.setParty(nil)
    H.chat("/tbx party on")
    t.eq(frame(), nil, "not in a party: no strip")
    t.ok(H.logged("it shows once you're in a party"))
    H.setParty(party())
    t.ok(frame() and frame():IsVisible(), "a party: the strip")
    t.eq(names(), "Ann,Bob,Cy", "yourself left out, tags dropped, party order")
    local r = rows()
    t.eq(r[1].text, "80%")
    t.eq(r[2].color, "@red", "the lowest's name is red")
    t.eq(r[1].color, "@text")
    t.eq(r[3].text, "away")
    t.eq(r[3].opacity, PT().DIM, "elsewhere: dimmed")
    t.eq(r[1].opacity, 1)
    t.ok(r[2].tip:find("Health 250 / 1,000", 1, true), r[2].tip)
    t.ok(r[3].tip:find("In Ardoris", 1, true), r[3].tip)
    H.setParty(nil)
    t.eq(frame(), nil, "left the party: the strip goes")
    done()
  end)

  t.test("the bars follow the polls; health order; yourself included", function()
    boot()
    H.chat("/tbx party on")
    local p = party()
    H.setParty(p)
    p[2].hp = 100                       -- Ann drops, no party event: the poll sees it
    H.advance(1)
    t.eq(rows()[1].hp, 0.1)
    t.eq(rows()[1].color, "@red", "Ann is the lowest now")
    t.eq(rows()[2].color, "@text")
    H.chat("/tbx party sort health")
    t.eq(names(), "Ann,Bob,Cy")
    p[3].hp = 50
    H.advance(1)
    t.eq(names(), "Bob,Ann,Cy", "re-sorted at the next poll")
    H.chat("/tbx party self on")
    t.eq(names(), "Bob,Ann,Tester,Cy")
    H.reload()
    t.eq(PT().GetSort(), "health", "kept over a reload")
    t.eq(PT().GetSelf(), true)
    t.eq(names(), "Bob,Ann,Tester,Cy")
    done()
  end)

  t.test("ShroudGetParty tells offline, the scene, dead and the leader", function()
    boot()
    H.chat("/tbx party on")
    H.chat("/tbx party self on")
    local p = party()
    p[3].dead, p[3].hp = true, 0
    p[5] = { name = "Dee", online = false }
    H.setParty(p)
    local r = rows()
    t.eq(names(), "Tester,Ann,Bob,Cy,Dee")
    t.ok(r[1].tip:find("(party leader)", 1, true), r[1].tip)
    t.eq(r[3].text, "dead")
    t.eq(r[3].color, PT().DEAD_COLOR)
    t.eq(r[2].color, "@red", "the lowest of the living")
    t.ok(r[4].tip:find("In Ardoris", 1, true), r[4].tip)
    t.eq(r[5].text, "offline")
    t.ok(H.S.partyReads > 0)
    done()
  end)

  t.test("reach (API 46): a member in your scene farther than it is dimmed less than one elsewhere", function()
    boot()
    H.chat("/tbx party on")
    local p = party()
    p[2].distance = 35
    H.setParty(p)
    local r = rows()
    t.eq(PT().GetReach(), 30, "30 m by default")
    t.eq(r[1].opacity, PT().FAR)
    t.ok(r[1].tip:find("Out of reach (30 m)", 1, true), r[1].tip)
    t.eq(r[2].opacity, 1)
    t.eq(r[3].opacity, PT().DIM)
    H.chat("/tbx party reach 40")
    t.eq(rows()[1].opacity, 1, "within 40 m")
    H.chat("/tbx party reach off")
    t.eq(PT().GetReach(), 0)
    p[2].distance = 100
    H.advance(1)
    t.eq(rows()[1].opacity, 1, "off: not asked")
    done()
  end)

  t.test("a client before API 55: nothing, and Settings says why", function()
    H.apiVersion = 54
    H.boot()
    H.chat("/tbx party on")
    t.ok(H.logged("Lua API 55"))
    t.eq(PT().GetShow(), false)
    H.setParty(party())
    t.eq(frame(), nil)
    H.chat("/tbx config")
    t.eq(H.config():Find("pt_show").enabled, false, "greyed out")
    t.eq(H.config():Find("pt_show").tooltip, PT().NEEDS)
    done()
  end)

  t.test("more members: the rows grow four at a time, to sixteen", function()
    boot()
    H.chat("/tbx party on")
    local p = party()
    H.setParty(p)
    t.eq(frame():Find("pt_row_5"), nil, "four rows for three members")
    for i = 5, 20 do p[i] = { name = "M" .. i, hp = 500, maxHp = 1000 } end
    H.setParty(p)
    t.ok(frame():Find("pt_row_16"), "rebuilt with sixteen")
    t.eq(frame():Find("pt_row_17"), nil, "at most PT.MAX")
    t.eq(#rows(), 16)
    for i = 7, 20 do p[i] = nil end
    H.setParty(p)
    t.eq(#rows(), 5, "fewer: rows hidden, not rebuilt")
    t.ok(frame():Find("pt_row_16"))
    done()
  end)

  t.test("only during combat", function()
    boot()
    H.chat("/tbx party on")
    H.chat("/tbx party combat on")
    H.setParty(party())
    t.eq(frame():IsVisible(), false, "out of combat: hidden")
    H.setCombat(true)
    H.advance(1)
    t.eq(frame():IsVisible(), true)
    H.setCombat(false)
    H.advance(60)
    t.eq(frame():IsVisible(), false)
    done()
  end)

  t.test("settings: the Party page; its hint while open with no party; a reset clears it", function()
    boot()
    H.chat("/tbx config")
    local cfg = "toolbox_config"
    t.eq(Toolbox.Config.PageOf("pt_show"), "party")
    H.change(cfg, "pt_show", true)
    t.eq(PT().GetShow(), true)
    t.ok(frame() and frame():IsVisible(), "settings open: shown to place it")
    t.eq(names(), PT().HINT)
    H.change(cfg, "pt_sort", PT().SORT_LABELS.health)
    t.eq(PT().GetSort(), "health")
    H.change(cfg, "pt_width", 200)
    t.eq(PT().GetWidth(), 200)
    t.eq(frame():Find("pt_hp_1").style.width, 200, "rebuilt at the new length")
    H.change(cfg, "pt_numbers", false)
    t.eq(frame():Find("pt_text_1").visible, false)
    H.chat("/tbx config")
    H.advance(1)
    t.eq(frame(), nil, "closed, no party: no strip at the next poll")
    t.eq(H.saved("party").sort, "health")
    done()
  end)

  -- a member's effects as ShroudGetPartyMemberBuffs gives them (RuneEffects, API 47's FromYou)
  local function rune(name, debuff, left, total, icon, fromYou, others)
    local effects = { { Description = "", Value = 0, CurrentDuration = left, TotalDuration = total, TotalTick = 0,
                        FromYou = fromYou == true, SourceKey = fromYou and 1 or 9 } }
    if others then
      effects[2] = { Description = "", Value = 0, CurrentDuration = others, TotalDuration = total, TotalTick = 0,
                     FromYou = false, SourceKey = 9 }
    end
    return { RuneName = name, RuneId = icon, IsDebuff = debuff, IconId = icon, Category = "Other",
             StackCount = #effects, Effects = effects, FromYou = fromYou == true, FromYouCount = fromYou and 1 or 0 }
  end
  local function fx(i)
    local out = {}
    for j = 1, PT().ICONS_MAX do
      local r = frame():Find("pt_fx_" .. i .. "_" .. j)
      if r and r.visible ~= false then
        out[#out + 1] = (frame():Find("pt_fxi_" .. i .. "_" .. j).tooltip:gsub(" %(yours%)$", ""))
      end
    end
    return table.concat(out, ",")
  end

  t.test("CollectEffects: debuffs first, then watched buffs, soonest first; only yours with mine; capped", function()
    boot()
    local runes = { rune("Regeneration", false, 20, 30, 5, false, 25), rune("Poison", true, 8, 10, 6),
                    rune("Bleed", true, 3, 10, 7), rune("Strength", false, 100, 600, 8),
                    rune("Shield", false, 5, 30, 9) }
    local out = {}
    t.eq(PT().CollectEffects(runes, out, true, { "regen", "SHIELD" }, false, 6), 4)
    t.eq(out[1].name .. "," .. out[2].name .. "," .. out[3].name .. "," .. out[4].name,
      "Bleed,Poison,Shield,Regeneration")
    t.eq(out[4].left, 25, "the longest copy")
    t.eq(PT().CollectEffects(runes, out, true, { "regen", "shield" }, true, 6), 2, "mine: nobody's are yours")
    runes[1] = rune("Regeneration", false, 12, 30, 5, true, 25)
    t.eq(PT().CollectEffects(runes, out, false, { "regen" }, true, 6), 1)
    t.eq(out[1].left, 12, "your own copy's time")
    t.eq(PT().CollectEffects(runes, out, true, {}, false, 1), 1, "capped")
    t.eq(out[1].name, "Bleed")
    done()
  end)

  t.test("effects on the rows: debuffs outlined, watched buffs, a wedge; read in turn; settings", function()
    boot()
    H.chat("/tbx party on")
    local p = party()
    p[2].buffs = { rune("Poison", true, 8, 10, 6), rune("Regeneration", false, 20, 30, 5, true) }
    p[3].buffs = { rune("Regeneration", false, 20, 30, 5) }
    p[4].buffs = { rune("Bleed", true, 8, 10, 7) }      -- elsewhere: the game gives none; nothing shown
    H.setParty(p)
    H.advance(1)
    t.eq(fx(1), "Poison", "only debuffs until a buff is watched")
    t.eq(frame():Find("pt_fx_1_1").style.borderWidth, 2, "a debuff is outlined")
    t.eq(fx(3), "")
    H.chat("/tbx party watch add regen")
    t.ok(H.logged('Watching "regen"'))
    H.advance(2)
    t.eq(fx(1), "Poison,Regeneration")
    t.eq(fx(2), "Regeneration")
    local covered = frame():Find("pt_fx_1_1").children[2]:SweepNow()
    t.ok(covered and covered > 0, "the wedge: " .. tostring(covered))
    H.chat("/tbx party mine on")
    H.advance(2)
    t.eq(fx(2), "", "mine: Bob's Regeneration isn't yours")
    t.eq(fx(1), "Poison,Regeneration")
    H.chat("/tbx party debuffs off")
    H.advance(2)
    t.eq(fx(1), "Regeneration")
    H.chat("/tbx config")
    H.change("toolbox_config", "pt_icons", 0)
    t.eq(frame():Find("pt_fx_1_1"), nil, "no effects: no icons built")
    H.change("toolbox_config", "pt_icons", 2)
    H.change("toolbox_config", "pt_icon_size", 30)
    t.eq(frame():Find("pt_fx_1_1").style.width, 30)
    t.eq(frame():Find("pt_fx_1_3"), nil)
    H.reload()
    t.eq(PT().GetWatch()[1], "regen", "kept")
    t.eq(PT().GetMine(), true)
    t.eq(PT().GetIcons(), 2)
    done()
  end)

  t.test("effects: a full party's reads are spread over the polls", function()
    boot()
    H.chat("/tbx party on")
    local p = party()
    for i = 5, 13 do p[i] = { name = "M" .. i, hp = 500, maxHp = 1000, buffs = { rune("Poison", true, 8, 10, 6) } } end
    local calls = 0
    H.setParty(p)
    local real = ShroudGetPartyMemberBuffs
    ShroudGetPartyMemberBuffs = function(x)
      calls = calls + 1
      return real(x)
    end
    Toolbox.Party.Poll()
    t.ok(calls <= PT().BUFF_READS, "at most " .. PT().BUFF_READS .. " a poll: " .. calls)
    H.advance(3)
    t.eq(fx(12), "Poison", "everyone read within a few seconds")
    ShroudGetPartyMemberBuffs = real
    done()
  end)

  -- Its share of the add-on's elements (2,000, the game counting more than the harness) and on-screen text: a full
  -- party (PT.MAX) with every effect slot filled and long names, measured alone (test_stress has the rest at its
  -- worst).
  t.test("budget: sixteen members with six effects each", function()
    boot()
    local text, live = H.S.text, H.S.live
    H.chat("/tbx party on")
    H.chat("/tbx party watch add Regeneration")
    Toolbox.Party.SetIcons(PT().ICONS_MAX)
    local members = { { name = "Tester", hp = 900, maxHp = 1000 } }
    for i = 2, PT().MAX + 1 do
      local buffs = {}
      for k = 1, 8 do buffs[k] = rune("A Long Debuff Name Number " .. k, k < 8, 20, 30, k) end
      buffs[8].RuneName = "Regeneration"
      members[i] = { name = "A Long Party Member Name " .. i, hp = 500 + i, maxHp = 1000, focus = 300, maxFocus = 400,
                     buffs = buffs }
    end
    H.setParty(members)
    H.advance(8)
    local chars, els = H.S.text - text, H.S.live - live
    if os.getenv("STRESS_PRINT") then print(string.format("  party of 16: %d characters, %d elements", chars, els)) end
    t.eq(#rows(), PT().MAX)
    t.eq(fx(PT().MAX), "A Long Debuff Name Number 1,A Long Debuff Name Number 2,A Long Debuff Name Number 3,"
      .. "A Long Debuff Name Number 4,A Long Debuff Name Number 5,A Long Debuff Name Number 6")
    t.ok(els <= 420, "at most 420 elements: " .. els)
    t.ok(chars <= 4200, "at most 4,200 characters of text: " .. chars)
    done()
  end)

  t.test("Changes: joins, leaves, scenes (not while quiet), offline only for a friend or guild member", function()
    boot()
    local function m(slot, plain, online, inScene, scene)
      return { slot = slot, plain = plain, online = online, inScene = inScene, scene = scene }
    end
    local friends = { Ann = true }
    local isFriend = function(name) return friends[name] == true end
    local prev = { Me = { online = true, inScene = true }, Ann = { online = true, inScene = true },
                   Bob = { online = true, inScene = true }, Cy = { online = true, inScene = true } }
    local list = { m(0, "Me", true, true), m(1, "Ann", false, false), m(2, "Bob", false, false),
                   m(3, "Cy", true, false, "Ardoris"), m(4, "Dee", true, true) }
    local lines = PT().Changes(prev, list, 5, false, isFriend)
    t.eq(table.concat(lines, " | "), "Ann went offline. | Cy left this scene for Ardoris. | Dee joined the party.",
      "Bob isn't a friend: his going offline isn't told")
    t.eq(#PT().Changes(prev, list, 5, true, isFriend), 2, "quiet: no scene changes")
    t.eq(PT().Changes(prev, { m(0, "Me", true, true) }, 1, false, isFriend)[3], "Cy left the party.")
    t.eq(PT().Changes(prev, {}, 0, false, isFriend)[1], "You're no longer in a party.")
    t.eq(PT().Changes({}, list, 5, false, isFriend)[1], "You're in a party with Ann, Bob, Cy, Dee.")
    t.eq(#PT().Changes(nil, list, 5, false, isFriend), 0, "no baseline: nothing")
    done()
  end)

  t.test("comings and goings in chat, the strip on or off; a scene change of yours tells nothing", function()
    boot()
    H.advance(30)
    local p = party()
    H.setParty(p)
    t.ok(H.logged("You're in a party with Ann, Bob, Cy."), "the strip off: the source alone")
    p[5] = { name = "Dee[AFK]", hp = 100, maxHp = 100 }
    H.setParty(p)
    t.ok(H.logged("Dee joined the party."))
    p[2].inScene, p[2].scene = false, "Brittany"
    H.setParty(p)
    t.ok(H.logged("Ann left this scene for Brittany."))
    H.callback("ShroudOnSceneLoaded", "Ardoris")
    p[2].inScene, p[3].inScene = true, false
    H.setParty(p)
    t.ok(not H.logged("Bob left this scene"), "your own scene change: quiet")
    H.advance(10)
    H.chat("/tbx party on")
    p[3].inScene = true
    H.setParty(p)
    t.ok(H.logged("Bob is here."), "after the quiet, with the strip on")
    H.S.friends = { { name = "Bob", online = true } }
    p[3].online, p[2].online = false, false
    H.setParty(p)
    t.ok(H.logged("Bob went offline."))
    t.ok(not H.logged("Ann went offline."), "not a friend")
    p[5] = nil
    H.setParty(p)
    t.ok(H.logged("Dee left the party."))
    H.setParty(nil)
    t.ok(H.logged("You're no longer in a party."))
    H.chat("/tbx notify party off")
    local before = #H.logs()
    H.setParty(party())
    for i = before + 1, #H.logs() do t.ok(not H.logs()[i]:find("in a party", 1, true), "off: " .. H.logs()[i]) end
    done()
  end)

  t.test("comings and goings: a start in a party tells nothing for those already there", function()
    boot()
    H.setParty(party())
    H.advance(30)
    H.reload()
    H.advance(30)
    local before = #H.logs()
    H.setParty(party())
    for i = before + 1, #H.logs() do t.ok(not H.logs()[i]:find("joined", 1, true), H.logs()[i]) end
    done()
  end)

  t.test("alerts: a member under the health level (once, the bar flashing), a named debuff landing", function()
    boot()
    H.advance(30)
    H.chat("/tbx notify party_alerts via chat")
    H.chat("/tbx party on")
    H.chat("/tbx party alert 40")
    t.ok(H.logged("Party alert below 40%% health"))
    H.chat("/tbx party alert add poison")
    local p = party()
    p[2].buffs = { rune("Deadly Poison", true, 8, 10, 6) }      -- there at the first read: not told
    H.setParty(p)
    H.advance(2)
    t.ok(H.logged("Bob is at 25%% health."), "Bob is under 40%")
    t.no(H.logged("Ann: Deadly Poison"), "there at Ann's first read")
    local colors = {}
    for _ = 1, 4 do
      H.advance(0.5, 0.5)
      colors[frame():Find("pt_hp_2").color or "@red"] = true
    end
    t.ok(colors[PT().FLASH_COLOR] and colors["@red"], "Bob's health bar flashes")
    H.clearLogs()
    p[3].hp = 300
    H.advance(2)
    t.no(H.logged("Bob is at"), "told once while under it")
    p[3].hp, p[2].buffs = 900, {}
    H.advance(2)
    p[3].hp = 100
    p[2].buffs = { rune("Deadly Poison", true, 8, 10, 6) }
    H.advance(4)
    t.ok(H.logged("Bob is at 10%% health."), "again after recovering")
    t.ok(H.logged("Ann: Deadly Poison."), "a poison landing")
    H.chat("/tbx party alert off")
    t.eq(PT().GetAlertBelow(), 0)
    H.chat("/tbx party alert 3")
    t.ok(H.logged("from 5 to 90"))
    done()
  end)

  t.test("combat model: the party's damage, healing and damage taken by name; the last hits at a death", function()
    boot()
    local C = Toolbox.Combat
    local stats = C.NewFight(0)
    local members = { tester = "Tester", ann = "Ann", bob = "Bob" }
    local function add(e) return C.AddParty(stats, e, e.amount or 0, members, "tester", e.time or 0) end
    t.ok(add({ kind = "hit", party = true, source = "Ann[PVP]", target = "Wolf", amount = 100 }))
    t.ok(add({ kind = "critical", fromYou = true, source = "Tester", target = "Wolf", amount = 50 }))
    t.ok(add({ kind = "heal", party = true, source = "Ann", target = "Bob", amount = 30 }))
    for k = 1, 7 do
      add({ kind = "hit", party = true, source = "Wolf", target = "Bob", amount = 10 * k, rune = "Bite", time = k })
    end
    t.no(add({ kind = "hit", party = true, source = "Wolf", target = "Stranger", amount = 5 }), "not a member")
    t.no(add({ kind = "dodge", party = true, source = "Wolf", target = "Bob" }))
    local list = C.PartyRows(stats)
    t.eq(list[1].name .. list[2].name .. list[3].name, "AnnTesterBob", "by damage done")
    t.eq(list[1].heal, 30)
    t.eq(list[3].taken, 280)
    t.eq(#list[3].hits, C.PARTY_LAST)
    C.PartyDeath(stats, "bob", "Bob", 8)
    t.eq(list[3].deaths, 1)
    t.eq(C.DeathText(list[3]), "Wolf 70 (Bite), 1.0 s before; Wolf 60 (Bite), 2.0 s before; Wolf 50 (Bite), 3.0 s"
      .. " before; Wolf 40 (Bite), 4.0 s before; Wolf 30 (Bite), 5.0 s before")
    t.eq(#list[3].hits, 0, "the next death's hits start over")
    done()
  end)

  t.test("Combat Detailed: a Party section from API 55, its rows and a death's last hits", function()
    boot()
    local p = party()
    H.setParty(p)
    H.chat("/tbx combat detail")
    H.setCombat(true)
    local now = ShroudTime
    H.combat({ { kind = "hit", party = true, source = "Ann", target = "Wolf", amount = 300, time = now },
               { kind = "hit", fromYou = true, source = "Tester", target = "Wolf", amount = 100, time = now },
               { kind = "heal", party = true, source = "Ann", target = "Bob", amount = 40, time = now },
               { kind = "hit", party = true, source = "Wolf", target = "Bob", amount = 90, rune = "Bite",
                 time = now } })
    p[3].dead, p[3].hp = true, 0
    H.setParty(p)
    H.advance(2)
    local w = H.S.windows.toolbox_combat_detail
    t.eq(w:Find("cd_party").visible, true)
    local shown = {}
    for _, r in ipairs(w:Find("cd_party").children[2].children) do
      if r.visible ~= false then shown[#shown + 1] = r.children[1].text .. "=" .. r.children[3].text end
    end
    t.eq(table.concat(shown, ","), "Ann=300 / 40,Tester=100 / 0,Bob=0 / 0")
    local bob = w:Find("cd_party").children[2].children[3].children[1].tooltip
    t.ok(bob:find("90 taken", 1, true) and bob:find("Died once; the last hits: Wolf 90 (Bite)", 1, true), bob)
    done()
  end)

  t.test("Combat Detailed: no Party section before API 55", function()
    H.apiVersion = 54
    H.boot()
    H.chat("/tbx combat detail")
    H.advance(1)
    local section = H.S.windows.toolbox_combat_detail:Find("cd_party")
    t.eq(section.visible, false)
    t.eq(#section.children, 0, "not built: its text would count")
    done()
  end)
end
