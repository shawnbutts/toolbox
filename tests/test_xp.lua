-- XP math: rates, rolling window, time to level, sample handling, formatting.
local H = require("harness")

return function(t)
  local function XP() H.boot(); return Toolbox.XP end

  t.test("new session gains nothing", function()
    local X = XP()
    local s = X.NewSession(0, 1000, 500, "A")
    t.eq(X.Gained(s, "a"), 0)
    t.eq(X.Gained(s, "p"), 0)
    t.ok(X.IsValid(s))
  end)

  t.test("gained is current total minus baseline", function()
    local X = XP()
    local s = X.NewSession(0, 1000, 500, "A")
    X.Record(s, 30, 1600, 700)
    t.eq(X.Gained(s, "a"), 600)
    t.eq(X.Gained(s, "p"), 200)
  end)

  t.test("per-hour rate", function()
    local X = XP()
    t.near(X.PerHour(1000, 1800), 2000)
    t.near(X.PerHour(50, 3600), 50)
    t.eq(X.PerHour(1000, 0), 0, "no time elapsed")
    t.eq(X.PerHour(1000, 0.5), 0, "under the minimum span")
  end)

  t.test("session rate uses the whole session", function()
    local X = XP()
    local s = X.NewSession(100, 0, 0, "A")
    X.Record(s, 200, 3000, 0)
    t.near(X.SessionRate(s, "a", 100 + 1800), 6000)   -- 3000 in half an hour
    t.eq(X.SessionRate(s, "p", 1900), 0)
  end)

  t.test("window rate equals session rate while the session is young", function()
    local X = XP()
    local s = X.NewSession(0, 0, 0, "A")
    X.Record(s, 60, 500, 0)
    X.Record(s, 240, 1200, 0)
    t.near(X.WindowRate(s, "a", 300), X.SessionRate(s, "a", 300))
    t.near(X.WindowRate(s, "a", 300), 1200 * 12)
  end)

  t.test("window rate forgets gains older than 10 minutes", function()
    local X = XP()
    local s = X.NewSession(0, 0, 0, "A")
    for sec = 10, 600, 10 do X.Record(s, sec, sec * 10, 0) end   -- 100 XP/s... 6000 in 10 min
    t.near(X.WindowRate(s, "a", 600), 6000 * 6)
    -- nothing more for 10 minutes
    for sec = 610, 1200, 10 do X.Record(s, sec, 6000, 0) end
    t.near(X.WindowRate(s, "a", 1200), 0)
    t.near(X.SessionRate(s, "a", 1200), 6000 * 3)
  end)

  t.test("window rate over a partially stale window", function()
    local X = XP()
    local s = X.NewSession(0, 0, 0, "A")
    X.Record(s, 100, 1000, 0)     -- before the window
    X.Record(s, 900, 1600, 0)     -- inside it
    -- window = [300, 900]: value at 300 is 1000, now 1600 -> 600 in 600 s
    t.near(X.WindowRate(s, "a", 900), 3600)
  end)

  t.test("samples closer than the bucket are merged", function()
    local X = XP()
    local s = X.NewSession(0, 0, 0, "A")
    X.Record(s, 20, 10, 0)
    X.Record(s, 21, 20, 0)
    X.Record(s, 25, 30, 0)
    t.eq(#s.samples, 2)
    t.eq(X.Current(s).a, 30)
    t.eq(X.Current(s).t, 20)
    X.Record(s, 31, 40, 0)
    t.eq(#s.samples, 3)
  end)

  t.test("a reading below the current total is ignored", function()
    local X = XP()
    local s = X.NewSession(0, 1000, 500, "A")
    X.Record(s, 20, 1500, 600)
    t.no(X.Record(s, 30, 0, 0), "bad read")
    t.eq(X.Gained(s, "a"), 500)
    t.eq(X.Gained(s, "p"), 100)
  end)

  t.test("unchanged readings add no samples", function()
    local X = XP()
    local s = X.NewSession(0, 1000, 500, "A")
    for sec = 1, 100 do t.no(X.Record(s, sec, 1000, 500)) end
    t.eq(#s.samples, 1)
  end)

  t.test("pruning keeps one anchor and bounds memory", function()
    local X = XP()
    local s = X.NewSession(0, 0, 0, "A")
    for sec = 1, 36000 do X.Record(s, sec, sec, 0) end    -- 10 hours of steady gains
    t.ok(#s.samples <= X.KEEP / X.BUCKET + 2, "samples: " .. #s.samples)
    t.ok(s.samples[1].t <= 36000 - X.KEEP, "anchor is at or before the oldest window start")
    t.ok(s.samples[1].t > 36000 - X.KEEP - X.BUCKET - 1, "nothing older than needed")
    t.near(X.WindowRate(s, "a", 36000), 3600, 3600 * 0.02)
    t.eq(X.Gained(s, "a"), 36000)
  end)

  t.test("next level: estimate", function()
    local X = XP()
    local p = { level = 10, intoLevel = 2000, forLevel = 10000, percent = 0.2 }
    local status, remaining, seconds = X.NextLevel(p, 8000)
    t.eq(status, "eta")
    t.eq(remaining, 8000)
    t.near(seconds, 3600)                        -- 8000 left at 8000/h
    t.near(select(3, X.NextLevel(p, 16000)), 1800)
    status = X.NextLevel({ intoLevel = 0, forLevel = 1000, percent = 0 }, 1000)
    seconds = select(3, X.NextLevel({ intoLevel = 0, forLevel = 1000, percent = 0 }, 1000))
    t.eq(status, "eta", "start of a level is not the cap")
    t.near(seconds, 3600)
  end)

  t.test("next level: no rate still reports XP needed", function()
    local X = XP()
    local p = { level = 10, intoLevel = 2000, forLevel = 10000, percent = 0.2 }
    local status, remaining, seconds = X.NextLevel(p, 0)
    t.eq(status, "norate")
    t.eq(remaining, 8000)
    t.eq(seconds, nil)
  end)

  t.test("next level: cap and unusable data", function()
    local X = XP()
    t.eq(X.NextLevel({ intoLevel = 500, forLevel = 1000, percent = 0 }, 100), "cap")
    t.eq(X.NextLevel(nil, 100), "unknown", "no data")
    t.eq(X.NextLevel({}, 100), "unknown", "empty side")
    t.eq(X.NextLevel({ intoLevel = 0, forLevel = 0, percent = 0 }, 100), "unknown", "no span")
    t.eq(X.NextLevel({ intoLevel = 1200, forLevel = 1000, percent = 0.9 }, 100), "unknown", "nothing left")
  end)

  t.test("saved session validation", function()
    local X = XP()
    t.ok(X.IsValid(X.NewSession(5, 1, 2, "A")))
    t.no(X.IsValid(nil))
    t.no(X.IsValid({}))
    t.no(X.IsValid({ v = 1, player = "A", start = 0, clock = 0, base = { a = 0 },
                     samples = { { t = 0, a = 0, p = 0 } } }), "missing base.p")
    local s = X.NewSession(5, 1, 2, "A")
    s.samples = {}
    t.no(X.IsValid(s), "no samples")
    s = X.NewSession(5, 1, 2, "A")
    s.samples[2] = { t = 1, a = 1, p = 2 }
    t.no(X.IsValid(s), "samples out of order")
    s = X.NewSession(5, 1, 2, "A")
    s.v = 99
    t.no(X.IsValid(s), "future format")
  end)

  t.test("number and duration formatting", function()
    H.boot()
    t.eq(Toolbox.FormatNumber(0), "0")
    t.eq(Toolbox.FormatNumber(999), "999")
    t.eq(Toolbox.FormatNumber(1000), "1,000")
    t.eq(Toolbox.FormatNumber(1234567.6), "1,234,568")
    t.eq(Toolbox.FormatNumber(-45000), "-45,000")
    t.eq(Toolbox.FormatDuration(7), "7s")
    t.eq(Toolbox.FormatDuration(65), "1m 05s")
    t.eq(Toolbox.FormatDuration(3723), "1h 02m 03s")
    t.eq(Toolbox.FormatDuration(-5), "0s")
    t.eq(Toolbox.FormatDuration(360000), "100h 00m 00s")
  end)
end
