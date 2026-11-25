-- "Only in a form", the recent flashes log, the "Soon" warning, profiles
-- (copy from a character, export and import)

FlashCDDB = { chars = { ["Alt - Forever"] = { class = "Druid", settings = { sound = "bell",
    groups = { { id = 1, name = "From alt", size = 70 } }, nextGroup = 2 } } } }
local db = LoadAddon()
local calls = {}
local orig = FlashCD.Flash
FlashCD.Flash = function(key, g, soon)
    calls[#calls + 1] = { key = key, soon = soon }
    return orig(key, g, soon)
end
local function last() return calls[#calls] or {} end

-- only while in a form
db.spells.Barkskin.formOnly = true
FORM = 0
local n = #calls
CooldownFor("Barkskin", 40)
check(#calls == n, "'only in a form' doesn't flash out of form")
check(FlashCD.log[1] and FlashCD.log[1].kind == "skip" and FlashCD.log[1].text:find("not in a form"),
    "the log says why it didn't flash")
FORM = 1
CooldownFor("Barkskin", 40)
check(last().key == "Barkskin" and not last().soon, "... and flashes in a form")
check(FlashCD.log[1].kind == "flash" and FlashCD.log[1].text:find("Main"), "the log shows the flash and its group")
FORM = 0
db.spells.Barkskin.formOnly = nil

-- warning before ready (Barkskin: 60 s)
db.preWarn = 3
calls = {}
CooldownFor("Barkskin", 60)
check(calls[1] and calls[1].soon == true, "a 'Soon' flash comes before the cooldown ends")
check(calls[2] and calls[2].key == "Barkskin" and not calls[2].soon, "... then the normal flash")
local soonLog
for _, e in ipairs(FlashCD.log) do if e.kind == "soon" then soonLog = e end end
check(soonLog and soonLog.text:find("ready in"), "the warning is in the log")
db.preWarn = 0

-- profiles: this character is saved for the others
check(FlashCDDB.chars["Tester - Forever"] ~= nil, "logging in saves this character's settings")
local chars = FlashCD.Characters()
check(#chars == 1 and chars[1].key == "Alt - Forever" and chars[1].label:find("Druid"),
    "other characters are listed (not this one), with their class")

-- export / import round trip, with awkward text in a name
db.groups[1].name = 'Big "one" \\ two\nlines'
db.groups[1].size = 123
db.spells.Barkskin.sound = "bell"
local text = FlashCD.ExportString(true)
check(text:sub(1, 10) == "FlashCD:1:" and not text:find("\n"), "export is one line of text starting with FlashCD:1:")
local data, err = FlashCD.ParseExport(text)
check(data ~= nil, "the export reads back" .. (err and (": " .. err) or ""))
check(data and data.settings.groups[1].name == 'Big "one" \\ two\nlines', "quotes, backslashes and new lines survive")
check(data and data.settings.groups[1].size == 123 and data.spells.Barkskin.sound == "bell", "settings and spells survive")

local bad = { "hello", "FlashCD:1:{[\"a\"]=", "FlashCD:1:{[\"a\"]=1}", "FlashCD:1:{[\"settings\"]=os.exit()}" }
local allRejected = true
for _, t in ipairs(bad) do
    local d, e = FlashCD.ParseExport(t)
    if d then allRejected = false end
end
check(allRejected, "foreign, damaged or code-like text is rejected (with a reason)")

-- import replaces settings; spells only when asked
db.groups[1].size = 50
db.spells.Barkskin.sound = nil
-- the name the sidebar shows for the first group
local function SidebarFirst()
    for _, b in ipairs(FindFrames(function(f) return rawget(f, "drop") and rawget(f, "id") == db.groups[1].id end)) do
        if b:IsShown() then return b.text:GetText() end
    end
end
local w1 = _G.FlashCDWindow
FlashCD.ApplyProfile(data, false)
check(db.groups[1].size == 123 and db.spells.Barkskin.sound == nil, "import without spells keeps this character's spells")
check(_G.FlashCDWindow == w1 and SidebarFirst() == db.groups[1].name,
    "the window shows the new settings (refreshed, not built again)")
FlashCD.ApplyProfile(data, true)
check(db.spells.Barkskin.sound == "bell", "import with spells brings the spells too")

-- copy from another character
FlashCD.CopyFromCharacter("Alt - Forever", false)
check(db.groups[1].name == "From alt" and db.groups[1].size == 70 and db.sound == "bell",
    "copying from a character takes its groups and settings")
check(db.groups[1].fontSize == 16 and db.groups[1].color, "missing values get their defaults")
check(db.spells.Barkskin ~= nil, "... and keeps this character's spells")

-- the pages build and refresh
SlashCmdList.FLASHCD("")
FlashCD.Log("Barkskin", "flash", "test entry")
check(FlashCD.log[1].text == "test entry", "log entries can be added while the window is open")

-- a fresh default profile
FlashCD.AddGroup()
db.groups[1].size, db.sound, db.theme = 40, "raid", "wow"
FlashCD.TrackKey("Growl")
db.spells.Growl.group = db.groups[2].id
db.spells.Growl.sound = "bell"
FlashCD.UntrackKey("Maul")
FlashCD.ResetToFresh(false)
check(#db.groups == 1 and db.groups[1].name == "Main" and db.groups[1].size == 96, "fresh profile: one default group")
check(db.sound == "none" and db.theme == "modern", "... and default settings")
check(db.spells.Growl and db.spells.Growl.sound == "bell" and db.spells.Growl.group == nil,
    "... keeps tracked spells (in the default group) unless asked")
check(SidebarFirst() == "Main", "... and the window shows it")
db.learnedCD.Growl = 7
FlashCD.ResetToFresh(true)
check(db.spells.Barkskin ~= nil and db.spells.Growl ~= nil and db.spells.Growl.sound == nil,
    "with spells: the tracked list starts over from the spellbook (spells with a learned cooldown count)")
check(next(db.removed) == nil, "... and unticked spells are forgotten")
check(db.learnedCD.Growl == 7, "learned cooldowns are kept")

-- exporting only some parts
local id2 = FlashCD.AddGroup()
db.groups[1].x, db.groups[1].y, db.groups[1].size = 111, 222, 64
FlashCD.GetGroup(id2).x, FlashCD.GetGroup(id2).y = -50, -60
db.sound = "ping"
local posText = FlashCD.ExportString({ position = true })
local pos = FlashCD.ParseExport(posText)
check(pos and pos.parts.position and not pos.parts.look and not pos.spells, "export holds only the chosen parts")
check(pos and pos.settings.groups[1].x == 111 and pos.settings.groups[1].size == nil and pos.settings.sound == nil,
    "... only positions, no size or sound")

-- import positions only, into a character with one group of its own look
FlashCD.ResetToFresh(false)
db.groups[1].size, db.sound = 40, "bell"
FlashCD.ApplyProfile(pos, true)
check(db.groups[1].x == 111 and db.groups[1].y == 222 and db.groups[1].size == 40,
    "importing positions moves your group and keeps its look")
check(#db.groups == 2 and db.groups[2].x == -50 and db.groups[2].size == 96,
    "a missing group is added, with the default look")
check(db.sound == "bell", "settings not in the text are kept")

-- a full export still replaces the groups completely
local full = FlashCD.ParseExport(FlashCD.ExportString())
FlashCD.AddGroup(); FlashCD.AddGroup()
FlashCD.ApplyProfile(full, true)
check(#db.groups == 2, "a full import replaces the groups")

-- older texts and saved characters (no parts list) hold everything
check(FlashCD.PartsOf({ settings = {} }).look and not FlashCD.PartsOf({ settings = {} }).spells,
    "older profiles count as everything (spells only if present)")
