-- FlashCD - Minimap.lua
-- A minimap button (drag it around the minimap's edge) and the addon
-- compartment entry. Left-click: options. Right-click: test flash.

local ADDON, ns = ...
local FlashCD = ns.FlashCD

local button

local function OnClick(mouse)
    if mouse == "RightButton" then
        FlashCD.Test()
    elseif FlashCD.OpenOptions then
        FlashCD.OpenOptions()
    end
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("FlashCD")
    GameTooltip:AddLine("Left-click: options", 1, 1, 1)
    GameTooltip:AddLine("Right-click: test flash", 1, 1, 1)
    if owner == button then
        GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

local function Place()
    local angle = math.rad(FlashCD.db.minimap.angle or 215)
    local r = ((Minimap:GetWidth() or 140) / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    FlashCD.db.minimap.angle = math.deg((math.atan2 or math.atan)(cy - my, cx - mx)) % 360
    Place()
end

local function Build()
    button = CreateFrame("Button", "FlashCDMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\AddOns\\FlashCD\\Media\\Icon")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, mouse) OnClick(mouse) end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", DragUpdate)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function FlashCD.UpdateMinimapButton()
    if not Minimap then return end
    if not button then Build() end
    local m = FlashCD.db.minimap
    if type(m) ~= "table" then
        m = { hide = false, angle = 215 }
        FlashCD.db.minimap = m
    end
    button:SetShown(not m.hide)
    Place()
end

FlashCD.InitMinimap = FlashCD.UpdateMinimapButton

-- Addon compartment (the addon list button by the minimap), set in the TOC
function FlashCD_OnAddonCompartmentClick(_, mouse)
    OnClick(mouse)
end

function FlashCD_OnAddonCompartmentEnter(_, owner)
    ShowTooltip(owner)
end

function FlashCD_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
