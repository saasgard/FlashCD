-- The welcome window: once, on a fresh install, not in combat, not when updating

IN_COMBAT = true                       -- logging in during a fight
local db = LoadAddon()
local w = NAMED.FlashCDWelcome
check(not (w and w:IsShown()), "a fresh install doesn't show the welcome in combat")
IN_COMBAT = false
fire("PLAYER_REGEN_ENABLED")
w = NAMED.FlashCDWelcome
check(w and w:IsShown(), "... it shows when the fight is over")
check(FlashCDDB.welcomed == true, "it is marked as seen (shown once per account)")
check(w.status:GetText():find("tracking 1 of your spells"), "it says how many spells are already tracked")

-- the welcome's buttons (made after the settings window, so the last match)
local function Button(text)
    local found = FindFrames(function(f) return rawget(f, "_text") == text and rawget(f, "_s_OnClick") end)
    return found[#found]
end
local choose = Button("Choose spells")
choose._s_OnClick(choose)
check(not w:IsShown() and NAMED.FlashCDWindow:IsShown(), "Choose spells opens the settings")
NAMED.FlashCDWindow:Hide()

SlashCmdList.FLASHCD("welcome")
check(w:IsShown(), "/fcd welcome shows it again")
local place = Button("Place the flash")
place._s_OnClick(place)
check(not w:IsShown() and FlashCD.IsUnlocked(), "Place the flash starts moving the flash")
FlashCD.SetUnlocked(false)

SlashCmdList.FLASHCD("welcome")
local fl = RecordFlashes()
local test = Button("Test flash")
test._s_OnClick(test)
check(#fl > 0 and w:IsShown(), "Test flash flashes and keeps the welcome open")

fire("PLAYER_LOGOUT")
check(FlashCDDB.welcomed == true, "the seen flag is kept in the account's saved settings")
