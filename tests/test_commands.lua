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
    local pick = docs:Find("docs_pick")
    t.eq(pick.value, "Getting started")
    t.eq(#docs:Find("docs_body").children, 1, "only the first topic is built when it opens")
    for _, topic in ipairs(pick.choices) do H.call(function() pick.onChange(pick, topic) end) end
    t.eq(#docs:Find("docs_body").children, #pick.choices, "each topic built once picked")
    local texts, labels = {}, {}
    for _, col in ipairs(docs:Find("docs_body").children) do
      for _, label in ipairs(col.children) do
        texts[#texts + 1] = label.text
        labels[#labels + 1] = label
      end
    end
    t.eq(docs:Find("docs_body").children[1].visible, false, "only the picked topic shows")
    local all = table.concat(texts, "\n")
    for _, heading in ipairs({ "Getting started", "XP", "Today", "Buff bar", "Health, focus & Vigor bars",
                               "Combat stats", "Moving the HUD strips", "Sounds", "Commands" }) do
      t.ok(all:find("\n" .. heading .. "\n", 1, true) or all:find("^" .. heading .. "\n"), "section " .. heading)
    end
    for _, cmd in ipairs(Toolbox.CommandList()) do
      t.ok(all:find("/toolbox " .. cmd.name, 1, true), "command " .. cmd.name .. " is listed")
    end
    t.ok(all:find("/toolbox xpdetailed (or xpd) - ", 1, true), "aliases shown")
    t.ok(all:find("Lock Status Movement", 1, true), "the HUD lock tip")
    for _, label in ipairs(labels) do
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

  -- Commands that are gone: no guide may still offer them (the root README did for a while; review 2026-09-30).
  -- The CHANGELOG records their removal, so it isn't checked.
  local REMOVED = { "uvtest", "buffs frame" }
  t.test("removed commands appear in no guide", function()
    local root = H.PACKAGE .. "/.."
    for _, file in ipairs({ "README.md", "toolbox/README.md", "BETA.md", "INSTALL.md", "AGENTS.md",
                             "toolbox/docs.lua", "toolbox/core.lua", "toolbox/config.lua" }) do
      local f = io.open(root .. "/" .. file)
      t.ok(f, file)
      if f then
        local text = f:read("*a")
        f:close()
        for _, cmd in ipairs(REMOVED) do
          t.no(text:find(cmd, 1, true), file .. " still mentions '" .. cmd .. "'")
        end
      end
    end
    H.boot()
    H.clearLogs()
    H.chat("/tbx buffs uvtest")
    t.no(H.logged("UV test"), "and the command itself is gone")
  end)

  t.test("/tbx version shows the version, build and how many copies loaded", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx version")
    local v = Toolbox.version:gsub("%.", "%%.")
    t.ok(H.logged("^Toolbox " .. v .. ", build dev; API 25; copies loaded: 1$"), H.lastLog())
    ToolboxCopies = 2                        -- as if an old copy also loaded
    H.clearLogs()
    H.chat("/tbx version")
    t.ok(H.logged("copies loaded: 2 %(remove the extra one%)"), H.lastLog())
  end)

  t.test("/tbx version opens the version window: one version's changes at a time, built when picked", function()
    H.boot()
    H.chat("/tbx version")
    local w = H.S.windows.toolbox_version
    t.ok(w and w:IsShown(), "version window open")
    t.eq(w.title, "Toolbox " .. Toolbox.version)
    t.eq(w:Find("version_line").text, Toolbox.VersionLine())
    local pick = w:Find("version_pick")
    t.eq(pick.value, pick.choices[1], "the newest first")
    local mine = nil
    for _, title in ipairs(pick.choices) do
      if title:find("^" .. Toolbox.version:gsub("%.", "%%.") .. " ") then mine = title end
    end
    t.ok(mine, "this version is in the list")
    t.eq(#w:Find("version_body").children, 1, "only the version shown is built")
    local oldest = pick.choices[#pick.choices]              -- never the one shown first
    H.call(function() pick.onChange(pick, oldest) end)
    local body = w:Find("version_body").children
    t.eq(#body, 2, "the picked one is built")
    t.eq(body[1].visible, false, "the one before is hidden")
    local texts = {}
    for _, label in ipairs(body[2].children) do texts[#texts + 1] = label.text end
    local all = "\n" .. table.concat(texts, "\n")
    t.ok(all:find("\nAdded\n", 1, true) or all:find("\nChanged\n", 1, true), "sections")
    t.ok(all:find("\n%- "), "items")
    t.no(all:find("`", 1, true), "no markdown left")
    H.call(function() pick.onChange(pick, pick.choices[1]) end)
    t.eq(#w:Find("version_body").children, 2, "picking one again doesn't rebuild it")
    H.chat("/tbx version")
    t.ok(w:IsShown(), "running it again leaves it open")
  end)

  t.test("ChangelogVersions splits the rows per version", function()
    H.boot()
    local v = Toolbox.Docs.ChangelogVersions({ { "version", "Unreleased" }, { "section", "Added" }, { "item", "A" },
      { "version", "0.1.0" }, { "para", "First." } })
    t.eq(#v, 2)
    t.eq(v[1].title, "Unreleased (newer than " .. Toolbox.version .. ")")
    t.eq(#v[1].entries, 2)
    t.eq(v[2].title, "0.1.0")
    t.eq(v[2].entries[1][2], "First.")
    t.eq(#Toolbox.Docs.ChangelogVersions(nil), 0)
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
    t.ok(H.logged("Lua API 25"))
    t.ok(H.logged("Buff bar %(API 16%): none present"))
    H.clearLogs()
    ShroudSetBuffBarVisible = function() end
    ShroudGetBuffBarRect = function() end
    ShroudGetGuildMotd = function() return "" end
    H.chat("/tbx api")
    t.ok(H.logged("Buff bar %(API 16%): 2 of 5 present; missing ShroudIsBuffBarVisible, ShroudCanDismissBuff"))
    t.ok(H.logged("Friends & guild %(API 18%): 1 of 3 present"))
    t.ok(H.logged("Crafting %(API 18%): all 2 present"))
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

  t.test("every window open at once stays within the game's 8 windows", function()
    H.boot()
    for _, c in ipairs({ "/tbx xp", "/tbx xpdetailed", "/tbx daily", "/tbx dd", "/tbx config", "/tbx combat detail",
                         "/tbx notify show", "/tbx docs", "/tbx version", "/tbx docs", "/tbx version" }) do
      H.chat(c)
    end
    H.setGuild("Knights", "Raid at 8")            -- the Notifications window too
    H.advance(2)
    local n = 0
    for _ in pairs(H.S.windows) do n = n + 1 end
    t.ok(n <= 8, n .. " windows")
    t.ok(H.S.windows.toolbox_version:IsShown(), "the version window, opened last")
    t.eq(H.S.windows.toolbox_docs, nil, "Docs made way for it")
  end)

  -- result-event probe (API 18) ------------------------------------------------

  t.test("a save the game refuses is reported in chat, not every time", function()
    H.boot()
    H.S.flushFails = true
    H.clearLogs()
    H.chat("/tbx reset")                                -- saves and flushes
    H.gain(100, 0)
    H.advance(Toolbox.flushSeconds + 1)
    t.ok(H.logged("Couldn't write Toolbox's saved settings to disk"), H.lastLog())
    local warned = #H.logs()
    H.gain(100, 0)
    H.advance(Toolbox.flushSeconds + 1)
    t.eq(#H.logs(), warned, "at most every few minutes")
    t.ok((Toolbox.flushFailures or 0) >= 2, "each failure is counted")
    H.S.flushFails = nil
  end)

  t.test("/tbx api shows made and the last recipe's yield (API 24)", function()
    H.boot()
    H.S.recipes = { [7] = { id = 7, name = "Crimson Pine Binding", ingredients = {},
                            results = { { name = "Crimson Pine Binding", quantity = 4 } } } }
    H.craftResults({ { kind = "craft", recipeId = 7, recipeName = "Crimson Pine Binding", item = "Crimson Pine Binding",
                       quantity = 1, crafted = 1, exceptional = 0, failed = 0, made = 4, outcome = "success",
                       experience = 100, items = { { name = "Crimson Pine Binding", quantity = 4 } } } })
    H.clearLogs()
    H.chat("/tbx api")
    t.ok(H.logged("failed=0; made=4; outcome=success"))
    t.ok(H.logged("^    last recipe's yield: Crimson Pine Binding x4$"))
    H.S.recipes = { [7] = { id = 7, name = "Crimson Pine Binding", ingredients = {} } }
    H.craftResults({ { kind = "craft", recipeId = 7, recipeName = "Recipe: Crimson Pine Binding", item = "x",
                       quantity = 1, crafted = 1, exceptional = 0, failed = 0, outcome = "success", experience = 1 } })
    H.clearLogs()
    H.chat("/tbx api")
    t.ok(H.logged("^    last recipe's yield: no results field %(before API 24%)$"))
  end)

  t.test("/tbx api reports the result events: not yet, then counts, fields and name matching", function()
    H.boot()
    H.clearLogs()
    H.chat("/tbx api")
    t.ok(H.logged("^  ShroudOnCraftResults: not yet$"))
    t.ok(H.logged("^  ShroudOnGatherResults: not yet$"))
    t.ok(H.logged("^Vigor %(API 20%): all 1 present%.$"))
    H.clearLogs()
    H.craftResults({ { kind = "craft", recipeId = 12, recipeName = "Iron Ingot", item = "Iron Ingot", quantity = 5,
                       crafted = 5, exceptional = 1, failed = 0, outcome = "mixed", experience = 120, items = {} } })
    t.ok(H.logged("^Probe: ShroudOnCraftResults fired: kind=craft; recipeId=12;.*outcome=mixed; experience=120"),
      H.lastLog())
    H.items({ { "Iron Ingot", 5 } })
    H.craftResults({ { kind = "salvage", item = "Iron Sword", quantity = 1, crafted = 0, exceptional = 0, failed = 0,
                       outcome = "success", experience = 0, items = { { name = "Iron Ingot", quantity = 2 } } } })
    t.eq(#H.logs(), 1, "the chat line only the first time")
    H.gatherResults({ { node = "Iron Ore Node", failed = false, experience = 40,
                        items = { { name = "Iron Ore", quantity = 3 } } } }, 2)
    H.craftingState({ open = true, station = "Smelter", busy = false })
    H.clearLogs()
    H.chat("/tbx api")
    t.ok(H.logged("^  ShroudOnCraftResults: 2 times %(2 results%)"), "counted")
    t.ok(H.logged("^    last: kind=salvage.*items: Iron Ingot x2"), "salvage returns listed")
    t.ok(H.logged("^  ShroudOnGatherResults: 1 time %(1 result, 2 dropped%)"))
    t.ok(H.logged("node=Iron Ore Node; failed=false; experience=40; items: Iron Ore x3"))
    t.ok(H.logged("^  ShroudOnCraftingStateChanged: 1 time"))
    t.ok(H.logged("open=true; station=Smelter; busy=false"))
    t.ok(H.logged("^  Last items gained %(%d+s ago%): Iron Ingot x5"))
    t.ok(H.logged("^  Gathered names also seen gained: none; not seen gained %(yet%): Iron Ore$"))
    H.items({ { "Iron Ore", 3 } })                     -- looted from the node; the station is still open
    H.craftingState({ open = false, station = "", busy = false })
    H.items({ { "Wolf Pelt", 1 } })                    -- not from the station
    H.clearLogs()
    H.chat("/tbx api")
    t.ok(H.logged("^  Gathered names also seen gained: Iron Ore$"))
    t.ok(H.logged("^  Gained while a crafting window was open: Iron Ore x3$"), "only while it was open")
  end)

  t.test("the probe reads results that are game objects, and says when names differ", function()
    H.boot()
    local obj = setmetatable({}, { __index = function(_, k)
      local fields = { kind = "craft", item = "Iron Ingot (Exceptional)", crafted = 1 }
      if fields[k] == nil then error("no field " .. k) end
      return fields[k]
    end })
    H.craftResults({ obj })
    H.items({ { "Iron Ingot", 1 } })
    H.clearLogs()
    H.chat("/tbx api")
    t.ok(H.logged("first: kind=craft; item=Iron Ingot %(Exceptional%); crafted=1"), "fields read, missing ones skipped")
    t.ok(H.logged("isn't among them"), "the loot filter would need a closer look")
  end)
end

