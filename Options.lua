-- FlashCD - Options.lua
-- Settings panel with two pages:
--   Display - size, position, fade, animation, sound, glow, filters
--   Spells  - pick spells (spellbook) or items to track; right-click a
--             tracked entry for its own sound / glow colour / mute.

local ADDON, ns = ...
local FlashCD = ns.FlashCD

local ROW_H = 24
local LIST_W, LIST_H = 275, 320

local panel, category
local bookList, trackList, searchBox, cdOnlyCheck, popup
local source = "spells"          -- left list shows "spells" or "items"
local refreshers = {}            -- widgets with :Refresh()

local function DB() return FlashCD.db end

---------------------------------------------------------------------------
-- Small widget helpers (no reliance on optional templates)
---------------------------------------------------------------------------
local function TryTemplate(kind, parent, template, name)
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f end
    return CreateFrame(kind, name, parent)
end

local function Track(w)
    refreshers[#refreshers + 1] = w
    return w
end

local function MakeButton(parent, text, w, h)
    local b = TryTemplate("Button", parent, "UIPanelButtonTemplate")
    b:SetSize(w or 100, h or 22)
    if not b:GetFontString() then
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetAllPoints()
        b:SetFontString(fs)
    end
    b:SetText(text)
    return b
end

local function MakeCheck(parent, label, get, set)
    local c = TryTemplate("CheckButton", parent, "UICheckButtonTemplate")
    c:SetSize(24, 24)
    if c.Text then c.Text:SetText("") end
    if c.text then c.text:SetText("") end
    local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
    fs:SetText(label)
    c.label = fs
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    c.Refresh = function(self) self:SetChecked(get() and true or false) end
    return c
end

local function MakeSlider(parent, label, minV, maxV, step, fmt, get, set)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(220, 16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouse(true)
    s:EnableMouseWheel(true)

    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)
    track:SetColorTexture(0.45, 0.45, 0.45, 1)

    local inner = s:CreateTexture(nil, "BORDER")
    inner:SetPoint("TOPLEFT", track, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.08, 0.08, 0.08, 1)

    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = s:GetThumbTexture()
    if thumb then thumb:SetSize(32, 32) end

    local title = s:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 2)
    title:SetText(label)

    local val = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    val:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", 0, 2)

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

-- Button that steps through a list of {key, label}. Left-click: next, right-click: previous.
local function MakeCycle(parent, prefix, list, get, set, w)
    local b = MakeButton(parent, "", w or 220, 22)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.Refresh = function(self)
        local cur = get()
        for _, e in ipairs(list) do
            if e.key == cur then self:SetText(prefix .. e.label) return end
        end
        self:SetText(prefix .. list[1].label)
    end
    b:SetScript("OnClick", function(self, mouse)
        local cur, idx = get(), 1
        for i, e in ipairs(list) do
            if e.key == cur then idx = i break end
        end
        idx = idx + (mouse == "RightButton" and -1 or 1)
        if idx > #list then idx = 1 elseif idx < 1 then idx = #list end
        set(list[idx].key)
        self:Refresh()
    end)
    return b
end

-- Whether the game's controller (gamepad) interface is on. Under it the game's
-- gamepad code takes every menu and shared window that opens into its focus
-- and calls the protected SetPreferredGamepadInteractTarget; if addon code
-- opened it, that call is blocked (ADDON_ACTION_FORBIDDEN). So under the
-- controller interface FlashCD opens none of the game's menus or shared windows.
local function GamepadUI()
    local styles, api = Enum and Enum.InputDeviceInterfaceType, C_InputInterfaceStyle
    if not (styles and api and api.GetCurrentStyle) then return false end
    local ok, style = pcall(api.GetCurrentStyle)
    return ok and style == styles.Gamepad
end

-- Labelled dropdown of {key, label} choices (the stock dropdown the game's own
-- Settings use). Under the controller interface, or where that template is
-- missing, a cycle button is shown instead (see GamepadUI).
-- The label sits above the dropdown; position the returned frame by its TOPLEFT.
local function MakeDropdown(parent, label, list, get, set, w)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w or 220, 40)

    local title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText(label)

    local b = MakeCycle(holder, "", list, get, set, w)
    b:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)

    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, holder, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetWidth(w or 220)
        dd:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
        dd:SetupMenu(function(_, root)
            for _, e in ipairs(list) do
                root:CreateRadio(e.label,
                    function() return get() == e.key end,
                    function() set(e.key); holder:Refresh() end)
            end
        end)
    else
        if ok and dd then dd:Hide() end
        dd = nil
    end

    holder.Refresh = function()
        local useMenu = dd ~= nil and not GamepadUI()
        if dd then dd:SetShown(useMenu) end
        b:SetShown(not useMenu)
        if useMenu then
            if dd.GenerateMenu then dd:GenerateMenu() end
        else
            b:Refresh()
        end
    end
    return holder
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

-- Small colour square; getColor() returns {r,g,b}, setColor(r,g,b)
local function MakeSwatch(parent, getColor, setColor)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.8, 0.8, 0.8, 1)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    b.Refresh = function(self)
        local c = getColor()
        fill:SetColorTexture(c.r, c.g, c.b, 1)
    end
    b:SetScript("OnClick", function(self)
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
        GameTooltip:SetText(GamepadUI() and "Click for the next colour" or "Click to pick a colour")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function MakeBackdropFrame(parent, name)
    local f = TryTemplate("Frame", parent, BackdropTemplateMixin and "BackdropTemplate" or nil, name)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.05, 0.05, 0.97)
    end
    return f
end

-- Scrollable list of rows. SetData({ {key, name, label, icon, id, itemID}, ... })
local function MakeList(parent, titleText, buttonText, onButton, onRightClick)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(LIST_W, LIST_H)

    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)

    local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 4)
    title:SetText(titleText)
    box.title = title

    local scroll = TryTemplate("ScrollFrame", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange()
        local v = math.max(0, math.min(max, self:GetVerticalScroll() - delta * ROW_H * 3))
        self:SetVerticalScroll(v)
    end)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(LIST_W - 30, 1)
    scroll:SetScrollChild(content)

    local empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")

    box.rows = {}

    local function GetRow(i)
        local r = box.rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, content)
        r:SetSize(LIST_W - 30, ROW_H)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        r:EnableMouse(true)

        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_H - 4, ROW_H - 4)
        r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        r.btn = MakeButton(r, buttonText, 60, ROW_H - 4)
        r.btn:SetPoint("RIGHT", -2, 0)
        r.btn:SetScript("OnClick", function() if r.key then onButton(r.key) end end)

        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT", r.btn, "LEFT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)

        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.itemID and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(self.itemID)
            elseif self.spellID and GameTooltip.SetSpellByID then
                GameTooltip:SetSpellByID(self.spellID)
            else
                GameTooltip:SetText(self.text:GetText() or "")
            end
            if onRightClick then
                GameTooltip:AddLine("Right-click: sound, glow colour, mute", 0.4, 0.8, 1)
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnMouseUp", function(self, mouse)
            if mouse == "RightButton" and onRightClick and self.key then
                onRightClick(self.key, self)
            end
        end)

        box.rows[i] = r
        return r
    end

    box.SetData = function(self, data, emptyText)
        for i, d in ipairs(data) do
            local r = GetRow(i)
            r.spellID = d.id
            r.itemID = d.itemID
            r.key = d.key or d.name
            r.icon:SetTexture(d.icon or 134400)
            r.text:SetText(d.label or d.name or "?")
            r:Show()
        end
        for i = #data + 1, #self.rows do self.rows[i]:Hide() end
        content:SetHeight(math.max(1, #data * ROW_H))
        empty:SetText(#data == 0 and (emptyText or "") or "")
        local max = scroll:GetVerticalScrollRange()
        if scroll:GetVerticalScroll() > max then scroll:SetVerticalScroll(max) end
    end

    return box
end

---------------------------------------------------------------------------
-- Spellbook and item scanning
---------------------------------------------------------------------------
function FlashCD.HasCooldown(id)
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
    local function add(id, name, icon)
        if not id then return end
        name = name or FlashCD.GetSpellName(id)
        if not name then return end
        local entry = byName[name]
        if not entry then
            entry = { name = name, key = name }
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
                        add(info.spellID, info.name, info.iconID)
                    end
                end
            end
        end
    elseif GetNumSpellTabs then
        for t = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(t)
            for j = offset + 1, offset + num do
                local kind, id = GetSpellBookItemInfo(j, BOOKTYPE_SPELL or "spell")
                if kind == "SPELL" and id and not (IsPassiveSpell and IsPassiveSpell(id)) then
                    add(id)
                end
            end
        end
    end

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
-- Refresh
---------------------------------------------------------------------------
local function TrackedLabel(key, entry)
    local name = tostring(FlashCD.KeyName(key))
    local tags = {}
    if entry.muted then tags[#tags + 1] = "muted" end
    if entry.sound then tags[#tags + 1] = "sound" end
    if entry.color then tags[#tags + 1] = "colour" end
    if #tags == 0 then return name end
    return name .. " |cff888888(" .. table.concat(tags, ", ") .. ")|r"
end

local function RefreshLists()
    if not panel then return end
    local db = DB()
    local filter = (searchBox and searchBox:GetText() or ""):lower()

    local data = source == "items" and FlashCD.ScanItems() or FlashCD.ScanSpellbook()
    local book = {}
    for _, d in ipairs(data) do
        local nameOk = filter == "" or (d.name and tostring(d.name):lower():find(filter, 1, true))
        local cdOk = source == "items" or not db.cdOnly or FlashCD.HasCooldown(d.id)
        if db.spells[d.key] == nil and nameOk and cdOk then
            book[#book + 1] = d
        end
    end
    bookList.title:SetText(source == "items" and "Usable items (equipped and bags)" or "Spellbook")
    bookList:SetData(book, source == "items" and "No usable items found" or "No matching spells")
    cdOnlyCheck:SetShown(source ~= "items")

    local tracked = {}
    for key, entry in pairs(db.spells) do
        local item = FlashCD.ItemID(key)
        tracked[#tracked + 1] = {
            key = key,
            itemID = item,
            id = (not item) and (type(key) == "number" and key or FlashCD.GetSpellID(key)) or nil,
            name = tostring(FlashCD.KeyName(key)),
            label = TrackedLabel(key, type(entry) == "table" and entry or {}),
            icon = FlashCD.KeyIcon(key),
        }
    end
    trackList:SetData(SortByName(tracked), "Add spells or items from the left list")
end

local function RefreshAll()
    if not panel then return end
    for _, w in ipairs(refreshers) do w:Refresh() end
    RefreshLists()
end

FlashCD.OnTrackedChanged = function()
    if panel and panel:IsShown() then RefreshLists() end
end

FlashCD.OnPositionChanged = function()
    if panel then for _, w in ipairs(refreshers) do w:Refresh() end end
end

---------------------------------------------------------------------------
-- Per-spell popup (right-click a tracked entry)
---------------------------------------------------------------------------
local function Entry()
    local e = popup and popup.key and DB().spells[popup.key]
    return type(e) == "table" and e or nil
end

local function BuildPopup()
    popup = MakeBackdropFrame(panel, "FlashCDSpellPopup")
    popup:SetSize(290, 196)
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:EnableMouse(true)
    popup:Hide()

    popup.icon = popup:CreateTexture(nil, "ARTWORK")
    popup.icon:SetSize(28, 28)
    popup.icon:SetPoint("TOPLEFT", 14, -14)
    popup.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    popup.title:SetPoint("LEFT", popup.icon, "RIGHT", 8, 0)
    popup.title:SetPoint("RIGHT", -34, 0)
    popup.title:SetJustifyH("LEFT")
    popup.title:SetWordWrap(false)

    local close = TryTemplate("Button", popup, "UIPanelCloseButton")
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() popup:Hide() end)

    local function changed()
        RefreshLists()
        popup:Refresh()
    end

    local mute = MakeCheck(popup, "Mute (keep tracked, never flash)",
        function() local e = Entry() return e and e.muted end,
        function(v) local e = Entry() if e then e.muted = v or nil end changed() end)
    mute:SetPoint("TOPLEFT", 12, -52)

    local soundList = { { key = nil, label = "Default" } }
    for _, s in ipairs(FlashCD.SOUNDS) do soundList[#soundList + 1] = s end
    local sound = MakeDropdown(popup, "Sound", soundList,
        function() local e = Entry() return e and e.sound end,
        function(v)
            local e = Entry()
            if e then e.sound = v end
            FlashCD.PlaySound(v or DB().sound, true)
            changed()
        end, 262)
    sound:SetPoint("TOPLEFT", 16, -80)

    local colourLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    colourLabel:SetPoint("TOPLEFT", 16, -138)
    colourLabel:SetText("Glow colour:")

    local swatch = MakeSwatch(popup,
        function() local e = Entry() return (e and e.color) or DB().glowColor end,
        function(r, g, b) local e = Entry() if e then e.color = { r = r, g = g, b = b } end changed() end)
    swatch:SetPoint("LEFT", colourLabel, "RIGHT", 8, 0)

    local reset = MakeButton(popup, "Use default", 100, 22)
    reset:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
    reset:SetScript("OnClick", function() local e = Entry() if e then e.color = nil end changed() end)

    local test = MakeButton(popup, "Test", 80, 22)
    test:SetPoint("BOTTOMRIGHT", -12, 12)
    test:SetScript("OnClick", function() if popup.key then FlashCD.Flash(popup.key) end end)

    popup.Refresh = function(self)
        if not Entry() then self:Hide() return end
        self.icon:SetTexture(FlashCD.KeyIcon(self.key) or 134400)
        self.title:SetText(FlashCD.KeyName(self.key))
        mute:Refresh()
        sound:Refresh()
        swatch:Refresh()
        reset:SetEnabled(Entry().color ~= nil)
    end
end

local function OpenPopup(key, row)
    if not popup then BuildPopup() end
    popup.key = key
    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", row, "TOPLEFT", -8, 0)
    popup:Show()
    popup:Refresh()
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function BuildDisplayPage(page)
    local db = DB
    local w = math.floor(GetScreenWidth() / 2)
    local h = math.floor(GetScreenHeight() / 2)
    local C1, C2 = 20, 320

    local function Slider(label, minV, maxV, step, fmt, key, x, y, after)
        local s = Track(MakeSlider(page, label, minV, maxV, step, fmt,
            function() return db()[key] end,
            function(v) db()[key] = v; if after then after() end end))
        s:SetPoint("TOPLEFT", x, y)
        return s
    end

    Slider("Icon size", 24, 300, 2, "%d", "size", C1, -30, FlashCD.ApplyLayout)
    Slider("Fade-out time (seconds)", 0.3, 3, 0.1, "%.1f", "duration", C2, -30)
    Slider("Horizontal position (X)", -w, w, 1, "%d", "x", C1, -80, FlashCD.ApplyLayout)
    Slider("Vertical position (Y)", -h, h, 1, "%d", "y", C2, -80, FlashCD.ApplyLayout)
    Slider("Opacity", 0.1, 1, 0.05, "%.2f", "alpha", C1, -130)
    Slider("Icons side by side (max)", 1, 8, 1, "%d", "maxIcons", C2, -130)
    Slider("Minimum cooldown to flash (seconds, 0 = off)", 0, 120, 1, "%d", "minCD", C1, -180)

    local lockBtn = MakeButton(page, "Unlock (drag)", 120, 22)
    lockBtn:SetPoint("TOPLEFT", C1, -215)
    lockBtn.Refresh = function(self)
        self:SetText(FlashCD.IsUnlocked() and "Lock" or "Unlock (drag)")
    end
    lockBtn:SetScript("OnClick", function()
        FlashCD.SetUnlocked(not FlashCD.IsUnlocked())
        RefreshAll()
    end)
    Track(lockBtn)

    local centerBtn = MakeButton(page, "Center", 80, 22)
    centerBtn:SetPoint("LEFT", lockBtn, "RIGHT", 8, 0)
    centerBtn:SetScript("OnClick", function()
        db().point, db().x, db().y = "CENTER", 0, 0
        FlashCD.ApplyLayout()
        RefreshAll()
    end)

    local testBtn = MakeButton(page, "Test flash", 100, 22)
    testBtn:SetPoint("LEFT", centerBtn, "RIGHT", 8, 0)
    testBtn:SetScript("OnClick", function()
        if FlashCD.IsUnlocked() then FlashCD.SetUnlocked(false); RefreshAll() end
        FlashCD.Test()
    end)

    -- Confirmation in a frame of our own. The game's shared StaticPopup
    -- dialogs are not used: filling StaticPopupDialogs from an addon taints
    -- them, and the controller interface's code then gets blocked
    -- (SetPreferredGamepadInteractTarget, ADDON_ACTION_FORBIDDEN).
    local confirm = MakeBackdropFrame(panel)
    confirm:SetSize(320, 120)
    confirm:SetPoint("CENTER", panel, "CENTER", 0, 40)
    confirm:SetFrameStrata("DIALOG")
    confirm:SetToplevel(true)
    confirm:EnableMouse(true)
    confirm:Hide()

    local ctext = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ctext:SetPoint("TOP", 0, -18)
    ctext:SetWidth(290)
    ctext:SetText("Reset all FlashCD settings to their defaults?\n\nYour tracked spells and items are kept.")

    local yes = MakeButton(confirm, YES or "Yes", 100, 22)
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

    local resetBtn = MakeButton(page, "Reset to defaults", 140, 22)
    resetBtn:SetPoint("LEFT", testBtn, "RIGHT", 8, 0)
    resetBtn:SetScript("OnClick", function() confirm:Show() end)

    local anim = Track(MakeDropdown(page, "Animation", FlashCD.ANIMS,
        function() return db().anim end,
        function(v) db().anim = v end))
    anim:SetPoint("TOPLEFT", C1, -250)

    local sound = Track(MakeDropdown(page, "Sound", FlashCD.SOUNDS,
        function() return db().sound end,
        function(v) db().sound = v; FlashCD.PlaySound(v, true) end))
    sound:SetPoint("TOPLEFT", C2, -250)

    local function Check(label, key, x, y)
        local c = Track(MakeCheck(page, label,
            function() return db()[key] end,
            function(v) db()[key] = v end))
        c:SetPoint("TOPLEFT", x - 4, y)
        return c
    end

    Check("Show name under the icon", "showName", C1, -304)
    local glow = Check("Glow border", "glow", C2, -304)
    local swatch = Track(MakeSwatch(page,
        function() return db().glowColor end,
        function(r, g, b) db().glowColor = { r = r, g = g, b = b } end))
    swatch:SetPoint("LEFT", glow.label, "RIGHT", 10, 0)

    Check("Only flash while in combat", "combatOnly", C1, -334)
    Check("Skip spells I can't cast now (wrong form)", "usableOnly", C2, -334)

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", C1, -378)
    note:SetWidth(560)
    note:SetJustifyH("LEFT")
    note:SetText("Settings and tracked spells are saved per character. A new character starts with the "
        .. "display settings of the last character you logged out on.\n"
        .. "Reset to defaults keeps your tracked spells and their own settings.")
end

local function BuildSpellsPage(page)
    local db = DB

    bookList = MakeList(page, "Spellbook", "Add", function(key)
        FlashCD.TrackKey(key)
        RefreshLists()
    end)
    bookList:SetPoint("TOPLEFT", 16, -96)

    trackList = MakeList(page, "Tracked", "Remove", function(key)
        FlashCD.UntrackKey(key)
        if popup and popup.key == key then popup:Hide() end
        RefreshLists()
    end, OpenPopup)
    trackList:SetPoint("TOPLEFT", bookList, "TOPRIGHT", 20, 0)

    -- source switch
    local spellsBtn = MakeButton(page, "Spellbook", 100, 22)
    spellsBtn:SetPoint("TOPLEFT", 16, -8)
    local itemsBtn = MakeButton(page, "Items", 100, 22)
    itemsBtn:SetPoint("LEFT", spellsBtn, "RIGHT", 6, 0)
    local function SetSource(s)
        source = s
        spellsBtn:SetEnabled(s ~= "spells")
        itemsBtn:SetEnabled(s ~= "items")
        RefreshLists()
    end
    spellsBtn:SetScript("OnClick", function() SetSource("spells") end)
    itemsBtn:SetScript("OnClick", function() SetSource("items") end)
    spellsBtn:SetEnabled(false)

    searchBox = TryTemplate("EditBox", page, "SearchBoxTemplate")
    if not searchBox.Instructions then
        searchBox:Hide()
        searchBox = TryTemplate("EditBox", page, "InputBoxTemplate")
    end
    searchBox:SetSize(150, 20)
    searchBox:SetAutoFocus(false)
    searchBox:SetPoint("BOTTOMRIGHT", bookList, "TOPRIGHT", 0, 2)
    searchBox:HookScript("OnTextChanged", function() RefreshLists() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    cdOnlyCheck = Track(MakeCheck(page, "Only spells with a cooldown",
        function() return db().cdOnly end,
        function(v) db().cdOnly = v; RefreshLists() end))
    cdOnlyCheck:SetPoint("BOTTOMLEFT", bookList, "TOPLEFT", -4, 26)

    local autoCheck = Track(MakeCheck(page, "Auto-track newly learned spells",
        function() return db().autoTrack end,
        function(v) db().autoTrack = v end))
    autoCheck:SetPoint("BOTTOMLEFT", trackList, "TOPLEFT", -4, 26)

    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", bookList, "BOTTOMLEFT", 0, -8)
    hint:SetWidth(LIST_W * 2 + 20)
    hint:SetJustifyH("LEFT")
    hint:SetText("Right-click a tracked entry to give it its own sound or glow colour, or to mute it.")

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("SPELLS_CHANGED")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    ev:SetScript("OnEvent", function() if panel:IsShown() then RefreshLists() end end)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function Build()
    panel = CreateFrame("Frame")
    panel.name = "FlashCD"
    panel:Hide()

    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(32, 32)
    logo:SetPoint("TOPLEFT", 14, -12)
    logo:SetTexture("Interface\\AddOns\\FlashCD\\Media\\Icon")

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 8, -2)
    title:SetText("FlashCD")

    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("Flashes an icon when a spell or item comes off cooldown.  /flashcd  ·  /flashcd unlock  ·  /flashcd test")

    local pages, tabs = {}, {}
    local function ShowPage(i)
        for j, p in ipairs(pages) do
            p:SetShown(j == i)
            tabs[j]:SetEnabled(j ~= i)
        end
        if popup then popup:Hide() end
    end

    for i, name in ipairs({ "Display", "Spells & items" }) do
        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", 0, -86)
        page:SetPoint("BOTTOMRIGHT")
        pages[i] = page

        local tab = MakeButton(panel, name, 130, 24)
        tab:SetPoint("TOPLEFT", 16 + (i - 1) * 136, -52)
        tab:SetScript("OnClick", function() ShowPage(i) end)
        tabs[i] = tab
    end

    BuildDisplayPage(pages[1])
    BuildSpellsPage(pages[2])
    ShowPage(1)

    panel:SetScript("OnShow", RefreshAll)
    panel:HookScript("OnHide", function() if popup then popup:Hide() end end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, "FlashCD")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function FlashCD.InitOptions()
    if not panel then Build() end
end

function FlashCD.OpenOptions()
    if InCombatLockdown and InCombatLockdown() then
        print("|cff33ccffFlashCD|r: options can't be opened in combat.")
        return
    end
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
