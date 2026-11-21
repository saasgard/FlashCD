-- With the game's controller interface on, FlashCD must not open the game's
-- shared windows (that blocks the controller code: ADDON_ACTION_FORBIDDEN)

Enum.InputDeviceInterfaceType = { KeyboardMouse = 0, Gamepad = 1 }
C_InputInterfaceStyle = { GetCurrentStyle = function() return 1 end }
local pickerOpened = false
ColorPickerFrame.SetupColorPickerAndShow = function() pickerOpened = true end
TrackGlobals()
local db = LoadAddon()

SlashCmdList.FLASHCD("")
check(NAMED.FlashCDWindow:IsShown(), "the window opens")

-- every colour square: under the controller UI it steps through preset colours
local swatches = FindFrames(function(f) return rawget(f, "_s_OnClick") and rawget(f, "Refresh") and rawget(f, "_s_OnEnter") and not rawget(f, "_text") end)
local before = db.groups[1].color.r .. db.groups[1].color.g
for _, s in ipairs(swatches) do s._s_OnClick(s, "LeftButton") end
check(not pickerOpened, "the game's colour picker is never opened")

CheckOwnGlobals()
