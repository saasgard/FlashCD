-- How often FlashCD asks the game about cooldowns, and that it still sees
-- cooldowns end without an event

for i = 10, 39 do   -- a full spellbook: 30 more spells, half with a cooldown
    SPELLBOOK[#SPELLBOOK + 1] = { spellID = i, name = "Spell " .. i }
    if i % 2 == 0 then BASE_CD[i] = 30000 end
end
local db = LoadAddon()
local fl = RecordFlashes()

local calls = 0
local orig = C_Spell.GetSpellCooldown
C_Spell.GetSpellCooldown = function(...) calls = calls + 1 return orig(...) end

Advance(10)
local idlePerSecond = calls / 10
local watched = 0
for _ in pairs(db.spells) do watched = watched + 1 end
check(idlePerSecond <= watched * 1.6 + 25, string.format(
    "idle: about one full scan a second (%.0f calls/s for %d tracked spells)", idlePerSecond, watched))

-- a cooldown that ends with no event is still noticed within 0.1-1 s
CooldownFor("Spell 10", 30, true)
check(fl[#fl] == "Spell 10", "a cooldown ending without an event still flashes")

-- while one spell is on cooldown, only it is checked often
ACTIVE[SpellID("Spell 12")] = true
fire("SPELL_UPDATE_COOLDOWN")
calls = 0
Advance(2)
-- the old way: every watched spell 10 times a second
local oldWay = idlePerSecond * 10 * 2
check(calls < oldWay / 4, string.format(
    "with one spell on cooldown: %d calls in 2 s (checking everything every 0.1 s would be %d)", calls, oldWay))
ACTIVE[SpellID("Spell 12")] = false
