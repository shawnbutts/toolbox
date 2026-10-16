-- Another character logging in without a reload (ShroudOnStart doesn't run again): every module takes that
-- character's settings and positions (Toolbox.FollowCharacter), and nothing of the last one's is saved into it.
local H = require("harness")

return function(t)
  -- Logs out and in as `name`, as the game does: the logout callback, then the new character's scene.
  local function switchTo(name)
    H.callback("ShroudOnLogOut")
    H.S.char.name = name
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(1)
  end

  t.test("settings follow the character: the new one's own, the last one's left alone", function()
    H.boot()
    H.chat("/tbx buffs")
    Toolbox.BuffBar.SetSize(30)
    H.chat("/tbx xp")
    H.advance(2)
    t.ok(H.S.windows.toolbox_compact:IsShown())
    switchTo("Alt")
    t.no(Toolbox.BuffBar.IsEnabled(), "Alt never turned the buff bar on")
    t.eq(Toolbox.BuffBar.GetSize(), Toolbox.BuffBar.SIZE_DEFAULT)
    t.no(H.S.windows.toolbox_compact:IsShown(), "nor opened the XP window")
    H.advance(3)
    local alt = H.saved("buffbar") or {}
    t.ok(alt.show ~= true and alt.size ~= 30, "nothing of Tester's saved into Alt's file (only where the strip is)")
    t.eq(H.S.memory["character:Tester"].buffbar.size, 30, "Tester's kept")
    Toolbox.BuffBar.SetSize(40)
    switchTo("Tester")
    t.ok(Toolbox.BuffBar.IsEnabled(), "back to Tester: its own again")
    t.eq(Toolbox.BuffBar.GetSize(), 30)
    t.ok(H.S.windows.toolbox_compact:IsShown())
    t.eq(H.S.memory["character:Alt"].buffbar.size, 40, "and Alt's change stayed Alt's")
  end)

  t.test("a strip the new character never placed stays where it is; one it placed goes there", function()
    H.boot()
    H.chat("/tbx vitals")
    H.S.frames.toolbox_vitals.x, H.S.frames.toolbox_vitals.y = 500, 300
    H.advance(1)
    switchTo("Alt")
    H.chat("/tbx vitals")
    H.advance(1)
    t.eq(H.S.frames.toolbox_vitals.x, 500, "Alt's health bars where Tester left them")
    H.S.frames.toolbox_vitals.x, H.S.frames.toolbox_vitals.y = 100, 120
    H.advance(1)
    switchTo("Tester")
    t.eq(H.S.frames.toolbox_vitals.x, 500, "Tester's own place")
    switchTo("Alt")
    t.eq(H.S.frames.toolbox_vitals.x, 100, "Alt's own place")
  end)

  t.test("the same character again, or the login screen: nothing restarts", function()
    H.boot()
    H.chat("/tbx buffs")
    local frame = H.frame()
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(1)
    t.eq(H.frame(), frame, "not rebuilt for a scene change")
    H.S.char.name = "INVALID"
    H.callback("ShroudOnSceneLoaded", "Login")
    H.advance(1)
    t.eq(H.frame(), frame, "not for the login screen either")
  end)

  t.test("the settings window follows: its controls show the new character's values", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx config")
    t.eq(H.config():Find("buff_size").value, Toolbox.BuffBar.SIZE_DEFAULT)
    Toolbox.BuffBar.SetSize(36)
    switchTo("Alt")
    t.eq(H.config():Find("buff_size").value, Toolbox.BuffBar.SIZE_DEFAULT, "Alt's")
  end)

  -- Review 2026-10-04 (15): the session and the day follow at the scene, before the windows show them.
  t.test("at the new character's scene: its own XP session and day, at once; events go into its day", function()
    H.boot()
    H.goldChange(250)
    H.advance(2)
    t.ok(Toolbox.Daily.day.gold >= 250, "Tester's gold today")
    H.S.memory["character:Alt"] = { daily_window = { open = true } }
    H.callback("ShroudOnLogOut")
    H.S.char.name = "Alt"
    H.callback("ShroudOnSceneLoaded", "Novia")   -- no tick in between
    t.eq(Toolbox.session.player, "Alt", "Alt's session")
    t.eq(Toolbox.Daily.day.gold, 0, "Alt's day")
    t.ok(H.S.windows.toolbox_daily:IsShown(), "Alt's Today window open")
    t.eq(H.dailyText("gold"), "0", "showing Alt's gold, not Tester's")
    H.items({ { "Iron Ore", 3 } })
    H.advance(2)
    t.eq(Toolbox.Daily.day.items["Iron Ore"], 3, "kept in Alt's day after the tick")
  end)

  -- Review 2026-10-04 (14): the Notifications window shows only this character's notices.
  t.test("the Notifications window doesn't carry the last character's notices", function()
    H.boot()
    H.setGuild("Knights", "Tester secret")
    H.advance(3)
    local tester = H.notify()
    t.ok(tester and tester:IsShown(), "Tester's guild message shown")
    H.callback("ShroudOnLogOut")
    H.S.char.name = "Alt"
    H.callback("ShroudOnSceneLoaded", "Novia")
    t.ok(H.notify() == nil or H.notify() ~= tester, "Tester's window is gone")
    t.ok(tester.destroyed or not tester:IsShown(), "not left on screen")
  end)

  -- The game's display name carries tags (seen 2026-10-07 and 08: "shawn[PVP]", "shawn[404040][AFK][-]"); the
  -- character, and its file, are the same.
  t.test("a name's tags are dropped: PvP, AFK with its color, spaces; names without stay as they are", function()
    H.boot()
    local P = Toolbox.PlainName
    t.eq(P("shawn[PVP]"), "shawn")
    t.eq(P("shawn[404040][AFK][-]"), "shawn")
    t.eq(P("Lord British [AFK]"), "Lord British")
    t.eq(P("shawn"), "shawn")
    t.eq(P("shawn[unclosed"), "shawn[unclosed", "an unclosed bracket stays")
    t.eq(P(nil), nil)
    H.S.char.tags = "[PVP]"
    t.eq(Toolbox.PlayerName(), "Tester")
    t.eq(Toolbox.CharacterName(), "Tester")
  end)

  t.test("going AFK or flagging PvP: the same character, nothing restarts", function()
    H.boot()
    H.chat("/tbx buffs")
    H.chat("/tbx skills on")
    H.advance(5)
    H.gain(5000, 0)
    H.advance(3)
    local session, frame, made = Toolbox.session, H.frame(), H.S.constructed
    for _, tags in ipairs({ "[404040][AFK][-]", "", "[PVP]", "" }) do
      H.S.char.tags = tags
      H.callback("ShroudOnSceneLoaded", "Novia")
      H.advance(2)
    end
    t.eq(Toolbox.session, session, "the same XP session")
    t.eq(Toolbox.session.player, "Tester")
    t.eq(H.frame(), frame, "the buff bar not rebuilt")
    t.eq(H.S.constructed, made, "no element made again")
    t.eq(Toolbox.settingsFor, "Tester")
    H.chat("/tbx settings share on")
    H.S.char.tags = "[PVP]"
    H.advance(Toolbox.flushSeconds or 31)
    H.advance(31)
    t.ok(H.S.memory.account["setup_character:tester"], "the copy under the plain name")
    for key in pairs(H.S.memory.account) do t.no(key:find("pvp", 1, true), "nothing kept under a tag: " .. key) end
  end)

  t.test("a session saved under a tagged name (1.7.0) resumes after the update", function()
    H.boot()
    H.advance(5)
    H.gain(5000, 0)
    H.advance(3)
    local started = Toolbox.session.started
    H.S.memory["character:Tester"].session.player = "Tester[PVP]"
    H.reload()
    H.advance(2)
    t.eq(Toolbox.session.started, started, "resumed, not started again")
    t.eq(Toolbox.session.player, "Tester")
  end)

  t.test("setup and recovery copies kept under tagged names go to the plain name, once", H.OlderClient(function()
    H.boot()
    H.chat("/tbx settings share on")
    Toolbox.BuffBar.SetSize(30)
    H.advance(Toolbox.flushSeconds or 31)
    H.advance(31)
    local account = H.S.memory.account
    local mine = account["setup_character:tester"]
    t.ok(mine and account["recovery:tester"], "Tester's own copies")
    -- as 1.7.0 left them (brackets are saved as they are): Tester also under "[PVP]" (dropped: the plain one is
    -- there), and Alt only under "[AFK]" (moved, with its recovery copy)
    account["setup_character:tester[pvp]"] = Toolbox.Resaved(Toolbox.FromSaved(mine))
    account["recovery:tester[pvp]"] = account["recovery:tester"]
    account["setup_character:alt[404040][afk][-]"] = Toolbox.Resaved(Toolbox.FromSaved(mine))
    account["recovery:alt[404040][afk][-]"] = account["recovery:tester"]
    local list = account.setups.list
    list[#list + 1] = { name = "Tester[PVP]", character = true, when = "2026-10-07" }
    list[#list + 1] = { name = "Alt[404040][AFK][-]", character = true, when = "2026-10-08" }
    H.reload()
    H.advance(1)
    for key in pairs(account) do t.no(key:find("[", 1, true), "no tagged key left: " .. key) end
    t.ok(account["setup_character:alt"], "Alt's copy under its plain name")
    t.ok(account["recovery:alt"], "and its recovery copy")
    local listed = {}
    for _, s in ipairs(Toolbox.Backup.Setups()) do listed[#listed + 1] = s.name end
    t.eq(table.concat(listed, ","), "Alt", "Alt once; Tester's own not listed to itself")
    t.eq(#account.setups.list, 2, "Tester and Alt")
    H.S.char.name, H.S.char.tags = "Alt", "[PVP]"    -- Alt with no file of its own: the moved copy is found
    H.reload()
    t.eq(Toolbox.BuffBar.GetSize(), 30, "Alt's recovery copy, put back under its plain name")
    t.ok(H.logged("put back from Toolbox's copy"))
  end))
end
