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
local view = { show = "all", status = "all", sort = "name" }
local spellTabs = {}             -- spellbook tab names seen in the last scan

local function DB() return FlashCD.db end

-- The group being edited on the Appearance and Layout pages
local editGroup
local function G() return FlashCD.GetGroup(editGroup) end

-- controls from Widgets.lua
local W = ns.W
local refreshers = W.refreshers
local Track = W.Track
local Tip = W.Tip
local AddBorder = W.AddBorder
local Fill = W.Fill
local MakeButton = W.MakeButton
local MakeFlatButton = W.MakeFlatButton
local MakeCheck = W.MakeCheck
local MakeSlider = W.MakeSlider
local MakeEditBox = W.MakeEditBox
local MakeScroll = W.MakeScroll
local ListOf = W.ListOf
local CloseMenu = W.CloseMenu
local OpenMenu = W.OpenMenu
local MakeDropdown = W.MakeDropdown
local GamepadUI = W.GamepadUI
local MakeSwatch = W.MakeSwatch
local MakeBackdropFrame = W.MakeBackdropFrame
local WindowPad = W.WindowPad
local MakeSection = W.MakeSection
local Place = W.Place
local WoW = W.WoW

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
        hint:SetText("Drag the box, or nudge it with the arrows around it or the arrow keys (Shift: 10 px)")
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
        Tip(b, "Move", "Shows only this group's box: one icon where its flashes start. "
            .. "Drag it, or hover it and use the arrow keys (1 pixel, Shift: 10). Click again when done.")
    else
        Tip(b, "Unlock all", "Shows a box for every group: one icon where its flashes start. "
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

    local when = MakeSection(page, "When to flash", "L", -136, 180)
    Check(when, "Only while in combat", "combatOnly", -30, nil, DB)
    Check(when, "Skip spells I can't cast now", "usableOnly", -56,
        "Don't flash a spell your current form or stance can't use. Lack of mana, rage or energy doesn't count.", DB)
    Slider(when, "Warn before ready (seconds, 0 = off)", 0, 5, 0.5, "%.1f", "preWarn", -146,
        "A grey \"Soon\" flash this many seconds before a cooldown is ready, then the normal flash when it is.", DB)
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
    resetBtn:SetPoint("TOPLEFT", 12, -334)
    resetBtn:SetScript("OnClick", function() confirm:Show() end)
    Tip(resetBtn, "Reset to defaults", "Puts every setting back to its default, and every group's look. "
        .. "Groups, their names, tracked spells and their own settings are kept.")

    local note = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 14, -366)
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

    local formOnly = MakeCheck(settings, "Only while in a form",
        function() return #tracked > 0 and Common("formOnly") == true end,
        function(v) ForTracked(function(e) e.formOnly = v or nil end) AfterChange() end)
    formOnly:SetPoint("TOPLEFT", 10, -134)
    Tip(formOnly, "Only while in a form", "Flash only while you're shapeshifted (bear, cat and so on). "
        .. "For spells like Faerie Fire that only have a cooldown in a form.")

    local glowLabel = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    glowLabel:SetPoint("TOPLEFT", 16, -170)
    glowLabel:SetText("Glow colour")
    local swatch = MakeSwatch(settings,
        function()
            local e = tracked[1] and Entry(tracked[1])
            return (e and e.color) or (tracked[1] and FlashCD.GroupOf(tracked[1]).glowColor) or { r = 1, g = 0.82, b = 0 }
        end,
        function(r, g, b) ForTracked(function(e) e.color = { r = r, g = g, b = b } end) AfterChange() end,
        function() ForTracked(function(e) e.color = nil end) AfterChange() end)
    swatch:SetPoint("TOPLEFT", 16, -186)
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
            formOnly:Refresh()
            swatch:Refresh()
        end
    end
    d.Refresh = function() OnSelectionChanged() end
    return Track(d)
end

local spellEvents   -- refreshes the list when spells or bags change (made once)

---------------------------------------------------------------------------
-- Asking "are you sure?" in a frame of FlashCD's own (see BuildAlertsPage
-- for why the game's StaticPopup dialogs aren't used)
---------------------------------------------------------------------------
local confirmFrame

local function AskConfirm(text, onYes)
    if not confirmFrame then
        local c = MakeBackdropFrame(panel)
        c:SetSize(340, 130)
        c:SetPoint("CENTER", panel, "CENTER", 0, 40)
        c:SetFrameStrata("FULLSCREEN_DIALOG")
        c:SetToplevel(true)
        c:EnableMouse(true)
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        c.text:SetPoint("TOP", 0, -20)
        c.text:SetWidth(300)
        local yes = MakeButton(c, YES or "Yes", 100, 22, true)
        yes:SetPoint("BOTTOMRIGHT", c, "BOTTOM", -6, 16)
        yes:SetScript("OnClick", function() c:Hide() if c.onYes then c.onYes() end end)
        local no = MakeButton(c, NO or "No", 100, 22)
        no:SetPoint("BOTTOMLEFT", c, "BOTTOM", 6, 16)
        no:SetScript("OnClick", function() c:Hide() end)
        panel:HookScript("OnHide", function() c:Hide() end)
        confirmFrame = c
    end
    confirmFrame.text:SetText(text)
    confirmFrame.onYes = onYes
    confirmFrame:Show()
end

---------------------------------------------------------------------------
-- Recent flashes: what flashed, what didn't and why
---------------------------------------------------------------------------
local LOG_COLOURS = {
    flash = { 0.4, 1, 0.4 },
    skip  = { 1, 0.6, 0.2 },
    soon  = { 1, 0.85, 0.3 },
    learn = { 0.45, 0.8, 1 },
}

local function BuildLogPage(page)
    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Recent flashes")
    local sub = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText("What flashed, what didn't and why, newest first. Kept until you log out.")
    local clear = MakeFlatButton(page, "Clear", 70, 22)
    clear:SetPoint("TOPRIGHT", -12, -14)

    local box = CreateFrame("Frame", nil, page)
    box:SetPoint("TOPLEFT", 12, -56)
    box:SetPoint("BOTTOMRIGHT", -12, 12)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)
    local scroll = MakeScroll(box, 22)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(500, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) if type(w) == "number" and w > 0 then content:SetWidth(w) end end)
    local empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetText("Nothing yet. Flashes show up here as they happen.")

    local rows = {}
    local function Row(i)
        local r = rows[i]
        if r then return r end
        r = CreateFrame("Frame", nil, content)
        r:SetHeight(22)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
        r:SetPoint("RIGHT", content, "RIGHT")
        r.time = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.time:SetPoint("LEFT", 6, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 66, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("LEFT", 92, 0)
        r.name:SetWidth(170)
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 270, 0)
        r.text:SetPoint("RIGHT", -6, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        rows[i] = r
        return r
    end

    local function Refresh()
        local log = FlashCD.log
        for i, e in ipairs(log) do
            local r = Row(i)
            r.time:SetText(e.time)
            r.icon:SetTexture(FlashCD.KeyIcon(e.key) or 134400)
            r.name:SetText(tostring(FlashCD.KeyName(e.key)))
            local c = LOG_COLOURS[e.kind] or { 1, 1, 1 }
            r.text:SetText(e.text)
            r.text:SetTextColor(c[1], c[2], c[3])
            r:Show()
        end
        for i = #log + 1, #rows do rows[i]:Hide() end
        content:SetHeight(math.max(1, #log * 22))
        empty:SetShown(#log == 0)
    end
    clear:SetScript("OnClick", function() wipe(FlashCD.log) Refresh() end)
    page:SetScript("OnShow", Refresh)
    FlashCD.OnLog = function() if page:IsVisible() then Refresh() end end
    Track({ Refresh = function() if page:IsShown() then Refresh() end end })
end

---------------------------------------------------------------------------
-- Profiles: copy from another character, export and import as text
---------------------------------------------------------------------------
local function BuildProfilesPage(page)
    local copy = MakeSection(page, "Copy from another character", "F", -12, 104)
    local chosen
    local chars = MakeDropdown(copy, "Character", function()
            local l = FlashCD.Characters()
            if #l == 0 then l = { { key = nil, label = "No other characters yet" } } end
            return l
        end,
        function() return chosen end,
        function(v) chosen = v end)
    Place(chars, copy, "L", -30)
    chars:SetTip("Character", "Every character you log in with saves its FlashCD settings here, so the others can copy them.")
    local copySpells = false
    local copyCheck = MakeCheck(copy, "Also copy tracked spells",
        function() return copySpells end, function(v) copySpells = v end)
    copyCheck:SetPoint("TOPLEFT", copy, "TOP", 10, -44)
    Tip(copyCheck, "Also copy tracked spells", "Which spells are tracked, in which group, with their own settings. Best for a character of the same class.")
    local copyBtn = MakeButton(copy, "Copy", 90, 22, true)
    copyBtn:SetPoint("TOPLEFT", 16, -76)
    local copyNote = copy:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    copyNote:SetPoint("LEFT", copyBtn, "RIGHT", 10, 0)
    copyBtn:SetScript("OnClick", function()
        if not chosen then copyNote:SetText("Pick a character first.") return end
        AskConfirm("Replace this character's FlashCD settings with " .. chosen .. "'s"
            .. (copySpells and " (including tracked spells)" or "") .. "?", function()
            if FlashCD.CopyFromCharacter(chosen, copySpells) then
                print("|cff33ccffFlashCD|r: settings copied from " .. chosen .. ".")
            end
        end)
    end)

    local ex = MakeSection(page, "Export (share with others)", "F", -128, 112)
    local exSpells = true
    local exCheck = MakeCheck(ex, "Include tracked spells",
        function() return exSpells end, function(v) exSpells = v end)
    exCheck:SetPoint("TOPLEFT", 10, -30)
    local exBtn = MakeButton(ex, "Export", 90, 22, true)
    exBtn:SetPoint("TOPLEFT", ex, "TOP", 10, -30)
    local exBox = MakeEditBox(ex, 300, 24)
    exBox:SetMaxLetters(0)
    if exBox.SetMaxBytes then exBox:SetMaxBytes(0) end
    exBox:SetPoint("TOPLEFT", 16, -62)
    exBox:SetPoint("RIGHT", -16, 0)
    local exNote = ex:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    exNote:SetPoint("TOPLEFT", exBox, "BOTTOMLEFT", 2, -4)
    exNote:SetText("Click Export, then press Ctrl+C to copy the text and send it to someone.")
    exBtn:SetScript("OnClick", function()
        exBox:SetText(FlashCD.ExportString(exSpells))
        exBox:SetFocus()
        exBox:HighlightText()
        exNote:SetText("Copied text ready: press Ctrl+C now.")
    end)

    local im = MakeSection(page, "Import", "F", -248, 124)
    local imBox = MakeEditBox(im, 300, 24)
    imBox:SetMaxLetters(0)
    if imBox.SetMaxBytes then imBox:SetMaxBytes(0) end
    imBox:SetPoint("TOPLEFT", 16, -32)
    imBox:SetPoint("RIGHT", -16, 0)
    imBox:SetPlaceholder("Paste a FlashCD export here (Ctrl+V)")
    local imSpells = true
    local imCheck = MakeCheck(im, "Also import tracked spells (if the text has them)",
        function() return imSpells end, function(v) imSpells = v end)
    imCheck:SetPoint("TOPLEFT", 10, -62)
    local imBtn = MakeButton(im, "Import", 90, 22, true)
    imBtn:SetPoint("TOPLEFT", 16, -92)
    local imNote = im:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    imNote:SetPoint("LEFT", imBtn, "RIGHT", 10, 0)
    imNote:SetPoint("RIGHT", -16, 0)
    imNote:SetJustifyH("LEFT")
    imBtn:SetScript("OnClick", function()
        local data, err = FlashCD.ParseExport(imBox:GetText())
        if not data then
            imNote:SetTextColor(1, 0.4, 0.3)
            imNote:SetText(err)
            return
        end
        imNote:SetText("")
        local spells = imSpells and type(data.spells) == "table"
        AskConfirm("Replace this character's FlashCD settings with the imported ones"
            .. (spells and " (including tracked spells)" or "") .. "?", function()
            if FlashCD.ApplyProfile(data, spells) then
                print("|cff33ccffFlashCD|r: settings imported.")
            end
        end)
    end)
end

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
    for i, e in ipairs({ { "spells", "Spells & items" }, { "alerts", "Alerts & moving" },
                         { "log", "Recent flashes" }, { "profiles", "Profiles & sharing" } }) do
        local b = SideButton(side, e[2])
        b:SetPoint("TOPLEFT", 8, -24 - (i - 1) * 26)
        b:SetScript("OnClick", function() ShowPage(e[1]) end)
        b.page = e[1]
        navs[#navs + 1] = b
    end

    Heading("GROUPS", -140)
    for i = 1, FlashCD.MAX_GROUPS do
        local b = SideButton(side)
        b:SetPoint("TOPLEFT", 8, -154 - (i - 1) * 26)
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
        new:SetPoint("TOPLEFT", 14, -158 - #groups * 26)
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
    for _, name in ipairs({ "group", "spells", "alerts", "log", "profiles" }) do
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
    BuildLogPage(pages.log)
    BuildProfilesPage(pages.profiles)
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
    W.ResetMenu()
    if movingBar then movingBar:Hide() end
    movingBar = nil
    wipe(refreshers)
    wipe(groupButtons)
    confirmFrame = nil
    preview, spellList, searchBox = nil, nil, nil
    RefreshSidebar, OnSelectionChanged = nil, nil
    panel = nil
    BuildWindow(currentPage)
    if wasShown then panel:Show() end
    UpdateMovingBar()
end

-- After settings were copied or imported: show them (and their theme)
FlashCD.OnProfileApplied = function()
    editGroup = nil
    RebuildWindow()
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
