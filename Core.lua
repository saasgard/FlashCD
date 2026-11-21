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
    spells     = {},      -- [key] = { muted, sound, color, group = group id }
    known      = {},      -- [spell name] = true for every spell already seen
    removed    = {},      -- [key] = true: unticked by you, never auto-tracked again
    learnedCD  = {},      -- [spell name] = seconds: cooldowns the game doesn't report
    skippedNoCD = {},     -- [spell name] = true: not auto-tracked, it had no cooldown then
    overrides  = {},      -- [spell name] = spell ID that replaces it in a form (seen once, kept)
    -- groups = { group, ... } (see GROUP_DEFAULTS), nextGroup = next group id
    sound      = "none",
    combatOnly = false,
    minCD      = 0,       -- seconds; shorter cooldowns don't flash
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
    "autoTrack", "cdOnly", "minimap", "grid", "snap", "theme",
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
    GameTooltip:Show()
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
    m.label:SetPoint("BOTTOM", m, "TOP", 0, 6)
    m:SetScript("OnDragStart", function(self) self:StartMoving() end)
    m:SetScript("OnDragStop", MoverDragStop)
    m:SetScript("OnKeyDown", MoverKeyDown)
    m:SetScript("OnEnter", MoverEnter)
    m:SetScript("OnLeave", MoverLeave)

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
    m.label:SetText(g.name)
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
    f.ready:SetShown(g.readyText)
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

-- Flash `key` in its group (or in group `g`)
function FlashCD.Flash(key, g)
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
    f.t = 0
    f:Show()
    IconOnUpdate(f, 0)
    Layout(d)

    FlashCD.PlaySound(entry.sound or db.sound)
end

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
        for _, key in ipairs(keys) do FlashCD.Flash(key, g) end
    end
end

---------------------------------------------------------------------------
-- Cooldown tracking
---------------------------------------------------------------------------
local state = {}     -- [key] = last known on-cooldown state
local lastDur = {}   -- [key] = last readable cooldown length

local function ShouldFlash(key)
    local db = FlashCD.db
    local entry = db.spells[key]
    if type(entry) == "table" and entry.muted then return false end
    if FlashCD.unlocked then return false end
    if db.combatOnly and not UnitAffectingCombat("player") then return false end
    if db.minCD > 0 then
        local len = lastDur[key] or CooldownLength(key)
        if len and len < db.minCD then return false end
    end
    if db.usableOnly and not ItemID(key) and C_Spell and C_Spell.IsSpellUsable then
        local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, SpellRef(key))
        -- check secrecy before comparing: secret values can't be compared
        if ok and not IsSecret(usable) and usable == false
            and not (IsSecret(noMana) or noMana == true) then
            return false   -- wrong form / stance, not just short on mana/rage/energy
        end
    end
    return true
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

local function Scan(silent)
    local db = FlashCD.db
    local learned
    local function check(key, tracked)
        local now, dur = IsOnCooldown(key)
        if now == nil then return end
        if now == true and state[key] ~= true then
            cdSince[key] = silent and 0 or GetTime()
        end
        if state[key] == true and now == false and not silent and WasRealCooldown(key) then
            if tracked then
                if ShouldFlash(key) then FlashCD.Flash(key) end
            elseif cdSince[key] and cdSince[key] > 0 then
                learned = learned or {}
                learned[#learned + 1] = { key = key, len = lastDur[key] or (GetTime() - cdSince[key]) }
            end
        end
        if dur then lastDur[key] = dur end
        state[key] = now
    end
    for key in pairs(db.spells) do check(key, true) end
    for key in pairs(candidates) do
        if db.spells[key] == nil then check(key, false) end
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
            if ShouldFlash(l.key) then FlashCD.Flash(l.key) end
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
    FlashCDDB = FlashCDDB or {}
    local account = FlashCDDB

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
    -- account table now only keeps the template for new characters
    for k in pairs(account) do
        if k ~= "template" then account[k] = nil end
    end

    local db = FlashCDCharDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = CopyTable(v) end
    end

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
    FlashCD.db = db
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
-- Events
---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then return end
    acc = 0
    Scan(false)
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
        driver:Show()
    elseif event == "PLAYER_LOGOUT" then
        SaveTemplate()
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
