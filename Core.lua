-- FlashCD - Core.lua
-- Shows a spell's (or item's) icon on screen for a moment, fading out, when
-- something you track comes off cooldown.
--
-- Cooldown times can be hidden ("secret") while restricted (e.g. in combat),
-- but C_Spell.GetSpellCooldown's isActive / isOnGCD flags stay readable, so
-- "on cooldown" = isActive and not just the global cooldown. Any value that
-- is secret is treated as unknown; nothing is guessed from it.
--
-- Tracked keys: a spell name (every rank counts as the same spell), or
-- "item:<itemID>" for items.

local ADDON, ns = ...
local FlashCD = {}
ns.FlashCD = FlashCD
_G.FlashCD = FlashCD

local GCD_MAX = 1.6
local NO_BASE_MIN = 3.2   -- shortest real cooldown accepted when the base cooldown is unknown

-- per-character settings; FlashCD.db points at the active table
local DEFAULTS = {
    spells     = {},      -- [key] = { muted, sound, color, group = group id, formOnly }
    known      = {},      -- [spell name] = true for every spell already seen
    removed    = {},      -- [key] = true: unticked by you, never auto-tracked again
    learnedCD  = {},      -- [spell name] = seconds: cooldowns the game doesn't report
    skippedNoCD = {},     -- [spell name] = true: not auto-tracked, it had no cooldown then
    overrides  = {},      -- [spell name] = spell ID that replaces it in a form (seen once, kept)
    -- groups = { group, ... } (see GROUP_DEFAULTS), nextGroup = next group id
    sound      = "none",
    combatOnly = false,
    minCD      = 0,       -- seconds; shorter cooldowns don't flash
    preWarn    = 0,       -- seconds before ready to show a "Soon" flash (0 = off)
    usableOnly = true,    -- skip spells that can't be cast now (wrong form etc.)
    autoTrack  = true,
    cdOnly     = true,
    minimap    = { hide = false, angle = 215 },
    grid       = true,    -- show a grid while groups are unlocked
    snap       = true,    -- snap dragged groups to the grid
    window     = {},      -- the settings window's size and place
    theme      = "modern", -- look of the settings window: modern | wow
}

-- each display group: where it shows and how it looks
-- Each group gets a colour of its own (shown in the settings and on its
-- move box), picked from this list by group id
local GROUP_COLOURS = {
    { r = 1,    g = 0.82, b = 0 },
    { r = 0.35, g = 0.75, b = 1 },
    { r = 0.45, g = 1,    b = 0.45 },
    { r = 1,    g = 0.45, b = 0.3 },
    { r = 0.8,  g = 0.5,  b = 1 },
    { r = 1,    g = 0.55, b = 0.85 },
    { r = 0.3,  g = 1,    b = 0.9 },
    { r = 1,    g = 0.65, b = 0.2 },
    { r = 0.6,  g = 0.65, b = 1 },
    { r = 0.85, g = 0.85, b = 0.85 },
}
local function GroupColour(id)
    local c = GROUP_COLOURS[(id - 1) % #GROUP_COLOURS + 1]
    return { r = c.r, g = c.g, b = c.b }
end

local GROUP_DEFAULTS = {
    name       = "Main",
    size       = 96,
    point      = "CENTER",
    x          = 0,
    y          = 120,
    duration   = 1.0,     -- seconds the flash takes to fade out
    alpha      = 1.0,
    maxIcons   = 4,       -- how many flashes can show at once
    anim       = "pop",   -- pop | zoom | bounce | slide | plain
    showName   = true,
    glow       = true,
    glowColor  = { r = 1, g = 0.82, b = 0 },
    grow       = "center", -- center | right | left | up | down
    shine      = true,     -- star burst over the icon as it appears
    readyText  = false,    -- "Ready!" above the icon
    fontSize   = 16,
    fontOutline = "outline", -- none | outline | thick
}

-- settings copied to new characters
local TEMPLATE_KEYS = {
    "groups", "nextGroup", "sound", "combatOnly", "minCD", "usableOnly",
    "autoTrack", "cdOnly", "minimap", "grid", "snap", "theme", "preWarn",
}

FlashCD.SOUNDS = {
    { key = "none",  label = "None" },
    { key = "raid",  label = "Raid Warning",  kit = "RAID_WARNING",          id = 8959 },
    { key = "ready", label = "Ready Check",   kit = "READY_CHECK",           id = 8960 },
    { key = "alarm", label = "Alarm Clock",   kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
    { key = "ping",  label = "Map Ping",      kit = "MAP_PING",              id = 3175 },
    { key = "bell",  label = "Auction Bell",  kit = "AUCTION_WINDOW_OPEN",   id = 5274 },
    { key = "tick",  label = "Click",         kit = "IG_MAINMENU_OPTION_CHECKBOX_ON", id = 856 },
}

FlashCD.ANIMS = {
    { key = "pop",   label = "Pop" },
    { key = "zoom",  label = "Zoom" },
    { key = "bounce", label = "Bounce" },
    { key = "slide", label = "Slide in" },
    { key = "plain", label = "Plain fade" },
}

FlashCD.GROWS = {
    { key = "center", label = "Centred row" },
    { key = "right",  label = "Grow right" },
    { key = "left",   label = "Grow left" },
    { key = "up",     label = "Grow up" },
    { key = "down",   label = "Grow down" },
}

FlashCD.OUTLINES = {
    { key = "none",    label = "No outline" },
    { key = "outline", label = "Outline" },
    { key = "thick",   label = "Thick outline" },
}
local OUTLINE_FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }

local function IsSecret(v)
    if type(issecretvalue) ~= "function" then return false end
    local ok, r = pcall(issecretvalue, v)
    return ok and r == true
end
FlashCD.IsSecret = IsSecret

local function CopyTable(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = CopyTable(v) end
    return c
end

---------------------------------------------------------------------------
-- Keys: spell names and "item:<id>"
---------------------------------------------------------------------------
function FlashCD.ItemID(key)
    return type(key) == "string" and tonumber(key:match("^item:(%d+)$")) or nil
end
local ItemID = FlashCD.ItemID

function FlashCD.GetSpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- Spellbook IDs by name (highest rank), filled by every spellbook scan.
-- Spells are looked up by these IDs, not by name: the game reads a name like
-- "Faerie Fire (Feral)" as "Faerie Fire" rank "Feral", which finds the wrong spell.
local idByName = {}

-- The spell that replaces `id` right now (e.g. a feral version in bear
-- form), or nil when it isn't replaced
local function OverrideOf(id)
    local fn = (C_Spell and C_Spell.GetOverrideSpell) or FindSpellOverrideByID
    if not fn or type(id) ~= "number" then return nil end
    local ok, o = pcall(fn, id)
    if ok and type(o) == "number" and not IsSecret(o) and o ~= 0 and o ~= id then return o end
end
FlashCD.OverrideOf = OverrideOf

function FlashCD.RememberSpell(name, id)
    if not (name and id) then return end
    idByName[name] = id
    -- a form version can have a cooldown the normal one hasn't: once seen,
    -- keep using it, also out of the form
    local o = OverrideOf(id)
    if o and FlashCD.db then FlashCD.db.overrides[name] = o end
end

-- What to pass to the spell API for a tracked key: its form version or its
-- spellbook ID when known, else the name
local function SpellRef(key)
    local db = FlashCD.db
    return (db and db.overrides[key]) or idByName[key] or key
end
FlashCD.SpellRef = SpellRef

function FlashCD.GetSpellID(name)
    local db = FlashCD.db
    if db and db.overrides[name] then return db.overrides[name] end
    if idByName[name] then return idByName[name] end
    if type(name) == "number" then return name end
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(name)
        return info and info.spellID
    end
    if GetSpellInfo then return (select(7, GetSpellInfo(name))) end
end

function FlashCD.GetSpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
end

function FlashCD.KeyName(key)
    local item = ItemID(key)
    if item then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
        if not name and GetItemInfo then name = GetItemInfo(item) end
        if not name and C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(item)
        end
        return name or ("Item " .. item)
    end
    if type(key) == "string" then return key end   -- spell keys are names
    return FlashCD.GetSpellName(key) or tostring(key)
end

function FlashCD.KeyIcon(key)
    local item = ItemID(key)
    if item then
        if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(item) end
        if GetItemIcon then return GetItemIcon(item) end
        return nil
    end
    return FlashCD.GetSpellIcon(SpellRef(key))
end

function FlashCD.SoundByKey(key)
    for _, s in ipairs(FlashCD.SOUNDS) do
        if s.key == key then return s end
    end
end

local lastSoundAt = 0
function FlashCD.PlaySound(key, force)
    local s = FlashCD.SoundByKey(key)
    if not s or s.key == "none" then return end
    local now = GetTime()
    if not force and now - lastSoundAt < 0.25 then return end   -- one sound per burst
    lastSoundAt = now
    local id = (SOUNDKIT and s.kit and SOUNDKIT[s.kit]) or s.id
    if id then pcall(PlaySound, id, "Master") end
end

---------------------------------------------------------------------------
-- Cooldown reading
---------------------------------------------------------------------------
local readyAt = {}   -- items: when the last readable cooldown ends

-- true/false = on cooldown or not (nil = unknown); 2nd value: cooldown length when readable
local function SpellCooldown(key)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, SpellRef(key))
        if not ok or type(info) ~= "table" then return nil end
        local s, d = info.startTime, info.duration
        if IsSecret(s) or IsSecret(d) or type(s) ~= "number" or type(d) ~= "number" then
            s, d = nil, nil
        end
        local active, onGCD = info.isActive, info.isOnGCD
        if active ~= nil and not IsSecret(active) then
            if active ~= true then return false end
            if onGCD ~= nil and not IsSecret(onGCD) then
                if onGCD == true then return false end
                if d and d <= GCD_MAX then return false end
                return true, d
            end
        end
        if not s then return nil end
        local cd = s > 0 and d > GCD_MAX
        return cd, cd and d or nil
    elseif GetSpellCooldown then
        local s, d = GetSpellCooldown(SpellRef(key))
        if type(s) ~= "number" or type(d) ~= "number" then return nil end
        local cd = s > 0 and d > GCD_MAX
        return cd, cd and d or nil
    end
end

local function ItemCooldown(key, item)
    local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not fn then return nil end
    local ok, s, d = pcall(fn, item)
    if not ok or IsSecret(s) or IsSecret(d) or type(s) ~= "number" or type(d) ~= "number" then
        -- hidden right now: fall back on the end time seen while it was readable
        local r = readyAt[key]
        if r then return GetTime() < r end
        return nil
    end
    local cd = s > 0 and d > GCD_MAX
    readyAt[key] = cd and (s + d) or nil
    return cd, cd and d or nil
end

local function IsOnCooldown(key)
    local item = ItemID(key)
    if item then return ItemCooldown(key, item) end
    return SpellCooldown(key)
end
FlashCD.IsOnCooldown = IsOnCooldown

local function BaseCooldown(key)
    if ItemID(key) or not GetSpellBaseCooldown then return nil end
    local id = FlashCD.GetSpellID(key)
    if not id then return nil end
    local ok, ms = pcall(GetSpellBaseCooldown, id)
    if ok and not IsSecret(ms) and type(ms) == "number" and ms > 0 then return ms / 1000 end
end
FlashCD.BaseCooldown = BaseCooldown

-- Cooldown length: the game's base cooldown, or one FlashCD saw itself
local function CooldownLength(key)
    return BaseCooldown(key) or (FlashCD.db and FlashCD.db.learnedCD[key])
end
FlashCD.CooldownLength = CooldownLength

---------------------------------------------------------------------------
-- Groups: each has its own spot on screen and its own look
---------------------------------------------------------------------------
function FlashCD.Groups() return FlashCD.db.groups end

-- The group with this id; the first group when there is no such group
function FlashCD.GetGroup(id)
    local groups = FlashCD.db.groups
    for _, g in ipairs(groups) do
        if g.id == id then return g end
    end
    return groups[1]
end

-- The group with this id, or nil
function FlashCD.GetGroupByID(id)
    for _, g in ipairs(FlashCD.db.groups) do
        if g.id == id then return g end
    end
end

-- The group a tracked key flashes in
function FlashCD.GroupOf(key)
    local e = FlashCD.db.spells[key]
    return FlashCD.GetGroup(type(e) == "table" and e.group or nil)
end

FlashCD.MAX_GROUPS = 10

-- New group with the look of `from` (or the defaults), placed below the last
-- group. Returns its id, or nil when there are already MAX_GROUPS groups.
function FlashCD.AddGroup(from)
    local db = FlashCD.db
    if #db.groups >= FlashCD.MAX_GROUPS then return nil end
    local last = db.groups[#db.groups]
    local g = CopyTable(from or GROUP_DEFAULTS)
    g.id = db.nextGroup
    db.nextGroup = db.nextGroup + 1
    g.name = from and (from.name .. " copy") or ("Group " .. g.id)
    g.color = GroupColour(g.id)
    g.point = "CENTER"
    g.x = last and last.x or 0
    g.y = (last and last.y or 120) - (last and last.size or 96) / 2 - g.size / 2 - 50
    db.groups[#db.groups + 1] = g
    FlashCD.ApplyLayout()
    return g.id
end

-- Delete a group (never the last one); its spells move to the first group
function FlashCD.DeleteGroup(id)
    local db = FlashCD.db
    if #db.groups <= 1 then return end
    for i, g in ipairs(db.groups) do
        if g.id == id then table.remove(db.groups, i) break end
    end
    for _, e in pairs(db.spells) do
        if type(e) == "table" and e.group == id then e.group = nil end
    end
    FlashCD.ApplyLayout()
end

-- How many tracked spells flash in group g
-- Move a group one place up (-1) or down (+1) in the list
function FlashCD.MoveGroup(id, dir)
    local groups = FlashCD.db.groups
    local i
    for n, g in ipairs(groups) do if g.id == id then i = n end end
    local j = i and i + dir
    if not j or j < 1 or j > #groups then return false end
    -- spells without a group follow the first group: keep them where they are
    local first = groups[1].id
    for _, e in pairs(FlashCD.db.spells) do
        if type(e) == "table" and e.group == nil then e.group = first end
    end
    groups[i], groups[j] = groups[j], groups[i]
    FlashCD.ApplyLayout()
    return true
end

function FlashCD.CountInGroup(g)
    local n = 0
    for key in pairs(FlashCD.db.spells) do
        if FlashCD.GroupOf(key) == g then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Flash display: per group an anchor (the spot the icons are placed from)
-- and a row of icons. While unlocked, a mover box per group shows the
-- group's full size (all its icons) and can be dragged or nudged.
---------------------------------------------------------------------------
local displays = {}   -- [group id] = { anchor, mover, active = {icon frames}, g = group }
local pool = {}
local GAP = 8
local SNAP = 25       -- grid spacing in pixels (from the middle of the screen)

-- Where icon i (1-based) of n sits, relative to the anchor's centre
local function IconOffset(g, i, n)
    local size, k = g.size, i - 1
    local textH = g.fontSize + 6
    local vstep = size + GAP + (g.showName and textH or 0) + (g.readyText and textH or 0)
    if g.grow == "right" then return k * (size + GAP), 0
    elseif g.grow == "left" then return -k * (size + GAP), 0
    elseif g.grow == "up" then return 0, k * vstep
    elseif g.grow == "down" then return 0, -k * vstep end
    local total = n * size + (n - 1) * GAP
    return -total / 2 + size / 2 + k * (size + GAP), 0
end

-- Save a group's position from where its anchor should be (screen offsets
-- from the middle), snapped to the grid when that's on
local function SetGroupPosition(g, x, y, snap)
    if snap then
        x = math.floor(x / SNAP + 0.5) * SNAP
        y = math.floor(y / SNAP + 0.5) * SNAP
    end
    g.point = "CENTER"
    g.x = math.floor(x + 0.5)
    g.y = math.floor(y + 0.5)
    FlashCD.ApplyLayout()
    if FlashCD.OnPositionChanged then FlashCD.OnPositionChanged() end
end

local function MoverDragStop(self)
    self:StopMovingOrSizing()
    local d = self.display
    local cx, cy = self:GetCenter()
    local ux, uy = UIParent:GetCenter()
    -- the mover's centre is offset from the anchor by the footprint's centre
    SetGroupPosition(d.g, cx - ux - self.offX, cy - uy - self.offY, FlashCD.db.snap)
end

-- Arrow keys nudge the group under the mouse: 1 pixel, 10 with Shift
local NUDGE = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local function MoverKeyDown(self, key)
    local step = NUDGE[key]
    if self.SetPropagateKeyboardInput and not InCombatLockdown() then
        pcall(self.SetPropagateKeyboardInput, self, not step)
    end
    if not step then return end
    local n = IsShiftKeyDown() and 10 or 1
    local g = self.display.g
    SetGroupPosition(g, g.x + step[1] * n, g.y + step[2] * n, false)
end

local function MoverEnter(self)
    if not InCombatLockdown() then self:EnableKeyboard(true) end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.display.g.name, 1, 1, 1)
    GameTooltip:AddLine("Drag to move. Arrow keys: 1 pixel (Shift: 10).", nil, nil, nil, true)
    GameTooltip:AddLine("Scroll: icon size, 2 pixels (Shift: 10).", nil, nil, nil, true)
    GameTooltip:Show()
end

-- Scroll over the box: the group's icon size (the Size slider's range)
local SIZE_MIN, SIZE_MAX = 24, 300
local function MoverWheel(self, delta)
    local g = self.display.g
    local step = IsShiftKeyDown() and 10 or 2
    g.size = math.max(SIZE_MIN, math.min(SIZE_MAX, g.size + (delta > 0 and step or -step)))
    FlashCD.ApplyLayout()
    if FlashCD.OnPositionChanged then FlashCD.OnPositionChanged() end
end

local function MoverLeave(self)
    if not InCombatLockdown() then self:EnableKeyboard(false) end
    GameTooltip:Hide()
end

local function GetDisplay(g)
    local d = displays[g.id]
    if d then d.g = g return d end

    local a = CreateFrame("Frame", nil, UIParent)
    a:SetSize(1, 1)

    local m = CreateFrame("Frame", "FlashCDMover" .. g.id, UIParent)
    m:SetClampedToScreen(true)
    m:SetMovable(true)
    m:RegisterForDrag("LeftButton")
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:Hide()
    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetPoint("TOPLEFT", -4, 4)
    m.bg:SetPoint("BOTTOMRIGHT", 4, -4)
    m.bg:SetColorTexture(0, 0.6, 1, 0.3)
    m.ghosts = {}
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    m.label:SetPoint("BOTTOM", m, "TOP", 0, 24)
    m:SetScript("OnDragStart", function(self) self:StartMoving() end)
    m:SetScript("OnDragStop", MoverDragStop)
    m:SetScript("OnKeyDown", MoverKeyDown)
    m:EnableMouseWheel(true)
    m:SetScript("OnMouseWheel", MoverWheel)
    m:SetScript("OnEnter", MoverEnter)
    m:SetScript("OnLeave", MoverLeave)

    -- arrow buttons around the box: nudge 1 pixel (Shift: 10). Clicks work in
    -- combat too, where the game doesn't let addons read the arrow keys.
    local BS = "Interface\\Buttons\\"
    for _, a in ipairs({
        { "UP",    "BOTTOM", "TOP",    0, 2,  BS .. "UI-ScrollBar-ScrollUpButton-" },
        { "DOWN",  "TOP",    "BOTTOM", 0, -2, BS .. "UI-ScrollBar-ScrollDownButton-" },
        { "LEFT",  "RIGHT",  "LEFT",   -2, 0, BS .. "UI-SpellbookIcon-PrevPage-" },
        { "RIGHT", "LEFT",   "RIGHT",  2, 0,  BS .. "UI-SpellbookIcon-NextPage-" },
    }) do
        local b = CreateFrame("Button", nil, m)
        b:SetSize(20, 20)
        b:SetPoint(a[2], m, a[3], a[4], a[5])
        b:SetNormalTexture(a[6] .. "Up")
        b:SetPushedTexture(a[6] .. "Down")
        b:SetHighlightTexture(BS .. "ButtonHilight-Square", "ADD")
        b:SetScript("OnClick", function() MoverKeyDown(m, a[1]) end)
        m["arrow" .. a[1]] = b
    end

    d = { anchor = a, mover = m, active = {}, g = g }
    m.display = d
    displays[g.id] = d
    return d
end

-- Size the mover to one icon of the group, at the group's position, and
-- show a placeholder icon in it
local function LayoutMover(d)
    local g, m = d.g, d.mover
    local n = 1
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, n do
        local x, y = IconOffset(g, i, n)
        minX, maxX = math.min(minX, x), math.max(maxX, x)
        minY, maxY = math.min(minY, y), math.max(maxY, y)
    end
    m.offX, m.offY = (minX + maxX) / 2, (minY + maxY) / 2
    m:SetSize(maxX - minX + g.size, maxY - minY + g.size)
    m:ClearAllPoints()
    m:SetPoint("CENTER", d.anchor, "CENTER", m.offX, m.offY)
    for i = 1, math.max(n, #m.ghosts) do
        local t = m.ghosts[i]
        if i <= n then
            if not t then
                t = m:CreateTexture(nil, "ARTWORK")
                t:SetTexture(134400)   -- question mark icon
                t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                m.ghosts[i] = t
            end
            local x, y = IconOffset(g, i, n)
            t:SetSize(g.size, g.size)
            t:ClearAllPoints()
            t:SetPoint("CENTER", m, "CENTER", x - m.offX, y - m.offY)
            t:SetAlpha(i == 1 and 0.9 or 0.45)
            t:Show()
        elseif t then
            t:Hide()
        end
    end
    m.label:SetText(g.name .. "  |cffaaaaaa" .. g.size .. " px|r")
    local c = g.color or GROUP_COLOURS[1]
    m.bg:SetColorTexture(c.r, c.g, c.b, 0.3)
    m.label:SetTextColor(c.r, c.g, c.b)
end

---------------------------------------------------------------------------
-- Grid shown while unlocked: a line every SNAP pixels from the middle,
-- brighter every 4th, and the centre lines in red
---------------------------------------------------------------------------
local grid
local function ShowGrid(on)
    if not on then
        if grid then grid:Hide() end
        return
    end
    if not grid then
        grid = CreateFrame("Frame", nil, UIParent)
        grid:SetAllPoints(UIParent)
        grid:SetFrameStrata("BACKGROUND")
        grid.lines = {}
    end
    for _, t in ipairs(grid.lines) do t:Hide() end
    local w, h = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    local used = 0
    local function Line(vertical, offset)
        used = used + 1
        local t = grid.lines[used]
        if not t then
            t = grid:CreateTexture(nil, "BACKGROUND")
            grid.lines[used] = t
        end
        local idx = math.floor(math.abs(offset) / SNAP + 0.5)
        if offset == 0 then t:SetColorTexture(1, 0.2, 0.2, 0.6)
        elseif idx % 4 == 0 then t:SetColorTexture(1, 1, 1, 0.18)
        else t:SetColorTexture(1, 1, 1, 0.07) end
        t:ClearAllPoints()
        if vertical then
            t:SetSize(1, h)
            t:SetPoint("CENTER", grid, "CENTER", offset, 0)
        else
            t:SetSize(w, 1)
            t:SetPoint("CENTER", grid, "CENTER", 0, offset)
        end
        t:Show()
    end
    for i = 0, math.floor(w / 2 / SNAP) do
        Line(true, i * SNAP)
        if i > 0 then Line(true, -i * SNAP) end
    end
    for i = 0, math.floor(h / 2 / SNAP) do
        Line(false, i * SNAP)
        if i > 0 then Line(false, -i * SNAP) end
    end
    grid:Show()
end

local function Layout(d)
    local g, n = d.g, #d.active
    local vertical = g.grow == "up" or g.grow == "down"
    for i, f in ipairs(d.active) do
        local x, y = IconOffset(g, i, n)
        f:SetSize(g.size, g.size)
        f.name:SetWidth(vertical and g.size * 3 or g.size + GAP)
        f:ClearAllPoints()
        f:SetPoint("CENTER", d.anchor, "CENTER", x, y)
    end
end

local function Release(f, skipLayout)
    f:Hide()
    local d = f.d
    if d then
        for i, a in ipairs(d.active) do
            if a == f then table.remove(d.active, i) break end
        end
        f.d = false
        if not skipLayout then Layout(d) end
    end
    pool[#pool + 1] = f
end

-- Draw one frame of the flash; p runs from 0 (appears) to 1 (gone)
local function Animate(f, p)
    local g = f.g
    local size = f.fixedSize or g.size
    local sc, dy, fadeIn = 1, 0, 1
    if g.anim == "pop" then
        sc = 1 + 0.25 * math.max(0, 1 - p * 4)
    elseif g.anim == "zoom" then
        sc = 1 + 0.6 * p
    elseif g.anim == "bounce" then
        sc = 1 + 0.3 * math.abs(math.sin(p * math.pi * 3)) * (1 - p) ^ 2
    elseif g.anim == "slide" then
        local q = math.max(0, 1 - p * 5)
        dy = -size * 0.6 * q * q
        fadeIn = math.min(1, p * 6)
    end
    local s = size * sc
    f.icon:SetSize(s, s)
    f.icon:SetPoint("CENTER", f, "CENTER", 0, dy)
    f.glow:SetSize(s * 1.8, s * 1.8)
    f:SetAlpha(g.alpha * (1 - p) * fadeIn)

    -- shine: a star burst that grows, turns and fades over the first part
    local q = p / 0.45
    if f.shineOn and q < 1 then
        local ss = size * (0.6 + 1.6 * q)
        f.shine:SetSize(ss, ss)
        f.shine:SetAlpha(1 - q)
        if f.shine.SetRotation then f.shine:SetRotation(q * 1.6) end
        f.shine:Show()
    else
        f.shine:Hide()
    end
end

local function IconOnUpdate(self, elapsed)
    local dur = self.g.duration
    self.t = self.t + elapsed
    if self.loop then
        -- options preview: play, pause briefly, repeat
        if self.t >= dur + 0.6 then self.t = 0 end
        if self.t >= dur then
            self:SetAlpha(0)
            self.shine:Hide()
            return
        end
    elseif self.t >= dur then
        Release(self)
        return
    end
    Animate(self, self.t / dur)
end

local function ApplyFont(fs, size, outline)
    local path = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    pcall(fs.SetFont, fs, path, size, OUTLINE_FLAGS[outline] or "")
end

local function NewIcon(parent)
    local f = CreateFrame("Frame", nil, parent or UIParent)
    if not parent then f:SetFrameStrata("HIGH") end
    f:SetSize(64, 64)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER")
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER", f.icon, "CENTER")
    f.shine = f:CreateTexture(nil, "OVERLAY")
    f.shine:SetTexture("Interface\\Cooldown\\star4")
    f.shine:SetBlendMode("ADD")
    f.shine:SetPoint("CENTER", f.icon, "CENTER")
    f.shine:Hide()
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.name:SetPoint("TOP", f, "BOTTOM", 0, -4)
    f.name:SetWordWrap(false)
    f.ready = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.ready:SetPoint("BOTTOM", f, "TOP", 0, 4)
    f.ready:SetTextColor(0.3, 1, 0.3)
    f.ready:SetText("Ready!")
    f.t = 0
    f.loop, f.fixedSize, f.shineOn, f.d = false, false, false, false
    f:SetScript("OnUpdate", IconOnUpdate)
    return f
end

-- Give an icon frame the look of key `key` in group `g`
local function StyleIcon(f, key, g)
    local db = FlashCD.db
    local entry = type(db.spells[key]) == "table" and db.spells[key] or {}
    f.key, f.g = key, g
    f.icon:SetTexture(FlashCD.KeyIcon(key) or 134400)
    ApplyFont(f.name, g.fontSize, g.fontOutline)
    ApplyFont(f.ready, math.floor(g.fontSize * 0.9 + 0.5), g.fontOutline)
    f.name:SetText(g.showName and FlashCD.KeyName(key) or "")
    f.ready:SetText("Ready!")
    f.ready:SetTextColor(0.3, 1, 0.3)
    f.ready:SetShown(g.readyText)
    f.icon:SetDesaturated(false)
    local c = entry.color or g.glowColor
    f.glow:SetVertexColor(c.r, c.g, c.b)
    f.glow:SetShown(g.glow)
    f.shineOn = g.shine
end

-- A looping flash for the options preview; its size is capped to fit the box
function FlashCD.NewPreview(parent)
    local f = NewIcon(parent)
    f.loop = true
    f.g = FlashCD.db.groups[1]
    f.Update = function(self, key, maxSize, g)
        StyleIcon(self, key, g)
        self.fixedSize = math.min(g.size, maxSize)
        self:SetSize(self.fixedSize, self.fixedSize)
        self.name:SetWidth(self.fixedSize * 2.5)
    end
    return f
end

-- Flash `key` in its group (or in group `g`). With `soon`, it is the warning
-- before the cooldown is ready: grey icon, "Soon", no sound. `opts`:
--   top   = drawn above windows (tests and previews, so a window can't hide it)
--   quiet = no sound
function FlashCD.Flash(key, g, soon, opts)
    local db = FlashCD.db
    if not FlashCD.KeyIcon(key) then return end
    g = g or FlashCD.GroupOf(key)
    local d = GetDisplay(g)
    local entry = type(db.spells[key]) == "table" and db.spells[key] or {}

    local f
    for _, a in ipairs(d.active) do
        if a.key == key then f = a break end
    end
    if not f then
        while #d.active >= math.max(1, g.maxIcons) do Release(d.active[1], true) end
        f = table.remove(pool) or NewIcon()
        f.d = d
        d.active[#d.active + 1] = f
    end

    StyleIcon(f, key, g)
    f:SetFrameStrata((opts and opts.top) and "TOOLTIP" or "HIGH")
    if soon then
        f.ready:SetText("Soon")
        f.ready:SetTextColor(1, 0.6, 0.1)
        f.ready:Show()
        f.icon:SetDesaturated(true)
    end
    f.t = 0
    f:Show()
    IconOnUpdate(f, 0)
    Layout(d)

    if not soon and not (opts and opts.quiet) then FlashCD.PlaySound(entry.sound or db.sound) end
end

-- Show a group's flash (a preview, not saved): place its spot and flash the
-- first of `keys` in it, one spell only, above windows and without sound
local function PreviewGroup(g, keys)
    local d = GetDisplay(g)
    while d.active[1] do Release(d.active[1], true) end   -- clear the last preview
    d.anchor:ClearAllPoints()
    d.anchor:SetPoint("CENTER", UIParent, g.point or "CENTER", g.x or 0, g.y or 0)
    if keys[1] then FlashCD.Flash(keys[1], g, false, { top = true, quiet = true }) end
end
FlashCD.PreviewGroup = PreviewGroup

function FlashCD.ApplyLayout()
    local live = {}
    local only = FlashCD.movingGroup   -- nil: all groups unlocked
    if only and not FlashCD.GetGroupByID(only) then
        FlashCD.unlocked, FlashCD.movingGroup, only = false, nil, nil   -- it was deleted
    end
    for _, g in ipairs(FlashCD.db.groups) do
        live[g.id] = true
        local d = GetDisplay(g)
        local unlocked = FlashCD.unlocked and (only == nil or only == g.id)
        d.anchor:ClearAllPoints()
        d.anchor:SetPoint("CENTER", UIParent, g.point or "CENTER", g.x, g.y)
        if unlocked then LayoutMover(d) end
        d.mover:EnableMouse(unlocked)
        d.mover:SetShown(unlocked)
        Layout(d)
    end
    -- groups that were deleted: hide their box and flashes
    for id, d in pairs(displays) do
        if not live[id] then
            d.mover:Hide()
            while d.active[1] do Release(d.active[1], true) end
            displays[id] = nil
        end
    end
    ShowGrid(FlashCD.unlocked and FlashCD.db.grid)
end

-- Unlock (or lock) every group
function FlashCD.SetUnlocked(on)
    FlashCD.unlocked = on and true or false
    FlashCD.movingGroup = nil
    FlashCD.ApplyLayout()
    if FlashCD.OnUnlockChanged then FlashCD.OnUnlockChanged() end
end

-- Unlock just one group, so it can be moved on its own; again to lock it
function FlashCD.ToggleMoveGroup(id)
    if FlashCD.unlocked and FlashCD.movingGroup == id then
        FlashCD.unlocked, FlashCD.movingGroup = false, nil
    else
        FlashCD.unlocked, FlashCD.movingGroup = true, id
    end
    FlashCD.ApplyLayout()
    if FlashCD.OnUnlockChanged then FlashCD.OnUnlockChanged() end
end

-- The group being moved on its own, or nil (none, or all unlocked)
function FlashCD.MovingGroup()
    return FlashCD.unlocked and FlashCD.movingGroup or nil
end

function FlashCD.IsUnlocked() return FlashCD.unlocked end

-- Flash a few tracked things in every group, ignoring every filter.
-- A group with nothing in it shows some other spell, so you can see it.
function FlashCD.Test()
    local db = FlashCD.db
    local any
    for key in pairs(db.spells) do any = key break end
    if not any and FlashCD.ScanSpellbook then
        local book = FlashCD.ScanSpellbook()
        any = book[1] and book[1].name
    end
    if not any then
        print("|cff33ccffFlashCD|r: nothing to test with yet.")
        return
    end
    for _, g in ipairs(db.groups) do
        local keys = {}
        for key in pairs(db.spells) do
            if FlashCD.GroupOf(key) == g then
                keys[#keys + 1] = key
                if #keys >= math.min(3, g.maxIcons) then break end
            end
        end
        if #keys == 0 then keys[1] = any end
        for _, key in ipairs(keys) do FlashCD.Flash(key, g, false, { top = true }) end
    end
end

---------------------------------------------------------------------------
-- Cooldown tracking
---------------------------------------------------------------------------
local state = {}     -- [key] = last known on-cooldown state
local lastDur = {}   -- [key] = last readable cooldown length

-- The form you're in: its spell ID (true if the game doesn't say which), or
-- nil when you're not in a form
local function CurrentForm()
    local i = GetShapeshiftForm and GetShapeshiftForm() or 0
    if not i or i == 0 then return nil end
    if GetShapeshiftFormInfo then
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        if type(spellID) == "number" and not IsSecret(spellID) then return spellID end
    end
    return true
end

-- Your forms (bear, cat...): { {id = spellID, name = name}, ... }
function FlashCD.Forms()
    local list = {}
    local n = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
    for i = 1, n do
        local _, _, _, spellID = GetShapeshiftFormInfo(i)
        if type(spellID) == "number" then
            list[#list + 1] = { id = spellID, name = FlashCD.GetSpellName(spellID) or ("Form " .. i) }
        end
    end
    return list
end

-- Whether a spell that just came ready should flash; when not, also why
local function ShouldFlash(key)
    local db = FlashCD.db
    local entry = db.spells[key]
    if type(entry) == "table" and entry.muted then return false, "muted" end
    if FlashCD.unlocked then return false, "groups are unlocked" end
    if db.combatOnly and not UnitAffectingCombat("player") then return false, "not in combat" end
    -- formOnly: true = in any form, a number = only in that form (its spell ID)
    local want = type(entry) == "table" and entry.formOnly
    if want then
        local cur = CurrentForm()
        if not cur then return false, "not in a form" end
        if type(want) == "number" and type(cur) == "number" and cur ~= want then
            return false, "not in " .. (FlashCD.GetSpellName(want) or "that form")
        end
    end
    if db.minCD > 0 then
        local len = lastDur[key] or CooldownLength(key)
        if len and len < db.minCD then return false, "shorter than the minimum cooldown" end
    end
    if db.usableOnly and not ItemID(key) and C_Spell and C_Spell.IsSpellUsable then
        local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, SpellRef(key))
        -- check secrecy before comparing: secret values can't be compared
        if ok and not IsSecret(usable) and usable == false
            and not (IsSecret(noMana) or noMana == true) then
            return false, "can't be cast now (form or stance)"
        end
    end
    return true
end

-- Recent flashes, newest first (not saved): { time, key, kind, text }
-- kind: "flash", "skip", "soon" or "learn"
FlashCD.log = {}
local LOG_MAX = 60
local function Log(key, kind, text)
    local log = FlashCD.log
    table.insert(log, 1, { time = date and date("%H:%M:%S") or "", key = key, kind = kind, text = text })
    while #log > LOG_MAX do table.remove(log) end
    if FlashCD.OnLog then FlashCD.OnLog() end
end
FlashCD.Log = Log

local warned = {}   -- [key] = true once the "Soon" warning showed for this cooldown

-- Seconds left on a cooldown, from when it started and how long it is
-- (works in combat too, where the game hides the times); nil if unknown
local function TimeLeft(key, since)
    if not since or since == 0 then return nil end
    local len = lastDur[key] or CooldownLength(key)
    if not len then return nil end
    return len - (GetTime() - since)
end

local cdSince = {}   -- [key] = GetTime() when it went on cooldown (0 = unknown)

-- A short lockout (global cooldown, wand / auto-shot swing) can look like a
-- cooldown, and in combat its length is hidden. So judge by how long the spell
-- actually stayed on cooldown: past the GCD, and at least half its base cooldown.
local function WasRealCooldown(key)
    local since = cdSince[key]
    if not since or since == 0 then return true end
    local elapsed = GetTime() - since
    if elapsed <= GCD_MAX + 0.2 then return false end
    local base = CooldownLength(key)
    if base then return elapsed >= base * 0.5 end
    -- no known base cooldown: a slow wand / ranged swing can last ~3 s
    return elapsed > NO_BASE_MIN
end

-- Spells the game says have no cooldown, watched in case they do have one
-- (the game doesn't report every cooldown). [name] = true
local candidates = {}

-- Check cooldowns. A full scan checks every tracked and watched spell; with
-- `busyOnly` only the ones on cooldown right now (cheap, run often).
local function Scan(silent, busyOnly)
    local db = FlashCD.db
    local learned
    local function check(key, tracked)
        local now, dur = IsOnCooldown(key)
        if now == nil then return end
        if now == true and state[key] ~= true then
            cdSince[key] = silent and 0 or GetTime()
            warned[key] = nil
        end
        -- the warning a few seconds before it's ready
        if now == true and tracked and db.preWarn > 0 and not warned[key] and not silent then
            local left = TimeLeft(key, cdSince[key])
            if left and left <= db.preWarn and left > 0.3 then
                warned[key] = true
                local ok, why = ShouldFlash(key)
                if ok then
                    FlashCD.Flash(key, nil, true)
                    Log(key, "soon", string.format("ready in %.0f s", left))
                end
            end
        end
        if state[key] == true and now == false and not silent and WasRealCooldown(key) then
            if tracked then
                local ok, why = ShouldFlash(key)
                if ok then
                    FlashCD.Flash(key)
                    Log(key, "flash", "flashed in " .. FlashCD.GroupOf(key).name)
                else
                    Log(key, "skip", "not flashed: " .. why)
                end
            elseif cdSince[key] and cdSince[key] > 0 then
                learned = learned or {}
                learned[#learned + 1] = { key = key, len = lastDur[key] or (GetTime() - cdSince[key]) }
            end
        end
        if dur then lastDur[key] = dur end
        state[key] = now
    end
    if busyOnly then
        local busy = {}
        for key, on in pairs(state) do
            if on == true and (db.spells[key] ~= nil or candidates[key]) then busy[#busy + 1] = key end
        end
        for _, key in ipairs(busy) do check(key, db.spells[key] ~= nil) end
    else
        for key in pairs(db.spells) do check(key, true) end
        for key in pairs(candidates) do
            if db.spells[key] == nil then check(key, false) end
        end
    end
    if not learned then return end

    -- a cooldown seen on a spell the game said had none: remember it, and
    -- track the spell unless you unticked it yourself
    local added = false
    for _, l in ipairs(learned) do
        db.learnedCD[l.key] = math.floor(l.len * 2 + 0.5) / 2
        candidates[l.key] = nil
        if db.autoTrack and not db.removed[l.key] then
            FlashCD.TrackKey(l.key)
            added = true
            print("|cff33ccffFlashCD|r: " .. l.key .. " has a cooldown, now tracking it.")
            Log(l.key, "learn", string.format("found a %g s cooldown, now tracked", db.learnedCD[l.key]))
            if ShouldFlash(l.key) then FlashCD.Flash(l.key) end
        else
            Log(l.key, "learn", string.format("found a %g s cooldown (not tracked)", db.learnedCD[l.key]))
        end
    end
    if FlashCD.OnTrackedChanged then FlashCD.OnTrackedChanged() end
end

function FlashCD.ResetState()
    wipe(state)
    wipe(cdSince)
    Scan(true)
end

function FlashCD.TrackKey(key)
    local db = FlashCD.db
    if type(db.spells[key]) ~= "table" then db.spells[key] = {} end
    db.removed[key] = nil
    candidates[key] = nil
    state[key] = (IsOnCooldown(key))
end

-- Untick a spell. It stays unticked: auto-tracking never adds it back.
function FlashCD.UntrackKey(key)
    FlashCD.db.spells[key] = nil
    FlashCD.db.removed[key] = true
    state[key] = nil
end

-- Convert older saves: ID keys -> spell names, `true` -> settings table.
-- Keys are collected first: adding keys while iterating with pairs is unsafe.
function FlashCD.MigrateSpells()
    local spells = FlashCD.db.spells
    local keys = {}
    for key in pairs(spells) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        local v = spells[key]
        local entry = type(v) == "table" and v or {}
        if type(key) == "number" then
            local name = FlashCD.GetSpellName(key)
            if name then
                spells[key] = nil
                spells[name] = entry
            else
                spells[key] = entry
            end
        elseif type(key) == "string" then
            spells[key] = entry
        else
            spells[key] = nil
        end
    end
end

-- Track every spell with a cooldown the first time it shows up in the
-- spellbook (all current spells on first run, then each newly learned one).
-- Spells already seen are never re-added, so removing one sticks, also when
-- a new rank is learned.
function FlashCD.AutoTrack()
    if not FlashCD.ScanSpellbook then return end
    local db = FlashCD.db
    local added = false
    wipe(candidates)
    for _, d in ipairs(FlashCD.ScanSpellbook()) do
        local name = d.name
        if name and not db.known[name] then
            db.known[name] = true
            if db.spells[name] == nil then
                if not FlashCD.HasCooldown(d.id, name) then
                    -- may still get one: some spells only have a cooldown in a form
                    db.skippedNoCD[name] = true
                elseif db.autoTrack then
                    FlashCD.TrackKey(name)
                    added = true
                end
            end
        elseif name and db.skippedNoCD[name] and FlashCD.HasCooldown(d.id, name) then
            -- skipped for having no cooldown, but has one now (e.g. in a form)
            db.skippedNoCD[name] = nil
            if db.autoTrack and db.spells[name] == nil and not db.removed[name] then
                FlashCD.TrackKey(name)
                added = true
            end
        end
        -- watched even when unticked: the cooldown is still learned (for the
        -- list), the spell just isn't tracked
        if name and db.spells[name] == nil and not FlashCD.HasCooldown(d.id, name) then
            candidates[name] = true
        end
    end
    if added and FlashCD.OnTrackedChanged then FlashCD.OnTrackedChanged() end
end

---------------------------------------------------------------------------
-- Saved settings (per character, new characters copy the last layout)
---------------------------------------------------------------------------
local function InitDB()
    -- nothing saved at all: FlashCD was just installed (shows the welcome)
    local fresh = FlashCDDB == nil and FlashCDCharDB == nil
    FlashCDDB = FlashCDDB or {}
    local account = FlashCDDB
    if not fresh and account.welcomed == nil then account.welcomed = true end   -- updating: no welcome

    if not FlashCDCharDB then
        if account.spells then
            -- the first versions kept everything account-wide: hand it to this character
            FlashCDCharDB = {}
            for k, v in pairs(account) do
                if k ~= "template" then FlashCDCharDB[k] = CopyTable(v) end
            end
        else
            FlashCDCharDB = CopyTable(account.template or {})
        end
    end
    -- account table keeps only the template for new characters and the
    -- saved settings of each character (to copy between them)
    for k in pairs(account) do
        if k ~= "template" and k ~= "chars" and k ~= "welcomed" and k ~= "profiles" then account[k] = nil end
    end
    if type(account.chars) ~= "table" then account.chars = {} end
    if type(account.profiles) ~= "table" then account.profiles = {} end   -- saved copies

    local db = FlashCDCharDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = CopyTable(v) end
    end

    FlashCD.NormalizeGroups(db)
    FlashCD.db = db
end

-- Make sure db.groups is a usable list of groups (also after copying or
-- importing settings)
function FlashCD.NormalizeGroups(db)
    -- before groups the look was stored flat: make it group 1
    if type(db.groups) ~= "table" or #db.groups == 0 then
        local g = { id = 1 }
        for k in pairs(GROUP_DEFAULTS) do
            if k ~= "name" and db[k] ~= nil then g[k] = db[k] end
        end
        db.groups = { g }
        db.nextGroup = 2
    end
    for k in pairs(GROUP_DEFAULTS) do db[k] = nil end
    local maxID = 0
    for i, g in ipairs(db.groups) do
        if type(g.id) ~= "number" then g.id = i end
        maxID = math.max(maxID, g.id)
        for k, v in pairs(GROUP_DEFAULTS) do
            if g[k] == nil then g[k] = CopyTable(v) end
        end
        if i > 1 and g.name == GROUP_DEFAULTS.name then g.name = "Group " .. g.id end
        if type(g.color) ~= "table" then g.color = GroupColour(g.id) end
    end
    if type(db.nextGroup) ~= "number" or db.nextGroup <= maxID then db.nextGroup = maxID + 1 end
end

-- Put every setting back to its default. Tracked spells (and their own
-- sound / colour / mute) and the list of already-seen spells are kept.
function FlashCD.ResetSettings()
    local db = FlashCD.db
    for k, v in pairs(DEFAULTS) do
        if k ~= "spells" and k ~= "known" and k ~= "removed" and k ~= "learnedCD"
            and k ~= "skippedNoCD" and k ~= "overrides" and k ~= "window" then
            db[k] = CopyTable(v)
        end
    end
    -- groups and their names are kept; their look goes back to the default,
    -- each a little lower than the one before so they don't overlap
    for i, g in ipairs(db.groups) do
        local id, name = g.id, g.name
        for k, v in pairs(GROUP_DEFAULTS) do g[k] = CopyTable(v) end
        g.id, g.name = id, name
        g.y = GROUP_DEFAULTS.y - (i - 1) * 170
    end
    if FlashCD.unlocked then FlashCD.SetUnlocked(false) end
    FlashCD.ApplyLayout()
    if FlashCD.UpdateMinimapButton then FlashCD.UpdateMinimapButton() end
end

local function SaveTemplate()
    local t = {}
    for _, k in ipairs(TEMPLATE_KEYS) do t[k] = CopyTable(FlashCD.db[k]) end
    FlashCDDB.template = t
end

---------------------------------------------------------------------------
-- Profiles: copy settings from another character, export and import them
-- as text to share with others
---------------------------------------------------------------------------
function FlashCD.CharKey()
    local name = UnitName and UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or "?"
    return name .. " - " .. realm
end

-- The parts a profile can hold (for exporting only some of them). `keys` are
-- settings; `group` are fields of each group.
FlashCD.PROFILE_PARTS = {
    { key = "position", label = "Group positions", group = { "point", "x", "y" } },
    { key = "look", label = "Group look (size, animation, glow, text)",
      group = { "size", "alpha", "duration", "anim", "showName", "glow", "glowColor", "shine",
                "readyText", "fontSize", "fontOutline", "color" } },
    { key = "layout", label = "Icons at once and grow direction", group = { "maxIcons", "grow" } },
    { key = "alerts", label = "Sound and when to flash", keys = { "sound", "combatOnly", "minCD", "usableOnly", "preWarn" } },
    { key = "tracking", label = "Auto-track options", keys = { "autoTrack", "cdOnly" } },
    { key = "window", label = "Theme, grid and minimap button", keys = { "theme", "grid", "snap", "minimap" } },
    { key = "spells", label = "Tracked spells (with their own settings)" },
}

-- The parts in a profile (older ones hold everything)
local function PartsOf(data)
    if type(data.parts) == "table" then return data.parts end
    local p = {}
    for _, part in ipairs(FlashCD.PROFILE_PARTS) do p[part.key] = true end
    p.spells = type(data.spells) == "table" or nil
    return p
end
FlashCD.PartsOf = PartsOf

-- This character's settings: the parts in `parts` (a set of part keys), or
-- everything when it is nil
function FlashCD.ProfileData(parts)
    if type(parts) ~= "table" then parts = nil end   -- true or nil: everything
    local db = FlashCD.db
    local data = { v = 2, parts = {}, settings = {} }
    local fields = {}
    for _, part in ipairs(FlashCD.PROFILE_PARTS) do
        if parts == nil or parts[part.key] then
            data.parts[part.key] = true
            for _, k in ipairs(part.keys or {}) do data.settings[k] = CopyTable(db[k]) end
            for _, k in ipairs(part.group or {}) do fields[k] = true end
        end
    end
    if next(fields) then
        local groups = {}
        for i, g in ipairs(db.groups) do
            local c = { id = g.id, name = g.name }
            for k in pairs(fields) do c[k] = CopyTable(g[k]) end
            groups[i] = c
        end
        data.settings.groups = groups
        data.settings.nextGroup = db.nextGroup
        -- which spell is in which group goes with the groups, also when the
        -- spells themselves aren't included
        data.members = {}   -- [spell] = group id, 0 = the first group
        for k, e in pairs(db.spells) do
            if type(e) == "table" then data.members[k] = e.group or 0 end
        end
    end
    if data.parts.spells then
        data.spells = CopyTable(db.spells)
        data.removed = CopyTable(db.removed)
    end
    return data
end

-- Saved per character (account-wide), so other characters can copy them
local function SaveCharacter()
    local data = FlashCD.ProfileData()
    local class = UnitClass and (UnitClass("player"))
    data.class = class
    FlashCDDB.chars[FlashCD.CharKey()] = data
end

-- Other characters with saved settings: { {key, label}, ... }
function FlashCD.Characters()
    local list, me = {}, FlashCD.CharKey()
    for key, data in pairs(FlashCDDB.chars or {}) do
        if key ~= me then
            list[#list + 1] = { key = key, label = key .. (data.class and (" (" .. data.class .. ")") or "") }
        end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

-- Undo: the settings from before the last preset, import, copy or fresh
-- start (one step; not saved over a reload)
local undo
local inChange = false

-- Run a change that replaces settings, keeping what was there for Undo
local function WithUndo(fn, ...)
    if inChange then return fn(...) end   -- part of a bigger change
    local db = FlashCD.db
    undo = { data = FlashCD.ProfileData(), known = CopyTable(db.known), skippedNoCD = CopyTable(db.skippedNoCD) }
    inChange = true
    local ok, result = pcall(fn, ...)
    inChange = false
    if not ok then error(result, 0) end
    return result
end

-- Use settings from profile data (from a character or an import). Only the
-- parts it holds are changed. Groups: with every group part they replace
-- yours; with only some (say positions), they go onto your groups in order,
-- and missing groups are added.
local function ApplyProfileNow(data, withSpells)
    local db = FlashCD.db
    if type(data) ~= "table" or type(data.settings) ~= "table" then return false end
    local parts = PartsOf(data)
    local fields = {}
    for _, part in ipairs(FlashCD.PROFILE_PARTS) do
        if parts[part.key] then
            for _, k in ipairs(part.keys or {}) do
                if data.settings[k] ~= nil then db[k] = CopyTable(data.settings[k]) end
            end
            for _, k in ipairs(part.group or {}) do fields[k] = true end
        end
    end

    local idMap = {}   -- the text's group ids -> ours
    local replaced = false
    local src = data.settings.groups
    if type(src) == "table" and #src > 0 and next(fields) then
        if parts.position and parts.look and parts.layout then
            replaced = true
            db.groups = CopyTable(src)
            db.nextGroup = data.settings.nextGroup
            for _, g in ipairs(db.groups) do if type(g) == "table" and g.id then idMap[g.id] = g.id end end
        else
            for i, ig in ipairs(src) do
                if type(ig) == "table" then
                    local g = db.groups[i]
                    if not g then
                        g = { id = db.nextGroup, name = ig.name }
                        db.nextGroup = db.nextGroup + 1
                        db.groups[i] = g
                    end
                    for k in pairs(fields) do
                        if ig[k] ~= nil then g[k] = CopyTable(ig[k]) end
                    end
                    if ig.id then idMap[ig.id] = g.id end
                end
            end
        end
    end
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil or type(db[k]) ~= type(v) then db[k] = CopyTable(v) end
    end
    FlashCD.NormalizeGroups(db)

    -- the groups were replaced but your spells stay: put each spell in the
    -- group it had in the profile (older profiles: from their spells)
    local loadingSpells = withSpells and parts.spells and type(data.spells) == "table"
    if replaced and not loadingSpells then
        local members = type(data.members) == "table" and data.members or nil
        if not members and type(data.spells) == "table" then
            members = {}
            for k, e in pairs(data.spells) do
                if type(e) == "table" then members[k] = e.group or 0 end
            end
        end
        for k, e in pairs(db.spells) do
            if type(e) == "table" then
                local g = members and members[k]
                if g ~= nil then
                    e.group = (g ~= 0) and idMap[g] or nil
                elseif e.group ~= nil and not FlashCD.GetGroupByID(e.group) then
                    e.group = nil   -- its group is gone: the first group
                end
            end
        end
    end

    if loadingSpells then
        local haveMap = next(idMap) ~= nil
        db.spells = {}
        for key, e in pairs(data.spells) do
            if type(key) == "string" then
                local c = type(e) == "table" and CopyTable(e) or {}
                if c.group ~= nil then
                    if haveMap then c.group = idMap[c.group]
                    elseif not FlashCD.GetGroupByID(c.group) then c.group = nil end
                end
                db.spells[key] = c
            end
        end
        db.removed = type(data.removed) == "table" and CopyTable(data.removed) or {}
    end
    if FlashCD.unlocked then FlashCD.SetUnlocked(false) end
    FlashCD.ApplyLayout()
    FlashCD.ResetState()
    if FlashCD.UpdateMinimapButton then FlashCD.UpdateMinimapButton() end
    if FlashCD.OnProfileApplied then FlashCD.OnProfileApplied() end
    return true
end

function FlashCD.ApplyProfile(data, withSpells)
    return WithUndo(ApplyProfileNow, data, withSpells)
end

function FlashCD.CanUndo() return undo ~= nil end

-- Put back the settings from before the last preset, import, copy or fresh start
function FlashCD.Undo()
    if not undo then return false end
    local u = undo
    undo = nil
    inChange = true
    local ok, err = pcall(ApplyProfileNow, u.data, true)
    inChange = false
    local db = FlashCD.db
    db.known, db.skippedNoCD = u.known, u.skippedNoCD
    if not ok then error(err, 0) end
    return true
end

-- Every profile: this character's (by name), your other characters', and
-- the copies you saved. { {key, label, name, kind = "me"|"char"|"copy"}, ... }
function FlashCD.ProfileList()
    local me = FlashCD.CharKey()
    local list = { { key = "char:" .. me, name = me, kind = "me", label = me .. " (this character)" } }
    for _, c in ipairs(FlashCD.Characters()) do
        list[#list + 1] = { key = "char:" .. c.key, name = c.key, kind = "char", label = c.label }
    end
    local copies = {}
    for name in pairs(FlashCDDB.profiles or {}) do copies[#copies + 1] = name end
    table.sort(copies)
    for _, name in ipairs(copies) do
        list[#list + 1] = { key = "copy:" .. name, name = name, kind = "copy", label = name }
    end
    return list
end

-- Load a profile from the list onto this character
function FlashCD.LoadProfile(key, withSpells)
    local kind, name = tostring(key):match("^(%a+):(.+)$")
    if kind == "char" then
        if name == FlashCD.CharKey() then return false end   -- that's this one
        return FlashCD.CopyFromCharacter(name, withSpells)
    elseif kind == "copy" then
        return FlashCD.ApplyProfile(FlashCDDB.profiles[name], withSpells)
    end
    return false
end

-- Save this character's settings (and tracked spells) as a named copy;
-- returns false and a reason when the name won't do
function FlashCD.SaveProfileCopy(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return false, "Type a name for the copy." end
    if #name > 40 then return false, "That name is too long." end
    local data = FlashCD.ProfileData()
    data.class = UnitClass and (UnitClass("player"))
    FlashCDDB.profiles[name] = data
    return true
end

function FlashCD.DeleteProfileCopy(name)
    if FlashCDDB.profiles[name] == nil then return false end
    FlashCDDB.profiles[name] = nil
    return true
end

function FlashCD.CopyFromCharacter(key, withSpells)
    local data = FlashCDDB.chars and FlashCDDB.chars[key]
    return FlashCD.ApplyProfile(data, withSpells)
end

-- Start over with a fresh default profile: every setting back to default and
-- one default group. With withSpells, the tracked spells start over too (the
-- spellbook is auto-tracked again). Learned cooldowns and the window's place
-- are kept.
local function ResetToFreshNow(withSpells)
    local db = FlashCD.db
    for _, k in ipairs(TEMPLATE_KEYS) do db[k] = CopyTable(DEFAULTS[k]) end
    db.groups, db.nextGroup = nil, nil
    FlashCD.NormalizeGroups(db)   -- makes the one default group
    if withSpells then
        db.spells, db.known, db.removed, db.skippedNoCD = {}, {}, {}, {}
        FlashCD.AutoTrack()
    else
        for _, e in pairs(db.spells) do
            if type(e) == "table" then e.group = nil end   -- their groups are gone
        end
    end
    if FlashCD.unlocked then FlashCD.SetUnlocked(false) end
    FlashCD.ApplyLayout()
    FlashCD.ResetState()
    if FlashCD.UpdateMinimapButton then FlashCD.UpdateMinimapButton() end
    if FlashCD.OnProfileApplied then FlashCD.OnProfileApplied() end
end

function FlashCD.ResetToFresh(withSpells)
    return WithUndo(ResetToFreshNow, withSpells)
end

-- Built-in looks to start from. A preset replaces the groups (look, layout,
-- place) and may set the sound; tracked spells, theme and other settings stay.
-- "default" is the full fresh start above.
local function PresetGroup(t)
    local g = CopyTable(GROUP_DEFAULTS)
    for k, v in pairs(t) do g[k] = v end
    return g
end

FlashCD.PRESETS = {
    { key = "default", label = "Default (start fresh)",
      desc = "Every setting back to default and one group, like a new install." },
    { key = "standard", label = "Standard",
      desc = "One group in the middle with the default look.",
      groups = { PresetGroup({}) } },
    { key = "minimal", label = "Minimal",
      desc = "One small, quiet icon: no glow, name or shine.",
      groups = { PresetGroup({ size = 56, y = 60, anim = "plain", glow = false, showName = false,
                               shine = false, alpha = 0.9, duration = 0.8 }) } },
    { key = "bold", label = "Big and bold",
      desc = "A large bouncing icon with glow, shine, \"Ready!\" and a raid warning sound.",
      sound = "raid",
      groups = { PresetGroup({ size = 140, y = 140, anim = "bounce", readyText = true,
                               fontSize = 20, duration = 1.4 }) } },
    { key = "bigsmall", label = "Big and small",
      desc = "Two groups: cooldowns of 1 minute or more big in the middle, the rest small in a row below.",
      split = 60,
      groups = { PresetGroup({ name = "Big", size = 110, y = 150 }),
                 PresetGroup({ name = "Small", size = 48, y = 40, maxIcons = 6, showName = false,
                               anim = "pop" }) } },
    { key = "right", label = "Column on the right",
      desc = "Medium icons stacked in a column to the right of your character.",
      groups = { PresetGroup({ size = 60, x = 260, y = 80, grow = "down", anim = "slide",
                               fontSize = 13, maxIcons = 5 }) } },
    { key = "left", label = "Column on the left",
      desc = "Medium icons stacked in a column to the left of your character.",
      groups = { PresetGroup({ size = 60, x = -260, y = 80, grow = "down", anim = "slide",
                               fontSize = 13, maxIcons = 5 }) } },
}

function FlashCD.GetPreset(key)
    for _, p in ipairs(FlashCD.PRESETS) do
        if p.key == key then return p end
    end
end

-- Show what a preset looks like with your spells, without using it
function FlashCD.PreviewPreset(key)
    local p = FlashCD.GetPreset(key)
    if not p then return false end
    local db = FlashCD.db
    -- your tracked spells, longest cooldown first (or a few from the spellbook)
    local keys = {}
    for k in pairs(db.spells) do keys[#keys + 1] = k end
    if #keys == 0 and FlashCD.ScanSpellbook then
        for _, d in ipairs(FlashCD.ScanSpellbook()) do
            keys[#keys + 1] = d.key
            if #keys >= 4 then break end
        end
    end
    local function Len(k) return (not FlashCD.ItemID(k) and FlashCD.CooldownLength(k)) or 0 end
    table.sort(keys, function(a, b)
        local la, lb = Len(a), Len(b)
        if la ~= lb then return la > lb end
        return tostring(a) < tostring(b)
    end)
    local groups = p.groups or { GROUP_DEFAULTS }
    for i, src in ipairs(groups) do
        local g = CopyTable(src)
        g.id = "preview" .. i
        local pick = {}
        for _, k in ipairs(keys) do
            if not p.split or ((Len(k) >= p.split) == (i == 1)) then pick[#pick + 1] = k end
        end
        if #pick == 0 then pick = { keys[i] or keys[1] } end
        PreviewGroup(g, pick)
    end
    if p.sound then FlashCD.PlaySound(p.sound, true) end
    return true
end

-- Use a preset. With freshSpells, the tracked spells start over too.
local function ApplyPresetNow(key, freshSpells)
    local p = FlashCD.GetPreset(key)
    if not p then return false end
    if key == "default" then
        FlashCD.ResetToFresh(freshSpells)
        return true
    end
    local db = FlashCD.db
    if freshSpells then
        db.spells, db.known, db.removed, db.skippedNoCD = {}, {}, {}, {}
        FlashCD.AutoTrack()
    end
    local groups = CopyTable(p.groups)
    for i, g in ipairs(groups) do g.id = i end
    -- spells' groups: sorted by cooldown length for a split preset, else the first group
    for k, e in pairs(db.spells) do
        if type(e) == "table" then
            e.group = nil
            if p.split then
                local len = not FlashCD.ItemID(k) and FlashCD.CooldownLength(k)
                e.group = (len and len >= p.split) and 1 or 2
            end
        end
    end
    local data = { v = 2, parts = { position = true, look = true, layout = true },
                   settings = { groups = groups, nextGroup = #groups + 1 } }
    if p.sound then
        data.parts.alerts = true
        data.settings.sound = p.sound
    end
    return FlashCD.ApplyProfile(data, false)
end

function FlashCD.ApplyPreset(key, freshSpells)
    if not FlashCD.GetPreset(key) then return false end
    return WithUndo(ApplyPresetNow, key, freshSpells)
end

-- Text form: "FlashCD:1:" followed by a Lua-like table of strings, numbers,
-- booleans and tables. Read back by a small parser of its own: pasted text is
-- never run as code.
local function Serialize(v, out)
    local t = type(v)
    if t == "table" then
        out[#out + 1] = "{"
        local first = true
        for k, x in pairs(v) do
            local kt, xt = type(k), type(x)
            if (kt == "string" or kt == "number") and (xt == "table" or xt == "string" or xt == "number" or xt == "boolean") then
                if not first then out[#out + 1] = "," end
                first = false
                out[#out + 1] = "["
                Serialize(k, out)
                out[#out + 1] = "]="
                Serialize(x, out)
            end
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = '"' .. v:gsub('[\\"]', "\\%0"):gsub("\n", "\\n") .. '"'
    elseif t == "number" then
        out[#out + 1] = (v == math.floor(v)) and string.format("%d", v) or string.format("%.4f", v):gsub("0+$", "")
    else
        out[#out + 1] = v and "true" or "false"
    end
end

local EXPORT_PREFIX = "FlashCD:1:"

-- `parts`: a set of part keys to include (nil = everything)
function FlashCD.ExportString(parts)
    local out = {}
    Serialize(FlashCD.ProfileData(parts), out)
    return EXPORT_PREFIX .. table.concat(out)
end

-- Returns the profile data, or nil and a reason
function FlashCD.ParseExport(text)
    if type(text) ~= "string" then return nil, "nothing to import" end
    text = text:match("^%s*(.-)%s*$")
    if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
        return nil, "this isn't a FlashCD export (it should start with " .. EXPORT_PREFIX .. ")"
    end
    if #text > 200000 then return nil, "the text is too long" end
    local src, pos, depth = text, #EXPORT_PREFIX + 1, 0
    local function fail(msg) error({ msg = msg }, 0) end
    local function skip() pos = src:find("[^%s]", pos) or (#src + 1) end
    local value
    local function str()
        local out, i = {}, pos + 1
        while true do
            local c = src:sub(i, i)
            if c == "" then fail("unfinished text") end
            if c == '"' then pos = i + 1 return table.concat(out) end
            if c == "\\" then
                local n = src:sub(i + 1, i + 1)
                out[#out + 1] = (n == "n") and "\n" or n
                i = i + 2
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
    end
    function value()
        skip()
        local c = src:sub(pos, pos)
        if c == "{" then
            depth = depth + 1
            if depth > 20 then fail("too deeply nested") end
            pos = pos + 1
            local t = {}
            skip()
            if src:sub(pos, pos) == "}" then pos = pos + 1 depth = depth - 1 return t end
            while true do
                skip()
                if src:sub(pos, pos) ~= "[" then fail("expected [ at " .. pos) end
                pos = pos + 1
                local k = value()
                skip()
                if src:sub(pos, pos + 1) ~= "]=" then fail("expected ]= at " .. pos) end
                pos = pos + 2
                if type(k) ~= "string" and type(k) ~= "number" then fail("bad key at " .. pos) end
                t[k] = value()
                skip()
                local sep = src:sub(pos, pos)
                pos = pos + 1
                if sep == "}" then depth = depth - 1 return t end
                if sep ~= "," then fail("expected , or } at " .. (pos - 1)) end
            end
        elseif c == '"' then
            return str()
        elseif src:sub(pos, pos + 3) == "true" then
            pos = pos + 4 return true
        elseif src:sub(pos, pos + 4) == "false" then
            pos = pos + 5 return false
        else
            local num = src:match("^%-?%d+%.?%d*", pos)
            if not num then fail("unexpected '" .. c .. "' at " .. pos) end
            pos = pos + #num
            return tonumber(num)
        end
    end
    local ok, result = pcall(function()
        local v = value()
        skip()
        if pos <= #src then fail("extra text at the end") end
        return v
    end)
    if not ok then return nil, "the text is damaged: " .. (type(result) == "table" and result.msg or tostring(result)) end
    if type(result) ~= "table" or type(result.settings) ~= "table" then return nil, "no settings in the text" end
    return result
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- The game's cooldown events trigger a full scan. Between them: spells on
-- cooldown are checked every 0.1 s (to catch the moment they are ready,
-- which has no event of its own), and a full scan runs every second in case
-- an event was missed.
local driver = CreateFrame("Frame")
local acc, fullAcc = 0, 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc, fullAcc = acc + elapsed, fullAcc + elapsed
    if acc < 0.1 then return end
    acc = 0
    if fullAcc >= 1 then
        fullAcc = 0
        Scan(false)
    else
        Scan(false, true)
    end
end)
driver:Hide()

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        InitDB()
        FlashCD.MigrateSpells()
        FlashCD.ApplyLayout()
        if FlashCD.InitOptions then FlashCD.InitOptions() end
        if FlashCD.InitMinimap then FlashCD.InitMinimap() end
        self:UnregisterEvent("ADDON_LOADED")
    elseif not FlashCD.db then
        return
    elseif event == "PLAYER_ENTERING_WORLD" then
        FlashCD.MigrateSpells()
        FlashCD.AutoTrack()
        FlashCD.ResetState()
        SaveCharacter()
        driver:Show()
    elseif event == "PLAYER_LOGOUT" then
        SaveTemplate()
        SaveCharacter()
    else
        if event == "SPELLS_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then FlashCD.AutoTrack() end
        Scan(false)
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
-- /flashcd spell <name>: print what FlashCD sees for matching spells
function FlashCD.DebugSpell(filter)
    local P = function(...) print("|cff33ccffFlashCD|r:", ...) end
    filter = (filter or ""):lower()
    if filter == "" then P("usage: /flashcd spell <part of a spell name>") return end
    local function Show(v)
        if v == nil then return "-" end
        if IsSecret(v) then return "secret" end
        return tostring(v)
    end
    local function Base(id)
        if not GetSpellBaseCooldown or not id then return "-" end
        local ok, ms = pcall(GetSpellBaseCooldown, id)
        return ok and Show(ms) or "error"
    end
    local function CD(ref)
        if not (C_Spell and C_Spell.GetSpellCooldown) then return "-" end
        local ok, i = pcall(C_Spell.GetSpellCooldown, ref)
        if not ok or type(i) ~= "table" then return "none" end
        return "active=" .. Show(i.isActive) .. " gcd=" .. Show(i.isOnGCD) .. " dur=" .. Show(i.duration)
    end
    local db, found = FlashCD.db, 0
    for _, d in ipairs(FlashCD.ScanSpellbook and FlashCD.ScanSpellbook() or {}) do
        if tostring(d.name):lower():find(filter, 1, true) then
            found = found + 1
            local name = d.name
            local o = OverrideOf(d.id)
            P(string.format("|cffffd100%s|r  spellbook id %s (base cd %s ms)  form version now %s (base cd %s ms)  saved form version %s",
                name, Show(d.id), Base(d.id), Show(o), Base(o), Show(db.overrides[name])))
            P("   cooldown by id: " .. CD(d.id) .. "   by what FlashCD uses (" .. Show(SpellRef(name)) .. "): " .. CD(SpellRef(name)))
            P(string.format("   tracked %s  unticked %s  seen %s  skipped(no cd) %s  learned cd %s  tab %s",
                Show(db.spells[name] ~= nil), Show(db.removed[name]), Show(db.known[name]),
                Show(db.skippedNoCD[name]), Show(db.learnedCD[name]), Show(d.tab)))
        end
    end
    if found == 0 then P("no spellbook spell matches '" .. filter .. "'") end
end

SLASH_FLASHCD1 = "/flashcd"
SLASH_FLASHCD2 = "/fcd"
SlashCmdList.FLASHCD = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "unlock" or msg == "lock" or msg == "move" then
        FlashCD.SetUnlocked(not FlashCD.unlocked)
        if FlashCD.OnPositionChanged then FlashCD.OnPositionChanged() end
    elseif msg:match("^spell") then
        FlashCD.DebugSpell(msg:match("^spell%s*(.*)$"))
    elseif msg == "welcome" then
        if FlashCD.ShowWelcome then FlashCD.ShowWelcome() end
    elseif msg == "minimap" then
        FlashCD.db.minimap.hide = not FlashCD.db.minimap.hide
        if FlashCD.UpdateMinimapButton then FlashCD.UpdateMinimapButton() end
        if FlashCD.OnPositionChanged then FlashCD.OnPositionChanged() end
    elseif msg == "test" then
        FlashCD.Test()
    elseif msg == "reset" then
        FlashCD.ResetSettings()
        if FlashCD.OnPositionChanged then FlashCD.OnPositionChanged() end
        print("|cff33ccffFlashCD|r: settings reset to defaults (tracked spells kept).")
    else
        if FlashCD.OpenOptions then FlashCD.OpenOptions() end
    end
end
