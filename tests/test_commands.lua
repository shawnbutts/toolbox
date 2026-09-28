-- Slash command registration and dispatch.
local H = require("harness")

return function(t)
  t.test("both commands are registered from ShroudOnStart", function()
    H.boot()
    t.ok(H.S.commands.toolbox, "/toolbox")
    t.ok(H.S.commands.tbx, "/tbx")
    t.eq(H.S.commands.toolbox, H.S.commands.tbx, "one dispatcher")
  end)

  t.test("constructors raise at file top level (harness enforces it)", function()
    H.boot()
    t.raises(function() Shroud.Command{ name = "x", help = "x", run = print } end, "outside a callback")
    t.raises(function() Shroud.UI.Label{ text = "x" } end, "outside a callback")
  end)

  t.test("a refused registration is reported in chat", function()
    H.boot()
    H.S.taken.tbx = "taken"
    H.S.taken.toolbox = "tooCloseToChat"
    H.clearLogs()
    H.reload()
    t.ok(H.logged("/tbx: taken"), "taken reported")
    t.ok(H.logged("/toolbox: tooCloseToChat"), "tooCloseToChat reported")
  end)

  t.test("commands lists every command in chat", function()
    H.boot()
    H.clearLogs()
    H.chat("/toolbox commands")
    t.ok(H.logged("help"))
    t.ok(H.logged("/toolbox xpdetailed"))
    t.ok(H.logged("/toolbox reset"))
    t.ok(H.logged("/toolbox font"))
    t.ok(H.logged("/toolbox config"))
    t.ok(H.logged("/toolbox xp"))
    t.ok(H.logged("/toolbox spacing"))
    t.ok(H.logged("/toolbox daily"))
    t.ok(H.logged("/tbx"), "mentions the alias")
  end)

  t.test("no arguments opens the settings window; help lists commands", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx")
    t.ok(H.config() and H.config():IsShown(), "settings opened")
    t.eq(#H.logs(), 0, "no chat spam")
    H.chat("/tbx")
    t.no(H.config():IsShown(), "and closed again")
    H.chat("/tbx commands")
    t.ok(H.logged("/toolbox reset"))
    t.ok(H.logged("/toolbox help %- open the Docs window"))
    t.ok(H.logged("/toolbox commands %- list every command in chat"))
    H.chat("/tbx help")
    t.ok(H.S.windows.toolbox_docs:IsShown(), "help opens the Docs")
    H.chat("/tbx help")
    t.ok(H.S.windows.toolbox_docs:IsShown(), "and keeps it open")
  end)

  t.test("first run: a welcome line and the settings window open, once per account", function()
    H.firstBoot()
    t.ok(H.logged("Toolbox is ready: type /toolbox to open its settings"), "first run")
    t.eq(H.config(), nil, "not built in the start-up burst (the element-creation cap)")
    H.advance(Toolbox.WELCOME_DELAY)
    t.ok(H.config() and H.config():IsShown(), "the settings window opened a moment later")
    H.closeWindow("toolbox_config")
    H.clearLogs()
    H.reload()
    t.no(H.logged("Toolbox is ready"), "not again")
    t.no(H.config() and H.config():IsShown(), "and the settings stay closed")
    t.eq(H.saved("welcomed", "account"), true)
  end)

  t.test("the settings window's Docs button opens the Docs window", function()
    H.boot()
    t.eq(H.S.windows.toolbox_docs, nil, "not built until first opened")
    H.chat("/tbx")
    H.click("toolbox_config", "docs")
    t.ok(H.S.windows.toolbox_docs:IsShown())
    H.click("toolbox_config", "docs")
    t.ok(H.S.windows.toolbox_docs:IsShown(), "the button opens (doesn't toggle it closed)")
  end)

  t.test("the Docs window: sections, and every registered command", function()
    H.boot()
    H.chat("/tbx docs")
    local docs = H.S.windows.toolbox_docs
    t.ok(docs:IsShown())
    t.eq(docs.title, "Toolbox Docs")
    local texts = {}
    for _, label in ipairs(docs:Find("docs_body").children) do texts[#texts + 1] = label.text end
    local all = table.concat(texts, "\n")
    for _, heading in ipairs({ "Getting started", "XP", "Today", "Buff bar", "Health & focus bars",
                               "Combat stats", "Moving the HUD strips", "Sounds", "Commands" }) do
      t.ok(all:find("\n" .. heading .. "\n", 1, true) or all:find("^" .. heading .. "\n"), "section " .. heading)
    end
    for _, cmd in ipairs(Toolbox.CommandList()) do
      t.ok(all:find("/toolbox " .. cmd.name, 1, true), "command " .. cmd.name .. " is listed")
    end
    t.ok(all:find("/toolbox xpdetailed (or xpd) - ", 1, true), "aliases shown")
    t.ok(all:find("Lock Status Movement", 1, true), "the HUD lock tip")
    for _, label in ipairs(docs:Find("docs_body").children) do
      t.ok(label.class == "text" or label.class == "heading", "one text colour: " .. label.text)
    end
    H.chat("/tbx docs")
    t.no(docs:IsShown(), "the command toggles it")
    local total = 0
    for _, text in ipairs(texts) do total = total + #text end
    t.ok(total < 20000, "well inside the 64 KiB text budget: " .. total)
  end)

  t.test("/tbx xp opens the XP window; xpdetailed and xpd open XP Detailed", function()
    H.boot()
    H.chat("/tbx xp")
    t.ok(H.compact():IsShown(), "xp -> XP window")
    t.eq(H.compact().title, "XP")
    t.no(H.window():IsShown())
    H.chat("/tbx xpdetailed")
    t.ok(H.window():IsShown(), "xpdetailed -> XP Detailed")
    t.eq(H.window().title, "XP Detailed")
    H.chat("/tbx xpd")
    t.no(H.window():IsShown(), "xpd is the same command")
  end)

  t.test("help shows the xpd alias; the old compact command is gone", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx commands")
    t.ok(H.logged("/toolbox xpdetailed %(or xpd%) %- "), "alias listed")
    H.clearLogs()
    t.no(Toolbox.Dispatch("compact"))
    t.ok(H.logged("Unknown command 'compact'"))
  end)

  t.test("xpdetailed toggles its window, alias and case-insensitive", function()
    H.boot()
    t.no(H.window():IsShown(), "starts closed")
    H.chat("/toolbox xpdetailed")
    t.ok(H.window():IsShown())
    H.chat("/tbx   XPD  ")
    t.no(H.window():IsShown())
  end)

  t.test("reset starts a new session", function()
    H.boot()
    H.gain(5000, 100)
    H.advance(60)
    t.eq(Toolbox.XP.Gained(Toolbox.session, "a"), 5000)
    H.clearLogs()
    H.chat("/tbx reset")
    t.ok(H.logged("New XP session"))
    t.eq(Toolbox.XP.Gained(Toolbox.session, "a"), 0)
    t.eq(Toolbox.session.start, ShroudTime)
  end)

  t.test("unknown subcommand", function()
    H.boot()
    H.clearLogs()
    t.no(Toolbox.Dispatch("frobnicate"))
    t.ok(H.logged("Unknown command 'frobnicate'"))
  end)

  t.test("argument parsing", function()
    H.boot()
    local w, rest = Toolbox.ParseArgs("  Reset   now please ")
    t.eq(w, "reset")
    t.eq(rest, "now please")
    w, rest = Toolbox.ParseArgs(nil)
    t.eq(w, "")
    t.eq(rest, "")
  end)

  t.test("/tbx stats lists matching readable stats and counts hidden ones", function()
    H.boot()
    H.S.stats = {
      { name = "Strength", label = "Strength", value = 50 },
      { name = "HealthMax", label = "Maximum Health", value = 812.5 },
      { name = "HealthRegen", label = "Health Regeneration", value = 3 },
      { name = "SecretHealth", label = "Secret", value = 7, hidden = true },
    }
    H.clearLogs()
    H.chat("/tbx stats HEALTH")
    t.ok(H.logged("^1 HealthMax %(Maximum Health%) = 812.5$"), H.logs()[1])
    t.ok(H.logged("^2 HealthRegen %(Health Regeneration%) = 3$"))
    t.no(H.logged("Strength"), "filtered")
    t.no(H.logged("SecretHealth"), "hidden ones aren't listed")
    t.ok(H.logged("2 readable, 1 hidden from add%-ons matching 'health' %(of 4 stats%)%."), H.lastLog())
  end)

  t.test("/tbx stats caps long lists", function()
    H.boot()
    for i = 1, 60 do H.S.stats[i] = { name = "Stat" .. i, label = "Stat " .. i, value = i } end
    H.clearLogs()
    H.chat("/tbx stats")
    t.ok(H.logged("20 more; narrow it with a word"))
    t.ok(H.logged("60 readable, 0 hidden"))
  end)

  t.test("/tbx version shows the version, build and how many copies loaded", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx version")
    local v = Toolbox.version:gsub("%.", "%%.")
    t.ok(H.logged("^Toolbox " .. v .. ", build dev; API 15; copies loaded: 1$"), H.lastLog())
    ToolboxCopies = 2                        -- as if an old copy also loaded
    H.clearLogs()
    H.chat("/tbx version")
    t.ok(H.logged("copies loaded: 2 %(remove the extra one%)"), H.lastLog())
  end)

  t.test("/tbx version also opens the version window with the changelog", function()
    H.boot()
    H.chat("/tbx version")
    local w = H.S.windows.toolbox_version
    t.ok(w and w:IsShown(), "version window open")
    t.eq(w.title, "Toolbox " .. Toolbox.version)
    t.eq(w:Find("version_line").text, Toolbox.VersionLine())
    local texts = {}
    for _, label in ipairs(w:Find("version_body").children) do texts[#texts + 1] = label.text end
    local all = table.concat(texts, "\n")
    t.ok(all:find("\n" .. Toolbox.version:gsub("%.", "%%.") .. " "), "this version's heading")
    t.ok(all:find("\nAdded\n", 1, true), "sections")
    t.ok(all:find("\n%- "), "items")
    t.no(all:find("`", 1, true), "no markdown left")
    H.chat("/tbx version")
    t.ok(w:IsShown(), "running it again leaves it open")
  end)

  t.test("the baked-in changelog starts with the newest entries", function()
    H.boot()
    local first = Toolbox.CHANGELOG[1]
    t.eq(first[1], "version")
    local seen = false
    for _, e in ipairs(Toolbox.CHANGELOG) do
      if e[1] == "version" and e[2]:find("^" .. Toolbox.version:gsub("%.", "%%.")) then seen = true end
    end
    t.ok(seen, "has an entry for " .. Toolbox.version)
  end)

  t.test("/tbx welcome shows it now; welcome reset shows it at the next load", function()
    H.boot()
    t.no(H.logged("Toolbox is ready"), "a returning player isn't welcomed")
    H.clearLogs()
    H.chat("/tbx welcome")
    t.ok(H.logged("Toolbox is ready"))
    H.advance(Toolbox.WELCOME_DELAY)
    t.ok(H.config():IsShown(), "opens the settings too")
    H.chat("/tbx welcome reset")
    t.ok(H.logged("show again at the next"))
    H.clearLogs()
    H.reload()
    t.ok(H.logged("Toolbox is ready"), "shown at the reload")
    H.clearLogs()
    H.reload()
    t.no(H.logged("Toolbox is ready"), "and only once")
  end)

  t.test("api lists which newer functions exist", function()
    H.boot()
    H.S.noApi16 = true                 -- an older client
    H.reload()
    H.clearLogs()
    H.chat("/tbx api")
    t.ok(H.logged("Lua API 15"))
    t.ok(H.logged("Buff bar %(API 16%): none present"))
    H.clearLogs()
    ShroudSetBuffBarVisible = function() end
    ShroudGetBuffBarRect = function() end
    ShroudGetGuildMotd = function() return "" end
    H.chat("/tbx api")
    t.ok(H.logged("Buff bar %(API 16%): 2 of 5 present; missing ShroudIsBuffBarVisible, ShroudCanDismissBuff"))
    t.ok(H.logged("Friends & guild %(withdrawn from the docs%): 1 of 3 present"))
    t.ok(H.logged("Crafting %(withdrawn from the docs%): none present"))
    ShroudSetBuffBarVisible, ShroudGetBuffBarRect, ShroudGetGuildMotd = nil, nil, nil
  end)

  t.test("Trim and ParseArgs, on short and very long text", function()
    H.boot()
    t.eq(Toolbox.Trim("  a b \n"), "a b")
    t.eq(Toolbox.Trim("   "), "")
    t.eq(Toolbox.Trim(nil), "")
    t.eq(Toolbox.Trim(", 2026-09-28 ,", "%s,"), "2026-09-28")
    local long = " " .. string.rep("x ", 300)
    t.eq(#Toolbox.Trim(long), 599)
    local w, rest = Toolbox.ParseArgs("  Group  add   Tonic Water  ")
    t.eq(w, "group")
    t.eq(rest, "add   Tonic Water")
    w, rest = Toolbox.ParseArgs("XP")
    t.eq(w, "xp")
    t.eq(rest, "")
    w, rest = Toolbox.ParseArgs("")
    t.eq(w, "")
    t.eq(rest, "")
    t.raises(function() return long:match("^%s*(.-)%s*$") end, "pattern too complex")   -- the harness models it
  end)

  t.test("/tbx xp debug: recorded vs game totals, last hour, and ignored lower readings", function()
    H.boot()
    H.gain(500, 0)
    H.advance(2)
    H.clearLogs()
    H.chat("/tbx xp debug")
    t.ok(H.logged("^Session: Tester, started .* ago, %d+ samples; newest .* ago: adventurer 1,000,500, "
      .. "producer 500,000%.$"))
    t.ok(H.logged("^Game totals now: adventurer 1,000,500, producer 500,000%.$"))
    t.ok(H.logged("^Last hour: adventurer %+500, producer %+0%.$"))
    t.ok(H.logged("^Readings lower than recorded, ignored: none%.$"))
    H.S.char.adv = H.S.char.adv - 100            -- a total that went down (a death?)
    H.advance(3)
    H.clearLogs()
    H.chat("/tbx xp debug")
    t.ok(H.logged("^Readings lower than recorded, ignored: %d+; the last .* ago: adventurer 1,000,400 %(recorded "
      .. "1,000,500%)"), H.lastLog())
  end)
end
