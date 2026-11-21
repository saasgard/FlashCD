-- Telling real cooldowns from lockouts, odd spell names, learned and form cooldowns

SPELLBOOK[#SPELLBOOK + 1] = { spellID = 4, name = "Faerie Fire (Feral)" }
BASE_CD[4] = 6000
SPELLBOOK[#SPELLBOOK + 1] = { spellID = 5, name = "Faerie Fire" }       -- cooldown not reported
SPELLBOOK[#SPELLBOOK + 1] = { spellID = 7, name = "Demoralizing Roar" } -- replaced in a form
SPELLBOOK[#SPELLBOOK + 1] = { spellID = 9, name = "Maul" }              -- no cooldown at first
local db = LoadAddon()
local fl = RecordFlashes()
FlashCD.TrackKey("Growl")

-- wand / ranged lockouts: short, look like cooldowns
for _ = 1, 4 do
    CooldownFor("Barkskin", 2.5)
    CooldownFor("Growl", 2.5)
end
check(#fl == 0, "wand lockouts (2.5 s) don't flash")
CooldownFor("Growl", 8)
check(fl[#fl] == "Growl", "an 8 s cooldown with no base cooldown flashes")
local n = #fl
CooldownFor("Barkskin", 20)
check(#fl == n, "less than half the base cooldown counts as a lockout")

-- a name with brackets: looked up by spellbook ID
check(db.spells["Faerie Fire (Feral)"] ~= nil, "Faerie Fire (Feral) is auto-tracked")
CooldownFor("Faerie Fire (Feral)", 6)
check(fl[#fl] == "Faerie Fire (Feral)", "Faerie Fire (Feral) flashes")

-- a cooldown the game doesn't report: learned by watching
check(db.spells["Faerie Fire"] == nil, "Faerie Fire (no reported cooldown) isn't tracked at first")
CooldownFor("Faerie Fire", 2.5)
check(db.learnedCD["Faerie Fire"] == nil, "a lockout isn't learned as a cooldown")
CooldownFor("Faerie Fire", 6)
check(db.learnedCD["Faerie Fire"] == 6, "a 6 s cooldown is learned")
check(db.spells["Faerie Fire"] ~= nil, "... and the spell is tracked")
FlashCD.UntrackKey("Faerie Fire")
db.learnedCD["Faerie Fire"] = nil
FlashCD.AutoTrack()
CooldownFor("Faerie Fire", 6)
check(db.spells["Faerie Fire"] == nil, "an unticked spell isn't tracked again")
check(db.learnedCD["Faerie Fire"] == 6, "... but its cooldown is still learned")

-- a form version of a spell with its own cooldown
check(db.spells["Demoralizing Roar"] == nil, "a spell without a cooldown isn't tracked out of form")
OVERRIDES[7] = 8
BASE_CD[8] = 10000
EXTRA_NAMES = { [8] = "Demoralizing Roar" }
FORM = 1
fire("UPDATE_SHAPESHIFT_FORM")
check(db.spells["Demoralizing Roar"] ~= nil, "shifting shows the form version's cooldown: tracked")
check(db.overrides["Demoralizing Roar"] == 8, "the form version is remembered")
OVERRIDES[7], FORM = nil, 0
fire("UPDATE_SHAPESHIFT_FORM")
check(FlashCD.SpellRef("Demoralizing Roar") == 8, "out of form it still checks the form version")

-- skipped for no cooldown, gets one later
check(db.skippedNoCD["Maul"] == true, "a spell skipped for having no cooldown is noted")
BASE_CD[9] = 12000
fire("SPELLS_CHANGED")
check(db.spells["Maul"] ~= nil, "it is tracked once the spellbook shows a cooldown")
