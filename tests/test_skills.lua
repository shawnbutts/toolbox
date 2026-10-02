-- The skill activity strip (Toolbox.SkillBar, skills.lua): skills pop up as they level, on a strip of their
-- own; a "Skill level ups" notification on the notification HUD only. To remove the feature, delete this
-- suite with skills.lua (see its header).
local H = require("harness")

return function(t)
  local SK = function() return Toolbox.SkillBar end

  local function skill(id, name, level, extra)
    local s = { id = id, key = name, name = name, level = level, trainedLevel = level, experience = level * 100,
                progress = 0.25, mode = "Learning", icon = 500 + id }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
  end
  local function sheet(levels, extra)       -- levels: { Fireball = 40, ... } in a fixed order
    local list = {}
    for i, name in ipairs({ "Fireball", "Healing", "Blacksmithing", "Archery", "Dodge" }) do
      if levels[name] then list[#list + 1] = skill(i, name, levels[name], extra and extra[name]) end
    end
    return list
  end
  local BASE = { Fireball = 40, Healing = 30, Blacksmithing = 20, Archery = 10, Dodge = 5 }
  local function levels(changes)
    local out = {}
    for k, v in pairs(BASE) do out[k] = v end
    for k, v in pairs(changes or {}) do out[k] = v end
    return out
  end
  local function on()
    H.boot()
    H.setSkills(sheet(BASE))
    H.chat("/tbx skills on")
    H.advance(1)
  end
  local function slotText(slot) return slot.children[3].text end
  local function slotTip(slot) return slot.children[1].children[1].tooltip or "" end

  -- model -------------------------------------------------------------------------

  t.test("Update: the first reading is the baseline; a level or mode change puts the skill on top", function()
    H.boot()
    local st = SK().NewState()
    t.eq(SK().Update(st, SK().Read(sheet(BASE)), 0, "levels", 12), false, "the baseline: nothing pops")
    t.eq(#st.active, 0)
    SK().Update(st, SK().Read(sheet(levels{ Healing = 31 })), 1, "levels", 12)
    t.eq(st.active[1].data.name, "Healing")
    t.eq(st.ups.n, 1, "a level up queued for the notification")
    SK().Update(st, SK().Read(sheet(levels{ Healing = 31 }, { Archery = { mode = "Unlearning" } })), 2, "levels", 12)
    t.eq(st.active[1].data.name, "Archery", "a mode change too, on top")
    t.eq(st.active[2].data.name, "Healing")
    t.eq(st.ups.n, 1, "a mode change isn't a level up")
    SK().Update(st, SK().Read(sheet(levels{ Healing = 32 }, { Archery = { mode = "Unlearning" } })), 3, "levels", 12)
    t.eq(#st.active, 2, "one slot per skill: refreshed, not added")
    t.eq(st.active[1].data.level, 32)
  end)

  t.test("Update: experience alone pops a skill only with \"Any experience\"", function()
    H.boot()
    local st = SK().NewState()
    SK().Update(st, SK().Read(sheet(BASE)), 0, "levels", 12)
    SK().Update(st, SK().Read(sheet(BASE, { Dodge = { experience = 999, progress = 0.9 } })), 1, "levels", 12)
    t.eq(#st.active, 0, "levels: experience alone doesn't")
    local st2 = SK().NewState()
    SK().Update(st2, SK().Read(sheet(BASE)), 0, "xp", 12)
    SK().Update(st2, SK().Read(sheet(BASE, { Dodge = { experience = 999 } })), 1, "xp", 12)
    t.eq(st2.active[1].data.name, "Dodge")
  end)

  t.test("Update: a burst of levels keeps the newest; Expire drops the quiet ones", function()
    H.boot()
    local st = SK().NewState()
    SK().Update(st, SK().Read(sheet(BASE)), 0, "levels", 3)
    SK().Update(st, SK().Read(sheet(levels{ Fireball = 41, Healing = 31, Blacksmithing = 21, Archery = 11,
                                             Dodge = 6 })), 1, "levels", 3)
    t.eq(#st.active, 3, "capped")
    SK().Update(st, SK().Read(sheet(levels{ Fireball = 41, Healing = 31, Blacksmithing = 21, Archery = 11,
                                             Dodge = 7 })), 20, "levels", 3)
    t.eq(SK().Expire(st, 32, 30), true)
    t.eq(#st.active, 1, "only the one that changed at 20 is left")
    t.eq(st.active[1].data.name, "Dodge")
  end)

  t.test("UpsText: each skill once at its highest level, after what was seen", function()
    H.boot()
    local ups = { n = 3, list = { { id = 1, name = "Fireball", level = 41 }, { id = 2, name = "Healing", level = 31 },
                                  { id = 3, name = "Fireball", level = 42 } } }
    t.eq(SK().UpsText(ups, 0), "Fireball 42, Healing 31.")
    t.eq(SK().UpsText(ups, 2), "Fireball 42.")
    t.eq(SK().UpsText(ups, 3), nil)
  end)

  -- the strip ---------------------------------------------------------------------

  t.test("off by default: no strip, no frame taken", function()
    H.boot()
    H.setSkills(sheet(BASE))
    t.eq(SK().GetShow(), false)
    t.eq(H.skillsFrame(), nil, "no HUD frame while off")
  end)

  t.test("a level up pops the skill with its level, progress, mode colour and tooltip", function()
    on()
    t.eq(H.skillsFrame().visible, false, "nothing to show yet: hidden")
    H.setSkills(sheet(levels{ Healing = 31 }, { Healing = { progress = 0.4 } }))
    H.advance(1)
    t.ok(H.skillsFrame().visible ~= false, "shown")
    local slots = H.skillSlots()
    t.eq(#slots, 1)
    t.eq(slotText(slots[1]), "31")
    t.eq(slots[1].children[3].style.color, "@gold", "a new level in gold")
    t.eq(slots[1].children[2].value, 0.4, "progress to the next")
    t.eq(slots[1].children[1].style.borderColor, "@green", "training: green")
    t.eq(slots[1].children[1].children[1].texture, 502, "its icon")
    t.ok(slotTip(slots[1]):find("^Healing\nLevel 31, 40%% to the next\nTraining"), slotTip(slots[1]))
    H.advance(Toolbox.SkillBar.NEW_FOR + 1)
    t.eq(slots[1].children[3].style.color, "@text", "then plain")
    H.setSkills(sheet(levels{ Healing = 31 }, { Fireball = { mode = "Unlearning" } }))
    H.advance(1)
    slots = H.skillSlots()
    t.eq(#slots, 2)
    t.eq(slotText(slots[1]), "40", "the newest on top: Fireball")
    t.eq(slots[1].children[1].style.borderColor, "@red", "unlearning: red")
  end)

  t.test("skills go after Keep it for; vertical by default, horizontal on request", function()
    on()
    H.setSkills(sheet(levels{ Archery = 11 }))
    H.advance(1)
    t.eq(H.skillsFrame():Find("skills").kind, "Column", "vertical")
    local w, h = Toolbox.SkillBar.ContentSize()
    t.ok(h > w, "taller than wide")
    H.advance(Toolbox.SkillBar.STAY_DEFAULT + 1)
    t.eq(#H.skillSlots(), 0, "gone after 30 seconds without a change")
    t.eq(H.skillsFrame().visible, false)
    H.chat("/tbx skills horizontal")
    t.eq(H.skillsFrame():Find("skills").kind, "Row")
    H.setSkills(sheet(levels{ Archery = 12, Dodge = 6 }))
    H.advance(1)
    w, h = Toolbox.SkillBar.ContentSize()
    t.ok(w > h, "wider than tall")
    t.eq(H.saved("skills").vertical, false)
  end)

  t.test("experience alone is read now and then, not on every event", function()
    on()
    local reads = 0
    local get = ShroudGetSkills
    ShroudGetSkills = function() reads = reads + 1; return get() end
    for i = 1, 20 do
      H.setSkills(sheet(BASE, { Dodge = { experience = 500 + i } }), false)   -- experience only
      H.advance(0.5)
    end
    ShroudGetSkills = get
    t.ok(reads <= 3, "every few seconds: " .. reads)
    H.setSkills(sheet(levels{ Dodge = 6 }))                                  -- a level: read at once
    H.advance(0.5)
    t.eq(#H.skillSlots(), 1)
  end)

  t.test("off and on again: what levelled meanwhile isn't news; the notification keeps counting", function()
    on()
    H.chat("/tbx notify skills on")
    H.setSkills(sheet(levels{ Fireball = 41 }))
    H.advance(1)
    t.ok(H.nhudRow(1):find("Fireball 41"), "notified")
    H.chat("/tbx skills off")
    H.chat("/tbx notify skills off")
    H.advance(2)
    H.setSkills(sheet(levels{ Fireball = 41, Healing = 35 }))     -- while nothing used the readings
    H.advance(2)
    H.chat("/tbx skills on")
    H.chat("/tbx notify skills on")
    H.advance(2)
    t.eq(#H.skillSlots(), 0, "Healing levelled while it was off: not shown now")
    H.setSkills(sheet(levels{ Fireball = 41, Healing = 36 }))
    H.advance(1)
    t.eq(#H.skillSlots(), 1)
    t.ok(H.nhudRow(1):find("Healing 36%.$"), "the notification still delivers: " .. tostring(H.nhudRow(1)))
  end)

  t.test("clicking a skill opens the game's Skills window", function()
    on()
    H.setSkills(sheet(levels{ Fireball = 41 }))
    H.advance(1)
    H.clickSkill(1)
    t.eq(H.S.stockOpen.skills, true)
  end)

  t.test("settings: its own page, saved and read back; the strip shows while settings are open", function()
    on()
    H.chat("/tbx config")
    H.advance(1)
    t.ok(H.skillsFrame().visible ~= false, "empty, but shown to place it")
    t.eq(H.skillsFrame():Find("sk_placeholder").visible, true)
    t.eq(H.config():Find("skills_show").value, true)
    H.change("toolbox_config", "skills_slots", 3)
    H.change("toolbox_config", "skills_size", 40)
    H.change("toolbox_config", "skills_stay", "1 minute")
    H.change("toolbox_config", "skills_trigger", "Any experience")
    t.eq(#H.skillsFrame():Find("skills").children, 1 + 3, "three slots (and the placeholder)")
    H.reload()
    t.eq(SK().GetSlots(), 3)
    t.eq(SK().GetSize(), 40)
    t.eq(SK().GetStay(), 60)
    t.eq(SK().GetTrigger(), "xp")
    H.chat("/tbx config")
    H.change("toolbox_config", "skills_show", false)
    t.eq(H.skillsFrame(), nil, "off: its frame is freed")
    t.eq(H.config():Find("skills_slots").enabled, false, "the rest greyed out")
  end)

  -- sounds ------------------------------------------------------------------------

  -- On, with both sounds' default files in the package, loaded.
  local function onWithSounds(file)
    H.boot()
    H.S.files[file or "toolbox/skill_up.ogg"] = true
    H.S.files["toolbox/skill_down.ogg"] = true
    H.setSkills(sheet(BASE))
    H.reload()
    H.chat("/tbx skills on")
    H.advance(3)
    H.S.played = {}
  end
  local function played(name)
    local n = 0
    for _, p in ipairs(H.S.played) do if p.name:find(name, 1, true) then n = n + 1 end end
    return n
  end

  t.test("sounds: a celebration for a level gained, a sad one for a level lost; one per burst", function()
    onWithSounds()
    H.setSkills(sheet(levels{ Fireball = 41 }))
    H.advance(1)
    t.eq(played("skill_up"), 1, H.playedNames())
    H.setSkills(sheet(levels{ Fireball = 42, Healing = 31 }))      -- straight after: the same burst
    H.advance(1)
    t.eq(played("skill_up"), 1, "at most one every few seconds")
    H.advance(Toolbox.SkillBar.SOUND_GAP)
    H.setSkills(sheet(levels{ Fireball = 42, Healing = 31, Archery = 9 }, { Archery = { mode = "Unlearning" } }))
    H.advance(1)
    t.eq(played("skill_down"), 1, "a level lost")
    t.eq(played("skill_up"), 1, "not a gain")
    H.advance(Toolbox.SkillBar.SOUND_GAP)
    H.chat("/tbx config")
    H.change("toolbox_config", "skills_sound_up", false)
    H.change("toolbox_config", "skills_sound_down", false)
    H.S.played = {}
    H.setSkills(sheet(levels{ Fireball = 43, Healing = 31, Archery = 8 }))
    H.advance(1)
    t.eq(#H.S.played, 0, "both off: silent")
    H.reload()
    t.eq(SK().GetSoundUp(), false, "saved")
  end)

  t.test("sounds: on the Sounds page, and a player's own file wins", function()
    onWithSounds("toolbox_skill_up.ogg")                           -- a replacement beside the package
    H.chat("/tbx config")
    t.ok(H.config():Find("snd_skill_up_test"), "a Test button for it")
    t.ok(H.config():Find("snd_skill_down_test"))
    H.closeWindow("toolbox_config")
    H.setSkills(sheet(levels{ Dodge = 6 }))
    H.advance(1)
    t.eq(played("toolbox_skill_up"), 1, "the player's file: " .. H.playedNames())
  end)

  t.test("sounds: with the notification's own sound, the level-up sound doesn't play as well", function()
    onWithSounds()
    H.chat("/tbx notify skills on")
    H.chat("/tbx notify skills sound on")
    H.advance(1)
    H.setSkills(sheet(levels{ Fireball = 41 }))
    H.advance(1)
    t.eq(played("skill_up"), 0, "not both")
    t.ok(H.nhudRow(1):find("Fireball 41"))
  end)

  -- the notification --------------------------------------------------------------

  t.test("Skill level ups: off by default, on the notification HUD only", function()
    H.boot()
    H.setSkills(sheet(BASE))
    H.advance(Toolbox.Notify.SETTLE + 1)
    t.eq(Toolbox.Notify.IsOn("skills"), false)
    t.eq(Toolbox.Notify.GetVia("skills"), "hud")
    H.chat("/tbx notify skills on")
    H.clearLogs()
    H.chat("/tbx notify skills via window")
    t.ok(H.logged("Skill level ups can only show via hud"), H.lastLog())
    t.eq(Toolbox.Notify.GetVia("skills"), "hud")
    H.chat("/tbx notify via chat")                      -- all of them: this one stays on the HUD
    t.eq(Toolbox.Notify.GetVia("skills"), "hud")
    H.chat("/tbx config")
    local choices = H.config():Find("notify_skills_via").choices
    t.eq(table.concat(choices, "|"), "HUD|HUD + sound", "only the HUD in its dropdown")
    H.closeWindow("toolbox_config")
    H.advance(1)                                        -- the first reading: where the levels start
    H.setSkills(sheet(levels{ Fireball = 41, Healing = 31 }))
    H.advance(1)
    t.eq(H.notify(), nil, "no window")
    t.ok(H.nhudRow(1):find("Skill level ups: Fireball 41, Healing 31%.$"), H.nhudRow(1))
    t.eq(H.skillsFrame(), nil, "the strip stays off")
  end)

  t.test("/toolbox skills: switches, orientation, what shows a skill, debug", function()
    H.boot()
    H.setSkills(sheet(BASE))
    H.clearLogs()
    H.chat("/tbx skills")
    t.ok(H.logged("Skill activity: on, vertical; shows a skill on level ups and mode changes; sounds: up and down%."),
      H.lastLog())
    H.chat("/tbx skills sound off")
    t.ok(H.logged("sounds: off%.$"), H.lastLog())
    t.eq(SK().GetSoundUp(), false)
    t.eq(SK().GetSoundDown(), false)
    H.chat("/tbx skills xp")
    t.eq(SK().GetTrigger(), "xp")
    H.clearLogs()
    H.chat("/tbx skills debug")
    t.ok(H.logged("Skills read: 5"), H.lastLog())
    H.chat("/tbx skills off")
    t.eq(SK().GetShow(), false)
    H.clearLogs()
    H.chat("/tbx skills sideways")
    t.ok(H.logged("Use /toolbox skills"))
  end)
end
