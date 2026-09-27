-- Headless test runner. From the repo root:  lua tests/run.lua   (or luajit tests/run.lua)
-- Optional filter:  lua tests/run.lua rolling

local ROOT = (arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]")) or "."
package.path = ROOT .. "/tests/?.lua;" .. package.path

local filter = arg and arg[1]
local suites = {
  "test_xp", "test_commands", "test_session", "test_config", "test_compact", "test_hover",
  "test_daily", "test_dailydetail", "test_buffbar", "test_vitals", "test_hud", "test_combat", "test_strips",
  "test_motd",
}

local tests = {}
local current_suite

-- Tiny assertion library shared by the suites.
local t = {}
function t.test(name, fn) tests[#tests + 1] = { suite = current_suite, name = name, fn = fn } end
local function fail(msg, level) error(msg, (level or 1) + 2) end
function t.eq(actual, expected, msg)
  if actual ~= expected then
    fail(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(actual)))
  end
end
function t.near(actual, expected, tol, msg)
  tol = tol or 1e-6
  if type(actual) ~= "number" or math.abs(actual - expected) > tol then
    fail(string.format("%sexpected ~%s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(actual)))
  end
end
function t.ok(v, msg) if not v then fail(msg or "expected truthy value") end end
function t.no(v, msg) if v then fail(msg or ("expected falsy value, got " .. tostring(v))) end end
function t.raises(fn, pattern)
  local ok, err = pcall(fn)
  if ok then fail("expected an error") end
  if pattern and not tostring(err):find(pattern) then
    fail("error did not match '" .. pattern .. "': " .. tostring(err))
  end
end

for _, name in ipairs(suites) do
  current_suite = name
  require(name)(t)
end

local passed, failed = 0, 0
for _, case in ipairs(tests) do
  local label = case.suite .. ": " .. case.name
  if not filter or label:find(filter, 1, true) then
    local ok, err = pcall(case.fn)
    if ok then
      passed = passed + 1
      print("ok    " .. label)
    else
      failed = failed + 1
      print("FAIL  " .. label .. "\n      " .. tostring(err))
    end
  end
end

local jit = rawget(_G, "jit")
local runtime = _VERSION .. (jit and (" / " .. jit.version) or "")
print(string.format("\n%d passed, %d failed (%s)", passed, failed, runtime))
os.exit(failed == 0 and 0 or 1)
