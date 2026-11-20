-- FlashCD - Options.lua
-- Settings panel with three pages:
--   Appearance       - icon, effects and text, with a live preview
--   Layout & alerts  - position, grow direction, sound, filters, minimap button
--   Spells & items   - one list: tick to track; each tracked row has its own
--                      mute, sound and glow colour

local ADDON, ns = ...
local FlashCD = ns.FlashCD

local ROW_H = 28
local LIST_W, LIST_H = 576, 290

local panel, category
local spellList, searchBox, preview
local refreshers = {}            -- widgets with :Refresh()
local view = { show = "all", status = "all", sort = "name" }
local spellTabs = {}             -- spellbook tab names seen in the last scan

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

local function MakeSlider(parent, label, minV, maxV, step, fmt, get, set, w)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(w or 220, 16)
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

-- `list` is a table of {key, label} or a function returning one
local function ListOf(list)
    if type(list) == "function" then return list() end
    return list
end

-- Button that steps through the choices. Left-click: next, right-click: previous.
local function MakeCycle(parent, prefix, list, get, set, w)
    local b = MakeButton(parent, "", w or 220, 22)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.Refresh = function(self)
        local cur, l = get(), ListOf(list)
        for _, e in ipairs(l) do
            if e.key == cur then self:SetText(prefix .. e.label) return end
        end
        self:SetText(prefix .. (l[1] and l[1].label or ""))
    end
    b:SetScript("OnClick", function(self, mouse)
        local cur, l, idx = get(), ListOf(list), 1
        for i, e in ipairs(l) do
            if e.key == cur then idx = i break end
        end
        idx = idx + (mouse == "RightButton" and -1 or 1)
        if idx > #l then idx = 1 elseif idx < 1 then idx = #l end
        set(l[idx].key)
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

-- Dropdown of {key, label} choices (the stock dropdown the game's own Settings
-- use). Under the controller interface, or where that template is missing, a
-- cycle button is shown instead (see GamepadUI). With a label, the label sits
-- above the dropdown. Position the returned frame by its TOPLEFT.
local function MakeDropdown(parent, label, list, get, set, w)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w or 220, label and 44 or 26)

    local anchorTo, ax, ay = holder, 0, 0
    if label then
        local title = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 0, 0)
        title:SetText(label)
        anchorTo, ay = title, -3
    end
    local point = label and "BOTTOMLEFT" or "TOPLEFT"

    local b = MakeCycle(holder, "", list, get, set, w)
    b:SetPoint("TOPLEFT", anchorTo, point, ax, ay)
    holder.button = b

    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, holder, "WowStyle1DropdownTemplate")
    if ok and dd and dd.SetupMenu then
        dd:SetWidth(w or 220)
        dd:SetPoint("TOPLEFT", anchorTo, point, ax, ay)
        dd:SetupMenu(function(_, root)
            for _, e in ipairs(ListOf(list)) do
                root:CreateRadio(e.label,
                    function() return get() == e.key end,
                    function() set(e.key); holder:Refresh() end)
            end
        end)
        holder.dd = dd
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
    holder.SetTip = function(self, title, text)
        Tip(b, title, text)
        if dd then Tip(dd, title, text) end
        return self
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

-- Small colour square; getColor() returns {r,g,b}, setColor(r,g,b).
-- With onReset, right-click puts the colour back to its default.
local function MakeSwatch(parent, getColor, setColor, onReset)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
        GameTooltip:SetText("Glow colour", 1, 1, 1)
        GameTooltip:AddLine(GamepadUI() and "Click: next colour" or "Click: pick a colour")
        if onReset then GameTooltip:AddLine("Right-click: use the default colour") end
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

-- A shaded box with a heading; place controls inside it
local function MakeSection(parent, title, x, y, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", x, y)
    f:SetSize(w, h)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.04)
    local line = f:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT")
    line:SetPoint("TOPRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.4)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 10, -7)
    t:SetText(title)
    return f
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

local function MakeSpellList(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(LIST_W, LIST_H)

    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)

    -- column headings
    local function Head(text, x)
        local fs = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        fs:SetPoint("BOTTOMLEFT", box, "TOPLEFT", x, 3)
        fs:SetText(text)
    end
    Head("Track", 4)
    Head("Spell", 62)
    Head("Cooldown", 236)
    Head("Mute", 290)
    Head("Sound", 350)
    Head("Glow", 466)

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

        local stripe = r:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

        r.check = MakeCheck(r, "",
            function() return DB().spells[r.key] ~= nil end,
            function(v)
                if not r.key then return end
                if v then FlashCD.TrackKey(r.key) else FlashCD.UntrackKey(r.key) end
                RefreshList()
            end)
        r.check:SetPoint("LEFT", 2, 0)

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_H - 6, ROW_H - 6)
        r.icon:SetPoint("LEFT", 30, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetPoint("LEFT", 58, 0)
        r.text:SetWidth(170)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)

        r.cd = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.cd:SetPoint("LEFT", 232, 0)
        r.cd:SetWidth(50)
        r.cd:SetJustifyH("LEFT")
        r.cd:SetTextColor(0.7, 0.7, 0.7)

        r.mute = MakeCheck(r, "",
            function() local e = Entry(r.key) return e and e.muted end,
            function(v) local e = Entry(r.key) if e then e.muted = v or nil end RefreshList() end)
        r.mute:SetPoint("LEFT", 288, 0)
        Tip(r.mute, "Mute", "Keep it tracked, but never flash it.")

        r.sound = MakeDropdown(r, nil, SOUND_CHOICES,
            function() local e = Entry(r.key) return e and e.sound end,
            function(v)
                local e = Entry(r.key)
                if e then e.sound = v end
                FlashCD.PlaySound(v or DB().sound, true)
            end, 110)
        r.sound:SetPoint("LEFT", 318, 0)
        r.sound:SetTip("Sound", "A sound just for this one. \"Default sound\" uses the sound set on the Layout & alerts page.")

        r.swatch = MakeSwatch(r,
            function() local e = Entry(r.key) return (e and e.color) or DB().glowColor end,
            function(cr, cg, cb) local e = Entry(r.key) if e then e.color = { r = cr, g = cg, b = cb } end end,
            function() local e = Entry(r.key) if e then e.color = nil end end)
        r.swatch:SetPoint("LEFT", 466, 0)

        r.test = MakeButton(r, "Test", 48, ROW_H - 6)
        r.test:SetPoint("LEFT", 496, 0)
        r.test:SetScript("OnClick", function() if r.key then FlashCD.Flash(r.key) end end)

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

        box.rows[i] = r
        return r
    end

    box.SetData = function(self, data, emptyText)
        for i, d in ipairs(data) do
            local r = GetRow(i)
            r.key = d.key
            r.spellID = d.id
            r.itemID = d.itemID
            r.icon:SetTexture(d.icon or 134400)
            r.icon:SetDesaturated(not d.tracked)
            r.text:SetText(d.name or "?")
            if d.tracked then r.text:SetTextColor(1, 1, 1) else r.text:SetTextColor(0.55, 0.55, 0.55) end
            r.cd:SetText(FormatCD(d.cd))
            r.check:Refresh()
            r.mute:SetShown(d.tracked)
            r.sound:SetShown(d.tracked)
            r.swatch:SetShown(d.tracked)
            if d.tracked then
                r.mute:Refresh()
                r.sound:Refresh()
                r.swatch:Refresh()
            end
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
                and (db.spells[d.key] ~= nil or not db.cdOnly or FlashCD.HasCooldown(d.id)) then
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
        if not d.itemID then d.cd = FlashCD.BaseCooldown(d.key) end
        local nameOk = filter == "" or tostring(d.name or ""):lower():find(filter, 1, true)
        local statusOk = view.status == "all"
            or (view.status == "tracked") == d.tracked
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

local shownRows = {}

RefreshList = function()
    if not panel or not spellList then return end
    shownRows = BuildRows()
    local emptyText = view.show == "items" and "No usable items found" or "No matching spells"
    spellList:SetData(shownRows, emptyText)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function UpdatePreview()
    if not preview then return end
    local key
    for k in pairs(DB().spells) do
        if not key or tostring(k) < tostring(key) then key = k end
    end
    if not key and FlashCD.ScanSpellbook then
        local book = FlashCD.ScanSpellbook()
        key = book[1] and book[1].key
    end
    preview:SetShown(key ~= nil)
    if key then preview:Update(key, 64) end
end

local function RefreshAll()
    if not panel then return end
    for _, w in ipairs(refreshers) do w:Refresh() end
    UpdatePreview()
    RefreshList()
end

FlashCD.OnTrackedChanged = function()
    if panel and panel:IsShown() then RefreshList() end
end

FlashCD.OnPositionChanged = function()
    if panel then for _, w in ipairs(refreshers) do w:Refresh() end end
end

-- After a display setting changes: move the flashes, redraw the preview
local function Changed()
    FlashCD.ApplyLayout()
    UpdatePreview()
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local C1, C2, COL_W = 16, 306, 280

local function Slider(parent, label, minV, maxV, step, fmt, key, y, tip)
    local db = DB
    local s = Track(MakeSlider(parent, label, minV, maxV, step, fmt,
        function() return db()[key] end,
        function(v) db()[key] = v; Changed() end, COL_W - 36))
    s:SetPoint("TOPLEFT", 16, y)
    Tip(s, label, tip)
    return s
end

local function Check(parent, label, key, y, tip)
    local db = DB
    local c = Track(MakeCheck(parent, label,
        function() return db()[key] end,
        function(v) db()[key] = v; Changed() end))
    c:SetPoint("TOPLEFT", 10, y)
    Tip(c, label, tip)
    return c
end

local function Dropdown(parent, label, list, key, y, tip, after)
    local db = DB
    local d = Track(MakeDropdown(parent, label, list,
        function() return db()[key] end,
        function(v) db()[key] = v; Changed(); if after then after(v) end end, COL_W - 36))
    d:SetPoint("TOPLEFT", 16, y)
    d:SetTip(label, tip)
    return d
end

local function BuildAppearancePage(page)
    local db = DB

    local icon = MakeSection(page, "Icon", C1, -8, COL_W, 176)
    Slider(icon, "Size", 24, 300, 2, "%d", "size", -44, "How big the flash is, in pixels.")
    Slider(icon, "Opacity", 0.1, 1, 0.05, "%.2f", "alpha", -90, "How see-through the flash is at its brightest.")
    Slider(icon, "Fade-out time (seconds)", 0.3, 3, 0.1, "%.1f", "duration", -136, "How long the flash stays on screen while it fades out.")

    local pv = MakeSection(page, "Preview", C2, -8, COL_W, 176)
    preview = FlashCD.NewPreview(pv)
    preview:SetPoint("CENTER", pv, "CENTER", 0, -4)

    local fx = MakeSection(page, "Effects", C1, -192, COL_W, 180)
    Dropdown(fx, "Animation", FlashCD.ANIMS, "anim", -30,
        "Pop: grows a little, then settles. Zoom: grows as it fades. Bounce: bounces a few times. Slide in: rises into place. Plain fade: just fades.")
    local glow = Check(fx, "Glow border", "glow", -84, "A coloured glow around the icon. Each spell can have its own colour on the Spells & items page.")
    local swatch = Track(MakeSwatch(fx,
        function() return db().glowColor end,
        function(r, g, b) db().glowColor = { r = r, g = g, b = b }; Changed() end,
        function() db().glowColor = { r = 1, g = 0.82, b = 0 }; Changed() end))
    swatch:SetPoint("LEFT", glow.label, "RIGHT", 10, 0)
    Check(fx, "Shine burst", "shine", -112, "A bright star that bursts over the icon as it appears.")

    local tx = MakeSection(page, "Text", C2, -192, COL_W, 180)
    Check(tx, "Show the name under the icon", "showName", -30)
    Check(tx, "Show \"Ready!\" above the icon", "readyText", -56)
    Slider(tx, "Font size", 8, 32, 1, "%d", "fontSize", -100, "Size of the name and the \"Ready!\" text.")
    Dropdown(tx, "Outline", FlashCD.OUTLINES, "fontOutline", -124, "A dark edge around the text, so it reads on bright backgrounds.")
end

local function BuildLayoutPage(page)
    local db = DB
    local w = math.floor(GetScreenWidth() / 2)
    local h = math.floor(GetScreenHeight() / 2)

    local pos = MakeSection(page, "Position", C1, -8, COL_W, 246)
    Slider(pos, "Horizontal position (X)", -w, w, 1, "%d", "x", -44, "Distance from the middle of the screen. You can also drag the flash: click Unlock.")
    Slider(pos, "Vertical position (Y)", -h, h, 1, "%d", "y", -90)
    Slider(pos, "Icons at once (max)", 1, 8, 1, "%d", "maxIcons", -136, "How many flashes can show together when several spells come ready at the same time.")
    Dropdown(pos, "When several show at once", FlashCD.GROWS, "grow", -160, "Which way the row of icons grows from the flash position.")

    local lockBtn = MakeButton(pos, "Unlock (drag)", 120, 22)
    lockBtn:SetPoint("TOPLEFT", 16, -212)
    lockBtn.Refresh = function(self)
        self:SetText(FlashCD.IsUnlocked() and "Lock" or "Unlock (drag)")
    end
    lockBtn:SetScript("OnClick", function()
        FlashCD.SetUnlocked(not FlashCD.IsUnlocked())
        RefreshAll()
    end)
    Track(lockBtn)
    Tip(lockBtn, "Unlock", "Shows a box you can drag to move the flash. Click again to lock it.")

    local centerBtn = MakeButton(pos, "Center", 80, 22)
    centerBtn:SetPoint("LEFT", lockBtn, "RIGHT", 8, 0)
    centerBtn:SetScript("OnClick", function()
        db().point, db().x, db().y = "CENTER", 0, 0
        FlashCD.ApplyLayout()
        RefreshAll()
    end)

    local snd = MakeSection(page, "Sound and button", C2, -8, COL_W, 112)
    Dropdown(snd, "Sound", FlashCD.SOUNDS, "sound", -30, "Played when something flashes (once, even if several flash together).",
        function(v) FlashCD.PlaySound(v, true) end)
    local mm = Track(MakeCheck(snd, "Show the minimap button",
        function() return not db().minimap.hide end,
        function(v)
            db().minimap.hide = not v
            if FlashCD.UpdateMinimapButton then FlashCD.UpdateMinimapButton() end
        end))
    mm:SetPoint("TOPLEFT", 10, -82)
    Tip(mm, "Minimap button", "Left-click opens these options, right-click shows a test flash. Drag it to move it around the minimap.")

    local when = MakeSection(page, "When to flash", C2, -128, COL_W, 126)
    Check(when, "Only while in combat", "combatOnly", -30)
    Check(when, "Skip spells I can't cast now", "usableOnly", -56,
        "Don't flash a spell your current form or stance can't use. Lack of mana, rage or energy doesn't count.")
    Slider(when, "Minimum cooldown (seconds, 0 = off)", 0, 120, 1, "%d", "minCD", -100,
        "Don't flash spells with a shorter cooldown than this.")

    local testBtn = MakeButton(page, "Test flash", 120, 22)
    testBtn:SetPoint("TOPLEFT", C1, -266)
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
    Tip(resetBtn, "Reset to defaults", "Puts every setting on all pages back to its default. Tracked spells and their own settings are kept.")

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", C1, -300)
    note:SetWidth(COL_W * 2 + 10)
    note:SetJustifyH("LEFT")
    note:SetText("Settings and tracked spells are saved per character. A new character starts with the "
        .. "settings of the last character you logged out on.")
end

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
        d:SetPoint("TOPLEFT", x, -6)
        d:SetTip(label, tip)
        return d
    end
    ViewDropdown("Show", ShowChoices, "show", 16, 180, "All spells, one spellbook tab, or items with a \"Use:\" effect.")
    ViewDropdown("Status", {
        { key = "all", label = "Everything" },
        { key = "tracked", label = "Tracked" },
        { key = "untracked", label = "Not tracked" },
    }, "status", 204, 130)
    ViewDropdown("Sort by", {
        { key = "name", label = "Name" },
        { key = "cooldown", label = "Cooldown (longest)" },
        { key = "tracked", label = "Tracked first" },
    }, "sort", 342, 130)

    searchBox = TryTemplate("EditBox", page, "SearchBoxTemplate")
    if not searchBox.Instructions then
        searchBox:Hide()
        searchBox = TryTemplate("EditBox", page, "InputBoxTemplate")
    end
    searchBox:SetSize(106, 20)
    searchBox:SetAutoFocus(false)
    searchBox:SetPoint("TOPLEFT", 484, -24)
    searchBox:HookScript("OnTextChanged", function() RefreshList() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local cdOnly = Track(MakeCheck(page, "Hide spells without a cooldown",
        function() return db().cdOnly end,
        function(v) db().cdOnly = v; RefreshList() end))
    cdOnly:SetPoint("TOPLEFT", 12, -54)

    local auto = Track(MakeCheck(page, "Auto-track new spells",
        function() return db().autoTrack end,
        function(v) db().autoTrack = v end))
    auto:SetPoint("TOPLEFT", 222, -54)
    Tip(auto, "Auto-track new spells", "Spells with a cooldown are ticked when you learn them. A spell you untick stays unticked, also when you learn a new rank.")

    local function SetAll(on)
        for _, d in ipairs(shownRows) do
            if on and DB().spells[d.key] == nil then FlashCD.TrackKey(d.key)
            elseif not on and DB().spells[d.key] ~= nil then FlashCD.UntrackKey(d.key) end
        end
        RefreshList()
    end
    local allOn = MakeButton(page, "Track all", 80, 22)
    allOn:SetPoint("TOPLEFT", 420, -55)
    allOn:SetScript("OnClick", function() SetAll(true) end)
    Tip(allOn, "Track all", "Ticks every spell shown in the list below.")
    local allOff = MakeButton(page, "Untrack all", 86, 22)
    allOff:SetPoint("LEFT", allOn, "RIGHT", 4, 0)
    allOff:SetScript("OnClick", function() SetAll(false) end)
    Tip(allOff, "Untrack all", "Unticks every spell shown in the list below. Their own sound, colour and mute settings are lost.")

    spellList = MakeSpellList(page)
    spellList:SetPoint("TOPLEFT", 14, -100)

    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", spellList, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(LIST_W)
    hint:SetJustifyH("LEFT")
    hint:SetText("Tick a row to track it. Tracked rows can be muted, or given their own sound and glow colour (right-click the colour to reset it).")

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("SPELLS_CHANGED")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    ev:SetScript("OnEvent", function() if panel:IsShown() then RefreshList() end end)
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
    end

    for i, name in ipairs({ "Appearance", "Layout & alerts", "Spells & items" }) do
        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", 0, -86)
        page:SetPoint("BOTTOMRIGHT")
        pages[i] = page

        local tab = MakeButton(panel, name, 130, 24)
        tab:SetPoint("TOPLEFT", 16 + (i - 1) * 136, -52)
        tab:SetScript("OnClick", function() ShowPage(i) end)
        tabs[i] = tab
    end

    BuildAppearancePage(pages[1])
    BuildLayoutPage(pages[2])
    BuildSpellsPage(pages[3])
    ShowPage(1)

    panel:SetScript("OnShow", RefreshAll)

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
