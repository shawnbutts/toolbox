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
    notify_history = true, prices = true, welcomed = true, guild_motd = true, settings_pending = true,
    loot_runs = true, skills_paused = true, map_overlays = true, recovery_index = true }

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

  t.test("refusals are reported, not shown as done: save now, reset, cancel, and the reset itself", function()
    H.boot()
    H.S.flushFails = true
    H.clearLogs()
    H.chat("/tbx settings save")
    t.ok(H.logged("The game refused to write the files"), H.lastLog())
    H.clearLogs()
    H.chat("/tbx settings reset")
    t.ok(H.logged("^Couldn't ask for a reset: the game couldn't write it to disk"), H.lastLog())
    H.clearLogs()
    H.chat("/tbx settings cancel")
    t.ok(H.logged("The game couldn't write that to disk"), H.lastLog())
    H.S.flushFails = false
    H.S.saveRefused = true
    H.clearLogs()
    H.chat("/tbx settings reset")
    t.ok(H.logged("^Couldn't ask for a reset: the game refused to store the request"), H.lastLog())
    t.eq(B().Pending(), nil)
    H.S.saveRefused = false
    H.chat("/tbx buffs")
    H.chat("/tbx settings reset")
    H.callback("ShroudOnDisableScript")
    H.S.flushFails = true                              -- the reset happens, but can't be written
    H.clearLogs()
    H.reload()
    t.ok(H.logged("back to their defaults for now, but the game couldn't write them to disk"))
    t.no(Toolbox.BuffBar.IsEnabled(), "defaults in this session")
    H.S.flushFails = false
    H.chat("/tbx config")
    H.S.flushFails = true
    H.click("toolbox_config", "settings_reset")
    H.click("toolbox_config", "settings_reset")
    t.ok(H.config():Find("backup_msg").text:find("^Couldn't ask for a reset"), H.config():Find("backup_msg").text)
    H.click("toolbox_config", "backup_save")
    t.ok(H.config():Find("backup_msg").text:find("refused"), H.config():Find("backup_msg").text)
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

  -- Owner, 2026-10-07: the game wrote a saved "/" as "\/" and then refused to load the file, dropping every
  -- setting of the character. The harness raises for a "/" in saved text; here text with "/" and "%" goes
  -- through sounds, muted effects, the Loot Tracker and the price cache, and comes back whole after a restart.
  t.test("text with / and % is saved without a slash and reads back the same", function()
    H.boot()
    Toolbox.Sounds.SetPath("buff_expiring", "my sounds/ding 100%.ogg")
    Toolbox.BuffBar.Mute("Ward/Shield")
    H.items({ { "Half/Half Ale", 2 }, { "100% Cotton", 1 } })
    H.advance(2)
    t.ok(H.S.memory["character:Tester"].sounds.paths.buff_expiring:find("%2F", 1, true), "stored encoded")
    H.restart(nil, true)
    t.eq(Toolbox.Sounds.GetPath("buff_expiring"), "my sounds/ding 100%.ogg")
    t.ok(Toolbox.BuffBar.IsMuted("Ward/Shield"))
    t.eq(Toolbox.Daily.day.items["Half/Half Ale"], 2)
    t.eq(Toolbox.Daily.day.items["100% Cotton"], 1)
  end)

  -- 2026-10-08: the game's loader refused a saved negative number ("Unexpected token : '-'") and dropped the file.
  t.test("negative, tiny and huge numbers are saved as text and read back as the numbers", function()
    H.boot()
    local T = Toolbox
    T.Save("location", { show = false, x = -40, y = 12.5, tiny = 0.00002, huge = 2e15, zero = -0.0,
                         nan = 0 / 0, list = { -1, 2, -3.25 }, text = "%N-5" })
    local raw = H.S.memory["character:Tester"].location
    t.eq(raw.x, "%N-40")
    t.eq(raw.y, 12.5, "an ordinary number stays a number")
    t.eq(type(raw.tiny), "string")
    t.eq(type(raw.huge), "string")
    t.eq(raw.zero, 0)
    t.eq(raw.nan, nil, "NaN isn't saved")
    t.eq(raw.text, "%25N-5", "text that looks like one stays text")
    H.restart(nil, true)
    local back = T.ReadSaved("location")
    t.eq(back.x, -40)
    t.eq(back.y, 12.5)
    t.eq(back.tiny, 0.00002)
    t.eq(back.huge, 2e15)
    t.eq(back.list[1], -1)
    t.eq(back.list[3], -3.25)
    t.eq(back.text, "%N-5")
  end)

  -- Saving only what the game's reader is known to take (owner, 2026-10-08, after the second lost file).
  t.test("any text is saved as plain ASCII and reads back the same; older text reads unchanged", function()
    H.boot()
    local T = Toolbox
    local text = 'say "hi"\\ back/slash\nnew line, 100% \195\132pfel %u00E4 %N5'
    T.Save("location", { note = text, [text] = true })
    local raw = H.S.memory["character:Tester"].location
    t.ok(not raw.note:find("[^ -~]"), "printable ASCII only: " .. raw.note)
    t.ok(not raw.note:find('["\\/]'), "no quote, backslash or slash: " .. raw.note)
    H.restart(nil, true)
    local back = T.ReadSaved("location")
    t.eq(back.note, text)
    t.eq(back[text], true, "keys too")
    H.S.memory["character:Tester"].legacy = { a = "100% sure", b = "Ward%2FShield", c = "plain" }
    local old = T.ReadSaved("legacy")
    t.eq(old.a, "100% sure")
    t.eq(old.b, "Ward/Shield")
    t.eq(old.c, "plain")
    t.eq(H.S.memory["character:Tester"].location[T.SAVE_FORMAT_KEY], 1, "saved marked")
    t.eq(back[T.SAVE_FORMAT_KEY], nil, "the mark isn't read back")
    -- review 23 (owner: upgrades from 1.3.0 on): as 1.3.0 saved text (as typed, unmarked), it reads as typed
    H.S.memory["character:Tester"].legacy = { a = "cost%20gold", b = "literal%u0041", c = "%N5", d = -4,
      ["key%20x"] = { "%41" } }
    old = T.ReadSaved("legacy")
    t.eq(old.a, "cost%20gold")
    t.eq(old.b, "literal%u0041")
    t.eq(old.c, "%N5", "text, not a number")
    t.eq(old.d, -4)
    t.eq(old["key%20x"][1], "%41", "keys and nested text too")
    T.Save("legacy", old)                        -- saved again: marked, and the same when read
    local again = T.ReadSaved("legacy")
    t.eq(again.a, "cost%20gold")
    t.eq(again.c, "%N5")
    t.eq(again["key%20x"][1], "%41")
    -- as 1.5.1 to 1.6.0 saved them (every "%" written "%25"), text that looks escaped reads as typed
    H.S.memory["character:Tester"].legacy = { a = "cost%2520gold", b = "literal%25u0041", c = "%25N5",
      ["key%2520x"] = "%252F" }
    old = T.ReadSaved("legacy")
    t.eq(old.a, "cost%20gold")
    t.eq(old.b, "literal%u0041")
    t.eq(old.c, "%N5", "text, not a number")
    t.eq(old["key%20x"], "%2F")
  end)

  -- Review 24: a list saved whole is marked too (wrapped), and reads back as the list.
  t.test("a list saved whole reads back the same; an unmarked one from before reads as it did", function()
    H.boot()
    local T = Toolbox
    local list = { -1, 0.00002, "Caf\195\169", "a/b", "%N5", "100%", { x = -2 } }
    T.Save("probe_list", list)
    local raw = H.S.memory["character:Tester"].probe_list
    t.eq(raw[T.SAVE_FORMAT_KEY], 1, "marked")
    H.restart(nil, true)
    local back = T.ReadSaved("probe_list")
    t.eq(#back, #list)
    for i = 1, 6 do t.eq(back[i], list[i], "item " .. i) end
    t.eq(back[7].x, -2)
    t.eq(back[T.SAVE_FORMAT_KEY], nil)
    t.eq(back[T.SAVE_LIST_KEY], nil)
    H.S.memory["character:Tester"].old_list = { "cost%20gold", "Ward%2FShield" }
    local old = T.ReadSaved("old_list")
    t.eq(old[1], "cost%20gold")
    t.eq(old[2], "Ward/Shield")
    H.S.memory["character:Tester"].probe_list = nil
    H.S.memory["character:Tester"].old_list = nil
  end)

  t.test("a value the game couldn't read back isn't saved: one key refused, said once, the rest saved", function()
    H.boot()
    local T = Toolbox
    t.eq(T.CheckSaved({ a = 1, b = "x", c = { true, 2.5 } }), true)
    for _, bad in ipairs({ { -1 }, { 0 / 0 }, { "a/b" }, { "\n" }, { [0] = 1 }, { [1.5] = 1 } }) do
      t.eq(T.CheckSaved(bad), false)
    end
    local loop = {}
    loop.self = loop
    t.eq(T.CheckSaved(loop), false)
    t.eq(T.CheckSaved({ string.rep("x", T.SAVE_MAX_CHARS + 1) }), false, "past the game's 256 KB")
    H.S.logs = {}
    t.eq(T.SetSavedVar("probe", { -1 }, "character"), false)
    t.eq(T.SetSavedVar("probe", { -2 }, "character"), false)
    t.eq(H.S.memory["character:Tester"].probe, nil, "never handed to the game")
    local said = 0
    for _, l in ipairs(H.S.logs) do if l:find("didn't save 'probe'") then said = said + 1 end end
    t.eq(said, 1, "said once")
    t.eq(T.SetSavedVar("other", { 1 }, "character"), true, "the rest still saves")
    T.saveRefused = {}
  end)

  local function lose(scope)          -- the game couldn't read a file: the add-on starts without it
    Toolbox.Flush()                   -- (Toolbox's own flush, as at shutdown: the copy is written there)
    H.S.disk[scope] = nil
    H.restart(nil)
  end

  t.test("recovery: a character file the game couldn't read is put back from the account copy", function()
    H.boot()
    H.chat("/tbx location on")
    H.chat("/tbx buffs quiet add Stillness")
    H.chat("/tbx loot reset")
    H.advance(120)
    H.chat("/tbx loot reset")
    H.advance(2)
    t.ok(H.S.memory.account["recovery:tester"], "a copy in the account file")
    lose("character:Tester")
    t.eq(Toolbox.Location.GetShow(), true, "settings back")
    t.ok(Toolbox.BuffBar.IsMuted("Stillness"), "muted effects back")
    t.eq(#Toolbox.Daily.Runs(), 1, "run history back")
    t.ok(H.logged("couldn't read Toolbox's saved file for Tester"), "said so")
    H.S.logs = {}
    H.restart(nil, true)
    t.no(H.logged("couldn't read"), "once: the file has its number again")
    t.eq(Toolbox.Location.GetShow(), true)
  end)

  t.test("recovery: a file with its number is left alone, even if older; no copy, nothing to do", function()
    H.boot()
    H.chat("/tbx location on")
    H.advance(2)
    ShroudFlushSavedVars()
    local older = H.S.disk["character:Tester"]
    older = Toolbox.Copy(older)
    H.chat("/tbx location facing off")
    H.advance(2)
    ShroudFlushSavedVars()
    H.S.disk["character:Tester"] = older       -- restored by hand from an older backup
    H.restart(nil)
    t.no(H.logged("couldn't read"))
    t.eq(Toolbox.Location.GetFacing(), true, "the older file's own setting kept")

    H.firstBoot()                                       -- a new player: nothing anywhere
    t.no(H.logged("couldn't read"))
  end)

  t.test("recovery: Reset and an import carry into the copy; another character has its own", function()
    H.boot()
    H.chat("/tbx location on")
    H.advance(2)
    H.chat("/tbx settings reset")
    H.reload()
    H.advance(2)
    lose("character:Tester")
    t.eq(Toolbox.Location.GetShow(), false, "the reset kept: defaults, not the old settings")
    H.callback("ShroudOnLogOut")
    H.S.char.name = "Alt"
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(2)
    t.eq(Toolbox.Location.GetShow(), false, "Alt's own")
    t.ok(H.S.memory.account["recovery:alt"], "Alt's copy")
  end)

  -- Each file's estimate against what the harness would write: every key counted, never below the real size.
  local function measuredWhole(label)
    for scope, keys in pairs(H.S.memory) do
      local mine = Toolbox.fileUse[scope == "account" and "account" or "character"]
      if scope == "account" or scope == "character:" .. H.S.char.name then
        for key in pairs(keys) do t.ok(mine.keys[key], label .. ": " .. scope .. " '" .. key .. "' measured") end
        t.ok(mine.total >= H.JsonSize(keys), label .. ": " .. scope .. " estimate " .. mine.total .. " below "
          .. H.JsonSize(keys))
      end
    end
  end

  t.test("each saved file is measured whole at start and kept measured by every write", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx mark Bank")
    H.chat("/tbx settings export Raid")
    t.ok(H.logged("Exported your settings"), H.lastLog())
    H.advance(5)
    measuredWhole("after a session")
    reloadForReal()
    measuredWhole("after a reload")
  end)

  t.test("a write that would take a file past 256 KB is refused and named; the rest of the file still saves", function()
    H.boot()
    local big = { string.rep("a", 150000) }
    t.ok(Toolbox.SetSavedVar("test_big_a", big, "account"))
    local ok, _, kind = Toolbox.SetSavedVar("test_big_b", big, "account")
    t.eq(ok, false, "the second one doesn't fit")
    t.eq(kind, "full")
    t.ok(H.logged("Toolbox didn't save 'test_big_b': the account file is full"), H.lastLog())
    t.eq(H.S.memory.account.test_big_b, nil, "never handed to the game")
    t.ok(Toolbox.Flush() ~= false, "the file is still written (the harness raises past 256 KB)")
    t.ok(Toolbox.SetSavedVar("test_big_a", { "smaller" }, "account"), "a write that shrinks it is taken")
    t.ok(Toolbox.SetSavedVar("test_big_b", big, "account"), "and now the other fits")
    Toolbox.DeleteSaved("test_big_b", "account")
    Toolbox.DeleteSaved("test_big_a", "account")
    t.ok(Toolbox.FileUse("account") < 50000, "deletes are counted: " .. Toolbox.FileUse("account"))
    Toolbox.saveRefused.test_big_b = nil
  end)

  t.test("other characters' recovery copies count toward the account file; overlays aren't copied", function()
    H.boot()
    H.chat("/tbx mark Bank")
    H.advance(5)
    H.callback("ShroudOnLogOut")
    H.S.char.name = "Alt"
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(5)
    t.ok(H.S.memory.account["recovery:alt"], "Alt's copy")
    t.eq(H.S.memory.account["recovery:tester"].keys.map_overlays, nil, "Tester's overlays not in the copy")
    H.callback("ShroudOnLogOut")
    H.S.char.name = "Tester"
    H.restart()
    t.ok(Toolbox.fileUse.account.keys["recovery:alt"], "Alt's copy measured with Alt not playing")
    measuredWhole("Tester again")
  end)

  t.test("an older account file with 2,000 prices is cut to 600 at start; the other account writes then fit", function()
    local items = {}
    for i = 1, 2000 do
      items[string.format("an item with a long name %04d", i)] = { avg = i + 0.37, sold = i, last = "2026-09-20",
        day = string.format("2026-09-%02d", 1 + i % 28), at = 1234.5 }
    end
    H.boot({ account = { prices = { v = 1, items = items } } })
    local n = 0
    for _ in pairs(H.S.memory.account.prices.items) do n = n + 1 end
    t.eq(n, Toolbox.Prices.MAX_KEEP)
    H.advance(5)
    t.eq(next(Toolbox.saveRefused), nil, "nothing refused")
    t.ok(H.S.memory.account["recovery:tester"], "the recovery copy written")
  end)
end
