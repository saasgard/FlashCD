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
    spells     = {},      -- [key] = { muted = bool, sound = key|nil, color = {r,g,b}|nil }
    known      = {},      -- [spell name] = true for every spell already seen
    size       = 96,
    point      = "CENTER",
    x          = 0,
    y          = 120,
    duration   = 1.0,     -- seconds the flash takes to fade out
    alpha      = 1.0,
    maxIcons   = 4,       -- how many flashes can show side by side
    anim       = "pop",   -- pop | zoom | plain
    showName   = true,
    glow       = true,
    glowColor  = { r = 1, g = 0.82, b = 0 },
    sound      = "none",
    combatOnly = false,
    minCD      = 0,       -- seconds; shorter cooldowns don't flash
    usableOnly = true,    -- skip spells that can't be cast now (wrong form etc.)
    autoTrack  = true,
    cdOnly     = true,
}

-- appearance settings copied to new characters
local TEMPLATE_KEYS = {
    "size", "point", "x", "y", "duration", "alpha", "maxIcons", "anim", "showName",
    "glow", "glowColor", "sound", "combatOnly", "minCD", "usableOnly", "autoTrack", "cdOnly",
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
    { key = "plain", label = "Plain fade" },
}

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

function FlashCD.GetSpellID(name)
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
    return FlashCD.GetSpellName(key) or tostring(key)
end

function FlashCD.KeyIcon(key)
    local item = ItemID(key)
    if item then
        if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(item) end
        if GetItemIcon then return GetItemIcon(item) end
        return nil
    end
    return FlashCD.GetSpellIcon(key)
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
        local ok, info = pcall(C_Spell.GetSpellCooldown, key)
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
        local s, d = GetSpellCooldown(key)
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

---------------------------------------------------------------------------
-- Flash display: an anchor (the movable spot) and a row of icons on it
---------------------------------------------------------------------------
local anchor = CreateFrame("Frame", "FlashCDAnchor", UIParent)
anchor:SetClampedToScreen(true)
anchor:SetMovable(true)
anchor:RegisterForDrag("LeftButton")
anchor:SetFrameStrata("FULLSCREEN_DIALOG")
anchor:Hide()

anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
anchor.bg:SetPoint("TOPLEFT", -2, 2)
anchor.bg:SetPoint("BOTTOMRIGHT", 2, -2)
anchor.bg:SetColorTexture(0, 0.6, 1, 0.5)
anchor.preview = anchor:CreateTexture(nil, "ARTWORK")
anchor.preview:SetAllPoints()
anchor.preview:SetTexture(134400)   -- question mark icon
anchor.preview:SetTexCoord(0.07, 0.93, 0.07, 0.93)
anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
anchor.label:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
anchor.label:SetText("FlashCD - drag me, then /flashcd lock")

anchor:SetScript("OnDragStart", function(self) self:StartMoving() end)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local cx, cy = self:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local db = FlashCD.db
    db.point = "CENTER"
    db.x = math.floor(cx - ux + 0.5)
    db.y = math.floor(cy - uy + 0.5)
    FlashCD.ApplyLayout()
    if FlashCD.OnPositionChanged then FlashCD.OnPositionChanged() end
end)

local pool, active = {}, {}
local GAP = 8

local function Layout()
    local db = FlashCD.db
    local size, n = db.size, #active
    local total = n * size + (n - 1) * GAP
    for i, f in ipairs(active) do
        f:SetSize(size, size)
        f.name:SetWidth(size + GAP)
        f:ClearAllPoints()
        f:SetPoint("CENTER", anchor, "CENTER", -total / 2 + size / 2 + (i - 1) * (size + GAP), 0)
    end
end

local function Release(f, skipLayout)
    f:Hide()
    for i, a in ipairs(active) do
        if a == f then table.remove(active, i) break end
    end
    pool[#pool + 1] = f
    if not skipLayout then Layout() end
end

local function IconOnUpdate(self, elapsed)
    local db = FlashCD.db
    self.t = self.t + elapsed
    local p = self.t / db.duration
    if p >= 1 then Release(self) return end
    local sc = 1
    if db.anim == "pop" then
        sc = 1 + 0.25 * math.max(0, 1 - p * 4)
    elseif db.anim == "zoom" then
        sc = 1 + 0.6 * p
    end
    local s = db.size * sc
    self.icon:SetSize(s, s)
    self.glow:SetSize(s * 1.8, s * 1.8)
    self:SetAlpha(db.alpha * (1 - p))
end

local function NewIcon()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetPoint("CENTER")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER")
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.name:SetPoint("TOP", f, "BOTTOM", 0, -4)
    f.name:SetWordWrap(false)
    f:SetScript("OnUpdate", IconOnUpdate)
    return f
end

function FlashCD.Flash(key)
    local db = FlashCD.db
    local icon = FlashCD.KeyIcon(key)
    if not icon then return end
    local entry = type(db.spells[key]) == "table" and db.spells[key] or {}

    local f
    for _, a in ipairs(active) do
        if a.key == key then f = a break end
    end
    if not f then
        while #active >= math.max(1, db.maxIcons) do Release(active[1], true) end
        f = table.remove(pool) or NewIcon()
        active[#active + 1] = f
    end

    f.key = key
    f.icon:SetTexture(icon)
    f.name:SetText(db.showName and FlashCD.KeyName(key) or "")
    local c = entry.color or db.glowColor
    f.glow:SetVertexColor(c.r, c.g, c.b)
    f.glow:SetShown(db.glow)
    f.t = 0
    f:SetAlpha(db.alpha)
    f:Show()
    IconOnUpdate(f, 0)
    Layout()

    FlashCD.PlaySound(entry.sound or db.sound)
end

function FlashCD.ApplyLayout()
    local db = FlashCD.db
    anchor:SetSize(db.size, db.size)
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, db.point or "CENTER", db.x, db.y)
    Layout()
end

function FlashCD.SetUnlocked(on)
    FlashCD.unlocked = on and true or false
    anchor:EnableMouse(FlashCD.unlocked)
    anchor:SetShown(FlashCD.unlocked)
    FlashCD.ApplyLayout()
end

function FlashCD.IsUnlocked() return FlashCD.unlocked end

-- Flash a few tracked things at once, ignoring every filter
function FlashCD.Test()
    local keys = {}
    for key in pairs(FlashCD.db.spells) do
        keys[#keys + 1] = key
        if #keys >= math.min(3, FlashCD.db.maxIcons) then break end
    end
    if #keys == 0 and FlashCD.ScanSpellbook then
        local book = FlashCD.ScanSpellbook()
        if book[1] then keys[1] = book[1].name end
    end
    if #keys == 0 then
        print("|cff33ccffFlashCD|r: nothing to test with yet.")
        return
    end
    for _, key in ipairs(keys) do FlashCD.Flash(key) end
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
        local len = lastDur[key] or BaseCooldown(key)
        if len and len < db.minCD then return false end
    end
    if db.usableOnly and not ItemID(key) and C_Spell and C_Spell.IsSpellUsable then
        local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, key)
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
    local base = BaseCooldown(key)
    if base then return elapsed >= base * 0.5 end
    -- no known base cooldown: a slow wand / ranged swing can last ~3 s
    return elapsed > NO_BASE_MIN
end

local function Scan(silent)
    for key in pairs(FlashCD.db.spells) do
        local now, dur = IsOnCooldown(key)
        if now ~= nil then
            if now == true and state[key] ~= true then
                cdSince[key] = silent and 0 or GetTime()
            end
            if state[key] == true and now == false and not silent
                and WasRealCooldown(key) and ShouldFlash(key) then
                FlashCD.Flash(key)
            end
            if dur then lastDur[key] = dur end
            state[key] = now
        end
    end
end

function FlashCD.ResetState()
    wipe(state)
    wipe(cdSince)
    Scan(true)
end

function FlashCD.TrackKey(key)
    local db = FlashCD.db
    if type(db.spells[key]) ~= "table" then db.spells[key] = {} end
    state[key] = (IsOnCooldown(key))
end

function FlashCD.UntrackKey(key)
    FlashCD.db.spells[key] = nil
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
    for _, d in ipairs(FlashCD.ScanSpellbook()) do
        if d.name and not db.known[d.name] then
            db.known[d.name] = true
            if db.autoTrack and FlashCD.HasCooldown(d.id) and db.spells[d.name] == nil then
                FlashCD.TrackKey(d.name)
                added = true
            end
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
            -- version 1 kept everything account-wide: hand it to this character
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
    FlashCD.db = db
end

-- Put every setting back to its default. Tracked spells (and their own
-- sound / colour / mute) and the list of already-seen spells are kept.
function FlashCD.ResetSettings()
    local db = FlashCD.db
    for _, k in ipairs(TEMPLATE_KEYS) do db[k] = CopyTable(DEFAULTS[k]) end
    if FlashCD.unlocked then FlashCD.SetUnlocked(false) end
    FlashCD.ApplyLayout()
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
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        InitDB()
        FlashCD.MigrateSpells()
        FlashCD.ApplyLayout()
        if FlashCD.InitOptions then FlashCD.InitOptions() end
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
        if event == "SPELLS_CHANGED" then FlashCD.AutoTrack() end
        Scan(false)
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_FLASHCD1 = "/flashcd"
SLASH_FLASHCD2 = "/fcd"
SlashCmdList.FLASHCD = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "unlock" or msg == "lock" or msg == "move" then
        FlashCD.SetUnlocked(not FlashCD.unlocked)
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
