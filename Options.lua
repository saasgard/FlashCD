-- FlashCD - Options.lua
-- The FlashCD window (its own window, not a page in the game's Settings):
--   sidebar          - the pages and the list of groups (drop spells on a group)
--   group page       - one group: name, move, its look, preview and position
--   Spells & items   - one list: tick to track; each tracked row has its own
--                      group, mute, sound and glow colour
--   Alerts & moving  - sound, filters, minimap button, unlock all, grid, reset
-- The game's Settings get a small page with a button that opens the window.

local ADDON, ns = ...
local FlashCD = ns.FlashCD

local ROW_H = 30
local LIST_W, LIST_H = 576, 262

local panel, category
local spellList, searchBox, preview
local refreshers = {}            -- widgets with :Refresh()
local view = { show = "all", status = "all", sort = "name" }
local spellTabs = {}             -- spellbook tab names seen in the last scan

local function DB() return FlashCD.db end

-- The group being edited on the Appearance and Layout pages
local editGroup
local function G() return FlashCD.GetGroup(editGroup) end

---------------------------------------------------------------------------
-- Widgets, in one of two themes (the "theme" setting, applied on /reload):
--   modern - flat dark controls with gold accents
--   wow    - the game's own look: dialog border, red buttons, gold checkboxes
-- Either way they are FlashCD's own frames with plain textures: none of the
-- game's widget templates or menus are used, so nothing shared with the
-- game's UI is touched (that also keeps the controller interface free of taint).
---------------------------------------------------------------------------
local GOLD = { 1, 0.82, 0 }
local FIELD_BG = { 0, 0, 0, 0.45 }
local EDGE = { 1, 1, 1, 0.14 }

FlashCD.THEMES = {
    { key = "modern", label = "Modern" },
    { key = "wow",    label = "WoW Forever" },
}
local function WoW() return FlashCD.db and FlashCD.db.theme == "wow" end

local BACKDROPS = {
    window = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    },
    panel = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    slider = {
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    },
}

-- Give a frame one of the game's backdrops (WoW theme)
local function Backdrop(f, kind, r, g, b, a)
    if not f.SetBackdrop and BackdropTemplateMixin and Mixin then
        Mixin(f, BackdropTemplateMixin)
        f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged)
    end
    if not f.SetBackdrop then return end
    f:SetBackdrop(BACKDROPS[kind])
    if r then f:SetBackdropColor(r, g, b, a or 1) end
    if kind == "panel" and f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1) end
end

local function Track(w)
    refreshers[#refreshers + 1] = w
    return w
end

-- Tooltip with a title and a wrapped line of help
local function Tip(frame, title, text)
    if not frame or not text then return frame end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

-- A 1-pixel border around a frame; returns its four textures
local function AddBorder(f, c, layer)
    c = c or EDGE
    local t = {}
    for i, pts in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }) do
        local x = f:CreateTexture(nil, layer or "BORDER")
        x:SetPoint(pts[1])
        x:SetPoint(pts[2])
        if pts[3] then x:SetWidth(pts[3]) else x:SetHeight(pts[4]) end
        x:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t[i] = x
    end
    f.SetBorderColor = function(_, r, g, b, a)
        for _, x in ipairs(t) do x:SetColorTexture(r, g, b, a or 1) end
    end
    return t
end

local function Fill(f, c, layer)
    local t = f:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

-- Flat button. Secondary by default; MakeButton(..., true) or :SetPrimary()
-- gives the gold one used for main actions.
local function MakeButton(parent, text, w, h, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 100, h or 22)
    if WoW() then
        -- the game's red panel button, from its textures
        for _, st in ipairs({ { "SetNormalTexture", "Up" }, { "SetPushedTexture", "Down" },
                              { "SetDisabledTexture", "Disabled" }, { "SetHighlightTexture", "Highlight" } }) do
            b[st[1]](b, "Interface\\Buttons\\UI-Panel-Button-" .. st[2])
        end
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
            local t = b[get] and b[get](b)
            if t and t.SetTexCoord then t:SetTexCoord(0, 0.625, 0, 0.6875) end
        end
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER")
        b:SetFontString(fs)
        if b.SetHighlightFontObject and GameFontHighlightSmall then b:SetHighlightFontObject(GameFontHighlightSmall) end
        if b.SetDisabledFontObject and GameFontDisableSmall then b:SetDisabledFontObject(GameFontDisableSmall) end
        b.SetPrimary = function(self) return self end
        b:SetText(text)
        return b
    end
    b.bg = Fill(b, { 1, 1, 1, 0.08 })
    AddBorder(b, { 1, 1, 1, 0.12 })
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    if b.SetDisabledFontObject and GameFontDisableSmall then b:SetDisabledFontObject(GameFontDisableSmall) end
    b.SetPrimary = function(self)
        self.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22)
        self:SetBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.6)
        if self.SetNormalFontObject and GameFontNormalSmall then self:SetNormalFontObject(GameFontNormalSmall) end
        fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        return self
    end
    b:SetText(text)
    if primary then b:SetPrimary() end
    return b
end
local MakeFlatButton = MakeButton

-- Flat checkbox; the label is part of the click area
local function MakeCheck(parent, label, get, set)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(22, 22)
    if WoW() then
        c:SetSize(24, 24)
        c:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        c:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        c:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
        fs:SetText(label)
        c.label = fs
        local lw = fs:GetStringWidth()
        if type(lw) == "number" and lw > 0 then c:SetHitRectInsets(0, -(lw + 6), 0, 0) end
        c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        c.Refresh = function(self) self:SetChecked(get() and true or false) end
        return c
    end
    local box = CreateFrame("Frame", nil, c)
    box:SetSize(16, 16)
    box:SetPoint("CENTER")
    Fill(box, FIELD_BG)
    AddBorder(box, { 1, 1, 1, 0.25 })
    local mark = c:CreateTexture(nil, "OVERLAY")
    mark:SetSize(10, 10)
    mark:SetPoint("CENTER")
    mark:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    c:SetCheckedTexture(mark)
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(16, 16)
    hl:SetPoint("CENTER")
    hl:SetColorTexture(1, 1, 1, 0.12)
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", c, "RIGHT", 4, 0)
    fs:SetText(label)
    c.label = fs
    local lw = fs:GetStringWidth()
    if type(lw) == "number" and lw > 0 then c:SetHitRectInsets(0, -(lw + 8), 0, 0) end
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    c.Refresh = function(self) self:SetChecked(get() and true or false) end
    return c
end

-- Slider with a gold fill up to the handle. It stretches when the caller
-- anchors its left and right edges.
local function MakeSlider(parent, label, minV, maxV, step, fmt, get, set, w)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(w or 220, 14)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouse(true)
    s:EnableMouseWheel(true)

    if WoW() then
        s:SetHeight(17)
        Backdrop(s, "slider")
        s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local th = s:GetThumbTexture()
        if th then th:SetSize(32, 32) end
    else
        local track = s:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
        track:SetHeight(4)
        track:SetColorTexture(1, 1, 1, 0.14)

        local thumb = s:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(8, 14)
        thumb:SetColorTexture(0.92, 0.92, 0.92, 1)
        s:SetThumbTexture(thumb)

        local fill = s:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("LEFT", track, "LEFT")
        fill:SetPoint("RIGHT", thumb, "CENTER")
        fill:SetHeight(4)
        fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
    end

    local title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 3)
    title:SetText(label)

    local val = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 3)

    s.updating = false
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        val:SetText(string.format(fmt, v))
        if not self.updating then set(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * step)
    end)
    s.Refresh = function(self)
        self.updating = true
        local v = get()
        self:SetValue(v)
        val:SetText(string.format(fmt, v))
        self.updating = false
    end
    return s
end

-- Background and border of a text field or dropdown button
local function FieldLook(f)
    if WoW() then
        Backdrop(f, "panel", 0, 0, 0, 0.75)
        f.SetBorderColor = function(self, r, g, b)
            if not self.SetBackdropBorderColor then return end
            -- gold while typing, grey otherwise
            if r == EDGE[1] and g == EDGE[2] then self:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
            else self:SetBackdropBorderColor(r, g, b, 1) end
        end
    else
        Fill(f, FIELD_BG)
        AddBorder(f)
    end
end

-- Text field; `font` is a font object name (default GameFontHighlight)
local function MakeEditBox(parent, w, h, font)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w or 150, h or 22)
    e:SetAutoFocus(false)
    e:SetFontObject(_G[font or "GameFontHighlight"] or GameFontHighlight)
    e:SetTextInsets(7, 7, 0, 0)
    FieldLook(e)
    e:HookScript("OnEditFocusGained", function(self) self:SetBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7) end)
    e:HookScript("OnEditFocusLost", function(self) self:SetBorderColor(EDGE[1], EDGE[2], EDGE[3], EDGE[4]) end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- grey text shown while empty
    e.SetPlaceholder = function(self, text)
        local ph = self:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        ph:SetPoint("LEFT", 8, 0)
        ph:SetText(text)
        local function upd() ph:SetShown((self:GetText() or "") == "" and not self:HasFocus()) end
        self:HookScript("OnTextChanged", upd)
        self:HookScript("OnEditFocusGained", upd)
        self:HookScript("OnEditFocusLost", upd)
        upd()
    end
    return e
end

-- Scroll area with a slim scrollbar on the right. Returns the scroll frame;
-- put the content in it with :SetScrollChild.
local function MakeScroll(parent, step)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -14, 4)

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT", -4, -4)
    bar:SetPoint("BOTTOMRIGHT", -4, 4)
    bar:SetWidth(6)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.06)
    if WoW() then
        bar:SetWidth(16)
        scroll:SetPoint("BOTTOMRIGHT", -24, 4)
        bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
        local th = bar:GetThumbTexture()
        if th then th:SetSize(16, 24) end
    else
        local thumb = bar:CreateTexture(nil, "OVERLAY")
        thumb:SetSize(6, 40)
        thumb:SetColorTexture(1, 1, 1, 0.3)
        bar:SetThumbTexture(thumb)
    end
    bar:Hide()

    bar:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
    scroll:SetScript("OnScrollRangeChanged", function(_, _, yr)
        yr = yr or 0
        bar:SetMinMaxValues(0, yr)
        bar:SetShown(yr > 0)
    end)
    scroll:SetScript("OnVerticalScroll", function(_, off) bar:SetValue(off) end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange() or 0
        local v = math.max(0, math.min(max, self:GetVerticalScroll() - delta * (step or 30) * 3))
        self:SetVerticalScroll(v)
        bar:SetValue(v)
    end)
    return scroll
end

---------------------------------------------------------------------------
-- Dropdowns, with a small menu of FlashCD's own (not the game's menus)
---------------------------------------------------------------------------
-- `list` is a table of {key, label} or a function returning one
local function ListOf(list)
    if type(list) == "function" then return list() end
    return list
end

local menu, catcher

local function CloseMenu()
    if menu then menu:Hide() end
end

local function OpenMenu(owner, list, get, onPick)
    if not menu then
        -- a click anywhere outside the menu closes it
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        catcher:SetScript("OnClick", CloseMenu)
        catcher:Hide()

        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel((catcher:GetFrameLevel() or 0) + 10)
        menu:EnableMouse(true)
        if WoW() then
            Backdrop(menu, "panel", 0.05, 0.05, 0.05, 0.97)
        else
            Fill(menu, { 0.1, 0.1, 0.11, 1 })
            AddBorder(menu, { 1, 1, 1, 0.2 })
        end
        menu.items = {}
        menu:SetScript("OnHide", function() catcher:Hide() menu.owner = nil end)
        menu:Hide()
    end
    if menu:IsShown() and menu.owner == owner then CloseMenu() return end

    local items = ListOf(list)
    local w = owner:GetWidth()
    if type(w) ~= "number" or w < 80 then w = 160 end
    local cur = get()
    for i, e in ipairs(items) do
        local it = menu.items[i]
        if not it then
            it = CreateFrame("Button", nil, menu)
            it:SetHeight(20)
            local hl = it:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.1)
            it.mark = it:CreateTexture(nil, "ARTWORK")
            it.mark:SetSize(6, 6)
            it.mark:SetPoint("LEFT", 8, 0)
            it.mark:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
            it.text = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            it.text:SetPoint("LEFT", 20, 0)
            it.text:SetPoint("RIGHT", -6, 0)
            it.text:SetJustifyH("LEFT")
            it.text:SetWordWrap(false)
            menu.items[i] = it
        end
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
        it:SetPoint("RIGHT", menu, "RIGHT", -2, 0)
        it.text:SetText(e.label)
        it.mark:SetShown(e.key == cur)
        it:SetScript("OnClick", function() CloseMenu() onPick(e.key) end)
        it:Show()
    end
    for i = #items + 1, #menu.items do menu.items[i]:Hide() end
    menu:SetSize(w, #items * 20 + 4)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu.owner = owner
    catcher:Show()
    menu:Show()
end

-- Dropdown of {key, label} choices. With a label, the label sits above it.
-- Position the returned frame by its TOPLEFT; anchor its right edge too to
-- let it stretch.
local function MakeDropdown(parent, label, list, get, set, w)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w or 220, label and 40 or 22)

    local b = CreateFrame("Button", nil, holder)
    b:SetHeight(22)
    if label then
        local title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 0, 0)
        title:SetText(label)
        b:SetPoint("TOPLEFT", 0, -16)
        b:SetPoint("TOPRIGHT", 0, -16)
    else
        b:SetPoint("TOPLEFT")
        b:SetPoint("TOPRIGHT")
    end
    FieldLook(b)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    local arrow = b:CreateTexture(nil, "ARTWORK")
    if WoW() then
        arrow:SetSize(20, 20)
        arrow:SetPoint("RIGHT", -2, 0)
        arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    else
        arrow:SetSize(12, 12)
        arrow:SetPoint("RIGHT", -6, 0)
        arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
        arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    end
    local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    holder.button = b

    holder.Refresh = function()
        local cur = get()
        for _, e in ipairs(ListOf(list)) do
            if e.key == cur then text:SetText(e.label) return end
        end
        text:SetText("-")
    end
    b:SetScript("OnClick", function()
        OpenMenu(b, list, get, function(v) set(v) holder:Refresh() end)
    end)
    holder.SetTip = function(self, title, tip)
        Tip(b, title, tip)
        return self
    end
    return holder
end

---------------------------------------------------------------------------
-- Colours
---------------------------------------------------------------------------
-- Whether the game's controller (gamepad) interface is on. Under it the game's
-- gamepad code takes shared windows that open into its focus and calls the
-- protected SetPreferredGamepadInteractTarget; if addon code opened them, that
-- call is blocked (ADDON_ACTION_FORBIDDEN). So under the controller interface
-- FlashCD doesn't open the game's colour picker.
local function GamepadUI()
    local styles, api = Enum and Enum.InputDeviceInterfaceType, C_InputInterfaceStyle
    if not (styles and api and api.GetCurrentStyle) then return false end
    local ok, style = pcall(api.GetCurrentStyle)
    return ok and style == styles.Gamepad
end

-- Colours the swatch steps through under the controller interface
local PRESET_COLOURS = {
    { r = 1,    g = 0.82, b = 0 },     -- gold
    { r = 1,    g = 1,    b = 1 },     -- white
    { r = 1,    g = 0.2,  b = 0.2 },   -- red
    { r = 1,    g = 0.5,  b = 0 },     -- orange
    { r = 0.3,  g = 1,    b = 0.3 },   -- green
    { r = 0.2,  g = 0.9,  b = 1 },     -- cyan
    { r = 0.3,  g = 0.5,  b = 1 },     -- blue
    { r = 0.7,  g = 0.3,  b = 1 },     -- purple
    { r = 1,    g = 0.4,  b = 0.8 },   -- pink
}

local function NextPreset(c)
    local best, bestD = 0, math.huge
    for i, p in ipairs(PRESET_COLOURS) do
        local d = (p.r - c.r) ^ 2 + (p.g - c.g) ^ 2 + (p.b - c.b) ^ 2
        if d < bestD then best, bestD = i, d end
    end
    return PRESET_COLOURS[best % #PRESET_COLOURS + 1]
end

local function OpenColorPicker(c, apply)
    local r, g, b = c.r, c.g, c.b
    local function changed()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        apply(nr, ng, nb)
    end
    local function cancel() apply(r, g, b) end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = changed, cancelFunc = cancel,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = changed
        ColorPickerFrame.cancelFunc = cancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Show()
    end
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
end

-- Small colour square; getColor() returns {r,g,b}, setColor(r,g,b).
-- With onReset, right-click puts the colour back to its default.
local function MakeSwatch(parent, getColor, setColor, onReset, tipTitle)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    AddBorder(b, { 1, 1, 1, 0.35 })
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b.Refresh = function(self)
        local c = getColor()
        fill:SetColorTexture(c.r, c.g, c.b, 1)
    end
    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            if onReset then onReset() self:Refresh() end
            return
        end
        if GamepadUI() then
            local p = NextPreset(getColor())
            setColor(p.r, p.g, p.b)
            self:Refresh()
            return
        end
        OpenColorPicker(getColor(), function(r, g, bl)
            setColor(r, g, bl)
            self:Refresh()
        end)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tipTitle or "Glow colour", 1, 1, 1)
        GameTooltip:AddLine(GamepadUI() and "Click: next colour" or "Click: pick a colour")
        if onReset then GameTooltip:AddLine("Right-click: use the default colour") end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- A plain dark frame with a thin border (the window, dialogs, the moving bar)
local function MakeBackdropFrame(parent, name)
    local f = CreateFrame("Frame", name, parent)
    if WoW() then
        Backdrop(f, "window", 1, 1, 1, 1)
        -- the game's dark dialog background is see-through: put a solid layer under it
        local solid = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        solid:SetPoint("TOPLEFT", 10, -10)
        solid:SetPoint("BOTTOMRIGHT", -10, 10)
        solid:SetColorTexture(0.04, 0.04, 0.05, 1)
    else
        Fill(f, { 0.06, 0.06, 0.07, 1 })
        AddBorder(f, { 1, 1, 1, 0.16 })
    end
    return f
end

-- Space between the window's edge and its contents (the WoW border is wide)
local function WindowPad() return WoW() and 12 or 6 end

-- A shaded box with a heading. `col` is "L" or "R" (half the width) or
-- "F" (full width); it stretches with its parent.
local function MakeSection(parent, title, col, y, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(h)
    if col == "R" then
        f:SetPoint("TOPLEFT", parent, "TOP", 6, y)
        f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, y)
    elseif col == "L" then
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
        f:SetPoint("TOPRIGHT", parent, "TOP", -6, y)
    else
        f:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
        f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, y)
    end
    if WoW() then
        Backdrop(f, "panel", 0, 0, 0, 0.45)
    else
        Fill(f, { 1, 1, 1, 0.035 })
        local line = f:CreateTexture(nil, "BORDER")
        line:SetPoint("TOPLEFT")
        line:SetPoint("TOPRIGHT")
        line:SetHeight(1)
        line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
    end
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -8)
    t:SetText(title)
    return f
end

-- Place a control inside a section: "F" full width, "L"/"R" the left or
-- right half; `x` is the left inset (default 16)
local function Place(w, parent, col, y, x)
    w:ClearAllPoints()
    x = x or 16
    if col == "R" then
        w:SetPoint("TOPLEFT", parent, "TOP", x, y)
        w:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    elseif col == "L" then
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        w:SetPoint("RIGHT", parent, "CENTER", -16, 0)
    else
        w:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        w:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    end
    return w
end

---------------------------------------------------------------------------
-- Spellbook and item scanning
---------------------------------------------------------------------------
function FlashCD.HasCooldown(id, name)
    local db = FlashCD.db
    if name and db and db.learnedCD[name] then return true end
    -- a form version (e.g. feral) may have the cooldown
    local o = name and db and db.overrides[name]
    if o and o ~= id and FlashCD.HasCooldown(o) then return true end
    if not GetSpellBaseCooldown then return true end
    local ok, ms = pcall(GetSpellBaseCooldown, id)
    if not ok or type(ms) ~= "number" then return true end
    if ms > 1500 then return true end
    -- spells with charges have their cooldown on the charges
    if C_Spell and C_Spell.GetSpellCharges then
        local ok2, ch = pcall(C_Spell.GetSpellCharges, id)
        if ok2 and type(ch) == "table" and ch.maxCharges and ch.maxCharges > 1 then return true end
    end
    return false
end

local function SortByName(list)
    table.sort(list, function(a, b) return tostring(a.name or "") < tostring(b.name or "") end)
    return list
end

function FlashCD.ScanSpellbook()
    -- one entry per spell name; a later (higher) rank replaces an earlier one
    local out, byName = {}, {}
    local function add(id, name, icon, tab)
        if not id then return end
        name = name or FlashCD.GetSpellName(id)
        if not name then return end
        local entry = byName[name]
        if not entry then
            entry = { name = name, key = name, tab = tab }
            byName[name] = entry
            out[#out + 1] = entry
        end
        entry.id = id
        entry.icon = icon or FlashCD.GetSpellIcon(id)
    end

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
        local bank = Enum.SpellBookSpellBank.Player
        local spellType = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if line and not line.shouldHide and line.numSpellBookItems then
                local first = (line.itemIndexOffset or 0) + 1
                for j = first, first + line.numSpellBookItems - 1 do
                    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, j, bank)
                    if ok and info and info.spellID and not info.isPassive
                        and (spellType == nil or info.itemType == spellType) then
                        add(info.spellID, info.name, info.iconID, line.name)
                    end
                end
            end
        end
    elseif GetNumSpellTabs then
        for t = 1, GetNumSpellTabs() do
            local tabName, _, offset, num = GetSpellTabInfo(t)
            for j = offset + 1, offset + num do
                local kind, id = GetSpellBookItemInfo(j, BOOKTYPE_SPELL or "spell")
                if kind == "SPELL" and id and not (IsPassiveSpell and IsPassiveSpell(id)) then
                    add(id, nil, nil, tabName)
                end
            end
        end
    end

    for _, e in ipairs(out) do FlashCD.RememberSpell(e.name, e.id) end
    return SortByName(out)
end

-- Equipped and bagged items that have a "Use:" effect (trinkets, potions...)
function FlashCD.ScanItems()
    local out, seen = {}, {}
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local function add(itemID, name, icon)
        if not itemID or seen[itemID] or not getSpell then return end
        local ok, spellName = pcall(getSpell, itemID)
        if not ok or not spellName then return end
        seen[itemID] = true
        local key = "item:" .. itemID
        out[#out + 1] = {
            key = key,
            itemID = itemID,
            name = name or FlashCD.KeyName(key),
            icon = icon or FlashCD.KeyIcon(key),
        }
    end

    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then add(id, nil, GetInventoryItemTexture("player", slot)) end
    end

    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if numSlots then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, numSlots(bag) or 0 do
                if C_Container and C_Container.GetContainerItemInfo then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.itemID then add(info.itemID, info.itemName, info.iconFileID) end
                elseif GetContainerItemID then
                    add(GetContainerItemID(bag, slot))
                end
            end
        end
    end

    return SortByName(out)
end

---------------------------------------------------------------------------
-- The spell list: one row per spell or item, tick to track
---------------------------------------------------------------------------
local function Entry(key)
    local e = key and DB().spells[key]
    return type(e) == "table" and e or nil
end

local function FormatCD(sec)
    if not sec then return "" end
    if sec < 60 then return string.format("%ds", sec) end
    if sec < 3600 then
        local m = sec / 60
        return (m == math.floor(m)) and string.format("%dm", m) or string.format("%.1fm", m)
    end
    return string.format("%.1fh", sec / 3600)
end

local SOUND_CHOICES = { { key = nil, label = "Default sound" } }
for _, s in ipairs(FlashCD.SOUNDS) do SOUND_CHOICES[#SOUND_CHOICES + 1] = s end

local RefreshList   -- defined below
local StartDrag, EndDrag   -- dragging a spell onto a group, defined below

-- Selected rows: [key] = true. Click selects one row, Ctrl-click adds or
-- removes a row, Shift-click selects every row from the last click.
local selected = {}
local lastClick            -- index (in the shown rows) of the last plain/Ctrl click
local OnSelectionChanged   -- set by the detail panel
local shownRows = {}

local MARK_MUTE  = "Interface\\Common\\VoiceChat-Muted"
local MARK_SOUND = "Interface\\Common\\VoiceChat-Speaker"

local function ClickRow(index, key)
    if IsControlKeyDown and IsControlKeyDown() then
        selected[key] = (not selected[key]) or nil
        lastClick = index
    elseif IsShiftKeyDown and IsShiftKeyDown() and lastClick and shownRows[lastClick] then
        wipe(selected)
        local a, b = math.min(lastClick, index), math.max(lastClick, index)
        for i = a, b do selected[shownRows[i].key] = true end
    else
        wipe(selected)
        selected[key] = true
        lastClick = index
    end
    if spellList then spellList:UpdateSelection() end
    if OnSelectionChanged then OnSelectionChanged() end
end

-- The selected keys, in list order (only rows the list shows)
local function SelectedKeys()
    local keys = {}
    for _, d in ipairs(shownRows) do
        if selected[d.key] then keys[#keys + 1] = d.key end
    end
    return keys
end

local function MakeSpellList(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(LIST_W, LIST_H)

    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)

    -- column headings
    local function Head(text, point, x)
        local fs = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("BOTTOM" .. point, box, "TOP" .. point, x, 3)
        fs:SetText(text)
    end
    Head("Spell", "LEFT", 62)
    Head("Group", "RIGHT", -34)
    Head("CD", "RIGHT", -136)

    local scroll = MakeScroll(box, ROW_H)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(LIST_W - 30, 1)
    scroll:SetScrollChild(content)
    -- rows follow the list's width when the window is resized
    scroll:SetScript("OnSizeChanged", function(self, w)
        if type(w) == "number" and w > 0 then content:SetWidth(w) end
    end)

    local empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")

    box.rows = {}

    local function GetRow(i)
        local r = box.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, content)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("RIGHT", content, "RIGHT")
        r:EnableMouse(true)

        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
        r.sel = r:CreateTexture(nil, "BORDER")
        r.sel:SetAllPoints()
        r.sel:SetColorTexture(1, 0.82, 0, 0.14)
        r.sel:Hide()
        r.bar = r:CreateTexture(nil, "ARTWORK")
        r.bar:SetPoint("TOPLEFT")
        r.bar:SetPoint("BOTTOMLEFT")
        r.bar:SetWidth(3)
        r.bar:SetColorTexture(1, 0.82, 0, 0.9)
        r.bar:Hide()
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)

        r.check = MakeCheck(r, "",
            function() return DB().spells[r.key] ~= nil end,
            function(v)
                if not r.key then return end
                if v then FlashCD.TrackKey(r.key) else FlashCD.UntrackKey(r.key) end
                RefreshList()
                if FlashCD.OnTrackedChanged then FlashCD.OnTrackedChanged() end
            end)
        r.check:SetPoint("LEFT", 4, 0)

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_H - 6, ROW_H - 6)
        r.icon:SetPoint("LEFT", 32, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- group tag (right), cooldown, then markers for own settings
        r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.tag:SetPoint("RIGHT", -8, 0)
        r.tag:SetWidth(96)
        r.tag:SetJustifyH("LEFT")
        r.tag:SetWordWrap(false)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(8, 8)
        r.dot:SetPoint("RIGHT", r.tag, "LEFT", -5, 0)

        r.cd = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.cd:SetPoint("RIGHT", -126, 0)
        r.cd:SetWidth(40)
        r.cd:SetJustifyH("RIGHT")
        r.cd:SetTextColor(0.65, 0.65, 0.65)

        r.marks = {}
        for m = 1, 3 do
            local t = r:CreateTexture(nil, "ARTWORK")
            t:SetSize(14, 14)
            t:SetPoint("RIGHT", -172 - (m - 1) * 16, 0)
            t:Hide()
            r.marks[m] = t
        end

        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetPoint("LEFT", 62, 0)
        r.text:SetPoint("RIGHT", -176, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)

        r:SetScript("OnMouseUp", function(self, mouse)
            if mouse == "LeftButton" and self.key then ClickRow(self.index, self.key) end
        end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemID and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(self.itemID)
            elseif self.spellID and GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(self.spellID)
            else
                GameTooltip:SetText(self.text:GetText() or "")
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- drag tracked rows (the selection, if this row is in it) onto a group
        r:RegisterForDrag("LeftButton")
        r:SetScript("OnDragStart", function(self)
            if not (self.key and StartDrag) then return end
            local keys = {}
            if selected[self.key] then
                for _, k in ipairs(SelectedKeys()) do
                    if DB().spells[k] ~= nil then keys[#keys + 1] = k end
                end
            elseif DB().spells[self.key] ~= nil then
                keys[1] = self.key
            end
            if #keys > 0 then StartDrag(keys, self.icon:GetTexture()) end
        end)
        r:SetScript("OnDragStop", function() if EndDrag then EndDrag() end end)

        box.rows[i] = r
        return r
    end

    box.UpdateSelection = function(self)
        for _, r in ipairs(self.rows) do
            local on = r.key ~= nil and selected[r.key] == true
            r.sel:SetShown(on)
            r.bar:SetShown(on)
        end
    end

    box.SetData = function(self, data, emptyText)
        local w = scroll:GetWidth()
        if type(w) == "number" and w > 0 then content:SetWidth(w) end
        for i, d in ipairs(data) do
            local r = GetRow(i)
            r.index = i
            r.key = d.key
            r.spellID = d.id
            r.itemID = d.itemID
            r.icon:SetTexture(d.icon or 134400)
            r.icon:SetDesaturated(not d.tracked)
            r.text:SetText(d.name or "?")
            if d.tracked then r.text:SetTextColor(1, 1, 1) else r.text:SetTextColor(0.5, 0.5, 0.5) end
            r.cd:SetText(FormatCD(d.cd))
            r.check:Refresh()

            local e = d.tracked and Entry(d.key)
            if e then
                local g = FlashCD.GroupOf(d.key)
                local c = g.color or { r = 1, g = 0.82, b = 0 }
                r.tag:SetText(g.name)
                r.tag:SetTextColor(c.r, c.g, c.b)
                r.dot:SetColorTexture(c.r, c.g, c.b, 1)
                r.dot:Show()
            else
                r.tag:SetText("")
                r.dot:Hide()
            end

            -- markers: muted, own sound, own glow colour
            local n = 0
            local function Mark(on, tex, colour)
                if not on then return end
                n = n + 1
                local t = r.marks[n]
                if colour then t:SetColorTexture(colour.r, colour.g, colour.b, 1) t:SetSize(10, 10)
                else t:SetTexture(tex) t:SetVertexColor(1, 1, 1) t:SetSize(14, 14) end
                t:Show()
            end
            for m = 1, 3 do r.marks[m]:Hide() end
            if e then
                Mark(e.muted, MARK_MUTE)
                Mark(e.sound ~= nil and not e.muted, MARK_SOUND)
                Mark(e.color ~= nil, nil, e.color)
            end
            r:Show()
        end
        for i = #data + 1, #self.rows do
            self.rows[i]:Hide()
            self.rows[i].key = nil
        end
        content:SetHeight(math.max(1, #data * ROW_H))
        empty:SetText(#data == 0 and (emptyText or "") or "")
        local max = scroll:GetVerticalScrollRange()
        if scroll:GetVerticalScroll() > max then scroll:SetVerticalScroll(max) end
        self:UpdateSelection()
    end

    return box
end

-- Rows for the current view: the spellbook (all or one tab) or items,
-- plus anything tracked that isn't there any more, so it can be unticked
local function BuildRows()
    local db = DB()
    local rows, seen = {}, {}
    local function add(d)
        if seen[d.key] then return end
        seen[d.key] = true
        rows[#rows + 1] = d
    end

    if view.show == "items" then
        for _, d in ipairs(FlashCD.ScanItems()) do add(d) end
        for key in pairs(db.spells) do
            local item = FlashCD.ItemID(key)
            if item then
                add({ key = key, itemID = item, name = tostring(FlashCD.KeyName(key)), icon = FlashCD.KeyIcon(key) })
            end
        end
    else
        wipe(spellTabs)
        local tabSeen = {}
        local wantTab = view.show:match("^tab:(.*)$")
        for _, d in ipairs(FlashCD.ScanSpellbook()) do
            if d.tab and not tabSeen[d.tab] then
                tabSeen[d.tab] = true
                spellTabs[#spellTabs + 1] = d.tab
            end
            if (not wantTab or d.tab == wantTab)
                and (db.spells[d.key] ~= nil or not db.cdOnly or FlashCD.HasCooldown(d.id, d.name)) then
                add(d)
            end
        end
        if wantTab and not tabSeen[wantTab] then view.show = "all" end
        if not wantTab then
            for key in pairs(db.spells) do
                if not FlashCD.ItemID(key) then
                    add({ key = key, id = FlashCD.GetSpellID(key), name = tostring(FlashCD.KeyName(key)), icon = FlashCD.KeyIcon(key) })
                end
            end
        end
    end

    local filter = (searchBox and searchBox:GetText() or ""):lower()
    local out = {}
    for _, d in ipairs(rows) do
        d.tracked = db.spells[d.key] ~= nil
        if not d.itemID then d.cd = FlashCD.CooldownLength(d.key) end
        local nameOk = filter == "" or tostring(d.name or ""):lower():find(filter, 1, true)
        local wantGroup = tonumber(view.status:match("^group:(%d+)$"))
        local statusOk
        if wantGroup then
            statusOk = d.tracked and FlashCD.GroupOf(d.key).id == wantGroup
        else
            statusOk = view.status == "all" or (view.status == "tracked") == d.tracked
        end
        if nameOk and statusOk then out[#out + 1] = d end
    end

    table.sort(out, function(a, b)
        if view.sort == "cooldown" and (a.cd or 0) ~= (b.cd or 0) then
            return (a.cd or 0) > (b.cd or 0)
        elseif view.sort == "tracked" and a.tracked ~= b.tracked then
            return a.tracked
        end
        return tostring(a.name or "") < tostring(b.name or "")
    end)
    return out
end

local refreshing = false
RefreshList = function()
    if not panel or not spellList or refreshing then return end
    refreshing = true   -- building rows must never start another refresh
    local ok, err = pcall(function()
        shownRows = BuildRows()
        local emptyText = view.show == "items" and "No usable items found" or "No matching spells"
        spellList:SetData(shownRows, emptyText)
        -- keep the selection to rows the list shows
        local shown = {}
        for _, d in ipairs(shownRows) do shown[d.key] = true end
        for k in pairs(selected) do if not shown[k] then selected[k] = nil end end
        spellList:UpdateSelection()
        if OnSelectionChanged then OnSelectionChanged() end
    end)
    refreshing = false
    if not ok then error(err, 0) end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local RefreshSidebar    -- set when the sidebar is built
local ShowPage          -- switches the window's page, set in BuildWindow
local RebuildWindow     -- builds the window again (new theme), set below

local function UpdatePreview()
    if not preview then return end
    local g = G()
    local key, any
    for k in pairs(DB().spells) do
        if not any or tostring(k) < tostring(any) then any = k end
        if FlashCD.GroupOf(k) == g and (not key or tostring(k) < tostring(key)) then key = k end
    end
    key = key or any
    if not key and FlashCD.ScanSpellbook then
        local book = FlashCD.ScanSpellbook()
        key = book[1] and book[1].key
    end
    preview:SetShown(key ~= nil)
    if key then preview:Update(key, 64, g) end
end

local function RefreshAll()
    if not panel then return end
    for _, w in ipairs(refreshers) do w:Refresh() end
    if RefreshSidebar then RefreshSidebar() end
    UpdatePreview()
    RefreshList()
end

FlashCD.OnTrackedChanged = function()
    if panel and panel:IsShown() then
        RefreshList()
        if RefreshSidebar then RefreshSidebar() end
    end
end

FlashCD.OnPositionChanged = function()
    if panel then for _, w in ipairs(refreshers) do w:Refresh() end end
end

-- After a display setting changes: move the flashes, redraw the preview
local function Changed()
    FlashCD.ApplyLayout()
    UpdatePreview()
    if RefreshSidebar then RefreshSidebar() end
end

---------------------------------------------------------------------------
-- Setting helpers. `src` picks the settings table: the group being edited
-- (default) or DB for settings that apply to all groups.
---------------------------------------------------------------------------

local function Slider(parent, label, minV, maxV, step, fmt, key, y, tip, src, col)
    local db = src or G
    local s = Track(MakeSlider(parent, label, minV, maxV, step, fmt,
        function() return db()[key] end,
        function(v) db()[key] = v; Changed() end))
    Place(s, parent, col, y)
    Tip(s, label, tip)
    return s
end

local function Check(parent, label, key, y, tip, src, x)
    local db = src or G
    local c = Track(MakeCheck(parent, label,
        function() return db()[key] end,
        function(v) db()[key] = v; Changed() end))
    c:SetPoint("TOPLEFT", x or 10, y)
    Tip(c, label, tip)
    return c
end

local function Dropdown(parent, label, list, key, y, tip, after, src, col)
    local db = src or G
    local d = Track(MakeDropdown(parent, label, list,
        function() return db()[key] end,
        function(v) db()[key] = v; Changed(); if after then after(v) end end))
    Place(d, parent, col, y)
    d:SetTip(label, tip)
    return d
end

local function GroupChoices()
    local l = {}
    for _, g in ipairs(FlashCD.Groups()) do l[#l + 1] = { key = g.id, label = g.name } end
    return l
end

---------------------------------------------------------------------------
-- While groups are unlocked: a small bar at the top of the screen with Done.
-- The window hides while moving and comes back on Done.
---------------------------------------------------------------------------
local movingBar
local reopenAfterMove = false

local function UpdateMovingBar()
    if not FlashCD.IsUnlocked() then
        if movingBar then movingBar:Hide() end
        if reopenAfterMove then
            reopenAfterMove = false
            if panel then panel:Show() end
        end
        return
    end
    if not movingBar then
        movingBar = MakeBackdropFrame(UIParent)
        movingBar:SetSize(470, 52)
        movingBar:SetPoint("TOP", 0, -60)
        movingBar:SetFrameStrata("FULLSCREEN_DIALOG")
        movingBar:SetClampedToScreen(true)
        movingBar:SetMovable(true)
        movingBar:EnableMouse(true)
        movingBar:RegisterForDrag("LeftButton")
        movingBar:SetScript("OnDragStart", function(self) self:StartMoving() end)
        movingBar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        local logo = movingBar:CreateTexture(nil, "ARTWORK")
        logo:SetSize(28, 28)
        logo:SetPoint("LEFT", 12, 0)
        logo:SetTexture("Interface\\AddOns\\FlashCD\\Media\\Icon")
        movingBar.title = movingBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        movingBar.title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
        movingBar.title:SetPoint("RIGHT", -100, 0)
        movingBar.title:SetJustifyH("LEFT")
        local hint = movingBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("BOTTOMLEFT", logo, "BOTTOMRIGHT", 10, 1)
        hint:SetText("Drag the box, or hover it and use the arrow keys (Shift: 10 px)")
        hint:SetTextColor(0.7, 0.7, 0.7)
        local done = MakeButton(movingBar, "Done", 76, 26, true)
        done:SetPoint("RIGHT", -12, 0)
        done:SetScript("OnClick", function() FlashCD.SetUnlocked(false) end)
    end
    local id = FlashCD.MovingGroup()
    movingBar.title:SetText(id and ("Moving " .. FlashCD.GetGroup(id).name) or "Moving all groups")
    movingBar:Show()
end

FlashCD.OnUnlockChanged = UpdateMovingBar

-- Unlock button: for every group, or (with getGroup) for one group on its own
local function LockButton(parent, getGroup)
    local b = MakeButton(parent, "", 120, 22, getGroup ~= nil)
    b.Refresh = function(self)
        if getGroup then
            local moving = FlashCD.MovingGroup() == getGroup().id
            self:SetText(moving and "Done moving" or "Move")
        else
            self:SetText(FlashCD.IsUnlocked() and "Lock all" or "Unlock all")
        end
    end
    b:SetScript("OnClick", function()
        if getGroup then
            FlashCD.ToggleMoveGroup(getGroup().id)
        else
            FlashCD.SetUnlocked(not FlashCD.IsUnlocked())
        end
        RefreshAll()
        -- get the window out of the way while placing groups
        if FlashCD.IsUnlocked() and panel and panel:IsShown() then
            reopenAfterMove = true
            panel:Hide()
        end
    end)
    if getGroup then
        Tip(b, "Move", "Shows only this group's box, as big as its full row of icons. "
            .. "Drag it, or hover it and use the arrow keys (1 pixel, Shift: 10). Click again when done.")
    else
        Tip(b, "Unlock all", "Shows a box for every group, as big as its full row of icons. "
            .. "Drag a box to move its group, or hover it and use the arrow keys (1 pixel, Shift: 10). Click again to lock.")
    end
    return Track(b)
end

---------------------------------------------------------------------------
-- Dragging a tracked spell onto a group in the sidebar
---------------------------------------------------------------------------
local groupButtons = {}
local dragKey, dragIcon

StartDrag = function(keys, texture)
    dragKey = keys
    if not dragIcon then
        dragIcon = CreateFrame("Frame", nil, UIParent)
        dragIcon:SetFrameStrata("TOOLTIP")
        dragIcon:SetSize(32, 32)
        dragIcon.t = dragIcon:CreateTexture(nil, "ARTWORK")
        dragIcon.t:SetAllPoints()
        dragIcon.t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        dragIcon.n = dragIcon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        dragIcon.n:SetPoint("BOTTOMRIGHT", 2, -2)
        dragIcon:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s + 18, y / s - 18)
            for _, b in ipairs(groupButtons) do
                b.drop:SetShown(b:IsShown() and b:IsMouseOver())
            end
        end)
    end
    dragIcon.t:SetTexture(texture or 134400)
    dragIcon.n:SetText(#keys > 1 and #keys or "")
    dragIcon:Show()
end

EndDrag = function()
    if not dragKey then return end
    local keys = dragKey
    dragKey = nil
    if dragIcon then dragIcon:Hide() end
    local target
    for _, b in ipairs(groupButtons) do
        if b:IsShown() and b.id and b:IsMouseOver() then target = b.id end
        b.drop:Hide()
    end
    if not target then return end
    for _, key in ipairs(keys) do
        local e = Entry(key)
        if e then e.group = target end
    end
    RefreshAll()
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

-- One group: name, buttons, and its whole look and position
local function BuildGroupPage(page)
    local nameBox = MakeEditBox(page, 200, 26, "GameFontNormalLarge")
    nameBox:SetMaxLetters(24)
    nameBox:SetPoint("TOPLEFT", 44, -12)
    local colour = Track(MakeSwatch(page,
        function() return G().color or { r = 1, g = 0.82, b = 0 } end,
        function(r, g, b) G().color = { r = r, g = g, b = b }; FlashCD.ApplyLayout(); RefreshAll() end,
        nil, "Group colour"))
    colour:SetPoint("TOPLEFT", 12, -14)
    local function SaveName(self)
        local text = (self:GetText() or ""):match("^%s*(.-)%s*$")
        if text ~= "" and text ~= G().name then
            G().name = text
            FlashCD.ApplyLayout()
            RefreshAll()
        end
        self:ClearFocus()
    end
    nameBox:SetScript("OnEnterPressed", SaveName)
    nameBox:SetScript("OnEditFocusLost", function(self)
        local text = (self:GetText() or ""):match("^%s*(.-)%s*$")
        if text ~= "" and text ~= G().name then SaveName(self) end
    end)
    nameBox:SetScript("OnEscapePressed", function(self) self:SetText(G().name) self:ClearFocus() end)
    Tip(nameBox, "Group name", "Type a new name and press Enter.")
    Track({ Refresh = function() if not nameBox:HasFocus() then nameBox:SetText(G().name) end end })

    local move = LockButton(page, G)
    move:SetPoint("LEFT", nameBox, "RIGHT", 14, 0)

    local test = MakeFlatButton(page, "Test", 64, 22)
    test:SetPoint("LEFT", move, "RIGHT", 8, 0)
    test:SetScript("OnClick", function()
        local g, n = G(), 0
        for key in pairs(DB().spells) do
            if FlashCD.GroupOf(key) == g then
                FlashCD.Flash(key, g)
                n = n + 1
                if n >= math.min(3, g.maxIcons) then break end
            end
        end
        if n == 0 then FlashCD.Test() end
    end)
    Tip(test, "Test", "Flashes a few of this group's spells.")

    local copy = MakeFlatButton(page, "Copy", 64, 22)
    copy:SetPoint("LEFT", test, "RIGHT", 6, 0)
    copy:SetScript("OnClick", function()
        local id = FlashCD.AddGroup(G())
        if id then editGroup = id end
        RefreshAll()
    end)
    Tip(copy, "Copy", "Adds a new group with the same look, placed below the last group.")

    local del = MakeFlatButton(page, "Delete", 64, 22)
    del:SetPoint("LEFT", copy, "RIGHT", 6, 0)
    del:SetScript("OnClick", function()
        FlashCD.DeleteGroup(G().id)
        editGroup = FlashCD.Groups()[1].id
        RefreshAll()
    end)
    Tip(del, "Delete", "Deletes this group. Its spells move to the first group. The last group can't be deleted.")
    Track({ Refresh = function()
        del:SetEnabled(#FlashCD.Groups() > 1)
        copy:SetEnabled(#FlashCD.Groups() < FlashCD.MAX_GROUPS)
    end })

    local db = G
    local icon = MakeSection(page, "Icon", "L", -48, 176)
    Slider(icon, "Size", 24, 300, 2, "%d", "size", -44, "How big the flash is, in pixels.")
    Slider(icon, "Opacity", 0.1, 1, 0.05, "%.2f", "alpha", -90, "How see-through the flash is at its brightest.")
    Slider(icon, "Fade-out time (seconds)", 0.3, 3, 0.1, "%.1f", "duration", -136, "How long the flash stays on screen while it fades out.")

    local pv = MakeSection(page, "Preview", "R", -48, 176)
    preview = FlashCD.NewPreview(pv)
    preview:SetPoint("CENTER", pv, "CENTER", 0, -4)

    local fx = MakeSection(page, "Effects", "L", -232, 156)
    Dropdown(fx, "Animation", FlashCD.ANIMS, "anim", -30,
        "Pop: grows a little, then settles. Zoom: grows as it fades. Bounce: bounces a few times. Slide in: rises into place. Plain fade: just fades.")
    local glow = Check(fx, "Glow border", "glow", -84, "A coloured glow around the icon. Each spell can have its own colour on the Spells & items page.")
    local swatch = Track(MakeSwatch(fx,
        function() return db().glowColor end,
        function(r, g, b) db().glowColor = { r = r, g = g, b = b }; Changed() end,
        function() db().glowColor = { r = 1, g = 0.82, b = 0 }; Changed() end))
    swatch:SetPoint("LEFT", glow.label, "RIGHT", 10, 0)
    Check(fx, "Shine burst", "shine", -112, "A bright star that bursts over the icon as it appears.")

    local tx = MakeSection(page, "Text", "R", -232, 156)
    Check(tx, "Show the name under the icon", "showName", -30)
    Check(tx, "Show \"Ready!\" above the icon", "readyText", -56)
    Slider(tx, "Font size", 8, 32, 1, "%d", "fontSize", -112, "Size of the name and the \"Ready!\" text.", nil, "L")
    Dropdown(tx, "Outline", FlashCD.OUTLINES, "fontOutline", -94, "A dark edge around the text, so it reads on bright backgrounds.", nil, nil, "R")

    local w = math.floor(GetScreenWidth() / 2)
    local h = math.floor(GetScreenHeight() / 2)
    local pos = MakeSection(page, "Position", "F", -396, 152)
    Slider(pos, "Horizontal position (X)", -w, w, 1, "%d", "x", -46,
        "Distance from the middle of the screen. You can also click Move and drag the group.", nil, "L")
    Slider(pos, "Vertical position (Y)", -h, h, 1, "%d", "y", -46, nil, nil, "R")
    Slider(pos, "Icons at once (max)", 1, 8, 1, "%d", "maxIcons", -96,
        "How many flashes can show together when several of this group's spells come ready at the same time.", nil, "L")
    Dropdown(pos, "When several show at once", FlashCD.GROWS, "grow", -80,
        "Which way the row of icons grows from the group's position.", nil, nil, "R")
    local center = MakeFlatButton(pos, "Center on screen", 130, 22)
    center:SetPoint("TOPLEFT", 16, -118)
    center:SetScript("OnClick", function()
        G().point, G().x, G().y = "CENTER", 0, 0
        FlashCD.ApplyLayout()
        RefreshAll()
    end)
end

-- Sound, filters, moving groups, reset
local function BuildAlertsPage(page)
    local db = DB

    local snd = MakeSection(page, "Sound and button", "L", -12, 112)
    Dropdown(snd, "Sound", FlashCD.SOUNDS, "sound", -30,
        "Played when something flashes (once, even if several flash together). Each spell can have its own sound.",
        function(v) FlashCD.PlaySound(v, true) end, DB)
    local mm = Track(MakeCheck(snd, "Show the minimap button",
        function() return not db().minimap.hide end,
        function(v)
            db().minimap.hide = not v
            if FlashCD.UpdateMinimapButton then FlashCD.UpdateMinimapButton() end
        end))
    mm:SetPoint("TOPLEFT", 10, -82)
    Tip(mm, "Minimap button", "Left-click opens this window, right-click shows a test flash. Drag it to move it around the minimap.")

    local when = MakeSection(page, "When to flash", "L", -136, 136)
    Check(when, "Only while in combat", "combatOnly", -30, nil, DB)
    Check(when, "Skip spells I can't cast now", "usableOnly", -56,
        "Don't flash a spell your current form or stance can't use. Lack of mana, rage or energy doesn't count.", DB)
    Slider(when, "Minimum cooldown (seconds, 0 = off)", 0, 120, 1, "%d", "minCD", -102,
        "Don't flash spells with a shorter cooldown than this.", DB)

    local mv = MakeSection(page, "Moving groups", "R", -12, 172)
    local lock = LockButton(mv)
    lock:SetPoint("TOPLEFT", 16, -32)
    local test = MakeFlatButton(mv, "Test flash", 100, 22)
    test:SetPoint("LEFT", lock, "RIGHT", 8, 0)
    test:SetScript("OnClick", function()
        if FlashCD.IsUnlocked() then FlashCD.SetUnlocked(false); RefreshAll() end
        FlashCD.Test()
    end)
    Tip(test, "Test flash", "Flashes a few spells in every group.")
    Check(mv, "Show a grid while unlocked", "grid", -64, nil, DB)
    Check(mv, "Snap to the grid when dragging", "snap", -90,
        "A dragged group lands on the nearest grid line (every 25 pixels from the middle of the screen). Arrow keys still move it 1 pixel.", DB)
    local mvHint = mv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mvHint:SetPoint("TOPLEFT", 16, -124)
    mvHint:SetPoint("RIGHT", -16, 0)
    mvHint:SetJustifyH("LEFT")
    mvHint:SetText("To move one group on its own, pick it in the list on the left and click Move. "
        .. "While moving, this window hides; click Done on the bar at the top of the screen to come back.")

    -- Confirmation in a frame of our own. The game's shared StaticPopup
    -- dialogs are not used: filling StaticPopupDialogs from an addon taints
    -- them, and the controller interface's code then gets blocked
    -- (SetPreferredGamepadInteractTarget, ADDON_ACTION_FORBIDDEN).
    local confirm = MakeBackdropFrame(panel)
    confirm:SetSize(320, 120)
    confirm:SetPoint("CENTER", panel, "CENTER", 0, 40)
    confirm:SetFrameStrata("FULLSCREEN_DIALOG")
    confirm:SetToplevel(true)
    confirm:EnableMouse(true)
    confirm:Hide()

    local ctext = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ctext:SetPoint("TOP", 0, -18)
    ctext:SetWidth(290)
    ctext:SetText("Reset all FlashCD settings to their defaults?\n\nYour groups and tracked spells are kept.")

    local yes = MakeButton(confirm, YES or "Yes", 100, 22, true)
    yes:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -6, 14)
    yes:SetScript("OnClick", function()
        confirm:Hide()
        FlashCD.ResetSettings()
        RefreshAll()
    end)

    local no = MakeButton(confirm, NO or "No", 100, 22)
    no:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 6, 14)
    no:SetScript("OnClick", function() confirm:Hide() end)

    panel:HookScript("OnHide", function() confirm:Hide() end)

    -- theme of this window
    local look = MakeSection(page, "Look", "R", -192, 80)
    Dropdown(look, "Theme", FlashCD.THEMES, "theme", -30,
        "Modern: flat and dark. WoW Forever: the game's own dialog look.",
        function()
            -- build the window again in the new look, once this click is done
            if C_Timer and C_Timer.After then C_Timer.After(0, RebuildWindow) else RebuildWindow() end
        end, DB)

    local resetBtn = MakeButton(page, "Reset to defaults", 140, 22)
    resetBtn:SetPoint("TOPLEFT", 12, -290)
    resetBtn:SetScript("OnClick", function() confirm:Show() end)
    Tip(resetBtn, "Reset to defaults", "Puts every setting back to its default, and every group's look. "
        .. "Groups, their names, tracked spells and their own settings are kept.")

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 14, -322)
    note:SetPoint("RIGHT", -14, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Settings and tracked spells are saved per character. A new character starts with the "
        .. "groups and settings of the last character you logged out on.")
end

-- The settings of the selected spell(s), right of the list
local DETAIL_W = 262

local function BuildDetail(page)
    local d = CreateFrame("Frame", nil, page)
    d:SetPoint("TOPRIGHT", -12, -104)
    d:SetPoint("BOTTOMRIGHT", -12, 34)
    d:SetWidth(DETAIL_W)
    local bg = d:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.04)
    local line = d:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.4)

    local emptyText = d:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 16, -20)
    emptyText:SetPoint("TOPRIGHT", -16, -20)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText("Click a spell to see and change its settings.\n\n"
        .. "Ctrl-click to add more spells, Shift-click to select a range, "
        .. "then change them all at once here.")

    local body = CreateFrame("Frame", nil, d)
    body:SetAllPoints()

    local icon = body:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("TOPLEFT", 14, -14)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local title = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetPoint("RIGHT", -12, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    local info = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    info:SetPoint("RIGHT", -12, 0)
    info:SetJustifyH("LEFT")
    info:SetTextColor(0.7, 0.7, 0.7)

    local keys, tracked = {}, {}

    local function ForTracked(fn)
        for _, k in ipairs(tracked) do
            local e = Entry(k)
            if e then fn(e, k) end
        end
    end
    -- the value all tracked selected spells share, or nil
    local function Common(field)
        local v, first = nil, true
        for _, k in ipairs(tracked) do
            local e = Entry(k)
            local x = e and e[field]
            if first then v, first = x, false elseif x ~= v then return nil end
        end
        return v
    end
    local function AfterChange()
        RefreshList()
        if RefreshSidebar then RefreshSidebar() end
    end

    local trackBtn = MakeButton(body, "Track", 110, 22, true)
    trackBtn:SetPoint("TOPLEFT", 14, -70)
    trackBtn:SetScript("OnClick", function()
        local anyOff = #tracked < #keys
        for _, k in ipairs(keys) do
            if anyOff then
                if DB().spells[k] == nil then FlashCD.TrackKey(k) end
            elseif DB().spells[k] ~= nil then
                FlashCD.UntrackKey(k)
            end
        end
        AfterChange()
    end)

    local test = MakeFlatButton(body, "Test flash", 90, 22)
    test:SetPoint("LEFT", trackBtn, "RIGHT", 8, 0)
    test:SetScript("OnClick", function()
        for i, k in ipairs(keys) do
            if i > 8 then break end
            FlashCD.Flash(k)
        end
    end)

    local settings = CreateFrame("Frame", nil, body)
    settings:SetPoint("TOPLEFT", 0, -102)
    settings:SetPoint("BOTTOMRIGHT")

    local group = MakeDropdown(settings, "Group", GroupChoices,
        function()
            local g = Common("group")
            return g and FlashCD.GetGroup(g).id or (#tracked > 0 and FlashCD.GroupOf(tracked[1]).id)
        end,
        function(v) ForTracked(function(e) e.group = v end) AfterChange() end, DETAIL_W - 30)
    group:SetPoint("TOPLEFT", 14, -4)
    group:SetTip("Group", "Which group these spells flash in. Each group has its own place and look.")

    local sound = MakeDropdown(settings, "Sound", SOUND_CHOICES,
        function() return Common("sound") end,
        function(v)
            ForTracked(function(e) e.sound = v end)
            FlashCD.PlaySound(v or DB().sound, true)
            AfterChange()
        end, DETAIL_W - 30)
    sound:SetPoint("TOPLEFT", 14, -56)
    sound:SetTip("Sound", "A sound just for these spells. \"Default sound\" uses the sound on the Alerts & moving page.")

    local mute = MakeCheck(settings, "Mute (keep tracked, never flash)",
        function() return #tracked > 0 and Common("muted") == true end,
        function(v) ForTracked(function(e) e.muted = v or nil end) AfterChange() end)
    mute:SetPoint("TOPLEFT", 10, -108)

    local glowLabel = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    glowLabel:SetPoint("TOPLEFT", 16, -144)
    glowLabel:SetText("Glow colour")
    local swatch = MakeSwatch(settings,
        function()
            local e = tracked[1] and Entry(tracked[1])
            return (e and e.color) or (tracked[1] and FlashCD.GroupOf(tracked[1]).glowColor) or { r = 1, g = 0.82, b = 0 }
        end,
        function(r, g, b) ForTracked(function(e) e.color = { r = r, g = g, b = b } end) AfterChange() end,
        function() ForTracked(function(e) e.color = nil end) AfterChange() end)
    swatch:SetPoint("TOPLEFT", 16, -160)
    local useGroup = MakeFlatButton(settings, "Use the group's colour", 160, 22)
    useGroup:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
    useGroup:SetScript("OnClick", function()
        ForTracked(function(e) e.color = nil end)
        AfterChange()
    end)

    local untrackedNote = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    untrackedNote:SetPoint("TOPLEFT", 14, -106)
    untrackedNote:SetPoint("RIGHT", -14, 0)
    untrackedNote:SetJustifyH("LEFT")
    untrackedNote:SetText("Not tracked. Track it to choose its group, sound and colour.")

    OnSelectionChanged = function()
        keys = SelectedKeys()
        wipe(tracked)
        for _, k in ipairs(keys) do
            if DB().spells[k] ~= nil then tracked[#tracked + 1] = k end
        end
        local n = #keys
        emptyText:SetShown(n == 0)
        body:SetShown(n > 0)
        if n == 0 then return end

        if n == 1 then
            local k = keys[1]
            icon:SetTexture(FlashCD.KeyIcon(k) or 134400)
            title:SetText(tostring(FlashCD.KeyName(k)))
            local len = not FlashCD.ItemID(k) and FlashCD.CooldownLength(k)
            local learned = DB().learnedCD[k] and not FlashCD.BaseCooldown(k)
            if FlashCD.ItemID(k) then info:SetText("Item")
            elseif len then info:SetText("Cooldown " .. FormatCD(len) .. (learned and " (seen by FlashCD)" or ""))
            else info:SetText("No cooldown reported") end
        else
            icon:SetTexture(FlashCD.KeyIcon(keys[1]) or 134400)
            title:SetText(n .. " spells selected")
            info:SetText(#tracked .. " tracked, " .. (n - #tracked) .. " not tracked")
        end
        trackBtn:SetText(#tracked < n and (n > 1 and "Track all" or "Track") or (n > 1 and "Untrack all" or "Untrack"))
        settings:SetShown(#tracked > 0)
        untrackedNote:SetShown(#tracked == 0)
        if #tracked > 0 then
            group:Refresh()
            sound:Refresh()
            mute:Refresh()
            swatch:Refresh()
        end
    end
    d.Refresh = function() OnSelectionChanged() end
    return Track(d)
end

local spellEvents   -- refreshes the list when spells or bags change (made once)

-- Every spell and item, with filters; the list grows with the window
local function BuildSpellsPage(page)
    local db = DB

    local function ShowChoices()
        local l = { { key = "all", label = "All spells" } }
        for _, t in ipairs(spellTabs) do l[#l + 1] = { key = "tab:" .. t, label = t } end
        l[#l + 1] = { key = "items", label = "Items (equipped and bags)" }
        return l
    end

    local function ViewDropdown(label, list, field, x, w, tip)
        local d = Track(MakeDropdown(page, label, list,
            function() return view[field] end,
            function(v) view[field] = v; RefreshList() end, w))
        d:SetPoint("TOPLEFT", x, -8)
        d:SetTip(label, tip)
        return d
    end
    ViewDropdown("Show", ShowChoices, "show", 14, 180, "All spells, one spellbook tab, or items with a \"Use:\" effect.")
    ViewDropdown("Status", function()
        local l = {
            { key = "all", label = "Everything" },
            { key = "tracked", label = "Tracked" },
            { key = "untracked", label = "Not tracked" },
        }
        for _, g in ipairs(FlashCD.Groups()) do
            l[#l + 1] = { key = "group:" .. g.id, label = "In " .. g.name }
        end
        return l
    end, "status", 202, 140, "Everything, only tracked or untracked spells, or the spells in one group.")
    ViewDropdown("Sort by", {
        { key = "name", label = "Name" },
        { key = "cooldown", label = "Cooldown (longest)" },
        { key = "tracked", label = "Tracked first" },
    }, "sort", 350, 140)

    searchBox = MakeEditBox(page, 150, 22)
    searchBox:SetPoint("TOPLEFT", 500, -24)
    searchBox:SetPoint("RIGHT", -12, 0)
    searchBox:SetPlaceholder("Search")
    searchBox:HookScript("OnTextChanged", function() RefreshList() end)

    local cdOnly = Track(MakeCheck(page, "Hide spells without a cooldown",
        function() return db().cdOnly end,
        function(v) db().cdOnly = v; RefreshList() end))
    cdOnly:SetPoint("TOPLEFT", 10, -56)

    local auto = Track(MakeCheck(page, "Auto-track new spells",
        function() return db().autoTrack end,
        function(v) db().autoTrack = v end))
    auto:SetPoint("TOPLEFT", 222, -56)
    Tip(auto, "Auto-track new spells", "Spells with a cooldown are ticked when you learn them. A spell you untick stays unticked, also when you learn a new rank.")

    local selAll = MakeFlatButton(page, "Select all", 80, 22)
    selAll:SetPoint("TOPRIGHT", -12, -57)
    selAll:SetScript("OnClick", function()
        for _, d in ipairs(shownRows) do selected[d.key] = true end
        spellList:UpdateSelection()
        if OnSelectionChanged then OnSelectionChanged() end
    end)
    Tip(selAll, "Select all", "Selects every spell in the list, so you can change them all at once on the right.")

    spellList = MakeSpellList(page)
    spellList:ClearAllPoints()
    spellList:SetPoint("TOPLEFT", 12, -104)
    spellList:SetPoint("BOTTOMRIGHT", -(DETAIL_W + 22), 34)

    BuildDetail(page)

    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 12)
    hint:SetPoint("BOTTOMRIGHT", -14, 12)
    hint:SetJustifyH("LEFT")
    hint:SetText("Tick to track. Click a row for its settings, Ctrl- or Shift-click for several. "
        .. "Drag rows onto a group on the left to move them there.")

    if not spellEvents then
        spellEvents = CreateFrame("Frame")
        spellEvents:RegisterEvent("SPELLS_CHANGED")
        spellEvents:RegisterEvent("BAG_UPDATE_DELAYED")
        spellEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        spellEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        spellEvents:SetScript("OnEvent", function() if panel and panel:IsShown() then RefreshList() end end)
    end
end

---------------------------------------------------------------------------
-- Sidebar: the pages and the group list (groups are drop targets)
---------------------------------------------------------------------------
local function SideButton(parent, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(184, 24)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(1, 0.82, 0, 0.18)
    b.sel:Hide()
    b.drop = b:CreateTexture(nil, "BORDER")
    b.drop:SetAllPoints()
    b.drop:SetColorTexture(0.2, 0.9, 0.3, 0.35)
    b.drop:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.dot = b:CreateTexture(nil, "ARTWORK")
    b.dot:SetSize(8, 8)
    b.dot:SetPoint("LEFT", 10, 0)
    b.dot:Hide()
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("LEFT", 10, 0)
    b.text:SetPoint("RIGHT", -36, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.text:SetText(text or "")
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.count:SetPoint("RIGHT", -8, 0)
    return b
end

local function BuildSidebar(side, pages)
    local function Heading(text, y)
        local fs = side:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", 10, y)
        fs:SetText(text)
        return fs
    end

    Heading("SETTINGS", -10)
    local navs = {}
    for i, e in ipairs({ { "spells", "Spells & items" }, { "alerts", "Alerts & moving" } }) do
        local b = SideButton(side, e[2])
        b:SetPoint("TOPLEFT", 8, -24 - (i - 1) * 26)
        b:SetScript("OnClick", function() ShowPage(e[1]) end)
        b.page = e[1]
        navs[#navs + 1] = b
    end

    Heading("GROUPS", -88)
    for i = 1, FlashCD.MAX_GROUPS do
        local b = SideButton(side)
        b:SetPoint("TOPLEFT", 8, -102 - (i - 1) * 26)
        b:SetScript("OnClick", function(self)
            editGroup = self.id
            ShowPage("group")
            RefreshAll()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.text:GetText() or "", 1, 1, 1)
            GameTooltip:AddLine("Click to edit this group. Drop a tracked spell here to move it into this group.", nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        groupButtons[i] = b
    end

    local new = MakeButton(side, "+ New group", 120, 22, true)
    new:SetScript("OnClick", function()
        local id = FlashCD.AddGroup()
        if id then
            editGroup = id
            ShowPage("group")
        end
        RefreshAll()
    end)
    Tip(new, "New group", "Adds a group with the default look, placed below the last group.")

    local hint = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 10, 10)
    hint:SetPoint("BOTTOMRIGHT", -10, 10)
    hint:SetJustifyH("LEFT")
    hint:SetText("Drag a tracked spell from the list onto a group to move it there.")

    RefreshSidebar = function()
        local groups = FlashCD.Groups()
        local page = pages.current
        for _, b in ipairs(navs) do b.sel:SetShown(page == b.page) end
        for i, b in ipairs(groupButtons) do
            local g = groups[i]
            b.id = g and g.id or nil
            b:SetShown(g ~= nil)
            if g then
                b.text:SetText(g.name)
                b.text:SetPoint("LEFT", 24, 0)
                local c = g.color or { r = 1, g = 0.82, b = 0 }
                b.dot:SetColorTexture(c.r, c.g, c.b, 1)
                b.dot:Show()
                b.count:SetText(FlashCD.CountInGroup(g))
                b.sel:SetShown(page == "group" and G().id == g.id)
            end
        end
        new:ClearAllPoints()
        new:SetPoint("TOPLEFT", 14, -106 - #groups * 26)
        new:SetEnabled(#groups < FlashCD.MAX_GROUPS)
    end
end

---------------------------------------------------------------------------
-- The FlashCD window
---------------------------------------------------------------------------
local WIN_W, WIN_H = 960, 640

local currentPage   -- the page showing, kept when the window is built again

local function SaveWindow(w)
    local s = DB().window
    local width, height, left, top = w:GetWidth(), w:GetHeight(), w:GetLeft(), w:GetTop()
    if type(width) ~= "number" or type(height) ~= "number" then return end
    s.w, s.h = math.floor(width + 0.5), math.floor(height + 0.5)
    s.x, s.y = left, top
end

local function BuildWindow(startPage)
    local w = MakeBackdropFrame(UIParent, "FlashCDWindow")
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:SetResizable(true)
    if w.SetResizeBounds then
        w:SetResizeBounds(WIN_W - 20, WIN_H, 1600, 1200)
    elseif w.SetMinResize then
        w:SetMinResize(WIN_W - 20, WIN_H)
    end
    w:EnableMouse(true)
    w:Hide()
    -- Esc closes it, like the game's own windows
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "FlashCDWindow") end

    local s = DB().window
    w:SetSize(math.max(WIN_W - 20, s.w or WIN_W), math.max(WIN_H, s.h or WIN_H))
    if s.x and s.y then
        w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", s.x, s.y)
    else
        w:SetPoint("CENTER")
    end

    -- title bar: drag to move
    local bar = CreateFrame("Frame", nil, w)
    local pad = WindowPad()
    bar:SetPoint("TOPLEFT", pad, -pad)
    bar:SetPoint("TOPRIGHT", -pad, -pad)
    bar:SetHeight(28)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() w:StartMoving() end)
    bar:SetScript("OnDragStop", function() w:StopMovingOrSizing() SaveWindow(w) end)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(1, 1, 1, 0.05)

    local logo = bar:CreateTexture(nil, "ARTWORK")
    logo:SetSize(22, 22)
    logo:SetPoint("LEFT", 6, 0)
    logo:SetTexture("Interface\\AddOns\\FlashCD\\Media\\Icon")
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("FlashCD")
    local sub = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 12, -1)
    sub:SetText("/fcd  ·  /fcd unlock  ·  /fcd test  ·  /fcd spell <name>")

    local close
    if WoW() then
        close = CreateFrame("Button", nil, bar)
        close:SetSize(30, 30)
        close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
        close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
        close:SetPoint("RIGHT", 4, 0)
    else
        close = MakeButton(bar, "X", 24, 22)
        close:SetPoint("RIGHT", -2, 0)
    end
    Tip(close, "Close", "Esc or /fcd also closes this window.")
    close:SetScript("OnClick", function() w:Hide() end)

    -- resize grip
    local grip = CreateFrame("Button", nil, w)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -pad + 2, pad - 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() w:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() w:StopMovingOrSizing() SaveWindow(w) end)

    local side = CreateFrame("Frame", nil, w)
    side:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    side:SetPoint("BOTTOMLEFT", pad, pad)
    side:SetWidth(200)
    local sideBg = side:CreateTexture(nil, "BACKGROUND")
    sideBg:SetAllPoints()
    sideBg:SetColorTexture(1, 1, 1, 0.035)

    local content = CreateFrame("Frame", nil, w)
    content:SetPoint("TOPLEFT", side, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", -pad, pad + 16)

    panel = w
    local pages = {}
    for _, name in ipairs({ "group", "spells", "alerts" }) do
        local p = CreateFrame("Frame", nil, content)
        p:SetAllPoints(content)
        p:Hide()
        pages[name] = p
    end

    ShowPage = function(name)
        pages.current = name
        currentPage = name
        for key, p in pairs(pages) do
            if key ~= "current" then p:SetShown(key == name) end
        end
        if RefreshSidebar then RefreshSidebar() end
    end

    BuildGroupPage(pages.group)
    BuildSpellsPage(pages.spells)
    BuildAlertsPage(pages.alerts)
    BuildSidebar(side, pages)
    ShowPage(startPage or "group")

    w:SetScript("OnShow", RefreshAll)
    w:HookScript("OnHide", function()
        if dragKey then EndDrag() end
        CloseMenu()
    end)
end

---------------------------------------------------------------------------
-- A small page in the game's Settings (Options -> AddOns) that opens the window
---------------------------------------------------------------------------
local function BuildLauncher()
    local p = CreateFrame("Frame")
    p.name = "FlashCD"
    p:Hide()

    local logo = p:CreateTexture(nil, "ARTWORK")
    logo:SetSize(32, 32)
    logo:SetPoint("TOPLEFT", 14, -12)
    logo:SetTexture("Interface\\AddOns\\FlashCD\\Media\\Icon")
    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 8, -2)
    title:SetText("FlashCD")
    local text = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -14)
    text:SetWidth(520)
    text:SetJustifyH("LEFT")
    text:SetText("FlashCD's settings are in a window of their own. Open it with the button below, "
        .. "with /fcd, or with the minimap button.")
    local open = MakeButton(p, "Open FlashCD", 160, 26, true)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    open:SetScript("OnClick", function() FlashCD.OpenOptions(true) end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(p, "FlashCD")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(p)
    end
end

-- Build the window again, e.g. in a new theme: same page, size and place.
-- The old frames are hidden and left alone (frames can't be deleted).
RebuildWindow = function()
    local old = panel
    if not old then return end
    local wasShown = old:IsShown()
    SaveWindow(old)
    old:SetScript("OnShow", nil)
    old:Hide()
    CloseMenu()
    if menu then menu:Hide() end
    menu, catcher = nil, nil
    if movingBar then movingBar:Hide() end
    movingBar = nil
    wipe(refreshers)
    wipe(groupButtons)
    preview, spellList, searchBox = nil, nil, nil
    RefreshSidebar, OnSelectionChanged = nil, nil
    panel = nil
    BuildWindow(currentPage)
    if wasShown then panel:Show() end
    UpdateMovingBar()
end

-- Change the window's theme ("modern" or "wow") right away
function FlashCD.SetTheme(theme)
    FlashCD.db.theme = theme
    RebuildWindow()
end

function FlashCD.InitOptions()
    if panel then return end
    BuildWindow()
    BuildLauncher()
end

-- Open (or, without `show`, toggle) the FlashCD window
function FlashCD.OpenOptions(show)
    if not panel then return end
    if panel:IsShown() and not show then
        panel:Hide()
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print("|cff33ccffFlashCD|r: the settings can't be opened in combat.")
        return
    end
    panel:Show()
    panel:Raise()
end
