-- The skill activity strip (Toolbox.SkillBar, skills.lua): skills pop up as they level, on a strip of their
-- own; a "Skill level changes" notification on the notification HUD only. To remove the feature, delete this
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
  -- a slot: Column{ frame Row{ icon, the level's outline x4, the level }, progress Bar }
  local function number(slot) local kids = slot.children[1].children; return kids[#kids] end
  local function slotText(slot) return number(slot).text end
  local function bar(slot) return slot.children[2] end
  local function slotTip(slot) return slot.children[1].children[1].tooltip or "" end

  -- model -------------------------------------------------------------------------

  t.test("Update: the first reading is the baseline; a level or mode change puts the skill on top", function()
    H.boot()
    local st = SK().NewState()
    t.eq(SK().Update(st, SK().Read(sheet(BASE)), 0, "levels", 12), false, "the baseline: nothing pops")
    t.eq(#st.active, 0)
    SK().Update(st, SK().Read(sheet(levels{ Healing = 31 })), 1, "levels", 12)
    t.eq(st.active[1].data.name, "Healing")
    t.eq(st.changes.n, 1, "a level change queued for the notification")
    SK().Update(st, SK().Read(sheet(levels{ Healing = 31 }, { Archery = { mode = "Unlearning" } })), 2, "levels", 12)
    t.eq(st.active[1].data.name, "Archery", "a mode change too, on top")
    t.eq(st.active[2].data.name, "Healing")
    t.eq(st.changes.n, 1, "a mode change isn't a level change")
    SK().Update(st, SK().Read(sheet(levels{ Healing = 32 }, { Archery = { mode = "Unlearning" } })), 3, "levels", 12)
    t.eq(#st.active, 2, "one slot per skill: refreshed, not added")
    t.eq(st.active[1].data.level, 32)
  end)

  t.test("Update: a scene's cap on the tile level isn't a level change; a trained level is", function()
    H.boot()
    local st = SK().NewState()
    SK().Update(st, SK().Read(sheet(BASE)), 0, "levels", 12)
    -- a capped scene: every tile shows 20 or less, the trained levels don't move (review, 2026-10-02)
    local capped = sheet(BASE)
    for _, sk in ipairs(capped) do sk.level = math.min(sk.level, 20) end
    t.eq(SK().Update(st, SK().Read(capped), 1, "levels", 12), false, "nothing pops")
    t.eq(st.changes.n, 0, "no level change queued")
    t.eq(st.downs, 0, "no sad sound")
    capped[1].trainedLevel = 41                       -- Fireball trains a level; its tile still shows 20
    SK().Update(st, SK().Read(capped), 2, "levels", 12)
    t.eq(st.changes.n, 1, "a trained level is a change")
    t.eq(st.changes.list[1].to, 41)
    t.eq(st.active[1].data.name, "Fireball")
    t.ok(SK().Tooltip(st.active[1].data):find("Level 41 %(20 in this scene%)"), SK().Tooltip(st.active[1].data))
    SK().Update(st, SK().Read(sheet(levels{ Fireball = 41 })), 3, "levels", 12)   -- out of the capped scene
    t.eq(st.changes.n, 1, "leaving it isn't one either")
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

  t.test("ChangesText: each skill once, from before the first change to after the last", function()
    H.boot()
    local ch = { n = 5, list = { { id = 1, name = "Fireball", from = 40, to = 41 },
                                 { id = 2, name = "Archery", from = 10, to = 9 },
                                 { id = 3, name = "Fireball", from = 41, to = 42 },
                                 { id = 4, name = "Dodge", from = 5, to = 6 },
                                 { id = 5, name = "Dodge", from = 6, to = 5 } } }
    local text, n, allDown = SK().ChangesText(ch, 0)
    t.eq(text, "Fireball up to 42, Archery down to 9, Dodge back to 5.")
    t.eq(n, 5)
    t.eq(allDown, false)
    text, n, allDown = SK().ChangesText({ n = 2, list = { ch.list[2] } }, 1)
    t.eq(text, "Archery down to 9.")
    t.eq(allDown, true, "only levels lost")
    t.eq(SK().ChangesText(ch, 5), nil)
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
    t.eq(number(slots[1]).style.color, "@gold", "a new level in gold")
    t.eq(number(slots[1]).style.marginLeft, -Toolbox.SkillBar.GetSize(), "over the icon")
    t.eq(#slots[1].children[1].children, 1 + #Toolbox.BuffBar.COUNT_OUTLINE + 1, "outlined like the buff count")
    t.eq(bar(slots[1]).value, 0.4, "progress to the next")
    t.eq(bar(slots[1]).color, "@green", "it went up: green")
    t.eq(slots[1].children[1].style.borderColor, "@green", "training: green")
    t.eq(slots[1].children[1].children[1].texture, 502, "its icon")
    t.ok(slotTip(slots[1]):find("^Healing\nLevel 31, 40%% to the next\nTraining"), slotTip(slots[1]))
    H.advance(Toolbox.SkillBar.NEW_FOR + 1)
    t.eq(number(slots[1]).style.color, Toolbox.SkillBar.NUMBER_COLOR, "then plain")
    H.setSkills(sheet(levels{ Healing = 31 }, { Fireball = { mode = "Unlearning" } }))
    H.advance(1)
    slots = H.skillSlots()
    t.eq(#slots, 2)
    t.eq(slotText(slots[1]), "40", "the newest on top: Fireball")
    t.eq(slots[1].children[1].style.borderColor, "@red", "unlearning: red")
  end)

  t.test("the progress bar: green while the skill rises, red while it falls", function()
    on()
    H.chat("/tbx skills xp")
    H.setSkills(sheet(BASE, { Dodge = { experience = 600, progress = 0.3 } }), false)
    H.advance(Toolbox.SkillBar.XP_EVERY + 1)
    t.eq(bar(H.skillSlots()[1]).color, "@green", "experience gained")
    H.setSkills(sheet(BASE, { Dodge = { experience = 550, progress = 0.2 } }), false)
    H.advance(Toolbox.SkillBar.XP_EVERY + 1)
    t.eq(bar(H.skillSlots()[1]).color, "@red", "experience lost")
    t.eq(bar(H.skillSlots()[1]).value, 0.2)
    H.setSkills(sheet(levels{ Dodge = 4 }, { Dodge = { experience = 380 } }))
    H.advance(1)
    t.eq(bar(H.skillSlots()[1]).color, "@red", "a level lost")
    H.setSkills(sheet(levels{ Dodge = 5 }, { Dodge = { experience = 501 } }))
    H.advance(1)
    t.eq(bar(H.skillSlots()[1]).color, "@green", "and back up")
  end)

  t.test("Keep it for Always: skills stay until newer ones need the room", function()
    on()
    H.chat("/tbx config")
    H.change("toolbox_config", "skills_stay", "Always")
    H.change("toolbox_config", "skills_slots", 2)
    H.closeWindow("toolbox_config")
    H.setSkills(sheet(levels{ Archery = 11 }))
    H.advance(600)
    t.eq(#H.skillSlots(), 1, "still there after ten minutes")
    H.setSkills(sheet(levels{ Archery = 11, Dodge = 6 }))
    H.advance(1)
    H.setSkills(sheet(levels{ Archery = 11, Dodge = 6, Healing = 31 }))
    H.advance(1)
    local slots = H.skillSlots()
    t.eq(#slots, 2, "the most shown")
    t.eq(slotText(slots[1]), "31")
    t.eq(slotText(slots[2]), "6", "Archery, the quietest, made room")
    t.eq(H.saved("skills").stay, 0)
  end)

  t.test("the level on the icon can be hidden (and shown again) in place", function()
    on()
    H.setSkills(sheet(levels{ Archery = 11 }))
    H.advance(1)
    local slot = H.skillSlots()[1]
    H.chat("/tbx config")
    H.change("toolbox_config", "skills_number", false)
    local kids = slot.children[1].children
    for i = 2, #kids do t.eq(kids[i].visible, false, "the level and its outline hidden") end
    t.eq(H.skillSlots()[1], slot, "not rebuilt")
    t.ok(slot.children[1].children[1].tooltip:find("Level 11"), "the tooltip still has it")
    H.reload()
    t.eq(Toolbox.SkillBar.GetNumber(), false, "saved")
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
    t.ok(H.nhudRow(1):find("Fireball up to 41"), "notified")
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
    t.ok(H.nhudRow(1):find("Healing up to 36%.$"), "the notification still delivers: " .. tostring(H.nhudRow(1)))
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

  t.test("sounds: any notification can pick them; Skill level changes plays the celebration", function()
    onWithSounds()
    H.chat("/tbx config")
    local choices = table.concat(H.config():Find("notify_skills_snd").choices, "|")
    t.ok(choices:find("Celebration|Sad notes", 1, true), choices)
    t.eq(H.config():Find("notify_skills_snd").value, "Celebration", "Skill level changes: the celebration by default")
    t.eq(H.config():Find("notify_mail_snd").value, "Chime", "the others keep the chime")
    H.chat("/tbx notify mail sound on")
    H.change("toolbox_config", "notify_mail_snd", "Sad notes")
    t.eq(Toolbox.Notify.GetSoundKey("mail"), "skill_down")
    H.chat("/tbx notify friends sound celebration")
    t.eq(Toolbox.Notify.GetSoundKey("friends"), "skill_up")
    H.closeWindow("toolbox_config")
    H.chat("/tbx notify skills on")
    H.chat("/tbx notify skills sound on")
    H.advance(1)
    H.S.played = {}
    H.setSkills(sheet(levels{ Fireball = 41 }))
    H.advance(1)
    t.eq(played("skill_up"), 1, "one celebration (the notification's), not two: " .. H.playedNames())
    H.advance(Toolbox.SkillBar.SOUND_GAP + 1)
    H.S.played = {}
    H.setSkills(sheet(levels{ Fireball = 41, Archery = 9 }, { Archery = { mode = "Unlearning" } }))
    H.advance(1)
    t.ok(H.nhudRow(1):find("Archery down to 9%.$"), H.nhudRow(1))
    t.eq(H.playedNames():find("skill_up", 1, true), nil, "a level lost: not the celebration")
    t.eq(played("skill_down"), 1, "the Sad notes, once: " .. H.playedNames())
  end)

  -- the notification --------------------------------------------------------------

  t.test("Skill level changes: off by default, on the notification HUD only, levels up and down", function()
    H.boot()
    H.setSkills(sheet(BASE))
    H.advance(Toolbox.Notify.SETTLE + 1)
    t.eq(Toolbox.Notify.IsOn("skills"), false)
    t.eq(Toolbox.Notify.GetVia("skills"), "hud")
    H.chat("/tbx notify skills on")
    H.clearLogs()
    H.chat("/tbx notify skills via window")
    t.ok(H.logged("Skill level changes can only show via hud"), H.lastLog())
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
    t.ok(H.nhudRow(1):find("Skill level changes: Fireball up to 41, Healing up to 31%.$"), H.nhudRow(1))
    H.setSkills(sheet(levels{ Fireball = 41, Healing = 31, Archery = 9 }))
    H.advance(1)
    t.ok(H.nhudRow(1):find("Skill level changes: Archery down to 9%.$"), "a level lost: " .. H.nhudRow(1))
    t.eq(H.skillsFrame(), nil, "the strip stays off")
  end)

  t.test("another character: no notice from the first one, delivered or not", function()
    H.boot()
    H.setSkills(sheet(BASE))
    H.chat("/tbx notify skills on")
    H.advance(2)
    H.setSkills(sheet(levels{ Fireball = 41 }))
    H.advance(1)
    t.ok(H.nhudRow(1):find("Fireball up to 41"), "delivered to Tester")
    H.setSkills(sheet(levels{ Fireball = 41, Healing = 31 }))   -- Tester levels, and logs out before it's read
    H.S.char.name = "Alt"
    H.chat("/tbx notify skills on")
    H.advance(5)
    t.eq(Toolbox.Notify.Hud.Count(), 0, "nothing of Tester's on Alt's HUD: " .. tostring(H.nhudRow(1)))
    H.setSkills(sheet(levels{ Fireball = 41, Healing = 31, Dodge = 6 }))
    H.advance(1)
    t.ok(H.nhudRow(1):find("Skill level changes: Dodge up to 6%.$"), "Alt's own: " .. tostring(H.nhudRow(1)))
    t.eq(H.nhudRow(2), nil, "only Alt's")
    t.eq(#H.saved("notify_history").list, 1, "Alt's saved history: only Alt's notice")
  end)

  t.test("sounds: the strip's own only with the strip on; the notification's only with its + sound", function()
    -- { strip on, notification + sound, what plays }
    for _, case in ipairs({ { false, false, "" }, { false, true, "skill_up" }, { true, false, "skill_up" },
                            { true, true, "skill_up" } }) do
      H.boot()
      H.S.files["toolbox/skill_up.ogg"] = true
      H.S.files["toolbox/skill_down.ogg"] = true
      H.setSkills(sheet(BASE))
      H.reload()
      if case[1] then H.chat("/tbx skills on") end
      H.chat("/tbx notify skills on")
      if case[2] then H.chat("/tbx notify skills sound on") end
      H.advance(3)
      H.S.played = {}
      H.setSkills(sheet(levels{ Fireball = 41 }))
      H.advance(1)
      local what = string.format("strip %s, notification sound %s", tostring(case[1]), tostring(case[2]))
      t.eq(#H.S.played, case[3] == "" and 0 or 1, what .. ": " .. H.playedNames())
      if case[3] ~= "" then t.ok(H.playedNames():find(case[3], 1, true), what .. ": " .. H.playedNames()) end
    end
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
