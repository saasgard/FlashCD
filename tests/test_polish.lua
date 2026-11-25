-- Undo, "Flash in" a specific form, reordering groups, the profile list

FORMS = { 5487, 768 }                 -- Bear Form, Cat Form
EXTRA_NAMES = { [5487] = "Bear Form", [768] = "Cat Form" }
local db = LoadAddon()
FlashCD.TrackKey("Growl")
db.spells.Barkskin.sound = "bell"

-- Undo
check(not FlashCD.CanUndo(), "nothing to undo at first")
FlashCD.ApplyPreset("bigsmall", false)
check(#db.groups == 2, "a preset changed the groups")
check(FlashCD.CanUndo(), "... and can be undone")
FlashCD.Undo()
check(#db.groups == 1 and db.groups[1].name == "Main" and db.spells.Barkskin.sound == "bell",
    "Undo puts the groups and spells back")
check(not FlashCD.CanUndo(), "Undo is one step")
FlashCD.ResetToFresh(true)
check(db.spells.Growl == nil, "a fresh start with spells clears them")
FlashCD.Undo()
check(db.spells.Growl ~= nil and db.known.Barkskin, "Undo brings the spells and what was seen back")
local data = FlashCD.ParseExport(FlashCD.ExportString({ look = true }))
local size = db.groups[1].size
data.settings.groups[1].size = 33
FlashCD.ApplyProfile(data, false)
FlashCD.Undo()
check(db.groups[1].size == size, "an import can be undone")

-- Flash in: any time, any form, one form
local fl = RecordFlashes()
check(#FlashCD.Forms() == 2 and FlashCD.Forms()[2].name == "Cat Form", "your forms are listed by name")
db.spells.Barkskin.formOnly = 768
FORM = 1
local n = #fl
CooldownFor("Barkskin", 40)
check(#fl == n and FlashCD.log[1].text:find("not in Cat Form"), "'only Cat Form' doesn't flash in Bear Form, and says why")
FORM = 2
CooldownFor("Barkskin", 40)
check(#fl == n + 1, "... and flashes in Cat Form")
db.spells.Barkskin.formOnly = true
FORM = 1
CooldownFor("Barkskin", 40)
check(#fl == n + 2, "'any form' flashes in Bear Form (spells saved before keep working)")
FORM = 0
db.spells.Barkskin.formOnly = nil

-- reorder groups
local id2 = FlashCD.AddGroup()
local first = db.groups[1].id
db.spells.Growl.group = id2
check(FlashCD.MoveGroup(id2, -1) and db.groups[1].id == id2, "a group moves up in the list")
check(FlashCD.GroupOf("Barkskin").id == first and FlashCD.GroupOf("Growl").id == id2,
    "spells stay in their groups when the order changes")
check(not FlashCD.MoveGroup(id2, -1), "the first group can't move further up")

-- profiles: this character by name, saved copies
local list = FlashCD.ProfileList()
check(list[1].kind == "me" and list[1].label == "Tester - Forever (this character)", "this character's profile is listed by name, first")
check(not FlashCD.LoadProfile(list[1].key), "loading this character's own profile does nothing")
local ok, err = FlashCD.SaveProfileCopy("   ")
check(not ok and err, "a copy needs a name")
db.groups[2].size = 77
check(FlashCD.SaveProfileCopy("Raid setup"), "this character's settings can be saved as a copy")
list = FlashCD.ProfileList()
check(list[#list].key == "copy:Raid setup" and list[#list].label == "Raid setup", "the copy is in the list, by its name")
db.groups[2].size = 40
FlashCD.LoadProfile("copy:Raid setup", false)
check(db.groups[2].size == 77, "loading the copy puts its settings back")
check(FlashCD.DeleteProfileCopy("Raid setup") and #FlashCD.ProfileList() == 1, "a copy can be deleted")

-- the window shows it all
SlashCmdList.FLASHCD("")
check(_G.FlashCDWindow:IsShown(), "the window opens with the new parts")

-- loading a profile puts spells back in its groups, also without loading the spells
FlashCD.ResetToFresh(false)
local small = FlashCD.AddGroup(); FlashCD.GetGroup(small).name = "Small"
db.spells.Growl.group = small                 -- Growl small, Barkskin in Main
FlashCD.SaveProfileCopy("Magic")
FlashCD.ApplyPreset("bold", false)            -- one group: everything in it
check(#db.groups == 1, "a preset put everything in one group")
FlashCD.LoadProfile("copy:Magic", false)      -- without "also load tracked spells"
check(#db.groups == 2 and FlashCD.GroupOf("Growl").name == "Small" and FlashCD.GroupOf("Barkskin").name == "Main",
    "loading a profile puts each spell back in the group it had there")
check(FlashCD.CountInGroup(FlashCD.GetGroup(small)) == 1, "... so the sidebar counts are right")
-- a positions-only import doesn't move spells between groups
db.spells.Barkskin.group = small
FlashCD.ApplyProfile(FlashCD.ParseExport(FlashCD.ExportString({ position = true })), false)
check(FlashCD.GroupOf("Barkskin").name == "Small", "a positions-only import leaves spells in their groups")
