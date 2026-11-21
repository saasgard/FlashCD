-- Display groups: migration, adding, assigning, reset, delete

FlashCDCharDB = { size = 50, x = 10, y = 20, glowColor = { r = 0, g = 1, b = 0 },
    spells = { Barkskin = {} }, known = { Barkskin = true, Growl = true } }   -- save from before groups
local db = LoadAddon()
local g1 = db.groups[1]

check(#db.groups == 1 and g1.name == "Main", "the old look becomes one group, Main")
check(g1.size == 50 and g1.x == 10 and g1.glowColor.g == 1, "... with the old size, place and colour")
check(db.size == nil, "the old flat settings are removed")
check(type(g1.color) == "table", "the group gets a colour")

local id2 = FlashCD.AddGroup(g1)
local g2 = FlashCD.GetGroup(id2)
check(#db.groups == 2 and g2.size == 50, "a copied group has the same look")
check(g2.y < g1.y, "... and is placed below")
check(g2.color.r ~= g1.color.r or g2.color.b ~= g1.color.b, "... with a colour of its own")

FlashCD.TrackKey("Growl")
db.spells.Growl.group = id2
check(FlashCD.GroupOf("Growl") == g2 and FlashCD.GroupOf("Barkskin") == g1, "spells flash in their own group")
check(FlashCD.CountInGroup(g2) == 1, "groups count their spells")

local seen = {}
local orig = FlashCD.Flash
FlashCD.Flash = function(k, g) seen[#seen + 1] = k .. "@" .. (g or FlashCD.GroupOf(k)).name return orig(k, g) end
FlashCD.Test()
FlashCD.Flash = orig
table.sort(seen)
check(table.concat(seen, ",") == "Barkskin@Main,Growl@" .. g2.name, "Test flashes in every group")

fire("PLAYER_LOGOUT")
check(#FlashCDDB.template.groups == 2, "new characters get all groups")

g2.size = 30
FlashCD.ResetSettings()
check(#db.groups == 2 and g2.size == 96, "reset keeps groups but resets their look")
check(FlashCD.GroupOf("Growl") == g2, "... and keeps spells in their groups")

FlashCD.DeleteGroup(id2)
check(#db.groups == 1 and FlashCD.GroupOf("Growl") == g1, "deleting a group moves its spells to the first group")
FlashCD.DeleteGroup(g1.id)
check(#db.groups == 1, "the last group can't be deleted")

for _ = 1, 15 do FlashCD.AddGroup() end
check(#db.groups == FlashCD.MAX_GROUPS and FlashCD.AddGroup() == nil, "no more than " .. FlashCD.MAX_GROUPS .. " groups")
