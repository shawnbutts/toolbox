-- Toolbox: daily.lua
-- Daily stats (/toolbox daily): gold picked up, kills, and adventurer / producer XP
-- gained today. Resets at local midnight (see Toolbox.Today). Kept per character in
-- the saved var "daily", so it survives reloads and relogs on the same day.
--
-- day = {
--   v     = 1,
--   key   = "local:2026-09-27",   -- Toolbox.Today() key the counts belong to
--   gold  = n, kills = n, a = n, p = n,   -- today's counts
--   items = { [name] = n },  -- items gained today, by name (at most D.MAX_KINDS names)
--   dropped = n,             -- item kinds the game didn't itemise (past 20 in one call)
--   last  = { gold = n|nil, a = n|nil, p = n|nil },  -- last readings, to diff against
--   -- crafting and gathering (API 18 result events; added 2026-09-29, filled in for older days):
--   crafted  = { [name] = n },   -- products taken off a station: gained while a crafting window was open,
--                                -- and named like a recipe crafted today (D.IsProduct)
--   station  = { [name] = n },   -- other items gained at a station (materials taken back, salvage returns)
--   used     = { [name] = n },   -- materials the crafts used (ShroudGetRecipe's ingredients x attempts)
--   products = { [name] = true }, -- products named by craft results (`item`, API 24)
--   pending  = { [name] = n },   -- API 24: counted from a craft result (made, or left over) but not yet taken
--                                -- off the station; what is taken there uses this up instead of counting again
--   early    = { [name] = n },   -- taken off a station and counted by name before a craft result named it;
--                                -- a later API 24 result uses this up instead of counting again
--   gathered = { [name] = n },   -- what harvested nodes' loot windows held
--   recipes  = { [recipe] = { n = crafts, exc = n, fail = n } },   -- "Recipe: " removed from the name
--   craft    = { n = crafts, exc = n, fail = n, salvaged = n, xp = n, dropped = results not delivered },
--   gather   = { nodes = n, failed = n, xp = n, dropped = results not delivered },
--   skills   = n,              -- skill levels gained today (D.SkillGains)
--   deaths   = n,              -- times you died today (ShroudOnDeathChanged)
--   since    = nil or a copy of the counts above when the player pressed the Loot Tracker's Reset, plus
--              at = "HH:MM" (D.StartRun) and played = seconds of play since (D.Tick: only while logged in
--              with Toolbox running): the Loot Tracker shows the day minus it (D.RunOf) and rates per hour of
--              that play; gone at midnight
-- }
-- The loot list (Loot Tracker, "Looted") is `items` minus `crafted`, `station` and `gathered` (plus
-- `pending`, which isn't in `items` yet), per name, unless the player includes them.
-- What was made: from API 24 a craft result says it (`item` x `made`, and `items` = everything it put
-- out), counted at once. Before that (2026-09-29 in game: `item` = the recipe's name, no `made`) it is
-- counted as it reaches the bags at a station, by name (D.IsProduct).

local T = Toolbox
local D = {}
Toolbox.Daily = D

local UI = Shroud.UI
local WINDOW_ID = "toolbox_daily"
local GUTTER = 8
D.FORMAT = 1
D.MAX_KINDS = 250                 -- distinct item names kept per day (saved-var size)
D.OTHER = "(other items)"         -- where kinds past D.MAX_KINDS are counted

-- ---------------------------------------------------------------------------
-- Model (plain data, no API calls)
-- ---------------------------------------------------------------------------

D.MAX_RECIPES = 100               -- recipes kept per day

function D.New(key)
  return D.Upgrade({ v = D.FORMAT, key = key, gold = 0, kills = 0, a = 0, p = 0, items = {}, dropped = 0,
                     last = {} })
end

local function isCount(x) return type(x) == "number" and x == x and x >= 0 end

function D.IsValid(d)
  if type(d) ~= "table" or d.v ~= D.FORMAT or type(d.key) ~= "string" or type(d.last) ~= "table" then
    return false
  end
  for _, k in ipairs({ "gold", "kills", "a", "p" }) do
    if not isCount(d[k]) then return false end
  end
  -- items / dropped arrived after v1 shipped: absent is fine (D.Upgrade fills them in).
  if d.items ~= nil then
    if type(d.items) ~= "table" then return false end
    for name, n in pairs(d.items) do
      if type(name) ~= "string" or not isCount(n) then return false end
    end
  end
  if d.dropped ~= nil and not isCount(d.dropped) then return false end
  return true
end

-- A name -> count table from a save, keeping only valid entries (crafting fields: a bad entry is
-- dropped, not the whole day).
local function counts(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for name, n in pairs(t) do
    if type(name) == "string" and isCount(n) then out[name] = n end
  end
  return out
end

local function totals(t, keys)
  local out = {}
  for _, k in ipairs(keys) do
    local v = type(t) == "table" and t[k] or nil
    out[k] = isCount(v) and v or 0
  end
  return out
end

-- Fills in fields added after the first v1 saves (and cleans the crafting ones).
function D.Upgrade(d)
  d.items = d.items or {}
  d.dropped = d.dropped or 0
  d.crafted, d.gathered = counts(d.crafted), counts(d.gathered)
  d.station, d.used, d.pending = counts(d.station), counts(d.used), counts(d.pending)
  d.early = counts(d.early)
  local products = {}
  if type(d.products) == "table" then
    for name, v in pairs(d.products) do
      if type(name) == "string" and v == true then products[name] = true end
    end
  end
  d.products = products
  local recipes = {}
  if type(d.recipes) == "table" then
    for name, r in pairs(d.recipes) do
      if type(name) == "string" and type(r) == "table" then recipes[name] = totals(r, { "n", "exc", "fail" }) end
    end
  end
  d.recipes = recipes
  d.skills = isCount(d.skills) and d.skills or 0
  d.deaths = isCount(d.deaths) and d.deaths or 0
  d.craft = totals(d.craft, { "n", "exc", "fail", "salvaged", "xp", "dropped" })
  d.gather = totals(d.gather, { "nodes", "failed", "xp", "dropped" })
  return d
end

-- Adds `qty` of `name` to a name -> count table, capped at D.MAX_KINDS names (the rest go to D.OTHER).
local function addCount(t, name, qty)
  if t[name] == nil then
    local kinds = 0
    for _ in pairs(t) do kinds = kinds + 1 end
    if kinds >= D.MAX_KINDS then name = D.OTHER end
  end
  t[name] = (t[name] or 0) + qty
end

-- A recipe's name as a row shows it: "Recipe: Crimson Pine Board" -> "Crimson Pine Board". Nothing
-- more is guessed (item names can have brackets too: "Hopper (Bait)").
function D.RecipeName(name)
  if type(name) ~= "string" then return nil end
  if name:sub(1, 8) == "Recipe: " then name = name:sub(9) end
  return name ~= "" and name or nil
end

local function num(r, k)
  local v = T.Field(r, k)
  return isCount(v) and v or 0
end

-- Whether `name` is the product of a recipe crafted today: the recipe's name, or the recipe's name with
-- a station in brackets ("Crimson Pine Binding" for "Crimson Pine Binding (Milling)"). In game
-- (2026-09-29) both products seen were named that way. A material returned to the bags isn't.
function D.IsProduct(d, name)
  if type(name) ~= "string" or name == "" then return false end
  if d.recipes[name] or d.products[name] then return true end
  local prefix = name .. " ("
  for recipe in pairs(d.recipes) do
    if recipe:sub(1, #prefix) == prefix then return true end
  end
  return false
end

-- Moves items counted as made that aren't named like a crafted recipe to `station` (days recorded
-- before that rule counted materials taken back off a station as made; owner, 2026-09-29).
function D.Reclassify(d)
  for name, n in pairs(d.crafted) do
    if not D.IsProduct(d, name) then
      d.station[name] = (d.station[name] or 0) + n
      d.crafted[name] = nil
    end
  end
end

-- Adds the materials one result used: each ingredient that isn't a tool or optional, times the crafts
-- attempted. `getRecipe(id)` is ShroudGetRecipe (or nil without it).
local function addUsed(d, r, getRecipe)
  local id = T.Field(r, "recipeId")
  if type(getRecipe) ~= "function" or type(id) ~= "number" then return end
  local ok, recipe = pcall(getRecipe, id)
  if not ok or recipe == nil then return end
  local attempts = num(r, "quantity")
  if attempts == 0 then attempts = num(r, "crafted") + num(r, "failed") end
  for _, ing in ipairs(T.List(T.Field(recipe, "ingredients"))) do
    local name, per = T.Field(ing, "name"), T.Field(ing, "quantity")
    if type(name) == "string" and isCount(per) and per > 0 and T.Field(ing, "tool") ~= true
        and T.Field(ing, "optional") ~= true then
      addCount(d.used, name, per * attempts)
    end
  end
end

-- API 24: what one craft result put out, counted at once. `item` x `made` is what was made; the rest of
-- `items` (leftovers such as an empty vial) goes to `station`, and so do other names in `items` unless the
-- recipe's fixed yield (`ShroudGetRecipe(id).results`) names them as products. All of it is also `pending`
-- until taken off the station (D.AddItems).
local function markProduct(d, name)
  if d.products[name] then return end
  local n = 0
  for _ in pairs(d.products) do n = n + 1 end
  if n < D.MAX_RECIPES then d.products[name] = true end
end

-- Counts `qty` of `name` from a craft result as made (`product`) or not, unless it was already taken off
-- the station and counted by name (`early`): then only moves it to made if the name rule had it apart.
local function place(d, name, qty, product)
  local seen = math.min(qty, d.early[name] or 0)
  if seen > 0 then
    d.early[name] = d.early[name] > seen and d.early[name] - seen or nil
    local wrong = product and math.min(seen, d.station[name] or 0) or 0
    if wrong > 0 then
      d.station[name] = d.station[name] > wrong and d.station[name] - wrong or nil
      addCount(d.crafted, name, wrong)
    end
  end
  local rest = qty - seen
  if rest > 0 then
    addCount(product and d.crafted or d.station, name, rest)
    addCount(d.pending, name, rest)
  end
  if product then markProduct(d, name) end
end

local function addMade(d, r, getRecipe, made)
  local item = T.Field(r, "item")
  local products = {}
  if type(item) == "string" and item ~= "" then products[item] = true end
  local id = T.Field(r, "recipeId")
  if type(getRecipe) == "function" and type(id) == "number" then
    local ok, recipe = pcall(getRecipe, id)
    if ok and recipe ~= nil then
      for _, res in ipairs(T.List(T.Field(recipe, "results"))) do
        local name = T.Field(res, "name")
        if type(name) == "string" and name ~= "" then products[name] = true end
      end
    end
  end
  local left = made                    -- product items still to place (made, from `items` or else `item`)
  local listed = false
  for _, it in ipairs(T.List(T.Field(r, "items"))) do
    local name, qty = T.Field(it, "name"), T.Field(it, "quantity")
    if type(name) == "string" and name ~= "" and isCount(qty) and qty > 0 then
      listed = true
      if products[name] then
        place(d, name, qty, true)               -- a product (even past `made`: trust the list)
        left = math.max(0, left - qty)
      else
        place(d, name, qty, false)
      end
    end
  end
  if not listed and left > 0 and type(item) == "string" and item ~= "" then place(d, item, left, true) end
end

-- Adds one ShroudOnCraftResults batch (results may be game objects). `getRecipe`: ShroudGetRecipe, for
-- the materials used and (API 24) the fixed yield. `dropped`: results past the 20 one call carries.
-- Returns true when counted.
function D.AddCraftResults(d, results, getRecipe, dropped)
  local changed = false
  if isCount(dropped) and dropped > 0 then
    d.craft.dropped = d.craft.dropped + dropped
    changed = true
  end
  for _, r in ipairs(T.List(results)) do
    local kind = T.Field(r, "kind")
    if kind == "salvage" then
      d.craft.salvaged = d.craft.salvaged + math.max(1, num(r, "quantity"))   -- returns counted as they arrive
      d.craft.xp = d.craft.xp + num(r, "experience")
      changed = true
    elseif kind == "craft" or kind == "refine" then
      local made, exc, fail = num(r, "crafted"), num(r, "exceptional"), num(r, "failed")
      d.craft.n, d.craft.exc, d.craft.fail = d.craft.n + made, d.craft.exc + exc, d.craft.fail + fail
      d.craft.xp = d.craft.xp + num(r, "experience")
      local name = D.RecipeName(T.Field(r, "recipeName")) or D.RecipeName(T.Field(r, "item"))
      if name then
        local rec = d.recipes[name]
        if not rec then
          local n = 0
          for _ in pairs(d.recipes) do n = n + 1 end
          if n < D.MAX_RECIPES then
            rec = { n = 0, exc = 0, fail = 0 }
            d.recipes[name] = rec
          end
        end
        if rec then rec.n, rec.exc, rec.fail = rec.n + made, rec.exc + exc, rec.fail + fail end
      end
      addUsed(d, r, getRecipe)
      local itemsMade = T.Field(r, "made")
      if isCount(itemsMade) then addMade(d, r, getRecipe, itemsMade) end
      -- `item` names what was made from API 24 (before, the recipe's name: "Recipe: ..."). It marks that
      -- item as a product for items taken off a station beyond what the results counted.
      local item = T.Field(r, "item")
      if type(item) == "string" and item ~= "" and item:sub(1, 8) ~= "Recipe: " and item ~= T.Field(r, "recipeName")
          and not d.products[item] then
        local n = 0
        for _ in pairs(d.products) do n = n + 1 end
        if n < D.MAX_RECIPES then d.products[item] = true end
      end
      changed = true
    end
  end
  return changed
end

-- Adds one ShroudOnGatherResults batch. `dropped`: results past the 20 one call carries. Returns true
-- when counted.
function D.AddGatherResults(d, results, dropped)
  local changed = false
  if isCount(dropped) and dropped > 0 then
    d.gather.dropped = d.gather.dropped + dropped
    changed = true
  end
  for _, r in ipairs(T.List(results)) do
    d.gather.nodes = d.gather.nodes + 1
    if T.Field(r, "failed") == true then d.gather.failed = d.gather.failed + 1 end
    d.gather.xp = d.gather.xp + num(r, "experience")
    for _, it in ipairs(T.List(T.Field(r, "items"))) do
      local name, qty = T.Field(it, "name"), T.Field(it, "quantity")
      if type(name) == "string" and name ~= "" and isCount(qty) and qty > 0 then addCount(d.gathered, name, qty) end
    end
    changed = true
  end
  return changed
end

-- The looted count of `name`: gained, less what was made, came off a station or was gathered (never
-- below 0). What a craft result counted but is still on the table (`pending`) isn't in `items` yet.
function D.Looted(d, name)
  local n = (d.items[name] or 0) - (d.crafted[name] or 0) - (d.station[name] or 0) - (d.gathered[name] or 0)
    + (d.pending[name] or 0)
  return n > 0 and n or 0
end

-- Adds one ShroudOnItemsGained batch. `atStation`: a crafting window is open, so the items came off a
-- station: counted as made when named like a recipe crafted today, otherwise as other station items
-- (materials taken back, salvage returns). Returns true when anything was counted.
function D.AddItems(d, items, dropped, atStation)
  local changed = false
  for _, item in ipairs(type(items) == "table" and items or {}) do
    local name, qty = type(item) == "table" and item.name, type(item) == "table" and item.quantity
    if type(name) == "string" and name ~= "" and isCount(qty) and qty > 0 then
      addCount(d.items, name, qty)
      if atStation then
        -- first what a craft result already counted (API 24), then the name rule for the rest
        local ahead = d.pending[name] or 0
        local rest = qty - math.min(qty, ahead)
        if ahead > 0 then d.pending[name] = ahead > qty and ahead - qty or nil end
        if rest > 0 then
          if D.IsProduct(d, name) then addCount(d.crafted, name, rest) else addCount(d.station, name, rest) end
          addCount(d.early, name, rest)
        end
      end
      changed = true
    end
  end
  if isCount(dropped) and dropped > 0 then
    d.dropped = d.dropped + dropped
    changed = true
  end
  return changed
end

-- Item names sorted by count (highest first), then name.
function D.SortedItems(d)
  local names = {}
  for name in pairs(d.items) do names[#names + 1] = name end
  table.sort(names, function(x, y)
    if d.items[x] ~= d.items[y] then return d.items[x] > d.items[y] end
    return x < y
  end)
  return names
end

-- Starts a new day when the key changed. Keeps the last readings so gains
-- that straddle midnight land on the new day. Returns true when it rolled over.
function D.Roll(d, key)
  if key == nil or d.key == key then return false end
  d.key, d.gold, d.kills, d.a, d.p = key, 0, 0, 0, 0
  d.items, d.dropped, d.la, d.lp = {}, 0, 0, 0
  d.crafted, d.gathered, d.recipes, d.craft, d.gather = {}, {}, {}, nil, nil
  d.station, d.used, d.products, d.pending, d.early = {}, {}, {}, {}, {}
  d.skills, d.deaths = 0, 0
  d.since = nil                      -- a run doesn't outlast its day
  D.Upgrade(d)                       -- zeroed craft and gather totals
  return true
end

-- ---------------------------------------------------------------------------
-- A run (owner, 2026-10-04: "some want to reset it every combat run"): the Loot Tracker's Reset counts from
-- now without losing the day. `since` is a copy of the counts at that moment; the tracker shows the day minus
-- it, so the Today window keeps the whole day and "Show all of today" undoes it.
-- ---------------------------------------------------------------------------
D.RUN_KEEP = { v = true, key = true, last = true, la = true, lp = true, since = true, products = true }

local function minus(cur, base)
  if type(cur) == "number" then
    local n = cur - (type(base) == "number" and base or 0)
    if n < 0 then n = 0 end
    return n
  end
  if type(cur) ~= "table" then return cur end
  local out = {}
  for k, v in pairs(cur) do
    local n = minus(v, type(base) == "table" and base[k] or nil)
    -- a name with nothing since the reset isn't listed (nor a recipe not crafted since)
    if n ~= 0 and not (type(n) == "table" and next(n) == nil) then out[k] = n end
  end
  return out
end

-- Starts a run on day `d` now; `at` labels it ("HH:MM").
function D.StartRun(d, at)
  local snap = {}
  for k, v in pairs(d) do
    if not D.RUN_KEEP[k] then snap[k] = T.Copy(v) end
  end
  snap.at, snap.played = at, 0
  d.since = snap
end

-- Starts a run on today's counts now (the Loot Tracker's Reset), or ends it (Show all of today).
function D.ResetRun()
  if not D.day then return false end
  D.FileRun(D.day)                     -- the run that ends here goes into the history
  D.StartRun(D.day, T.ClockText())
  D.itemsVersion = D.itemsVersion + 1  -- the Loot Tracker redraws
  D.Save()
  return true
end

function D.EndRun()
  if not (D.day and D.day.since) then return false end
  D.FileRun(D.day)
  D.day.since = nil
  D.itemsVersion = D.itemsVersion + 1
  D.Save()
  return true
end

-- Seconds played since the Loot Tracker's reset, or nil for the whole day.
function D.RunPlayed()
  local s = D.day and D.day.since
  if type(s) ~= "table" then return nil end
  return s.played or 0
end

-- "47m", "1h 12m" (whole minutes).
function D.Duration(seconds)
  local m = math.floor((seconds or 0) / 60)
  if m < 1 then return "<1m" end
  if m < 60 then return m .. "m" end
  return math.floor(m / 60) .. "h " .. (m % 60) .. "m"
end

-- `n` an hour over `seconds` of play, or nil under D.RATE_AFTER (a first drop would read as thousands an hour).
D.RATE_AFTER = 60
function D.PerHour(n, seconds)
  if type(n) ~= "number" or type(seconds) ~= "number" or seconds < D.RATE_AFTER then return nil end
  return n * 3600 / seconds
end

-- "14:32" when the Loot Tracker counts from a reset, "" when it was reset with no clock, nil for the whole day.
function D.RunStart()
  local s = D.day and D.day.since
  if type(s) ~= "table" then return nil end
  return type(s.at) == "string" and s.at or ""
end

-- ---------------------------------------------------------------------------
-- Run history (owner, 2026-10-07): a run ending (Reset again, Show all of today, midnight) is filed with its
-- numbers, the last D.RUNS_KEEP per character, newest first, for comparing farming spots. Saved var
-- "loot_runs" = { v = 1, list = { { at = "HH:MM", date = "YYYY-MM-DD", scene, played = s, gold, kills, items,
-- kinds, nodes, value = estimated gold or nil, spot = { scene, raw, x, y, z } or nil (where it was played most) } } }.
-- A run under D.RUN_MIN s of play isn't kept.
-- ---------------------------------------------------------------------------
D.RUNS_KEEP, D.RUN_MIN = 10, 60
D.runsVersion = 0
local runs, runsFor = nil, nil

local function isRun(r)
  return type(r) == "table" and isCount(r.played) and isCount(r.gold) and isCount(r.kills)
end

-- This character's filed runs, newest first (read once per character).
function D.Runs()
  local who = T.PlayerName()
  if runs and runsFor == who then return runs end
  runs, runsFor = {}, who
  local saved = T.ReadSaved("loot_runs")
  if type(saved) == "table" and saved.v == 1 and type(saved.list) == "table" then
    for _, r in ipairs(saved.list) do
      if isRun(r) and #runs < D.RUNS_KEEP then runs[#runs + 1] = r end
    end
  end
  return runs
end

-- The scene a run spent most of its play in, or "".
local function mainScene(s)
  local best, most = "", -1
  for name, secs in pairs(type(s.scenes) == "table" and s.scenes or {}) do
    if type(name) == "string" and type(secs) == "number" and secs > most then best, most = name, secs end
  end
  return best
end

-- Files the run on day `d` (when it has lasted D.RUN_MIN s of play). Its estimated value comes from the Loot
-- Tracker's prices, when they're on (Toolbox.DailyDetail.RunValue).
function D.FileRun(d)
  local s = d and d.since
  if type(s) ~= "table" or not isCount(s.played) or s.played < D.RUN_MIN then return false end
  local run = D.RunOf(d)
  local items, kinds = 0, 0
  for _, n in pairs(run.items or {}) do
    items, kinds = items + n, kinds + 1
  end
  local value = nil
  local DD = T.DailyDetail
  if DD and DD.RunValue then value = DD.RunValue(run) end
  local date = tostring(d.key or ""):match("(%d+%-%d+%-%d+)") or ""
  local entry = { at = type(s.at) == "string" and s.at or "", date = date,
                  scene = mainScene(s), played = math.floor(s.played), gold = run.gold or 0, kills = run.kills or 0,
                  items = items, kinds = kinds, nodes = (run.gather and run.gather.nodes) or 0, value = value }
  entry.spot = D.MainSpot(s, entry.scene)
  local list = D.Runs()
  table.insert(list, 1, entry)
  while #list > D.RUNS_KEEP do list[#list] = nil end
  T.Save("loot_runs", { v = 1, list = list })
  D.runsVersion = D.runsVersion + 1
  return true
end

-- A new day: the run in progress is filed first (D.Roll drops it).
function D.RollDay(key)
  if D.day and D.day.since and key ~= nil and D.day.key ~= key then D.FileRun(D.day) end
  return D.Roll(D.day, key)
end

-- The day as the Loot Tracker shows it: since the run started, or the whole day.
function D.RunOf(d)
  if type(d) ~= "table" or type(d.since) ~= "table" then return d end
  local out = {}
  for k, v in pairs(d) do
    if k ~= "since" then
      if D.RUN_KEEP[k] then out[k] = v else out[k] = minus(v, d.since[k]) end
    end
  end
  for k, v in pairs(d) do              -- counts read as plain numbers stay numbers (0, not absent)
    if type(v) == "number" and out[k] == nil then out[k] = 0 end
  end
  D.Upgrade(out)                       -- every table the views read, even when empty
  return out
end

-- XP totals: only increases count. A lower reading is a bad read (a 0 while a scene loads)
-- until Toolbox.XP.ConfirmDrop believes it (it held for a few seconds: XP lost, e.g. on death);
-- then counting carries on from it. Before 2026-09-28 a real loss stopped the count until the
-- total climbed back.
local pending = {}     -- per track: since when a lower total has held (not saved)

local function observeTrack(d, key, v, now)
  local last = d.last[key]
  if last == nil or v > last then
    if last ~= nil then d[key] = d[key] + (v - last) end
    d.last[key], pending[key] = v, nil
    return true
  end
  if v == last then
    pending[key] = nil
    return false
  end
  if T.XP.ConfirmDrop(pending, key, v, now) then
    d["l" .. key] = (d["l" .. key] or 0) + (last - v)   -- a loss (shown only with the net option)
    d.last[key] = v                  -- count on from here, nothing subtracted
    return true
  end
  return false
end

-- Today's XP on a track as shown: gains, or with the net option (Toolbox.Window.GetNet) gains
-- minus losses (d.la / d.lp), which can be negative.
function D.XPToday(d, key)
  local gained = d[key] or 0
  if T.Window.GetNet() then return gained - (d["l" .. key] or 0) end
  return gained
end

function D.ObserveXP(d, adv, prod, now)
  now = now or T.Now()
  local a = observeTrack(d, "a", adv, now)
  local p = observeTrack(d, "p", prod, now)
  return a or p
end

-- Gold: every increase counts (the API has no "picked up" event, so vendor sales,
-- trades and mail count too). Spending lowers the baseline without counting. A read
-- of exactly 0 from a positive balance is ignored as a bad read.
function D.ObserveGold(d, gold)
  local last = d.last.gold
  if last == nil then
    d.last.gold = gold
    return true
  end
  if gold == last or (gold == 0 and last > 0) then return false end
  if gold > last then d.gold = d.gold + (gold - last) end
  d.last.gold = gold
  return true
end

-- Sets the baselines to the current readings, so changes while the add-on wasn't
-- running (gold from a player vendor while logged out) don't count.
function D.Rebase(d, adv, prod, gold)
  d.last.a, d.last.p = adv, prod
  pending = {}
  d.last.gold = (type(gold) == "number" and gold >= 0) and gold or nil
end

-- A kill is a combat "death" line dealt by you or your pet (and not about you or it).
function D.IsKill(e)
  return type(e) == "table" and e.kind == "death"
    and (e.fromYou == true or e.fromYourPet == true)
    and e.toYou ~= true and e.toYourPet ~= true
end

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------

D.day = nil
D.unsaved = false
D.source = nil      -- "local" | "utc" | nil (from Toolbox.Today)
D.label = nil       -- date shown in the window

local function today()
  local key, label, source = T.Today()
  D.source, D.label = source, label
  return key
end

function D.ReadDay()
  D.dayFor = T.PlayerName()     -- whose day D.day is
  local saved = T.ReadSaved("daily")
  local key = today()
  if D.IsValid(saved) then
    D.day = D.Upgrade(saved)
    if type(D.day.since) ~= "table" then D.day.since = nil end
    if D.day.since and not isCount(D.day.since.played) then D.day.since.played = 0 end
    D.Reclassify(D.day)
  else
    D.day = D.New(key or "none")
  end
  if D.RollDay(key) then D.unsaved = true end
end

function D.Save()
  if not D.day then return end
  T.Save("daily", D.day)
  D.unsaved = false
  T.unflushed = true          -- written to disk with the session's periodic flush
end

-- Called with fresh totals by Toolbox.Sample (every tick and on XP gain).
function D.ObserveTotals(adv, prod)
  if not D.day then return end
  if D.ObserveXP(D.day, adv, prod) then D.unsaved = true end
end

-- A run's play time: the time between ticks while a character is in the world. A longer gap than D.PLAY_GAP
-- (a reload, a loading screen, the game closed) isn't counted. Saved every D.PLAY_SAVE s of play, not every
-- tick (the day is a big table to copy).
D.PLAY_GAP, D.PLAY_SAVE = 10, 30
local lastPlayAt = nil

D.SCENES_MAX = 20                    -- scenes a run keeps play time for (its place: the one played most)

-- Where a run was played (owner, 2026-10-08): play time per D.SPOT_CELL square of ground, keyed by the scene's
-- internal name and the square, with the time-weighted sum of the positions in it. A run's spot is the middle of
-- its most-played square (in its most-played scene). At most D.SPOTS_MAX squares: past that a new square takes
-- the place of the least-played one and starts from its time (the busiest squares stay; a route can't push out
-- the farming spot). since.spots = { ["<raw scene>|cx|cz"] = { s = scene name, r = raw scene, t = seconds,
-- w = seconds here, x, y, z = position x seconds } }.
D.SPOT_CELL, D.SPOTS_MAX = 40, 40

local function playerPos()
  local x, y, z = ShroudPlayerX, ShroudPlayerY, ShroudPlayerZ
  if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
  if x ~= x or y ~= y or z ~= z or math.abs(x) > 100000 or math.abs(y) > 100000 or math.abs(z) > 100000 then
    return nil
  end
  return x, y, z
end

local function countSpot(s, scene, dt)
  local okRaw, raw = pcall(T.SceneRaw)
  local x, y, z = playerPos()
  if not (okRaw and type(raw) == "string" and raw ~= "" and x) then return end
  if type(s.spots) ~= "table" then s.spots = {} end
  local key = raw .. "|" .. math.floor(x / D.SPOT_CELL) .. "|" .. math.floor(z / D.SPOT_CELL)
  local cell = s.spots[key]
  if type(cell) == "table" and not (type(cell.t) == "number" and type(cell.w) == "number"
      and type(cell.x) == "number" and type(cell.y) == "number" and type(cell.z) == "number") then
    s.spots[key], cell = nil, nil      -- (a damaged save)
  end
  if cell == nil then
    local n, leastKey, least = 0, nil, nil
    for k, c in pairs(s.spots) do
      n = n + 1
      local ct = type(c) == "table" and type(c.t) == "number" and c.t or 0
      if least == nil or ct < least then leastKey, least = k, ct end
    end
    local start = 0
    if n >= D.SPOTS_MAX then
      s.spots[leastKey] = nil
      start = least
    end
    cell = { s = scene, r = raw, t = start, w = 0, x = 0, y = 0, z = 0 }
    s.spots[key] = cell
  end
  cell.t, cell.w = cell.t + dt, cell.w + dt
  cell.x, cell.y, cell.z = cell.x + x * dt, cell.y + y * dt, cell.z + z * dt
end

-- The run's spot: { scene, raw, x, y, z } in scene `main` (else anywhere), or nil.
local function mainSpot(s, main)
  local best, bestIn = nil, nil
  for _, c in pairs(type(s.spots) == "table" and s.spots or {}) do
    if type(c) == "table" and type(c.t) == "number" and type(c.w) == "number" and c.w > 0
        and type(c.x) == "number" and type(c.y) == "number" and type(c.z) == "number"
        and type(c.r) == "string" and c.r ~= "" then
      if not best or c.t > best.t then best = c end
      if c.s == main and (not bestIn or c.t > bestIn.t) then bestIn = c end
    end
  end
  local c = bestIn or best
  if not c then return nil end
  local function round(v) return math.floor(v / c.w * 100 + 0.5) / 100 end
  return { scene = type(c.s) == "string" and c.s or "", raw = c.r, x = round(c.x), y = round(c.y),
           z = round(c.z) }
end
D.MainSpot = mainSpot

local function countPlay(hasCharacter)
  local s = D.day.since
  local now = T.Now()
  if type(s) == "table" and hasCharacter and lastPlayAt then
    local dt = now - lastPlayAt
    if dt > 0 and dt <= D.PLAY_GAP then
      local before = math.floor((s.played or 0) / D.PLAY_SAVE)
      s.played = (s.played or 0) + dt
      if math.floor(s.played / D.PLAY_SAVE) ~= before then D.unsaved = true end
      local okScene, scene = pcall(T.SceneName)
      if okScene and type(scene) == "string" and scene ~= "" then
        if type(s.scenes) ~= "table" then s.scenes = {} end
        local n = 0
        for _ in pairs(s.scenes) do n = n + 1 end
        if s.scenes[scene] or n < D.SCENES_MAX then s.scenes[scene] = (s.scenes[scene] or 0) + dt end
        countSpot(s, scene, dt)
      end
    end
  end
  if hasCharacter then lastPlayAt = now else lastPlayAt = nil end
end

-- Once a tick, from Toolbox.Tick: day rollover, gold, a run's play time, and storing changes.
function D.Tick(hasCharacter)
  if not D.day then return end
  if D.RollDay(today()) then D.unsaved = true end
  countPlay(hasCharacter)
  if hasCharacter then
    local gold = ShroudPlayerGold
    if type(gold) == "number" and gold >= 0 and D.ObserveGold(D.day, gold) then D.unsaved = true end
  end
  -- A changed day is stored with the next flush (T.Tick: D.SaveIfChanged), not each tick: each store copied and
  -- checked the whole day, about 23 ms in game, every 2 s while crafting (the owner's timed /toolbox perf,
  -- 2026-10-14: 20 of the tick's 21 slow runs).
  if D.unsaved then T.unflushed = true end
end

-- Stores the day if it changed since it was last stored (before a flush).
function D.SaveIfChanged()
  if D.unsaved then D.Save() end
end

-- A new login or character (not a reload), with that character's current totals:
-- load its day and start counting from now.
function D.OnLogin(adv, prod)
  -- Already this character's (loaded at its scene, before its totals came): keep what it counted since.
  if D.day and D.dayFor == T.PlayerName() then
    if D.RollDay(today()) then D.unsaved = true end
  else
    D.ReadDay()
  end
  D.skillHigh = nil                    -- another character's skills, or read again: start from its save
  D.Rebase(D.day, adv, prod, ShroudPlayerGold)
  D.unsaved = true
end

-- Bumped whenever today's items change, so Loot Tracker redraws its list only then.
D.itemsVersion = 0

-- A crafting window is open (ShroudOnCraftingStateChanged; read at start where the client has it).
D.stationOpen = false

-- Whether this client reports crafting and gathering results (API 18). The result callbacks can't be
-- probed, so this goes by the crafting getter the same group added.
function D.HasResults() return type(ShroudGetCraftingState) == "function" end

local function changed()
  D.unsaved = true
  D.itemsVersion = D.itemsVersion + 1
end

-- ---------------------------------------------------------------------------
-- Skill levels gained and deaths (shown in the Today window and XP Detailed)
-- ---------------------------------------------------------------------------
-- A skill level counts when a skill's trainedLevel (the level your experience bought; a scene's skill cap
-- doesn't change it) rises above the highest seen for it on this character (saved var "skill_levels":
-- { v = 1, high = { [skill key] = level } }). So unlearning and relearning doesn't count twice. A skill
-- seen for the first time only sets its starting point (the sheet may load in parts at login), and so does
-- the very first reading. Both the day (D.day.skills) and the XP session (T.session.skills) count them.

D.skillHigh = nil          -- skill key -> highest trainedLevel seen; nil until read

-- Pure: adds the rises in `skills` (entries { key, level }) over `high` to it, and returns how many
-- levels were gained. Unknown keys set their starting point only.
function D.SkillGains(high, skills)
  local gained = 0
  for _, sk in ipairs(skills) do
    local was = high[sk.key]
    if was == nil then
      high[sk.key] = sk.level
    elseif sk.level > was then
      gained = gained + (sk.level - was)
      high[sk.key] = sk.level
    end
  end
  return gained
end

-- ShroudGetSkills as { key, level } (game objects read by field).
local function readSkills()
  if type(ShroudGetSkills) ~= "function" then return nil end
  local ok, list = pcall(ShroudGetSkills)
  if not ok or list == nil then return nil end
  local out = {}
  for _, sk in ipairs(T.List(list)) do
    local key = T.Field(sk, "key")
    if type(key) ~= "string" or key == "" then key = tostring(T.Field(sk, "id")) end
    local level = T.Field(sk, "trainedLevel")
    if type(level) == "number" and level >= 0 and key ~= "nil" then out[#out + 1] = { key = key, level = level } end
  end
  return out
end

-- Reads the skills and counts levels gained. At start and on ShroudOnSkillsChanged(levelsChanged).
function D.OnSkills(levelsChanged)
  if levelsChanged == false then return end          -- experience only
  local skills = readSkills()
  if not skills or #skills == 0 then return end
  local first = D.skillHigh == nil
  if first then
    local saved = T.ReadSaved("skill_levels")
    D.skillHigh = {}
    if type(saved) == "table" and saved.v == 1 and type(saved.high) == "table" then
      for k, v in pairs(saved.high) do
        if type(k) == "string" and isCount(v) then D.skillHigh[k] = v end
      end
    end
  end
  local gained = D.SkillGains(D.skillHigh, skills)
  if gained > 0 then
    if D.day then
      D.day.skills = D.day.skills + gained
      changed()
    end
    if T.session then
      T.session.skills = (T.session.skills or 0) + gained
      T.SaveSession(false)             -- rare: stored now (else at the next flush)
    end
  end
  if gained > 0 or first then T.Save("skill_levels", { v = 1, high = D.skillHigh }) end
end

-- ShroudOnDeathChanged: one more death today and this session.
function D.OnDeath(isDead)
  if isDead ~= true then return end
  if D.day then
    D.day.deaths = D.day.deaths + 1
    changed()
  end
  if T.session then
    T.session.deaths = (T.session.deaths or 0) + 1
    T.SaveSession(false)             -- rare: stored now (else at the next flush)
  end
end

-- The latest item events as the game sent them, for /toolbox loot log (owner, 2026-10-08: 2 sharks counted as 4).
-- Memory only, at most D.ITEM_LOG_MAX, newest last: { at = "HH:MM (game seconds)", text, station }.
D.ITEM_LOG_MAX = 20
D.itemLog = {}

function D.NoteItems(items, dropped)
  local parts = {}
  for _, item in ipairs(T.List(items)) do
    local name, qty = T.Field(item, "name"), T.Field(item, "quantity")
    if type(name) == "string" then parts[#parts + 1] = name .. " x" .. tostring(qty) end
  end
  if type(dropped) == "number" and dropped > 0 then parts[#parts + 1] = "(" .. dropped .. " more kinds)" end
  if #parts == 0 then parts[1] = "(empty)" end
  local log = D.itemLog
  local clock = T.ClockText()
  log[#log + 1] = { at = (clock ~= "" and (clock .. " ") or "") .. string.format("(%.1f s)", T.Now()),
    text = table.concat(parts, ", "), station = D.stationOpen == true }
  while #log > D.ITEM_LOG_MAX do table.remove(log, 1) end
end

function D.ItemLogLines()
  local lines = {}
  for _, e in ipairs(D.itemLog) do
    lines[#lines + 1] = e.at .. ": " .. e.text .. (e.station and " (a crafting window open)" or "")
  end
  return lines
end

function D.OnItems(items, dropped)
  pcall(D.NoteItems, items, dropped)
  if D.day and D.AddItems(D.day, items, dropped, D.stationOpen) then changed() end
end

function D.OnCraftResults(results, dropped)
  local getRecipe = nil
  if type(ShroudGetRecipe) == "function" then getRecipe = ShroudGetRecipe end
  if D.day and D.AddCraftResults(D.day, results, getRecipe, dropped) then changed() end
end

function D.OnGatherResults(results, dropped)
  if D.day and D.AddGatherResults(D.day, results, dropped) then changed() end
end

function D.OnCraftingState(state)
  D.stationOpen = T.Field(state, "open") == true
end

-- At start: whether a crafting window is already open (a /lua reload at a station).
function D.ReadCraftingState()
  if not D.HasResults() then return end
  local ok, state = pcall(ShroudGetCraftingState)
  if ok then D.OnCraftingState(state) end
end

function D.OnCombat(events)
  if not D.day or type(events) ~= "table" then return end
  for _, e in ipairs(events) do
    if D.IsKill(e) then
      D.day.kills = D.day.kills + 1
      D.unsaved = true
    end
  end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local win = nil
local el = {}
local prefs = { open = false, hover = true, hud = false }
local strip = nil                     -- the HUD strip form (Toolbox.Hud.TextStrip; see compact.lua)
D.HOME = { 40, 200 }

-- Hover pop-up of the Loot Tracker window (Toolbox.DailyDetail).
local hover = T.Hover.New{
  name = "daily",
  enabled = function() return prefs.hover end,
  trigger = function() return D.IsShown() end,
  popup = {
    IsShown = function() return T.DailyDetail.IsShown() end,
    IsPopup = function() return T.DailyDetail.IsPopup() end,
    ShowPopup = function() return T.DailyDetail.ShowPopup() end,
    HidePopup = function() return T.DailyDetail.HidePopup() end,
  },
}

local LINES = {
  { id = "gold", label = "Gold picked up",
    tooltip = "Every increase in your gold today: loot, but also vendor sales, trades and mail" },
  { id = "kills", label = "Kills", tooltip = "Kills by you or your pet today, from combat chat" },
  { id = "adv", label = "Adventurer XP" },
  { id = "prod", label = "Producer XP" },
  { id = "skills", label = "Skill levels", tooltip = "Skill levels gained today (trained levels, not scene caps)" },
  { id = "deaths", label = "Deaths", tooltip = "Times you died today" },
}
local TEXT_IDS = { "date" }
for _, line in ipairs(LINES) do
  TEXT_IDS[#TEXT_IDS + 1] = line.id .. "_label"
  TEXT_IDS[#TEXT_IDS + 1] = line.id
end

local function row(spec)
  local W = T.Window
  return UI.Row{ style = { alignItems = "center" }, tooltip = spec.tooltip or spec.label, children = {
    UI.Label{ id = spec.id .. "_label", text = spec.label, class = "text", style = W.TextStyle{ flexGrow = 1 } },
    UI.Label{ id = spec.id, text = "0", class = "text", style = W.TextStyle{ textAlign = "right" } },
  } }
end

local function build()
  local rows = { UI.Label{ id = "date", text = "", class = "title", style = T.Window.TextStyle() } }
  for _, spec in ipairs(LINES) do rows[#rows + 1] = row(spec) end
  win = UI.Window{
    id = WINDOW_ID, title = "Today",
    compact = prefs.compact == true,  -- API 19: the title bar only on hover, over the content (no fields in it)
    width = 200, height = 170, minWidth = 150, minHeight = 50,
    x = prefs.x or T.Window.DEFAULT_X, y = prefs.y or T.Window.DEFAULT_Y,   -- never nil in a spec
    escCloses = prefs.compact ~= true,  -- a compact window's close button only shows on hover
    onClose = function()
      prefs.open = false
      D.SavePrefs()
      hover:Clear("t:")
      T.Config.Sync()
    end,
    onHover = function(_, over) hover:Report("t:window", over) end,
    style = { paddingTop = 4, paddingBottom = 4 },
    children = {
      UI.Scroll{ id = "body", style = { flexGrow = 1 },
        onHover = function(_, over) hover:Report("t:body", over) end, children = {
        UI.Column{ style = { paddingLeft = GUTTER, paddingRight = GUTTER }, children = rows },
      } },
    },
  }
  el = {}
  for _, id in ipairs(TEXT_IDS) do el[id] = win:Find(id) end
end

function D.SavePrefs()
  T.Save("daily_window", prefs)
end

function D.IsShown()
  if prefs.hud then return prefs.open == true and strip ~= nil end
  return win ~= nil and win:IsShown()
end

-- The labels of the form in use (window or HUD strip).
local function active()
  if prefs.hud then return strip and strip.el or {} end
  return el
end

-- Builds the window (after Toolbox.Window.Init, whose text settings it uses).
-- The data is loaded earlier, by D.ReadDay from ShroudOnStart.
function D.InitWindow()
  if win then pcall(function() win:Destroy() end) end   -- started again for another character
  win = nil
  local saved = T.ReadSaved("daily_window")
  prefs = { open = false, hover = true, hud = false }
  if type(saved) == "table" then
    prefs.open = saved.open == true
    prefs.hover = saved.hover ~= false
    prefs.hud = saved.hud == true
    prefs.compact = saved.compact == true
    if type(saved.x) == "number" and type(saved.y) == "number" then prefs.x, prefs.y = saved.x, saved.y end
    if type(saved.hx) == "number" and type(saved.hy) == "number" then prefs.hx, prefs.hy = saved.hx, saved.hy end
  end
  strip = T.Hud.TextStrip{ key = "daily", FRAME_ID = "toolbox_daily_hud", HOME = D.HOME, titleId = "date",
    lines = LINES, hover = hover, prefs = prefs, save = D.SavePrefs,
    isShown = function() return prefs.hud and prefs.open == true end }
  T.Hud.Register("daily", strip)       -- built by Toolbox.Hud.Init, after this
  build()
  if prefs.open and not prefs.hud and not win:Show() then
    T.Print("Daily stats window could not reopen yet; use /toolbox daily.")
  end
  D.Refresh()
end

function D.SetOpen(open)
  if not win then build() end
  local ok = true
  if not open then
    win:Hide()
    prefs.open = false
    hover:Clear("t:")
  elseif prefs.hud then
    prefs.open = true
  elseif win:IsShown() or win:Show() then
    prefs.open = true
  else
    T.Print("The daily stats window can't reopen right now; try again in a few seconds.")
    ok = false
  end
  D.SavePrefs()
  T.Hud.Refresh()
  D.Refresh()
  T.Config.Sync()
  return ok
end

function D.Toggle()
  return D.SetOpen(not D.IsShown())
end

-- Shows today's stats as a HUD strip (true) or a window (false); open or closed stays as it was.
-- Returns false when the window can't reopen yet.
function D.SetHud(on)
  on = on == true
  if on == prefs.hud then return true end
  local open = D.IsShown()
  hover:Clear("t:")
  prefs.hud = on
  local ok = true
  if on then
    if win then win:Hide() end
    prefs.open = open
  elseif open then
    if not win then build() end
    ok = win:IsShown() or win:Show()
    if not ok then T.Print("The daily stats window can't reopen right now; try again in a few seconds.") end
    prefs.open = ok
  end
  D.SavePrefs()
  T.Hud.Build(true)                   -- the HUD strip exists only in the HUD form (HUD frames per add-on are limited)
  T.Hud.Refresh()
  D.Refresh()
  T.Config.Sync()
  return ok
end

function D.GetHud()
  return prefs.hud
end

-- The window form as a compact window (API 19: its title bar shows only on hover, laid over the content)
-- or a normal one. A window's fields are fixed when it's made, so it is rebuilt; open stays open.
function D.SetCompact(on)
  on = on == true
  if on == (prefs.compact == true) then return true end
  local open = not prefs.hud and win ~= nil and win:IsShown()
  hover:Clear("t:")
  if win then pcall(function() win:Destroy() end) end
  win = nil
  prefs.compact = on
  build()
  local ok = true
  if open then
    ok = win:Show() ~= false
    if not ok then T.Print("The daily stats window can't reopen right now; try again in a few seconds.") end
    prefs.open = ok
  end
  D.SavePrefs()
  D.ApplyText()
  D.Refresh()
  T.Config.Sync()
  return ok
end

function D.GetCompact() return prefs.compact == true end

-- The strip's position (for /toolbox daily move); nil while it isn't laid out.
function D.GetPosition()
  if not strip then return nil end
  return strip.GetPosition()          -- both numbers ("strip and ..." would keep only x)
end
function D.MoveTo(x, y) return strip ~= nil and strip.MoveTo(x, y) end

function D.ApplyText()
  if strip then strip.ApplyText() end
  if not win then return end
  local style = T.Window.LineStyle()
  for _, id in ipairs(TEXT_IDS) do el[id]:SetStyle(style) end
end

function D.SampleLabel()
  return D.IsShown() and active().date or nil
end

function D.Track()
  if T.Window.TrackPosition(win, prefs) then D.SavePrefs() end
end

-- Hover reports from the Loot Tracker window (key without prefix).
function D.PopupHover(key, over)
  hover:Report("p:" .. key, over)
end

function D.PopupClosed()
  hover:Clear("p:")
end

function D.SetHover(on)
  prefs.hover = on == true
  D.SavePrefs()
  if not prefs.hover then hover:Cancel() end
  T.Config.Sync()
end

function D.GetHover()
  return prefs.hover
end

-- "Today 2026-09-27", and a tooltip saying which clock resets it.
function D.DateText()
  if D.source == "local" then return "Today " .. D.label, "Resets at local midnight" end
  if D.source == "utc" then return "Today " .. D.label, "Local clock unavailable: resets at midnight UTC" end
  return "Today (no clock)", "No usable clock: these counts will not reset by themselves"
end

function D.Refresh()
  local e = active()
  if not D.IsShown() or not D.day or not e.date then return end
  local date, tip = D.DateText()
  T.SetText(e.date, date)
  T.SetTooltip(e.date, tip)
  T.SetText(e.gold, T.FormatNumber(D.day.gold))
  T.SetText(e.kills, T.FormatNumber(D.day.kills))
  T.SetText(e.adv, T.FormatNumber(D.XPToday(D.day, "a")))
  T.SetText(e.prod, T.FormatNumber(D.XPToday(D.day, "p")))
  T.SetText(e.skills, T.FormatNumber(D.day.skills))
  T.SetText(e.deaths, T.FormatNumber(D.day.deaths))
end

-- ---------------------------------------------------------------------------
-- /toolbox recipe <name>: a probe for the crafting planner (owner, 2026-10-05). Prints a known recipe as
-- ShroudGetRecipe gives it, every field included (an undocumented one, such as a list of choices for an
-- ingredient, would show here), then expands it "from scratch" through the recipes you know: an ingredient
-- some known recipe makes (by its `results` name) is broken down into that recipe's ingredients, the rest are
-- raw. Read-only. Reading every known recipe at once ran past the game's time limit for one call ("Lua addon
-- exceeded its execution time budget", owner, 2026-10-05): the book is read D.BOOK_STEP recipes a
-- D.BOOK_PERIOD (D.ReadRecipeBook), kept for the session, and read again after ShroudOnRecipesChanged.
-- ---------------------------------------------------------------------------
D.BOOK_STEP, D.BOOK_PERIOD = 8, 0.1
D.recipeIndex = nil                       -- { recipes = { [id] = recipe }, byResult = { [item] = { { id, yield } } } }
local reading = nil                       -- the book being read: { list, at, recipes, byResult, waiting }
local BOOK_TIMER = "toolbox_recipe_book"

function D.ForgetRecipes()
  D.recipeIndex = nil
  if reading then
    pcall(ShroudRemovePeriodic, BOOK_TIMER)
    local waiting = reading.waiting
    reading = nil
    for _, done in ipairs(waiting) do done(false) end
  end
end

-- Adds one recipe to the book being read: by id, and under each result's name and (API 37) item key.
local function indexRecipe(r, id, rec)
  r.recipes[id] = rec
  for _, res in ipairs(T.List(T.Field(rec, "results"))) do
    local q = T.Field(res, "quantity")
    local maker = { id = id, yield = type(q) == "number" and q or 0 }
    local name, key = T.Field(res, "name"), T.Field(res, "key")
    if type(name) == "string" then
      r.byResult[name] = r.byResult[name] or {}
      table.insert(r.byResult[name], maker)
    end
    if type(key) == "string" and key ~= "" then
      r.byKey[key] = r.byKey[key] or {}
      table.insert(r.byKey[key], maker)
    end
  end
end

-- One step: D.BOOK_STEP recipes by id, or (API 37, ShroudGetRecipeBook) one station's recipes in one call, the game
-- counting your bags once for them (the reference: "build it once, keep it").
local function readSome()
  local r = reading
  if not r then return end
  local t0 = T.PerfT()
  if r.cats then
    local ok, list = pcall(ShroudGetRecipeBook, r.cats[r.at])
    for _, rec in ipairs(ok and T.List(list) or {}) do
      local id = T.Field(rec, "id")
      if type(id) == "number" then indexRecipe(r, id, rec) end
    end
    r.at = r.at + 1
    r.done = r.at > #r.cats
  else
    local stop = math.min(#r.list, r.at + D.BOOK_STEP - 1)
    for i = r.at, stop do
      local id = type(T.Field(r.list[i], "id")) == "number" and T.Field(r.list[i], "id") or nil
      if id then
        local ok, rec = pcall(ShroudGetRecipe, id)
        if ok and rec then indexRecipe(r, id, rec) end
      end
    end
    r.at = stop + 1
    r.done = r.at > #r.list
  end
  T.PerfAdd("recipe book", t0)
  if r.done then
    pcall(ShroudRemovePeriodic, BOOK_TIMER)
    reading = nil
    D.recipeIndex = { recipes = r.recipes, byResult = r.byResult, byKey = r.byKey }
    for _, done in ipairs(r.waiting) do done(true) end
  end
end

-- Reads the recipe book a few recipes (or one station) at a time, then calls done(true) (done(false) if it was
-- dropped). Returns how many recipes it reads, or nil when there's nothing to read (no book: done isn't called).
function D.ReadRecipeBook(done)
  if D.recipeIndex then
    done(true)
    return 0
  end
  if reading then
    reading.waiting[#reading.waiting + 1] = done
    return #reading.list
  end
  if type(ShroudGetKnownRecipes) ~= "function" or type(ShroudGetRecipe) ~= "function" then return nil end
  local ok, book = pcall(ShroudGetKnownRecipes)
  local list = ok and T.List(book) or {}
  if #list == 0 then return nil end
  local cats = nil
  if type(ShroudGetRecipeBook) == "function" then
    local seen = {}
    cats = {}
    for _, known in ipairs(list) do
      local cat = T.Field(known, "categoryKey")
      if type(cat) == "string" and cat ~= "" and not seen[cat] then
        seen[cat] = true
        cats[#cats + 1] = cat
      end
    end
    if #cats == 0 then cats = nil end
  end
  reading = { list = list, cats = cats, at = 1, recipes = {}, byResult = {}, byKey = {}, waiting = { done } }
  T.RegisterPeriodic(BOOK_TIMER, readSome, D.BOOK_PERIOD, true)
  return #list
end

-- Whether the book is being read now.
function D.ReadingRecipes() return reading ~= nil end
D.PROBE_DEPTH = 8
D.PROBE_LINES = 80
D.PROBE_MATCHES = 15
local INGREDIENT_FIELDS = { name = true, quantity = true, have = true, optional = true, tool = true,
                            -- API 37 (shown on their own lines below)
                            key = true, carried = true, stats = true, group = true, groupKey = true,
                            chosenKey = true, choosable = true, choices = true, choiceCount = true }
local RECIPE_FIELDS = { id = true, name = true, category = true, categoryKey = true, requiredLevel = true,
                        refine = true, ingredients = true, results = true, result = true,
                        station = true, stationKey = true, locations = true, favorite = true }   -- API 37
local RESULT_FIELDS = { name = true, quantity = true, key = true, carried = true, stats = true }
D.PROBE_CHOICES = 6                    -- a group slot's material choices shown (the game gives up to 30)

-- API 37 stats rows ({ key, value[, name] }) as "+0.6 Armor Damage Resistance, weight 2".
local function statsText(stats)
  local parts = {}
  for _, stat in ipairs(T.List(stats)) do
    local v = T.Field(stat, "value")
    local label = T.Field(stat, "name")
    if type(label) ~= "string" or label == "" then label = tostring(T.Field(stat, "key")) end
    parts[#parts + 1] = label .. " " .. (type(v) == "number" and string.format("%g", v) or tostring(v))
  end
  return table.concat(parts, ", ")
end

-- API 37 item fields: " carried N, key item:..., stats: ..." (each only when the game gave it).
local function itemText(t)
  local out = ""
  local carried, key, stats = T.Field(t, "carried"), T.Field(t, "key"), T.Field(t, "stats")
  if carried ~= nil then out = out .. " carried " .. tostring(carried) .. "," end
  if key ~= nil then out = out .. " key " .. tostring(key) .. "," end
  if stats ~= nil then out = out .. " stats: " .. (statsText(stats) ~= "" and statsText(stats) or "none") .. "," end
  return (out:gsub(",$", ""))
end

-- "k=v, k=v" for a table's fields outside `known` (sorted), or "" (a game object can't be walked: says so).
local function extraFields(t, known)
  if type(t) == "userdata" then return "(a game object: its other fields can't be listed)" end
  if type(t) ~= "table" then return "" end
  local keys = {}
  for k in pairs(t) do
    if not known[k] then keys[#keys + 1] = tostring(k) end
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    if type(v) == "table" then
      local n = 0
      for _ in pairs(v) do n = n + 1 end
      parts[#parts + 1] = k .. "=<table of " .. n .. ">"
    else
      parts[#parts + 1] = k .. "=" .. tostring(v)
    end
  end
  return table.concat(parts, ", ")
end

local function number(v) if type(v) == "number" then return v end return nil end

function D.RecipeLines(text)
  if type(ShroudGetKnownRecipes) ~= "function" or type(ShroudGetRecipe) ~= "function" then
    return { "This game client has no recipe calls for add-ons (they need Lua API 18)." }
  end
  local ok, book = pcall(ShroudGetKnownRecipes)
  local known = ok and T.List(book) or {}
  if #known == 0 then return { "No known recipes yet (the recipe book may still be loading)." } end
  text = T.Trim(text or "")
  if text == "" then
    return { #known .. " known recipes. /toolbox recipe <part of a name> shows one as the game reports it, and "
      .. "what it takes from raw materials." }
  end
  local want, exact, matches = text:lower(), nil, {}
  for _, r in ipairs(known) do
    local name = T.Field(r, "name")
    if type(name) == "string" and name:lower():find(want, 1, true) then
      matches[#matches + 1] = r
      if name:lower() == want then exact = r end
    end
  end
  if #matches == 0 then return { "No known recipe has '" .. text .. "' in its name." } end
  if not exact and #matches > 1 then
    local lines = { #matches .. " known recipes match '" .. text .. "'; type more of the name:" }
    for i = 1, math.min(#matches, D.PROBE_MATCHES) do
      local r = matches[i]
      lines[#lines + 1] = "  " .. tostring(T.Field(r, "name")) .. " (" .. tostring(T.Field(r, "category")) .. ")"
    end
    if #matches > D.PROBE_MATCHES then lines[#lines + 1] = "  ... and " .. (#matches - D.PROBE_MATCHES) .. " more" end
    return lines
  end
  local pick = exact or matches[1]
  local index = D.recipeIndex
  if not index then return nil end         -- the caller reads the book first (D.ReadRecipeBook)
  local recipes, byResult = index.recipes, index.byResult

  local lines = {}
  local function say(s)
    if #lines < D.PROBE_LINES then lines[#lines + 1] = s
    elseif #lines == D.PROBE_LINES then lines[#lines + 1] = "... (cut short: " .. D.PROBE_LINES .. " lines)" end
  end
  local id = number(T.Field(pick, "id"))
  local okPick, fresh = pcall(ShroudGetRecipe, id)   -- read now: its "have" counts are current
  local rec = (okPick and fresh) or (id and recipes[id])
  if not rec then return { "The game gave nothing for '" .. tostring(T.Field(pick, "name")) .. "'." } end
  say("Recipe '" .. tostring(T.Field(rec, "name")) .. "' (id " .. tostring(id) .. ", "
    .. tostring(T.Field(rec, "category")) .. " / " .. tostring(T.Field(rec, "categoryKey")) .. ", level "
    .. tostring(T.Field(rec, "requiredLevel")) .. ", refine " .. tostring(T.Field(rec, "refine")) .. ")")
  local station = T.Field(rec, "station")
  if station ~= nil then                 -- API 37
    local places = {}
    for _, l in ipairs(T.List(T.Field(rec, "locations"))) do places[#places + 1] = tostring(l) end
    say("  Made at: " .. tostring(station) .. " (" .. tostring(T.Field(rec, "stationKey")) .. "), where: "
      .. (#places > 0 and table.concat(places, ", ") or "not given") .. (T.Field(rec, "favorite") == true
        and ", a favorite" or ""))
  end
  local extra = extraFields(rec, RECIPE_FIELDS)
  if extra ~= "" then say("  other fields: " .. extra) end
  local results = T.List(T.Field(rec, "results"))
  if #results == 0 then say("  Makes: no fixed yield (a rolled result)") end
  for _, res in ipairs(results) do
    local more = extraFields(res, RESULT_FIELDS)
    say("  Makes " .. tostring(T.Field(res, "quantity")) .. " x " .. tostring(T.Field(res, "name"))
      .. itemText(res) .. (more ~= "" and ("  {" .. more .. "}") or ""))
  end
  say("Ingredients, as the game gives them:")
  for _, ing in ipairs(T.List(T.Field(rec, "ingredients"))) do
    local flags = {}
    if T.Field(ing, "optional") == true then flags[#flags + 1] = "optional" end
    if T.Field(ing, "tool") == true then flags[#flags + 1] = "tool" end
    local more = extraFields(ing, INGREDIENT_FIELDS)
    if T.Field(ing, "group") == true then flags[#flags + 1] = "group" end
    say("  " .. tostring(T.Field(ing, "quantity")) .. " x " .. tostring(T.Field(ing, "name")) .. " (have "
      .. tostring(T.Field(ing, "have")) .. ")" .. (#flags > 0 and (" [" .. table.concat(flags, ", ") .. "]") or "")
      .. itemText(ing) .. (more ~= "" and ("  {" .. more .. "}") or ""))
    if T.Field(ing, "group") == true then  -- API 37: the slot's material choices
      local choices = T.List(T.Field(ing, "choices"))
      local chosen = T.Field(ing, "chosenKey")
      say("    " .. tostring(T.Field(ing, "groupKey")) .. ", " .. tostring(T.Field(ing, "choiceCount") or #choices)
        .. " choices" .. (T.Field(ing, "choosable") == true and " (picked in the crafting window)" or "")
        .. (chosen ~= nil and (", picked " .. tostring(chosen)) or ""))
      for i = 1, math.min(#choices, D.PROBE_CHOICES) do
        local c = choices[i]
        local have = T.Field(c, "have")
        say("    - " .. tostring(T.Field(c, "name")) .. (have ~= nil and (" (have " .. tostring(have) .. ")") or "")
          .. itemText(c))
      end
      if #choices > D.PROBE_CHOICES then say("    ... and " .. (#choices - D.PROBE_CHOICES) .. " more") end
    end
  end

  -- from scratch: through the first known recipe that makes each ingredient
  say("From scratch, through the recipes you know:")
  local raw = {}
  -- The item a slot stands for: its own name, or for a group slot (API 37: "Metal Sheet") the material picked for it
  -- in the crafting window, else the game's first choice (the ones you can craft with now come first). Returns the
  -- name and a note for the line ("" for a plain slot).
  local function slotItem(ing)
    local iname = T.Field(ing, "name")
    if T.Field(ing, "group") ~= true then return iname, "" end
    local choices = T.List(T.Field(ing, "choices"))
    local chosen = T.Field(ing, "chosenKey")
    for _, c in ipairs(choices) do
      if chosen ~= nil and T.Field(c, "key") == chosen and type(T.Field(c, "name")) == "string" then
        return T.Field(c, "name"), "  (for " .. tostring(iname) .. ": picked)"
      end
    end
    local first = choices[1] and T.Field(choices[1], "name")
    if type(first) ~= "string" then return iname, "" end
    return first, "  (for " .. tostring(iname) .. ": the first choice; pick one in the crafting window)"
  end
  local function expand(name, qty, depth, seen, note)
    local pad = string.rep("  ", depth)
    local makers = byResult[name]
    if not makers or depth >= D.PROBE_DEPTH or seen[name] then
      say(pad .. qty .. " x " .. name .. note .. (seen[name] and "  (made from itself: stops here)" or ""))
      raw[name] = (raw[name] or 0) + qty
      return
    end
    -- the recipe named like the item first ("Iron Ingot", not "Iron Ingot from Metal Scraps"): the usual way
    local m = makers[1]
    for _, mk in ipairs(makers) do
      if T.Field(recipes[mk.id], "name") == name then m = mk end
    end
    local also = {}
    for _, mk in ipairs(makers) do
      if mk ~= m then also[#also + 1] = tostring(T.Field(recipes[mk.id], "name")) end
    end
    local mrec = recipes[m.id]
    if m.yield <= 0 then
      say(pad .. qty .. " x " .. name .. "  <- " .. tostring(T.Field(mrec, "name")) .. " (no fixed yield: stops here)"
        .. note)
      raw[name] = (raw[name] or 0) + qty
      return
    end
    local crafts = math.floor((qty + m.yield - 1) / m.yield)
    say(pad .. qty .. " x " .. name .. "  <- " .. crafts .. " x " .. tostring(T.Field(mrec, "name")) .. " ("
      .. tostring(T.Field(mrec, "category")) .. ", makes " .. m.yield .. ")" .. note
      .. (#also > 0 and ("  [also made by: " .. table.concat(also, "; ") .. "]") or ""))
    seen[name] = true
    for _, ing in ipairs(T.List(T.Field(mrec, "ingredients"))) do
      local iname, inote = slotItem(ing)
      local iqty = number(T.Field(ing, "quantity")) or 0
      if type(iname) == "string" and T.Field(ing, "tool") ~= true and T.Field(ing, "optional") ~= true then
        expand(iname, iqty * crafts, depth + 1, seen, inote)
      end
    end
    seen[name] = nil
  end
  for _, ing in ipairs(T.List(T.Field(rec, "ingredients"))) do
    local iname, inote = slotItem(ing)
    local iqty = number(T.Field(ing, "quantity")) or 0
    if type(iname) == "string" and T.Field(ing, "tool") ~= true and T.Field(ing, "optional") ~= true then
      expand(iname, iqty, 1, {}, inote)
    end
  end
  local names = {}
  for n in pairs(raw) do names[#names + 1] = n end
  table.sort(names)
  say("Raw materials in all (tools and optional ones left out):")
  for _, n in ipairs(names) do say("  " .. raw[n] .. " x " .. n) end
  return lines
end

-- ---------------------------------------------------------------------------
-- The crafting planner (Toolbox.Planner, PL; owner, 2026-10-15, the 1.9.0 feature): pick a known recipe and a
-- number of crafts; each slot that takes a choice of material ("Metal Sheet", API 37) gets a dropdown, filled one of
-- two ways (owner: "some just use what they have, others craft for stat combos for their builds"): "Use what I have"
-- (the first choice you have enough of, in the game's order, which puts the ones you can craft with first) or
-- "Stats I care about" (the stats you watch, per recipe kind, shown on every choice, the best for the first one
-- picked; a lower weight or charge time is better). A slot you pick yourself keeps your pick (`picks`, per recipe).
-- With From scratch on, an ingredient you're short of and a known recipe makes gets Make it: the shortfall is
-- crafted, that recipe's ingredients planned below it (`makes`, by the row's path; a recipe never inside itself;
-- several recipes making one item: the one named like it, or the one picked). The plan's views: Plan (the slots),
-- Shopping list (what to buy or gather) and Build order (the crafts by station, deepest first, ticked off as their
-- count reaches 0: the game's `have` counts what's on the crafting table, so a craft made counts at once). The
-- result line adds the picks' stats to the result's base stats (the reference: a slot that doesn't pass its
-- material's bonus on lists only its weight, which isn't added). Its window is the shared 8th one
-- (T.TakeSharedWindow), built when opened. The plan is worked out again on a change: inventory, a craft, a
-- learned recipe (at most every PL.REFRESH_GAP s while shown), with the plan's recipes read fresh (`have`).
-- Saved var "planner" (character scope; a reset keeps it): { v = 1, mode = "have"/"stats", scratch = bool,
-- crafts = n, recipe = id, view = a PL.VIEWS name, makes = { [path] = true }, makers = { [item key] = recipe id },
-- picks = { ["r" .. recipe id] = { at = n, ["s" .. slot] = item key } } (at most PL.PICKS_MAX recipes, the oldest
-- picked dropped), pickAt = n, watch = { [categoryKey] = { stat keys } } }.
-- ---------------------------------------------------------------------------
local PL = {}
Toolbox.Planner = PL
PL.KEY = "planner"
PL.WINDOW_ID = "toolbox_planner"
PL.DEPTH = 8                          -- levels of Make it below the recipe
PL.MATCHES = 15                       -- recipes a search lists
PL.CHOICES_SHOWN = 10                 -- a slot's choices in its dropdown (the game gives up to 30): the text budget
PL.ROWS_MAX = 60
PL.PICKS_MAX = 60
PL.WATCH_MAX = 6
PL.RESULT_STATS = 8                   -- stats on the result line
PL.REFRESH_GAP = 2
PL.INDENT = 14
PL.CRAFTS = { 1, 2, 3, 4, 5, 10, 20, 50, 100 }
PL.MODES = { { "have", "Use what I have" }, { "stats", "Stats I care about" } }
PL.VIEWS = { "Plan", "Shopping list", "Build order" }
PL.NO_RECIPE = "Find a recipe first"
PL.NO_STATS = "No stats to watch"
PL.STAT_NAMES = { weight = "Weight", durability = "Durability", damageMin = "Min damage", damageMax = "Max damage",
                  critical = "Critical", parry = "Parry", chargeSeconds = "Charge time", resistance = "Resistance",
                  avoidance = "Avoidance" }
PL.LOWER_BETTER = { weight = true, chargeSeconds = true }

local plPrefs = {}
local plWin, plEl = nil, {}
local plMatches = {}                  -- the recipe dropdown's names -> recipe ids
local plFresh = {}                    -- recipe id -> ShroudGetRecipe's table, read for this plan
local plPlan = nil                    -- the last PL.Expand result
local plDirty, plAt = false, -math.huge
local plRows = {}                     -- the Plan view's rows as built: { sig, label, pick, make, via, values }
local plBodySig = nil                 -- what the body was built for (rebuilt only when it changes)
local plBody, plCol = nil, nil
local plBuilt = {}                    -- recipe id -> { name, station, depth }: every craft the plan has asked for
local plMade = {}                     -- recipe id -> crafts made since the plan was set (ShroudOnCraftResults)
local plStatChoices = {}              -- the stat dropdown's names -> stat keys

local function plNum(v) if type(v) == "number" and v == v then return v end return nil end

local function plSave() T.Save(PL.KEY, plPrefs) end

-- An item's key (API 37: "item:" + 32 hex), or its name on an older client.
function PL.KeyOf(item)
  local key = T.Field(item, "key")
  if type(key) == "string" and key ~= "" then return key end
  return tostring(T.Field(item, "name"))
end

-- How many of an item the craft can reach: `have` (a choice has it only when choosable), else `carried`, else 0.
function PL.HaveOf(item)
  return plNum(T.Field(item, "have")) or plNum(T.Field(item, "carried")) or 0
end

function PL.StatName(sr)
  local name = T.Field(sr, "name")
  if type(name) == "string" and name ~= "" then return name end
  local key = tostring(T.Field(sr, "key"))
  if PL.STAT_NAMES[key] then return PL.STAT_NAMES[key] end
  return (key:gsub("^stat:", ""))
end

-- The value an item's stats rows give one stat key, or nil.
function PL.StatValue(item, key)
  for _, sr in ipairs(T.List(T.Field(item, "stats"))) do
    if T.Field(sr, "key") == key then return plNum(T.Field(sr, "value")) end
  end
  return nil
end

-- A stat's name as an item's rows give it, else from its key.
function PL.StatLabel(item, key)
  for _, sr in ipairs(T.List(T.Field(item, "stats"))) do
    if T.Field(sr, "key") == key then return PL.StatName(sr) end
  end
  return PL.StatName({ key = key })
end

-- "+0.2" / "-1" / "220": a stat's number, short.
function PL.Number(v, signed)
  local text = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
  if signed and v >= 0 then text = "+" .. text end
  return text
end

-- A group slot's choice: the player's pick (`manual`, an item key) when it's still offered; in "stats" mode the
-- best for `stat` (the highest, or the lowest for PL.LOWER_BETTER); else, and when no choice has that stat, the first
-- you have enough of (`avail(choice)`), else the one you have most of. Nil without choices.
function PL.PickChoice(choices, need, avail, mode, stat, manual)
  if manual then
    for _, c in ipairs(choices) do
      if PL.KeyOf(c) == manual then return c end
    end
  end
  if mode == "stats" and stat then
    local best, bestV = nil, nil
    for _, c in ipairs(choices) do
      local v = PL.StatValue(c, stat)
      if v and (bestV == nil or (PL.LOWER_BETTER[stat] and v < bestV) or (not PL.LOWER_BETTER[stat] and v > bestV)) then
        best, bestV = c, v
      end
    end
    if best then return best end
  end
  local most, mostN = nil, -1
  for _, c in ipairs(choices) do
    local n = avail(c)
    if n >= need then return c end
    if n > mostN then most, mostN = c, n end
  end
  return most
end

-- Of several recipes making an item: the player's (`picked`, a recipe id), else the one named like the item ("Iron
-- Ingot", not "Iron Ingot from Metal Scraps"), else the first. `makers`: { { id, yield } }, `nameOf(id)`.
function PL.PickMaker(makers, itemName, picked, nameOf)
  local named = nil
  for _, m in ipairs(makers) do
    if picked and m.id == picked then return m end
    if not named and nameOf(m.id) == itemName then named = m end
  end
  return named or makers[1]
end

-- Works a plan out: `crafts` crafts of recipe `rootId`. `ctx`: recipe(id) -> the recipe's table; makers(key, name) ->
-- { { id, yield } } (yield > 0); mode, stat (the first watched, or nil), scratch, makes (set of row paths), pick(id,
-- slot) -> an item key or nil, maker(key) -> a recipe id or nil. Your bags are shared across the plan (an item used
-- in one branch isn't counted again in another). Returns { rows, shop (list of { key, name, n, tool }), build (list
-- of { id, name, station, crafts, depth }, deepest first, then by station), cut (rows past PL.ROWS_MAX) }.
function PL.Expand(rootId, crafts, ctx)
  local out = { rows = {}, shop = {}, build = {}, cut = false }
  local pool, shopBy, buildBy = {}, {}, {}
  local function avail(item)
    local key = PL.KeyOf(item)
    if pool[key] == nil then return PL.HaveOf(item) end
    return pool[key]
  end
  local function take(item, need)
    local key = PL.KeyOf(item)
    if pool[key] == nil then pool[key] = PL.HaveOf(item) end
    local use = math.min(pool[key], need)
    pool[key] = pool[key] - use
    return need - use, use
  end
  local function addShop(r)
    local s = shopBy[r.key]
    if not s then
      s = { key = r.key, name = r.name, n = 0, tool = r.tool }
      shopBy[r.key] = s
      out.shop[#out.shop + 1] = s
    end
    s.n = s.n + r.short
  end
  local function walk(id, n, depth, path, seen)
    local rec = ctx.recipe(id)
    if not rec then return end
    local b = buildBy[id]
    if not b then
      b = { id = id, name = tostring(T.Field(rec, "name")), station = tostring(T.Field(rec, "station")
        or T.Field(rec, "category") or ""), crafts = 0, depth = depth }
      buildBy[id] = b
      out.build[#out.build + 1] = b
    end
    b.crafts = b.crafts + n
    if depth > b.depth then b.depth = depth end
    seen[id] = true
    for i, ing in ipairs(T.List(T.Field(rec, "ingredients"))) do
      local qty = plNum(T.Field(ing, "quantity")) or 0
      local r = { depth = depth, path = path .. "." .. i, recipe = id, slot = i,
                  slotName = tostring(T.Field(ing, "name")),
                  tool = T.Field(ing, "tool") == true, optional = T.Field(ing, "optional") == true,
                  group = T.Field(ing, "group") == true, short = 0, have = 0 }
      r.need = r.tool and qty or qty * n
      local item = ing
      if r.group then
        r.choices = T.List(T.Field(ing, "choices"))
        local manual = ctx.pick(id, i)
        if manual == nil and type(T.Field(ing, "chosenKey")) == "string" then manual = T.Field(ing, "chosenKey") end
        item = PL.PickChoice(r.choices, r.need, avail, ctx.mode, ctx.stat, manual) or ing
        r.pick = item ~= ing and PL.KeyOf(item) or nil
      end
      r.item, r.name, r.key = item, tostring(T.Field(item, "name")), PL.KeyOf(item)
      if #out.rows < PL.ROWS_MAX then out.rows[#out.rows + 1] = r else out.cut = true end
      if not r.optional then
        r.short, r.have = take(item, r.need)
        local makers = {}
        for _, m in ipairs(ctx.makers(r.key, r.name)) do
          if not seen[m.id] and m.yield > 0 then makers[#makers + 1] = m end
        end
        r.makers = makers
        r.canMake = r.short > 0 and ctx.scratch == true and #makers > 0 and not r.tool and depth + 1 <= PL.DEPTH
        r.making = r.canMake and ctx.makes[r.path] == true
        if r.making then
          local m = PL.PickMaker(makers, r.name, ctx.maker(r.key), function(mid)
            return T.Field(ctx.recipe(mid), "name")
          end)
          r.maker = m.id
          r.crafts = math.floor((r.short + m.yield - 1) / m.yield)
          walk(m.id, r.crafts, depth + 1, r.path, seen)
        elseif r.short > 0 then
          addShop(r)
        end
      end
    end
    seen[id] = nil
  end
  walk(rootId, crafts, 0, "p", {})
  table.sort(out.build, function(a, b)
    if a.depth ~= b.depth then return a.depth > b.depth end
    if a.station ~= b.station then return a.station < b.station end
    return a.name < b.name
  end)
  table.sort(out.shop, function(a, b) return a.name < b.name end)
  return out
end

-- The result line's stats: the result's base stats with what the recipe's own slots add (each row's item, weight
-- left out: an ingredient's weight is its own), watched stats first. { { key, name, base, add } }.
function PL.Preview(rec, rows, watch)
  local list, by = {}, {}
  local function entry(key, name)
    if not by[key] then
      by[key] = { key = key, name = name, base = nil, add = 0 }
      list[#list + 1] = by[key]
    end
    return by[key]
  end
  for _, key in ipairs(watch or {}) do entry(key, PL.STAT_NAMES[key] or (key:gsub("^stat:", ""))) end
  local res = T.List(T.Field(rec, "results"))[1]
  for _, sr in ipairs(res and T.List(T.Field(res, "stats")) or {}) do
    local key, v = T.Field(sr, "key"), plNum(T.Field(sr, "value"))
    if type(key) == "string" and v then
      local e = entry(key, PL.StatName(sr))
      e.name, e.base = PL.StatName(sr), (e.base or 0) + v
    end
  end
  for _, r in ipairs(rows) do
    if r.depth == 0 and not r.tool then
      for _, sr in ipairs(T.List(T.Field(r.item, "stats"))) do
        local key, v = T.Field(sr, "key"), plNum(T.Field(sr, "value"))
        if type(key) == "string" and key ~= "weight" and v then
          local e = entry(key, PL.StatName(sr))
          e.name, e.add = PL.StatName(sr), e.add + v
        end
      end
    end
  end
  return list
end

function PL.PreviewText(list)
  local parts = {}
  for i = 1, math.min(#list, PL.RESULT_STATS) do
    local e = list[i]
    local text = e.name .. " " .. (e.base and PL.Number(e.base) or "0")
    if e.add ~= 0 then text = text .. " " .. PL.Number(e.add, true) end
    parts[#parts + 1] = text
  end
  if #list > PL.RESULT_STATS then parts[#parts + 1] = "..." end
  if #parts == 0 then return "Result: no stats given for it" end
  return "Result: " .. table.concat(parts, ", ")
end

-- ---- the player's choices ----

local function plRecipeId() return plNum(plPrefs.recipe) end

local function plRecipe(id)
  if plFresh[id] == nil then
    local ok, rec = pcall(ShroudGetRecipe, id)
    plFresh[id] = (ok and rec) or false
  end
  return plFresh[id] or nil
end

local function plCategory()
  local rec = plRecipeId() and plRecipe(plRecipeId())
  local cat = rec and T.Field(rec, "categoryKey")
  if type(cat) == "string" and cat ~= "" then return cat end
  return "any"
end

function PL.Watched()
  local w = type(plPrefs.watch) == "table" and plPrefs.watch[plCategory()]
  return type(w) == "table" and w or {}
end

function PL.Watch(key)
  local w = PL.Watched()
  for _, k in ipairs(w) do
    if k == key then return false, "already watched" end
  end
  if #w >= PL.WATCH_MAX then return false, "at most " .. PL.WATCH_MAX .. " stats" end
  plPrefs.watch = type(plPrefs.watch) == "table" and plPrefs.watch or {}
  local copy = { key }
  for _, k in ipairs(w) do copy[#copy + 1] = k end
  plPrefs.watch[plCategory()] = copy        -- the newest first: it's the one the picks follow
  plSave()
  return true
end

function PL.Unwatch(key)
  local w, kept, found = PL.Watched(), {}, false
  for _, k in ipairs(w) do
    if k == key then found = true else kept[#kept + 1] = k end
  end
  if not found then return false end
  plPrefs.watch[plCategory()] = #kept > 0 and kept or nil
  plSave()
  return true
end

local function plPickOf(id, slot)
  local p = type(plPrefs.picks) == "table" and plPrefs.picks["r" .. id]
  local key = type(p) == "table" and p["s" .. slot]
  return type(key) == "string" and key or nil
end

-- Remembers the player's material for one slot of a recipe (nil: back to the mode's choice).
function PL.SetPick(id, slot, key)
  plPrefs.picks = type(plPrefs.picks) == "table" and plPrefs.picks or {}
  local p = plPrefs.picks["r" .. id] or {}
  p["s" .. slot] = key
  plPrefs.pickAt = (plNum(plPrefs.pickAt) or 0) + 1
  p.at = plPrefs.pickAt
  plPrefs.picks["r" .. id] = p
  local n, oldest, oldestAt = 0, nil, math.huge
  for k, v in pairs(plPrefs.picks) do
    n = n + 1
    local at = type(v) == "table" and plNum(v.at) or 0
    if at < oldestAt then oldest, oldestAt = k, at end
  end
  if n > PL.PICKS_MAX and oldest then plPrefs.picks[oldest] = nil end
  plSave()
  PL.Refresh(true)
end

function PL.SetMaking(path, on)
  plPrefs.makes = type(plPrefs.makes) == "table" and plPrefs.makes or {}
  plPrefs.makes[path] = on and true or nil
  plSave()
  PL.Refresh(true)
end

function PL.SetMaker(key, id)
  plPrefs.makers = type(plPrefs.makers) == "table" and plPrefs.makers or {}
  plPrefs.makers[key] = id
  plSave()
  PL.Refresh(true)
end

function PL.SetMode(mode)
  plPrefs.mode = mode == "stats" and "stats" or "have"
  plSave()
  PL.Refresh(true)
end
function PL.GetMode() return plPrefs.mode == "stats" and "stats" or "have" end

function PL.SetScratch(on)
  plPrefs.scratch = on == true
  plSave()
  if plPrefs.scratch then PL.NeedBook() end
  PL.Refresh(true)
end
function PL.GetScratch() return plPrefs.scratch == true end

function PL.SetCrafts(n)
  n = plNum(n)
  if not n or n < 1 then return end
  plPrefs.crafts = math.floor(n)
  plSave()
  PL.Refresh(true)
end
function PL.GetCrafts() return plNum(plPrefs.crafts) or 1 end

function PL.SetView(view)
  for _, v in ipairs(PL.VIEWS) do
    if v == view then plPrefs.view = v end
  end
  plSave()
  PL.Refresh(true)
end
function PL.GetView() return plPrefs.view or PL.VIEWS[1] end

-- Plans a recipe (by id): a new plan, so the Make it choices and the crafts made start over.
function PL.SetRecipe(id)
  plPrefs.recipe, plPrefs.makes = id, {}
  plBuilt, plMade = {}, {}
  plSave()
  PL.Refresh(true)
end

-- Known recipes whose name has `text` in it (an exact name alone): { { id, name } }, at most PL.MATCHES, and how
-- many matched in all.
function PL.Find(text)
  local want = T.Trim(text or ""):lower()
  local found, n = {}, 0
  if want == "" or type(ShroudGetKnownRecipes) ~= "function" then return found, 0 end
  local ok, book = pcall(ShroudGetKnownRecipes)
  for _, r in ipairs(ok and T.List(book) or {}) do
    local name, id = T.Field(r, "name"), plNum(T.Field(r, "id"))
    if type(name) == "string" and id and name:lower():find(want, 1, true) then
      if name:lower() == want then return { { id = id, name = name } }, 1 end
      n = n + 1
      if #found < PL.MATCHES then found[#found + 1] = { id = id, name = name } end
    end
  end
  return found, n
end

-- The recipe book (for Make it), read once a session in the background (D.ReadRecipeBook).
function PL.NeedBook()
  if D.recipeIndex or D.ReadingRecipes() then return end
  D.ReadRecipeBook(function(ok)
    if ok then PL.Refresh(true) end
  end)
end

local function plMakers(key, name)
  local index = D.recipeIndex
  if not index then return {} end
  if index.byKey and key and index.byKey[key] then return index.byKey[key] end
  return index.byResult[name] or {}
end

-- Works the plan out again (nil without a recipe or a game client with the recipe calls).
function PL.Plan()
  local id = plRecipeId()
  if not id or type(ShroudGetRecipe) ~= "function" or not plRecipe(id) then return nil end
  local watch = PL.Watched()
  local stat = PL.GetMode() == "stats" and watch[1] or nil
  return PL.Expand(id, PL.GetCrafts(), {
    recipe = plRecipe, makers = plMakers, mode = PL.GetMode(), stat = stat, scratch = PL.GetScratch(),
    makes = type(plPrefs.makes) == "table" and plPrefs.makes or {},
    pick = plPickOf,
    maker = function(key) return type(plPrefs.makers) == "table" and plNum(plPrefs.makers[key]) or nil end,
  })
end

-- ---- the window ----

local function plMsg(text) if plEl.msg then T.SetText(plEl.msg, text or "") end end

local function plDrop()
  if plWin then pcall(function() plWin:Destroy() end) end
  plWin, plEl, plRows, plBodySig, plBody, plCol = nil, {}, {}, nil, nil, nil
end

-- A choice as its dropdown shows it: "Iron Sheet (have 3)", and in "stats" mode the value of the stat the picks
-- follow (one: every choice of every slot is on screen, against the add-on's text budget; the row's status shows
-- the picked one's other watched stats).
local function plChoiceText(c, watch)
  local text = tostring(T.Field(c, "name")) .. " (have " .. T.FormatNumber(PL.HaveOf(c)) .. ")"
  if PL.GetMode() == "stats" and watch[1] then
    local v = PL.StatValue(c, watch[1])
    if v then text = text .. ": " .. PL.StatLabel(c, watch[1]) .. " " .. PL.Number(v, true) end
  end
  return text
end

-- The picked material's other watched stats, short: "Focus +10, Strength +1".
local function plOtherStats(item, watch)
  local parts = {}
  for i = 2, #watch do
    local v = PL.StatValue(item, watch[i])
    if v then parts[#parts + 1] = PL.StatLabel(item, watch[i]) .. " " .. PL.Number(v, true) end
  end
  return table.concat(parts, ", ")
end

-- A row's text: "7 x Metal Sheet:" for a slot with a dropdown, "4 x Iron Ingot: have 3, 1 short" for the rest.
local function plRowText(r)
  local lead = (r.optional and "(optional) " or "") .. (r.tool and "Tool: " or "") .. T.FormatNumber(r.need) .. " x "
  if r.group then return lead .. r.slotName .. ":" end
  local text = lead .. r.name
  if r.optional then return text end
  if r.short <= 0 then return text .. ": have them" end
  text = text .. ": have " .. T.FormatNumber(r.have) .. ", " .. T.FormatNumber(r.short) .. " short"
  if r.making then text = text .. ", craft " .. T.FormatNumber(r.crafts) end
  return text
end

local function plGroupStatus(r, watch)
  local others = PL.GetMode() == "stats" and plOtherStats(r.item, watch) or ""
  if others ~= "" then others = "; " .. others end
  if r.optional then return (others:gsub("^; ", "")) end
  if r.short <= 0 then return "have them" .. others end
  local text = T.FormatNumber(r.short) .. " short"
  if r.making then text = text .. ", craft " .. T.FormatNumber(r.crafts) end
  return text .. others
end

-- The choices a slot's dropdown lists: the first PL.CHOICES_SHOWN, the picked one always among them.
local function plShownChoices(r, watch)
  local names, values = {}, {}
  local pickedIn = false
  for i, c in ipairs(r.choices) do
    if i <= PL.CHOICES_SHOWN or PL.KeyOf(c) == r.pick then
      local text = plChoiceText(c, watch)
      if values[text] == nil then
        names[#names + 1] = text
        values[text] = PL.KeyOf(c)
        if PL.KeyOf(c) == r.pick then pickedIn = text end
      end
    end
  end
  return names, values, pickedIn
end

local function plMakerNames(r)
  local names, values, chosen = {}, {}, nil
  for _, m in ipairs(r.makers or {}) do
    local rec = plRecipe(m.id)
    local name = tostring(rec and T.Field(rec, "name") or m.id)
    if values[name] == nil then
      names[#names + 1] = name
      values[name] = m.id
      if m.id == r.maker then chosen = name end
    end
  end
  return names, values, chosen
end

-- The structure the Plan view's elements were made for: rebuilt only when it changes (the creation cap); the
-- counts change in place.
local function plRowSig(r)
  return table.concat({ r.path, tostring(r.group), tostring(r.canMake), tostring(r.making),
    tostring(r.makers and #r.makers > 1 and r.making) }, "|")
end

local function plPlanRows(plan, watch)
  local children = {}
  plRows = {}
  for i, r in ipairs(plan.rows) do
    local e = { sig = plRowSig(r) }
    local parts = {}
    e.label = UI.Label{ text = plRowText(r), class = r.optional and "dim" or "text", style = { flexShrink = 1,
      marginLeft = r.depth * PL.INDENT, whiteSpace = "wrap" } }
    parts[#parts + 1] = e.label
    if r.group then
      local names, values, picked = plShownChoices(r, watch)
      if #names == 0 then names = { "No choices given" } end
      e.values, e.names = values, table.concat(names, "\n")
      e.pick = UI.Dropdown{ id = "pl_pick_" .. i, choices = names, value = picked or names[1],
        style = { flexGrow = 1, flexShrink = 1, marginLeft = 4 },
        tooltip = "The material for this slot (the game lists up to 30; the first " .. PL.CHOICES_SHOWN .. " here)",
        onChange = function(_, text)
          local key = e.values[text]
          if key then PL.SetPick(r.recipe, r.slot, key) end
        end }
      parts[#parts + 1] = e.pick
      e.status = UI.Label{ text = plGroupStatus(r, watch), class = "dim", style = { marginLeft = 4 } }
      parts[#parts + 1] = e.status
    end
    if r.canMake then
      e.make = UI.Button{ id = "pl_make_" .. i, text = r.making and "Buy instead" or "Make it",
        style = { marginLeft = 4 },
        tooltip = r.making and "Get the shortfall instead of crafting it"
          or "Craft the shortfall from its recipe (planned below it)",
        onClick = function() PL.SetMaking(r.path, not r.making) end }
      parts[#parts + 1] = e.make
    end
    children[#children + 1] = UI.Row{ style = { alignItems = "center", marginTop = 2 }, children = parts }
    if r.making and #r.makers > 1 then
      local names, values, chosen = plMakerNames(r)
      e.makerValues = values
      e.via = UI.Dropdown{ id = "pl_via_" .. i, choices = names, value = chosen or names[1],
        style = { flexGrow = 1, flexShrink = 1 }, tooltip = "Which of your recipes makes it",
        onChange = function(_, name)
          local mid = e.makerValues[name]
          if mid then PL.SetMaker(r.key, mid) end
        end }
      children[#children + 1] = UI.Row{ style = { alignItems = "center", marginLeft = (r.depth + 1) * PL.INDENT },
        children = { UI.Label{ text = "made by", class = "dim", style = { marginRight = 4 } }, e.via } }
    end
    plRows[i] = e
  end
  if plan.cut then
    children[#children + 1] = UI.Label{ text = "... and more (the plan is cut at " .. PL.ROWS_MAX .. " lines)",
      class = "dim" }
  end
  return children
end

local function plShopRows(plan)
  local children = {}
  for _, s in ipairs(plan.shop) do
    children[#children + 1] = UI.Label{ text = T.FormatNumber(s.n) .. " x " .. s.name .. (s.tool and " (a tool)"
      or ""), class = "text" }
  end
  if #children == 0 then
    children[1] = UI.Label{ text = "Nothing to get: you have everything the plan needs.", class = "dim" }
  end
  return children
end

local function plBuildRows(plan)
  local now = {}
  for _, b in ipairs(plan.build) do
    now[b.id] = b
    plBuilt[b.id] = plBuilt[b.id] or { name = b.name, station = b.station, depth = b.depth, order = 0 }
  end
  local list = {}
  for id, b in pairs(plBuilt) do list[#list + 1] = { id = id, name = b.name, station = b.station, depth = b.depth } end
  table.sort(list, function(a, b)
    if a.depth ~= b.depth then return a.depth > b.depth end
    if a.station ~= b.station then return a.station < b.station end
    return a.name < b.name
  end)
  local children, station = {}, nil
  local rootId = plRecipeId()
  for _, b in ipairs(list) do
    if b.station ~= station then
      station = b.station
      children[#children + 1] = UI.Label{ text = station ~= "" and station or "Station", class = "text",
        style = { marginTop = 4 } }
    end
    local left = now[b.id] and now[b.id].crafts or 0
    local made = plMade[b.id] or 0
    if b.id == rootId then left = math.max(0, left - made) end   -- the recipe itself: its crafts, less those made
    local text = (left > 0 and "[ ] " or "[x] ") .. b.name .. (left > 0 and (": " .. T.FormatNumber(left)
      .. " crafts") or ": done") .. (made > 0 and (" (made " .. T.FormatNumber(made) .. ")") or "")
    children[#children + 1] = UI.Label{ text = text, class = left > 0 and "text" or "dim",
      style = { marginLeft = PL.INDENT } }
  end
  return children
end

-- The plan's text, in place when the Plan view's structure is the same (counts, choices' have).
local function plUpdateRows(plan, watch)
  for i, r in ipairs(plan.rows) do
    local e = plRows[i]
    if e then
      T.SetText(e.label, plRowText(r))
      if e.status then T.SetText(e.status, plGroupStatus(r, watch)) end
      if e.pick then
        local names, values, picked = plShownChoices(r, watch)
        local joined = table.concat(names, "\n")
        if #names > 0 and joined ~= e.names then
          e.values, e.names = values, joined
          pcall(function() e.pick:SetChoices(names) end)
        end
        if picked then pcall(function() e.pick:SetValue(picked) end) end
      end
    end
  end
end

local function plStatList()
  local id = plRecipeId()
  local rec = id and plRecipe(id)
  local keys, names = {}, {}
  local function add(sr)
    local key = T.Field(sr, "key")
    if type(key) == "string" and key ~= "weight" and not names[key] then
      names[key] = PL.StatName(sr)
      keys[#keys + 1] = key
    end
  end
  if rec then
    for _, res in ipairs(T.List(T.Field(rec, "results"))) do
      for _, sr in ipairs(T.List(T.Field(res, "stats"))) do add(sr) end
    end
    for _, ing in ipairs(T.List(T.Field(rec, "ingredients"))) do
      for _, c in ipairs(T.List(T.Field(ing, "choices"))) do
        for _, sr in ipairs(T.List(T.Field(c, "stats"))) do add(sr) end
      end
      for _, sr in ipairs(T.List(T.Field(ing, "stats"))) do add(sr) end
    end
  end
  table.sort(keys, function(a, b) return names[a] < names[b] end)
  return keys, names
end

local function plSyncStats()
  if not plEl.stat then return end
  local stats = PL.GetMode() == "stats"
  T.SetVisible(plEl.statRow, stats)
  if not stats then return end
  local keys, names = plStatList()
  local choices = {}
  plStatChoices = {}
  for _, key in ipairs(keys) do
    choices[#choices + 1] = names[key]
    plStatChoices[names[key]] = key
  end
  if #choices == 0 then choices = { PL.NO_STATS } end
  local keep = plEl.stat:GetValue()
  pcall(function()
    plEl.stat:SetChoices(choices)
    plEl.stat:SetValue(plStatChoices[keep] and keep or choices[1])
  end)
  local watched = {}
  for _, key in ipairs(PL.Watched()) do watched[#watched + 1] = names[key] or PL.STAT_NAMES[key] or key end
  T.SetText(plEl.watching, #watched > 0 and ("Watching: " .. table.concat(watched, ", "))
    or "Pick a stat and Watch it: each slot's choices show it, and the best for the first is picked")
end

-- Fills the window from a new plan. `now`: at once (a player's change), else only when something changed and at
-- most every PL.REFRESH_GAP s (PL.Tick).
function PL.Refresh(now)
  plDirty = true
  if not (plWin and plBody) then return end
  if not now and T.Now() - plAt < PL.REFRESH_GAP then return end
  plDirty, plAt = false, T.Now()
  plFresh = {}
  local t0 = T.PerfT()
  local plan = PL.Plan()
  plPlan = plan
  local watch = PL.Watched()
  local view = PL.GetView()
  pcall(function()
    plEl.mode:SetValue(PL.MODES[PL.GetMode() == "stats" and 2 or 1][2])
    plEl.scratch:SetValue(PL.GetScratch())
    plEl.crafts:SetValue(tostring(PL.GetCrafts()))
    plEl.view:SetValue(view)
  end)
  plSyncStats()
  local id = plRecipeId()
  local rec = id and plRecipe(id)
  if not plan or not rec then
    T.SetText(plEl.title, id and "That recipe isn't in your book any more: find another" or
      "Type part of a recipe's name and Find it")
    T.SetText(plEl.result, "")
    if plCol then pcall(function() plCol:Destroy() end) end
    plCol, plBodySig, plRows = nil, nil, {}
    T.PerfAdd("planner", t0)
    return
  end
  local yield = 0
  for _, res in ipairs(T.List(T.Field(rec, "results"))) do yield = yield + (plNum(T.Field(res, "quantity")) or 0) end
  T.SetText(plEl.title, tostring(T.Field(rec, "name")) .. " at " .. tostring(T.Field(rec, "station")
    or T.Field(rec, "category")) .. (yield > 0 and (": makes " .. T.FormatNumber(yield * PL.GetCrafts())) or ""))
  T.SetText(plEl.result, PL.PreviewText(PL.Preview(rec, plan.rows, PL.GetMode() == "stats" and watch or nil)))
  local readingBook = PL.GetScratch() and not D.recipeIndex
  if readingBook then PL.NeedBook() end
  local sigParts = { view, tostring(id), tostring(PL.GetMode()), table.concat(watch, ",") }
  if view == "Plan" then
    for _, r in ipairs(plan.rows) do sigParts[#sigParts + 1] = plRowSig(r) end
  elseif view == "Shopping list" then
    for _, s in ipairs(plan.shop) do sigParts[#sigParts + 1] = s.key .. "=" .. s.n end
  else
    for _, b in ipairs(plan.build) do sigParts[#sigParts + 1] = b.id .. "=" .. b.crafts end
    for k, n in pairs(plMade) do sigParts[#sigParts + 1] = "m" .. k .. "=" .. n end
  end
  local sig = table.concat(sigParts, ";")
  if sig == plBodySig and plCol then
    if view == "Plan" then plUpdateRows(plan, watch) end
  else
    if plCol then pcall(function() plCol:Destroy() end) end
    plCol, plRows = nil, {}
    local children = nil
    if view == "Plan" then children = plPlanRows(plan, watch)
    elseif view == "Shopping list" then children = plShopRows(plan)
    else children = plBuildRows(plan) end
    local ok, col = pcall(function() return plBody:Add(UI.Column{ children = children }) end)
    if ok then
      plCol, plBodySig = col, sig
    else
      plRows, plBodySig = {}, nil
      plDirty = true                    -- the creation cap: tried again at the next tick
    end
  end
  plMsg(readingBook and "Reading your recipe book for Make it: a few seconds." or nil)
  T.PerfAdd("planner", t0)
end

local function plFind(text)
  local found, n = PL.Find(text or (plEl.find and plEl.find:GetText()) or "")
  if #found == 0 then
    plMsg(T.Trim(text or (plEl.find and plEl.find:GetText()) or "") == "" and "Type part of a recipe's name first."
      or "No recipe you know has that in its name.")
    return
  end
  local names = {}
  plMatches = {}
  for _, f in ipairs(found) do
    local name = f.name
    if plMatches[name] then name = name .. " (" .. f.id .. ")" end
    names[#names + 1] = name
    plMatches[name] = f.id
  end
  pcall(function()
    plEl.recipe:SetChoices(names)
    plEl.recipe:SetValue(names[1])
  end)
  PL.SetRecipe(found[1].id)
  plMsg(n > #found and (n .. " recipes match: the first " .. #found .. " are listed; type more of the name.")
    or (#found > 1 and (#found .. " recipes match: pick one.") or nil))
end

local function plBuild()
  local modes, crafts = {}, {}
  for i, m in ipairs(PL.MODES) do modes[i] = m[2] end
  for i, n in ipairs(PL.CRAFTS) do crafts[i] = tostring(n) end
  local function line(children, top)
    return UI.Row{ style = { alignItems = "center", marginTop = top or 4 }, children = children }
  end
  local id = plRecipeId()
  local rec = id and plRecipe(id)
  local first = rec and tostring(T.Field(rec, "name")) or PL.NO_RECIPE
  plMatches = {}
  if rec then plMatches[first] = id end
  plEl = {
    find = UI.TextField{ id = "pl_find", text = "", placeholder = "Part of a recipe's name: plate chest...",
      maxLength = 60, style = { flexGrow = 1, flexShrink = 1 },
      tooltip = "Search the recipes you know", onSubmit = function(_, text) plFind(text) end },
    recipe = UI.Dropdown{ id = "pl_recipe", choices = { first }, value = first,
      style = { flexGrow = 1, flexShrink = 1 },
      tooltip = "The recipe planned (Find lists the ones matching)",
      onChange = function(_, name)
        local rid = plMatches[name]
        if rid and rid ~= plRecipeId() then PL.SetRecipe(rid) end
      end },
    crafts = UI.Dropdown{ id = "pl_crafts", choices = crafts, value = tostring(PL.GetCrafts()),
      tooltip = "How many times to craft it", onChange = function(_, v) PL.SetCrafts(tonumber(v)) end },
    title = UI.Label{ id = "pl_title", text = "", class = "text", style = { flexGrow = 1, flexShrink = 1,
      whiteSpace = "wrap", marginLeft = 6 } },
    mode = UI.Dropdown{ id = "pl_mode", choices = modes, value = modes[1],
      tooltip = "How each slot's material is picked: the first you have enough of, or the best for the stats you"
        .. " watch (a slot you pick yourself keeps your pick)",
      onChange = function(_, v) PL.SetMode(v == PL.MODES[2][2] and "stats" or "have") end },
    scratch = UI.Toggle{ id = "pl_scratch", text = "From scratch", value = PL.GetScratch(),
      tooltip = "Offer Make it for what you're short of and one of your recipes makes",
      onChange = function(_, on) PL.SetScratch(on == true) end },
    stat = UI.Dropdown{ id = "pl_stat", choices = { PL.NO_STATS }, value = PL.NO_STATS,
      style = { flexGrow = 1, flexShrink = 1 }, tooltip = "The stats this recipe and its materials give",
      onChange = function() plMsg("") end },
    watching = UI.Label{ id = "pl_watching", text = "", class = "dim", style = { whiteSpace = "wrap" } },
    view = UI.Dropdown{ id = "pl_view", choices = PL.VIEWS, value = PL.GetView(),
      tooltip = "The slots, what to buy or gather, or the crafts in order by station",
      onChange = function(_, v) PL.SetView(v) end },
    result = UI.Label{ id = "pl_result", text = "", class = "text", style = { whiteSpace = "wrap" },
      tooltip = "The result's base stats, plus what the picked materials add (an exceptional craft adds more)" },
    msg = UI.Label{ id = "pl_msg", text = "", class = "dim", style = { whiteSpace = "wrap" } },
  }
  plEl.statRow = UI.Column{ id = "pl_stats", visible = false, children = {
    line({ plEl.stat,
      UI.Button{ id = "pl_watch", text = "Watch", style = { marginLeft = 4 },
        tooltip = "Show this stat on every choice; the newest watched is the one the picks follow",
        onClick = function()
          local key = plStatChoices[plEl.stat:GetValue()]
          if not key then return end
          local ok, why = PL.Watch(key)
          plMsg(ok and "" or ("Can't watch it: " .. why .. "."))
          PL.Refresh(true)
        end },
      UI.Button{ id = "pl_unwatch", text = "Stop", style = { marginLeft = 2 },
        tooltip = "Stop watching this stat",
        onClick = function()
          local key = plStatChoices[plEl.stat:GetValue()]
          if key and PL.Unwatch(key) then PL.Refresh(true) end
        end } }),
    plEl.watching } }
  plBody = UI.Column{ id = "pl_body", style = { paddingRight = 4 } }
  plWin = UI.Window{
    id = PL.WINDOW_ID, title = "Crafting planner", width = 500, height = 460, minWidth = 380, minHeight = 300,
    x = T.Window.DEFAULT_X, y = T.Window.DEFAULT_Y, escCloses = true,
    style = { paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 6 },
    children = {
      line({ plEl.find, UI.Button{ id = "pl_find_go", text = "Find", style = { marginLeft = 4 },
        tooltip = "List the recipes you know with this in their name", onClick = function() plFind() end } }, 0),
      line({ UI.Label{ text = "Recipe", class = "text", style = { marginRight = 6 } }, plEl.recipe }),
      line({ UI.Label{ text = "Crafts", class = "text", style = { marginRight = 6 } }, plEl.crafts, plEl.title }),
      line({ plEl.mode, UI.Label{ text = "", style = { flexGrow = 1 } }, plEl.scratch }),
      plEl.statRow,
      line({ UI.Label{ text = "Show", class = "text", style = { marginRight = 6 } }, plEl.view }),
      UI.Scroll{ style = { flexGrow = 1, marginTop = 4 }, children = { plBody } },
      plEl.result,
      plEl.msg,
    },
  }
end

function PL.IsShown() return plWin ~= nil and plWin:IsShown() end
function PL.LastPlan() return plPlan end

-- Opens the planner (or closes it when it's open and `text` is empty); `text`: a recipe to find. True when shown.
function PL.Open(text)
  text = T.Trim(text or "")
  if PL.IsShown() and text == "" then
    plWin:Hide()
    return false
  end
  if type(ShroudGetRecipe) ~= "function" or type(ShroudGetKnownRecipes) ~= "function" then
    T.Print("This game client has no recipe calls for add-ons (the planner needs Lua API 18; material choices 37).")
    return false
  end
  if not plWin then
    T.TakeSharedWindow("planner", plDrop)
    local ok, err = pcall(plBuild)
    if not ok then
      plDrop()
      T.Print("The crafting planner can't open right now; try again in a moment. (" .. tostring(err) .. ")")
      return false
    end
  end
  if not plWin:IsShown() and not plWin:Show() then
    T.Print("The crafting planner can't reopen right now; try again in a few seconds.")
    return false
  end
  plBodySig = nil
  if text ~= "" then
    plFind(text)
  else
    PL.Refresh(true)
  end
  return true
end

-- T.ViewsTick: a change since the last refresh shows (at most every PL.REFRESH_GAP s).
function PL.Tick()
  if plDirty and PL.IsShown() then PL.Refresh(false) end
end

-- Your bags, the table or the book changed (ShroudOnInventoryChanged, ShroudOnCraftingStateChanged,
-- ShroudOnRecipesChanged): the plan is worked out again.
function PL.Changed()
  plDirty = true
end

-- ShroudOnCraftResults: the crafts made for the build order's "made" counts.
function PL.OnCraftResults(results)
  if not plRecipeId() then return end
  for _, r in ipairs(T.List(results)) do
    local id, n = plNum(T.Field(r, "recipeId")), plNum(T.Field(r, "crafted")) or 0
    if id and n > 0 and (plBuilt[id] or id == plRecipeId()) then plMade[id] = (plMade[id] or 0) + n end
  end
  plDirty = true
end

-- Re-runnable (another character): its own plan and picks; the window, built for the last one, goes.
function PL.Init()
  if plWin then plDrop() end
  local saved = T.ReadSaved(PL.KEY)
  plPrefs = type(saved) == "table" and saved or {}
  plPrefs.v = 1
  plFresh, plBuilt, plMade, plPlan = {}, {}, {}, nil
end

T.Backup.OTHER_KEYS[#T.Backup.OTHER_KEYS + 1] = PL.KEY
