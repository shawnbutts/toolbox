-- Estimated values in Today Detailed (Toolbox.Prices), and the JSON / URL helpers behind them.
local H = require("harness")

return function(t)
  local ANSWER = '{"generatedAt":"2026-09-28T07:55:19Z","count":1,"items":[{"item":"Iron Ore","lastPrice":5,'
    .. '"lastSoldAt":"2026-07-26T18:56:00Z","avg90d":5,"sold90d":1000}],"missing":["Rusty Nail"]}'

  -- Booted with Today Detailed open and values on.
  local function withValues()
    H.boot()
    H.chat("/tbx dd")
    H.chat("/tbx dd values on")
  end

  local function row(name)
    for _, r in ipairs(H.detailRows()) do if r[1] == name then return r end end
  end

  local function header() return H.detail():Find("value_summary") end

  t.test("JsonDecode: objects, arrays, strings, numbers, literals", function()
    H.boot()
    local J = Toolbox.JsonDecode
    local v = J('{"a":[1,-2.5,3e2,true,false,null,"x"],"b":{"c":"d"}, "e" : "" }')
    t.eq(v.a[1], 1)
    t.eq(v.a[2], -2.5)
    t.eq(v.a[3], 300)
    t.eq(v.a[4], true)
    t.eq(v.a[5], false)
    t.eq(v.a[6], nil, "null")
    t.eq(v.a[7], "x")
    t.eq(v.b.c, "d")
    t.eq(v.e, "")
    t.eq(J('"a\\"b\\\\c\\/d\\n"'), 'a"b\\c/d\n')
    t.eq(J('"\\u00e9\\u20ac\\ud83d\\ude00"'), "\195\169\226\130\172\240\159\152\128", "UTF-8 from \\u")
    t.eq(#J("[]"), 0)
    t.eq(next(J("{}")), nil)
  end)

  t.test("JsonDecode: bad input gives nil and a reason", function()
    H.boot()
    local J = Toolbox.JsonDecode
    for _, bad in ipairs({ "", "[1,2", '{"a" 1}', '{"a":1} x', '"open', "nope", "{a:1}", '"\\q"' }) do
      local v, err = J(bad)
      t.eq(v, nil, bad)
      t.ok(type(err) == "string", "a reason for " .. bad)
    end
    t.eq(J(nil), nil)
  end)

  t.test("UrlEncode and Format", function()
    H.boot()
    t.eq(Toolbox.UrlEncode("Gold Ore, 5&x=é"), "Gold%20Ore%2C%205%26x%3D%C3%A9")
    local F = Toolbox.Prices.Format
    t.eq(F(1234.4), "1,234g")
    t.eq(F(12), "12g")
    t.eq(F(4.5), "4.5g")
    t.eq(F(3), "3g")
    t.eq(F(0.2), "<1g")
    t.eq(F(0), "0g")
  end)

  t.test("off by default: nothing is sent", function()
    H.boot()
    H.chat("/tbx dd")
    H.items({ { "Iron Ore", 40 } })
    H.advance(30)
    t.eq(H.S.requests, nil)
    t.eq(header().visible, false)
    t.eq(row("Iron Ore")[3], "", "no value")
  end)

  t.test("values: looked up, shown per row and in total; unsold items stay blank", function()
    withValues()
    H.items({ { "Iron Ore", 40 }, { "Rusty Nail", 3 } })
    H.advance(2)
    t.eq(#H.S.requests, 1)
    local asked = H.requestedItems(1)
    table.sort(asked)
    t.eq(table.concat(asked, ","), "Iron Ore,Rusty Nail")
    t.ok(header().text:find("looking up prices"), header().text)
    H.httpRespond(1, true, 200, ANSWER)
    t.eq(row("Iron Ore")[3], "~200g")
    t.ok(row("Iron Ore")[4]:find("~5g each: the average of 1,000 sold in the last 90 days; last sold 2026%-07%-26"))
    t.eq(row("Rusty Nail")[3], "")
    t.eq(row("Rusty Nail")[4], "No sales on SOTA.net in the last 90 days")
    t.eq(header().text, "Estimated value ~200g (1 of 2 kinds priced, SOTA.net)")
    H.items({ { "Iron Ore", 10 } })
    H.advance(1)
    t.eq(row("Iron Ore")[3], "~250g", "follows the count")
    t.eq(#H.S.requests, 1, "no new lookup for a known item")
  end)

  t.test("prices are kept per account for the day, then looked up again", function()
    withValues()
    H.items({ { "Iron Ore", 40 } })
    H.advance(2)
    H.httpRespond(1, true, 200, ANSWER)
    t.eq(H.saved("prices", "account").items["iron ore"].avg, 5)
    H.reload()                               -- Today Detailed reopens (it was open)
    H.advance(3)
    t.eq(#H.S.requests, 1, "still today: no new lookup")
    t.eq(row("Iron Ore")[3], "~200g")
    H.S.date = "2026-09-28"
    H.advance(2)
    H.items({ { "Iron Ore", 2 } })
    H.advance(3)
    t.eq(#H.S.requests, 2, "a new day: looked up again")
  end)

  t.test("at most 50 names a request, spaced out", function()
    withValues()
    local list = {}
    for i = 1, 60 do list[#list + 1] = { "Item " .. i, 1 } end
    H.items(list)
    H.advance(2)
    t.eq(#H.S.requests, 1)
    t.eq(#H.requestedItems(1), 50)
    H.advance(5)
    t.eq(#H.S.requests, 1, "one at a time")
    H.httpRespond(1, true, 200, '{"items":[],"missing":[]}')
    H.advance(Toolbox.Prices.GAP)
    t.eq(#H.S.requests, 2)
    t.eq(#H.requestedItems(2), 10)
  end)

  t.test("a long URL is split before the client's limit", function()
    H.boot()
    local names = {}
    for i = 1, 50 do names[i] = string.rep("Long Item Name ", 3) .. i end
    local batch, url = Toolbox.Prices.NextBatch(names)
    t.ok(#url <= Toolbox.Prices.URL_MAX, "URL " .. #url)
    t.ok(#batch < 50 and #batch > 10, "split at " .. #batch)
  end)

  t.test("Internet switched off in the add-on manager: the header says so, then it retries", function()
    withValues()
    H.S.httpRefuse = "not_permitted"
    H.items({ { "Iron Ore", 40 } })
    H.advance(3)
    t.eq(H.S.requests, nil)
    t.ok(header().text:find("switch Internet on for Toolbox"), header().text)
    H.S.httpRefuse = nil
    H.advance(Toolbox.Prices.RETRY)
    t.eq(#H.S.requests, 1)
  end)

  t.test("a failed or unanswered lookup is tried again later", function()
    withValues()
    H.items({ { "Iron Ore", 40 } })
    H.advance(2)
    H.httpRespond(1, false, 429, '{"error":"slow down"}', "http_status")
    t.ok(header().text:find("didn't answer"), header().text)
    H.advance(Toolbox.Prices.RETRY + 1)
    t.eq(#H.S.requests, 2, "retried")
    H.advance(Toolbox.Prices.TIMEOUT + 2)    -- never answered (a reload drops requests)
    t.eq(#H.S.requests, 3, "given up and sent again")
    H.httpRespond(3, true, 200, ANSWER)
    t.eq(row("Iron Ore")[3], "~200g")
    t.eq(H.httpRespond(2, true, 200, ANSWER), nil, "a late answer to an old request is ignored")
  end)

  t.test("not JSON: treated as a failure", function()
    withValues()
    H.items({ { "Iron Ore", 40 } })
    H.advance(2)
    H.httpRespond(1, true, 200, "<html>oops</html>")
    t.eq(row("Iron Ore")[3], "")
    t.ok(header().text:find("didn't answer"))
  end)

  t.test("the '(other items)' bucket is never looked up", function()
    withValues()
    local list = {}
    for i = 1, Toolbox.Daily.MAX_KINDS + 3 do list[#list + 1] = { "K" .. i, 1 } end
    H.items(list)
    H.advance(2)
    for _, name in ipairs(H.requestedItems(1)) do t.ok(name ~= Toolbox.Daily.OTHER) end
  end)

  t.test("values test: one lookup now, even with values off, each step in chat", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx dd values test")
    t.eq(#H.S.requests, 1)
    t.eq(H.requestedItems(1)[1], "Iron Ore", "the default item")
    t.ok(H.logged("asked SOTA.net for 'Iron Ore'"))
    H.httpRespond(1, true, 200, ANSWER)
    t.ok(H.logged("connected%. 'Iron Ore': ~5g each %(90%-day average%), 1,000 sold in 90 days, "
      .. "last sold 2026%-07%-26"))
    H.advance(Toolbox.Prices.GAP)
    H.chat("/tbx dd values test Rusty Nail")
    t.eq(H.requestedItems(2)[1], "Rusty Nail", "the name as typed")
    H.httpRespond(2, true, 200, '{"items":[],"missing":["Rusty Nail"]}')
    t.ok(H.logged("'Rusty Nail' has no sales on SOTA.net in the last 90 days"))
  end)

  t.test("values test: refusals and failures are explained", function()
    H.boot()
    H.S.httpRefuse = "not_permitted"
    H.clearLogs()
    H.chat("/tbx dd values test")
    t.ok(H.logged("refused the request: not_permitted %(switch Internet on for Toolbox in the add%-on manager%)"))
    H.S.httpRefuse = nil
    H.chat("/tbx dd values test")
    H.chat("/tbx dd values test")
    t.ok(H.logged("a lookup is already running"))
    H.httpRespond(1, false, 429, '{"error":"slow down"}', "http_status")
    t.ok(H.logged('failed, http_status %(HTTP 429%): {"error":"slow down"}'))
    H.advance(Toolbox.Prices.GAP)
    H.chat("/tbx dd values test")
    H.advance(Toolbox.Prices.TIMEOUT + 2)
    t.ok(H.logged("no answer after"))
    t.eq(#H.S.requests, 2, "a test that times out isn't sent again")
  end)

  t.test("the setting and the command follow each other; off hides the column", function()
    H.boot()
    H.chat("/tbx dd")
    H.chat("/tbx config")
    t.eq(H.config():Find("dd_values").value, false)
    H.change("toolbox_config", "dd_values", true)
    t.eq(H.saved("daily_detail").values, true)
    H.items({ { "Iron Ore", 40 } })
    H.advance(2)
    H.httpRespond(1, true, 200, ANSWER)
    t.eq(row("Iron Ore")[3], "~200g")
    H.chat("/tbx dd values off")
    t.eq(H.config():Find("dd_values").value, false)
    t.eq(H.detail():Find("list").children[1].children[3].visible, false)
    t.eq(header().visible, false)
  end)
end
