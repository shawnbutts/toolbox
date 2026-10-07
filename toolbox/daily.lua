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
-- kinds, nodes, value = estimated gold or nil } } }. A run under D.RUN_MIN s of play isn't kept.
-- ---------------------------------------------------------------------------
D.RUNS_KEEP, D.RUN_MIN = 10, 60
D.runsVersion = 0
local runs, runsFor = nil, nil

local function isRun(r)
  return type(r) == "table" and isCount(r.played) and isCount(r.gold) and isCount(r.kills)
end

-- This character's filed runs, newest first (read once per character).
function D.Runs()
  local who = ShroudGetPlayerName()
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
  D.dayFor = ShroudGetPlayerName()     -- whose day D.day is
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

local function countPlay(hasCharacter)
  local s = D.day.since
  local now = T.Now()
  if type(s) == "table" and hasCharacter and lastPlayAt then
    local dt = now - lastPlayAt
    if dt > 0 and dt <= D.PLAY_GAP then
      local before = math.floor((s.played or 0) / D.PLAY_SAVE)
      s.played = (s.played or 0) + dt
      if math.floor(s.played / D.PLAY_SAVE) ~= before then D.unsaved = true end
      local okScene, scene = pcall(ShroudGetCurrentSceneName)
      if okScene and type(scene) == "string" and scene ~= "" then
        if type(s.scenes) ~= "table" then s.scenes = {} end
        local n = 0
        for _ in pairs(s.scenes) do n = n + 1 end
        if s.scenes[scene] or n < D.SCENES_MAX then s.scenes[scene] = (s.scenes[scene] or 0) + dt end
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
  if D.unsaved then D.Save() end
end

-- A new login or character (not a reload), with that character's current totals:
-- load its day and start counting from now.
function D.OnLogin(adv, prod)
  -- Already this character's (loaded at its scene, before its totals came): keep what it counted since.
  if D.day and D.dayFor == ShroudGetPlayerName() then
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
      T.unsaved = true
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
    T.unsaved = true
  end
end

function D.OnItems(items, dropped)
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

local function readSome()
  local r = reading
  if not r then return end
  local stop = math.min(#r.list, r.at + D.BOOK_STEP - 1)
  for i = r.at, stop do
    local id = type(T.Field(r.list[i], "id")) == "number" and T.Field(r.list[i], "id") or nil
    if id then
      local ok, rec = pcall(ShroudGetRecipe, id)
      if ok and rec then
        r.recipes[id] = rec
        for _, res in ipairs(T.List(T.Field(rec, "results"))) do
          local name = T.Field(res, "name")
          if type(name) == "string" then
            r.byResult[name] = r.byResult[name] or {}
            local makers = r.byResult[name]
            local q = T.Field(res, "quantity")
            makers[#makers + 1] = { id = id, yield = type(q) == "number" and q or 0 }
          end
        end
      end
    end
  end
  r.at = stop + 1
  if r.at > #r.list then
    pcall(ShroudRemovePeriodic, BOOK_TIMER)
    reading = nil
    D.recipeIndex = { recipes = r.recipes, byResult = r.byResult }
    for _, done in ipairs(r.waiting) do done(true) end
  end
end

-- Reads the recipe book a few recipes at a time, then calls done(true) (done(false) if it was dropped).
-- Returns how many recipes it reads, or nil when there's nothing to read (no book: done isn't called).
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
  reading = { list = list, at = 1, recipes = {}, byResult = {}, waiting = { done } }
  ShroudRegisterPeriodic(BOOK_TIMER, readSome, D.BOOK_PERIOD, true)
  return #list
end
D.PROBE_DEPTH = 8
D.PROBE_LINES = 80
D.PROBE_MATCHES = 15
local INGREDIENT_FIELDS = { name = true, quantity = true, have = true, optional = true, tool = true }
local RECIPE_FIELDS = { id = true, name = true, category = true, categoryKey = true, requiredLevel = true,
                        refine = true, ingredients = true, results = true, result = true }

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
  local extra = extraFields(rec, RECIPE_FIELDS)
  if extra ~= "" then say("  other fields: " .. extra) end
  local results = T.List(T.Field(rec, "results"))
  if #results == 0 then say("  Makes: no fixed yield (a rolled result)") end
  for _, res in ipairs(results) do
    local more = extraFields(res, { name = true, quantity = true })
    say("  Makes " .. tostring(T.Field(res, "quantity")) .. " x " .. tostring(T.Field(res, "name"))
      .. (more ~= "" and ("  {" .. more .. "}") or ""))
  end
  say("Ingredients, as the game gives them:")
  for _, ing in ipairs(T.List(T.Field(rec, "ingredients"))) do
    local flags = {}
    if T.Field(ing, "optional") == true then flags[#flags + 1] = "optional" end
    if T.Field(ing, "tool") == true then flags[#flags + 1] = "tool" end
    local more = extraFields(ing, INGREDIENT_FIELDS)
    say("  " .. tostring(T.Field(ing, "quantity")) .. " x " .. tostring(T.Field(ing, "name")) .. " (have "
      .. tostring(T.Field(ing, "have")) .. ")" .. (#flags > 0 and (" [" .. table.concat(flags, ", ") .. "]") or "")
      .. (more ~= "" and ("  {" .. more .. "}") or ""))
  end

  -- from scratch: through the first known recipe that makes each ingredient
  say("From scratch, through the recipes you know:")
  local raw = {}
  local function expand(name, qty, depth, seen)
    local pad = string.rep("  ", depth)
    local makers = byResult[name]
    if not makers or depth >= D.PROBE_DEPTH or seen[name] then
      say(pad .. qty .. " x " .. name .. (seen[name] and "  (made from itself: stops here)" or ""))
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
      say(pad .. qty .. " x " .. name .. "  <- " .. tostring(T.Field(mrec, "name")) .. " (no fixed yield: stops here)")
      raw[name] = (raw[name] or 0) + qty
      return
    end
    local crafts = math.floor((qty + m.yield - 1) / m.yield)
    say(pad .. qty .. " x " .. name .. "  <- " .. crafts .. " x " .. tostring(T.Field(mrec, "name")) .. " ("
      .. tostring(T.Field(mrec, "category")) .. ", makes " .. m.yield .. ")"
      .. (#also > 0 and ("  [also made by: " .. table.concat(also, "; ") .. "]") or ""))
    seen[name] = true
    for _, ing in ipairs(T.List(T.Field(mrec, "ingredients"))) do
      local iname, iqty = T.Field(ing, "name"), number(T.Field(ing, "quantity")) or 0
      if type(iname) == "string" and T.Field(ing, "tool") ~= true and T.Field(ing, "optional") ~= true then
        expand(iname, iqty * crafts, depth + 1, seen)
      end
    end
    seen[name] = nil
  end
  for _, ing in ipairs(T.List(T.Field(rec, "ingredients"))) do
    local iname, iqty = T.Field(ing, "name"), number(T.Field(ing, "quantity")) or 0
    if type(iname) == "string" and T.Field(ing, "tool") ~= true and T.Field(ing, "optional") ~= true then
      expand(iname, iqty, 1, {})
    end
  end
  local names = {}
  for n in pairs(raw) do names[#names + 1] = n end
  table.sort(names)
  say("Raw materials in all (tools and optional ones left out):")
  for _, n in ipairs(names) do say("  " .. raw[n] .. " x " .. n) end
  return lines
end
