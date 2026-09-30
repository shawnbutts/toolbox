-- Settings backup, restore and reset (Toolbox.Backup; /toolbox settings; settings: Backup & reset).
local H = require("harness")

return function(t)
  local B = function() return Toolbox.Backup end
  local function backup() return H.saved("settings_backup", "account") end
  -- /lua reload as the game does it: the add-on is shut down (the windows write their positions), then loaded.
  local function reloadForReal()
    H.callback("ShroudOnDisableScript")
    H.reload()
  end
  -- Settings to back up: buff icon size 24, health bars at 200%, the XP window open at 300, 400.
  local function customise()
    H.chat("/tbx buffs")
    Toolbox.BuffBar.SetSize(24)
    H.chat("/tbx vitals size 200")
    H.chat("/tbx xp")
    H.moveWindow("toolbox_compact", 300, 400)
  end

  -- Saved keys that aren't settings: state, stats, histories, caches.
  local NOT_BACKED_UP = { session = true, daily = true, buff_timers = true, skill_levels = true,
    notify_history = true, prices = true, welcomed = true, guild_motd = true, settings_backup = true,
    settings_pending = true }

  t.test("every saved key is a setting, learned data or listed as neither", function()
    H.boot()
    local known = {}
    for _, k in ipairs(B().KEYS) do known[k] = true end
    for _, k in ipairs(B().DATA_KEYS) do known[k] = true end
    for k in pairs(NOT_BACKED_UP) do known[k] = true end
    local seen = 0
    local manifest = io.open(H.PACKAGE .. "/manifest.json"):read("*a")
    for file in manifest:gmatch('"([%w_]+%.lua)"') do
      local src = io.open(H.PACKAGE .. "/" .. file):read("*a")
      for _, pat in ipairs({ 'T%.Save%("([%w_]+)"', 'T%.Load%("([%w_]+)"', 'SavedVar%("([%w_]+)"' }) do
        for key in src:gmatch(pat) do
          seen = seen + 1
          t.ok(known[key], file .. " saves '" .. key .. "': add it to Backup.KEYS, DATA_KEYS or NOT_BACKED_UP")
        end
      end
    end
    t.ok(seen >= 20, "the scan found the keys: " .. seen)
  end)

  t.test("backup: every setting and position, for the account; not stats, not what was delivered", function()
    H.boot()
    customise()
    H.setGuild("Guild", "Welcome, all")               -- the guild message is delivered: notify remembers it
    H.advance(5)
    t.ok(H.saved("notify").sources.motd.seen ~= nil, "delivered")
    H.clearLogs()
    H.chat("/tbx settings backup")
    t.ok(H.logged("^Settings backed up: .*%(Tester, Toolbox "), H.lastLog())
    t.ok(H.logged("copy Toolbox's %.account%.json file"))
    local b = backup()
    t.eq(b.v, 1)
    t.eq(b.from, "Tester")
    t.eq(b.version, Toolbox.version)
    t.eq(b.keys.buffbar.size, 24)
    t.eq(b.keys.vitals.scale, 200)
    t.eq(b.keys.compact.x, 300, "the XP window's position, though it is only saved at shutdown otherwise")
    t.eq(b.keys.compact.y, 400)
    t.eq(b.keys.notify.sources.motd.seen, nil, "what was delivered isn't a setting")
    t.eq(b.keys.notify.sources.motd.on, true)
    t.eq(b.keys.session, nil, "no XP session")
    t.eq(b.keys.daily, nil, "no stats")
    t.ok(H.S.disk.account.settings_backup ~= nil, "written to disk at once, ready to copy")
    H.clearLogs()
    H.chat("/tbx settings")
    t.ok(H.logged("^Last backup: .*%(Tester, Toolbox "), H.lastLog())
  end)

  t.test("restore: waits for the next start, then every setting and position comes back", function()
    H.boot()
    customise()
    H.chat("/tbx settings backup")
    Toolbox.BuffBar.SetSize(40)                       -- changed after the backup
    H.chat("/tbx vitals size 100")
    H.moveWindow("toolbox_compact", 10, 20)
    H.clearLogs()
    H.chat("/tbx settings restore")
    t.ok(H.logged("when Toolbox next starts: type /lua reload now"), H.lastLog())
    t.eq(Toolbox.BuffBar.GetSize(), 40, "nothing changes yet")
    reloadForReal()                                   -- the XP window writes 10, 20 at shutdown
    t.ok(H.logged("settings were restored from the backup of"))
    t.eq(Toolbox.BuffBar.GetSize(), 24)
    t.eq(H.saved("vitals").scale, 200)
    t.eq(H.S.windows.toolbox_compact.x, 300, "the backup's position, not the one written at shutdown")
    t.eq(H.S.windows.toolbox_compact.y, 400)
    t.eq(B().Pending(), nil, "done once")
    H.clearLogs()
    H.reload()
    t.no(H.logged("restored"), "not again")
  end)

  t.test("restore keeps what this character was already told", function()
    H.boot()
    H.chat("/tbx settings backup")                    -- before the guild message
    H.setGuild("Guild", "Welcome, all")
    H.advance(5)
    local seen = H.saved("notify").sources.motd.seen
    t.ok(seen ~= nil)
    H.chat("/tbx settings restore")
    reloadForReal()
    t.eq(H.saved("notify").sources.motd.seen, seen)
  end)

  t.test("a backup restores on another computer (only the account file copied) and another character", function()
    H.boot()
    customise()
    H.chat("/tbx settings backup")
    local account = H.S.disk.account
    H.boot({ account = account })                      -- a new install: no character file yet
    t.no(Toolbox.BuffBar.IsEnabled(), "a new install starts from the defaults")
    H.chat("/tbx settings restore")
    reloadForReal()
    t.eq(Toolbox.BuffBar.GetSize(), 24)
    t.ok(Toolbox.BuffBar.IsEnabled())
    t.eq(H.saved("vitals").scale, 200)
  end)

  t.test("learned buff lengths travel with the backup, without replacing what this install learned", function()
    H.boot()
    H.S.memory["character:Tester"].buff_durations = { v = 2, durations = { Light = 1200, Ward = 60 } }
    H.chat("/tbx settings backup")
    t.eq(backup().keys.buff_durations.durations.Light, 1200)
    H.boot({ account = H.S.disk.account, ["character:Tester"] = {
      buff_durations = { v = 2, durations = { Ward = 90, Heal = 30 } } } })
    H.chat("/tbx settings restore")
    reloadForReal()
    local d = H.saved("buff_durations").durations
    t.eq(d.Light, 1200, "learned elsewhere: added")
    t.eq(d.Ward, 90, "this install's own kept")
    t.eq(d.Heal, 30)
  end)

  t.test("reset: every setting and position to its default; stats, learned lengths and the backup stay", function()
    H.boot()
    customise()
    H.chat("/tbx settings backup")
    H.goldChange(250)
    H.advance(2)
    local gold = H.saved("daily").gold
    t.ok(gold > 0)
    H.S.memory["character:Tester"].buff_durations = { v = 2, durations = { Light = 1200 } }
    H.setGuild("Guild", "Welcome, all")
    H.advance(5)
    local seen = H.saved("notify").sources.motd.seen
    H.clearLogs()
    H.chat("/tbx settings reset")
    t.ok(H.logged("will go back to its default when Toolbox next starts"), H.lastLog())
    reloadForReal()
    t.ok(H.logged("settings are back to their defaults"))
    t.eq(Toolbox.BuffBar.GetSize(), Toolbox.BuffBar.SIZE_DEFAULT)
    t.no(Toolbox.BuffBar.IsEnabled())
    t.eq(H.saved("vitals"), nil)
    t.eq(H.saved("daily").gold, gold, "today's stats kept")
    t.eq(H.saved("buff_durations").durations.Light, 1200)
    t.eq(H.saved("notify").sources.motd.seen, seen, "the guild message isn't shown again")
    t.ok(backup() ~= nil, "the backup kept")
    t.eq(backup().keys.buffbar.size, 24)
  end)

  t.test("cancel drops a waiting restore; restore without a backup says so", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx settings restore")
    t.ok(H.logged("Nothing to restore: there is no backup yet"), H.lastLog())
    t.eq(B().Pending(), nil)
    H.chat("/tbx buffs")
    H.chat("/tbx settings reset")
    H.clearLogs()
    H.chat("/tbx settings")
    t.ok(H.logged("A reset is waiting: type /lua reload"))
    H.chat("/tbx settings cancel")
    t.ok(H.logged("Dropped the waiting"))
    reloadForReal()
    t.ok(Toolbox.BuffBar.IsEnabled(), "nothing was reset")
    H.clearLogs()
    H.chat("/tbx settings cancel")
    t.ok(H.logged("Nothing was waiting"))
  end)

  t.test("settings window: Back up now, Restore and Reset take a second click, Cancel", function()
    H.boot()
    H.chat("/tbx config")
    local cfg = H.config()
    t.eq(cfg:Find("backup_status").text, "No backup yet.")
    t.eq(cfg:Find("backup_restore").enabled, false, "nothing to restore")
    t.eq(cfg:Find("backup_cancel").enabled, false)
    H.click("toolbox_config", "backup_now")
    t.ok(cfg:Find("backup_status").text:find("^Last backup: "), cfg:Find("backup_status").text)
    t.ok(cfg:Find("backup_msg").text:find("^Backed up: "))
    H.click("toolbox_config", "backup_restore")
    t.eq(cfg:Find("backup_restore").text, "Click again to confirm")
    t.eq(B().Pending(), nil, "one click does nothing")
    H.advance(Toolbox.Config.CONFIRM_SECONDS + 1)
    t.eq(cfg:Find("backup_restore").text, "Restore backup", "the confirmation runs out")
    H.click("toolbox_config", "backup_restore")
    H.click("toolbox_config", "backup_restore")
    t.eq(B().Pending().kind, "restore")
    t.eq(cfg:Find("backup_pending").visible, true)
    t.ok(cfg:Find("backup_pending").text:find("A restore is waiting"))
    t.eq(cfg:Find("backup_cancel").enabled, true)
    H.click("toolbox_config", "backup_cancel")
    t.eq(B().Pending(), nil)
    t.eq(cfg:Find("backup_pending").visible, false)
    H.click("toolbox_config", "settings_reset")
    H.click("toolbox_config", "settings_reset")
    t.eq(B().Pending().kind, "reset")
    t.ok(cfg:Find("backup_msg").text:find("Reset waiting"))
  end)
end
