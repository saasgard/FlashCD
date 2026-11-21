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
local w1 = NAMED.FlashCDWindow
FlashCD.ApplyProfile(data, false)
check(db.groups[1].size == 123 and db.spells.Barkskin.sound == nil, "import without spells keeps this character's spells")
check(NAMED.FlashCDWindow ~= w1, "the window is rebuilt to show the new settings")
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
