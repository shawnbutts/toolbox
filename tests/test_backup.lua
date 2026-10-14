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
    notify_history = true, prices = true, welcomed = true, version_seen = true, guild_motd = true,
    settings_pending = true, loot_runs = true, skills_paused = true, map_overlays = true, recovery_index = true,
    ceiling_due = true }

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

  t.test("1.7.0's unlisted recovery copies: room kept for them; a fresh install keeps none (review 36)", function()
    local alt = { v = 1, n = 3, when = "2026-10-12 20:00", keys = { buff_durations = { v = 2, durations = {} } } }
    for i = 1, 600 do alt.keys.buff_durations.durations[string.format("A_Long_Rune_Name_%04d", i)] = 3600 + i end
    H.boot({ account = { welcomed = true, ["recovery:alt"] = alt } })
    local used, max = Toolbox.FileUse("account")
    t.eq(max, Toolbox.FILE_MAX - B().LEGACY_RESERVE, "room kept for copies it can't see")
    t.no(Toolbox.fileUse.account.keys["recovery:alt"], "Alt's copy isn't listed anywhere")
    local fill = { string.rep("x", max - used + B().LEGACY_RESERVE - 2000) }      -- fits only without Alt's room
    local ok, _, kind = Toolbox.SetSavedVar("test_fill", fill, "account")
    t.eq(ok, false, "refused before it reaches the game")
    t.eq(kind, "full")
    Toolbox.saveRefused.test_fill = nil
    t.ok(Toolbox.Flush() ~= false)
    t.eq(H.S.memory.account.recovery_index.legacy, true, "the index remembers this install ran 1.7.0")
    H.restart()
    t.eq(select(2, Toolbox.FileUse("account")), Toolbox.FILE_MAX - B().LEGACY_RESERVE, "kept after a restart")
    H.firstBoot()
    H.advance(2)
    t.eq(select(2, Toolbox.FileUse("account")), Toolbox.FILE_MAX, "a new install keeps no room")
  end)

  t.test("a recovery copy is listed before it's written: a refused index writes no copy", function()
    H.boot()
    H.advance(5)
    H.S.refuseKeys = { recovery_index = true }
    H.callback("ShroudOnLogOut")
    H.S.char.name = "Alt"
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(5)
    t.eq(H.S.memory.account["recovery:alt"], nil, "no copy no one could find")
    H.S.refuseKeys = nil
    H.chat("/tbx vitals")                        -- a change: the next flush tries again
    H.advance(Toolbox.flushSeconds + 1)
    t.ok(H.S.memory.account["recovery:alt"], "written once the index is")
    t.eq(H.S.memory.account.recovery_index.names[2], "alt")
  end)

  -- A 1.8.0 development copy with full overlays (review 36's case, 135 KB for ten; thirteen here), unlisted.
  local function bigLegacyCopy()
    local overlays = {}
    for o = 1, 13 do
      local places = {}
      for i = 1, 100 do
        places[i] = { id = i, name = string.format("A long place name %03d", i), raw = "Elsewhere",
                      scene = "A scene with a long name", x = "%N" .. (-1000.5 - i), y = 12.25, z = 2000 + i,
                      icon = "diamond", color = "Purple" }
      end
      overlays[o] = { id = o, name = "Overlay number " .. o, icon = "star", color = "Blue", nextPlace = 101,
                      places = places }
    end
    return { v = 1, n = 9, when = "2026-10-13 12:00", keys = {
      map_overlays = { v = 1, shown = 1, nextId = 11, list = overlays, ["%E"] = 1 } } }
  end

  t.test("an unlisted copy past the room kept: the failed flush teaches the file's ceiling (review 36)", function()
    local prices = {}
    for i = 1, 470 do                              -- with the copy, just under 256 KB at the start
      prices[string.format("loot item %03d", i)] = { avg = i * 3, sold = i, last = "2026-09-20", day = "2026-10-13" }
    end
    H.boot({ account = { ["recovery:alt"] = bigLegacyCopy(), prices = { v = 1, items = prices } } })
    H.S.fileLimitAsGame = true                     -- the game's answer: that file not written, the flush false
    H.chat("/tbx settings share on")
    local i = 0
    repeat                                         -- setups, one at a time, as a player makes them
      i = i + 1
      H.chat("/tbx settings export A long setup name " .. i)
      Toolbox.Flush()
    until H.logged("couldn't save Toolbox's shared account file") or i >= Toolbox.Backup.SETUP_MAX - 1
    t.ok(H.logged("Toolbox cleared its remembered prices %(they're looked up again%)"), H.lastLog())
    t.no(H.logged("set aside this character's recovery copy"), "prices were room enough")
    t.eq(Toolbox.Prices.Count(), 0)
    t.ok(H.JsonSize(H.S.disk.account) <= 256 * 1024, "written, under 256 KB")
    t.ok(H.S.disk.account["setup:a long setup name " .. i], "the setup that tipped it over, saved")
    local ceiling = H.S.memory.account.recovery_index.ceiling
    local used, max = Toolbox.FileUse("account")
    t.ok(ceiling and ceiling > 0 and ceiling < used,
      "the ceiling learned below what was written (review 36): " .. tostring(ceiling) .. " / " .. used)
    t.ok(max <= ceiling, "growth stops short of it: " .. max)
    for k = 1, 20 do H.chat("/tbx settings export Yet another " .. k) end
    t.ok(Toolbox.Flush() ~= false, "every later flush works")
    t.ok(select(1, Toolbox.FileUse("account")) <= used, "no growth past it")
    t.ok(H.JsonSize(H.S.disk.account) <= 256 * 1024)
    Toolbox.saveRefused = {}
    H.restart()
    t.eq(select(2, Toolbox.FileUse("account")), max, "the ceiling kept after a restart")
    Toolbox.saveRefused = {}                       -- growth refused until the other characters log in
    H.S.fileLimitAsGame = nil
  end)

  -- Review 36's case with nothing disposable: the unlisted copy and a 130 KB value accepted beside it.
  local function bigUnlisted()
    H.boot({ account = { ["recovery:alt"] = bigLegacyCopy() } })
    H.S.fileLimitAsGame = true
    H.advance(Toolbox.flushSeconds + 1)            -- this character's copy written and listed
    local fill = { string.rep("x", 130 * 1024) }
    t.ok(Toolbox.SetSavedVar("test_fill", fill, "account"), "accepted: Alt's copy can't be measured")
  end

  t.test("no prices to clear: the account file's latest changes are undone and named, the rest written", function()
    bigUnlisted()
    local before = H.S.disk.account
    local ok, why = Toolbox.Flush()
    t.eq(ok, false, "not everything was saved")
    t.eq(why, "full")
    t.ok(H.logged("undid its latest changes to that file, which weren't saved: 'test_fill'"), H.lastLog())
    t.eq(H.S.memory.account.test_fill, nil, "undone")
    t.ok(H.S.disk.account ~= before and H.JsonSize(H.S.disk.account) <= 256 * 1024, "the rest written")
    t.ok(H.S.disk.account["recovery:alt"], "Alt's copy untouched")
    t.ok(H.S.disk.account["recovery:tester"], "this character's copy kept: the undo was room enough")
    t.no(H.logged("set aside"))
    local used, max = Toolbox.FileUse("account")
    t.ok(max < used, "the ceiling below what's there now")
    t.eq(Toolbox.SetSavedVar("test_fill", { "small" }, "account") == true, false, "growth refused")
    Toolbox.saveRefused = {}
    t.ok(Toolbox.Flush() ~= false, "later flushes work")
    H.S.fileLimitAsGame = nil
  end)

  t.test("an export the full account file undid says so", function()
    bigUnlisted()
    H.chat("/tbx settings export Last one")
    t.ok(H.logged("shared account file is full"), H.lastLog())
    t.eq(H.S.memory.account["setup:last one"], nil)
    t.eq(H.S.memory.account.test_fill, nil)
    Toolbox.saveRefused = {}
    H.S.fileLimitAsGame = nil
  end)

  t.test("a ceiling learned rises again as an unmeasured copy's character logs in", function()
    bigUnlisted()
    Toolbox.Flush()
    Toolbox.saveRefused = {}
    local _, max = Toolbox.FileUse("account")
    local ceiling = H.S.memory.account.recovery_index.ceiling
    H.callback("ShroudOnLogOut")
    H.S.char.name = "Alt"
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(Toolbox.flushSeconds + 1)
    local now = H.S.memory.account.recovery_index.ceiling
    t.ok(now > ceiling + 100000, "Alt's old copy's room given back: " .. ceiling .. " -> " .. now)
    t.ok(select(2, Toolbox.FileUse("account")) > max)
    t.ok(H.S.memory.account["recovery:alt"].keys.map_overlays == nil, "Alt's copy rewritten, small")
    t.ok(Toolbox.Flush() ~= false)
    t.ok(H.JsonSize(H.S.disk.account) <= 256 * 1024)
    Toolbox.saveRefused = {}                       -- Tester's copy, refused at its logout while the room was short
    H.S.fileLimitAsGame = nil
  end)

  t.test("an undo keeps this character's copy listed: the index is never rolled back past it (review 40)", function()
    H.boot({ account = { ["recovery:alt"] = bigLegacyCopy() } })
    H.callback("ShroudOnLogOut")
    H.S.char.name = "Third"                        -- a character listed for the first time...
    H.callback("ShroudOnSceneLoaded", "Novia")
    local index = H.S.memory.account.recovery_index
    local before = { v = 1, legacy = index.legacy, names = {} }
    for _, n in ipairs(index.names) do
      if n ~= "third" then before.names[#before.names + 1] = n end
    end
    Toolbox.accountUndo.recovery_index = { old = before }   -- as if listed since the last flush that worked
    H.S.fileLimitAsGame = true
    t.ok(Toolbox.SetSavedVar("test_fill", { string.rep("x", 130 * 1024) }, "account"))
    H.chat("/tbx vitals")                          -- ...in the flush that's refused
    local ok, why = Toolbox.Flush()
    t.eq(ok, false)
    t.eq(why, "full")
    local disk = H.S.disk.account
    t.ok(disk["recovery:third"], "the copy kept")
    local listed = false
    for _, n in ipairs(disk.recovery_index.names) do listed = listed or n == "third" end
    t.ok(listed, "and listed")
    t.no(disk.test_fill, "the big value undone")
    Toolbox.saveRefused = {}
    H.S.fileLimitAsGame = nil
  end)

  local function ceilingKeptThrough(name, fail)
    t.test(name, function()
      bigUnlisted()
      local undo = fail()
      local ok, why = Toolbox.Flush()
      undo()
      t.eq(ok, false, tostring(why))
      t.eq(H.S.disk.account.recovery_index.ceiling, nil, "not on disk yet")
      local _, max = Toolbox.FileUse("account")
      t.ok(max < Toolbox.FILE_MAX - Toolbox.Backup.LEGACY_RESERVE, "kept in memory meanwhile")
      t.ok(Toolbox.Flush() ~= false, "the next flush")
      local ceiling = H.S.disk.account.recovery_index.ceiling
      t.ok(ceiling and ceiling > 0, "written then")
      t.eq(Toolbox.Backup.pendingCeiling, nil)
      Toolbox.saveRefused = {}
      H.restart()
      t.eq(H.S.disk.account.recovery_index.ceiling, ceiling, "the same ceiling after a restart")
      t.eq(select(2, Toolbox.FileUse("account")), ceiling, "and it rules")
      t.ok(select(2, Toolbox.FileUse("account")) <= max)
      Toolbox.saveRefused = {}
      H.S.fileLimitAsGame = nil
    end)
  end
  ceilingKeptThrough("a refused ceiling write is tried again at every flush until it's on disk (review 41)",
    function()
      H.S.refuseKeys = { recovery_index = true }
      return function() H.S.refuseKeys = nil end
    end)
  ceilingKeptThrough("a refused flush after the ceiling: it stays due, written by the next one (review 41)",
    function()
      local real, failed = ShroudFlushSavedVars, false
      ShroudFlushSavedVars = function()
        local index = H.S.memory.account.recovery_index
        if not failed and index and index.ceiling then
          failed = true
          return false
        end
        return real()
      end
      return function() ShroudFlushSavedVars = real end
    end)

  local function ceilingKeptAcrossRestart(name, fail)
    t.test(name, function()
      bigUnlisted()
      local undo = fail()
      t.eq(Toolbox.Flush(), false)
      undo()
      local _, max = Toolbox.FileUse("account")
      t.eq(H.S.disk.account.recovery_index.ceiling, nil, "not in the account file")
      t.ok(H.S.disk["character:" .. H.S.char.name].ceiling_due, "noted in the character file")
      Toolbox.saveRefused = {}
      H.restart()                                  -- the game closed before another flush
      t.eq(select(2, Toolbox.FileUse("account")), max, "the bound holds after the restart")
      t.eq(Toolbox.SetSavedVar("test_fill", { "small" }, "account") == true, false, "growth still refused")
      Toolbox.saveRefused = {}
      t.ok(Toolbox.Flush() ~= false)
      t.eq(H.S.disk.account.recovery_index.ceiling, max, "written into the account file now")
      t.ok(Toolbox.Flush() ~= false)
      t.eq(H.S.disk["character:" .. H.S.char.name].ceiling_due, nil, "the note dropped once it's there")
      H.restart()
      t.eq(select(2, Toolbox.FileUse("account")), max)
      Toolbox.saveRefused = {}
      H.S.fileLimitAsGame = nil
    end)
  end
  ceilingKeptAcrossRestart("a refused ceiling write survives a restart before the retry (review 42)", function()
    H.S.refuseKeys = { recovery_index = true }
    return function() H.S.refuseKeys = nil end
  end)
  ceilingKeptAcrossRestart("a refused flush after the ceiling survives a restart before the retry (review 42)",
    function()
      local real, failed = ShroudFlushSavedVars, false
      ShroudFlushSavedVars = function()
        local index = H.S.memory.account.recovery_index
        if not failed and index and index.ceiling then
          failed = true
          local account = H.S.disk.account
          real()                                   -- as the game: the character file written, not the account
          H.S.disk.account = account
          return false
        end
        return real()
      end
      return function() ShroudFlushSavedVars = real end
    end)

  t.test("the bound kept in memory only: a warning window says so (review 43, an accepted risk)", function()
    bigUnlisted()
    H.S.refuseKeys = { recovery_index = true, ceiling_due = true }
    H.chat("/tbx vitals")
    H.advance(Toolbox.flushSeconds + 1)            -- the periodic flush (a callback: windows can be made)
    H.S.refuseKeys = nil
    local w = H.S.windows.toolbox_warning
    t.ok(w and w:IsShown(), "the warning window")
    t.ok(w:Find("warning_text"):GetText():find("log in each of your characters once", 1, true))
    t.ok(H.logged("couldn't keep a note of how full"), "in chat too")
    H.click("toolbox_warning", "warning_ok")
    t.no(H.S.windows.toolbox_warning, "OK closes it")
    t.ok(Toolbox.Flush() ~= false)
    t.ok(H.S.disk.account.recovery_index.ceiling, "written at the next flush")
    Toolbox.saveRefused = {}
    H.S.fileLimitAsGame = nil
  end)

  t.test("a note refused but the index written: no warning", function()
    bigUnlisted()
    H.S.refuseKeys = { ceiling_due = true }
    Toolbox.Flush()
    H.S.refuseKeys = nil
    t.no(H.S.windows.toolbox_warning)
    Toolbox.saveRefused = {}
    H.S.fileLimitAsGame = nil
  end)

  local function withPrices()
    local prices = {}
    for i = 1, 50 do prices["item " .. i] = { avg = i, sold = 1, last = "2026-10-01", day = "2026-10-13" } end
    H.boot({ account = { welcomed = true, prices = { v = 1, items = prices } } })
    H.advance(Toolbox.flushSeconds + 1)
    t.ok(H.S.memory.account["recovery:tester"], "this character's copy")
    t.ok(Toolbox.fileUse.account.reserve > 0, "an upgraded install: room kept")
  end

  t.test("a refusal that passes changes nothing: no prices or copy lost, no ceiling (review 39)", function()
    withPrices()
    local real, refusals = ShroudFlushSavedVars, 1
    ShroudFlushSavedVars = function()
      if refusals > 0 then
        refusals = refusals - 1
        return false
      end
      return real()
    end
    H.chat("/tbx vitals")
    t.ok(Toolbox.Flush() ~= false, "written at the retry")
    ShroudFlushSavedVars = real
    t.eq(Toolbox.Prices.Count(), 50, "prices kept")
    t.ok(H.S.disk.account["recovery:tester"], "the copy kept")
    t.eq(H.S.memory.account.recovery_index.ceiling, nil, "no ceiling")
    t.no(H.logged("256 KB a file"))
  end)

  t.test("a refusal that passes after room was made: everything put back, nothing learned (review 39)", function()
    withPrices()
    local real, refusals = ShroudFlushSavedVars, 2   -- the first try and the retry; then it passes
    ShroudFlushSavedVars = function()
      if refusals > 0 then
        refusals = refusals - 1
        return false
      end
      return real()
    end
    t.ok(Toolbox.Flush() ~= false)
    ShroudFlushSavedVars = real
    t.eq(Toolbox.Prices.Count(), 50, "prices put back")
    t.ok(H.S.disk.account.prices and H.S.disk.account["recovery:tester"], "both on disk")
    t.eq(H.S.memory.account.recovery_index.ceiling, nil, "no ceiling")
    t.no(H.logged("256 KB a file"))
  end)

  t.test("a refusal that keeps on (a disk error) loses nothing and learns nothing (review 39)", function()
    withPrices()
    local copy = H.S.memory.account["recovery:tester"]
    H.S.flushFails = true
    t.eq(Toolbox.Flush(), false)
    H.S.flushFails = nil
    t.eq(Toolbox.Prices.Count(), 50, "prices kept")
    t.eq(H.S.memory.account["recovery:tester"].n, copy.n, "the copy kept")
    t.eq(H.S.memory.account.recovery_index.ceiling, nil, "no ceiling")
    t.ok(H.logged("Couldn't write Toolbox's saved settings to disk"), "the usual warning")
    t.no(H.logged("256 KB a file"))
    t.ok(Toolbox.Flush() ~= false)
  end)
end
