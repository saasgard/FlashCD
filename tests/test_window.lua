-- The settings window: opening, pages, groups sidebar, drag and drop,
-- selecting spells, moving, themes. test_window_wow.lua runs it again in the
-- WoW Forever theme.

FlashCDCharDB = { theme = THEME or "modern" }
TrackGlobals()
local db = LoadAddon()
local w = NAMED.FlashCDWindow

check(w ~= nil, "the window is built")
check(UISpecialFrames[1] == "FlashCDWindow", "Esc closes it")
w:Hide()
SlashCmdList.FLASHCD("")
check(w:IsShown(), "/fcd opens it")
SlashCmdList.FLASHCD("")
check(not w:IsShown(), "/fcd again closes it")
local open = FindFrames(function(f) return rawget(f, "_text") == "Open FlashCD" end)[1]
open._s_OnClick(open)
check(w:IsShown(), "the button in the game's Settings opens it")
IN_COMBAT = true
w:Hide()
FlashCD.OpenOptions(true)
check(not w:IsShown(), "it doesn't open in combat")
IN_COMBAT = false

-- groups in the sidebar; drag a spell onto one
local id2 = FlashCD.AddGroup(); FlashCD.GetGroup(id2).name = "Big"
local id3 = FlashCD.AddGroup(); FlashCD.GetGroup(id3).name = "Small"
FlashCD.TrackKey("Growl")
w:Hide(); w:Show()
local function GroupButton(id)
    return FindFrames(function(f) return rawget(f, "drop") and rawget(f, "id") == id end)[1]
end
local function Rows()
    local r = {}
    for _, f in ipairs(FindFrames(function(f) return rawget(f, "_s_OnMouseUp") and rawget(f, "check") and rawget(f, "key") end)) do
        r[f.key] = f
    end
    return r
end
local rows = Rows()
check(rows.Growl and rows.Barkskin, "tracked spells are in the list")
local big = GroupButton(id2)
rows.Growl._s_OnDragStart(rows.Growl)
big._mouseOver = true
rows.Growl._s_OnDragStop(rows.Growl)
big._mouseOver = false
check(FlashCD.GroupOf("Growl").name == "Big", "dropping a spell on a group moves it there")

-- select: click, Ctrl-click, Shift-click; drag the selection
local function click(k, mod)
    CTRL, SHIFT = mod == "ctrl", mod == "shift"
    rows[k]._s_OnMouseUp(rows[k], "LeftButton")
    CTRL, SHIFT = false, false
end
rows = Rows()
click("Barkskin")
check(rows.Barkskin.sel:IsShown() and not rows.Growl.sel:IsShown(), "click selects one row")
click("Growl", "ctrl")
check(rows.Barkskin.sel:IsShown() and rows.Growl.sel:IsShown(), "Ctrl-click adds a row")
local small = GroupButton(id3)
rows.Barkskin._s_OnDragStart(rows.Barkskin)
small._mouseOver = true
rows.Barkskin._s_OnDragStop(rows.Barkskin)
small._mouseOver = false
check(FlashCD.GroupOf("Barkskin").name == "Small" and FlashCD.GroupOf("Growl").name == "Small",
    "dragging a selected row moves the whole selection")
rows = Rows()
click("Growl")
click("Barkskin", "shift")
check(rows.Barkskin.sel:IsShown() and rows.Growl.sel:IsShown(), "Shift-click selects a range")

-- clicking a group opens its page
big._s_OnClick(big)
check(big.sel:IsShown(), "clicking a group in the sidebar selects it")

-- Move hides the window; Done brings it back
local move = FindFrames(function(f) return rawget(f, "_text") == "Move" and rawget(f, "_s_OnClick") end)
move = move[#move]
move._s_OnClick(move)
check(FlashCD.IsUnlocked() and not w:IsShown(), "Move hides the window while moving")
local done = FindFrames(function(f) return rawget(f, "_text") == "Done" end)[1]
done._s_OnClick(done)
check(not FlashCD.IsUnlocked() and w:IsShown(), "Done locks and brings the window back")

-- themes switch at once
local other = (db.theme == "wow") and "modern" or "wow"
FlashCD.SetTheme(other)
local w2 = NAMED.FlashCDWindow
check(w2 ~= w and w2:IsShown() and not w:IsShown(), "changing the theme rebuilds the open window")
w2:Hide()
FlashCD.SetTheme(db.theme == "wow" and "modern" or "wow")
check(not NAMED.FlashCDWindow:IsShown(), "a closed window stays closed after a theme change")
SlashCmdList.FLASHCD("")
check(NAMED.FlashCDWindow:IsShown(), "the rebuilt window opens normally")

db.window = { w = 1000, h = 700, x = 50, y = 900 }
FlashCD.ResetSettings()
check(db.window.w == 1000, "reset keeps the window's size and place")

CheckOwnGlobals()
