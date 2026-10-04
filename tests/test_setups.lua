-- Setups (Toolbox.Backup): a character's settings and positions copied through the account file, so another
-- character on the same computer (someone else's too) can import them. Copies, never linked.
local H = require("harness")

return function(t)
  local B = function() return Toolbox.Backup end
  local function switchTo(name)
    H.callback("ShroudOnLogOut")
    H.S.char.name = name
    H.callback("ShroudOnSceneLoaded", "Novia")
    H.advance(1)
  end
  local function names()
    local out = {}
    for _, s in ipairs(B().Setups()) do out[#out + 1] = s.label end
    return table.concat(out, ", ")
  end
  -- "Mom" sets up her Toolbelt and plays a while (her copy is kept at the next flush).
  local function momPlays()
    H.boot()
    H.S.char.name = "Mom"
    H.reload()
    H.chat("/tbx buffs")
    Toolbox.BuffBar.SetSize(30)
    H.chat("/tbx vitals")
    H.S.frames.toolbox_buffs.x, H.S.frames.toolbox_buffs.y = 640, 480
    H.advance(Toolbox.flushSeconds or 31)
    H.advance(31)
  end

  t.test("every character's setup is kept for the others as it plays; not its own in its list", function()
    momPlays()
    t.eq(names(), "", "Mom doesn't see her own")
    switchTo("Dad")
    t.ok(names():find("^Mom %(character"), names())
  end)

  t.test("Dad imports Mom's: her settings and places, at once; later changes stay apart", function()
    momPlays()
    switchTo("Dad")
    t.no(Toolbox.BuffBar.IsEnabled(), "Dad's own setup first")
    H.clearLogs()
    H.chat("/tbx settings import Mom")
    t.ok(H.logged("Imported 'Mom'"), H.lastLog())
    t.ok(Toolbox.BuffBar.IsEnabled(), "her buff bar")
    t.eq(Toolbox.BuffBar.GetSize(), 30)
    t.ok(Toolbox.Vitals.IsShown and Toolbox.Vitals.IsShown() or H.vitals(), "her health bars")
    t.eq(H.S.frames.toolbox_buffs.x, 640, "where she keeps it")
    Toolbox.BuffBar.SetSize(44)
    switchTo("Mom")
    t.eq(Toolbox.BuffBar.GetSize(), 30, "Mom's untouched by Dad's change")
  end)

  t.test("export under a name; import it from another character; delete it", function()
    momPlays()
    H.clearLogs()
    H.chat("/tbx settings export Raid layout")
    t.ok(H.logged("Exported your settings and positions as 'Raid layout'"), H.lastLog())
    Toolbox.BuffBar.SetSize(22)                 -- changes after the export aren't in it
    switchTo("Kid")
    t.ok(names():find("^Raid layout, Mom"), "named ones first: " .. names())
    H.chat("/tbx settings import raid layout")
    t.eq(Toolbox.BuffBar.GetSize(), 30, "as it was exported")
    H.chat("/tbx settings delete Raid layout")
    t.no(names():find("Raid layout"), names())
    H.clearLogs()
    H.chat("/tbx settings import Nobody")
    t.ok(H.logged("No setup called 'Nobody'"), H.lastLog())
  end)

  t.test("an import keeps what this character was told: notices aren't shown again", function()
    momPlays()
    switchTo("Dad")
    H.setGuild("Knights", "Raid at 8")
    H.advance(3)
    local seen = H.saved("notify").sources.motd.seen
    t.eq(seen, "Raid at 8")
    H.chat("/tbx settings import Mom")
    H.advance(3)
    t.eq(H.saved("notify").sources.motd.seen, "Raid at 8", "Dad's own")
  end)

  t.test("the settings page: pick, Import (second click), Export, Delete", function()
    momPlays()
    switchTo("Dad")
    H.chat("/tbx config")
    local w = H.config()
    local pick = w:Find("setup_pick")
    t.ok(pick.value:find("^Mom"), tostring(pick.value))
    H.click("toolbox_config", "setup_import")
    t.no(Toolbox.BuffBar.IsEnabled(), "the first click only asks")
    t.eq(w:Find("setup_import").text, "Click again to confirm")
    H.click("toolbox_config", "setup_import")
    t.ok(Toolbox.BuffBar.IsEnabled(), "imported")
    t.ok(w:Find("setup_msg").text:find("Imported 'Mom'"), w:Find("setup_msg").text)
    H.submit("toolbox_config", "setup_name", "Dad's")
    t.ok(names():find("Dad's"), names())
    H.change("toolbox_config", "setup_pick", "Dad's")
    H.click("toolbox_config", "setup_delete")
    H.click("toolbox_config", "setup_delete")
    t.no(names():find("Dad's"), names())
  end)

  t.test("names are cleaned: no slashes, trimmed, not too long", function()
    H.boot()
    t.eq(B().CleanName("  a/b\\c  "), "a b c")
    t.eq(B().CleanName("   "), nil)
    t.eq(#B().CleanName(string.rep("x", 60)), B().NAME_MAX)
  end)
end
