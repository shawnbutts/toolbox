-- Items gained today and the Loot Tracker window (pinned and hover pop-up).
local H = require("harness")

return function(t)
  local function day() return Toolbox.Daily.day end
  local D = function() return Toolbox.Daily end

  -- model -------------------------------------------------------------------

  t.test("model: items add up by name; dropped kinds are counted", function()
    H.boot()
    local d = D().New("k")
    t.ok(D().AddItems(d, { { name = "Iron Ore", quantity = 5 }, { name = "Wolf Pelt", quantity = 1 } }, 0))
    D().AddItems(d, { { name = "Iron Ore", quantity = 3 } }, 2)
    t.eq(d.items["Iron Ore"], 8)
    t.eq(d.items["Wolf Pelt"], 1)
    t.eq(d.dropped, 2)
    t.no(D().AddItems(d, { { name = "", quantity = 1 }, { name = "X", quantity = 0 }, "junk" }, 0), "ignored")
  end)

  t.test("model: kinds past the cap go to one 'other' line", function()
    H.boot()
    local d = D().New("k")
    for i = 1, D().MAX_KINDS do D().AddItems(d, { { name = "Item " .. i, quantity = 1 } }, 0) end
    D().AddItems(d, { { name = "One too many", quantity = 4 }, { name = "Item 1", quantity = 1 } }, 0)
    t.eq(d.items["One too many"], nil)
    t.eq(d.items[D().OTHER], 4)
    t.eq(d.items["Item 1"], 2, "known names still count")
  end)

  t.test("model: sorted by count, then name", function()
    H.boot()
    local d = D().New("k")
    d.items = { B = 2, A = 2, C = 9 }
    local names = D().SortedItems(d)
    t.eq(table.concat(names, ","), "C,A,B")
  end)

  t.test("model: a new day clears items; v1 saves without items still load", function()
    H.boot()
    local d = D().New("day1")
    D().AddItems(d, { { name = "Ore", quantity = 1 } }, 3)
    D().Roll(d, "day2")
    t.eq(next(d.items), nil)
    t.eq(d.dropped, 0)
    local old = { v = 1, key = "k", gold = 0, kills = 0, a = 0, p = 0, last = {} }
    t.ok(D().IsValid(old))
    D().Upgrade(old)
    t.eq(type(old.items), "table")
  end)

  -- live --------------------------------------------------------------------

  t.test("items gained are counted and survive a reload", function()
    H.boot()
    H.items({ { "Iron Ore", 5 }, { "Wolf Pelt", 1 } })
    H.items({ { "Iron Ore", 2 } })
    H.advance(1)
    H.reload()
    t.eq(day().items["Iron Ore"], 7)
    t.eq(day().items["Wolf Pelt"], 1)
  end)

  t.test("window lists items sorted by count, with totals", function()
    H.boot()
    H.items({ { "Wolf Pelt", 1 }, { "Iron Ore", 12 }, { "Arrows", 40 } })
    H.goldChange(250)
    H.combat({ { kind = "death", fromYou = true } })
    H.advance(1)
    H.chat("/tbx dailydetailed")
    t.ok(H.detail():IsShown())
    t.eq(H.detail().title, "Loot Tracker")
    local rows = H.detailRows()
    t.eq(#rows, 3)
    t.eq(rows[1][1], "Arrows")
    t.eq(rows[1][2], "40")
    t.eq(rows[3][1], "Wolf Pelt")
    t.eq(H.detail():Find("summary").text, "Gold 250  |  Kills 1")
    t.eq(H.detail():Find("items_summary").text, "Items looted: 53 (3 kinds)")
    t.eq(H.detail():Find("date").text, "Today 2026-09-27")
    t.eq(H.detail():Find("more").visible, false)
  end)

  t.test("new items are appended, counts update, and nothing is rebuilt each tick", function()
    H.boot()
    H.items({ { "Iron Ore", 1 } })
    H.chat("/tbx dd")
    H.advance(1)
    local created = H.S.created or 0
    H.advance(30)
    t.eq(H.S.created or 0, created, "no elements created while nothing new arrives")
    H.items({ { "Iron Ore", 4 }, { "Gem", 1 } })
    H.advance(1)
    local rows = H.detailRows()
    t.eq(#rows, 2)
    t.eq(rows[1][1], "Iron Ore")
    t.eq(rows[1][2], "5")
    t.eq(rows[2][1], "Gem", "appended")
    t.eq((H.S.created or 0) - created, 1, "one new row")
  end)

  t.test("rows get re-sorted when shown, at most every RESORT_SECONDS", function()
    H.boot()
    H.chat("/tbx dd")
    H.items({ { "A", 1 } })
    H.advance(1)
    H.items({ { "B", 2 } })
    H.advance(1)
    t.eq(H.detailRows()[1][1], "A", "appended in arrival order while open")
    H.chat("/tbx dd")                                   -- close
    H.advance(Toolbox.DailyDetail.RESORT_SECONDS)
    H.chat("/tbx dd")                                   -- reopen: out of order, so rebuilt
    t.eq(H.detailRows()[1][1], "B")
    H.items({ { "A", 5 } })                             -- A overtakes B
    H.chat("/tbx dd")
    H.chat("/tbx dd")                                   -- reopened too soon: left alone
    t.eq(H.detailRows()[1][1], "B")
    H.chat("/tbx dd")
    H.advance(Toolbox.DailyDetail.RESORT_SECONDS)
    H.chat("/tbx dd")
    t.eq(H.detailRows()[1][1], "A", "re-sorted once allowed")
  end)

  t.test("a rebuild stays well inside the element burst", function()
    H.boot()
    local list = {}
    for i = 1, 200 do list[#list + 1] = { string.format("Item %03d", i), i } end
    H.items(list)
    H.advance(Toolbox.DailyDetail.RESORT_SECONDS)
    local before = H.S.created or 0
    H.chat("/tbx dd")
    local made = (H.S.created or 0) - before
    t.ok(made <= Toolbox.DailyDetail.MAX_ROWS, "rows added: " .. made)
    t.ok(3 * Toolbox.DailyDetail.MAX_ROWS < 500, "3 elements per row, under the 500 burst")
    t.eq(H.detailRows()[1][1], "Item 200", "highest count first")
  end)

  t.test("no items yet", function()
    H.boot()
    H.chat("/tbx dd")
    t.eq(H.detail():Find("items_summary").text, "No items looted yet")
    t.eq(#H.detailRows(), 0)
  end)

  t.test("rows are capped; the rest and dropped kinds are summarised", function()
    H.boot()
    local list = {}
    for i = 1, Toolbox.DailyDetail.MAX_ROWS + 5 do list[#list + 1] = { string.format("Item %03d", i), 1 } end
    H.items(list, 3)
    H.chat("/tbx dd")
    t.eq(#H.detailRows(), Toolbox.DailyDetail.MAX_ROWS)
    t.eq(H.detail():Find("more").text, "+5 more kinds not listed; +3 kinds the game didn't itemise")
    t.eq(H.detail():Find("more").visible, true)
  end)

  t.test("midnight clears the list", function()
    H.boot()
    H.items({ { "Iron Ore", 1 } })
    H.chat("/tbx dd")
    H.advance(1)
    H.S.date = "2026-09-28"
    H.advance(1)
    t.eq(#H.detailRows(), 0)
    H.items({ { "Gem", 2 } })
    H.advance(1)
    t.eq(H.detailRows()[1][1], "Gem")
  end)

  t.test("text size and spacing reach the item rows", function()
    H.boot()
    H.items({ { "Iron Ore", 1 } })
    H.chat("/tbx dd")
    H.chat("/tbx font 16")
    local row = H.detail():Find("list").children[1]
    t.eq(row.children[1].style.fontSize, 16)
    t.eq(row.children[2].style.height, Toolbox.Window.LineHeight())
  end)

  -- hover and pinning -------------------------------------------------------

  t.test("hovering Today pops up Loot Tracker after the delay", function()
    H.boot()
    H.chat("/tbx daily")
    H.hover("toolbox_daily", nil, true)
    H.advance(Toolbox.Hover.SHOW_DELAY - 0.2, 0.1)
    t.no(H.detail():IsShown())
    H.advance(0.3, 0.1)
    t.ok(H.detail():IsShown())
    t.eq(H.saved("daily_detail") and H.saved("daily_detail").open or false, false, "pop-up not remembered")
    H.hover("toolbox_daily", nil, false)
    H.hover("toolbox_daily_detail", "body", true)       -- move into it: stays
    H.advance(2, 0.1)
    t.ok(H.detail():IsShown())
    H.hover("toolbox_daily_detail", "body", false)
    H.advance(1, 0.1)
    t.no(H.detail():IsShown(), "closes after leaving both")
  end)

  t.test("the two hover pop-ups are independent", function()
    H.boot()
    H.chat("/tbx daily")
    H.chat("/tbx xp")
    H.hover("toolbox_daily", nil, true)
    H.advance(1, 0.1)
    t.ok(H.detail():IsShown())
    t.no(H.window():IsShown(), "XP Detailed not affected")
  end)

  t.test("pinned Loot Tracker stays and is remembered; dd pins a pop-up", function()
    H.boot()
    H.chat("/tbx daily")
    H.hover("toolbox_daily", nil, true)
    H.advance(1, 0.1)
    H.chat("/tbx dd")
    t.eq(H.saved("daily_detail").open, true)
    H.hover("toolbox_daily", nil, false)
    H.advance(2, 0.1)
    t.ok(H.detail():IsShown(), "pinned")
    H.reload()
    t.ok(H.detail():IsShown(), "reopened after reload")
  end)

  t.test("settings: show and hover checkboxes for Loot Tracker", function()
    H.boot()
    H.chat("/tbx daily")
    H.chat("/tbx config")
    t.eq(H.config():Find("hover_daily").value, true, "hover on by default")
    H.change("toolbox_config", "hover_daily", false)
    H.hover("toolbox_daily", nil, true)
    H.advance(2, 0.1)
    t.no(H.detail():IsShown())
    t.eq(H.saved("daily_window").hover, false)
    H.change("toolbox_config", "show_daily_detail", true)
    t.ok(H.detail():IsShown())
    H.closeWindow("toolbox_daily_detail")
    t.eq(H.config():Find("show_daily_detail").value, false)
  end)

  t.test("help lists loot and its aliases, the older dailydetailed and dd", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx commands")
    t.ok(H.logged("/toolbox loot %(or dailydetailed, dd%)"), H.logs()[1])
  end)

  -- Reset (owner, 2026-10-04): a run counted from a moment, the day kept underneath.
  local function names()
    local out = {}
    for _, r in ipairs(H.detailRows()) do out[#out + 1] = r[1] .. "=" .. r[2] end
    return table.concat(out, ", ")
  end

  t.test("Reset: the Loot Tracker counts from now; the Today window keeps the whole day", function()
    H.boot()
    H.chat("/tbx loot")
    H.items({ { "Iron Ore", 5 }, { "Wolf Pelt", 2 } })
    H.goldChange(100)
    H.advance(2)
    t.eq(names(), "Iron Ore=5, Wolf Pelt=2")
    H.click("toolbox_daily_detail", "dd_reset")
    t.eq(names(), "", "nothing since the reset")
    t.ok(H.detail():Find("date").text:find("^Since %d%d:%d%d %(<1m%)$"), H.detail():Find("date").text)
    t.ok(H.detail():Find("dd_today").visible ~= false, "Show all of today offered")
    H.items({ { "Iron Ore", 3 }, { "Bone", 1 } })
    H.goldChange(40)
    H.advance(2)
    t.eq(names(), "Iron Ore=3, Bone=1", "only this run")
    t.eq(H.detail():Find("summary").text, "Gold 40  |  Kills 0")
    t.eq(day().items["Iron Ore"], 8, "the day keeps everything")
    t.eq(day().gold, 140)
    H.chat("/tbx daily")
    t.eq(H.dailyText("gold"), "140", "the Today window: the whole day")
  end)

  t.test("Show all of today undoes it; a run survives a reload and ends at midnight", function()
    H.boot()
    H.chat("/tbx loot")
    H.items({ { "Iron Ore", 5 } })
    H.advance(1)
    H.chat("/tbx loot reset")
    H.items({ { "Bone", 2 } })
    H.advance(1)
    H.reload()                                     -- (it reopens: it was open)
    H.advance(1)
    t.eq(names(), "Bone=2", "still the run after a reload")
    H.click("toolbox_daily_detail", "dd_today")
    t.eq(names(), "Iron Ore=5, Bone=2", "all of today again")
    t.eq(H.detail():Find("dd_today").visible, false)
    H.chat("/tbx loot reset")
    H.S.date = "2026-09-28"
    H.advance(2)
    t.eq(day().since, nil, "a new day: no run")
    t.ok(H.detail():Find("date").text:find("^Today"), H.detail():Find("date").text)
  end)

  t.test("Reset covers the Crafted and Gathered views too", function()
    H.boot()
    H.chat("/tbx loot")
    H.gatherResults({ { node = "Iron Vein", failed = false, experience = 5,
                        items = { { name = "Iron Ore", quantity = 4 } } } })
    H.items({ { "Iron Ore", 4 } })
    H.advance(1)
    H.chat("/tbx loot view gathered")
    t.eq(names(), "Iron Ore=4")
    H.chat("/tbx loot reset")
    t.eq(names(), "")
    H.gatherResults({ { node = "Iron Vein", failed = false, experience = 5,
                        items = { { name = "Iron Ore", quantity = 2 } } } })
    H.items({ { "Iron Ore", 2 } })
    H.advance(1)
    t.eq(names(), "Iron Ore=2")
  end)

  -- Run rates (owner, 2026-10-04): per hour of play since the reset.
  t.test("a run's rates: per hour of play, after its first minute; the header shows how long", function()
    H.boot()
    H.chat("/tbx loot")
    H.chat("/tbx loot reset")
    H.goldChange(500)
    H.advance(30)
    t.eq(H.detail():Find("summary").text, "Gold 500  |  Kills 0", "no rate in the first minute")
    H.advance(30 * 60 - 30 + 2)                          -- half an hour of play (rates move once a minute)
    t.eq(H.detail():Find("summary").text, "Gold 500 (1,000/h)  |  Kills 0 (0/h)")
    t.ok(H.detail():Find("date").text:find("%(30m%)$"), H.detail():Find("date").text)
    t.ok(H.detail():Find("summary").tooltip:find("over 30m of play"), H.detail():Find("summary").tooltip)
  end)

  t.test("a run's play time pauses while logged out and through a reload, and carries on", function()
    H.boot()
    H.chat("/tbx loot")
    H.chat("/tbx loot reset")
    H.advance(10 * 60)
    H.callback("ShroudOnDisableScript")                  -- /lua reload as the game does it: saved at shutdown
    H.reload()                                           -- (the window reopens: it was open)
    H.S.time = ShroudTime + 3600                         -- an hour away before the next tick
    ShroudTime = H.S.time
    H.advance(5 * 60 + 3)
    t.ok(math.abs(Toolbox.Daily.RunPlayed() - 15 * 60) <= 3, "15 minutes of play: " .. Toolbox.Daily.RunPlayed())
    t.ok(H.detail():Find("date").text:find("%(15m%)$"), H.detail():Find("date").text)
  end)

  t.test("model: durations and per-hour", function()
    H.boot()
    t.eq(D().Duration(30), "<1m")
    t.eq(D().Duration(47 * 60), "47m")
    t.eq(D().Duration(72 * 60 + 5), "1h 12m")
    t.eq(D().PerHour(100, 59), nil)
    t.eq(D().PerHour(100, 1800), 200)
  end)

  -- Run history (owner, 2026-10-07): runs filed as they end, to compare farming spots.
  local function runRows()
    local out = {}
    for _, r in ipairs(H.detailRows()) do out[#out + 1] = r[1] .. " = " .. r[2] end
    return out
  end

  t.test("runs: filed at the next Reset with their place, length and rates; listed newest first", function()
    H.boot()
    H.chat("/tbx loot")
    H.chat("/tbx loot reset")
    H.S.scene = "Northern Lowlands"
    H.goldChange(600)
    H.items({ { "Iron Ore", 10 } })
    H.advance(30 * 60 + 2)                               -- half an hour
    H.chat("/tbx loot reset")                            -- files it, starts the next
    H.S.scene = "Highvale"
    H.goldChange(100)
    H.advance(10 * 60 + 2)
    H.chat("/tbx loot reset")
    H.chat("/tbx loot view runs")
    local rows = runRows()
    t.eq(#rows, 2, table.concat(rows, " | "))
    t.ok(rows[1]:find("^%d%d:%d%d Highvale %(10m%) = [56]%d%dg/h$"), rows[1])          -- about 600 gold an hour
    t.ok(rows[2]:find("^%d%d:%d%d Northern Lowlands %(30m%) = 1,[12]%d%dg/h$"), rows[2]) -- about 1,200
    local tip = H.detail():Find("list").children[2].children[1].tooltip
    t.ok(tip:find("Gold 600 %(1,[12]%d%d/h%), kills 0"), tip)
    t.ok(tip:find("10 items %(1 kinds%)"), tip)
    t.eq(H.detail():Find("items_summary").text, "Last 2 runs, newest first")
  end)

  t.test("runs: Show all of today and midnight file a run; under a minute isn't kept; at most 10; per character",
      function()
    H.boot()
    H.chat("/tbx loot")
    H.chat("/tbx loot reset")
    H.advance(30)
    H.chat("/tbx loot today")
    t.eq(#Toolbox.Daily.Runs(), 0, "30 s: not kept")
    H.chat("/tbx loot reset")
    H.advance(120)
    H.chat("/tbx loot today")
    t.eq(#Toolbox.Daily.Runs(), 1, "filed by Show all of today")
    H.chat("/tbx loot reset")
    H.advance(120)
    H.S.date = "2026-09-28"
    H.advance(2)
    t.eq(#Toolbox.Daily.Runs(), 2, "filed at midnight")
    for _ = 1, 12 do
      H.chat("/tbx loot reset")
      H.advance(61)
    end
    t.eq(#Toolbox.Daily.Runs(), Toolbox.Daily.RUNS_KEEP)
    H.restart(nil, true)
    t.eq(#Toolbox.Daily.Runs(), Toolbox.Daily.RUNS_KEEP, "kept across a restart")
    H.callback("ShroudOnLogOut")
    H.S.char.name = "Alt"
    H.callback("ShroudOnSceneLoaded", "Novia")
    t.eq(#Toolbox.Daily.Runs(), 0, "Alt's own history")
  end)

  t.test("runs: the estimated value per hour, from the prices when the run ended", function()
    H.boot()
    H.chat("/tbx loot")
    H.chat("/tbx loot values on")
    H.chat("/tbx loot reset")
    H.items({ { "Iron Ore", 30 } })
    H.advance(2)
    H.httpRespond(#H.S.requests, true, 200, '{"items":[{"item":"Iron Ore","avg90d":5,"sold90d":10}],"missing":[]}')
    H.advance(60 * 60)                                   -- an hour
    H.chat("/tbx loot reset")
    H.chat("/tbx loot view runs")
    local row = H.detailRows()[1]
    t.ok(row[3] == "150g/h" or row[3] == "149g/h", "30 ore x 5g over an hour: " .. tostring(row[3]))
    t.eq(Toolbox.Daily.Runs()[1].value, 150, "the run's value")
  end)
end
