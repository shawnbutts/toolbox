-- Notifications (Toolbox.Notify): the guild message of the day, mail and the other game notices.
local H = require("harness")

return function(t)
  local function seen(key)
    local saved = H.saved("notify")
    return saved and saved.sources[key].seen
  end

  -- Booted and past the start-up settling, so counts going down are remembered.
  local function settled()
    H.boot()
    H.advance(Toolbox.Notify.SETTLE + 1)
  end

  -- guild message of the day ------------------------------------------------

  t.test("NewMotd: only a real, unseen message in a guild", function()
    H.boot()
    local N = Toolbox.Notify.NewMotd
    t.eq(N(nil, ""), nil, "no character")
    t.eq(N({ inGuild = false, guildMotd = "Hi" }, ""), nil, "not in a guild")
    t.eq(N({ inGuild = true, guildMotd = "" }, ""), nil, "empty (not loaded yet)")
    t.eq(N({ inGuild = true, guildMotd = "   " }, ""), nil, "only spaces")
    t.eq(N({ inGuild = true }, ""), nil, "missing")
    t.eq(N({ inGuild = true, guildMotd = "Raid at 8" }, ""), "Raid at 8")
    t.eq(N({ inGuild = true, guildMotd = "Raid at 8" }, "Raid at 8"), nil, "already seen")
    t.eq(N({ inGuild = true, guildMotd = " Raid at 8\n" }, "Raid at 8"), nil, "spacing isn't a change")
    t.eq(N({ inGuild = true, guildMotd = "Raid at 9" }, "Raid at 8"), "Raid at 9")
  end)

  t.test("nothing new: no window", function()
    H.boot()
    H.advance(3)
    t.eq(H.notify(), nil)
  end)

  t.test("a guild message that loads after login shows once", function()
    H.boot()
    H.setGuild("Knights", "")
    H.advance(2)
    t.eq(H.notify(), nil, "empty while the guild data loads")
    H.setGuild("Knights", "Raid at 8")
    H.advance(1)
    local n = H.notice("motd")
    t.ok(n.shown)
    t.eq(n.text, "Raid at 8")
    t.eq(n.title, "Knights: message of the day")
    t.eq(seen("motd"), "Raid at 8")
    H.click("toolbox_notify", "n_ok")
    t.no(H.notify():IsShown())
    H.advance(5)
    t.no(H.notify():IsShown(), "not again in the same session")
  end)

  t.test("an unchanged guild message stays hidden after a reload and a restart", function()
    H.boot()
    H.setGuild("Knights", "Raid at 8")
    H.advance(1)
    H.closeWindow("toolbox_notify")
    H.reload()
    H.advance(2)
    t.no(H.notify() and H.notify():IsShown(), "reload")
    H.restart(nil, true)
    H.advance(2)
    t.no(H.notify() and H.notify():IsShown(), "restart")
  end)

  t.test("a changed guild message shows at the next reload, or at once while playing", function()
    H.boot()
    H.setGuild("Knights", "Raid at 8")
    H.advance(1)
    H.closeWindow("toolbox_notify")
    H.S.social.guildMotd = "Raid moved to 9"
    H.reload()
    t.ok(H.notice("motd").shown, "shown from ShroudOnStart")
    t.eq(H.notice("motd").text, "Raid moved to 9")
    H.closeWindow("toolbox_notify")
    H.setMotd("Siege tonight")
    t.eq(H.notice("motd").text, "Siege tonight")
  end)

  t.test("a refused window is retried and not marked seen", function()
    H.boot()
    H.S.showRefused = true
    H.setGuild("Knights", "Raid at 8")
    H.advance(2)
    t.no(H.notify():IsShown())
    t.eq(seen("motd"), nil, "not seen yet")
    H.S.showRefused = false
    H.advance(1)
    t.ok(H.notify():IsShown())
    t.eq(seen("motd"), "Raid at 8")
  end)

  t.test("each character remembers its own", function()
    H.boot()
    H.setGuild("Knights", "Raid at 8")
    H.advance(1)
    H.closeWindow("toolbox_notify")
    H.S.char.name = "Alt"
    H.advance(1)
    t.ok(H.notice("motd").shown, "new to the alt")
  end)

  t.test("the old guild_motd setting is taken over", function()
    H.boot({ ["character:Tester"] = { guild_motd = { show = false, seen = "Raid at 8" } } })
    t.no(Toolbox.Notify.IsOn("motd"))
    Toolbox.Notify.SetOn("motd", true)
    H.setGuild("Knights", "Raid at 8")
    H.advance(2)
    t.eq(H.notify(), nil, "already seen before the move")
  end)

  t.test("/tbx motd: shows the message any time; on/off; outside a guild says so", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx motd")
    t.ok(H.logged("not in a guild"))
    H.setGuild("Knights", "")
    H.chat("/tbx motd")
    t.ok(H.logged("no message of the day"))
    H.chat("/tbx motd off")
    t.no(Toolbox.Notify.IsOn("motd"))
    H.setGuild("Knights", "Raid at 8")
    H.advance(2)
    t.eq(H.notify(), nil, "off: nothing by itself")
    H.chat("/tbx motd")
    t.ok(H.notice("motd").shown)
    t.eq(H.notice("motd").text, "Raid at 8")
  end)

  -- mail and the other notices ----------------------------------------------

  t.test("new mail: shown when the count goes up, quiet when it goes down", function()
    settled()
    H.setNotes{ unreadMail = 2 }
    t.eq(H.notice("mail").text, "You have 2 unread letters.")
    t.eq(seen("mail"), 2)
    H.closeWindow("toolbox_notify")
    H.setNotes{ unreadMail = 1 }                 -- read one
    t.no(H.notify():IsShown(), "no notice for fewer")
    t.eq(seen("mail"), 1)
    H.setNotes{ unreadMail = 3 }
    t.eq(H.notice("mail").text, "2 new letters (3 unread in all).")
  end)

  t.test("counts reading 0 while the game loads don't count as read", function()
    H.boot()
    H.setNotes{ unreadMail = 3 }
    H.closeWindow("toolbox_notify")
    H.restart(nil, true)
    H.S.notes.unreadMail = 0                     -- not loaded yet
    H.advance(5)
    H.setNotes{ unreadMail = 3 }                 -- loaded: the same 3
    H.advance(1)
    t.no(H.notify() and H.notify():IsShown(), "nothing new")
  end)

  t.test("flags: mail expiring and new rewards, once each time they come on", function()
    settled()
    H.setNotes{ mailExpiring = true, newRewards = true }
    t.eq(H.notice("expiring").text, "Some of your mail is about to expire. Collect it before it's gone.")
    t.eq(H.notice("rewards").text, "You have new rewards waiting.")
    H.closeWindow("toolbox_notify")
    H.advance(3)
    t.no(H.notify():IsShown())
    H.setNotes{ mailExpiring = false }
    H.setNotes{ mailExpiring = true }
    t.ok(H.notice("expiring").shown, "on again")
    t.no(H.notice("rewards").shown, "only what's new is listed")
  end)

  t.test("ransoms and guild applications; -1 applications means unknown", function()
    settled()
    H.setNotes{ ransoms = 1 }
    t.eq(H.notice("ransoms").text, "You have 1 ransom notice.")
    H.closeWindow("toolbox_notify")
    H.setNotes{ guildApplications = -1 }
    t.no(H.notify():IsShown())
    H.setNotes{ guildApplications = 2 }
    t.eq(H.notice("applications").text, "2 guild applications are waiting.")
  end)

  t.test("several at once share one window", function()
    settled()
    H.setGuild("Knights", "Raid at 8")
    H.S.notes.unreadMail = 1
    H.advance(1)
    t.ok(H.notice("motd").shown)
    t.ok(H.notice("mail").shown)
    t.no(H.notice("ransoms").shown)
  end)

  t.test("a source switched off keeps up quietly, so switching it on brings no old news", function()
    settled()
    H.chat("/tbx notify mail off")
    t.no(Toolbox.Notify.IsOn("mail"))
    H.setNotes{ unreadMail = 4 }
    t.eq(H.notify(), nil)
    t.eq(seen("mail"), 4)
    H.chat("/tbx notify mail on")
    H.advance(2)
    t.eq(H.notify(), nil)
    H.setNotes{ unreadMail = 5 }
    t.eq(H.notice("mail").text, "1 new letter (5 unread in all).")
  end)

  t.test("/tbx notify lists, switches and shows everything current", function()
    settled()
    H.clearLogs()
    H.chat("/tbx notify")
    t.ok(H.logged("motd %(Guild message of the day%) on, mail %(New mail%) on"))
    H.chat("/tbx notify nope on")
    t.ok(H.logged("Use /toolbox notify <name> on|off"))
    H.chat("/tbx notify show")
    t.ok(H.logged("Nothing to show right now"))
    H.setNotes{ unreadMail = 2 }
    H.closeWindow("toolbox_notify")
    H.chat("/tbx notify show")
    t.eq(H.notice("mail").text, "You have 2 unread letters.", "current state, though seen")
  end)

  t.test("settings: one toggle per source, following the commands", function()
    H.boot()
    H.chat("/tbx config")
    for _, src in ipairs(Toolbox.Notify.Sources()) do
      t.eq(H.config():Find("notify_" .. src.key).value, true, src.key .. " on by default")
    end
    H.chat("/tbx notify rewards off")
    t.eq(H.config():Find("notify_rewards").value, false)
    H.change("toolbox_config", "notify_mail", false)
    t.no(Toolbox.Notify.IsOn("mail"))
    t.eq(H.saved("notify").sources.mail.on, false)
    t.eq(H.saved("notify").sources.mail.via, "window", "delivered by window (the only way for now)")
  end)

  -- the notification HUD --------------------------------------------------

  -- Settled, with mail going to the HUD.
  local function mailToHud()
    settled()
    H.chat("/tbx notify mail via hud")
  end

  t.test("the HUD stays hidden until a source uses it", function()
    settled()
    t.eq(H.nhud().visible, false)
    H.chat("/tbx config")
    H.advance(1)
    t.eq(H.nhud().visible, false, "not even in settings when nothing goes there")
  end)

  t.test("via hud: newest on top, one line each, the whole notice on hover", function()
    mailToHud()
    t.eq(Toolbox.Notify.GetVia("mail"), "hud")
    t.eq(H.saved("notify").sources.mail.via, "hud")
    H.setNotes{ unreadMail = 2 }
    t.ok(H.nhud().visible ~= false, "shown")
    t.eq(H.notify(), nil, "no window")
    local text, tip = H.nhudRow(1)
    t.ok(text:find("New mail: You have 2 unread letters%.$"), text)
    t.ok(tip:find("^New mail.*\nYou have 2 unread letters%.$"), tip)
    H.setNotes{ unreadMail = 3 }
    t.ok(H.nhudRow(1):find("1 new letter"), "newest on top")
    t.ok(H.nhudRow(2):find("2 unread letters"))
    t.eq(H.nhudRow(3), nil)
    local row = H.nhud():Find("nh_1")
    t.eq(row.style.whiteSpace, "nowrap", "one line (the label ends in ... when it runs out of room)")
  end)

  t.test("the HUD hides after 10 seconds, but not while hovered", function()
    mailToHud()
    t.eq(Toolbox.Notify.Hud.GetHideAfter(), 10)
    H.setNotes{ unreadMail = 1 }
    H.advance(5)
    t.ok(H.nhud().visible ~= false)
    H.nhudHover(true)
    H.advance(20)
    t.ok(H.nhud().visible ~= false, "kept while the pointer is on it")
    H.nhudHover(false)
    H.advance(11)
    t.eq(H.nhud().visible, false, "hidden after the wait")
    H.setNotes{ unreadMail = 2 }
    t.ok(H.nhud().visible ~= false, "back for the next one")
  end)

  t.test("hide after: never, other choices, and chat", function()
    mailToHud()
    H.chat("/tbx notify hud hide never")
    H.setNotes{ unreadMail = 1 }
    H.advance(120)
    t.ok(H.nhud().visible ~= false, "never hidden")
    H.clearLogs()
    H.chat("/tbx notify hud hide 7")
    t.ok(H.logged("seconds: 5, 10, 20, 30, 60"))
    H.chat("/tbx notify hud hide 30")
    t.eq(H.saved("notify_hud").hideAfter, 30)
  end)

  t.test("the HUD keeps the latest 20 across a reload; clear empties it", function()
    mailToHud()
    for n = 1, 25 do H.setNotes{ unreadMail = n } end
    t.ok(H.nhudRow(20) ~= nil)
    t.eq(#H.saved("notify_history").list, Toolbox.Notify.Hud.KEEP)
    H.reload()
    t.ok(H.nhudRow(1):find("25 unread in all"), "kept, newest on top")
    H.chat("/tbx notify hud clear")
    t.eq(H.nhudRow(1), nil)
    t.eq(H.nhud().visible, false)
  end)

  t.test("the HUD shows while settings are open, to place it", function()
    mailToHud()
    H.chat("/tbx config")
    H.advance(1)
    t.ok(H.nhud().visible ~= false)
    t.eq(H.config():Find("notify_mail_via").value, "HUD")
    t.eq(H.config():Find("nhud_hide").value, "10 seconds")
    H.change("toolbox_config", "notify_rewards_via", "HUD")
    t.eq(Toolbox.Notify.GetVia("rewards"), "hud")
    H.change("toolbox_config", "nhud_hide", "1 minute")
    t.eq(Toolbox.Notify.Hud.GetHideAfter(), 60)
    H.closeWindow("toolbox_config")
    H.advance(1)
    t.eq(H.nhud().visible, false)
  end)

  t.test("/tbx notify via hud sends everything there; per source too", function()
    settled()
    H.chat("/tbx notify via hud")
    for _, src in ipairs(Toolbox.Notify.Sources()) do t.eq(Toolbox.Notify.GetVia(src.key), "hud", src.key) end
    H.chat("/tbx notify motd via window")
    t.eq(Toolbox.Notify.GetVia("motd"), "window")
    H.clearLogs()
    H.chat("/tbx notify via sky")
    t.ok(H.logged("via window|hud"))
    H.setGuild("Knights", "Raid at 8")
    H.S.notes.unreadMail = 1
    H.advance(1)
    t.ok(H.notice("motd").shown, "the guild message in the window")
    t.no(H.notice("mail") and H.notice("mail").shown, "mail not in the window")
    t.ok(H.nhudRow(1):find("New mail"), "mail on the HUD")
  end)
end
