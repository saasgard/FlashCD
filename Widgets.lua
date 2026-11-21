-- FlashCD - Widgets.lua
-- The controls the settings window is built from, in two themes. Options.lua
-- gets them through ns.W.

local ADDON, ns = ...
local FlashCD = ns.FlashCD
local W = {}
ns.W = W

local refreshers = {}            -- widgets with :Refresh(), refreshed together
W.refreshers = refreshers

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

-- onHover(key), if given, runs when the mouse moves onto an item (previews)
local function OpenMenu(owner, list, get, onPick, onHover)
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
        it:SetScript("OnEnter", onHover and function() onHover(e.key) end or nil)
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
        text:SetText(holder.placeholder or "-")   -- nothing chosen
    end
    b:SetScript("OnClick", function()
        OpenMenu(b, list, get, function(v) set(v) holder:Refresh() end, holder.onHover)
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

-- Forget the shared dropdown menu (it is made again in the current theme)
function W.ResetMenu()
    if menu then menu:Hide() end
    menu, catcher = nil, nil
end

W.Track = Track
W.Tip = Tip
W.AddBorder = AddBorder
W.Fill = Fill
W.MakeButton = MakeButton
W.MakeFlatButton = MakeFlatButton
W.MakeCheck = MakeCheck
W.MakeSlider = MakeSlider
W.MakeEditBox = MakeEditBox
W.MakeScroll = MakeScroll
W.ListOf = ListOf
W.CloseMenu = CloseMenu
W.OpenMenu = OpenMenu
W.MakeDropdown = MakeDropdown
W.GamepadUI = GamepadUI
W.MakeSwatch = MakeSwatch
W.MakeBackdropFrame = MakeBackdropFrame
W.WindowPad = WindowPad
W.MakeSection = MakeSection
W.Place = Place
W.WoW = WoW
