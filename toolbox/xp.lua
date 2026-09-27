-- Toolbox: xp.lua
-- Session XP model. Pure functions over a plain-data session table, so it can be
-- stored with ShroudSetSavedVar and tested without the game.
--
-- session = {
--   v        = 1,                 -- format version
--   player   = "Name",            -- character the session belongs to
--   start    = <seconds>,         -- T.Now() when the session began
--   clock    = <seconds>,         -- T.Now() at the last save (detects client restarts)
--   base     = { a = n, p = n },  -- total adventurer / producer XP at the start
--   samples  = { { t = s, a = n, p = n }, ... },  -- ascending t; last one = current
--   ended    = true|nil,          -- set at logout
-- }
-- Samples are kept only for the rolling window (plus one anchor older than it).

local XP = {}
Toolbox.XP = XP

XP.FORMAT = 1
XP.WINDOW = 600        -- rolling window, seconds (10 minutes)
XP.BUCKET = 10         -- samples closer together than this are merged
XP.MIN_RATE_SPAN = 1   -- no rate is reported over less than this many seconds
XP.TRACKS = {
  { key = "a", name = "Adventurer", progress = "adventurer" },
  { key = "p", name = "Producer", progress = "producer" },
}

function XP.NewSession(now, adv, prod, player)
  return {
    v = XP.FORMAT,
    player = player,
    start = now,
    clock = now,
    base = { a = adv, p = prod },
    samples = { { t = now, a = adv, p = prod } },
  }
end

local function isNum(x) return type(x) == "number" and x == x end

-- Validates a table read back from saved vars.
function XP.IsValid(s)
  if type(s) ~= "table" or s.v ~= XP.FORMAT then return false end
  if not (isNum(s.start) and isNum(s.clock) and type(s.player) == "string") then return false end
  if type(s.base) ~= "table" or not (isNum(s.base.a) and isNum(s.base.p)) then return false end
  if type(s.samples) ~= "table" or #s.samples == 0 then return false end
  local prev = -math.huge
  for i = 1, #s.samples do
    local x = s.samples[i]
    if type(x) ~= "table" or not (isNum(x.t) and isNum(x.a) and isNum(x.p)) or x.t < prev then
      return false
    end
    prev = x.t
  end
  return true
end

function XP.Current(s)
  return s.samples[#s.samples]
end

-- Drops samples that are no longer needed for the window, keeping the newest
-- sample at or before the window start as the anchor.
function XP.Prune(s, now)
  local cutoff = now - XP.WINDOW
  local samples = s.samples
  while #samples >= 2 and samples[2].t <= cutoff do
    table.remove(samples, 1)
  end
end

-- Records a reading of the totals. Returns true when the session changed.
-- A reading lower than the current one is treated as a bad read (for example a
-- 0 during a scene change) and ignored; totals are not expected to go down.
function XP.Record(s, now, adv, prod)
  local cur = XP.Current(s)
  if adv < cur.a or prod < cur.p then return false end
  if adv == cur.a and prod == cur.p then
    XP.Prune(s, now)
    return false
  end
  if #s.samples >= 2 and now - cur.t < XP.BUCKET then
    cur.a, cur.p = adv, prod          -- merge into the recent sample, keep its time
  else
    s.samples[#s.samples + 1] = { t = now, a = adv, p = prod }
  end
  XP.Prune(s, now)
  return true
end

function XP.Elapsed(s, now)
  return math.max(0, now - s.start)
end

-- XP gained this session on one track ("a" or "p").
function XP.Gained(s, key)
  return math.max(0, XP.Current(s)[key] - s.base[key])
end

-- Amount over seconds, per hour. 0 for spans too short to mean anything.
function XP.PerHour(amount, seconds)
  if seconds < XP.MIN_RATE_SPAN then return 0 end
  return amount * 3600 / seconds
end

function XP.SessionRate(s, key, now)
  return XP.PerHour(XP.Gained(s, key), XP.Elapsed(s, now))
end

-- Rate over the last XP.WINDOW seconds (or the whole session while it is
-- younger than that). The value at the window start is the newest sample at or
-- before it; totals only change at samples.
function XP.WindowRate(s, key, now)
  local cutoff = now - XP.WINDOW
  local fromT, fromV
  if cutoff <= s.start then
    fromT, fromV = s.start, s.base[key]
  else
    fromT, fromV = cutoff, s.samples[1][key]
    for i = 1, #s.samples do
      local x = s.samples[i]
      if x.t > cutoff then break end
      fromV = x[key]
    end
  end
  local gained = math.max(0, XP.Current(s)[key] - fromV)
  return XP.PerHour(gained, now - fromT)
end

-- Seconds until the next level at ratePerHour, from one side of
-- ShroudGetLevelProgress() ({ level, experience, intoLevel, forLevel, percent }).
-- nil when it cannot be estimated (no rate, no data, or at the level cap).
function XP.TimeToLevel(progress, ratePerHour)
  if type(progress) ~= "table" then return nil end
  local into, span = progress.intoLevel, progress.forLevel
  if not (isNum(into) and isNum(span)) or span <= 0 then return nil end
  -- percent "reads 0 at the level cap"; 0% with XP into the level can only be the cap.
  if progress.percent == 0 and into > 0 then return nil end
  local remaining = span - into
  if remaining <= 0 or not isNum(ratePerHour) or ratePerHour <= 0 then return nil end
  return remaining / ratePerHour * 3600
end
