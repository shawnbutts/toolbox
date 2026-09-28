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
--   samples  = { { t = s, a = n, p = n, la = n, lp = n }, ... },  -- ascending t; last one = current;
--              la / lp: XP lost so far on that track (nil = 0), for the "net" views
--   ended    = true|nil,          -- set at logout
--   offset   = { a = n, p = n }|nil,  -- XP lost so far (added to readings: a loss isn't negative gain)
--   pending  = { a = t, p = t }|nil,  -- since when a track has read lower than recorded
-- }
-- Samples are kept only for the longest rolling window, XP.KEEP (plus one anchor older than it).

local XP = {}
Toolbox.XP = XP

XP.FORMAT = 1
XP.WINDOW = 600        -- rolling rate window, seconds (10 minutes)
XP.HOUR = 3600         -- "last hour" window, seconds
XP.KEEP = XP.HOUR      -- sample history kept: the longest window in use
XP.BUCKET = 10         -- samples closer together than this are merged
XP.MIN_RATE_SPAN = 1   -- no rate is reported over less than this many seconds
XP.DROP_CONFIRM = 5    -- seconds a lower total must hold before it is believed (XP lost, e.g. on death)
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
  if s.offset ~= nil and type(s.offset) ~= "table" then return false end
  if s.pending ~= nil and type(s.pending) ~= "table" then return false end
  local prev = -math.huge
  for i = 1, #s.samples do
    local x = s.samples[i]
    if type(x) ~= "table" or not (isNum(x.t) and isNum(x.a) and isNum(x.p)) or x.t < prev then
      return false
    end
    if (x.la ~= nil and not isNum(x.la)) or (x.lp ~= nil and not isNum(x.lp)) then return false end
    prev = x.t
  end
  return true
end

function XP.Current(s)
  return s.samples[#s.samples]
end

-- Drops samples that no window needs any more, keeping the newest sample at or
-- before the oldest window start as the anchor.
function XP.Prune(s, now)
  local cutoff = now - XP.KEEP
  local samples = s.samples
  while #samples >= 2 and samples[2].t <= cutoff do
    table.remove(samples, 1)
  end
end

-- A total that should only grow read lower than recorded. `pending` (the caller's table, by key)
-- remembers since when. True once it has stayed lower for XP.DROP_CONFIRM seconds: a real loss
-- (the adventurer total fell 943,678 in game, 2026-09-28, most likely a death); false while it may
-- be a bad read (a 0 while a scene loads). A reading of 0 or less is never believed.
function XP.ConfirmDrop(pending, key, value, now)
  if type(value) ~= "number" or value <= 0 then return false end
  local since = pending[key]
  if not since then
    pending[key] = now
    return false
  end
  if now - since < XP.DROP_CONFIRM then return false end
  pending[key] = nil
  return true
end

-- Records a reading of the totals. Returns true when the session changed. Each track on its
-- own: a lower reading is ignored until XP.ConfirmDrop believes it; then the session carries on
-- from it, the loss added to s.offset so it counts as no gain rather than negative gain.
-- (Before 2026-09-28 any lower reading was ignored, on both tracks, until the total climbed back:
-- after a death, all XP tracking froze.)
function XP.Record(s, now, adv, prod)
  local cur = XP.Current(s)
  s.offset = s.offset or {}
  s.pending = s.pending or {}
  local vals, changed = {}, false
  for _, key in ipairs({ "a", "p" }) do
    local v = (key == "a" and adv or prod) + (s.offset[key] or 0)
    if v >= cur[key] then
      s.pending[key] = nil
    elseif XP.ConfirmDrop(s.pending, key, v - (s.offset[key] or 0), now) then
      s.offset[key] = (s.offset[key] or 0) + (cur[key] - v)
      v, changed = cur[key], true
    else
      v = cur[key]
    end
    vals[key] = v
  end
  if vals.a == cur.a and vals.p == cur.p and not changed then
    XP.Prune(s, now)
    return false
  end
  local la, lp = s.offset.a or 0, s.offset.p or 0
  if #s.samples >= 2 and now - cur.t < XP.BUCKET then
    cur.a, cur.p, cur.la, cur.lp = vals.a, vals.p, la, lp   -- merge into the recent sample, keep its time
  else
    s.samples[#s.samples + 1] = { t = now, a = vals.a, p = vals.p, la = la, lp = lp }
  end
  XP.Prune(s, now)
  return true
end

-- XP lost so far on a track this session.
function XP.Lost(s, key)
  return type(s.offset) == "table" and s.offset[key] or 0
end

-- A track's reading as the session counts it (with XP lost so far added back).
function XP.Adjusted(s, key, raw)
  return raw + (type(s.offset) == "table" and s.offset[key] or 0)
end

function XP.Elapsed(s, now)
  return math.max(0, now - s.start)
end

-- XP gained this session on one track ("a" or "p"); with `net`, minus what was lost (can be < 0).
function XP.Gained(s, key, net)
  local gained = math.max(0, XP.Current(s)[key] - s.base[key])
  if net then return gained - XP.Lost(s, key) end
  return gained
end

-- Amount over seconds, per hour. 0 for spans too short to mean anything.
function XP.PerHour(amount, seconds)
  if seconds < XP.MIN_RATE_SPAN then return 0 end
  return amount * 3600 / seconds
end

function XP.SessionRate(s, key, now, net)
  return XP.PerHour(XP.Gained(s, key, net), XP.Elapsed(s, now))
end

-- XP gained on one track over the last `seconds` (at most XP.KEEP), and the
-- span it covers: the whole session while it is younger than that. The value at
-- the window start is the newest sample at or before it; totals only change at samples.
-- With `net`, XP lost within the window is subtracted (the result can be negative).
function XP.WindowGain(s, key, now, seconds, net)
  local lkey = "l" .. key
  local cutoff = now - seconds
  local fromT, fromV, fromL = nil, nil, 0
  if cutoff <= s.start then
    fromT, fromV = s.start, s.base[key]
  else
    fromT, fromV, fromL = cutoff, s.samples[1][key], s.samples[1][lkey] or 0
    for i = 1, #s.samples do
      local x = s.samples[i]
      if x.t > cutoff then break end
      fromV, fromL = x[key], x[lkey] or 0
    end
  end
  local gained = math.max(0, XP.Current(s)[key] - fromV)
  if net then gained = gained - ((XP.Current(s)[lkey] or 0) - fromL) end
  return gained, now - fromT
end

-- XP/hour over the last XP.WINDOW seconds (or the whole session while it is younger).
function XP.WindowRate(s, key, now, net)
  return XP.PerHour(XP.WindowGain(s, key, now, XP.WINDOW, net))
end

-- XP gained over the last hour (or the whole session while it is younger).
function XP.LastHour(s, key, now, net)
  return (XP.WindowGain(s, key, now, XP.HOUR, net))
end

-- "+1,234" / "-567": a gain, or with the net option a change, for display.
function XP.Signed(n)
  return (n >= 0 and "+" or "") .. Toolbox.FormatNumber(n)
end

-- Where the next level stands, from one side of ShroudGetLevelProgress()
-- ({ level, experience, intoLevel, forLevel, percent }) and an XP/hour rate.
-- Returns status, remaining XP, seconds:
--   "eta",     remaining, seconds  -- estimate available
--   "norate",  remaining, nil      -- XP still needed is known, but no XP gained to estimate from
--   "cap",     nil, nil            -- at the level cap
--   "unknown", nil, nil            -- no usable level data
function XP.NextLevel(progress, ratePerHour)
  if type(progress) ~= "table" then return "unknown" end
  local into, span = progress.intoLevel, progress.forLevel
  if not (isNum(into) and isNum(span)) or span <= 0 then return "unknown" end
  -- percent "reads 0 at the level cap"; 0% with XP into the level can only be the cap.
  if progress.percent == 0 and into > 0 then return "cap" end
  local remaining = span - into
  if remaining <= 0 then return "unknown" end
  if not isNum(ratePerHour) or ratePerHour <= 0 then return "norate", remaining end
  return "eta", remaining, remaining / ratePerHour * 3600
end
