local ADDON_NAME, GearCheck = ...

-- WotLK 3.3.5a combat rating conversions at level 80
local RATING_PER_PERCENT = {
    hit     = 32.79,    -- hit rating per 1% hit
    crit    = 45.91,    -- crit rating per 1% crit
    haste   = 32.79,    -- haste rating per 1% haste
    expertise = 32.79 / 4, -- expertise rating per 1 expertise (8.20 per point)
    arpen   = 13.99,    -- armor pen rating per 1% ArPen
}

-- Hit caps vs level 83 boss (in percent)
local HIT_CAPS = {
    melee_yellow = 8,     -- special attacks (SS, WF, etc.)
    melee_white  = 28,    -- dual wield auto attacks
    spell        = 17,    -- spell hit cap
}

-- Expertise cap: 26 expertise = 6.50% dodge reduction
local EXPERTISE_CAP = 26

-- Stat keys from GetItemStats
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT        = "str",
    ITEM_MOD_AGILITY_SHORT         = "agi",
    ITEM_MOD_STAMINA_SHORT         = "sta",
    ITEM_MOD_INTELLECT_SHORT       = "int",
    ITEM_MOD_SPIRIT_SHORT          = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT    = "ap",
    ITEM_MOD_SPELL_POWER_SHORT     = "sp",
    ITEM_MOD_HIT_RATING_SHORT      = "hit",
    ITEM_MOD_CRIT_RATING_SHORT     = "crit",
    ITEM_MOD_HASTE_RATING_SHORT    = "haste",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "expertise",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "arpen",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense",
    ITEM_MOD_DODGE_RATING_SHORT    = "dodge",
    ITEM_MOD_PARRY_RATING_SHORT    = "parry",
    ITEM_MOD_BLOCK_RATING_SHORT    = "block",
    ITEM_MOD_RESILIENCE_RATING_SHORT = "resilience",
}

-- Default stat weights (Spellhance Enhancement Shaman)
-- Users can customise via /gc weights
local DEFAULT_WEIGHTS = {
    hit   = 3.50,  -- until spell hit cap, then 0
    sp    = 2.80,
    haste = 2.20,
    crit  = 1.80,
    ap    = 1.00,
    agi   = 1.80,
    str   = 1.10,
    arpen = 0.50,
    int   = 0.40,
    sta   = 0.01,
    spi   = 0.00,
    expertise = 2.50, -- until cap, then 0
}

-- Equip slot mapping: inventory slot ID -> slot name
local SLOT_NAMES = {
    [1]  = "Head",       [2]  = "Neck",       [3]  = "Shoulder",
    [4]  = "Shirt",      [5]  = "Chest",      [6]  = "Waist",
    [7]  = "Legs",       [8]  = "Feet",       [9]  = "Wrist",
    [10] = "Hands",      [11] = "Finger0",    [12] = "Finger1",
    [13] = "Trinket0",   [14] = "Trinket1",   [15] = "Back",
    [16] = "MainHand",   [17] = "OffHand",    [18] = "Ranged",
}

-- Equip location string -> inventory slot IDs
local EQUIP_LOC_TO_SLOT = {
    INVTYPE_HEAD           = { 1 },
    INVTYPE_NECK           = { 2 },
    INVTYPE_SHOULDER       = { 3 },
    INVTYPE_BODY           = { 4 },
    INVTYPE_CHEST          = { 5 },
    INVTYPE_ROBE           = { 5 },
    INVTYPE_WAIST          = { 6 },
    INVTYPE_LEGS           = { 7 },
    INVTYPE_FEET           = { 8 },
    INVTYPE_WRIST          = { 9 },
    INVTYPE_HAND           = { 10 },
    INVTYPE_FINGER         = { 11, 12 },
    INVTYPE_TRINKET        = { 13, 14 },
    INVTYPE_CLOAK          = { 15 },
    INVTYPE_WEAPON         = { 16, 17 },
    INVTYPE_2HWEAPON       = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND  = { 17 },
    INVTYPE_HOLDABLE       = { 17 },
    INVTYPE_SHIELD         = { 17 },
    INVTYPE_RANGED         = { 18 },
    INVTYPE_RANGEDRIGHT    = { 18 },
    INVTYPE_THROWN          = { 18 },
    INVTYPE_RELIC          = { 18 },
}

-- ============================================================
-- Hit Cap Tracking
-- ============================================================

local function GetMeleeHitPercent()
    local bonus = GetCombatRatingBonus(CR_HIT_MELEE)
    local mod = GetHitModifier and GetHitModifier() or 0
    return bonus + mod
end

local function GetSpellHitPercent()
    local bonus = GetCombatRatingBonus(CR_HIT_SPELL)
    local mod = GetSpellHitModifier and GetSpellHitModifier() or 0
    return bonus + mod
end

local function GetPlayerExpertise()
    local exp = GetExpertise()
    return exp or 0
end

local function FormatCapLine(label, current, cap, unit)
    unit = unit or "%%"
    local remaining = cap - current
    if remaining <= 0 then
        return ("|cff20ff20%s: %.1f%s (CAPPED)|r"):format(label, current, unit)
    else
        return ("|cffff8020%s: %.1f / %.0f%s (need %.1f)|r"):format(label, current, cap, unit, remaining)
    end
end

local function AddHitCapLines(tooltip)
    local meleeHit = GetMeleeHitPercent()
    local spellHit = GetSpellHitPercent()
    local expertise = GetPlayerExpertise()

    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffcc00GearCheck|r")
    tooltip:AddLine(FormatCapLine("Spell Hit", spellHit, HIT_CAPS.spell, "%"))
    tooltip:AddLine(FormatCapLine("Melee Hit", meleeHit, HIT_CAPS.melee_yellow, "%"))
    tooltip:AddLine(FormatCapLine("Expertise", expertise, EXPERTISE_CAP, ""))
end

-- ============================================================
-- Item Stat Extraction
-- ============================================================

local function NormalizeStats(itemLink)
    if not itemLink then return nil end
    local raw = {}
    GetItemStats(itemLink, raw)
    local stats = {}
    for key, value in pairs(raw) do
        local short = STAT_KEYS[key]
        if short then
            stats[short] = (stats[short] or 0) + value
        end
    end
    return stats
end

local function GetEquippedStats(slotID)
    local link = GetInventoryItemLink("player", slotID)
    if not link then return {} end
    return NormalizeStats(link) or {}
end

local function GetBestEquippedSlot(slots)
    local bestSlot = slots[1]
    local bestScore = -999999

    local weights = GearCheckDB and GearCheckDB.weights or DEFAULT_WEIGHTS
    for _, slotID in ipairs(slots) do
        local stats = GetEquippedStats(slotID)
        local score = 0
        for stat, value in pairs(stats) do
            score = score + value * (weights[stat] or 0)
        end
        if score < bestScore or bestSlot == slots[1] then
            bestScore = score
            bestSlot = slotID
        end
    end
    return bestSlot
end

-- ============================================================
-- DPS Delta Calculation
-- ============================================================

local function CalcDPSDelta(tooltipStats, equippedStats)
    local weights = GearCheckDB and GearCheckDB.weights or DEFAULT_WEIGHTS
    local delta = 0
    local details = {}

    -- Collect all stat keys
    local allKeys = {}
    for k in pairs(tooltipStats) do allKeys[k] = true end
    for k in pairs(equippedStats) do allKeys[k] = true end

    -- Check if hit/expertise are over cap (reduce weight to 0)
    local activeWeights = {}
    for k, v in pairs(weights) do
        activeWeights[k] = v
    end

    local spellHit = GetSpellHitPercent()
    if spellHit >= HIT_CAPS.spell then
        activeWeights.hit = 0
    end

    local expertise = GetPlayerExpertise()
    if expertise >= EXPERTISE_CAP then
        activeWeights.expertise = 0
    end

    for stat in pairs(allKeys) do
        local newVal = tooltipStats[stat] or 0
        local oldVal = equippedStats[stat] or 0
        local diff = newVal - oldVal
        if diff ~= 0 then
            local w = activeWeights[stat] or 0
            local contribution = diff * w
            delta = delta + contribution
            if w > 0 then
                details[#details + 1] = {
                    stat = stat,
                    diff = diff,
                    contribution = contribution,
                }
            end
        end
    end

    table.sort(details, function(a, b)
        return math.abs(a.contribution) > math.abs(b.contribution)
    end)

    return delta, details
end

-- ============================================================
-- Tooltip Hook
-- ============================================================

local function OnTooltipSetItem(tooltip)
    local _, itemLink = tooltip:GetItem()
    if not itemLink then return end

    -- Get item equip location
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc or equipLoc == "" then
        -- Non-equippable item — just show hit caps on character panel
        return
    end

    local slots = EQUIP_LOC_TO_SLOT[equipLoc]
    if not slots then return end

    -- Get stats for the tooltip item
    local tooltipStats = NormalizeStats(itemLink)
    if not tooltipStats then return end

    -- Find which equipped slot to compare against
    local compareSlot = GetBestEquippedSlot(slots)
    local equippedStats = GetEquippedStats(compareSlot)

    -- Calculate DPS delta
    local delta, details = CalcDPSDelta(tooltipStats, equippedStats)

    -- Add comparison lines
    tooltip:AddLine(" ")
    tooltip:AddLine("|cffffcc00GearCheck|r vs " .. (SLOT_NAMES[compareSlot] or "?"))

    if #details > 0 then
        for _, d in ipairs(details) do
            local sign = d.diff > 0 and "+" or ""
            local color = d.diff > 0 and "|cff20ff20" or "|cffff4040"
            tooltip:AddDoubleLine(
                ("  %s%d %s"):format(sign, d.diff, d.stat),
                ("%s%+.1f DPS|r"):format(color, d.contribution)
            )
        end
    end

    local totalColor = delta >= 0 and "|cff20ff20" or "|cffff4040"
    local arrow = delta >= 0 and "UPGRADE" or "DOWNGRADE"
    tooltip:AddLine(("%s  %s %+.1f DPS|r"):format(totalColor, arrow, delta))

    -- Always show hit caps
    AddHitCapLines(tooltip)

    tooltip:Show()
end

-- ============================================================
-- Character Panel Hit Display
-- ============================================================

local function OnCharacterFrame()
    AddHitCapLines(GameTooltip)
    GameTooltip:Show()
end

-- ============================================================
-- Slash Commands
-- ============================================================

local function PrintWeights()
    local weights = GearCheckDB and GearCheckDB.weights or DEFAULT_WEIGHTS
    print("|cffffcc00GearCheck|r stat weights:")
    local sorted = {}
    for k, v in pairs(weights) do
        sorted[#sorted + 1] = { stat = k, weight = v }
    end
    table.sort(sorted, function(a, b) return a.weight > b.weight end)
    for _, entry in ipairs(sorted) do
        if entry.weight > 0 then
            print(("  %s = %.2f"):format(entry.stat, entry.weight))
        end
    end
end

local function SetWeight(stat, value)
    if not DEFAULT_WEIGHTS[stat] then
        print("|cffffcc00GearCheck|r: Unknown stat '" .. stat .. "'")
        print("  Valid: " .. table.concat((function()
            local keys = {}
            for k in pairs(DEFAULT_WEIGHTS) do keys[#keys + 1] = k end
            table.sort(keys)
            return keys
        end)(), ", "))
        return
    end
    GearCheckDB.weights = GearCheckDB.weights or {}
    for k, v in pairs(DEFAULT_WEIGHTS) do
        if not GearCheckDB.weights[k] then
            GearCheckDB.weights[k] = v
        end
    end
    GearCheckDB.weights[stat] = tonumber(value) or 0
    print("|cffffcc00GearCheck|r: " .. stat .. " = " .. GearCheckDB.weights[stat])
end

local function PrintCaps()
    local meleeHit = GetMeleeHitPercent()
    local spellHit = GetSpellHitPercent()
    local meleeRating = GetCombatRating(CR_HIT_MELEE)
    local spellRating = GetCombatRating(CR_HIT_SPELL)
    local expertise = GetPlayerExpertise()

    print("|cffffcc00GearCheck|r hit caps:")
    print(("  Spell Hit:  %.1f%% / %d%%  (rating: %d, need %d more)"):format(
        spellHit, HIT_CAPS.spell, spellRating,
        math.max(0, math.ceil((HIT_CAPS.spell - spellHit) * RATING_PER_PERCENT.hit))
    ))
    print(("  Melee Hit:  %.1f%% / %d%%  (rating: %d, need %d more)"):format(
        meleeHit, HIT_CAPS.melee_yellow, meleeRating,
        math.max(0, math.ceil((HIT_CAPS.melee_yellow - meleeHit) * RATING_PER_PERCENT.hit))
    ))
    print(("  Expertise:  %d / %d"):format(expertise, EXPERTISE_CAP))
end

SLASH_GEARCHECK1 = "/gearcheck"
SLASH_GEARCHECK2 = "/gc"
SlashCmdList["GEARCHECK"] = function(msg)
    local cmd, arg1, arg2 = msg:match("^(%S+)%s*(%S*)%s*(%S*)")
    cmd = (cmd or ""):lower()

    if cmd == "weights" then
        PrintWeights()
    elseif cmd == "weight" and arg1 ~= "" and arg2 ~= "" then
        SetWeight(arg1:lower(), arg2)
    elseif cmd == "caps" or cmd == "hit" then
        PrintCaps()
    elseif cmd == "reset" then
        GearCheckDB.weights = nil
        print("|cffffcc00GearCheck|r: Weights reset to defaults.")
    else
        print("|cffffcc00GearCheck|r commands:")
        print("  /gc caps — show hit/expertise caps")
        print("  /gc weights — show current stat weights")
        print("  /gc weight <stat> <value> — set a weight")
        print("  /gc reset — reset weights to defaults")
    end
end

-- ============================================================
-- Init
-- ============================================================

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        GearCheckDB = GearCheckDB or {}
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        print("|cffffcc00GearCheck|r loaded. /gc for commands.")
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
