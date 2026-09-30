-- Settings files and reset (Toolbox.Backup; /toolbox settings; settings: Backup & reset).
local H = require("harness")

return function(t)
  local B = function() return Toolbox.Backup end
  -- /lua reload as the game does it: the add-on is shut down (the windows write their positions), then loaded.
  local function reloadForReal()
    H.callback("ShroudOnDisableScript")
    H.reload()
  end

  -- Saved keys that a reset leaves alone: state, stats, histories, caches, learned data.
  local KEPT = { session = true, daily = true, buff_timers = true, buff_durations = true, skill_levels = true,
    notify_history = true, prices = true, welcomed = true, guild_motd = true, settings_pending = true }

  t.test("every saved key is a setting (reset clears it) or listed as kept", function()
    H.boot()
    local known = {}
    for _, k in ipairs(B().KEYS) do known[k] = true end
    for k in pairs(KEPT) do known[k] = true end
    local seen = 0
    local manifest = io.open(H.PACKAGE .. "/manifest.json"):read("*a")
    for file in manifest:gmatch('"([%w_]+%.lua)"') do
      local src = io.open(H.PACKAGE .. "/" .. file):read("*a")
      for _, pat in ipairs({ 'T%.Save%("([%w_]+)"', 'T%.Load%("([%w_]+)"', 'SavedVar%("([%w_]+)"' }) do
        for key in src:gmatch(pat) do
          seen = seen + 1
          t.ok(known[key], file .. " saves '" .. key .. "': add it to Backup.KEYS (reset clears it) or KEPT")
        end
      end
    end
    t.ok(seen >= 20, "the scan found the keys: " .. seen)
  end)

  t.test("/toolbox settings says where the files are and how to copy them back", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx settings")
    t.ok(H.logs()[1]:find("in /Users/tester/SotA/Lua/SavedVariables:", 1, true), H.logs()[1])
    t.ok(H.logged("^  toolbox%.Tester%.character%.json %(this character's settings"), H.logs()[2])
    t.ok(H.logged(" and toolbox%.account%.json %(shared by all your characters%)"))
    t.ok(H.logged("quit the game first"))
    H.S.luaPath = "C:\\Games\\SotA\\Lua\\"                    -- Windows, with a trailing separator
    H.reload()
    H.clearLogs()
    H.chat("/tbx settings")
    t.ok(H.logs()[1]:find("in C:\\Games\\SotA\\Lua\\SavedVariables:", 1, true), H.logs()[1])
  end)

  t.test("save now writes positions and settings to disk, ready to copy", function()
    H.boot()
    H.chat("/tbx xp")
    H.moveWindow("toolbox_compact", 300, 400)                -- tracked only once a second otherwise
    H.clearLogs()
    H.chat("/tbx settings save")
    t.ok(H.logged("^Saved: the files are up to date"), H.lastLog())
    local disk = H.S.disk["character:Tester"]
    t.eq(disk.compact.x, 300)
    t.eq(disk.compact.y, 400)
  end)

  t.test("reset: every setting and position to its default at the next start; stats and learned data stay", function()
    H.boot()
    H.chat("/tbx buffs")
    Toolbox.BuffBar.SetSize(24)
    H.chat("/tbx vitals size 200")
    H.goldChange(250)
    H.advance(2)
    local gold = H.saved("daily").gold
    t.ok(gold > 0)
    H.S.memory["character:Tester"].buff_durations = { v = 2, durations = { Light = 1200 } }
    H.setGuild("Guild", "Welcome, all")
    H.advance(5)
    local seen = H.saved("notify").sources.motd.seen
    t.ok(seen ~= nil)
    H.clearLogs()
    H.chat("/tbx settings reset")
    t.ok(H.logged("will go back to its default when Toolbox next starts"), H.lastLog())
    t.eq(Toolbox.BuffBar.GetSize(), 24, "nothing changes yet")
    reloadForReal()                                         -- the windows write their prefs at shutdown
    t.ok(H.logged("settings are back to their defaults"))
    t.eq(Toolbox.BuffBar.GetSize(), Toolbox.BuffBar.SIZE_DEFAULT)
    t.no(Toolbox.BuffBar.IsEnabled())
    t.eq(H.saved("vitals"), nil)
    t.eq(H.saved("daily").gold, gold, "today's stats kept")
    t.eq(H.saved("buff_durations").durations.Light, 1200)
    t.eq(H.saved("notify").sources.motd.seen, seen, "the guild message isn't shown again")
    t.eq(B().Pending(), nil, "done once")
    H.clearLogs()
    H.reload()
    t.no(H.logged("back to their defaults"), "not again")
  end)

  t.test("cancel drops a waiting reset", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx settings reset")
    H.clearLogs()
    H.chat("/tbx settings")
    t.ok(H.logged("A reset is waiting: type /lua reload"))
    H.chat("/tbx settings cancel")
    t.ok(H.logged("Dropped the waiting reset"))
    reloadForReal()
    t.ok(Toolbox.BuffBar.IsEnabled(), "nothing was reset")
    H.clearLogs()
    H.chat("/tbx settings cancel")
    t.ok(H.logged("Nothing was waiting"))
  end)

  t.test("settings window: where the files are, Save now; Reset takes a second click; Cancel", function()
    H.boot()
    H.chat("/tbx config")
    local cfg = H.config()
    t.ok(cfg:Find("backup_where").text:find("/Users/tester/SotA/Lua/SavedVariables", 1, true))
    H.click("toolbox_config", "backup_save")
    t.ok(cfg:Find("backup_msg").text:find("^Saved"))
    t.eq(cfg:Find("backup_cancel").enabled, false)
    H.click("toolbox_config", "settings_reset")
    t.eq(cfg:Find("settings_reset").text, "Click again to confirm")
    t.eq(B().Pending(), nil, "one click does nothing")
    H.advance(Toolbox.Config.CONFIRM_SECONDS + 1)
    t.eq(cfg:Find("settings_reset").text, "Reset all settings", "the confirmation runs out")
    H.click("toolbox_config", "settings_reset")
    H.click("toolbox_config", "settings_reset")
    t.eq(B().Pending().kind, "reset")
    t.eq(cfg:Find("backup_pending").visible, true)
    t.eq(cfg:Find("backup_cancel").enabled, true)
    t.ok(cfg:Find("backup_msg").text:find("Reset waiting"))
    H.click("toolbox_config", "backup_cancel")
    t.eq(B().Pending(), nil)
    t.eq(cfg:Find("backup_pending").visible, false)
  end)
end
