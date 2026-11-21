-- Presets: ready-made looks to start from

SPELLBOOK[#SPELLBOOK + 1] = { spellID = 20, name = "Rake" }
BASE_CD[20] = 10000                   -- a short cooldown: goes to the small group
local db = LoadAddon()
db.theme, db.minCD = "wow", 5
db.spells.Barkskin.sound = "bell"
check(db.spells.Barkskin and db.spells.Rake, "Barkskin (60 s) and Rake (10 s) are tracked")

for _, p in ipairs(FlashCD.PRESETS) do
    check(p.label and p.desc, "preset " .. p.key .. " has a name and a description")
end

FlashCD.ApplyPreset("bigsmall", false)
check(#db.groups == 2 and db.groups[1].name == "Big" and db.groups[2].name == "Small", "Big and small makes two groups")
check(FlashCD.GroupOf("Barkskin").name == "Big" and FlashCD.GroupOf("Rake").name == "Small",
    "... long cooldowns go big, short ones small")
check(db.groups[1].color and db.groups[2].color and db.groups[1].fontSize == 16, "... with colours and every value filled in")
check(db.theme == "wow" and db.minCD == 5 and db.spells.Barkskin.sound == "bell",
    "a preset keeps the theme, other settings and the spells' own settings")

FlashCD.ApplyPreset("bold", false)
check(#db.groups == 1 and db.groups[1].size == 140 and db.groups[1].anim == "bounce", "Big and bold: one large bouncing group")
check(db.sound == "raid", "... and sets the raid warning sound")
check(FlashCD.GroupOf("Rake") == db.groups[1], "spells go to the one group")

FlashCD.ApplyPreset("minimal", true)
check(db.groups[1].glow == false and db.groups[1].size == 56, "Minimal: a small icon without glow")
check(db.spells.Barkskin and db.spells.Barkskin.sound == nil, "starting over with spells clears their own settings")

FlashCD.ApplyPreset("right", false)
check(db.groups[1].x == 260 and db.groups[1].grow == "down", "Column on the right: right of the middle, growing down")
FlashCD.ApplyPreset("left", false)
check(db.groups[1].x == -260 and db.groups[1].grow == "down", "Column on the left: the same on the left")

FlashCD.ApplyPreset("default", false)
check(db.theme == "modern" and db.minCD == 0 and db.groups[1].name == "Main", "Default (start fresh) resets everything")

-- the welcome's preset choice applies at once
FlashCDDB.welcomed = nil
FlashCD.ShowWelcome()
local w = NAMED.FlashCDWelcome
check(w and w.preset and w:IsShown(), "the welcome has a preset choice")

-- previewing a preset shows its flashes but changes nothing
local calls = {}
local origFlash = FlashCD.Flash
FlashCD.Flash = function(key, g, soon, opts)
    calls[#calls + 1] = { key = key, group = g and g.id, name = g and g.name, top = opts and opts.top, quiet = opts and opts.quiet }
    return origFlash(key, g, soon, opts)
end
local before = #db.groups .. db.groups[1].name .. db.groups[1].size .. db.sound
local played = #SOUNDS_PLAYED
FlashCD.PreviewPreset("bigsmall")
local where = {}
for _, c in ipairs(calls) do where[c.key] = c.name end
check(where.Barkskin == "Big" and where.Rake == "Small", "preview of Big and small: long cooldowns big, short ones small")
check(calls[1].top and calls[1].quiet, "preview flashes are drawn above windows, without each spell's sound")
check(#db.groups .. db.groups[1].name .. db.groups[1].size .. db.sound == before, "previewing changes no settings")
FlashCD.PreviewPreset("bold")
check(#SOUNDS_PLAYED > played, "the Big and bold preview plays its sound")

-- Test flash is drawn above windows too
calls = {}
FlashCD.Test()
check(calls[1] and calls[1].top, "Test flash is drawn above windows")

-- hovering a preset in the welcome's list previews it
calls = {}
w.preset.button._s_OnClick(w.preset.button)
local items = FindFrames(function(f) return rawget(f, "mark") and rawget(f, "_s_OnEnter") end)
check(#items > 0, "the preset list opens")
items[1]._s_OnEnter(items[1])
check(#calls > 0 and calls[1].group == "preview1", "hovering a preset previews it")
check(#db.groups .. db.groups[1].name .. db.groups[1].size .. db.sound == before, "... without using it")
