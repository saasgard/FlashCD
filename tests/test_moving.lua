-- Moving groups: the move box, dragging, snapping, nudging, the Done bar

local db = LoadAddon()
local id2 = FlashCD.AddGroup()
local g2 = FlashCD.GetGroup(id2)
g2.size, g2.maxIcons, g2.grow = 40, 4, "right"

FlashCD.ToggleMoveGroup(id2)
local m = NAMED["FlashCDMover" .. id2]
local m1 = NAMED["FlashCDMover" .. db.groups[1].id]
check(m:IsShown() and not m1:IsShown(), "Move shows only that group's box")
check(m.offX == 0 and m.offY == 0, "the box is one icon at the group's position")
local shown = 0
for _, t in ipairs(m.ghosts) do if rawget(t, "_shown") ~= false then shown = shown + 1 end end
check(#m.ghosts == 1, "... with one placeholder icon")

-- drag: the box ends 172 px right and 61 px up of the screen's middle
m.GetCenter = function() return 960 + 172, 540 + 61 end
m._s_OnDragStop(m)
check(g2.x == 175 and g2.y == 50, "dragging snaps to the 25 px grid")
db.snap = false
m._s_OnDragStop(m)
check(g2.x == 172 and g2.y == 61, "without snapping it lands where dropped")

m._s_OnKeyDown(m, "UP")
m._s_OnKeyDown(m, "LEFT")
SHIFT = true; m._s_OnKeyDown(m, "RIGHT"); SHIFT = false
m._s_OnKeyDown(m, "A")
check(g2.x == 181 and g2.y == 62, "arrow keys nudge 1 px, Shift 10 px, other keys do nothing")

-- arrow buttons around the box, also in combat
IN_COMBAT = true
m.arrowUP._s_OnClick(m.arrowUP)
SHIFT = true; m.arrowLEFT._s_OnClick(m.arrowLEFT); SHIFT = false
check(g2.x == 171 and g2.y == 63, "the arrow buttons nudge (1 px, Shift 10 px), also in combat")
IN_COMBAT = false

-- scroll over the box: icon size
m._s_OnMouseWheel(m, 1)
check(g2.size == 42, "scrolling up makes the icon 2 px bigger")
SHIFT = true; m._s_OnMouseWheel(m, -1); m._s_OnMouseWheel(m, -1); SHIFT = false
check(g2.size == 24, "Shift-scroll down 10 px at a time, not below 24 px")
check(m.label:GetText():find("24 px"), "the box shows the size")
for _ = 1, 40 do SHIFT = true; m._s_OnMouseWheel(m, 1) end
SHIFT = false
check(g2.size == 300, "... and not above 300 px")
g2.size = 40
FlashCD.ApplyLayout()

FlashCD.ToggleMoveGroup(db.groups[1].id)
check(m1:IsShown() and not m:IsShown(), "Move on another group switches to it")
FlashCD.ToggleMoveGroup(db.groups[1].id)
check(not FlashCD.IsUnlocked(), "Move again locks")

FlashCD.SetUnlocked(true)
check(m:IsShown() and m1:IsShown(), "Unlock all shows every group")
FlashCD.SetUnlocked(false)

FlashCD.ToggleMoveGroup(id2)
FlashCD.DeleteGroup(id2)
check(not FlashCD.IsUnlocked() and not m:IsShown(), "deleting the group being moved locks again")

-- the Done bar
local before = #ALL
SlashCmdList.FLASHCD("unlock")
local bar = FindFrames(function(f) return rawget(f, "title") and rawget(f, "_text") == nil and rawget(f, "_s_OnDragStart") end)
bar = bar[#bar]
check(bar and bar:IsShown(), "unlocking shows the bar at the top")
local done = FindFrames(function(f) return rawget(f, "_text") == "Done" end)[1]
done._s_OnClick(done)
check(not FlashCD.IsUnlocked() and not bar:IsShown(), "Done locks and hides the bar")
