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
  -- a slot: Column{ frame Row{ icon, the level's outline x4, the level[, training click areas] }, progress Bar }
  local function number(slot) return slot.children[1].children[#Toolbox.BuffBar.COUNT_OUTLINE + 2] end
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
    t.eq(#slots[1].children[1].children, 1 + #Toolbox.BuffBar.COUNT_OUTLINE + 1 + 1,
      "outlined like the buff count (then the training click areas)")
    t.eq(bar(slots[1]).value, 0.4, "progress to the next")
    t.eq(bar(slots[1]).color, "@green", "it went up: green")
    t.ok(slots[1].children[1].style.borderColor == "@green" or slots[1].children[1].style.borderColor == "@gold",
      "training: green (flashing gold just after its level)")
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

  t.test("a level gained: the icon flashes for a few seconds, then settles; a level lost doesn't", function()
    on()
    H.setSkills(sheet(levels{ Healing = 31 }))
    H.advance(0.5, 0.25)
    local slot = H.skillSlots()[1]
    local frame, icon = slot.children[1], slot.children[1].children[1]
    local borders, dims = {}, {}
    for _ = 1, 6 do
      H.advance(0.25, 0.25)
      borders[frame.style.borderColor] = true
      dims[icon.style.opacity] = true
    end
    t.ok(borders["@gold"] and borders["@green"], "the frame flashes gold (and back to training green)")
    t.ok(dims[Toolbox.SkillBar.FLASH_DIM] and dims[1], "the icon pulses")
    H.advance(Toolbox.SkillBar.FLASH_SECONDS, 0.25)
    t.eq(frame.style.borderColor, "@green", "then settles")
    t.eq(icon.style.opacity, 1)
    t.eq(H.S.periodics.toolbox_skills_flash, nil, "its quick timer stops")
    H.setSkills(sheet(levels{ Healing = 31, Archery = 9 }))
    H.advance(0.5, 0.25)
    local lost = H.skillSlots()[1]
    for _ = 1, 4 do
      H.advance(0.25, 0.25)
      t.eq(lost.children[1].style.borderColor, "@green", "a level lost: no flash")
    end
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
    for i = 2, #Toolbox.BuffBar.COUNT_OUTLINE + 2 do
      t.eq(kids[i].visible, false, "the level and its outline hidden")
    end
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

  -- training markers (API 27) ----------------------------------------------------------

  local function marksOn(extra)
    H.boot()
    for _, f in ipairs({ "skill_train", "skill_maintain", "skill_unlearn" }) do
      H.S.files["toolbox/" .. f .. ".ogg"] = true
    end
    H.setSkills(sheet(BASE, extra))
    H.reload()
    H.chat("/tbx skills on")
    H.advance(3)
    H.setSkills(sheet(levels{ Fireball = 41 }, extra))
    H.advance(Toolbox.SkillBar.FLASH_SECONDS + 1)   -- past its level-up flash
    H.S.played = {}
  end
  local function opacities(n)
    local _, marks = H.skillMarks(n)
    local out = {}
    for i, m in ipairs(marks) do out[i] = tostring(m.style and m.style.opacity) end
    return table.concat(out, ",")
  end

  t.test("markers: left half opens Skills; right half train / maintain / unlearn, the mode lit", function()
    marksOn()
    local open, marks = H.skillMarks(1)
    t.ok(open and #marks == 3, "the click areas over the icon")
    t.eq(marks[1].tint, "@green")
    t.eq(marks[2].tint, "@gold")
    t.eq(marks[3].tint, "@red")
    t.eq(marks[3].rotation, 180, "the arrow turned down")
    local s = SK().GetSize()
    t.eq(open.width, math.floor(s / 2), "the left half")
    t.eq(marks[1].width, s - math.floor(s / 2), "the right half")
    t.eq(opacities(1), "1,0.35,0.35", "training: train lit, the others faded")
    t.ok(marks[2].tooltip:find("Click: maintain"), marks[2].tooltip)
    H.clickSkillPart(1, "open")
    t.eq(H.S.stockOpen.skills, true, "the left half opens the Skills window")
  end)

  t.test("markers: the level shrinks and moves left, clear of them; back without them", function()
    marksOn()
    local s = SK().GetSize()
    local level = H.skillSlots()[1].children[1].children[#Toolbox.BuffBar.COUNT_OUTLINE + 2]
    t.eq(level.style.textAlign, "left")
    t.eq(level.style.fontSize, math.max(9, math.floor(Toolbox.BuffBar.CountFont(s) * 0.8)), "80% of its size")
    t.ok(level.style.paddingLeft >= 1 and level.style.paddingLeft < s / 4, "a little in from the left")
    H.chat("/tbx config")
    H.change("toolbox_config", "skills_marks", false)
    H.advance(1)
    level = H.skillSlots()[1].children[1].children[#Toolbox.BuffBar.COUNT_OUTLINE + 2]
    t.eq(level.style.textAlign, "center", "no markers: centred, full size")
    t.eq(level.style.fontSize, Toolbox.BuffBar.CountFont(s))
  end)

  t.test("markers: a click sets that mode, with its sound; clicking the lit one does nothing", function()
    marksOn()
    H.clickSkillPart(1, "maintain")
    t.eq(H.S.skills[1].mode, "Maintaining", "the game's mode set")
    t.eq(opacities(1), "0.35,1,0.35", "maintain lit now")
    t.ok(played("skill_maintain") == 1, H.playedNames())
    local calls = H.S.modeCalls
    H.clickSkillPart(1, "maintain")
    t.eq(H.S.modeCalls, calls, "already maintaining: nothing")
    H.clickSkillPart(1, "unlearn")
    t.eq(H.S.skills[1].mode, "Unlearning")
    t.eq(played("skill_unlearn"), 1)
    t.eq(H.skillSlots()[1].children[1].style.borderColor, "@red", "the frame follows the mode")
  end)

  t.test("markers: the game's rules: maintains instead, stops instead, refused", function()
    marksOn({ Fireball = { mastery = true } })
    H.clearLogs()
    H.clickSkillPart(1, "train")                 -- (it's training: unlearn first, then ask to train)
    H.clickSkillPart(1, "unlearn")
    H.clickSkillPart(1, "train")
    t.ok(H.logged("Fireball: not one of your specializations, so it maintains instead%."), H.lastLog())
    t.eq(opacities(1), "0.35,1,0.35", "it maintains")
    marksOn({ Fireball = { low = true } })
    H.clearLogs()
    H.clickSkillPart(1, "maintain")
    t.ok(H.logged("too low to maintain or unlearn, so it stops training instead"), H.lastLog())
    t.eq(opacities(1), "0.35,0.35,0.35", "off: none lit")
    marksOn({ Fireball = { elixir = true } })
    t.eq(opacities(1), "1,0.12,0.12", "an elixir skill: the others can't be set")
    local calls = H.S.modeCalls or 0
    H.clickSkillPart(1, "unlearn")
    t.eq(H.S.modeCalls or 0, calls, "nothing asked")
  end)

  t.test("markers: off in settings, or an older client: the whole icon opens Skills", function()
    marksOn()
    H.chat("/tbx config")
    H.change("toolbox_config", "skills_marks", false)
    H.advance(1)
    t.eq(H.skillMarks(1), nil, "no click areas")
    t.eq(H.saved("skills").marks, false)
    H.clickSkill(1)
    t.eq(H.S.stockOpen.skills, true)
    H.boot()
    ShroudSetSkillMode, ShroudCanSetSkillMode = nil, nil
    H.setSkills(sheet(BASE))
    H.chat("/tbx skills on")
    H.advance(3)
    H.setSkills(sheet(levels{ Fireball = 41 }))
    H.advance(1)
    t.eq(H.skillMarks(1), nil, "API 26: none")
    H.chat("/tbx config")
    t.eq(H.config():Find("skills_marks").enabled, false, "the setting greyed out")
  end)

  t.test("markers: a passing \"not now\" isn't remembered; an error isn't taken for a yes", function()
    marksOn()
    local real = ShroudCanSetSkillMode
    ShroudCanSetSkillMode = function() return false, "notNow", "Learning" end   -- a loading screen, say
    H.setSkills(sheet(levels{ Fireball = 41, Healing = 31 }))
    H.advance(1)
    local slot = 1                                   -- Healing, on top
    t.eq(opacities(slot), "1,0.35,0.35", "not now: faded as usual, not refused")
    ShroudCanSetSkillMode = real
    H.advance(10)
    H.clickSkillPart(slot, "maintain")
    t.eq(H.S.skills[2].mode, "Maintaining", "back in normal play: it works")
    ShroudCanSetSkillMode = function() error("boom") end
    H.setSkills(sheet(levels{ Fireball = 41, Healing = 31, Dodge = 6 }))
    H.advance(1)
    local _, marks = H.skillMarks(1)
    t.eq(marks[2].style.opacity, Toolbox.SkillBar.MARK_OFF, "an error: unknown, not lit as allowed")
    ShroudCanSetSkillMode = real
  end)
end
