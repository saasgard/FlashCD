-- Logging in, auto-tracking, flashing, settings and slash commands

FlashCDDB = { spells = { [5229] = true, Barkskin = true }, size = 80 }   -- first-version save
EXTRA_NAMES = { [5229] = "Enrage" }
TrackGlobals()
local db = LoadAddon()

check(db.spells.Barkskin ~= nil and db.spells.Enrage ~= nil, "old account-wide save moves to the character, IDs become names")
check(db.groups[1].size == 80, "old look becomes group 1")
check(FlashCDDB.spells == nil, "account table keeps only the template")
check(db.spells.Growl == nil, "a spell without a cooldown isn't auto-tracked")

local fl = RecordFlashes()
CooldownFor("Barkskin", 40)
check(fl[1] == "Barkskin", "a real cooldown flashes when it ends")

db.sound = "raid"
CooldownFor("Barkskin", 40)
check(SOUNDS_PLAYED[#SOUNDS_PLAYED] == 8959, "the chosen sound plays")

db.spells.Barkskin.muted = true
local n = #fl
CooldownFor("Barkskin", 40)
check(#fl == n, "a muted spell doesn't flash")
db.spells.Barkskin.muted = nil

db.combatOnly = true
CooldownFor("Barkskin", 40)
check(#fl == n, "'only in combat' skips flashes out of combat")
IN_COMBAT = true
CooldownFor("Barkskin", 40)
check(#fl == n + 1, "... and flashes in combat")
IN_COMBAT, db.combatOnly = false, false

db.groups[1].size = 200
db.spells.Barkskin.sound = "bell"
SlashCmdList.FLASHCD("reset")
check(db.groups[1].size == 96, "/fcd reset puts the look back to default")
check(db.spells.Barkskin and db.spells.Barkskin.sound == "bell", "... and keeps tracked spells and their own settings")

fire("PLAYER_LOGOUT")
check(FlashCDDB.template and FlashCDDB.template.groups and #FlashCDDB.template.groups == 1,
    "logging out saves the settings for new characters")

SlashCmdList.FLASHCD("unlock")
check(FlashCD.IsUnlocked(), "/fcd unlock unlocks")
SlashCmdList.FLASHCD("unlock")
check(not FlashCD.IsUnlocked(), "/fcd unlock again locks")
SlashCmdList.FLASHCD("minimap")
check(db.minimap.hide == true, "/fcd minimap hides the minimap button")
SlashCmdList.FLASHCD("test")
SlashCmdList.FLASHCD("spell bark")
check(PRINTED and PRINTED[#PRINTED]:find("tracked"), "/fcd spell prints what FlashCD sees")

CheckOwnGlobals()
