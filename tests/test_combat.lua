-- Combat stats HUD.
local H = require("harness")

return function(t)
  local C = function() return Toolbox.Combat end
  local function hit(amount, kind) return { kind = kind or "hit", fromYou = true, amount = amount } end
  local function hurt(amount, kind) return { kind = kind or "hit", toYou = true, amount = amount or 0 } end

  -- model -------------------------------------------------------------------

  t.test("model: damage out / taken / healing, crits and avoids", function()
    H.boot()
    local f = C().NewFight(0)
    C().Add(f, hit(100), 1, true)
    C().Add(f, hit(300, "critical"), 2, true)
    C().Add(f, { kind = "hit", fromYourPet = true, amount = 50 }, 2, true)
    C().Add(f, { kind = "hit", fromYourPet = true, amount = 50 }, 2, false)   -- pet not counted
    C().Add(f, hurt(80), 3, true)
    C().Add(f, hurt(0, "dodge"), 3, true)
    C().Add(f, hurt(0, "parry"), 3, true)
    C().Add(f, { kind = "heal", fromYou = true, amount = 120 }, 4, true)
    C().Add(f, { kind = "hit", party = true, amount = 999 }, 4, true)           -- a party member's
    C().Add(f, { kind = "fall", fromYou = true, toYou = true, amount = 30 }, 4, true)
    t.eq(f.out, 450)
    t.eq(f.taken, 80)
    t.eq(f.healed, 120)
    t.eq(f.hits, 3)
    t.near(C().CritPct(f), 100 / 3)
    t.near(C().AvoidPct(f), 200 / 3)
  end)

  t.test("model: 'now' rates use the last few seconds, averages the whole fight", function()
    H.boot()
    local f = C().NewFight(0)
    for s = 0, 9 do C().Add(f, hit(100), s, true) end     -- 100/s for 10 s
    local now, avg = C().Rates(f, 10)
    t.near(now.out, 400 / C().WINDOW)                      -- t = 6..9 are within 5 s of t = 10
    t.near(avg.out, 100)
    now, avg = C().Rates(f, 15)                           -- 5 quiet seconds
    t.near(now.out, 0)
    t.near(avg.out, 1000 / 15)
    t.eq(C().CritPct(C().NewFight(0)), nil, "no hits, no crit %")
  end)

  -- live --------------------------------------------------------------------

  t.test("hidden by default; /tbx combat shows its rows", function()
    H.boot()
    t.eq(H.combatHud().visible, false)
    H.chat("/tbx combat")
    t.eq(H.combatHud().visible, true)
    local rows = H.combatRows()
    t.eq(rows[1], "Fight=--")
    t.eq(rows[2], "DPS=0  avg 0")
    t.eq(rows[7], "MagicResistance=n/a", "the default stat, unreadable here")
  end)

  t.test("a fight: timer, DPS, taken, crit and avoided from combat lines", function()
    H.boot()
    H.S.stats = { { name = "MagicResistance", value = 42 } }
    H.chat("/tbx combat")
    H.setCombat(true)
    for _ = 1, 10 do
      H.combat({ hit(200), hurt(50) })
      H.advance(1)
    end
    H.combat({ hit(400, "critical"), hurt(0, "dodge") })
    H.advance(0.5, 0.5)
    local rows = H.combatRows()
    t.eq(rows[1], "Fight=10s")
    t.ok(rows[2]:find("^DPS=%d"), rows[2])
    t.ok(rows[2]:find("avg 2%d%d$"), rows[2])
    t.eq(rows[5], "Crit=9%")
    t.eq(rows[6], "Avoided=9%")
    t.eq(rows[7], "MagicResistance=42")
    H.setCombat(false)
    H.advance(5)
    rows = H.combatRows()
    t.ok(rows[1]:find("%(ended%)$"), rows[1])
    t.eq(rows[2]:sub(1, 6), "DPS=0 ", "no 'now' damage after the fight")
    t.ok(rows[2]:find("avg 2%d%d$"), "the average stays up: " .. rows[2])
  end)

  t.test("a new fight starts fresh; reset clears", function()
    H.boot()
    H.chat("/tbx combat")
    H.setCombat(true)
    H.combat({ hit(1000) })
    H.advance(2)
    H.setCombat(false)
    H.advance(2)
    H.setCombat(true)
    H.advance(1)
    t.ok(H.combatRows()[2]:find("avg 0$"), "fresh fight")
    H.combat({ hit(500) })
    H.chat("/tbx combat reset")
    t.ok(H.combatRows()[2]:find("avg 0$"), "reset")
  end)

  t.test("damage lines start a fight without combat mode; quiet time ends it", function()
    H.boot()
    H.chat("/tbx combat")
    H.combat({ hit(100) })
    H.advance(1)
    t.no(H.combatRows()[1]:find("ended"))
    H.advance(C().IDLE_END + 1)
    t.ok(H.combatRows()[1]:find("ended"))
  end)

  t.test("pet damage toggle", function()
    H.boot()
    H.chat("/tbx combat")
    H.setCombat(true)
    H.combat({ { kind = "hit", fromYourPet = true, amount = 500 } })
    H.chat("/tbx combat pet off")
    H.combat({ { kind = "hit", fromYourPet = true, amount = 500 } })
    H.advance(1)
    t.ok(H.combatRows()[2]:find("avg 500$"), "only the first counted: " .. H.combatRows()[2])
    t.eq(C().GetPet(), false)
  end)

  t.test("stats: add readable ones by name, refuse unknown / hidden / duplicates, remove", function()
    H.boot()
    H.S.stats = { { name = "MagicResistance", value = 42 }, { name = "Resist", value = 12.5 },
                  { name = "Secret", value = 1, hidden = true } }
    H.chat("/tbx combat")
    H.clearLogs()
    H.chat("/tbx combat stat add Resist")
    t.ok(H.logged("Added Resist"))
    H.advance(0.5, 0.5)
    t.eq(H.combatRows()[8], "Resist=12.5")
    H.clearLogs()
    H.chat("/tbx combat stat add Nope")
    t.ok(H.logged("No stat is called Nope"))
    H.chat("/tbx combat stat add Secret")
    t.ok(H.logged("hidden from add%-ons"))
    H.chat("/tbx combat stat add resist")
    t.ok(H.logged("already shown"))
    H.chat("/tbx combat stat remove MagicResistance")
    H.advance(0.5, 0.5)
    t.eq(H.combatRows()[7], "Resist=12.5")
    H.reload()
    t.eq(table.concat(C().Stats(), ","), "Resist", "remembered")
  end)

  t.test("size, position, its own strip even when the others are glued", function()
    H.boot()
    H.chat("/tbx combat")
    H.chat("/tbx combat size 150")
    t.eq(H.combatGroup().children[2].children[1].style.fontSize, 18)
    H.chat("/tbx combat move 800 100")
    t.eq(H.combatHud().x, 800)
    H.chat("/tbx buffs")
    H.chat("/tbx vitals glue on")
    t.ok(H.hud() and H.combatHud(), "glued strip plus the combat strip")
    t.eq(H.combatHud().x, 800, "the combat strip stayed put")
    H.advance(1)
    H.reload()
    t.eq(H.combatHud().x, 800)
    t.eq(C().GetScale(), 150)
  end)

  t.test("settings section", function()
    H.boot()
    H.chat("/tbx config")
    H.change("toolbox_config", "show_combat", true)
    t.eq(H.combatHud().visible, true)
    H.change("toolbox_config", "combat_pet", false)
    t.eq(C().GetPet(), false)
    t.eq(H.config():Find("combat_stats").text, "Stats shown: MagicResistance")
    H.click("toolbox_config", "combat_right")
    t.eq(H.combatHud().x, C().HOME[1] + 10)
    H.click("toolbox_config", "combat_reset")
  end)

  -- background ---------------------------------------------------------------

  t.test("Dark: one flat panel at 70% behind all rows, no per-row pieces", function()
    H.boot()
    H.chat("/tbx combat")
    local m = C().Metrics()
    local rows = H.combatHud():Find("combat_rows")
    t.eq(rows.style.backgroundColor, "#000000b3", "black at 70% (0xb3)")
    t.eq(rows.style.paddingTop, m.pad)
    t.eq(rows.style.paddingBottom, m.pad)
    t.eq(rows.style.opacity, nil, "the colour's alpha, not opacity: the text isn't faded")
    local g = H.combatGroup()
    local light, line = g.children[1], g.children[2]
    t.eq(light.visible, false, "no slabs for Dark")
    t.eq(line.style.marginTop, 0, "no pull-up")
    t.eq(g.style.marginTop, 0, "no gap between rows")
    t.eq(g.style.marginBottom, 0)
    t.eq(line.style.paddingLeft, m.pad)
    t.eq(line.style.paddingRight, m.pad, "values inset from the right edge like the names on the left")
    for _, label in ipairs(line.children) do
      t.eq(label.style.marginLeft, 0, "no side margins: the row must fit its panel")
      t.eq(label.style.marginRight, 0)
    end
    t.eq(H.combatHud():Find("pad_top").visible, false, "padding comes from the panel itself")
    local w, h = C().ContentSize()
    t.eq(w, m.w + 2 * m.pad)
    t.ok(h > 0)
    H.chat("/tbx combat bg dark 40")
    t.eq(rows.style.backgroundColor, "#00000066", "follows the opacity")
  end)

  t.test("Light: slabs pulled under each row, inside the margin limit, even at the largest size", function()
    H.boot()
    H.chat("/tbx combat")
    H.chat("/tbx combat bg light 40")
    H.chat("/tbx combat size 250")
    local m = C().Metrics()
    t.ok(m.line <= 64, "line height " .. m.line)
    local g = H.combatGroup()
    local light, line = g.children[1], g.children[2]
    t.eq(light.visible, true)
    t.eq(light.style.backgroundColor, "@text")
    t.eq(light.style.opacity, 0.4)
    t.eq(light.style.height, m.line)
    t.eq(light.style.width, m.w + 2 * m.pad, "full width")
    t.eq(light.style.borderWidth, 0)
    t.eq(line.style.marginTop, -m.line, "the row is pulled up onto its slab")
    t.eq(H.combatHud():Find("combat_rows").style.backgroundColor, "#00000000", "no Dark panel")
    t.eq(H.combatHud():Find("pad_top").visible, true, "padding slabs above and below")
  end)

  t.test("names aren't dim, values are bright; Light turns the text dark", function()
    H.boot()
    H.chat("/tbx combat")
    local line = H.combatGroup().children[2]
    t.ok(line.children[1]:Classes().text and not line.children[1]:Classes().dim)
    t.ok(line.children[2]:Classes().bright)
    H.chat("/tbx combat bg light 40")
    t.eq(H.combatGroup().children[2].children[1].style.color, C().DARK_TEXT)
  end)

  t.test("combat debug adds the laid-out sizes of a row", function()
    H.boot()
    H.chat("/tbx combat")
    H.chat("/tbx combat debug")
    local line = H.lastLog()
    t.ok(line:find("layout: bg ", 1, true), line)
    t.ok(line:find("laid out: slab ", 1, true), line)
  end)

  t.test("None removes the panel and the padding; settings and chat", function()
    H.boot()
    H.chat("/tbx combat")
    H.chat("/tbx combat bg none")
    t.eq(H.combatGroup().children[1].visible, false)
    t.eq(H.combatGroup().children[2].style.marginTop, 0, "no pull-up without a panel")
    t.eq(H.combatHud():Find("combat_rows").style.backgroundColor, "#00000000")
    t.eq(H.combatHud():Find("pad_top").visible, false)
    H.clearLogs()
    H.chat("/tbx combat bg purple")
    t.ok(H.logged("None, Dark, Light"))
    H.chat("/tbx combat bg dark 5")
    t.ok(H.logged("10%-100"), H.lastLog())
    H.chat("/tbx config")
    H.change("toolbox_config", "combat_bg", "Dark")
    H.change("toolbox_config", "combat_bg_opacity", 85)
    t.eq(select(2, C().GetBackground()), 85)
    t.eq(H.combatHud():Find("combat_rows").style.backgroundColor, "#000000d9", "85%")
    H.reload()
    local bg, pct = C().GetBackground()
    t.eq(bg, "Dark"); t.eq(pct, 85)
  end)

  t.test("/tbx combat help explains adding stats on the fly, with examples", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx combat help")
    t.ok(H.logged("Adding stats while playing %(up to 8, saved per character%)"))
    t.ok(H.logged("Find a stat's name: /toolbox stats resist"))
    t.ok(H.logged("Add it by the name shown: /toolbox combat stat add CombatHealthRegen"))
    t.ok(H.logged("Remove it: /toolbox combat stat remove"))
    t.ok(H.logged("combat bg dark 70"))
    H.clearLogs()
    H.chat("/tbx combat stats")
    t.ok(H.logged("Stats on the combat HUD %(1 of 8%): MagicResistance%."))
    t.ok(H.logged("Add one while playing: /toolbox stats <word>"))
    H.clearLogs()
    H.chat("/tbx commands")
    t.ok(H.logged("/toolbox combat %- combat stats HUD; add stats while playing: /toolbox combat help"))
  end)

  t.test("settings show the current stats and how to add more", function()
    H.boot()
    H.chat("/tbx config")
    t.eq(H.config():Find("combat_stats").text, "Stats shown: MagicResistance")
    H.S.stats = { { name = "MagicResistance", value = 1 }, { name = "CombatHealthRegen", value = 0.1 } }
    H.chat("/tbx combat stat add CombatHealthRegen")
    t.eq(H.config():Find("combat_stats").text, "Stats shown: MagicResistance, CombatHealthRegen",
      "the open settings window follows at once")
    H.chat("/tbx combat stat remove MagicResistance")
    t.eq(H.config():Find("combat_stats").text, "Stats shown: CombatHealthRegen")
  end)

  t.test("combat events as game objects still count (DPS and kills)", function()
    H.boot()
    H.S.eventObjects = true
    H.chat("/tbx combat")
    H.setCombat(true)
    H.combat({ { kind = "hit", fromYou = true, amount = 500, target = "Wolf" },
               { kind = "death", fromYou = true, target = "Wolf" } })
    H.advance(1)
    t.ok(table.concat(H.combatRows(), "|"):find("DPS=%d"), "DPS counted")
    t.eq(Toolbox.Daily.day.kills, 1, "the kill counted")
  end)

  t.test("/tbx combat events prints the next events' fields", function()
    H.boot()
    H.S.eventObjects = true
    H.clearLogs()
    H.chat("/tbx combat events 2")
    t.ok(H.logged("^Printing the next 2 combat events"))
    H.combat({ { kind = "hit", fromYou = true, amount = 500, target = "Wolf", rune = "Fireball", runeId = 12,
                 damageType = "fire", time = 101.5, targetKey = 3 },
               { kind = "heal", fromYou = true, amount = 80, overheal = 20, rune = "Heal", runeId = 7 },
               { kind = "hit", toYou = true, amount = 30 } })
    t.ok(H.logged("^Combat event: %(%a+%) kind=hit target=Wolf amount=500 fromYou=true rune=Fireball runeId=12 "
      .. "damageType=fire time=101.5 targetKey=3$"), H.logs()[2])
    t.ok(H.logged("kind=heal .*overheal=20"))
    t.no(H.logged("toYou=true"), "only the next 2")
  end)

  t.test("per-skill damage, healing and overheal; the session sums fights", function()
    H.boot()
    local M = Toolbox.Combat
    local s = M.NewSession(0)
    local f = M.NewFight(0)
    local function ev(x)
      for _, k in ipairs({ "fromYou", "toYou", "fromYourPet", "toYourPet" }) do x[k] = x[k] == true end
      return x
    end
    M.Add(f, ev{ kind = "hit", fromYou = true, amount = 300, rune = "Fireball", runeId = 12 }, 1, true, s)
    M.Add(f, ev{ kind = "critical", fromYou = true, amount = 700, rune = "Fireball", runeId = 12 }, 2, true, s)
    M.Add(f, ev{ kind = "hit", fromYou = true, amount = 100, rune = "Ignite", runeId = 13, dot = true }, 3, true, s)
    M.Add(f, ev{ kind = "hit", fromYou = true, amount = 50, skill = "Swords" }, 3, true, s)   -- no rune (API 14)
    M.Add(f, ev{ kind = "heal", fromYou = true, amount = 80, overheal = 20, rune = "Heal", runeId = 7 }, 4, true, s)
    local top = M.TopRunes(f, 8)
    t.eq(#top, 3)
    t.eq(top[1].name, "Fireball")
    t.eq(top[1].dmg, 1000)
    t.eq(top[1].hits, 2)
    t.eq(top[1].crits, 1)
    t.near(top[1].share, 1000 / 1150, 1e-9)
    t.eq(top[2].name, "Ignite")
    t.eq(top[2].dots, 1)
    t.eq(top[3].name, "Swords", "grouped by the skill's name without a rune")
    t.eq(M.OverhealPct(f), 20)
    t.eq(s.out, 1150, "the session has the same numbers")
    local f2 = M.NewFight(10)
    M.Add(f2, ev{ kind = "hit", fromYou = true, amount = 500, rune = "Fireball", runeId = 12 }, 11, true, s)
    t.eq(M.TopRunes(s, 8)[1].dmg, 1500, "the session keeps adding up")
    t.eq(M.TopRunes(f2, 8)[1].dmg, 500)
  end)

  t.test("the timeline: per-second damage done and taken in 2-second slices, last 60 s", function()
    H.boot()
    local M = Toolbox.Combat
    local s = M.NewSession(0)
    M.AddTimeline(s, 100.5, 400, 0)
    M.AddTimeline(s, 101.9, 200, 60)
    M.AddTimeline(s, 40, 999, 0)                      -- over a minute before: dropped
    local tl = M.Timeline(s, 103)
    t.eq(#tl, M.TIMELINE / M.SLICE)
    t.eq(tl[#tl - 1].out, 300, "slice 100-102: 600 over 2 s")
    t.eq(tl[#tl - 1].taken, 30)
    t.eq(tl[#tl].out, 0, "the current slice")
    for _, x in ipairs(tl) do t.ok(x.out ~= 999 / 2, "old slices dropped") end
  end)

  t.test("in game: fights end, and the session keeps skills, time and the timeline", function()
    H.boot()
    H.chat("/tbx combat")
    H.setCombat(true)
    H.combat({ { kind = "hit", fromYou = true, amount = 400, rune = "Fireball", runeId = 12, time = ShroudTime } })
    H.advance(4)
    H.setCombat(false)
    H.advance(1)
    H.setCombat(true)
    H.combat({ { kind = "hit", fromYou = true, amount = 100, rune = "Frost", runeId = 14, time = ShroudTime } })
    local f, s = Toolbox.Combat.Current()
    t.eq(s.fights, 1, "one finished fight")
    t.eq(Toolbox.Combat.TopRunes(f, 8)[1].name, "Frost", "this fight")
    t.eq(#Toolbox.Combat.TopRunes(s, 8), 2, "the session: both")
    t.ok(Toolbox.Combat.SessionDuration(s, f, Toolbox.Now()) >= 4)
    H.chat("/tbx combat reset")
    local _, s2 = Toolbox.Combat.Current()
    t.eq(s2, nil, "reset clears the session too")
  end)

  -- Combat Detailed ------------------------------------------------------------

  local function cd() return H.S.windows.toolbox_combat_detail end
  -- Skill row i of the window ({ name, bar, value, tip }), nil when hidden. The window's layout:
  -- Scroll > Column > { summary row, heading, skills column, ... }.
  local function skillRow(i)
    local row = cd().children[1].children[1].children[3].children[i]
    if not row or row.visible == false then return nil end
    return { name = row.children[1].text, bar = row.children[2].value, value = row.children[3].text,
             tip = row.children[1].tooltip }
  end

  local function fightWithSkills()
    H.boot()
    H.chat("/tbx combat")
    H.setCombat(true)
    local now = ShroudTime
    H.combat({ { kind = "hit", fromYou = true, amount = 600, rune = "Fireball", runeId = 12, time = now },
               { kind = "critical", fromYou = true, amount = 400, rune = "Fireball", runeId = 12, time = now },
               { kind = "hit", fromYou = true, amount = 150, rune = "Ignite", runeId = 13, dot = true, time = now },
               { kind = "hit", toYou = true, amount = 90, rune = "Bite", time = now },
               { kind = "heal", fromYou = true, amount = 300, overheal = 100, rune = "Heal", runeId = 7, time = now } })
  end

  t.test("Combat Detailed: damage by skill as bars, longest first, with details on hover", function()
    fightWithSkills()
    H.chat("/tbx combat detail")
    t.ok(cd():IsShown())
    t.eq(H.saved("combat_detail").open, true)
    H.advance(1)
    local r1, r2 = skillRow(1), skillRow(2)
    t.eq(r1.name, "Fireball")
    t.eq(r1.bar, 1, "the longest bar")
    t.eq(r1.value, "1,000  87%")
    t.ok(r1.tip:find("2 hits, 1 critical %(50%%%), 0 over%-time ticks"), r1.tip)
    t.eq(r2.name, "Ignite")
    t.near(r2.bar, 0.15, 1e-9)
    t.eq(skillRow(3), nil, "only skills that did damage")
    t.ok(cd():Find("cd_summary").text:find("^This fight: .*Damage 1,150"), cd():Find("cd_summary").text)
    t.ok(cd():Find("cd_heal").text:find("^300 healed %(.-%); 100 wasted as overheal %(25%%%)%.$"))
  end)

  t.test("Combat Detailed: the last-minute chart scales to its peak", function()
    fightWithSkills()
    H.chat("/tbx combat detail")
    H.advance(1)
    local M = Toolbox.Combat.Detail
    local rows = cd().children[1].children[1].children
    local up, down = rows[6].children, rows[8].children
    local tallest, shownUp, shownDown = 0, 0, 0
    for _, b in ipairs(up) do
      if b.style.backgroundColor ~= M.EMPTY then
        shownUp, tallest = shownUp + 1, math.max(tallest, b.style.height)
        t.eq(b.style.marginTop + b.style.height, M.OUT_H, "stands on the baseline")
      end
    end
    for _, b in ipairs(down) do if b.style.backgroundColor ~= M.EMPTY then shownDown = shownDown + 1 end end
    t.eq(#up, 30, "one element per column; empty ones keep their place")
    t.eq(shownUp, 1, "one slice with damage done")
    t.eq(tallest, M.OUT_H, "the peak fills the chart")
    t.eq(shownDown, 1, "one slice with damage taken")
    t.ok(cd():Find("cd_peak").text:find("^Peaks: "))
  end)

  t.test("Combat Detailed: this fight or the session", function()
    fightWithSkills()
    H.advance(1)
    H.setCombat(false)
    H.advance(2)
    H.setCombat(true)
    H.combat({ { kind = "hit", fromYou = true, amount = 50, rune = "Frost", runeId = 14, time = ShroudTime } })
    H.chat("/tbx combat detail")
    H.advance(1)
    t.eq(skillRow(1).name, "Frost", "this fight only")
    H.chat("/tbx combat detail session")
    t.eq(H.saved("combat_detail").scope, "session")
    H.advance(1)
    t.eq(skillRow(1).name, "Fireball", "every fight")
    t.ok(cd():Find("cd_summary").text:find("1 fights done"))
    H.change("toolbox_combat_detail", "cd_scope", "This fight")
    t.eq(Toolbox.Combat.Detail.GetScope(), "fight")
  end)

  t.test("Combat Detailed pops up when the combat HUD is hovered", function()
    fightWithSkills()
    local rows = H.combatHud():Find("combat_rows")
    H.call(function() rows.onHover(rows, true) end)
    H.advance(1, 0.25)
    t.ok(cd() and cd():IsShown(), "popped up")
    t.eq(H.saved("combat_detail") and H.saved("combat_detail").open or false, false, "not pinned")
    H.call(function() rows.onHover(rows, false) end)
    H.advance(1, 0.25)
    t.no(cd():IsShown(), "gone after leaving")
    H.chat("/tbx config")
    H.change("toolbox_config", "combat_detail_hover", false)
    H.call(function() rows.onHover(rows, true) end)
    H.advance(1, 0.25)
    t.no(cd():IsShown(), "no pop-up with hover off")
  end)

  t.test("targets: damage per creature, same-named ones kept apart, kill time from first hit to death", function()
    H.boot()
    local M = Toolbox.Combat
    local f = M.NewFight(0)
    local function ev(x)
      for _, k in ipairs({ "fromYou", "toYou", "fromYourPet", "toYourPet" }) do x[k] = x[k] == true end
      return x
    end
    local bear = "Large Grizzly Bear"
    M.Add(f, ev{ kind = "hit", fromYou = true, amount = 44, target = bear, targetKey = 15, time = 851 }, 851)
    M.Add(f, ev{ kind = "hit", fromYou = true, amount = 14, target = bear, targetKey = 15, time = 852 }, 852)
    M.Add(f, ev{ kind = "hit", fromYou = true, amount = 30, target = bear, targetKey = 16, time = 853 }, 853)
    M.Add(f, ev{ kind = "death", fromYou = true, source = "shawn", sourceKey = 1, target = "Large Grizzly Bear",
                 targetKey = 15, time = 893 }, 893)
    local tops = M.TopTargets(f, 6)
    t.eq(#tops, 2, "two bears, not one")
    t.eq(tops[1].dmg, 58)
    t.eq(tops[1].killed, true)
    t.eq(tops[1].secs, 42, "first hit at 851, death at 893")
    t.eq(tops[2].killed, false)
    t.eq(M.TargetKey(nil, "Wolf"), "n:Wolf", "by name without a key (API 14)")
  end)

  t.test("damage types: done and taken, most first, with shares", function()
    H.boot()
    local M = Toolbox.Combat
    local f = M.NewFight(0)
    local function ev(x)
      for _, k in ipairs({ "fromYou", "toYou", "fromYourPet", "toYourPet" }) do x[k] = x[k] == true end
      return x
    end
    M.Add(f, ev{ kind = "hit", fromYou = true, amount = 70, damageType = "blade" }, 1)
    M.Add(f, ev{ kind = "hit", fromYou = true, amount = 30, damageType = "handToHand" }, 1)
    M.Add(f, ev{ kind = "hit", fromYou = true, amount = 5 }, 1)                    -- no type: "other"
    M.Add(f, ev{ kind = "glancing", toYou = true, amount = 1, damageType = "handToHand" }, 1)
    local out = M.Types(f, "out")
    t.eq(out[1].type, "blade")
    t.near(out[1].share, 70 / 105, 1e-9)
    t.eq(out[3].type, "other")
    t.eq(M.Types(f, "taken")[1].type, "handToHand")
    t.eq(M.Detail.TypeName("handToHand"), "Hand to hand")
  end)

  t.test("Combat Detailed shows targets and damage types", function()
    H.boot()
    H.chat("/tbx combat")
    H.setCombat(true)
    local now = ShroudTime
    H.combat({ { kind = "hit", fromYou = true, amount = 44, rune = "Body Slam", runeId = 75, damageType = "handToHand",
                 target = "Large Grizzly Bear", targetKey = 15, time = now },
               { kind = "hit", fromYou = true, amount = 100, rune = "Bladed Combat", runeId = 222, damageType = "blade",
                 target = "Large Grizzly Bear", targetKey = 15, time = now },
               { kind = "glancing", toYou = true, amount = 1, damageType = "handToHand", source = "Large Grizzly Bear",
                 sourceKey = 15, time = now } })
    H.advance(20)
    H.combat({ { kind = "death", fromYou = true, source = "shawn", sourceKey = 1, target = "Large Grizzly Bear",
                 targetKey = 15, time = ShroudTime } })
    H.chat("/tbx combat detail")
    H.advance(1)
    local w = H.S.windows.toolbox_combat_detail
    local body = w.children[1].children[1].children
    local target = body[13].children[1]
    t.eq(target.children[1].text, "Large Grizzly Bear")
    t.ok(target.children[3].text:find("^144  killed 20s$"), target.children[3].text)
    t.eq(w:Find("cd_types_out").text, "Blade 69%  ·  Hand to hand 31%")
    t.eq(w:Find("cd_types_taken").text, "Hand to hand 100%")
    local done = body[17]
    local shownW = 0
    for _, seg in ipairs(done.children) do
      if seg.visible ~= false then shownW = shownW + seg.style.width end
    end
    t.eq(shownW, Toolbox.Combat.Detail.TYPE_W, "the parts fill the bar")
  end)

  t.test("fight history: the last 10 finished fights, newest first, blips left out", function()
    H.boot()
    local M = Toolbox.Combat
    local s = M.NewSession(0)
    local function fight(start, dmg, secs)
      local f = M.NewFight(start)
      f.out, f.last, f.ended = dmg, start + secs, start + secs
      return f
    end
    for i = 1, 12 do M.Remember(s, fight(i * 100, i * 1000, 10)) end
    M.Remember(s, fight(2000, 0, 3))                 -- nothing happened: not remembered
    t.eq(#s.history, M.HISTORY)
    t.eq(s.history[1].out, 12000, "newest first")
    t.eq(s.history[1].dps, 1200)
    t.eq(s.history[#s.history].out, 3000, "the oldest two dropped")
  end)

  t.test("Combat Detailed: recent fights as DPS bars", function()
    H.boot()
    H.chat("/tbx combat")
    for n = 1, 2 do
      H.setCombat(true)
      H.combat({ { kind = "hit", fromYou = true, amount = n * 300, rune = "Thrust", runeId = 10, target = "Spider",
                   targetKey = n, time = ShroudTime } })
      H.advance(3)
      H.setCombat(false)
      H.advance(1)
    end
    H.chat("/tbx combat detail")
    H.advance(1)
    local w = H.S.windows.toolbox_combat_detail
    local body = w.children[1].children[1].children
    local rows = body[#body - 1].children
    t.eq(rows[1].visible ~= false, true)
    t.ok(rows[1].children[1].text:find("Thrust$"), rows[1].children[1].text)
    t.eq(rows[1].children[2].value, 1, "the newest (600) is the best")
    t.near(rows[2].children[2].value, 0.5, 0.01)
    t.eq(rows[3].visible, false)
    t.eq(w:Find("cd_nohistory").visible, false)
  end)

  t.test("start-up with every window open stays inside the element-creation cap", function()
    H.boot()
    for _, c in ipairs({ "/tbx xp", "/tbx xpdetailed", "/tbx daily", "/tbx dd", "/tbx buffs", "/tbx vitals",
                         "/tbx combat", "/tbx combat detail", "/tbx config", "/tbx notify via hud" }) do
      H.chat(c)
    end
    H.reload()                                 -- everything rebuilt at once: must not raise
    t.no(H.S.windows.toolbox_combat_detail, "the pinned Combat Detailed waits")
    H.advance(Toolbox.Combat.Detail.OPEN_DELAY + 1)
    t.ok(H.S.windows.toolbox_combat_detail:IsShown(), "and opens a moment later")
  end)
end
