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
end
