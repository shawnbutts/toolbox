-- The Party Toolbelt (Toolbox.Party, in vitals.lua): the party's health and focus on a strip of its own.
local H = require("harness")

return function(t)
  local PT = function() return Toolbox.Party end

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
                          opacity = r.style.opacity, tip = f:Find("pt_name_" .. i).tooltip }
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
    H.boot()
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
  end)

  t.test("off by default; on, a strip only while in a party", function()
    H.boot()
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
    t.ok(r[3].tip:find("Not in this scene", 1, true), "before API 45 the scene isn't known: " .. r[3].tip)
    H.setParty(nil)
    t.eq(frame(), nil, "left the party: the strip goes")
  end)

  t.test("the bars follow the polls; health order; yourself included", function()
    H.boot()
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
  end)

  t.test("API 45: ShroudGetParty tells offline, the scene, dead and the leader", function()
    H.apiVersion = 45
    H.boot()
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
    H.apiVersion = nil
  end)

  t.test("more members: the rows grow four at a time, to sixteen", function()
    H.boot()
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
  end)

  t.test("only during combat", function()
    H.boot()
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
  end)

  t.test("settings: the Party page; its hint while open with no party; a reset clears it", function()
    H.boot()
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
  end)
end
