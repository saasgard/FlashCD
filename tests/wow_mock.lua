-- FlashCD tests: a small fake of the WoW API, enough to load and drive the
-- addon outside the game. Loaded before each test file by run_tests.py.
--
-- Frames are plain tables: every method exists and does nothing unless it is
-- defined below. Scripts set with SetScript/HookScript are kept as
-- frame._s_<name> so tests can call them.

local frames = {}          -- frames that registered events
ALL = {}                   -- every frame made, in order
NAMED = {}                 -- named frames
ADDON_DIR = ADDON_DIR or arg[1]

local mt = {}
local returns = {
    GetText = "", GetVerticalScrollRange = 0, GetVerticalScroll = 0, GetChecked = false,
    GetValue = 0, GetEffectiveScale = 1, GetID = 7, GetWidth = 300, GetHeight = 200,
    GetLeft = 100, GetTop = 700, GetFrameLevel = 1, GetStringWidth = 60,
}
mt.__index = function(t, k)
    if k == "SetScript" then return function(self, n, f) rawset(self, "_s_" .. n, f) end end
    if k == "HookScript" then
        return function(self, n, f)
            local old = rawget(self, "_s_" .. n)
            if old then rawset(self, "_s_" .. n, function(...) old(...) f(...) end)
            else rawset(self, "_s_" .. n, f) end
        end
    end
    if k == "GetScript" then return function(self, n) return rawget(self, "_s_" .. n) end end
    if k == "Show" then
        return function(self)
            local was = rawget(self, "_shown")
            rawset(self, "_shown", true)
            if not was and rawget(self, "_s_OnShow") then self._s_OnShow(self) end
        end
    end
    if k == "Hide" then
        return function(self)
            local was = rawget(self, "_shown")
            rawset(self, "_shown", false)
            if was and rawget(self, "_s_OnHide") then self._s_OnHide(self) end
        end
    end
    if k == "SetShown" then return function(self, v) if v then self:Show() else self:Hide() end end end
    if k == "IsShown" then return function(self) return rawget(self, "_shown") == true end end
    if k == "RegisterEvent" then
        return function(self, e)
            rawset(self, "_ev_" .. e, true)
            if not rawget(self, "_listed") then rawset(self, "_listed", true); frames[#frames + 1] = self end
        end
    end
    if k == "UnregisterEvent" then return function(self, e) rawset(self, "_ev_" .. e, false) end end
    if k == "UnregisterAllEvents" then
        return function(self)
            for key in pairs(self) do
                if type(key) == "string" and key:match("^_ev_") then rawset(self, key, false) end
            end
        end
    end
    if k == "SetText" then return function(self, v) rawset(self, "_text", v) end end
    if k == "GetText" then return function(self) return rawget(self, "_text") or "" end end
    if k == "SetChecked" then return function(self, v) rawset(self, "_checked", v and true or false) end end
    if k == "GetChecked" then return function(self) return rawget(self, "_checked") == true end end
    if k == "GetCenter" then return function() return 960, 540 end end
    if k == "GetColorRGB" then return function() return 1, 0, 0 end end
    if k == "IsMouseOver" then return function(self) return rawget(self, "_mouseOver") == true end end
    if k == "HasFocus" then return function() return false end end
    if k:match("^Create") or k == "GetFontString" or k == "GetThumbTexture"
        or k:match("^Get.*Texture$") then
        return function() return NewObj() end
    end
    if returns[k] ~= nil then local v = returns[k]; return function() return v end end
    return function() end
end
function NewObj() return setmetatable({}, mt) end
function CreateFrame(_, name)
    local f = NewObj()
    f._shown = true
    if name then NAMED[name] = f; rawset(_G, name, f) end
    ALL[#ALL + 1] = f
    return f
end

-- the game's frames and helpers
Minimap = NewObj(); UIParent = NewObj(); GameTooltip = NewObj(); ColorPickerFrame = NewObj()
ColorPickerFrame.SetupColorPickerAndShow = function(_, info) info.swatchFunc(); info.cancelFunc() end
UISpecialFrames = {}
SlashCmdList = {}
SOUNDKIT = { RAID_WARNING = 8959 }
NUM_BAG_SLOTS = 4
function GetCursorPosition() return 0, 0 end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    PRINTED = PRINTED or {}
    PRINTED[#PRINTED + 1] = table.concat(t, " ")
end
SOUNDS_PLAYED = {}
function PlaySound(id) SOUNDS_PLAYED[#SOUNDS_PLAYED + 1] = id end
function ReloadUI() RELOADED = true end
function UnitName() return "Tester" end
function GetRealmName() return "Forever" end
function date(fmt) return "12:00:00" end

-- combat, keys, forms
IN_COMBAT = false
function UnitAffectingCombat() return IN_COMBAT end
function InCombatLockdown() return IN_COMBAT end
CTRL, SHIFT = false, false
function IsControlKeyDown() return CTRL end
function IsShiftKeyDown() return SHIFT end
FORM = 0                   -- the form you're in (index in FORMS, 0 = none)
FORMS = {}                 -- your forms: { spellID, ... }
function GetShapeshiftForm() return FORM end
function GetNumShapeshiftForms() return #FORMS end
function GetShapeshiftFormInfo(i) return 100 + i, i == FORM, true, FORMS[i] end

-- time
NOW = 100
function GetTime() return NOW end

-- items: a trinket (1001) equipped in slot 13 and in bag 0 slot 1
function GetInventoryItemID(_, slot) if slot == 13 then return 1001 end end
function GetInventoryItemTexture() return 555 end
C_Item = {
    GetItemSpell = function(id) if id == 1001 then return "Use" end end,
    GetItemNameByID = function() return "Trinket" end,
    GetItemIconByID = function() return 9 end,
}
C_Container = {
    GetItemCooldown = function() return 0, 0, 1 end,
    GetContainerNumSlots = function() return 2 end,
    GetContainerItemInfo = function(b, s)
        if b == 0 and s == 1 then return { itemID = 1001, itemName = "Trinket", iconFileID = 9 } end
    end,
}

-- spells: the spellbook, base cooldowns (ms), live cooldowns, form overrides
SPELLBOOK = {
    { spellID = 1, name = "Barkskin", tab = "Feral" },
    { spellID = 2, name = "Growl", tab = "Feral" },
    { spellID = 3, name = "Thick Hide", tab = "Feral", isPassive = true },
}
BASE_CD = { [1] = 60000 }
ACTIVE = {}                -- [spellID] = true while on cooldown
OVERRIDES = {}             -- [spellID] = spellID that replaces it right now

local function SpellByName(n)
    for _, s in ipairs(SPELLBOOK) do if s.name == n then return s end end
end
function SpellID(nameOrID)
    if type(nameOrID) == "number" then return nameOrID end
    local s = SpellByName(nameOrID)
    return s and s.spellID
end
local function NameOf(id)
    for _, s in ipairs(SPELLBOOK) do if s.spellID == id then return s.name end end
    return EXTRA_NAMES and EXTRA_NAMES[id]
end
function GetSpellBaseCooldown(id) return BASE_CD[id] or 0 end
function FindSpellOverrideByID(id) return OVERRIDES[id] or id end
Enum = {
    SpellBookSpellBank = { Player = 0 },
    SpellBookItemType = { Spell = 1 },
}
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #SPELLBOOK, name = "Feral" } end,
    GetSpellBookItemInfo = function(i)
        local s = SPELLBOOK[i]
        if not s then return nil end
        return { spellID = s.spellID, name = s.name, iconID = s.spellID, itemType = 1, isPassive = s.isPassive }
    end,
}
C_Spell = {
    GetSpellName = function(x) if type(x) == "number" then return NameOf(x) end return x end,
    GetSpellInfo = function(n) local id = SpellID(n) return id and { spellID = id } end,
    GetSpellTexture = function(x) return 100 + (SpellID(x) or 0) end,
    -- like the client: a name with "(...)" is read as name + rank and finds nothing useful
    GetSpellCooldown = function(k)
        if type(k) == "string" and k:find("%(") then return { isActive = false, isOnGCD = false } end
        local id = SpellID(k)
        return { isActive = ACTIVE[id] == true, isOnGCD = false }   -- times hidden, as in combat
    end,
    IsSpellUsable = function() return true, false end,
}

-- Settings (the game's options): a canvas category
Settings = {
    RegisterCanvasLayoutCategory = function(p) SETTINGS_PAGE = p; return NewObj() end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

---------------------------------------------------------------------------
-- Test helpers
---------------------------------------------------------------------------
local failures = 0
function check(cond, label)
    if cond then
        io.write("  ok   ", label, "\n")
    else
        failures = failures + 1
        io.write("  FAIL ", label, "\n")
    end
end
function Failures() return failures end

-- send a game event to every frame that registered it
function fire(e, ...)
    for _, f in ipairs(frames) do
        if rawget(f, "_ev_" .. e) == true and rawget(f, "_s_OnEvent") then f._s_OnEvent(f, e, ...) end
    end
end

-- move the clock forward, running every shown frame's OnUpdate in 0.1 s steps
function Advance(seconds)
    local steps = math.floor(seconds / 0.1 + 0.5)
    for _ = 1, steps do
        NOW = NOW + 0.1
        for i = 1, #ALL do
            local f = ALL[i]
            local u = rawget(f, "_s_OnUpdate")
            if u and rawget(f, "_shown") then u(f, 0.1) end
        end
    end
end

-- put a spell on cooldown (with the game's event), then after `seconds` take it
-- off again; `quietEnd` leaves out the event at the end
function CooldownFor(name, seconds, quietEnd)
    local id = SpellID(name)
    ACTIVE[id] = true
    fire("SPELL_UPDATE_COOLDOWN")
    Advance(seconds)
    ACTIVE[id] = false
    if not quietEnd then fire("SPELL_UPDATE_COOLDOWN") end
    Advance(0.3)
end

-- record FlashCD.Flash calls: returns the list it fills
function RecordFlashes()
    local list = {}
    local orig = FlashCD.Flash
    FlashCD.Flash = function(key, g, ...)
        list[#list + 1] = key
        return orig(key, g, ...)
    end
    return list
end

-- globals written by the addon (should be only its own)
GLOBAL_WRITES = {}
local MOCK_GLOBALS = { SETTINGS_PAGE = true, PRINTED = true, RELOADED = true }
function CheckOwnGlobals()
    local bad = {}
    for _, k in ipairs(GLOBAL_WRITES) do
        if not (MOCK_GLOBALS[k] or k:match("^FlashCD") or k:match("^SLASH_FLASHCD")) then bad[#bad + 1] = k end
    end
    check(#bad == 0, "only FlashCD's own globals are written" .. (#bad > 0 and (": " .. table.concat(bad, ", ")) or ""))
end
function TrackGlobals()
    local known = {}
    for k in pairs(_G) do known[k] = true end
    setmetatable(_G, { __newindex = function(t, k, v)
        if not known[k] then GLOBAL_WRITES[#GLOBAL_WRITES + 1] = k end
        rawset(t, k, v)
    end })
end

-- load the addon's files in TOC order, then log in
local ns = {}
function LoadAddon()
    local toc = assert(io.open(ADDON_DIR .. "/FlashCD.toc")):read("a")
    for line in toc:gmatch("[^\r\n]+") do
        if line:match("%.lua$") then
            local f = assert(loadfile(ADDON_DIR .. "/" .. line))
            f("FlashCD", ns)
        end
    end
    fire("ADDON_LOADED", "FlashCD")
    fire("PLAYER_ENTERING_WORLD")
    return FlashCD.db
end

-- find frames made by the addon
function FindFrames(pred)
    local out = {}
    for _, f in ipairs(ALL) do if pred(f) then out[#out + 1] = f end end
    return out
end
