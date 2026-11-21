-- FlashCD - Scan.lua
-- Reading the spellbook and the bags: which spells and usable items there are.

local ADDON, ns = ...
local FlashCD = ns.FlashCD

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
